extends SceneTree
const Save = preload('res://scripts/core/save_manager.gd')
const Warehouse = preload('res://scripts/inventory/warehouse_inventory.gd')
const PATH := 'user://test_storage_inventory.json'
var errors: Array[String]=[]
var world: Node3D
func check(ok: bool, msg: String) -> void:
	if not ok:errors.append(msg);printerr('FAIL: '+msg)
func _initialize() -> void:
	world=load('res://scenes/world/world.tscn').instantiate();root.add_child(world);call_deferred('run_checks')
func run_checks() -> void:
	for i in 4:await process_frame
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var b=world.get_node('Props/RepairableStorage');var p=world.get_node('Player');var inv=p.inventory;var store=b.storage_inventory
	check(store!=inv and store.max_slots==20,'Independent 20-cell storage')
	inv.clear();inv.add_item('stone',250)
	for stage in [0,1]:
		b.current_stage=stage;check(b.deposit(inv,'stone',10)==0,'Storage locked until warehouse repaired')
	b.current_stage=2;b._update_visuals()
	var weight_before:float=inv.get_total_weight()
	check(b.deposit(inv,'stone',150)==150,'Deposit spans two stacks')
	check(inv.get_item_count('stone')==100 and store.get_item_count('stone')==150,'No item loss or duplication')
	check(inv.get_total_weight()<weight_before,'Stored goods do not weigh down backpack')
	check(store.get_slot_cells().size()==20 and store.get_used_slots()==3,'Exactly 20 cells including empty slots')
	check(b.withdraw(inv,'stone',30)==30 and store.get_item_count('stone')==120,'Withdraw transaction')
	store.move_slot(0,19)
	var layout: Array=store.get_slot_cells().duplicate(true)
	check(Save.save_game(world,PATH),'Save storage')
	store.clear();b.current_stage=0;b._update_visuals()
	check(Save.load_game(world,PATH),'Load storage')
	check(b.current_stage==2 and store.get_slot_cells()==layout,'Contents and cell positions restored')
	# Fill all 20 slots with stone; only the partial last stack can accept more.
	store.clear();inv.clear();inv.max_slots=40;inv.add_item('stone',1010)
	var stack:int=store.get_max_stack('stone')
	check(b.deposit(inv,'stone',20*stack-2)==20*stack-2,'Fill nearly all 20 slots')
	check(b.deposit(inv,'stone',10)==2,'Partial deposit into full storage, no 21st slot')
	var left:int=inv.get_item_count('stone')
	check(b.deposit(inv,'stone',10)==0 and inv.get_item_count('stone')==left,'Full storage does not consume source')
	inv.clear();inv.max_slots=1;inv.add_item('wood',inv.get_max_stack('wood'))
	var before:int=store.get_item_count('stone')
	check(b.withdraw(inv,'stone',1)==0 and store.get_item_count('stone')==before,'Full backpack does not consume stored goods')
	inv.clear();inv.add_item('stone',stack-3)
	check(b.withdraw(inv,'stone',10)==3,'Partial withdrawal respects backpack slots')
	b.current_stage=1
	check(b.withdraw(inv,'stone',1)==0,'Damaged warehouse keeps goods but blocks access')
	check(store.get_item_count('stone')==before-3,'Downgrade does not erase stored goods')
	check(Save.save_game(world,PATH),'Save inaccessible contents')
	store.clear();check(Save.load_game(world,PATH),'Reload damaged warehouse')
	check(store.get_item_count('stone')==before-3 and not b.is_storage_ready(),'Goods persist through damage and save')
	# Reject invalid inventory before touching even unrelated player fields.
	var file:=FileAccess.open(PATH,FileAccess.READ);var data:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	for bad in [{'items':{'stone':20*stack+1}}, {'items':{'stone':-1}}, {'items':{'stone':1.5}}, {'items':{'bad_item':1}}, {'items':{'stone':1e30}}, {'items':{'stone':1},'slot_layout':['bad_item']}, {'slot_layout':range(21)}, []]:
		data['buildings']['storage_inventory']=bad;data['player']['energy']=1
		file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close();p.energy=77
		check(not Save.load_game(world,PATH) and p.energy==77,'Invalid storage rejected atomically')
	data['buildings'].erase('storage_inventory')
	file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(Save.load_game(world,PATH) and store.get_used_slots()==0,'Old save produces empty warehouse, not duplicates')
	# Repair costs and capacity bonuses remain unchanged.
	inv.clear();inv.credits=500;inv.max_slots=40
	for id in ['wood','stone','poor_brick','mortar','fired_brick','iron_plate','gear','stone_dust']: inv.add_item(id,40)
	b.current_stage=0;b._update_visuals()
	for cost in [15,45,100]:
		var cr:int=inv.credits
		check(b.upgrade(p) and inv.credits==cr-cost,'Original repair cost retained')
	check(store.max_slots==20 and b.get_weight_bonus()==35,'Final stage: 20 cells plus existing 35kg bonus')
	# UI route, cell count, motion lock, return to repair, and reopening inventory.
	var controller=preload('res://scripts/ui/gameplay_ui_controller.gd').new()
	controller.name='GameplayUIController'
	controller.setup(world.get_node('HUD'),world,p)
	world.get_node('HUD').add_child(controller)
	var panel=controller.open_storage_panel(b)
	check(panel!=null and panel.storage_grid.get_visible_cell_count()==20,'20 visible storage cells')
	check(p.process_mode==Node.PROCESS_MODE_DISABLED,'Movement blocked while storage panel is open')
	panel._move('wood',10,true)
	check(store.get_item_count('wood')==10,'UI deposits actual goods')
	panel.repair_requested.emit()
	check(not controller.is_panel_open(),'Repair button closes inventory')
	var hud=controller.hud
	check(hud.repair_window.visible and hud.repair_storage_button.visible,'Repair window offers return to storage')
	hud.repair_storage_button.pressed.emit()
	check(controller.is_panel_open(),'Reopen warehouse from repair window')
	controller.close_panel()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if errors.is_empty():print('PASS: test_storage_inventory')
	quit(0 if errors.is_empty() else 1)
