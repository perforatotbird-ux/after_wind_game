extends Control

## Окно рюкзака (TAB / I / слот 5) в индустриальном стиле:
## - Тёмный графитовый UI с лаконичными бронзово-янтарными акцентами
## - Компактное модальное окно с адаптивными размерами
## - Верхняя панель: статус, кредиты, быстрые действия и закрытие
## - Тонкий индикатор загрузки с состояниями норма/перегруз/критично
## - Панель быстрого доступа (пояс инструментов с горячими клавишами [1]-[5])
## - Сетка ячеек инвентаря с перетаскиванием (drag-and-drop)
## - Правая панель характеристик, описания и контекстных действий
## - Нижняя информационная строка управления

signal closed
## Кнопка постройки («Делянка» / «Грядка»): контроллер закрывает рюкзак и включает размещение.
signal build_requested(kind: String)

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const QuantityDialog = preload("res://scripts/ui/quantity_dialog.gd")
const SharpenDialog = preload("res://scripts/ui/sharpen_dialog.gd")
const DroppedItem = preload("res://scripts/inventory/dropped_item.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const DRINK_ITEMS: Array[String] = ["clean_water", "high_purity_water", "bottled_water", "healing_water"]

var player: Node
var inventory: Node

var _grid: GridContainer
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _weight_label: Label
var _weight_status: Label
var _slots_label: Label
var _credits_label: Label
var _belt: HBoxContainer

# Панель деталей
var _empty_details_box: VBoxContainer
var _active_details_box: VBoxContainer
var _d_icon: TextureRect
var _d_name: Label
var _d_category_badge: PanelContainer
var _d_category_label: Label
var _d_desc: Label
var _d_count: Label
var _d_weight: Label
var _d_extra_meta: Label
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
	add_to_group("ui_input_blockers")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Затемнение вокруг окна: перетащить стек за пределы окна = выбросить на землю
	var overlay := UI.make_overlay()
	overlay.set_drag_forwarding(Callable(), _can_drop_outside, _drop_outside)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Главное модальное окно: компактное (880×560 px), адаптивное
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_BORDER, 1, 6)
	panel.custom_minimum_size = Vector2(880, 560)
	center.add_child(panel)

	var margin := UI.make_margin(16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# --- 1. ВЕРХНЯЯ ПАНЕЛЬ (Header) ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	var title_lbl := UI.make_label("РЮКЗАК", 18, UI.COLOR_TITLE)
	var subtitle_lbl := UI.make_label("СНАРЯЖЕНИЕ ВЫЖИВШЕГО", 9, UI.COLOR_DIM)
	title_box.add_child(title_lbl)
	title_box.add_child(subtitle_lbl)
	header.add_child(title_box)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	# Бейдж баланса кредитов
	var credits_box := UI.make_badge("💰 0 кр.", 12, UI.COLOR_ACCENT, UI.COLOR_GRAPHITE_INSET, UI.COLOR_BORDER_SUBTLE)
	_credits_label = credits_box.get_child(0) as Label
	header.add_child(credits_box)

	var sort_btn := UI.make_button("⇅ Сортировка", Vector2(110, 30), false, false, 12)
	sort_btn.tooltip_text = "Упорядочить рюкзак по категориям и названиям"
	sort_btn.pressed.connect(_on_sort_pressed)
	header.add_child(sort_btn)

	var farm_btn := UI.make_button("🌾 Делянка", Vector2(100, 30), true, false, 12)
	farm_btn.name = "BuildFarmFieldButton"
	farm_btn.tooltip_text = "Разметить фермерскую делянку мышкой (до 128 клеток). Материалы: дерево, камень, опилки."
	farm_btn.pressed.connect(func(): request_build("farm_field"))
	header.add_child(farm_btn)

	var plot_btn := UI.make_button("🌱 Грядка", Vector2(95, 30), true, false, 12)
	plot_btn.name = "BuildFarmlandPlotButton"
	plot_btn.tooltip_text = "Поставить классическую грядку (4 дерева, 2 камня)."
	plot_btn.pressed.connect(func(): request_build("farmland_plot"))
	header.add_child(plot_btn)

	var whetstone_btn := UI.make_button("🪨 Точильный камень", Vector2(145, 30), false, false, 12)
	whetstone_btn.name = "CraftWhetstoneButton"
	whetstone_btn.tooltip_text = "Скрафтить точильный камень прямо из рюкзака. Нужно: 2 камня, 1 песок (6 с)."
	whetstone_btn.pressed.connect(_craft_whetstone_in_backpack)
	_whetstone_header_btn = whetstone_btn
	header.add_child(whetstone_btn)

	var close_btn := UI.make_button("✕", Vector2(34, 30), false, false, 13)
	close_btn.tooltip_text = "Закрыть (ESC / TAB / I)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# --- 2. ИНДИКАТОР ВЕСА И СЛОТОВ ---
	var load_box := VBoxContainer.new()
	load_box.add_theme_constant_override("separation", 3)
	root.add_child(load_box)

	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	load_box.add_child(load_row)

	_weight_label = UI.make_label("⚖ ЗАГРУЗКА: 0.0 / 0.0 кг", 12, UI.COLOR_TEXT)
	load_row.add_child(_weight_label)

	_weight_status = UI.make_label("— норма", 12, UI.COLOR_OK)
	load_row.add_child(_weight_status)

	var load_spacer := Control.new()
	load_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(load_spacer)

	_slots_label = UI.make_label("СЛОТЫ: 0 / 0", 12, UI.COLOR_MUTED)
	load_row.add_child(_slots_label)

	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(0, 6)
	_weight_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_bar.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_GRAPHITE_INSET, Color(0, 0, 0, 0), 0, 3))
	_weight_fill = UI.make_stylebox(UI.COLOR_OK, Color(0, 0, 0, 0), 0, 3)
	_weight_bar.add_theme_stylebox_override("fill", _weight_fill)
	load_box.add_child(_weight_bar)

	# --- 3. ПАНЕЛЬ БЫСТРОГО ДОСТУПА (ПОЯС ИНСТРУМЕНТОВ) ---
	var belt_section := VBoxContainer.new()
	belt_section.add_theme_constant_override("separation", 4)
	root.add_child(belt_section)

	var belt_title_row := HBoxContainer.new()
	belt_title_row.add_theme_constant_override("separation", 6)
	belt_section.add_child(belt_title_row)

	var belt_lbl := UI.make_label("БЫСТРЫЙ ДОСТУП", 11, UI.COLOR_TITLE)
	belt_title_row.add_child(belt_lbl)
	var belt_tip := UI.make_label("— клавиши [1]–[5] или клик для выбора активного инструмента", 11, UI.COLOR_DIM)
	belt_title_row.add_child(belt_tip)

	_belt = HBoxContainer.new()
	_belt.add_theme_constant_override("separation", 6)
	belt_section.add_child(_belt)

	# --- 4. ОСНОВНАЯ ОБЛАСТЬ: СЕТКА ИНВЕНТАРЯ + ПРАВАЯ ПАНЕЛЬ ДЕТАЛЕЙ ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Левая колонка: сетка предметов
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)

	var grid_title_row := HBoxContainer.new()
	grid_title_row.add_theme_constant_override("separation", 6)
	left.add_child(grid_title_row)
	grid_title_row.add_child(UI.make_label("ОТДЕЛЕНИЕ РЮКЗАКА", 11, UI.COLOR_TITLE))
	grid_title_row.add_child(UI.make_label("— 6 колонок · перетаскивание ячеек", 11, UI.COLOR_DIM))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 276)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_grid = ItemGrid.new()
	_grid.columns = 6
	_grid.drag_enabled = true
	_grid.cell_pressed.connect(_on_cell_pressed)
	_grid.cell_right_clicked.connect(_on_cell_right_clicked)
	_grid.cell_moved.connect(_on_cell_moved)
	_grid.cell_activated.connect(_on_cell_activated)
	scroll.add_child(_grid)

	# Правая колонка: панель деталей выбранного предмета
	var right_panel := UI.make_panel(UI.COLOR_GRAPHITE_PANEL, UI.COLOR_BORDER_SUBTLE, 1, 4)
	right_panel.custom_minimum_size = Vector2(320, 0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)

	var details_margin := UI.make_margin(12)
	right_panel.add_child(details_margin)

	var details_stack := Control.new()
	details_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_margin.add_child(details_stack)

	# А. Нейтральное состояние (предмет не выбран)
	_empty_details_box = VBoxContainer.new()
	_empty_details_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty_details_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_details_box.add_theme_constant_override("separation", 8)
	details_stack.add_child(_empty_details_box)

	var empty_icon_frame := UI.make_panel(UI.COLOR_GRAPHITE_INSET, UI.COLOR_BORDER_SUBTLE, 1, 4)
	empty_icon_frame.custom_minimum_size = Vector2(48, 48)
	empty_icon_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var empty_icon_margin := UI.make_margin(8)
	empty_icon_frame.add_child(empty_icon_margin)
	var empty_icon_lbl := UI.make_label("🎒", 20)
	empty_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_icon_margin.add_child(empty_icon_lbl)
	_empty_details_box.add_child(empty_icon_frame)

	var empty_title := UI.make_label("ПРЕДМЕТ НЕ ВЫБРАН", 13, UI.COLOR_MUTED)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_details_box.add_child(empty_title)

	var empty_sub := UI.make_label("Выберите ячейку в рюкзаке для просмотра параметров, описания и доступных действий.", 11, UI.COLOR_DIM)
	empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_details_box.add_child(empty_sub)

	# Б. Активное состояние (предмет выбран)
	_active_details_box = VBoxContainer.new()
	_active_details_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_details_box.add_theme_constant_override("separation", 6)
	_active_details_box.visible = false
	details_stack.add_child(_active_details_box)

	# Верх карточки: иконка + имя + категория
	var item_head := HBoxContainer.new()
	item_head.add_theme_constant_override("separation", 10)
	_active_details_box.add_child(item_head)

	var icon_frame := UI.make_panel(UI.COLOR_GRAPHITE_INSET, UI.COLOR_BORDER_SUBTLE, 1, 4)
	icon_frame.custom_minimum_size = Vector2(58, 58)
	item_head.add_child(icon_frame)

	var icon_margin := UI.make_margin(4)
	icon_frame.add_child(icon_margin)

	_d_icon = TextureRect.new()
	_d_icon.custom_minimum_size = Vector2(50, 50)
	_d_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_d_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon_margin.add_child(_d_icon)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 2)
	item_head.add_child(name_box)

	_d_name = UI.make_label("", 15, UI.COLOR_TITLE)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(_d_name)

	_d_category_badge = UI.make_badge("ПРЕДМЕТ", 10, UI.COLOR_MUTED, UI.COLOR_GRAPHITE_SURFACE, UI.COLOR_BORDER_SUBTLE)
	_d_category_label = _d_category_badge.get_child(0) as Label
	name_box.add_child(_d_category_badge)

	_active_details_box.add_child(UI.make_divider())

	# Метаданные (вес, количество, стек)
	var meta_box := VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 3)
	_active_details_box.add_child(meta_box)

	_d_count = UI.make_label("", 12, UI.COLOR_TEXT)
	meta_box.add_child(_d_count)

	_d_weight = UI.make_label("", 12, UI.COLOR_TEXT)
	meta_box.add_child(_d_weight)

	_d_extra_meta = UI.make_label("", 12, UI.COLOR_ACCENT)
	meta_box.add_child(_d_extra_meta)

	_active_details_box.add_child(UI.make_divider())

	# Описание
	_d_desc = UI.make_label("", 12, UI.COLOR_MUTED)
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_details_box.add_child(_d_desc)

	var details_spacer := Control.new()
	details_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_active_details_box.add_child(details_spacer)

	# Контекстные действия
	var actions_box := VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 4)
	_active_details_box.add_child(actions_box)

	_use_btn = UI.make_button("", Vector2(0, 32), true, false, 12)
	_use_btn.pressed.connect(_on_use_pressed)
	actions_box.add_child(_use_btn)

	_craft_btn = UI.make_button("", Vector2(0, 30), false, false, 12)
	_craft_btn.visible = false
	_craft_btn.pressed.connect(_craft_whetstone_in_backpack)
	actions_box.add_child(_craft_btn)

	_drop_btn = UI.make_button("🫳 Выбросить на землю…", Vector2(0, 30), false, true, 12)
	_drop_btn.pressed.connect(func(): _open_drop_dialog(_selected))
	actions_box.add_child(_drop_btn)

	# Полоса прогресса длительных операций
	_task_box = VBoxContainer.new()
	_task_box.add_theme_constant_override("separation", 3)
	_task_box.visible = false
	actions_box.add_child(_task_box)

	_task_label = UI.make_label("", 12, UI.COLOR_ACCENT)
	_task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_box.add_child(_task_label)

	_task_bar = ProgressBar.new()
	_task_bar.show_percentage = false
	_task_bar.custom_minimum_size = Vector2(0, 8)
	_task_bar.max_value = 1.0
	_task_bar.value = 0.0
	_task_bar.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_GRAPHITE_INSET, UI.COLOR_BORDER_SUBTLE, 1, 4))
	_task_bar.add_theme_stylebox_override("fill", UI.make_stylebox(UI.COLOR_ACCENT, Color(0, 0, 0, 0), 0, 4))
	_task_box.add_child(_task_bar)

	# --- 5. НИЖНЯЯ СТРОКА ПОДСКАЗОК УПРАВЛЕНИЯ ---
	root.add_child(UI.make_divider())

	var footer := UI.make_label("[ЛКМ] Выбрать · [2×ЛКМ] Использовать · [ПКМ / Drag за окно] Выбросить · [Drag] Переложить · [ESC / TAB] Закрыть", 11, UI.COLOR_DIM)
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
	_weight_label.text = "⚖ ЗАГРУЗКА: %.1f / %.0f кг" % [total, limit]
	_weight_bar.max_value = maxf(1.0, limit * inventory.OVERLOAD_CRITICAL_RATIO)
	_weight_bar.value = minf(total, _weight_bar.max_value)

	var state: int = inventory.get_load_state()
	if state == 0:
		_weight_fill.bg_color = UI.COLOR_OK
		_weight_status.text = "— норма"
		_weight_status.add_theme_color_override("font_color", UI.COLOR_OK)
	elif state == 1:
		_weight_fill.bg_color = UI.COLOR_ACCENT
		_weight_status.text = "— ПЕРЕГРУЗ (-30% скор.)"
		_weight_status.add_theme_color_override("font_color", UI.COLOR_ACCENT)
	else:
		_weight_fill.bg_color = UI.COLOR_DANGER
		_weight_status.text = "— КРИТИЧЕСКИЙ ПЕРЕГРУЗ (нет хода)"
		_weight_status.add_theme_color_override("font_color", UI.COLOR_DANGER)

	_slots_label.text = "СЛОТЫ: %d / %d" % [inventory.get_used_slots(), inventory.max_slots]
	_credits_label.text = "💰 %d кр." % int(inventory.credits)

	if _whetstone_header_btn:
		var stones: int = inventory.get_item_count("stone")
		var sands: int = inventory.get_item_count("sand")
		_whetstone_header_btn.tooltip_text = "Скрафтить точильный камень прямо из рюкзака. Нужно: 2 камня, 1 песок (6 с).\nВ наличии: %d камня, %d песка." % [stones, sands]

	if inventory.has_method("ensure_belt_whetstone"):
		inventory.ensure_belt_whetstone()

	_build_belt()
	_update_details()

