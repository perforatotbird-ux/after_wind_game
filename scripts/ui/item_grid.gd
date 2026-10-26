extends GridContainer

## Сетка клеток инвентаря в стиле Industrial Survival: тёмный графит,
## аккуратные контуры, сдержанный янтарный акцент выделения, иконка предмета
## и количество в стеке. Пустые слоты показаны темными углубленными ячейками.
## Используется окном рюкзака, станка, генератора и склада.

signal cell_pressed(item_id: String, count: int, index: int)
signal cell_right_clicked(item_id: String, count: int, index: int)
## Двойной клик по клетке (использовать: съесть / выпить / открыть меню).
signal cell_activated(item_id: String, count: int, index: int)
## Стек перетащен мышью из клетки from_index в клетку to_index.
signal cell_moved(from_index: int, to_index: int)

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")

var cell_size: Vector2 = Vector2(62, 62)
## Выделенный предмет (янтарная рамка).
var selected_item: String = ""
## Подсветка предметов { item_id: Color } (например, сырьё выбранного рецепта).
var highlight_items: Dictionary = {}
## Разрешить перетаскивание стеков между клетками (окно рюкзака).
var drag_enabled: bool = false
## Тип данных drag-and-drop клетки (принимает и окно рюкзака: «выбросить»).
const DRAG_TYPE: String = "inventory_cell"

var _cells: Array[Button] = []
var _stacks: Array = []

func _init() -> void:
	columns = 6
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)

## stacks — массив { item_id, count }; total_cells — сколько клеток показать
## (лишние — пустые). Если стеков больше, показываются все.
func set_stacks(stacks: Array, total_cells: int = -1) -> void:
	_stacks = stacks.duplicate()
	var n: int = maxi(stacks.size(), total_cells)
	while _cells.size() < n:
		_cells.append(_make_cell(_cells.size()))
	for i in range(_cells.size()):
		var cell: Button = _cells[i]
		cell.visible = i < n
		if i < n:
			_fill_cell(cell, stacks[i] if i < stacks.size() else {})

## Не называть get_stack(): это встроенная функция GDScript (стек вызовов),
## и вызов get_stack(index) не компилируется — весь рюкзак оставался пустым.
func get_cell_stack(index: int) -> Dictionary:
	if index < 0 or index >= _stacks.size():
		return {}
	return _stacks[index]

func get_visible_cell_count() -> int:
	var n: int = 0
	for c in _cells:
		if c.visible:
			n += 1
	return n

func _make_cell(index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = cell_size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)

	var lbl := Label.new()
	lbl.name = "Count"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_right = -4
	lbl.offset_bottom = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.07, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(lbl)

	b.pressed.connect(_on_cell_pressed.bind(index))
	b.gui_input.connect(_on_cell_gui_input.bind(index))
	b.set_drag_forwarding(_get_cell_drag_data.bind(index), _can_drop_on_cell.bind(index), _drop_on_cell.bind(index))
	add_child(b)
	return b

func _fill_cell(cell: Button, stack: Dictionary) -> void:
	var icon: TextureRect = cell.get_node("Icon")
	var lbl: Label = cell.get_node("Count")
	var item_id: String = str(stack.get("item_id", ""))
	var count: int = int(stack.get("count", 0))

	if item_id.is_empty() or count <= 0:
		icon.texture = null
		lbl.text = ""
		cell.tooltip_text = "Пустой слот"
		_apply_style(cell, UI.COLOR_GRAPHITE_INSET, UI.COLOR_BORDER_SUBTLE, 1, 4)
		return

	icon.texture = ItemIcons.get_texture(item_id)
	lbl.text = str(count) if count > 1 else ""
	var item_data: Dictionary = ItemDB.get_item(item_id)
	var w: float = float(item_data.get("weight", 1.0))
	var cat: String = str(item_data.get("category", ""))
	cell.tooltip_text = "%s %s\nКоличество: %d\nВес: %.1f кг (%.2f кг/шт.)" % [
		ItemDB.get_item_icon(item_id),
		ItemDB.get_item_name(item_id),
		count,
		w * count,
		w
	]

	# Сдержанный графитовый фон слота с деликатным тоновым оттенком предмета
	var item_color: Color = ItemIcons.get_color(item_id)
	var base_bg: Color = UI.COLOR_GRAPHITE_SURFACE.lerp(item_color.darkened(0.75), 0.15)
	base_bg.a = 0.96

	if item_id == selected_item:
		_apply_style(cell, base_bg.lightened(0.12), UI.COLOR_ACCENT, 2, 4)
	elif highlight_items.has(item_id):
		_apply_style(cell, base_bg, highlight_items[item_id], 2, 4)
	else:
		_apply_style(cell, base_bg, UI.COLOR_BORDER, 1, 4)

