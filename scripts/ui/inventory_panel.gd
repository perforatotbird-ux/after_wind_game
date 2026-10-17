extends Control

## Окно рюкзака (TAB / I / слот 5): клеточная сетка стеков, вес и слоты, пояс
## инструментов, карточка выбранного предмета и выбрасывание на землю.
## ЛКМ — выбрать, ПКМ — сразу «Выбросить…», ESC / TAB / I — закрыть.
## Создаётся и уничтожается GameplayUIController.

signal closed
## Кнопка постройки (сейчас — «Делянка»): контроллер закрывает рюкзак и включает размещение.
signal build_requested(kind: String)

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const QuantityDialog = preload("res://scripts/ui/quantity_dialog.gd")
const DroppedItem = preload("res://scripts/inventory/dropped_item.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const DRINK_ITEMS: Array[String] = ["clean_water", "bottled_water", "healing_water"]

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
var _craft_btn: Button
var _whetstone_header_btn: Button
var _drop_btn: Button
var _selected: String = ""
var _modal: Control
var _closing: bool = false

## Длительные операции рюкзака с полосой прогресса.
const WHETSTONE_CRAFT_TIME: float = 6.0
const SHARPEN_BASE_TIME: float = 25.0
var _task_kind: String = ""
var _task_total: float = 0.0
var _task_left: float = 0.0
var _task_target: String = ""
var _task_box: VBoxContainer
var _task_label: Label
var _task_bar: ProgressBar
var _task_consumed: Dictionary = {}

func setup(p_player: Node) -> void:
	player = p_player
	inventory = player.inventory if player and "inventory" in player else null

func _ready() -> void:
	AudioManager.play("ui_open")
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
	panel.custom_minimum_size = Vector2(940, 0)
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
	var farm_btn := UI.make_button("🌾 Делянка", Vector2(120, 32), true)
	farm_btn.name = "BuildFarmFieldButton"
	farm_btn.tooltip_text = "Разметить фермерскую делянку мышкой (до 128 клеток). Материалы: древесина по периметру, камень и опилки по площади. Стройка — 1 игровой день."
	farm_btn.pressed.connect(func(): request_build("farm_field"))
	header.add_child(farm_btn)
	var plot_btn := UI.make_button("🌱 Грядка", Vector2(110, 32), true)
	plot_btn.name = "BuildFarmlandPlotButton"
	plot_btn.tooltip_text = "Поставить классическую грядку перед собой (модели mounded/tilled). Нужно: 4 дерева, 2 камня."
	plot_btn.pressed.connect(func(): request_build("farmland_plot"))
	header.add_child(plot_btn)
	var whetstone_btn := UI.make_button("🪨 Оселок (крафт)", Vector2(150, 32))
	whetstone_btn.name = "CraftWhetstoneButton"
	whetstone_btn.tooltip_text = "Скрафтить точильный брусок (оселок) прямо из рюкзака. Требуется: 2 камня, 1 песок."
	whetstone_btn.pressed.connect(_craft_whetstone_in_backpack)
	_whetstone_header_btn = whetstone_btn
	header.add_child(whetstone_btn)
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
	var belt_header := UI.make_section_header("🛠 Пояс — клик берёт инструмент в руки (колесо мыши в игре делает то же)")
	belt_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(belt_header)
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
	_d_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	details.add_child(_d_icon)
	_d_name = UI.make_label("", 17, UI.COLOR_TITLE)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_d_name)
	_d_desc = UI.make_label("", 14, UI.COLOR_MUTED)
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
	_craft_btn = UI.make_button("", Vector2(0, 36), true)
	_craft_btn.visible = false
	_craft_btn.pressed.connect(_craft_whetstone_in_backpack)
	details.add_child(_craft_btn)
	_drop_btn = UI.make_button("🫳 Выбросить…", Vector2(0, 36), false, true)
	_drop_btn.pressed.connect(func(): _open_drop_dialog(_selected))
	details.add_child(_drop_btn)
	# Полоса прогресса длительных операций (крафт оселка 6 с, заточка 25 с).
	_task_box = VBoxContainer.new()
	_task_box.add_theme_constant_override("separation", 4)
	_task_box.visible = false
	details.add_child(_task_box)
	_task_label = UI.make_label("", 14, UI.COLOR_ACCENT)
	_task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_box.add_child(_task_label)
	_task_bar = ProgressBar.new()
	_task_bar.show_percentage = false
	_task_bar.custom_minimum_size = Vector2(0, 12)
	_task_bar.max_value = 1.0
	_task_bar.value = 0.0
	_task_bar.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_CARD_EMPTY, UI.COLOR_BORDER, 1, 4))
	_task_bar.add_theme_stylebox_override("fill", UI.make_stylebox(UI.COLOR_ACCENT, Color(0, 0, 0, 0), 0, 4))
	_task_box.add_child(_task_bar)
	
	var footer := UI.make_label("ЛКМ — выбрать · перетащить — переложить · двойной клик — съесть/выпить · ПКМ или перетащить за окно — выбросить · ESC / TAB / I — закрыть", 13, UI.COLOR_DIM)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(footer)
	
	if inventory:
		inventory.inventory_updated.connect(_refresh)
		inventory.tool_changed.connect(_on_tool_changed)
		inventory.credits_changed.connect(_on_credits_changed)
		if inventory.has_signal("tool_sharpness_changed"):
			inventory.tool_sharpness_changed.connect(func(_t, _s): _refresh())
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
	if _whetstone_header_btn:
		var stones: int = inventory.get_item_count("stone")
		var sands: int = inventory.get_item_count("sand")
		_whetstone_header_btn.tooltip_text = "Скрафтить точильный брусок (оселок) прямо из рюкзака. Нужно: 2 камня, 1 песок (6 с).\nВ наличии: %d камня, %d песка." % [stones, sands]
	if inventory.has_method("ensure_belt_whetstone"):
		inventory.ensure_belt_whetstone()
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
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var d: Dictionary = ItemDB.get_item(t)
		var sharp_info: String = ""
		if inventory.has_method("is_sharp_tool") and inventory.is_sharp_tool(t):
			var s: float = inventory.get_tool_sharpness(t)
			var eff: Dictionary = inventory.get_sharpness_efficiency(t)
			sharp_info = "\nЗаточка: %d%% [%s]" % [int(round(s)), eff.get("status_name", "")]
			
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_left = 4
			bar.offset_right = -4
			bar.offset_bottom = -3
			bar.offset_top = -8
			bar.value = s
			var col: Color = Color(0.2, 0.85, 0.3)
			if s < 10.0:
				col = Color(0.95, 0.2, 0.2)
			elif s < 35.0:
				col = Color(0.95, 0.55, 0.15)
			elif s < 75.0:
				col = Color(0.85, 0.85, 0.2)
			bar.add_theme_stylebox_override("fill", UI.make_stylebox(col, Color(0, 0, 0, 0), 0, 2))
			bar.add_theme_stylebox_override("background", UI.make_stylebox(Color(0.1, 0.1, 0.12, 0.85), Color(0, 0, 0, 0), 0, 2))
			b.add_child(bar)
			
		b.tooltip_text = "[%d] %s (ур. %d)%s%s" % [
			i + 1,
			ItemDB.get_item_name(t),
			int(d.get("level", 1)),
			sharp_info,
			"\nСлоты: %d" % inventory.max_slots if is_pack else ("\nВ руках" if t == inventory.equipped_tool else "")
		]
		if t == "whetstone" and inventory.has_method("get_whetstone_uses"):
			var w_left: int = inventory.get_whetstone_uses()
			var w_count: int = inventory.get_item_count("whetstone")
			b.tooltip_text = "🪨 Оселок на поясе: %d шт., зарядов %d/5\nКлик — точить самый тупой инструмент (25 с, быстрее с навыком ремесла)" % [w_count, w_left]
			var w_lbl := UI.make_label("%d/5" % w_left, 13, UI.COLOR_ACCENT)
			w_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			w_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			w_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			w_lbl.offset_top = -16
			w_lbl.offset_bottom = -2
			b.add_child(w_lbl)
		if not is_pack:
			b.pressed.connect(_on_belt_pressed.bind(t))
		_belt.add_child(b)

