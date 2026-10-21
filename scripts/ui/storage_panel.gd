extends Control
## Две сетки: личный рюкзак и 20 ячеек склада. ЛКМ — количество, ПКМ — стек.
signal closed
signal repair_requested
const UI = preload('res://scripts/ui/ui_style.gd')
const Grid = preload('res://scripts/ui/item_grid.gd')
const Quantity = preload('res://scripts/ui/quantity_dialog.gd')
const Audio = preload('res://scripts/audio/audio_manager.gd')
const ItemDB = preload('res://scripts/inventory/item_db.gd')
var player: Node
var building: Node
var backpack_grid: GridContainer
var storage_grid: GridContainer
var fermentation_container: VBoxContainer
var status: Label
var capacity: Label
var weight: Label
var modal: Control
var _closing:=false
var _last_ferm_sec: int = -1
func setup(p: Node, b: Node) -> void:
	player=p;building=b
func _ready() -> void:

	add_to_group('ui_input_blockers')
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(center)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(850,550);center.add_child(scroll)
	var panel:=UI.make_panel(UI.COLOR_BG,UI.COLOR_ACCENT,2);panel.custom_minimum_size=Vector2(830,0);scroll.add_child(panel)
	var margin:=UI.make_margin(18);panel.add_child(margin)
	var v:=VBoxContainer.new();v.add_theme_constant_override('separation',12);margin.add_child(v)
	var head:=HBoxContainer.new();v.add_child(head);head.add_child(UI.make_label('📦 Склад продукции',20,UI.COLOR_TITLE))
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(spacer)
	var repair:=UI.make_button('Ремонт / улучшение',Vector2(170,32));repair.pressed.connect(func(): repair_requested.emit());head.add_child(repair)
	var x:=UI.make_button('×',Vector2(40,32));x.pressed.connect(close);head.add_child(x)
	var row:=HBoxContainer.new();row.add_theme_constant_override('separation',30);v.add_child(row)
	var left:=VBoxContainer.new();row.add_child(left);left.add_child(UI.make_label('Рюкзак → положить на склад',16,UI.COLOR_TITLE))
	weight=UI.make_label('',13);left.add_child(weight)
	backpack_grid=Grid.new();backpack_grid.columns=5;backpack_grid.name='BackpackGrid';left.add_child(backpack_grid)
	var right:=VBoxContainer.new();row.add_child(right);right.add_child(UI.make_label('Склад → забрать в рюкзак',16,UI.COLOR_TITLE))
	capacity=UI.make_label('',13);right.add_child(capacity)
	storage_grid=Grid.new();storage_grid.columns=5;storage_grid.name='StorageGrid';storage_grid.drag_enabled=true;right.add_child(storage_grid)
	storage_grid.cell_moved.connect(func(a,b): building.storage_inventory.move_slot(a,b))
	backpack_grid.cell_pressed.connect(_choose.bind(true));storage_grid.cell_pressed.connect(_choose.bind(false))
	backpack_grid.cell_right_clicked.connect(_quick.bind(true));storage_grid.cell_right_clicked.connect(_quick.bind(false))
	v.add_child(UI.make_label('ЛКМ: выбрать количество • ПКМ: перенести стек • ESC: закрыть',13,UI.COLOR_MUTED))
	status=UI.make_label('Хранилище отдельно от рюкзака; вес вещей на складе не нагружает персонажа.',13)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=720;v.add_child(status)
	
	v.add_child(HSeparator.new())
	v.add_child(UI.make_label('🍺 Бродильный цех (Бочки для созревания пива, вина и браги)',16,UI.COLOR_TITLE))
	fermentation_container = VBoxContainer.new()
	fermentation_container.add_theme_constant_override('separation', 6)
	v.add_child(fermentation_container)

	player.inventory.inventory_updated.connect(refresh)
	building.storage_inventory.inventory_updated.connect(refresh)
	building.stage_upgraded.connect(_stage_changed)
	if building.has_signal("fermentation_updated"):
		building.fermentation_updated.connect(refresh)
	refresh();Audio.play('ui_open')

