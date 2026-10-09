extends GridContainer

## Сетка клеток инвентаря: каждая клетка — иконка предмета и количество в стеке,
## пустые слоты рюкзака показаны тёмными. Подсказка: название, количество, вес.
## Используется окном рюкзака и окном станка. Клетки переиспользуются.

signal cell_pressed(item_id: String, count: int, index: int)
signal cell_right_clicked(item_id: String, count: int, index: int)

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")

var cell_size: Vector2 = Vector2(64, 64)
## Выделенный предмет (золотая рамка).
var selected_item: String = ""
## Подсветка предметов { item_id: Color } (например, сырьё выбранного рецепта).
var highlight_items: Dictionary = {}

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

func get_stack(index: int) -> Dictionary:
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
	icon.offset_left = 7
	icon.offset_top = 5
	icon.offset_right = -7
	icon.offset_bottom = -9
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var lbl := Label.new()
	lbl.name = "Count"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_right = -5
	lbl.offset_bottom = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UI.COLOR_TEXT)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(lbl)
	b.pressed.connect(_on_cell_pressed.bind(index))
	b.gui_input.connect(_on_cell_gui_input.bind(index))
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
		_apply_style(cell, UI.COLOR_CARD_EMPTY, Color(0.25, 0.28, 0.32, 0.5), 1)
		return
	icon.texture = ItemIcons.get_texture(item_id)
	lbl.text = str(count)
	var w: float = float(ItemDB.get_item(item_id).get("weight", 1.0))
	cell.tooltip_text = "%s %s\nКоличество: %d\nВес: %.1f кг (%.2f кг/шт.)" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), count, w * count, w]
	var bg: Color = ItemIcons.get_color(item_id).darkened(0.7)
	bg.a = 0.95
	if item_id == selected_item:
		_apply_style(cell, bg.lightened(0.1), UI.COLOR_ACCENT, 2)
	elif highlight_items.has(item_id):
		_apply_style(cell, bg, highlight_items[item_id], 2)
	else:
		_apply_style(cell, bg, UI.COLOR_BORDER, 1)

func _apply_style(cell: Button, bg: Color, border: Color, width: int) -> void:
	cell.add_theme_stylebox_override("normal", UI.make_stylebox(bg, border, width))
	cell.add_theme_stylebox_override("hover", UI.make_stylebox(bg.lightened(0.12), UI.COLOR_ACCENT, maxi(width, 1)))
	cell.add_theme_stylebox_override("pressed", UI.make_stylebox(bg.lightened(0.2), UI.COLOR_ACCENT, 2))
	cell.add_theme_stylebox_override("disabled", UI.make_stylebox(bg, border, width))

func _on_cell_pressed(index: int) -> void:
	var s: Dictionary = get_stack(index)
	if s.is_empty():
		return
	cell_pressed.emit(str(s["item_id"]), int(s["count"]), index)

func _on_cell_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var s: Dictionary = get_stack(index)
		if not s.is_empty():
			cell_right_clicked.emit(str(s["item_id"]), int(s["count"]), index)
		accept_event()
