extends Control

## Окно станка: слева — рюкзак игрока (сырьё выбранного рецепта подсвечено),
## в центре — рецепты, справа — заказ: сколько единиц продукции произвести
## (кратно выходу одного цикла), «Старт» списывает сырьё на всю партию.
## Ниже — ход партии, отмена (без возврата сырья) и готовая продукция в станке.
## ESC — закрыть. Логика партий — production_machine.gd (start_batch / cancel_batch).

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const PM = preload("res://scripts/crafting/production_machine.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

var machine: Node
var player: Node
var inventory: Node

var _recipes: Array = []
var _selected_recipe: Dictionary = {}

var _grid: GridContainer
var _recipe_list: VBoxContainer
var _recipe_name: Label
var _inputs_box: VBoxContainer
var _spin: SpinBox
var _info: Label
var _start_btn: Button
var _status_label: Label
var _progress: ProgressBar
var _cancel_btn: Button
var _out_grid: GridContainer
var _collect_btn: Button
var _modal: Control
var _closing: bool = false
var _syncing: bool = false

func setup(p_machine: Node, p_player: Node) -> void:
	machine = p_machine
	player = p_player
	inventory = player.inventory if player and "inventory" in player else null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(1080, 0)
	center.add_child(panel)
	var margin := UI.make_margin(16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	
	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(UI.make_label("⚙️ %s" % str(machine.object_name if machine else "Станок"), 20, UI.COLOR_TITLE))
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
	
	# 1. Рюкзак
	var col_inv := VBoxContainer.new()
	body.add_child(col_inv)
	col_inv.add_child(UI.make_section_header("🎒 Рюкзак"))
	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(4 * 62 + 16, 440)
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_inv.add_child(inv_scroll)
	_grid = ItemGrid.new()
	_grid.columns = 4
	_grid.cell_size = Vector2(56, 56)
	inv_scroll.add_child(_grid)
	
	# 2. Рецепты
	var col_rec := VBoxContainer.new()
	body.add_child(col_rec)
	col_rec.add_child(UI.make_section_header("📜 Рецепты"))
	var rec_scroll := ScrollContainer.new()
	rec_scroll.custom_minimum_size = Vector2(320, 440)
	rec_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_rec.add_child(rec_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 6)
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_scroll.add_child(_recipe_list)
	
	# 3. Заказ и состояние
	var card := UI.make_panel(UI.COLOR_CARD, UI.COLOR_BORDER, 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var cm := UI.make_margin(12)
	card.add_child(cm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	cm.add_child(col)
	col.add_child(UI.make_section_header("🏭 Заказ"))
	_recipe_name = UI.make_label("", 15)
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
	_info.custom_minimum_size = Vector2(340, 0)
	col.add_child(_info)
	_start_btn = UI.make_button("▶ Старт", Vector2(0, 40), true, false, 16)
	_start_btn.pressed.connect(_on_start)
	col.add_child(_start_btn)
	
	col.add_child(UI.make_section_header("⏱ Состояние"))
	_status_label = UI.make_label("", 13)
	col.add_child(_status_label)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.add_theme_stylebox_override("background", UI.make_stylebox(UI.COLOR_CARD_EMPTY, UI.COLOR_BORDER, 1, 4))
	_progress.add_theme_stylebox_override("fill", UI.make_stylebox(UI.COLOR_ACCENT, Color(0, 0, 0, 0), 0, 4))
	col.add_child(_progress)
	_cancel_btn = UI.make_button("⏹ Отменить партию", Vector2(0, 34), false, true)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	col.add_child(_cancel_btn)
	
	col.add_child(UI.make_section_header("📦 Готовая продукция в станке"))
	_out_grid = ItemGrid.new()
	_out_grid.columns = 5
	_out_grid.cell_size = Vector2(56, 56)
	col.add_child(_out_grid)
	_collect_btn = UI.make_button("📦 Забрать всё", Vector2(0, 34), true)
	_collect_btn.pressed.connect(_on_collect)
	col.add_child(_collect_btn)
	
	root.add_child(UI.make_label("Количество кратно выходу одного цикла · сырьё и энергия на всю партию списываются при старте · отмена не возвращает сырьё · ESC — закрыть", 12, UI.COLOR_DIM))
	
	if inventory:
		inventory.inventory_updated.connect(_refresh)
	if machine:
		for sig in ["outputs_changed", "batch_finished", "batch_cancelled", "process_started"]:
			if machine.has_signal(sig):
				machine.connect(sig, _on_machine_signal)
	_load_recipes()
	if not _recipes.is_empty():
		_select_recipe(_recipes[0])
	else:
		_refresh()

func _on_machine_signal(_a = null, _b = null) -> void:
	_refresh()

func _load_recipes() -> void:
	_recipes.clear()
	if machine == null:
		return
	var list = RecipeDB.get_recipes_for_machine(machine.machine_type)
	for r in list:
		if r is Dictionary and not r.is_empty():
			_recipes.append(r)
		elif r is String:
			var rd: Dictionary = RecipeDB.get_recipe(r)
			if not rd.is_empty():
				_recipes.append(rd)

func _build_recipe_cards() -> void:
	for c in _recipe_list.get_children():
		c.queue_free()
	for r in _recipes:
		var main_out: String = PM.get_main_output(r)
		var ins: PackedStringArray = []
		var inputs: Dictionary = r.get("inputs", {})
		for item_id in inputs.keys():
			ins.append("%s×%d" % [ItemDB.get_item_name(item_id), int(inputs[item_id])])
		var max_c: int = PM.get_max_cycles(r, inventory)
		var text: String = "%s\n%s → %s×%d · %.0f с" % [str(r.get("name", r.get("id", ""))), ", ".join(ins), ItemDB.get_item_name(main_out), PM.get_output_per_cycle(r), float(r.get("duration", 6.0))]
		var selected: bool = str(r.get("id", "")) == str(_selected_recipe.get("id", ""))
		var b := UI.make_button(text, Vector2(300, 58), selected, false, 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = ItemIcons.get_texture(main_out)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 36)
		b.tooltip_text = "Хватает сырья на %d цикл(ов)" % max_c
		if max_c <= 0:
			b.add_theme_color_override("font_color", UI.COLOR_DIM)
		b.pressed.connect(_select_recipe.bind(r))
		_recipe_list.add_child(b)

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
	_refresh_order()

func _refresh() -> void:
	if not is_inside_tree() or inventory == null:
		return
	_build_recipe_cards()
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
	_refresh_order()

## Состав заказа, подсветка сырья в рюкзаке и доступность «Старт».
func _refresh_order() -> void:
	for c in _inputs_box.get_children():
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
		_inputs_box.add_child(_make_line(item_id, "%s: %d × %d = %d  (есть %d)" % [ItemDB.get_item_name(item_id), need, maxi(cycles, 1), total, have], UI.COLOR_OK if ok else UI.COLOR_DANGER))
	var outputs: Dictionary = _selected_recipe.get("outputs", {})
	for item_id in outputs.keys():
		_inputs_box.add_child(_make_line(item_id, "→ %s ×%d" % [ItemDB.get_item_name(item_id), int(outputs[item_id]) * maxi(cycles, 1)], UI.COLOR_TITLE))
	_grid.set_stacks(inventory.get_slot_cells(), inventory.max_slots)
	
	var params: Dictionary = machine.get_cycle_params(_selected_recipe, player) if machine else {"duration": 0.0, "energy": 0.0}
	var energy_total: float = float(params["energy"]) * maxi(cycles, 1)
	var text: String = "Циклов: %d  ·  Время: %.0f с  ·  Энергия: %.0f" % [maxi(cycles, 1), float(params["duration"]) * maxi(cycles, 1), energy_total]
	if PM.get_max_cycles(_selected_recipe, inventory) <= 0:
		text += "\n❌ Не хватает сырья даже на один цикл."
	if player and "energy" in player and float(player.energy) < energy_total:
		text += "\n⚠️ Мало энергии: есть %.0f." % float(player.energy)
	_info.text = text
	_start_btn.disabled = not enough_all or (machine and machine.is_machine_running)
	_start_btn.text = "▶ Старт: %s ×%d" % [ItemDB.get_item_name(PM.get_main_output(_selected_recipe)), int(_spin.value)]

func _make_line(item_id: String, text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = ItemIcons.get_texture(item_id)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	row.add_child(UI.make_label(text, 13, color))
	return row

func _process(_delta: float) -> void:
	if machine == null or not is_instance_valid(machine):
		return
	if machine.is_machine_running:
		_progress.value = machine.get_progress()
		var r_name: String = str(machine.active_recipe.get("name", "Переработка"))
		_status_label.text = "🔄 %s · цикл %d/%d · осталось %.0f с" % [r_name, machine.batch_cycles_done + 1, maxi(1, machine.batch_cycles_total), machine.get_batch_remaining_time()]
		_cancel_btn.visible = true
		_start_btn.disabled = true
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

func _on_collect() -> void:
	if machine and player:
		machine.collect_outputs(player)
	_refresh()

func _input(event: InputEvent) -> void:
	if _modal and is_instance_valid(_modal):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit and event.keycode != KEY_ESCAPE:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play("ui_click")
	closed.emit()
	queue_free()
