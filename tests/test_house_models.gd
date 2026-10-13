extends SceneTree
## Дома по референсам: геометрия, четыре стадии, эффекты, ремонт и сохранения.
const Save = preload('res://scripts/core/save_manager.gd')
const SAVE_PATH := 'user://test_house_models.json'
class CycleStub extends Node:
	var night := false
	func is_night() -> bool: return night
var errors: Array[String] = []
var world: Node3D
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr('FAIL: '+message)
func _initialize() -> void:
	world=load('res://scenes/world/world.tscn').instantiate()
	root.add_child(world)
	call_deferred('run_checks')
func triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count(): count += mesh.surface_get_array_index_len(s)/3
	return count
func run_checks() -> void:
	for i in 4: await process_frame
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var h=world.get_node('Props/RepairableHouse')
	var player=world.get_node('Player')
	var cycle:=CycleStub.new(); root.add_child(cycle)
	check(h.building_id=='house' and h is RepairableBuilding,'Existing building mechanics connected')
	check(h.global_position.is_equal_approx(Vector3(-6.2,0,-5.5)),'House location unchanged')
	var box: BoxShape3D=h.get_node('StaticBody3D/SolidShape').shape
	check(box.size.is_equal_approx(Vector3(5.8,4.8,4.1)),'Solid collision fits the cottage')
	check(h.has_node('StaticBody3D/FrontStep'),'Front step collision exists')
	for state in range(4):
		print('CHECK STAGE ',state)
		h.current_stage=state;h._update_visuals()
		var model=h.get_node('Visuals/Stage%d'%state)
		model._day_cycle=cycle
		model.update_environment()
		for k in range(4):
			var other=h.get_node('Visuals/Stage%d'%k)
			other._day_cycle=cycle;other.update_environment()
			check(other.visible==(k==state),'Exactly one visible stage %d'%state)
		var total:=0;var bounds:=AABB();var first:=true
		for mi in model.find_children('*','MeshInstance3D',false,false):
			check(mi.mesh is ArrayMesh,'No placeholder primitive '+mi.name)
			total+=triangles(mi.mesh)
			var b: AABB=mi.transform*mi.get_aabb()
			bounds=b if first else bounds.merge(b);first=false
			for s in mi.mesh.get_surface_count():
				var a=mi.mesh.surface_get_arrays(s)
				check(a[Mesh.ARRAY_TEX_UV]!=null and a[Mesh.ARRAY_NORMAL]!=null and a[Mesh.ARRAY_TANGENT]!=null,'UV, normals and tangents '+mi.name)
				var mat=mi.mesh.surface_get_material(s)
				check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo,'PBR and per-piece tint '+mi.name)
		check(total>20000 and total<40000,'20–40k triangle budget')
		check(bounds.position.y>-.1 and bounds.size.y>4.6 and bounds.size.y<5.8,'House rests on ground, correct height')
		check(bounds.size.x<7.8 and bounds.size.z<6.8,'Footprint fits base')
		check(model.get_node('Roof').visible==(state!=1),'Roof hidden under emergency tarp')
		check(model.get_node('Tarp').visible==(state==1),'Tarp only after clearing')
		if state<2:check(model.get_node('Debris').visible==(state==0),'Debris removed after first repair')
		check(h.can_sleep()==(state>=1),'Sleep unlock preserved')
		check(is_equal_approx(h.get_weight_bonus(),15.0 if state==3 else 0.0),'Weight bonus preserved')
		if state>=2:
			check(model.smoke!=null and model.smoke.emitting==(state==3),'Smoke only at final residence')
			check(model.smoke.mesh.material.albedo_texture!=null,'Soft textured smoke')
			check(model.window_lights.size()==2,'Two window lights')
			check(not model.window_lights[0].visible,'Window light off by day')
			cycle.night=true;model.update_environment()
			check(model.window_lights[0].visible==(state==3),'Window light only in occupied residence at night')
			check(is_equal_approx(model.window_material.emission_energy_multiplier,0.8 if state==3 else 0.0),'Correct night window emission')
			cycle.night=false;model.update_environment()
		else:check(model.smoke==null,'Ruined house has no smoke')
		check(Save.save_game(world,SAVE_PATH),'Save house stage')
		h.current_stage=(state+1)%4;h._update_visuals()
		check(Save.load_game(world,SAVE_PATH),'Load house stage')
		check(h.current_stage==state and model.visible,'Stage and visuals restored from save')
	print('STAGES DONE')
	var ruined=h.get_node('Visuals/Stage0');var restored=h.get_node('Visuals/Stage2')
	check(triangles(ruined.get_node('Roof').mesh)<triangles(restored.get_node('Roof').mesh),'Roof breach is actual missing geometry')
	check(ruined.get_node('Foundation').mesh!=restored.get_node('Foundation').mesh,'Separate states with aged tint')
	player.inventory.items.clear();player.inventory.credits=1000
	for id in ['wood','stone','poor_brick','mortar','fired_brick','glass','fuel_briquette']:player.inventory.items[id]=100
	h.current_stage=0;h._update_visuals()
	for cost in [20,60,120]:
		print('REPAIR ',cost)
		var before: int=player.inventory.credits
		check(h.upgrade(player),'House can be repaired normally')
		check(player.inventory.credits==before-cost,'Original repair credit costs')
	check(h.current_stage==3,'All three repairs complete')
	for file in DirAccess.get_files_at('res://assets/models/house'):
		if file.ends_with('.tres'):
			check(FileAccess.get_file_as_bytes('res://assets/models/house/'+file).size()<1024*1024,'Portable text resource <1MiB: '+file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	cycle.free()
	if errors.is_empty():print('PASS: test_house_models')
	quit(0 if errors.is_empty() else 1)
