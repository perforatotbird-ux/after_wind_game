extends Control

## Окно станка: основная область — сетка рецептов (как клетки рюкзака) и заказ;
## справа — рюкзак игрока (сырьё выбранного рецепта подсвечено). У печи — блок
## из 4 топливных слотов (уголь/дрова/брикеты горят разное время), у всех станков —
## состояние износа и ремонт. ESC — закрыть. Логика — production_machine.gd.

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const PM = preload("res://scripts/crafting/production_machine.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const RECIPE_COLS: int = 3
const RECIPE_CELL: Vector2 = Vector2(196, 64)

var machine: Node
var player: Node
var inventory: Node

var _recipes: Array = []
var _selected_recipe: Dictionary = {}

var _rebuild_box: VBoxContainer
var _rebuild_title: Label
var _rebuild_desc: Label
var _rebuild_perks: Label
var _rebuild_cost: Label
var _rebuild_btn: Button
var _production_box: VBoxContainer
var _bottom_row: HBoxContainer

var _title_label: Label
var _grid: ItemGrid
var _recipe_grid: GridContainer
var _recipe_name: Label
var _inputs_box: VBoxContainer
var _spin: SpinBox
var _info: Label
var _start_btn: Button
var _wear_label: Label
var _repair_btn: Button
var _repair_q_btn: Button
var _upgrade_btn: Button
var _upgrade_cost_label: Label
var _fuel_box: VBoxContainer
var _fuel_slot_btns: Array[Button] = []
var _fuel_status: Label
var _status_label: Label
var _progress: ProgressBar
var _cancel_btn: Button
var _out_grid: ItemGrid
var _collect_btn: Button
var _store_grid: ItemGrid
var _store_hint: Label
var _modal: Control
var _closing: bool = false
var _syncing: bool = false

func setup(p_machine: Node, p_player: Node) -> void:
	machine = p_machine
	player = p_player
	inventory = player.inventory if player and "inventory" in player else null

func _ready() -> void:
	AudioManager.play("ui_open")
	# Панель перехватывает игровой ввод — как storage_panel.
	add_to_group("ui_input_blockers")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(1200, 0)
	center.add_child(panel)
	var margin := UI.make_margin(16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title_label = UI.make_label("⚙️ %s" % str(machine.object_name if machine else "Станок"), 20, UI.COLOR_TITLE)
	header.add_child(_title_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	var close_btn := UI.make_button("✕", Vector2(40, 32))
	close_btn.tooltip_text = "Закрыть (ESC)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

# 1. Основная область: сетка рецептов + заказ + состояние (+ топливо у печи)
	var col_main := VBoxContainer.new()
	col_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col_main)

	# 1a. Карточка восстановления/постройки (видна, пока станок не готов).
	_rebuild_box = VBoxContainer.new()
	_rebuild_box.add_theme_constant_override("separation", 8)
	col_main.add_child(_rebuild_box)
	var rebuild_card := UI.make_panel(UI.COLOR_CARD, UI.COLOR_BORDER, 1)
	_rebuild_box.add_child(rebuild_card)
	var rebuild_margin := UI.make_margin(14)
	rebuild_card.add_child(rebuild_margin)
	var rebuild_col := VBoxContainer.new()
	rebuild_col.add_theme_constant_override("separation", 8)
	rebuild_margin.add_child(rebuild_col)
	_rebuild_title = UI.make_label("", 18, UI.COLOR_TITLE)
	_rebuild_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rebuild_col.add_child(_rebuild_title)
	_rebuild_desc = UI.make_label("", 14)
	_rebuild_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rebuild_desc.custom_minimum_size = Vector2(360, 0)
	rebuild_col.add_child(_rebuild_desc)
	_rebuild_perks = UI.make_label("", 13, UI.COLOR_MUTED)
	_rebuild_perks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rebuild_col.add_child(_rebuild_perks)
	_rebuild_cost = UI.make_label("", 14)
	_rebuild_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rebuild_col.add_child(_rebuild_cost)
	_rebuild_btn = UI.make_button("🔨 Восстановить", Vector2(0, 44), true, false, 16)
	_rebuild_btn.pressed.connect(_on_rebuild_pressed)
	rebuild_col.add_child(_rebuild_btn)

	_production_box = VBoxContainer.new()
	_production_box.add_theme_constant_override("separation", 8)
	col_main.add_child(_production_box)
	_production_box.add_child(UI.make_section_header("📜 Рецепты"))
	var rec_scroll := ScrollContainer.new()
	rec_scroll.custom_minimum_size = Vector2(RECIPE_COLS * RECIPE_CELL.x + 14, 4 * RECIPE_CELL.y + 14)
	rec_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_production_box.add_child(rec_scroll)
	_recipe_grid = GridContainer.new()
	_recipe_grid.columns = RECIPE_COLS
	_recipe_grid.add_theme_constant_override("h_separation", 8)
	_recipe_grid.add_theme_constant_override("v_separation", 8)
	_recipe_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_scroll.add_child(_recipe_grid)

	var card := UI.make_panel(UI.COLOR_CARD, UI.COLOR_BORDER, 1)
	_production_box.add_child(card)
	var cm := UI.make_margin(12)
	card.add_child(cm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	cm.add_child(col)
	_recipe_name = UI.make_label("", 16)
	_recipe_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_recipe_name)
	_inputs_box = VBoxContainer.new()
	_inputs_box.add_theme_constant_override("separation", 4)
	col.add_child(_inputs_box)

	var qty := HBoxContainer.new()
	qty.add_theme_constant_override("separation", 6)
	col.add_child(qty)
	qty.add_child(UI.make_label("Произвести:", 14))
	var minus := UI.make_button("−", Vector2(36, 32))
	minus.pressed.connect(func(): _spin.value -= _spin.step)
	qty.add_child(minus)
	_spin = SpinBox.new()
	_spin.rounded = true
	_spin.custom_minimum_size = Vector2(100, 32)
	_spin.value_changed.connect(_on_amount_changed)
	qty.add_child(_spin)
	var plus := UI.make_button("+", Vector2(36, 32))
	plus.pressed.connect(func(): _spin.value += _spin.step)
	qty.add_child(plus)
	var max_btn := UI.make_button("Макс", Vector2(64, 32))
	max_btn.pressed.connect(func(): _spin.value = _spin.max_value)
	qty.add_child(max_btn)

	_info = UI.make_label("", 13, UI.COLOR_MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(360, 0)
	col.add_child(_info)
	_start_btn = UI.make_button("▶ Старт", Vector2(0, 40), true, false, 16)
	_start_btn.pressed.connect(_on_start)
	col.add_child(_start_btn)

	# 2. Справа: рюкзак игрока
	var col_inv := VBoxContainer.new()
	body.add_child(col_inv)
	col_inv.add_child(UI.make_section_header("🎒 Рюкзак"))
	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(6 * 62 + 16, 440)
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_inv.add_child(inv_scroll)
	_grid = ItemGrid.new()
	_grid.columns = 6
	_grid.cell_size = Vector2(56, 56)
	_grid.cell_pressed.connect(_on_backpack_cell_pressed)
	inv_scroll.add_child(_grid)

	# 3. Нижняя строка: состояние, топливо, продукция
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	_bottom_row = bottom
	root.add_child(bottom)

	var col_state := VBoxContainer.new()
	col_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(col_state)
	col_state.add_child(UI.make_section_header("⏱ Состояние"))
	_wear_label = UI.make_label("", 14)
	_wear_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col_state.add_child(_wear_label)
	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override("separation", 6)
	col_state.add_child(repair_row)
	_repair_btn = UI.make_button("🔧 Ремонт (+50%)", Vector2(0, 32))
	_repair_btn.pressed.connect(func(): _on_repair_pressed(false))
	repair_row.add_child(_repair_btn)
	_repair_q_btn = UI.make_button("✨ Качественный ремонт (+70%)", Vector2(0, 32), true)
	_repair_q_btn.pressed.connect(func(): _on_repair_pressed(true))
	repair_row.add_child(_repair_q_btn)
	_upgrade_btn = UI.make_button("⬆ Улучшить станок", Vector2(0, 36), true)
	_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	col_state.add_child(_upgrade_btn)
	_upgrade_cost_label = UI.make_label("", 13, UI.COLOR_MUTED)
	_upgrade_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col_state.add_child(_upgrade_cost_label)
	_status_label = UI.make_label("", 14)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col_state.add_child(_status_label)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_CARD_EMPTY, UI.COLOR_BORDER, 1, 4))
	_progress.add_theme_stylebox_override("fill", UI.make_stylebox(UI.COLOR_ACCENT, Color(0, 0, 0, 0), 0, 4))
	col_state.add_child(_progress)
	_cancel_btn = UI.make_button("⏹ Отменить партию", Vector2(0, 34), false, true)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	col_state.add_child(_cancel_btn)

	if machine and machine.get("has_fuel_slots"):
		_fuel_box = VBoxContainer.new()
		_fuel_box.add_theme_constant_override("separation", 6)
		bottom.add_child(_fuel_box)
		_fuel_box.add_child(UI.make_section_header("⛽ Топливо — клик по слоту: добавить/забрать"))
		var fuel_row := HBoxContainer.new()
		fuel_row.add_theme_constant_override("separation", 6)
		_fuel_box.add_child(fuel_row)
		for i in int(machine.fuel_slot_count if "fuel_slot_count" in machine else PM.FUEL_SLOTS):
			var slot_btn := UI.make_button("", Vector2(56, 56))
			slot_btn.expand_icon = true
			slot_btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot_btn.pressed.connect(_on_fuel_slot_pressed.bind(i))
			fuel_row.add_child(slot_btn)
			_fuel_slot_btns.append(slot_btn)
		_fuel_status = UI.make_label("", 13, UI.COLOR_MUTED)
		_fuel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fuel_box.add_child(_fuel_status)
		var fill_btn := UI.make_button("⛽ Заправить из рюкзака", Vector2(0, 32), true)
		fill_btn.pressed.connect(_on_fuel_fill_pressed)
		_fuel_box.add_child(fill_btn)

	var col_out := VBoxContainer.new()
	bottom.add_child(col_out)
	col_out.add_child(UI.make_section_header("📦 Продукция в станке"))
	_out_grid = ItemGrid.new()
	_out_grid.columns = 5
	_out_grid.cell_size = Vector2(56, 56)
	_out_grid.cell_pressed.connect(_on_out_cell_pressed)
	col_out.add_child(_out_grid)
	_collect_btn = UI.make_button("📦 Забрать всё", Vector2(0, 34), true)
	_collect_btn.pressed.connect(_on_collect)
	col_out.add_child(_collect_btn)

	var col_store := VBoxContainer.new()
	bottom.add_child(col_store)
	col_store.add_child(UI.make_section_header("🗄 Склад станка (до 8 стеков)"))
	_store_hint = UI.make_label("Клик по рюкзаку — положить, клик по складу — забрать", 12, UI.COLOR_MUTED)
	_store_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col_store.add_child(_store_hint)
	_store_grid = ItemGrid.new()
	_store_grid.columns = 5
	_store_grid.cell_size = Vector2(56, 56)
	_store_grid.cell_pressed.connect(_on_store_cell_pressed)
	col_store.add_child(_store_grid)

	var footer := UI.make_label("Количество кратно выходу одного цикла · сырьё и энергия на всю партию списываются при старте · отмена не возвращает сырьё · ESC — закрыть", 13, UI.COLOR_DIM)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(footer)

	if inventory:
		inventory.inventory_updated.connect(_refresh)
	if machine:
		for sig in ["outputs_changed", "batch_finished", "batch_cancelled", "process_started", "machine_rebuilt", "storage_changed"]:
			if machine.has_signal(sig):
				machine.connect(sig, _on_machine_signal)
		if machine.has_signal("machine_upgraded"):
			machine.machine_upgraded.connect(_on_machine_upgraded)
	_load_recipes()
	if not _recipes.is_empty():
		_select_recipe(_recipes[0])
	else:
		_refresh()

func _on_machine_signal(_a = null, _b = null) -> void:
	_refresh()

## После улучшения: перечитываем рецепты (появляются рецепты со min_level)
## и обновляем заголовок, блок улучшения и характеристики.
func _on_machine_upgraded(_new_level: int) -> void:
	_load_recipes()
	if not _recipes.is_empty() and _selected_recipe.is_empty():
		_select_recipe(_recipes[0])
	_refresh()

func _load_recipes() -> void:
	_recipes.clear()
	if machine == null:
		return
	var list = RecipeDB.get_recipes_for_machine(machine.machine_type, machine.get_level())
	for r in list:
		if r is Dictionary and not r.is_empty():
			_recipes.append(r)
		elif r is String:
			var rd: Dictionary = RecipeDB.get_recipe(r)
			if not rd.is_empty():
				_recipes.append(rd)

## Сетка рецептов: карточки одного размера (иконка продукции, название, вход → выход),
## серые без сырья, выбранный рецепт выделен — как клетки рюкзака.
func _build_recipe_grid() -> void:
	for c in _recipe_grid.get_children():
		c.queue_free()
	for r in _recipes:
		var main_out: String = PM.get_main_output(r)
		var ins: PackedStringArray = []
		var inputs: Dictionary = r.get("inputs", {})
		for item_id in inputs.keys():
			ins.append("%d %s" % [int(inputs[item_id]), ItemDB.get_item_name(item_id)])
		var max_c: int = PM.get_max_cycles(r, inventory)
		var selected: bool = str(r.get("id", "")) == str(_selected_recipe.get("id", ""))
		var b := UI.make_button("", RECIPE_CELL, selected)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.tooltip_text = "%s\n%s → %s ×%d\nХватает сырья на %d цикл(ов)" % [
			str(r.get("name", r.get("id", ""))),
			", ".join(ins), ItemDB.get_item_name(main_out),
			PM.get_output_per_cycle(r), max_c
		]
		if max_c <= 0:
			b.add_theme_color_override("font_color", UI.COLOR_DIM)
		b.pressed.connect(_select_recipe.bind(r))
		var cell := VBoxContainer.new()
		cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 2)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = ItemIcons.get_texture(main_out)
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(icon)
		var name_l := UI.make_label(str(r.get("name", r.get("id", ""))), 13, UI.COLOR_TITLE if not selected else UI.COLOR_BG)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(name_l)
		cell.add_child(top)
		var bottom_l := UI.make_label("%s → %s×%d · %.0f с" % [", ".join(ins), ItemDB.get_item_icon(main_out), PM.get_output_per_cycle(r), float(r.get("duration", 6.0))], 12, UI.COLOR_MUTED if not selected else UI.COLOR_BG)
		bottom_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bottom_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bottom_l)
		b.add_child(cell)
		_recipe_grid.add_child(b)