func _build_belt() -> void:
	for c in _belt.get_children():
		_belt.remove_child(c)
		c.queue_free()

	for i in range(inventory.tools.size()):
		var t: String = inventory.tools[i]
		var is_pack: bool = t == "backpack" or ItemDB.get_item(t).get("tool_type", "") == "backpack"
		var is_equipped: bool = t == inventory.equipped_tool

		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true

		var bg_color: Color = UI.COLOR_GRAPHITE_CARD
		var border_color: Color = UI.COLOR_BORDER_SUBTLE
		var border_width: int = 1
		if is_equipped:
			bg_color = Color(0.18, 0.22, 0.28, 0.98)
			border_color = UI.COLOR_ACCENT
			border_width = 2
		b.add_theme_stylebox_override("normal", UI.make_stylebox(bg_color, border_color, border_width, 4))
		b.add_theme_stylebox_override("hover", UI.make_stylebox(bg_color.lightened(0.12), UI.COLOR_ACCENT, maxi(border_width, 1), 4))
		b.add_theme_stylebox_override("pressed", UI.make_stylebox(bg_color.lightened(0.20), UI.COLOR_ACCENT, 2, 4))

		# Иконка инструмента
		var icon_rect := TextureRect.new()
		icon_rect.texture = ItemIcons.get_texture(t)
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 8
		icon_rect.offset_top = 6
		icon_rect.offset_right = -8
		icon_rect.offset_bottom = -10
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon_rect)

		# Шильдик клавиши [1]-[5] в верхнем левом углу
		var hotkey_lbl := Label.new()
		hotkey_lbl.text = "[%d]" % (i + 1)
		hotkey_lbl.add_theme_font_size_override("font_size", 10)
		hotkey_lbl.add_theme_color_override("font_color", UI.COLOR_ACCENT if is_equipped else UI.COLOR_MUTED)
		hotkey_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		hotkey_lbl.add_theme_constant_override("outline_size", 2)
		hotkey_lbl.offset_left = 4
		hotkey_lbl.offset_top = 2
		hotkey_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hotkey_lbl)

		var d: Dictionary = ItemDB.get_item(t)
		var sharp_info: String = ""

		# Индикатор заточки/прочности
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
			bar.offset_top = -7
			bar.max_value = 100.0
			bar.value = s

			var col: Color = UI.COLOR_OK
			if s < 10.0:
				col = UI.COLOR_DANGER
			elif s < 35.0:
				col = Color(0.92, 0.52, 0.22)
			elif s < 75.0:
				col = UI.COLOR_ACCENT
			bar.add_theme_stylebox_override("fill", UI.make_stylebox(col, Color(0, 0, 0, 0), 0, 2))
			bar.add_theme_stylebox_override("background", UI.make_stylebox(Color(0.08, 0.09, 0.11, 0.9), Color(0, 0, 0, 0), 0, 2))
			b.add_child(bar)

		b.tooltip_text = "[%d] %s (ур. %d)%s%s" % [
			i + 1,
			ItemDB.get_item_name(t),
			int(d.get("level", 1)),
			sharp_info,
			"\nСлоты: %d" % inventory.max_slots if is_pack else ("\nВ руках" if is_equipped else "")
		]

		if t == "whetstone" and inventory.has_method("get_whetstone_uses"):
			var w_left: int = inventory.get_whetstone_uses()
			var w_count: int = inventory.get_item_count("whetstone")
			b.tooltip_text = "🪨 Точильный камень на поясе: %d шт., зарядов %d/5\nКлик — точить самый тупой инструмент (25 с)" % [w_count, w_left]
			var w_lbl := UI.make_label("%d/5" % w_left, 11, UI.COLOR_ACCENT)
			w_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			w_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			w_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			w_lbl.offset_top = -14
			w_lbl.offset_bottom = -1
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