func _on_belt_pressed(tool_id: String) -> void:
	if tool_id == "whetstone":
		_selected = "whetstone"
		_sharpen_with_whetstone()
		return
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
		_craft_btn.visible = false
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
	elif str(data.get("category", "")) == "seeds":
		if ItemDB.is_fruit_sapling(_selected):
			_use_btn.text = "🌱 Посадить в саду"
			_use_btn.visible = true
		else:
			var chosen: bool = player != null and player.get("selected_seed") == _selected
			_use_btn.text = "🌱 Выбрано для посадки" if chosen else "🌱 Сажать эти семена"
			_use_btn.visible = true
	elif _selected == "whetstone":
		var w_left: int = inventory.get_whetstone_uses() if inventory.has_method("get_whetstone_uses") else 0
		_d_desc.text = str(data.get("description", "")) + "\nЗарядов: %d/5. Висит на поясе, слоты рюкзака не занимает." % w_left
		_use_btn.text = "🪨 Заточить оселком (+40%%, %.0f с)" % _sharpen_duration()
		_use_btn.visible = true
	else:
		_use_btn.visible = false

	if _selected in ["stone", "sand"]:
		var stones: int = inventory.get_item_count("stone")
		var sands: int = inventory.get_item_count("sand")
		_craft_btn.text = "🪨 Скрафтить оселок (2 камня, 1 песок) [%d/2, %d/1]" % [stones, sands]
		_craft_btn.visible = true
	else:
		_craft_btn.visible = false