func refresh() -> void:
	if _closing or not is_instance_valid(building): return
	backpack_grid.set_stacks(player.inventory.get_slot_cells(),player.inventory.max_slots)
	storage_grid.set_stacks(building.storage_inventory.get_slot_cells(),20)
	capacity.text='Ячейки: %d / 20'%building.storage_inventory.get_used_slots()
	weight.text='Ячейки: %d / %d • Вес: %.1f / %.1f кг'%[player.inventory.get_used_slots(),player.inventory.max_slots,player.inventory.get_total_weight(),player.inventory.max_weight]
	if not building.is_storage_ready(): status.text='Склад повреждён. Вещи сохранены; восстановите его до стадии 2.'
	_refresh_fermentation()

func _refresh_fermentation() -> void:
	if not is_instance_valid(fermentation_container) or not is_instance_valid(building):
		return
	for child in fermentation_container.get_children():
		# Убираем из дерева сразу: queue_free() отложенный, и на кадр в
		# контейнере оставались бы и старые, и новые строки.
		fermentation_container.remove_child(child)
		child.queue_free()
	
	if not "fermentation_slots" in building or not building.is_storage_ready():
		var disabled_lbl = UI.make_label("Бродильный цех доступен после восстановления склада до стадии 2.", 13, UI.COLOR_MUTED)
		fermentation_container.add_child(disabled_lbl)
		return
	
	var slots: Array = building.fermentation_slots
	for idx in range(slots.size()):
		var slot: Dictionary = slots[idx]
		var status_str: String = slot.get("status", "idle")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		
		var barrel_lbl := UI.make_label("🛢️ Бочка #%d:" % (idx + 1), 14, UI.COLOR_TITLE)
		barrel_lbl.custom_minimum_size.x = 90
		row.add_child(barrel_lbl)
		
		if status_str == "idle":
			var desc := UI.make_label("Свободна. Готова для сусла.", 13, UI.COLOR_DIM)
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(desc)
			
			var btn_pour := UI.make_button("Залить сусло", Vector2(130, 28))
			btn_pour.pressed.connect(_on_pour_pressed.bind(idx))
			row.add_child(btn_pour)
		elif status_str == "fermenting":
			var in_id: String = slot.get("input_item", "")
			var out_id: String = slot.get("output_item", "")
			var in_name: String = ItemDB.get_item_name(in_id)
			var out_name: String = ItemDB.get_item_name(out_id)
			var cur_t: float = float(slot.get("timer", 0.0))
			var dur: float = maxf(1.0, float(slot.get("duration", 50.0)))
			var left: int = maxi(0, int(dur - cur_t))
			
			var info_v := VBoxContainer.new()
			info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lbl_info := UI.make_label("Брожение: %s → %s (осталось %d с)" % [in_name, out_name, left], 13)
			info_v.add_child(lbl_info)
			
			var pbar := ProgressBar.new()
			pbar.max_value = 100.0
			pbar.value = (cur_t / dur) * 100.0
			pbar.custom_minimum_size = Vector2(240, 14)
			pbar.show_percentage = true
			info_v.add_child(pbar)
			row.add_child(info_v)
			
			var btn_cancel := UI.make_button("Отмена", Vector2(80, 28), false, true)
			btn_cancel.pressed.connect(func():
				building.cancel_fermentation(idx, player.inventory)
				refresh()
			)
			row.add_child(btn_cancel)
		elif status_str == "ready":
			var out_id: String = slot.get("output_item", "")
			var out_count: int = int(slot.get("output_count", 0))
			var out_name: String = ItemDB.get_item_name(out_id)
			var out_icon: String = ItemDB.get_item_icon(out_id)
			
			var desc := UI.make_label("✨ Готово к розливу: %s %s ×%d" % [out_icon, out_name, out_count], 13, UI.COLOR_OK)
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(desc)
			
			var btn_take := UI.make_button("В рюкзак", Vector2(100, 28), true)
			btn_take.pressed.connect(func():
				var taken: int = building.collect_fermentation(idx, player.inventory)
				if taken > 0:
					Audio.play("ui_click")
					status.text = "Получено: %s ×%d в рюкзак!" % [out_name, taken]
				else:
					status.text = "Рюкзак полон! Освободите место в рюкзаке."
				refresh()
			)
			row.add_child(btn_take)

			var btn_to_storage := UI.make_button("На склад", Vector2(100, 28))
			btn_to_storage.pressed.connect(func():
				var taken: int = building.collect_fermentation(idx, building.storage_inventory)
				if taken > 0:
					Audio.play("ui_click")
					status.text = "Перемещено: %s ×%d прямо на склад!" % [out_name, taken]
				else:
					status.text = "Склад полон! Заберите в рюкзак."
				refresh()
			)
			row.add_child(btn_to_storage)
		
		fermentation_container.add_child(row)