func _select_recipe(recipe: Dictionary) -> void:
	AudioManager.play("ui_click")
	_selected_recipe = recipe
	var out: int = PM.get_output_per_cycle(recipe)
	_syncing = true
	_spin.min_value = out
	_spin.step = out
	_spin.max_value = out * maxi(1, PM.get_max_cycles(recipe, inventory))
	_spin.value = out
	_syncing = false
	_refresh()

func _cycles() -> int:
	if _selected_recipe.is_empty():
		return 0
	return PM.cycles_for_amount(_selected_recipe, int(_spin.value))

func _on_amount_changed(_v: float) -> void:
	if _syncing:
		return
	if not is_inside_tree() or inventory == null:
		return
	_refresh_order()

func _refresh() -> void:
	if not is_inside_tree() or inventory == null:
		return
	if not _refresh_rebuild():
		return
	_build_recipe_grid()
	if not _selected_recipe.is_empty():
		var out: int = PM.get_output_per_cycle(_selected_recipe)
		var keep: float = _spin.value
		_syncing = true
		_spin.max_value = out * maxi(1, PM.get_max_cycles(_selected_recipe, inventory))
		_spin.value = clampf(keep, _spin.min_value, _spin.max_value)
		_syncing = false
	var stacks: Array = []
	if machine:
		for item_id in machine.pending_outputs.keys():
			var n: int = int(machine.pending_outputs[item_id])
			if n > 0:
				stacks.append({"item_id": item_id, "count": n})
	_out_grid.set_stacks(stacks, maxi(5, stacks.size()))
	_collect_btn.disabled = stacks.is_empty()
	if _store_grid and machine and machine.has_method("get_storage_stacks"):
		_store_grid.set_stacks(machine.get_storage_stacks(), PM.MACHINE_STORAGE_MAX_STACKS)
	_refresh_wear()
	_refresh_fuel()
	_refresh_order()

