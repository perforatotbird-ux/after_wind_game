extends Node3D

## Размещение делянки мышкой (открывается кнопкой «Делянка» в рюкзаке).
## Курсор показывает клетку под мышью; зажать ЛКМ и тянуть — растянуть делянку
## до нужного размера (не больше FarmField.MAX_CELLS клеток), отпустить — поставить.
## ПКМ или Esc — отмена. Красный контур — место занято (здания, станки, жилы, камни,
## деревья, вода, другие делянки, ягодные кусты) или делянка вышла за край карты.
## Пока идёт размещение, удары и взаимодействие персонажа выключены (группа
## ui_input_blockers), ходить и крутить камеру можно.

const FarmField = preload("res://scripts/farming/farm_field.gd")
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const BLOCKER_GROUP: String = "ui_input_blockers"
const CONTAINER_NAME: String = "FarmFields"
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

signal finished(field: Node)
signal cancelled

var world: Node
var player: Node
var hover_cell: Vector2i = Vector2i.ZERO
var anchor_cell: Vector2i = Vector2i.ZERO
var dragging: bool = false
var has_hover: bool = false

var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _label: Label3D
var _hint_layer: CanvasLayer
var _hint: Label
var _last_rect_key: String = ""

func setup(p_world: Node, p_player: Node) -> void:
	world = p_world
	player = p_player

func _ready() -> void:
	add_to_group(BLOCKER_GROUP)
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.vertex_color_use_as_albedo = true
	_ghost.material_override = _ghost_mat
	add_child(_ghost)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 10
	add_child(_label)
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 50
	add_child(_hint_layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.08, 0.82)
	sb.border_color = Color(0.55, 0.8, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_top = 150
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint = Label.new()
	_hint.text = "🌾 Делянка: зажмите ЛКМ и растяните по земле, отпустите — поставить.\nПКМ / Esc — отмена. Не больше %d клеток." % FarmField.MAX_CELLS
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_hint)
	_hint_layer.add_child(panel)
	if player is Node3D:
		set_hover_world((player as Node3D).global_position + Vector3(0, 0, 2))

## Прямоугольник в клетках: позиция (угол) и размер. Размер ограничен MAX_CELLS.
func get_cell_rect() -> Rect2i:
	var a: Vector2i = anchor_cell if dragging else hover_cell
	var b: Vector2i = hover_cell
	var w: int = absi(b.x - a.x) + 1
	var h: int = absi(b.y - a.y) + 1
	if w * h > FarmField.MAX_CELLS:
		if w >= h:
			h = maxi(1, FarmField.MAX_CELLS / w)
			if w > FarmField.MAX_CELLS:
				w = FarmField.MAX_CELLS
		else:
			w = maxi(1, FarmField.MAX_CELLS / h)
			if h > FarmField.MAX_CELLS:
				h = FarmField.MAX_CELLS
	var x0: int = a.x if b.x >= a.x else a.x - w + 1
	var z0: int = a.y if b.y >= a.y else a.y - h + 1
	return Rect2i(x0, z0, w, h)

func set_hover_world(p: Vector3) -> void:
	hover_cell = Vector2i(floori(p.x), floori(p.z))
	has_hover = true
	_update_ghost()

func begin_drag() -> void:
	anchor_cell = hover_cell
	dragging = true
	_update_ghost()

## Отпускание ЛКМ: ставит делянку, если место свободно.
func end_drag() -> Node:
	if not dragging:
		begin_drag()
	var r := get_cell_rect()
	dragging = false
	var err := check_rect(world, Rect2(r.position, r.size))
	if err != "":
		AudioManager.play("ui_error")
		_notify("⛔ " + err)
		_update_ghost()
		return null
	var field := place(r)
	finished.emit(field)
	queue_free()
	return field

func place(r: Rect2i) -> Node:
	var container: Node = world.get_node_or_null(CONTAINER_NAME)
	if container == null:
		container = Node3D.new()
		container.name = CONTAINER_NAME
		world.add_child(container)
	var field = FarmField.spawn(container, Vector3(r.position.x, 0.0, r.position.y), r.size.x, r.size.y)
	AudioManager.play("build", 1.15, -4.0)
	var cost := FarmField.cost_for(r.size.x, r.size.y)
	var parts: PackedStringArray = []
	for id in cost:
		parts.append("%s ×%d" % [ItemDB.get_item_name(id), cost[id]])
	_notify("📐 Делянка %d×%d размечена. Принесите: %s (E у разметки)." % [r.size.x, r.size.y, ", ".join(parts)])
	return field

func cancel() -> void:
	_notify("Размещение делянки отменено.")
	cancelled.emit()
	queue_free()

