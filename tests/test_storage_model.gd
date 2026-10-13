extends SceneTree
## Новый склад по двум референсам: четыре стадии, архитектура, фонари, подъёмник.
const Decor = preload('res://scripts/world/meadow_decor.gd')
var errors: Array[String]=[]
var world: Node3D
class CycleStub extends Node:
	var night:=false
	func is_night() -> bool:return night
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message);printerr('FAIL: '+message)
func _initialize() -> void:
	world=load('res://scenes/world/world.tscn').instantiate();root.add_child(world)
	call_deferred('run_checks')
func triangles(mesh: Mesh) -> int:
	var total:=0
	for s in mesh.get_surface_count():total+=mesh.surface_get_array_index_len(s)/3
	return total
func run_checks() -> void:
	for i in 4:await process_frame
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var storage=world.get_node('Props/RepairableStorage')
	var cycle:=CycleStub.new();root.add_child(cycle)
	check(storage is RepairableBuilding and storage.building_id=='storage','Existing upgrade system retained')
	var box:BoxShape3D=storage.get_node('StaticBody3D/SolidShape').shape
	check(box.size.is_equal_approx(Vector3(4.6,4.6,3.8)),'Collision fits warehouse')
	for state in range(4):
		storage.current_stage=state;storage._update_visuals()
		var footprint: Rect2=Decor.node_footprint(storage)
		for neighbor in ['RepairableHouse','Smelter','KitchenStove','StoneCrusher','Workbench','DispatchStation','BatteryBank']:
			check(not footprint.intersects(Decor.node_footprint(world.get_node('Props/'+neighbor))), 'Warehouse does not overlap '+neighbor+' at stage '+str(state))
		var model=storage.get_node('Visuals/Stage%d'%state)
		model._day_cycle=cycle;model.update_environment()
		for k in range(4):check(storage.get_node('Visuals/Stage%d'%k).visible==(state==k),'Only one visible state')
		var total:=0;var bounds:=AABB();var first:=true
		for mi in model.find_children('*','MeshInstance3D',false,false):
			check(mi.mesh is ArrayMesh,'Real mesh '+mi.name)
			total+=triangles(mi.mesh)
			var b: AABB=mi.transform*mi.get_aabb();bounds=b if first else bounds.merge(b);first=false
			for s in mi.mesh.get_surface_count():
				var a=mi.mesh.surface_get_arrays(s)
				check(a[Mesh.ARRAY_TEX_UV]!=null and a[Mesh.ARRAY_NORMAL]!=null and a[Mesh.ARRAY_TANGENT]!=null,'UV normals tangents '+mi.name)
				var mat=mi.mesh.surface_get_material(s)
				check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo,'PBR per-piece tint '+mi.name)
		check(total>20000 and total<60000,'Triangle budget 20–60k')
		check(bounds.position.y>-.12 and bounds.size.y>4.0 and bounds.size.y<4.9,'Ground and height')
		check(bounds.size.x<6 and bounds.size.z<6,'Fits the base')
		check(model.get_node('Roof').visible==(state!=1),'Roof replaced by canvas at stage 1')
		check(model.get_node('Tarp').visible==(state==1),'Canvas only in cleared-frame stage')
		check(model.get_node('Shell').visible==(state!=1),'Cleared frame has no damaged walls')
		if state<2:check(model.get_node('Debris').visible==(state==0),'Rubble cleared by repair')
		if state>=2:
			check(model.lantern_lights.size()==2,'Two lanterns')
			check(not model.lantern_lights[0].visible,'Lantern light off by day')
			cycle.night=true;model.update_environment()
			check(model.lantern_lights[0].visible,'Lanterns lit at night')
			cycle.night=false;model.update_environment()
		check(storage.get_weight_bonus()==[0.0,10.0,20.0,35.0][state],'Old weight bonuses retained')
	var ruined=storage.get_node('Visuals/Stage0');var repaired=storage.get_node('Visuals/Stage2')
	check(triangles(ruined.get_node('Roof').mesh)<triangles(repaired.get_node('Roof').mesh),'Actual holes in ruined roof')
	check(repaired.get_node('Goods').get_aabb().size.y>1.5,'Interior shelves, crates and barrels')
	var hoist=storage.get_node('Visuals/Stage3/HoistAnimator')
	check(hoist!=null,'Animated hoist retained on final stage')
	hoist.time=0;hoist._apply()
	var hook=storage.get_node('Visuals/Stage3/Hook');var bottom:float=hook.position.y
	hoist.time=hoist.cycle_time*.5;hoist._apply()
	check(is_equal_approx(hoist.lift,hoist.lift_height) and absf(hook.position.y-bottom-hoist.lift_height)<.004,'Cargo lifted by 0.45m')
	check(absf(storage.get_node('Visuals/Stage3/Gear').rotation.z)>1,'Pulley rotates')
	for file in DirAccess.get_files_at('res://assets/models/warehouse'):
		if file.ends_with('.tres'):check(FileAccess.get_file_as_bytes('res://assets/models/warehouse/'+file).size()<1024*1024,'Text resource <1MiB '+file)
	cycle.free()
	if errors.is_empty():print('PASS: test_storage_model')
	quit(0 if errors.is_empty() else 1)