func _apply_style(cell: Button, bg: Color, border: Color, width: int, radius: int = 4) -> void:
	cell.add_theme_stylebox_override("normal", UI.make_stylebox(bg, border, width, radius))
	var hover_border: Color = UI.COLOR_ACCENT if border == UI.COLOR_ACCENT else UI.COLOR_BORDER_STRONG
	cell.add_theme_stylebox_override("hover", UI.make_stylebox(bg.lightened(0.10), hover_border, maxi(width, 1), radius))
	cell.add_theme_stylebox_override("pressed", UI.make_stylebox(bg.lightened(0.18), UI.COLOR_ACCENT, 2, radius))
	cell.add_theme_stylebox_override("disabled", UI.make_stylebox(bg, border, width, radius))

func _on_cell_pressed(index: int) -> void:
	var s: Dictionary = get_cell_stack(index)
	if s.is_empty():
		return
	cell_pressed.emit(str(s["item_id"]), int(s["count"]), index)

func _on_cell_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		var st: Dictionary = get_cell_stack(index)
		if not st.is_empty():
			cell_activated.emit(str(st["item_id"]), int(st["count"]), index)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var s: Dictionary = get_cell_stack(index)
		if not s.is_empty():
			cell_right_clicked.emit(str(s["item_id"]), int(s["count"]), index)
		accept_event()

# --- Перетаскивание (drag-and-drop) ---

func _get_cell_drag_data(_at: Vector2, index: int) -> Variant:
	if not drag_enabled:
		return null
	var st: Dictionary = get_cell_stack(index)
	if st.is_empty() or str(st.get("item_id", "")) == "":
		return null

	var holder := Control.new()
	var bg_panel := Panel.new()
	bg_panel.custom_minimum_size = cell_size
	bg_panel.size = cell_size
	bg_panel.position = -cell_size * 0.5
	bg_panel.add_theme_stylebox_override("panel", UI.make_stylebox(Color(0.14, 0.17, 0.22, 0.90), UI.COLOR_ACCENT, 2, 4))
	holder.add_child(bg_panel)

	var preview := TextureRect.new()
	preview.texture = ItemIcons.get_texture(str(st["item_id"]))
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	preview.custom_minimum_size = cell_size - Vector2(12, 12)
	preview.size = preview.custom_minimum_size
	preview.position = -preview.size * 0.5
	holder.add_child(preview)

	if _cells[index].get_viewport() and _cells[index].get_viewport().gui_is_dragging():
		_cells[index].set_drag_preview(holder)
	else:
		holder.free() # вызов вне реального перетаскивания (тесты)
	return {"type": DRAG_TYPE, "grid": self, "index": index, "item_id": str(st["item_id"]), "count": int(st["count"])}

func _can_drop_on_cell(_at: Vector2, data: Variant, _index: int) -> bool:
	return drag_enabled and data is Dictionary and data.get("type", "") == DRAG_TYPE and data.get("grid") == self

func _drop_on_cell(_at: Vector2, data: Variant, index: int) -> void:
	var from: int = int(data.get("index", -1))
	if from != index and from >= 0:
		cell_moved.emit(from, index)