func _refresh_wear() -> void:
	if machine == null or machine.wear == null:
		_wear_label.text = ""
		_repair_btn.visible = false
		_repair_q_btn.visible = false
		return
	var lvl: int = machine.get_level()
	_title_label.text = "⚙️ %s · Lv.%d" % [str(machine.object_name), lvl] if lvl > 1 else "⚙️ %s" % str(machine.object_name)
	_wear_label.text = machine.wear.get_status_text()
	_repair_btn.visible = true
	_repair_btn.disabled = machine.wear.get_ratio() >= 1.0
	_repair_btn.tooltip_text = "Восстанавливает +50%% состояния. %s. Детали переносятся в станок порциями." % _job_mats_text(machine, "repair")
	# Качественный ремонт: та же кнопка «на месте», но со стальной пластиной.
	_repair_q_btn.visible = true
	_repair_q_btn.disabled = machine.wear.get_ratio() >= 1.0
	_repair_q_btn.tooltip_text = "Стальные детали служат дольше: +70%% состояния. %s" % _job_mats_text(machine, "repair_q")
	_refresh_job_button(_repair_btn, "repair", "🔧 Ремонт (+50%)", machine)
	_refresh_job_button(_repair_q_btn, "repair_q", "✨ Качественный ремонт (+70%)", machine)
	_refresh_upgrade()