func _get_category_info(cat: String, item_id: String) -> Dictionary:
	if item_id in DRINK_ITEMS or cat == "water":
		return {"title": "ВОДА / НАПИТОК", "color": Color(0.38, 0.75, 0.98)}
	if cat == "food":
		return {"title": "ЕДА / ПРИПАСЫ", "color": Color(0.92, 0.68, 0.30)}
	if cat == "seeds":
		return {"title": "СЕМЕНА / САЖЕНЦЫ", "color": Color(0.48, 0.82, 0.48)}
	if cat == "tool":
		return {"title": "ИНСТРУМЕНТ", "color": Color(0.60, 0.78, 0.95)}
	if cat == "fuel":
		return {"title": "ТОПЛИВО", "color": Color(0.92, 0.52, 0.25)}
	if cat == "refined_materials" or cat == "material":
		return {"title": "МАТЕРИАЛ", "color": Color(0.85, 0.72, 0.45)}
	if cat == "raw_materials" or cat == "resource":
		return {"title": "СЫРЬЁ / РЕСУРС", "color": Color(0.72, 0.76, 0.82)}
	if cat == "building" or cat == "construction":
		return {"title": "СТРОИТЕЛЬСТВО", "color": Color(0.82, 0.62, 0.48)}
	return {"title": "ПРЕДМЕТ", "color": UI.COLOR_MUTED}