func _process(delta: float) -> void:
	if _task_kind == "":
		return
	_task_left = maxf(0.0, _task_left - delta)
	if _task_bar:
		_task_bar.value = 1.0 - (_task_left / maxf(0.01, _task_total))
	if _task_label:
		_task_label.text = _task_text()
	if _task_left <= 0.0:
		var done_kind: String = _task_kind
		var done_target: String = _task_target
		var done_consumed: Dictionary = _task_consumed.duplicate()
		_task_kind = ""
		_task_total = 0.0
		_task_target = ""
		_task_consumed = {}
		if _task_box:
			_task_box.visible = false
		if done_kind == "craft_whetstone":
			_finish_whetstone_craft(done_consumed)
		elif done_kind == "sharpen":
			_finish_sharpen(done_target)

func _task_text() -> String:
	var pct: int = int(round((1.0 - (_task_left / maxf(0.01, _task_total))) * 100.0))
	if _task_kind == "craft_whetstone":
		return "🪨 Обтёсываю оселок… %d%% (осталось %.1f с)" % [pct, _task_left]
	if _task_kind == "sharpen":
		var t_name: String = ItemDB.get_item_name(_task_target) if _task_target != "" else "инструмент"
		return "🪨 Заточка: %s… %d%% (осталось %.1f с)" % [t_name, pct, _task_left]
	return ""

func _sharpen_duration() -> float:
	var mult: float = 1.0
	if player and "skills" in player and player.skills and player.skills.has_method("get_machine_speed_mult"):
		mult = maxf(0.5, float(player.skills.get_machine_speed_mult()))
	return SHARPEN_BASE_TIME / mult

func _craft_whetstone_in_backpack() -> void:
	if inventory == null or _task_kind != "":
		return
	var stones: int = inventory.get_item_count("stone")
	var sands: int = inventory.get_item_count("sand")
	if stones < 2 or sands < 1:
		AudioManager.play("ui_error")
		if player and player.has_method("notify"):
			player.notify("❌ Для создания оселка нужно: 2 камня, 1 песок (есть: %d камня, %d песка)" % [stones, sands])
		return
	if not inventory.remove_item("stone", 2) or not inventory.remove_item("sand", 1):
		AudioManager.play("ui_error")
		return
	_task_consumed = {"stone": 2, "sand": 1}
	_task_kind = "craft_whetstone"
	_task_total = WHETSTONE_CRAFT_TIME
	_task_left = WHETSTONE_CRAFT_TIME
	_task_target = ""
	if _task_box:
		_task_box.visible = true
	AudioManager.play("ui_click")
	_refresh()

func _finish_whetstone_craft(done_consumed: Dictionary = {}) -> void:
	if inventory == null:
		return
	if not inventory.add_item("whetstone", 1):
		# Нет места даже на поясе — возвращаем ресурсы.
		for rid in done_consumed.keys():
			inventory.add_item(str(rid), int(done_consumed[rid]))
		if player and player.has_method("notify"):
			player.notify("❌ Не удалось взять оселок — ресурсы возвращены.")
		_refresh()
		return
	if inventory.has_method("ensure_belt_whetstone"):
		inventory.ensure_belt_whetstone()
	AudioManager.play("ui_click")
	var skills = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("add_xp"):
		skills.add_xp("crafting", 5)
	if player and player.has_method("notify"):
		var uses: int = int(inventory.get_whetstone_uses()) if inventory.has_method("get_whetstone_uses") else 5
		player.notify("✨ Оселок готов! Зарядов: %d/5 — он на поясе." % uses)
	_selected = "whetstone"
	_refresh()

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
	if item_id in DRINK_ITEMS or str(data.get("category", "")) == "food" or item_id == "whetstone":
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

