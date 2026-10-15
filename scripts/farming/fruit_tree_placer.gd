extends Node3D

## Инструмент размещения саженцев фруктовых деревьев мышкой.
## Активируется из инвентаря по кнопке «🌱 Посадить в саду» при выборе саженца.
## Проверяет пригодность грунта, отсутствие коллизий и радиус от персонажа.

const FruitTree = preload("res://scripts/resources/fruit_tree.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const BLOCKER_GROUP: String = "ui_input_blockers"
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

signal finished(tree: Node)
signal cancelled

var world: Node
var player: Node
var sapling_id: String = "apple_sapling"
var tree_type: String = "apple_tree"
var hover_pos: Vector3 = Vector3.ZERO
var has_hover: bool = false

var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _label: Label3D
var _hint_layer: CanvasLayer
var _hint: Label

func setup(p_world: Node, p_player: Node, p_sapling_id: String = "apple_sapling") -> void:
	world = p_world
	player = p_player
	sapling_id = p_sapling_id
	var d: Dictionary = ItemDB.get_item(sapling_id)
	tree_type = str(d.get("tree_type", "apple_tree"))

func _ready() -> void:
	add_to_group(BLOCKER_GROUP)

	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(0.3, 0.9, 0.3, 0.45)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.6
	cyl.height = 1.6
	_ghost.mesh = cyl
	_ghost.position.y = 0.8
	_ghost.material_override = _ghost_mat
	add_child(_ghost)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	_label.font_size = 36
	_label.outline_size = 8
	_label.position.y = 1.9
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

	_hint = Label.new()
	_hint.text = "🌱 Посадка саженца: ЛКМ — посадить, ПКМ / Esc — отмена"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.9, 0.95, 0.85))
	panel.add_child(_hint)

	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-220, -70)
	_hint_layer.add_child(panel)

func _exit_tree() -> void:
	if _hint_layer and is_instance_valid(_hint_layer):
		_hint_layer.queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_from_mouse((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_hover_from_mouse(mb.position)
			if mb.pressed:
				place()
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
	var target: Vector3 = from + dir * t
	hover_pos = Vector3(snappedf(target.x, 0.25), 0.0, snappedf(target.z, 0.25))
	has_hover = true
	_update_ghost()

func check_placement(p_world: Node, pos: Vector3) -> String:
	if player:
		var dist: float = pos.distance_to(player.global_position)
		if dist > 10.0:
			return "Слишком далеко от персонажа."
		if dist < 1.0:
			return "Слишком близко к персонажу."

	var tree := p_world.get_tree() if p_world and p_world.is_inside_tree() else null
	if tree:
		# Проверка расстояния до других фруктовых деревьев
		for t in tree.get_nodes_in_group(FruitTree.GROUP):
			if not t.is_queued_for_deletion():
				if pos.distance_to(t.global_position) < 2.5:
					return "Слишком близко к другому фруктовому дереву (мин. 2.5 м)."

		# Проверка делянок
		for f in tree.get_nodes_in_group("farm_fields"):
			if not f.is_queued_for_deletion() and f.has_method("get_rect"):
				var rect: Rect2 = f.get_rect()
				if rect.grow(1.2).has_point(Vector2(pos.x, pos.z)):
					return "Мешает грядка / делянка."

		# Проверка ягодных кустов
		for b in tree.get_nodes_in_group("berry_bushes"):
			if not b.is_queued_for_deletion():
				if pos.distance_to(b.global_position) < 1.8:
					return "Мешает ягодный куст."

	# Проверка маски MeadowDecor
	if p_world:
		var decor = p_world.get_node_or_null("MeadowDecor")
		if decor and decor.has_method("get_mask_at"):
			var mask: int = decor.get_mask_at(Vector2(pos.x, pos.z))
			if mask & MeadowDecor.NO_PROPS:
				return "Место занято объектом мира (постройка, скала, озеро)."

	return ""

func _update_ghost() -> void:
	if not has_hover:
		return
	global_position = hover_pos
	var err: String = check_placement(world, hover_pos)
	var ok: bool = err == ""
	_ghost_mat.albedo_color = Color(0.3, 0.9, 0.3, 0.45) if ok else Color(1.0, 0.3, 0.25, 0.55)
	_label.text = ItemDB.get_item_name(sapling_id) + ("\n✓ Место подходит" if ok else "\n✕ " + err)
	_label.modulate = Color(1.0, 1.0, 1.0) if ok else Color(1.0, 0.6, 0.6)

func place() -> bool:
	if not has_hover:
		return false
	var err: String = check_placement(world, hover_pos)
	if err != "":
		AudioManager.play("ui_error")
		_notify(err)
		return false

	var inv = player.get("inventory") if player and "inventory" in player else null
	if inv:
		if inv.get_item_count(sapling_id) <= 0:
			_notify("У вас нет саженца %s!" % ItemDB.get_item_name(sapling_id))
			cancel()
			return false
		inv.remove_item(sapling_id, 1)

	var tree = FruitTree.new()
	tree.tree_type = tree_type
	tree.stage = FruitTree.Stage.SAPLING
	tree.has_fruit = false
	tree.position = hover_pos

	var container = world.get_node_or_null("FruitTrees") if world else null
	if container:
		container.add_child(tree)
	elif world:
		world.add_child(tree)

	AudioManager.play("plant")
	var skills: Object = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("add_xp"):
		skills.add_xp("orchard", 25)
	_notify("🌱 Саженец успешно посажен в саду!")
	finished.emit(tree)
	queue_free()
	return true

func cancel() -> void:
	cancelled.emit()
	queue_free()

func _notify(text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)