func _update_details() -> void:
	if _selected == "":
		_empty_details_box.visible = true
		_active_details_box.visible = false
		_use_btn.visible = false
		_craft_btn.visible = false
		_drop_btn.visible = false
		return

	_empty_details_box.visible = false
	_active_details_box.visible = true

	var data: Dictionary = ItemDB.get_item(_selected)
	var count: int = inventory.get_item_count(_selected)
	var w: float = inventory.get_item_weight(_selected)
	var max_st: int = inventory.get_max_stack(_selected)
	var slots_used: int = inventory.get_slots_for(_selected, count)

	_d_icon.texture = ItemIcons.get_texture(_selected)
	_d_name.text = "%s %s" % [ItemDB.get_item_icon(_selected), ItemDB.get_item_name(_selected)]

	var cat_info: Dictionary = _get_category_info(str(data.get("category", "")), _selected)
	_d_category_label.text = str(cat_info.get("title", "ПРЕДМЕТ"))
	_d_category_label.add_theme_color_override("font_color", cat_info.get("color", UI.COLOR_MUTED))

	_d_count.text = "📦 Количество: %d шт. (стек до %d, слотов: %d)" % [count, max_st, slots_used]
	_d_weight.text = "⚖ Вес: %.1f кг (%.2f кг/шт.)" % [w * count, w]
	_d_desc.text = str(data.get("description", ""))

	# Дополнительные специфические метаданные
	if _selected == "whetstone":
		var w_left: int = inventory.get_whetstone_uses() if inventory.has_method("get_whetstone_uses") else 0
		_d_extra_meta.text = "🪨 Зарядов заточки: %d/5 (поясной инструмент)" % w_left
		_d_extra_meta.visible = true
	elif inventory.is_sharp_tool(_selected):
		var s_now: float = inventory.get_tool_sharpness(_selected)
		var eff: Dictionary = inventory.get_sharpness_efficiency(_selected)
		_d_extra_meta.text = "🔨 Заточка: %d%% [%s]" % [int(round(s_now)), eff.get("status_name", "")]
		_d_extra_meta.visible = true
	else:
		_d_extra_meta.visible = false

	_drop_btn.visible = true

	# Контекстные действия
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
		_use_btn.text = "🪨 Заточить инструмент (+40%%, %.0f с)" % _sharpen_duration()
		_use_btn.visible = true
	elif inventory.is_sharp_tool(_selected):
		var s_now: float = inventory.get_tool_sharpness(_selected)
		_use_btn.text = "🔨 Меню «Заточить» (%d%%)" % int(round(s_now))
		_use_btn.visible = true
	else:
		_use_btn.visible = false

	# Кнопка быстрого крафта точильного камня
	if _selected in ["stone", "sand"]:
		var stones: int = inventory.get_item_count("stone")
		var sands: int = inventory.get_item_count("sand")
		_craft_btn.text = "🪨 Скрафтить точильный камень [%d/2 к., %d/1 п.]" % [stones, sands]
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
		return "🪨 Готовлю точильный камень… %d%% (осталось %.1f с)" % [pct, _task_left]
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
			player.notify("❌ Для создания точильного камня нужно: 2 камня, 1 песок (есть: %d камня, %d песка)" % [stones, sands])
		return

	var took_stone: bool = inventory.remove_item("stone", 2)
	var took_sand: bool = inventory.remove_item("sand", 1)
	if not took_stone or not took_sand:
		if took_stone:
			inventory.add_item("stone", 2)
		if took_sand:
			inventory.add_item("sand", 1)
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
		for rid in done_consumed.keys():
			inventory.add_item(str(rid), int(done_consumed[rid]))
		if player and player.has_method("notify"):
			player.notify("❌ Не удалось взять точильный камень — ресурсы возвращены.")
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
		player.notify("✨ Точильный камень готов! Зарядов: %d/5 — он на поясе." % uses)
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
	if inventory and inventory.is_sharp_tool(item_id):
		_refresh()
		_open_sharpen_dialog(item_id)
	elif item_id in DRINK_ITEMS or str(data.get("category", "")) == "food" or item_id == "whetstone":
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