## Пустая строка — место подходит; иначе причина отказа.
static func check_rect(p_world: Node, rect: Rect2) -> String:
	var n: int = int(rect.size.x) * int(rect.size.y)
	if n < 1:
		return "Слишком маленькая делянка."
	if n > FarmField.MAX_CELLS:
		return "Делянка больше %d клеток." % FarmField.MAX_CELLS
	if p_world == null:
		return ""
	var decor: Node = null
	for c in p_world.get_children():
		if c.get_script() == MeadowDecor:
			decor = c
	if decor:
		var half: Vector2 = decor.area_size * 0.5 - Vector2(1.0, 1.0)
		if rect.position.x < -half.x or rect.position.y < -half.y or rect.end.x > half.x or rect.end.y > half.y:
			return "Делянка выходит за край карты."
		if not decor.mask.is_empty():
			var steps_x: int = int(rect.size.x * 2.0)
			var steps_z: int = int(rect.size.y * 2.0)
			for iz in steps_z + 1:
				for ix in steps_x + 1:
					var p := Vector2(rect.position.x + ix * 0.5, rect.position.y + iz * 0.5)
					p.x = clampf(p.x, rect.position.x + 0.05, rect.end.x - 0.05)
					p.y = clampf(p.y, rect.position.y + 0.05, rect.end.y - 0.05)
					if decor.get_mask_at(p) & MeadowDecor.NO_PROPS:
						return "Место занято (постройка, камень, дерево или жила)."
	# Интерактивные объекты вне маски (торговец, доска заказов и т.п.) — с запасом под табличку.
	for a in p_world.find_children("*", "Area3D", true, false):
		if a.is_in_group(FarmField.GROUP) or a.is_in_group("berry_bushes") or not a.has_method("get_prompt"):
			continue
		if a.get("resource_id") != null or a.has_method("get_footprint_rect"):
			continue
		var ap := Vector2(a.global_position.x, a.global_position.z)
		if rect.grow(0.7).has_point(ap):
			return "Мешает: %s." % str(a.get("object_name") if a.get("object_name") != null else a.name)
	var tree := p_world.get_tree() if p_world.is_inside_tree() else null
	if tree:
		for f in tree.get_nodes_in_group(FarmField.GROUP):
			if not f.is_queued_for_deletion() and (f.get_rect() as Rect2).grow(0.3).intersects(rect):
				return "Здесь уже есть другая делянка."
		for b in tree.get_nodes_in_group("berry_bushes"):
			var bp := Vector2(b.global_position.x, b.global_position.z)
			if rect.grow(0.8).has_point(bp):
				return "Мешает ягодный куст."
	return ""

func _update_ghost() -> void:
	var r := get_cell_rect()
	var rect := Rect2(r.position, r.size)
	var err := check_rect(world, rect)
	var ok: bool = err == ""
	var key := "%s|%s|%s" % [r, ok, dragging]
	if key == _last_rect_key:
		return
	_last_rect_key = key
	var col: Color = Color(0.45, 1.0, 0.45) if ok else Color(1.0, 0.35, 0.3)
	_ghost.mesh = _ghost_mesh(r.size.x, r.size.y, col)
	_ghost.position = Vector3(r.position.x, 0.0, r.position.y)
	var cost := FarmField.cost_for(r.size.x, r.size.y)
	var cost_txt: PackedStringArray = []
	for id in cost:
		cost_txt.append("%s %d" % [ItemDB.get_item_name(id), cost[id]])
	_label.text = "%d × %d = %d клет.\n%s%s" % [r.size.x, r.size.y, r.size.x * r.size.y, ", ".join(cost_txt), "" if ok else "\n" + err]
	_label.modulate = Color(1, 1, 1) if ok else Color(1.0, 0.6, 0.55)
	_label.position = Vector3(r.position.x + r.size.x * 0.5, 1.4, r.position.y + r.size.y * 0.5)

## Полупрозрачная заливка с сеткой клеток и рамкой.
static func _ghost_mesh(w: int, h: int, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y: float = 0.06
	var fill := Color(col.r, col.g, col.b, 0.22)
	var line := Color(col.r, col.g, col.b, 0.9)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, cc: Color) -> void:
		for v in [a, b, c, a, c, d]:
			st.set_color(cc)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	quad.call(Vector3(0, y, 0), Vector3(0, y, h), Vector3(w, y, h), Vector3(w, y, 0), fill)
	var t: float = 0.03
	for x in w + 1:
		var tt: float = t * (2.0 if x == 0 or x == w else 1.0)
		quad.call(Vector3(x - tt, y + 0.01, 0), Vector3(x - tt, y + 0.01, h), Vector3(x + tt, y + 0.01, h), Vector3(x + tt, y + 0.01, 0), line)
	for z in h + 1:
		var tt2: float = t * (2.0 if z == 0 or z == h else 1.0)
		quad.call(Vector3(0, y + 0.01, z - tt2), Vector3(0, y + 0.01, z + tt2), Vector3(w, y + 0.01, z + tt2), Vector3(w, y + 0.01, z - tt2), line)
	return st.commit()

func _notify(text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)

# --- Ввод -----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_from_mouse((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_hover_from_mouse(mb.position)
			if mb.pressed:
				begin_drag()
			else:
				end_drag()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			get_viewport().set_input_as_handled()
			cancel()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancel()

func _hover_from_mouse(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4:
		return
	var t: float = -from.y / dir.y
	if t <= 0.0:
		return
	set_hover_world(from + dir * t)
