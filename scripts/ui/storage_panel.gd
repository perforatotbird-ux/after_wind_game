extends Control
## Две сетки: личный рюкзак и 20 ячеек склада. ЛКМ — количество, ПКМ — стек.
signal closed
signal repair_requested
const UI = preload('res://scripts/ui/ui_style.gd')
const Grid = preload('res://scripts/ui/item_grid.gd')
const Quantity = preload('res://scripts/ui/quantity_dialog.gd')
const Audio = preload('res://scripts/audio/audio_manager.gd')
var player: Node
var building: Node
var backpack_grid: GridContainer
var storage_grid: GridContainer
var status: Label
var capacity: Label
var weight: Label
var modal: Control
var _closing:=false
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
	player.inventory.inventory_updated.connect(refresh)
	building.storage_inventory.inventory_updated.connect(refresh)
	building.stage_upgraded.connect(_stage_changed)
	refresh();Audio.play('ui_open')
func refresh() -> void:
	if _closing or not is_instance_valid(building): return
	backpack_grid.set_stacks(player.inventory.get_slot_cells(),player.inventory.max_slots)
	storage_grid.set_stacks(building.storage_inventory.get_slot_cells(),20)
	capacity.text='Ячейки: %d / 20'%building.storage_inventory.get_used_slots()
	weight.text='Ячейки: %d / %d • Вес: %.1f / %.1f кг'%[player.inventory.get_used_slots(),player.inventory.max_slots,player.inventory.get_total_weight(),player.inventory.max_weight]
	if not building.is_storage_ready(): status.text='Склад повреждён. Вещи сохранены; восстановите его до стадии 2.'
func _stage_changed(_b: Node, _s: int) -> void:
	refresh()
func _process(_delta: float) -> void:
	if not is_instance_valid(building): close();return
	if not building.is_storage_ready():
		if is_instance_valid(modal): modal.queue_free();modal=null
		refresh()
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_TAB,KEY_I] and not is_instance_valid(modal):
		get_viewport().set_input_as_handled();close()
func close() -> void:
	if _closing: return
	_closing=true
	closed.emit();queue_free()