func _on_pour_pressed(slot_idx: int) -> void:
	if not is_instance_valid(building) or not is_instance_valid(player):
		return
	var inv: Node = player.inventory
	var fermentables: Array[String] = []
	for it_id in ["beer_wort_boiled", "berry_must", "grain_wash"]:
		if inv.get_item_count(it_id) > 0:
			fermentables.append(it_id)
	
	if fermentables.is_empty():
		status.text = "⚠️ В рюкзаке нет сусла! Сварите охмелённое сусло на костре, сожмите ягоды или зерно на верстаке."
		Audio.play("ui_error")
		return
	
	var chosen: String = fermentables[0]
	var ok: bool = building.start_fermentation(slot_idx, chosen, 1, inv)
	if ok:
		Audio.play("ui_click")
		status.text = "Залито в бочку #%d: %s (1 шт). Брожение началось!" % [slot_idx + 1, ItemDB.get_item_name(chosen)]
		refresh()

func _stage_changed(_b: Node, _s: int) -> void:
	refresh()

func _process(_delta: float) -> void:
	if not is_instance_valid(building): close();return
	if not building.is_storage_ready():
		if is_instance_valid(modal): modal.queue_free();modal=null
		# Полный пересбор панелей делаем не каждый кадр (это пересоздаёт
		# сотни узлов), а по сигналам инвентаря и смены стадии.
		if status:
			var msg := 'Склад повреждён. Вещи сохранены; восстановите его до стадии 2.'
			if status.text != msg:
				status.text = msg
		return
	# Периодическое обновление прогресс-баров брожения раз в секунду
	var sec = int(Time.get_ticks_msec() / 1000.0)
	if sec != _last_ferm_sec:
		_last_ferm_sec = sec
		var has_active = false
		for s in building.fermentation_slots:
			if s.get("status", "") == "fermenting":
				has_active = true
				break
		if has_active:
			_refresh_fermentation()

func _choose(id: String, count: int, _index: int, deposit_: bool) -> void:
	if is_instance_valid(modal) or not building.is_storage_ready(): return
	modal=Quantity.new();modal.setup('Положить на склад' if deposit_ else 'Забрать со склада',id,count,count,'Перенести')
	modal.confirmed.connect(func(n): _move(id,n,deposit_);modal=null)
	modal.cancelled.connect(func(): modal=null)
	add_child(modal)
func _quick(id: String, count: int, _index: int, deposit_: bool) -> void:
	if not is_instance_valid(modal): _move(id,count,deposit_)
func _move(id: String, count: int, deposit_: bool) -> void:
	var n: int=building.deposit(player.inventory,id,count) if deposit_ else building.withdraw(player.inventory,id,count)
	refresh()
	status.text='Перенесено: %d из %d. Остаток остаётся на прежнем месте.'%[n,count] if n<count else 'Перенесено: %d.'%n
	if n>0: Audio.play('ui_click')
func _input(event: InputEvent) -> void:
	if not is_instance_valid(modal):
		if event.is_action_pressed("toggle_inventory") and not event.is_echo():
			get_viewport().set_input_as_handled()
			close()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if code in [KEY_ESCAPE, KEY_TAB, KEY_I]:
				get_viewport().set_input_as_handled()
				close()
func close() -> void:
	if _closing: return
	_closing=true
	closed.emit();queue_free()