func _on_use_pressed() -> void:
	if player == null or _selected == "":
		return
	if _selected == "whetstone":
		_sharpen_with_whetstone()
		return
	if inventory and inventory.is_sharp_tool(_selected):
		_open_sharpen_dialog(_selected)
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

func _open_sharpen_dialog(tool_id: String) -> void:
	if tool_id == "" or inventory == null or (_modal and is_instance_valid(_modal)):
		return
	var d = SharpenDialog.new()
	d.setup(tool_id, inventory)
	d.confirmed.connect(func(t: String):
		_start_sharpen_task(t)
	)
	_modal = d
	add_child(d)

func _sharpen_with_whetstone() -> void:
	if inventory == null:
		return
	if _task_kind != "":
		if player and player.has_method("notify"):
			player.notify("🛠 Уже идёт другая операция — дождитесь её завершения.")
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
	_start_sharpen_task(target_tool)

func _start_sharpen_task(tool_id: String) -> void:
	if inventory == null or tool_id == "":
		return
	if _task_kind != "":
		if player and player.has_method("notify"):
			player.notify("🛠 Уже идёт другая операция — дождитесь её завершения.")
		return
	if inventory.get_item_count("whetstone") <= 0:
		if player and player.has_method("notify"):
			player.notify("❌ Нужен Точильный камень! Скрафтите его (2 камня, 1 песок) через кнопку 🪨 в шапке рюкзака.")
		return
	if inventory.get_tool_sharpness(tool_id) >= 100.0:
		if player and player.has_method("notify"):
			player.notify("✨ Инструмент уже идеально наточен!")
		return
	_task_kind = "sharpen"
	_task_target = tool_id
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
			player.notify("❌ Точильный камень пропал — заточка отменена.")
		return
	if inventory.get_tool_sharpness(target_tool) >= 100.0:
		if player and player.has_method("notify"):
			player.notify("✨ Инструмент уже наточен — камень не потрачен.")
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
		var left_txt: String = ("Осталось заточек: %d/5." % left) if int(inventory.get_item_count("whetstone")) > 0 else "Точильный камень стёрся — нужен новый."
		player.notify("🪨 %s заточен на +40%% (теперь %d%%)! %s" % [t_name, int(round(new_s)), left_txt])
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
		for rid in _task_consumed.keys():
			inventory.add_item(str(rid), int(_task_consumed[rid]))
		_task_consumed = {}
	_task_kind = ""
	_closing = true
	AudioManager.play("ui_close")
	closed.emit()
	queue_free()
