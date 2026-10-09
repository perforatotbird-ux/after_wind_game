extends Control

## Окно рюкзака (TAB / I / слот 5): клеточная сетка стеков, вес и слоты, пояс
## инструментов, карточка выбранного предмета и выбрасывание на землю.
## ЛКМ — выбрать, ПКМ — сразу «Выбросить…», ESC / TAB / I — закрыть.
## Создаётся и уничтожается GameplayUIController.

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const QuantityDialog = preload("res://scripts/ui/quantity_dialog.gd")
const DroppedItem = preload("res://scripts/inventory/dropped_item.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const DRINK_ITEMS: Array[String] = ["clean_water", "bottled_water"]

var player: Node
var inventory: Node

var _grid: GridContainer
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _weight_label: Label
var _slots_label: Label
var _credits_label: Label
var _belt: HBoxContainer
var _d_icon: TextureRect
var _d_name: Label
var _d_desc: Label
var _d_count: Label
var _d_weight: Label
var _use_btn: Button
var _drop_btn: Button
var _selected: String = ""
var _modal: Control
var _closing: bool = false

func setup(p_player: Node) -> void:
	player = p_player
	inventory = player.inventory if player and "inventory" in player else null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Затемнение вокруг окна: перетащить стек сюда (за окно) = выбросить на землю.
	var overlay := UI.make_overlay()
	overlay.set_drag_forwarding(Callable(), _can_drop_outside, _drop_outside)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(880, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	
	# Заголовок
	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(UI.make_label("🎒 Рюкзак", 20, UI.COLOR_TITLE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	_credits_label = UI.make_label("", 15, UI.COLOR_ACCENT)
	header.add_child(_credits_label)
	var sort_btn := UI.make_button("⇅ Сортировать", Vector2(130, 32))
	sort_btn.tooltip_text = "Упорядочить рюкзак по типу и названию"
	sort_btn.pressed.connect(_on_sort_pressed)
	header.add_child(sort_btn)
	var close_btn := UI.make_button("✕", Vector2(40, 32))
	close_btn.tooltip_text = "Закрыть (ESC)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	# Вес и слоты
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 12)
	root.add_child(load_row)
	_weight_label = UI.make_label("", 14)
	_weight_label.custom_minimum_size = Vector2(230, 0)
	load_row.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(0, 14)
	_weight_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weight_bar.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_CARD_EMPTY, UI.COLOR_BORDER, 1, 4))
	_weight_fill = UI.make_stylebox(UI.COLOR_OK, Color(0, 0, 0, 0), 0, 4)
	_weight_bar.add_theme_stylebox_override("fill", _weight_fill)
	load_row.add_child(_weight_bar)
	_slots_label = UI.make_label("", 14, UI.COLOR_MUTED)
	load_row.add_child(_slots_label)
	
	# Пояс инструментов
	root.add_child(UI.make_section_header("🛠 Пояс — клик берёт инструмент в руки (колесо мыши в игре делает то же)"))
	_belt = HBoxContainer.new()
	_belt.add_theme_constant_override("separation", 6)
	root.add_child(_belt)
	
	# Сетка + карточка предмета
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	var left := VBoxContainer.new()
	body.add_child(left)
	left.add_child(UI.make_section_header("📦 Предметы"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(6 * 70 + 16, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_grid = ItemGrid.new()
	_grid.columns = 6
	scroll.add_child(_grid)
	_grid.drag_enabled = true
	_grid.cell_pressed.connect(_on_cell_pressed)
	_grid.cell_right_clicked.connect(_on_cell_right_clicked)
	_grid.cell_moved.connect(_on_cell_moved)
	_grid.cell_activated.connect(_on_cell_activated)
	
	var card := UI.make_panel(UI.COLOR_CARD, UI.COLOR_BORDER, 1)
	card.custom_minimum_size = Vector2(300, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var cm := UI.make_margin(14)
	card.add_child(cm)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	cm.add_child(details)
	_d_icon = TextureRect.new()
	_d_icon.custom_minimum_size = Vector2(96, 96)
	_d_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_d_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	details.add_child(_d_icon)
	_d_name = UI.make_label("", 17, UI.COLOR_TITLE)
	details.add_child(_d_name)
	_d_desc = UI.make_label("", 13, UI.COLOR_MUTED)
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.custom_minimum_size = Vector2(270, 0)
	details.add_child(_d_desc)
	_d_count = UI.make_label("", 14)
	details.add_child(_d_count)
	_d_weight = UI.make_label("", 14)
	details.add_child(_d_weight)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(fill)
	_use_btn = UI.make_button("", Vector2(0, 36), true)
	_use_btn.pressed.connect(_on_use_pressed)
	details.add_child(_use_btn)
	_drop_btn = UI.make_button("🫳 Выбросить…", Vector2(0, 36), false, true)
	_drop_btn.pressed.connect(func(): _open_drop_dialog(_selected))
	details.add_child(_drop_btn)
	
	root.add_child(UI.make_label("ЛКМ — выбрать · перетащить — переложить · двойной клик — съесть/выпить · ПКМ или перетащить за окно — выбросить · ESC / TAB / I — закрыть", 12, UI.COLOR_DIM))
	
	if inventory:
		inventory.inventory_updated.connect(_refresh)
		inventory.tool_changed.connect(_on_tool_changed)
		inventory.credits_changed.connect(_on_credits_changed)
	_refresh()

func _on_tool_changed(_id: String, _name: String) -> void:
	_refresh()

func _on_credits_changed(_total: int) -> void:
	_refresh()

func _refresh() -> void:
	if inventory == null or not is_inside_tree():
		return
	if _selected != "" and inventory.get_item_count(_selected) <= 0:
		_selected = ""
	_grid.selected_item = _selected
	_grid.set_stacks(inventory.get_slot_cells(), inventory.max_slots)
	var total: float = inventory.get_total_weight()
	var limit: float = inventory.max_weight
	_weight_label.text = "⚖️ Вес: %.1f / %.0f кг" % [total, limit]
	_weight_bar.max_value = maxf(1.0, limit * inventory.OVERLOAD_CRITICAL_RATIO)
	_weight_bar.value = minf(total, _weight_bar.max_value)
	var state: int = inventory.get_load_state()
	_weight_fill.bg_color = UI.COLOR_OK if state == 0 else (UI.COLOR_ACCENT if state == 1 else UI.COLOR_DANGER)
	if state == 1:
		_weight_label.text += "  — перегруз"
	elif state == 2:
		_weight_label.text += "  — не могу идти!"
	_slots_label.text = "Слоты: %d / %d" % [inventory.get_used_slots(), inventory.max_slots]
	_credits_label.text = "💰 %d кр.   " % int(inventory.credits)
	_build_belt()
	_update_details()

func _build_belt() -> void:
	for c in _belt.get_children():
		c.queue_free()
	for i in range(inventory.tools.size()):
		var t: String = inventory.tools[i]
		var is_pack: bool = t == "backpack" or ItemDB.get_item(t).get("tool_type", "") == "backpack"
		var b := UI.make_button("", Vector2(60, 60), t == inventory.equipped_tool)
		b.icon = ItemIcons.get_texture(t)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var d: Dictionary = ItemDB.get_item(t)
		b.tooltip_text = "[%d] %s (ур. %d)%s" % [i + 1, ItemDB.get_item_name(t), int(d.get("level", 1)), "\nСлоты: %d" % inventory.max_slots if is_pack else ("\nВ руках" if t == inventory.equipped_tool else "")]
		if not is_pack:
			b.pressed.connect(_on_belt_pressed.bind(t))
		_belt.add_child(b)

func _on_belt_pressed(tool_id: String) -> void:
	AudioManager.play("ui_click")
	inventory.equip_tool(tool_id)

func _update_details() -> void:
	if _selected == "":
		_d_icon.texture = null
		_d_name.text = "Выберите предмет"
		_d_desc.text = "Нажмите на клетку, чтобы увидеть описание, количество и вес."
		_d_count.text = ""
		_d_weight.text = ""
		_use_btn.visible = false
		_drop_btn.visible = false
		return
	var data: Dictionary = ItemDB.get_item(_selected)
	var count: int = inventory.get_item_count(_selected)
	var w: float = inventory.get_item_weight(_selected)
	_d_icon.texture = ItemIcons.get_texture(_selected)
	_d_name.text = "%s %s" % [ItemDB.get_item_icon(_selected), ItemDB.get_item_name(_selected)]
	_d_desc.text = str(data.get("description", ""))
	_d_count.text = "Количество: %d  (стек до %d, слотов: %d)" % [count, inventory.get_max_stack(_selected), inventory.get_slots_for(_selected, count)]
	_d_weight.text = "Вес: %.1f кг  (%.2f кг/шт.)" % [w * count, w]
	_drop_btn.visible = true
	if _selected in DRINK_ITEMS:
		_use_btn.text = "💧 Выпить (U)"
		_use_btn.visible = true
	elif str(data.get("category", "")) == "food":
		_use_btn.text = "🍞 Съесть (Y)"
		_use_btn.visible = true
	else:
		_use_btn.visible = false

func _on_cell_pressed(item_id: String, _count: int, _index: int) -> void:
	AudioManager.play("ui_click")
	_selected = item_id
	_refresh()

func _on_cell_moved(from_index: int, to_index: int) -> void:
	if inventory and inventory.move_slot(from_index, to_index):
		AudioManager.play("ui_click")

func _on_cell_activated(item_id: String, _count: int, _index: int) -> void:
	_selected = item_id
	var data: Dictionary = ItemDB.get_item(item_id)
	if item_id in DRINK_ITEMS or str(data.get("category", "")) == "food":
		_on_use_pressed()
	else:
		_refresh()

func _on_sort_pressed() -> void:
	AudioManager.play("ui_click")
	if inventory:
		inventory.sort_slots()

func _can_drop_outside(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == ItemGrid.DRAG_TYPE and data.get("grid") == _grid

func _drop_outside(_at: Vector2, data: Variant) -> void:
	var item_id: String = str(data.get("item_id", ""))
	_selected = item_id
	_refresh()
	_open_drop_dialog(item_id)

func _on_cell_right_clicked(item_id: String, _count: int, _index: int) -> void:
	_selected = item_id
	_refresh()
	_open_drop_dialog(item_id)

## Еда и вода расходуются тем же кодом, что и клавиши U / Y в игре.
func _on_use_pressed() -> void:
	if player == null or _selected == "":
		return
	var key: Key = KEY_U if _selected in DRINK_ITEMS else KEY_Y
	var was_mode: int = player.process_mode
	player.process_mode = Node.PROCESS_MODE_INHERIT
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	if player.has_method("_unhandled_input"):
		player._unhandled_input(ev)
	player.process_mode = was_mode
	_refresh()

func _open_drop_dialog(item_id: String) -> void:
	if item_id == "" or inventory == null or (_modal and is_instance_valid(_modal)):
		return
	var total: int = inventory.get_item_count(item_id)
	if total <= 0:
		return
	var d = QuantityDialog.new()
	d.setup("🫳 Выбросить на землю", item_id, total, mini(total, inventory.get_max_stack(item_id)))
	d.confirmed.connect(func(n: int): DroppedItem.drop_from_player(player, item_id, n))
	_modal = d
	add_child(d)

func _input(event: InputEvent) -> void:
	if _modal and is_instance_valid(_modal):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.keycode in [KEY_ESCAPE, KEY_TAB, KEY_I]:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play("ui_click")
	closed.emit()
	queue_free()