## Строка взноса компонента: «Камень: нужно 16» → «Камень: 8/16» → «Камень: 16/16 ✓».
func _contrib_line(item_id: String, need: int, inside: int) -> String:
	var head: String = "%s %s" % [ItemDB.get_item_icon(str(item_id)), ItemDB.get_item_name(str(item_id))]
	if inside <= 0:
		return "%s: нужно %d" % [head, need]
	if inside >= need:
		return "%s: %d/%d ✓" % [head, need, need]
	return "%s: %d/%d" % [head, inside, need]

## Краткая сводка взносов работы kind для подсказок: те же строки «нужно N → d/n → n/n ✓».
func _job_mats_text(machine: Node, kind: String) -> String:
	if machine == null or not machine.has_method("get_job_progress"):
		return ""
	var progress: Dictionary = machine.get_job_progress(kind)
	var mats: Dictionary = progress.get("materials", {})
	var parts: PackedStringArray = []
	for item_id in mats.keys():
		var pair: Array = mats[item_id]
		parts.append(_contrib_line(str(item_id), int(pair[1]), int(pair[0])))
	return "; ".join(parts) if not parts.is_empty() else "ничего"

## Кнопка переноса компонентов: показывает, сколько деталей уже внесено
## в станок (work идёт порциями, применяется по завершении комплекта).
func _refresh_job_button(btn: Button, kind: String, base_text: String, machine: Node) -> void:
	if btn == null or machine == null or not machine.has_method("get_job_progress"):
		return
	var progress: Dictionary = machine.get_job_progress(kind)
	var delivered: int = int(progress.get("delivered", 0))
	var need: int = int(progress.get("need", 0))
	if delivered > 0:
		btn.text = "%s (%d/%d)" % [base_text, delivered, need]
	else:
		btn.text = base_text