## Еда и вода расходуются по id выбранного предмета (карточка справа), а не
## по общему приоритету клавиш U / Y: выбрана синяя ягода — съедается она.
func _on_use_pressed() -> void:
	if player == null or _selected == "":
		return
	if _selected == "whetstone":
		_sharpen_with_whetstone()
		return
	if str(ItemDB.get_item(_selected).get("category", "")) == "seeds":
		if ItemDB.is_fruit_sapling(_selected):
			request_build("fruit_tree:" + _selected)
			close()
			return
		if "selected_seed" in player:
			player.selected_seed = _selected
		_update_details()
		return
	if _selected in DRINK_ITEMS:
		player.drink_from_inventory(_selected)
	else:
		player.eat_food(_selected)
	_refresh()

func _sharpen_with_whetstone() -> void:
	if inventory == null or _task_kind != "":
		return
	if inventory.get_item_count("whetstone") <= 0:
		if player and player.has_method("notify"):
			player.notify("❌ Нет оселка! Скрафтите его (2 камня, 1 песок).")
		return
	var target_tool: String = ""
	if inventory.is_sharp_tool(inventory.equipped_tool) and inventory.get_tool_sharpness(inventory.equipped_tool) < 100.0:
		target_tool = inventory.equipped_tool
	else:
		var lowest_s: float = 100.0
		for t in ["axe", "pickaxe", "shovel"]:
			var s: float = inventory.get_tool_sharpness(t)
			if s < lowest_s:
				lowest_s = s
				target_tool = t

	if target_tool == "" or inventory.get_tool_sharpness(target_tool) >= 100.0:
		if player and player.has_method("notify"):
			player.notify("✨ Все инструменты уже идеально наточены!")
		return

	_task_kind = "sharpen"
	_task_target = target_tool
	_task_total = _sharpen_duration()
	_task_left = _task_total
	if _task_box:
		_task_box.visible = true
	AudioManager.play("ui_click")
	_refresh()

func _finish_sharpen(target_tool: String) -> void:
	if inventory == null or target_tool == "":
		return
	if inventory.get_item_count("whetstone") <= 0:
		if player and player.has_method("notify"):
			player.notify("❌ Оселок пропал — заточка отменена.")
		return
	if inventory.get_tool_sharpness(target_tool) >= 100.0:
		if player and player.has_method("notify"):
			player.notify("✨ Инструмент уже наточен — оселок не потрачен.")
		return
	var new_s: float = inventory.sharpen_tool(target_tool, 40.0)
	if not inventory.consume_whetstone_use():
		return
	AudioManager.play("ui_click")
	var skills = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("add_xp"):
		skills.add_xp("crafting", 8)
	if player and player.has_method("notify"):
		var t_name: String = ItemDB.get_item(target_tool).get("name", target_tool)
		var left: int = inventory.get_whetstone_uses() if inventory.has_method("get_whetstone_uses") else 0
		var left_txt: String = ("Осталось заточек: %d/5." % left) if int(inventory.get_item_count("whetstone")) > 0 else "Оселок стёрт — нужен новый."
		player.notify("🪨 %s заточен оселком на +40%% (теперь %d%%)! %s" % [t_name, int(round(new_s)), left_txt])
	_refresh()
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
	if event.is_action_pressed("toggle_inventory") and not event.is_echo():
		if not (get_viewport().gui_get_focus_owner() is LineEdit):
			close()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code in [KEY_ESCAPE, KEY_TAB, KEY_I]:
		close()
		get_viewport().set_input_as_handled()

func request_build(kind: String) -> void:
	build_requested.emit(kind)

func close() -> void:
	if _closing:
		return
	if _task_kind == "craft_whetstone" and not _task_consumed.is_empty() and inventory:
		# Возвращаем ресурсы за незавершённый крафт.
		for rid in _task_consumed.keys():
			inventory.add_item(str(rid), int(_task_consumed[rid]))
		_task_consumed = {}
	_task_kind = ""
	_closing = true
	AudioManager.play("ui_close")
	closed.emit()
	queue_free()
