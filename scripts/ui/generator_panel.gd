extends Control

## Окно управления твердотопливным генератором:
## * Статус работы и рубильник (Старт / Стоп);
## * Индикатор текущей выработки (кВт) и прогресс сгорания топлива;
## * Мини-инвентарь на 4 слота топлива (дерево, уголь, брикеты);
## * Рюкзак игрока с быстрой загрузкой топлива кликом;
## * Справочная таблица энергоэффективности видов топлива.

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const SolidFuelGeneratorScript = preload("res://scripts/energy/solid_generator.gd")

var generator: Node
var player: Node
var inventory: Node

var _status_badge: Label
var _power_label: Label
var _burn_info: Label
var _burn_progress: ProgressBar
var _toggle_btn: Button

var _fuel_slot_btns: Array[Button] = []
var _fuel_total_label: Label
var _backpack_grid: ItemGrid
var _backpack_info: Label

var _closing: bool = false

func setup(p_generator: Node, p_player: Node) -> void:
	generator = p_generator
	player = p_player
	inventory = player.inventory if player and "inventory" in player else null

func _ready() -> void:
	add_to_group("ui_input_blockers")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 560)
	center.add_child(scroll)

	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(840, 0)
	scroll.add_child(panel)

	var margin := UI.make_margin(18)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	# --- 1. Шапка ---
	var head := HBoxContainer.new()
	root_vbox.add_child(head)

	var title_lbl := UI.make_label("⚡ Твердотопливный генератор", 20, UI.COLOR_TITLE)
	head.add_child(title_lbl)

	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_spacer)

	var close_btn := UI.make_button("×", Vector2(40, 32))
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# --- 2. Блок статуса и управления генератором ---
	var status_panel := UI.make_panel(UI.COLOR_CARD, UI.COLOR_BORDER, 1)
	root_vbox.add_child(status_panel)

	var sp_margin := UI.make_margin(12)
	status_panel.add_child(sp_margin)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 8)
	sp_margin.add_child(status_vbox)

	var status_top_row := HBoxContainer.new()
	status_top_row.add_theme_constant_override("separation", 16)
	status_vbox.add_child(status_top_row)

	_status_badge = UI.make_label("⚪ ОСТАНОВЛЕН", 16, UI.COLOR_TITLE)
	status_top_row.add_child(_status_badge)

	_power_label = UI.make_label("Выработка: 0.0 кВт", 16, UI.COLOR_TEXT)
	status_top_row.add_child(_power_label)

	var st_spacer := Control.new()
	st_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_top_row.add_child(st_spacer)

	_toggle_btn = UI.make_button("▶ Запустить генератор", Vector2(190, 34), true)
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	status_top_row.add_child(_toggle_btn)

	var burn_row := HBoxContainer.new()
	burn_row.add_theme_constant_override("separation", 12)
	status_vbox.add_child(burn_row)

	_burn_info = UI.make_label("Топливо не горит", 13, UI.COLOR_MUTED)
	_burn_info.custom_minimum_size.x = 260
	burn_row.add_child(_burn_info)

	_burn_progress = ProgressBar.new()
	_burn_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_burn_progress.custom_minimum_size.y = 20
	_burn_progress.show_percentage = true
	_burn_progress.min_value = 0.0
	_burn_progress.max_value = 100.0
	_burn_progress.value = 0.0
	_burn_progress.add_theme_stylebox_override("fill", UI.make_stylebox(UI.COLOR_ACCENT, Color(0, 0, 0, 0), 0, 4))
	burn_row.add_child(_burn_progress)

	# --- 3. Основная рабочая область (2 колонки) ---
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 24)
	root_vbox.add_child(body_row)

	# --- Левая колонка: Мини-инвентарь генератора ---
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = 380
	left_col.add_theme_constant_override("separation", 10)
	body_row.add_child(left_col)

	left_col.add_child(UI.make_section_header("⛽ Топливный отсек (4 слота)"))

	var slots_hbox := HBoxContainer.new()
	slots_hbox.add_theme_constant_override("separation", 8)
	left_col.add_child(slots_hbox)

	var slot_count: int = generator.fuel_slots.size() if generator and "fuel_slots" in generator else 4
	for i in range(slot_count):
		var btn := UI.make_button("", Vector2(64, 64))
		btn.expand_icon = true
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(_on_fuel_slot_pressed.bind(i))
		slots_hbox.add_child(btn)
		_fuel_slot_btns.append(btn)

	_fuel_total_label = UI.make_label("", 13, UI.COLOR_MUTED)
	left_col.add_child(_fuel_total_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	left_col.add_child(btn_row)

	var fill_btn := UI.make_button("⛽ Заправить всё", Vector2(180, 32), true)
	fill_btn.pressed.connect(_on_fill_all_pressed)
	btn_row.add_child(fill_btn)

	var take_btn := UI.make_button("📦 Забрать всё", Vector2(150, 32))
	take_btn.pressed.connect(_on_take_all_pressed)
	btn_row.add_child(take_btn)

	# Таблица топлива
	left_col.add_child(HSeparator.new())
	left_col.add_child(UI.make_section_header("📊 Энергоэффективность топлива"))

	var fuel_info_box := VBoxContainer.new()
	fuel_info_box.add_theme_constant_override("separation", 4)
	left_col.add_child(fuel_info_box)

	fuel_info_box.add_child(_make_fuel_info_row("wood", "Древесина: 2.0 кВт · 30 с / шт"))
	fuel_info_box.add_child(_make_fuel_info_row("coal", "Уголь: 4.0 кВт · 75 с / шт"))
	fuel_info_box.add_child(_make_fuel_info_row("fuel_briquette", "Топливный брикет: 6.0 кВт · 120 с / шт"))

	# --- Правая колонка: Рюкзак игрока ---
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	body_row.add_child(right_col)

	right_col.add_child(UI.make_section_header("🎒 Рюкзак (клик по топливу — загрузить)"))

	_backpack_info = UI.make_label("", 13, UI.COLOR_MUTED)
	right_col.add_child(_backpack_info)

	_backpack_grid = ItemGrid.new()
	_backpack_grid.columns = 5
	_backpack_grid.cell_size = Vector2(56, 56)
	_backpack_grid.cell_pressed.connect(_on_backpack_cell_pressed)
	right_col.add_child(_backpack_grid)

	# Подвал с подсказками
	root_vbox.add_child(HSeparator.new())
	var hint_lbl := UI.make_label("ЛКМ по топливу в рюкзаке — загрузить • Клик по слоту генератора — забрать в рюкзак • ESC — закрыть", 12, UI.COLOR_MUTED)
	root_vbox.add_child(hint_lbl)

	# Сигналы
	if generator:
		if generator.has_signal("fuel_slots_changed"):
			generator.fuel_slots_changed.connect(refresh)
		if generator.has_signal("generator_state_changed"):
			generator.generator_state_changed.connect(func(_r, _o): refresh())

	if inventory and inventory.has_signal("inventory_updated"):
		inventory.inventory_updated.connect(refresh)

	refresh()
	AudioManager.play("ui_open")

func _process(_delta: float) -> void:
	if _closing or generator == null or not is_instance_valid(generator):
		return

	# Плавное обновление прогресса сгорания
	if generator.is_running and generator.fuel_burn_left > 0.0:
		var pct: float = (generator.fuel_burn_left / maxf(0.01, generator.fuel_burn_total)) * 100.0
		_burn_progress.value = pct
		var fuel_name: String = generator.FUEL_PROPERTIES.get(generator.active_fuel_type, {}).get("name", "Топливо")
		_burn_info.text = "Горит: %s · осталось %.0f с" % [fuel_name, generator.fuel_burn_left]
	else:
		_burn_progress.value = 0.0
		_burn_info.text = "Топливо не горит"

func refresh() -> void:
	if _closing or generator == null or not is_instance_valid(generator):
		return

	# Обновление статуса
	if generator.is_running and generator.fuel_burn_left > 0.0:
		_status_badge.text = "🟢 РАБОТАЕТ"
		_status_badge.modulate = Color(0.3, 1.0, 0.4)
		_power_label.text = "Выработка: %.1f кВт" % generator.current_output
		_toggle_btn.text = "⏸ Остановить генератор"
		_toggle_btn.disabled = false
	elif generator._has_any_fuel():
		_status_badge.text = "⚪ ОСТАНОВЛЕН"
		_status_badge.modulate = Color(0.85, 0.85, 0.85)
		_power_label.text = "Выработка: 0.0 кВт (готов к пуску)"
		_toggle_btn.text = "▶ Запустить генератор"
		_toggle_btn.disabled = false
	else:
		_status_badge.text = "🔴 НЕТ ТОПЛИВА"
		_status_badge.modulate = Color(1.0, 0.35, 0.35)
		_power_label.text = "Выработка: 0.0 кВт"
		_toggle_btn.text = "▶ Запустить генератор"
		_toggle_btn.disabled = true

	# Обновление слотов топлива генератора
	for i in range(_fuel_slot_btns.size()):
		var btn: Button = _fuel_slot_btns[i]
		if i < generator.fuel_slots.size():
			var slot: Dictionary = generator.fuel_slots[i]
			var fid: String = str(slot.get("item_id", ""))
			var cnt: int = int(slot.get("count", 0))
			if not fid.is_empty() and cnt > 0:
				btn.icon = ItemIcons.get_texture(fid)
				btn.text = "×%d" % cnt
				btn.tooltip_text = "%s (×%d)\nКлик: забрать в рюкзак" % [ItemDB.get_item_name(fid), cnt]
			else:
				btn.icon = null
				btn.text = "Пусто"
				btn.tooltip_text = "Пустой топливный слот\nКликните по топливу в рюкзаке для загрузки"
		else:
			btn.icon = null
			btn.text = ""

	var total_fuel: int = generator.get_total_fuel_count()
	var total_time: float = generator.get_total_fuel_burn_time()
	var mins: int = int(total_time) / 60
	var secs: int = int(total_time) % 60
	_fuel_total_label.text = "Всего топлива в баке: %d шт. · Запас работы: %02d:%02d" % [total_fuel, mins, secs]

	# Обновление рюкзака
	if inventory:
		_backpack_grid.set_stacks(inventory.get_slot_cells(), inventory.max_slots)
		_backpack_info.text = "Слоты: %d / %d · Вес: %.1f / %.1f кг" % [
			inventory.get_used_slots(), inventory.max_slots,
			inventory.get_total_weight(), inventory.max_weight
		]

func _make_fuel_info_row(item_id: String, desc: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = ItemIcons.get_texture(item_id)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	row.add_child(icon)
	var lbl := UI.make_label(desc, 13, UI.COLOR_MUTED)
	row.add_child(lbl)
	return row

func _on_toggle_pressed() -> void:
	if generator:
		generator.toggle_running()
		refresh()

func _on_fuel_slot_pressed(slot_idx: int) -> void:
	if generator and inventory:
		var taken = generator.take_fuel_to_inventory(slot_idx, inventory)
		if taken > 0:
			AudioManager.play("ui_click")
			refresh()

func _on_backpack_cell_pressed(item_id: String, count: int, _idx: int) -> void:
	if generator and inventory and item_id in generator.VALID_FUELS:
		var added = generator.add_fuel_from_inventory(inventory, item_id, count)
		if added > 0:
			AudioManager.play("ui_click")
			refresh()

func _on_fill_all_pressed() -> void:
	if generator and inventory:
		var total_added: int = 0
		for fid in generator.VALID_FUELS:
			total_added += generator.add_fuel_from_inventory(inventory, fid)
		if total_added > 0:
			AudioManager.play("ui_click")
			refresh()

func _on_take_all_pressed() -> void:
	if generator and inventory:
		var total_taken: int = generator.take_all_fuel_to_inventory(inventory)
		if total_taken > 0:
			AudioManager.play("ui_click")
			refresh()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