## Блок улучшения: доступен, пока станок не занят и есть следующий уровень.
func _refresh_upgrade() -> void:
	var can: bool = machine.can_upgrade()
	_upgrade_btn.visible = can
	_upgrade_cost_label.visible = can
	if not can:
		return
	var next_level: int = machine.get_level() + 1
	var cost: Dictionary = machine.get_upgrade_cost()
	var parts: PackedStringArray = []
	var progress: Dictionary = machine.get_job_progress("upgrade")
	var in_stash: Dictionary = progress.get("materials", {})
	for item_id in cost.keys():
		var need: int = int(cost[item_id])
		var inside: int = int(in_stash.get(item_id, [0, need])[0]) if in_stash.has(item_id) else 0
		parts.append(_contrib_line(str(item_id), need, inside))
	_upgrade_btn.disabled = machine.is_machine_running
	_upgrade_btn.text = "⬆ Внести детали (Lv.%d) %d/%d" % [next_level, int(progress.get("delivered", 0)), int(progress.get("need", 0))]
	_upgrade_cost_label.text = "  ·  ".join(parts)
	_upgrade_btn.tooltip_text = "Переносит детали в станок порциями. Когда комплект собран — станок улучшится до Lv.%d: циклы ×%.2f быстрее, износ меньше, ресурс больше, питание ×%.1f." % [
		next_level, machine.level_state.LEVEL_STATS[next_level]["speed"], machine.level_state.LEVEL_STATS[next_level]["power"]]

func _refresh_fuel() -> void:
	if _fuel_box == null or machine == null:
		return
	for i in _fuel_slot_btns.size():
		var slot: Dictionary = machine.fuel_slots[i] if i < machine.fuel_slots.size() else {"item_id": "", "count": 0}
		var fid: String = str(slot.get("item_id", ""))
		var btn: Button = _fuel_slot_btns[i]
		if fid != "" and int(slot.get("count", 0)) > 0:
			btn.icon = ItemIcons.get_texture(fid)
			btn.text = "×%d" % int(slot["count"])
			btn.tooltip_text = "%s %s ×%d (%d с/шт)\nКлик — забрать в рюкзак" % [
				ItemDB.get_item_icon(fid), ItemDB.get_item_name(fid), int(slot["count"]),
				int(machine.get_fuel_burn_time(fid))]
		else:
			btn.icon = null
			btn.text = "+"
			btn.tooltip_text = "Пустой топливный слот. Клик — положить топливо из рюкзака (%s)." % machine._fuel_list_text()
		btn.disabled = machine.is_machine_running and machine.active_fuel_slot == i and machine.fuel_burn_left > 0.0
	var burn: float = float(machine.fuel_burn_left)
	var total: float = machine.get_fuel_time_total()
	if total <= 0.0:
		_fuel_status.text = "⛔ Нет топлива! Печь стоит: добавьте уголь, дрова или брикеты."
		_fuel_status.add_theme_color_override("font_color", UI.COLOR_DANGER)
	else:
		var active_txt: String = "—"
		if machine.active_fuel_slot >= 0 and machine.active_fuel_slot < machine.fuel_slots.size():
			var af: String = str(machine.fuel_slots[machine.active_fuel_slot].get("item_id", ""))
			if af != "":
				active_txt = "%s %s" % [ItemDB.get_item_icon(af), ItemDB.get_item_name(af)]
		_fuel_status.text = "🔥 Горит: %s (ещё %s) · Запас горения: %s" % [active_txt, _fmt_time(burn), _fmt_time(total)]
		_fuel_status.add_theme_color_override("font_color", UI.COLOR_MUTED)

func _fmt_time(sec: float) -> String:
	var s: int = maxi(0, int(sec))
	return "%d:%02d" % [s / 60, s % 60]

## Состав заказа, подсветка сырья в рюкзаке и доступность «Старт».
func _refresh_order() -> void:
	if not is_inside_tree() or inventory == null:
		return
	for c in _inputs_box.get_children():
		# Убираем из дерева сразу: queue_free() отложенный, и на кадр в
		# списке оставались бы старые и новые строки.
		_inputs_box.remove_child(c)
		c.queue_free()
	_grid.highlight_items = {}
	if _selected_recipe.is_empty():
		_recipe_name.text = "У этого станка нет рецептов"
		_info.text = ""
		_start_btn.disabled = true
		_grid.set_stacks(inventory.get_slot_cells(), inventory.max_slots)
		return
	var cycles: int = _cycles()
	var enough_all: bool = cycles > 0
	_recipe_name.text = str(_selected_recipe.get("name", _selected_recipe.get("id", "")))
	var inputs: Dictionary = _selected_recipe.get("inputs", {})
	for item_id in inputs.keys():
		var need: int = int(inputs[item_id])
		var total: int = need * maxi(cycles, 1)
		var have: int = inventory.get_item_count(item_id)
		var ok: bool = have >= total
		enough_all = enough_all and ok
		_grid.highlight_items[item_id] = UI.COLOR_OK if ok else UI.COLOR_DANGER
		_inputs_box.add_child(_make_line(item_id, "%s: нужно %d  (есть %d)" % [ItemDB.get_item_name(item_id), total, have], UI.COLOR_OK if ok else UI.COLOR_DANGER))
	var outputs: Dictionary = _selected_recipe.get("outputs", {})
	for item_id in outputs.keys():
		_inputs_box.add_child(_make_line(item_id, "→ %s: %d шт." % [ItemDB.get_item_name(item_id), int(outputs[item_id]) * maxi(cycles, 1)], UI.COLOR_TITLE))
	_grid.set_stacks(inventory.get_slot_cells(), inventory.max_slots)

	var params: Dictionary = machine.get_cycle_params(_selected_recipe, player) if machine else {"duration": 0.0, "energy": 0.0}
	var energy_total: float = float(params["energy"]) * maxi(cycles, 1)
	var text: String = "Циклов: %d  ·  Время: %.0f с  ·  Энергия: %.0f" % [maxi(cycles, 1), float(params["duration"]) * maxi(cycles, 1), energy_total]
	if PM.get_max_cycles(_selected_recipe, inventory) <= 0:
		text += "\n❌ Не хватает сырья даже на один цикл."
	if player and "energy" in player and float(player.energy) < energy_total:
		text += "\n⚠️ Мало энергии: есть %.0f." % float(player.energy)
	if machine and machine.wear and machine.wear.is_broken():
		text += "\n⛔ Станок неисправен — нужен ремонт."
	if machine and machine.get("has_fuel_slots"):
		var need_fuel: float = float(params["duration"]) * maxi(cycles, 1)
		if machine.get_fuel_time_total() < need_fuel:
			text += "\n⛽ Не хватает топлива на партию (%s в слотах)." % _fmt_time(machine.get_fuel_time_total())
	_info.text = text
	var broken: bool = machine != null and machine.wear != null and machine.wear.is_broken()
	_start_btn.disabled = not enough_all or (machine and machine.is_machine_running) or broken
	_start_btn.text = "▶ Старт: %s ×%d" % [ItemDB.get_item_name(PM.get_main_output(_selected_recipe)), int(_spin.value)]

func _make_line(item_id: String, text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = ItemIcons.get_texture(item_id)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	row.add_child(icon)
	var l := UI.make_label(text, 14, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	return row

func _process(_delta: float) -> void:
	if machine == null or not is_instance_valid(machine):
		return
	if machine.is_machine_running:
		_progress.value = machine.get_progress()
		var r_name: String = str(machine.active_recipe.get("name", "Переработка"))
		if not machine.power_ok:
			_status_label.text = "⚡ Нет питания — цикл приостановлен"
		elif machine.get("has_fuel_slots") and machine.fuel_burn_left <= 0.0 and machine.get_fuel_time_total() <= 0.0:
			_status_label.text = "⛽ Нет топлива — цикл приостановлен"
		else:
			_status_label.text = "🔄 %s · цикл %d/%d · осталось %.0f с" % [r_name, machine.batch_cycles_done + 1, maxi(1, machine.batch_cycles_total), machine.get_batch_remaining_time()]
		_cancel_btn.visible = true
		_start_btn.disabled = true
		if machine.get("has_fuel_slots"):
			_refresh_fuel()
	else:
		_progress.value = 0.0
		_status_label.text = "✅ Станок свободен"
		_cancel_btn.visible = false

func _on_start() -> void:
	if machine == null or _selected_recipe.is_empty():
		return
	var cycles: int = _cycles()
	if cycles <= 0:
		return
	if machine.start_batch(str(_selected_recipe.get("id", "")), cycles, player):
		AudioManager.play("ui_click")
	_refresh()

## Готов ли станок к работе. Пока нет — показываем карточку восстановления
## и прячем производство, износ, топливо и продукцию.
func _refresh_rebuild() -> bool:
	if machine == null or not machine.has_method("is_operational"):
		return true
	var ready_state: bool = machine.is_operational()
	_rebuild_box.visible = not ready_state
	_production_box.visible = ready_state
	_bottom_row.visible = ready_state
	_collect_btn.disabled = true
	if ready_state:
		return true
	var info: Dictionary = machine.rebuild_info
	_rebuild_title.text = "🔨 %s — %s" % [str(machine.object_name), str(info.get("title", "Разрушена"))]
	_rebuild_desc.text = str(info.get("description", "Станок вышел из строя после бури. Его нужно восстановить, чтобы вернуться к работе."))
	_rebuild_perks.text = str(info.get("perks", "После восстановления: %s" % str(machine.machine_display_name)))
	var req: Dictionary = machine.get_rebuild_requirements()
	var progress: Dictionary = machine.get_job_progress("rebuild")
	var parts: PackedStringArray = []
	if int(req.get("credits", 0)) > 0:
		var have_cr: int = int(inventory.get("credits")) if "credits" in inventory else 0
		parts.append("💰 %d/%d кр." % [have_cr, int(req["credits"])])
	var mats: Dictionary = req.get("materials", {})
	var in_stash: Dictionary = progress.get("materials", {})
	for item_id in mats.keys():
		var need: int = int(mats[item_id])
		var inside: int = int(in_stash.get(item_id, [0, need])[0]) if in_stash.has(item_id) else 0
		parts.append(_contrib_line(str(item_id), need, inside))
	_rebuild_cost.text = "Нужно: " + ("  ·  ".join(parts) if not parts.is_empty() else "ничего")
	_rebuild_btn.text = "🔨 Внести компоненты (%d/%d)" % [int(progress.get("delivered", 0)), int(progress.get("need", 0))]
	_rebuild_btn.disabled = machine.is_operational()
	_rebuild_btn.tooltip_text = "Переносит в станок всё, что есть в рюкзаке. Когда комплект собран — станок автоматически восстановится."
	return false

func _on_rebuild_pressed() -> void:
	if machine == null:
		return
	if machine.rebuild(player):
		AudioManager.play("ui_click")
		_load_recipes()
		if not _recipes.is_empty():
			_select_recipe(_recipes[0])
	_refresh()

func _on_repair_pressed(quality: bool) -> void:
	if machine == null:
		return
	if machine.repair_machine(player, quality):
		AudioManager.play("ui_click")
	_refresh()

## Улучшение станка на месте: детали списываются, уровень растёт,
## рецепты перечитываются сигналом machine_upgraded.
func _on_upgrade_pressed() -> void:
	if machine == null:
		return
	if machine.upgrade_machine(player):
		AudioManager.play("ui_click")
	_refresh()

## Клик по топливному слоту: заполненный — забрать всё в рюкзак, пустой —
## положить первый подходящий вид топлива из рюкзака.
func _on_fuel_slot_pressed(slot_index: int) -> void:
	if machine == null or inventory == null:
		return
	var slot: Dictionary = machine.fuel_slots[slot_index] if slot_index < machine.fuel_slots.size() else {}
	if int(slot.get("count", 0)) > 0:
		machine.take_fuel_from_slot(slot_index, inventory)
	else:
		for fid in machine.FUEL_ITEMS:
			if inventory.get_item_count(fid) > 0:
				machine.add_fuel_from_inventory(inventory, fid, 1)
				break
	AudioManager.play("ui_click")
	_refresh()

## «Заправить из рюкзака»: заполняет слоты всеми видами топлива из рюкзака.
func _on_fuel_fill_pressed() -> void:
	if machine == null or inventory == null:
		return
	for fid in machine.FUEL_ITEMS:
		machine.add_fuel_from_inventory(inventory, fid)
	AudioManager.play("ui_click")
	_refresh()

func _on_cancel_pressed() -> void:
	if _modal and is_instance_valid(_modal):
		return
	var d = ConfirmDialog.new()
	d.setup("Остановить производство?", "Сырьё, потраченное на партию, не вернётся. Уже готовая продукция останется в станке.", "Остановить", true)
	d.confirmed.connect(func():
		if machine and is_instance_valid(machine):
			machine.cancel_batch()
		_refresh()
	)
	_modal = d
	add_child(d)

func _on_out_cell_pressed(item_id: String, _count: int, _index: int) -> void:
	if machine and player and not item_id.is_empty():
		if machine.has_method("collect_output_item"):
			machine.collect_output_item(item_id, player)
		else:
			machine.collect_outputs(player)
		AudioManager.play("ui_click")
		_refresh()

func _on_collect() -> void:
	if machine and player:
		machine.collect_outputs(player)
		AudioManager.play("ui_click")
	_refresh()

## Клик по клетке рюкзака — положить стек на склад станка.
func _on_backpack_cell_pressed(item_id: String, count: int, _index: int) -> void:
	if machine == null or player == null or item_id == "":
		return
	if not machine.has_method("store_from_player"):
		return
	var n: int = maxi(1, count)
	var got: int = machine.store_from_player(item_id, player, n)
	if got > 0:
		AudioManager.play("ui_click")
		if player.has_method("notify"):
			player.notify("🗄 На склад станка: %s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), got])
	_refresh()

## Клик по клетке склада — забрать стек в рюкзак.
func _on_store_cell_pressed(item_id: String, count: int, _index: int) -> void:
	if machine == null or player == null or item_id == "":
		return
	if not machine.has_method("take_stored"):
		return
	var got: int = machine.take_stored(item_id, player, maxi(1, count))
	if got > 0:
		AudioManager.play("ui_click")
	_refresh()

func _input(event: InputEvent) -> void:
	if _modal and is_instance_valid(_modal):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if get_viewport().gui_get_focus_owner() is LineEdit and code != KEY_ESCAPE:
		return
	if code in [KEY_ESCAPE, KEY_E] or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play("ui_close")
	closed.emit()
	queue_free()
