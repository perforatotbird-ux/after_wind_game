extends SceneTree
## Модель по референсу; горение без готовки, эффекты, пауза, топливо и сейвы.
const Save = preload("res://scripts/core/save_manager.gd")
const SAVE_PATH := "user://test_campfire_model.json"
class NightStub extends Node:
	func is_night() -> bool: return true
var world: Node3D
var errors: Array[String] = []
func _initialize() -> void:
	world=load("res://scenes/world/world.tscn").instantiate();root.add_child(world)
	call_deferred("run_checks")
func check(ok:bool,message:String)->void:
	if not ok: errors.append(message);printerr("FAIL: "+message)
func clear_fire(fire:Node)->void:
	fire.cancel_batch();fire.pending_outputs.clear();fire.fuel_slots[0]={"item_id":"","count":0}
	fire.fuel_burn_left=0;fire.active_fuel_slot=-1;fire.has_burned=false
	fire.refresh_fire_visuals(true)
func run_checks()->void:
	for i in 4:await process_frame
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var fire=world.find_child("Campfire",true,false)
	var model=fire.get_node("Visual/CampfireModel")
	var player=world.get_node("Player");var inv=player.inventory
	check(fire is Campfire and fire.shake_strength==0,"Костёр подключён без дрожания поленьев")
	check(fire.has_node("SolidBody/SolidShape"),"Твёрдая коллизия костра")
	var total:=0
	for mi in model.get_node("CampfireGeometry").find_children("*","MeshInstance3D",true,false):
		for s in mi.mesh.get_surface_count():total+=mi.mesh.surface_get_array_index_len(s)/3
	check(total>6000 and total<22000,"Бюджет статичной модели 6–22 тыс. треугольников")
	check(model.flame_materials.size()==8 and model.flames.get_child_count()==8,"Восемь анимированных изогнутых языков огня")
	check(model.smoke.mesh.material.albedo_texture!=null and model.sparks.mesh.material.albedo_texture!=null,"Частицы не рисуют прямоугольники без альфа-текстуры")
	check(model.wood_materials.size()==2 and model.coal_materials.size()==1,"Отдельные материалы дерева/торцов и углей")
	clear_fire(fire)
	check(not fire.is_lit() and not model.flames.visible and not fire.fire_light.visible,"Пустой костёр погашен")
	check(not model.smoke.emitting and not model.sparks.emitting,"Нет постоянных частиц без топлива")
	# One log expires after its real 15 seconds even when no recipe is active.
	inv.items.clear();inv.items["wood"]=1
	check(fire.add_fuel_from_inventory(inv,"wood",1)==1,"Дрова из инвентаря разжигают костёр")
	check(fire.is_lit() and not fire.is_machine_running and fire.has_burned,"Горит без рецепта")
	fire._process(1.0)
	check(is_equal_approx(fire.fuel_burn_left,14.0),"Топливо расходуется без готовки")
	check(model.flames.visible and model.sparks.emitting and model.smoke.emitting and fire.fire_light.visible,"Огонь, искры, дым и свет работают")
	var energy:float=fire.fire_light.light_energy
	fire._process(.1)
	check(not is_equal_approx(energy,fire.fire_light.light_energy),"Свет мерцает")
	fire._process(14.0)
	check(not fire.is_lit() and fire.get_fuel_time_total()==0,"Последнее полено догорело")
	check(not model.sparks.emitting,"Искры перестали испускаться")
	fire._process(8.0)
	check(not model.flames.visible and not model.smoke.emitting and not fire.fire_light.visible,"Полное угасание без вечного ночного свечения")
	check(model.char_amount>.99 and model.ember_strength<.001,"Остались обугленные поленья и холодные угли")
	# Empty campfire is cold even at night; lit one heats the player.
	var stub:=NightStub.new();root.add_child(stub);fire._day_cycle=stub
	fire._process(1.0)
	check(not fire.fire_light.visible,"Пустой костёр не светит ночью")
	var smelter=world.find_child("Smelter",true,false)
	var old_smelter:Vector3=smelter.global_position;smelter.global_position=Vector3(150,0,150)
	player.global_position=fire.global_position+Vector3(1,0,0)
	check(not player.is_near_heat(),"Потушенный костёр не согревает и не ускоряет сушку")
	clear_fire(fire);inv.items["wood"]=3
	fire.add_fuel_from_inventory(inv,"wood",3);fire._process(31.0)
	check(fire.is_lit() and is_equal_approx(fire.fuel_burn_left,14.0),"Большой delta корректно пересёк три полена без потери секунд")
	check(player.is_near_heat(),"Горящий костёр — источник тепла")
	smelter.global_position=old_smelter
	# With cooking, fuel and recipe clocks advance once, not twice.
	clear_fire(fire);inv.items.clear();inv.items["wood"]=3;inv.items["potato"]=2;player.energy=100
	fire.add_fuel_from_inventory(inv,"wood",3)
	check(fire.start_recipe("cook_baked_potato",player),"Рецепт костра работает")
	fire._process(10.0)
	check(is_equal_approx(fire.process_timer,10.0) and is_equal_approx(fire.get_fuel_time_total(),35.0),"Готовка не списывает топливо дважды")
	fire._process(20.0)
	check(int(fire.pending_outputs.get("baked_potato",0))==2 and not fire.is_machine_running,"Готовка завершилась с прежним выходом")
	check(is_equal_approx(fire.get_fuel_time_total(),15.0) and fire.is_processing(),"После готовки остаётся реальный запас горения и процесс не выключен")
	fire._process(16.0);check(not fire.is_lit(),"После готовки огонь тоже догорел")
	# Cancellation and taking spare fuel cannot freeze/refund an already burning log.
	clear_fire(fire);inv.items["wood"]=3;inv.items["potato"]=2
	fire.add_fuel_from_inventory(inv,"wood",3);fire.start_recipe("cook_baked_potato",player)
	fire._process(2);fire.cancel_batch();fire._process(1)
	check(fire.is_processing() and is_equal_approx(fire.get_fuel_time_total(),42.0),"Отмена рецепта не замораживает огонь")
	check(fire.take_fuel_from_slot(0,inv)==2,"Возвращён только запас из слота")
	check(fire.is_lit() and is_equal_approx(fire.fuel_burn_left,12.0),"Уже горящая единица не возвращена и догорает")
	# Save/load idle-burning and fully charred states, plus malformed optional flags.
	check(Save.save_game(world,SAVE_PATH),"Сохранение горения без рецепта")
	clear_fire(fire)
	check(Save.load_game(world,SAVE_PATH),"Загрузка горения без рецепта")
	check(fire.is_lit() and fire.is_processing() and model.flames.visible,"Сейв сразу возвращает пламя и расход топлива")
	fire._process(13);fire._process(8)
	check(Save.save_game(world,SAVE_PATH),"Сохранение потушенного обугленного костра")
	clear_fire(fire);check(Save.load_game(world,SAVE_PATH),"Загрузка потушенного костра")
	check(fire.has_burned and model.char_amount>.99 and not model.flames.visible,"Обугливание сохраняется, новый огонь не появляется")
	var file:=FileAccess.open(SAVE_PATH,FileAccess.READ);var data:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	for m in data.machines:
		if m.path==str(world.get_path_to(fire)):m.fire_has_burned="bad"
	file=FileAccess.open(SAVE_PATH,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(not Save.load_game(world,SAVE_PATH),"Некорректное поле обугливания отклонено до загрузки")
	for m in data.machines:m.erase("fire_has_burned")
	file=FileAccess.open(SAVE_PATH,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(Save.load_game(world,SAVE_PATH),"Старые сейвы без нового поля загружаются")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("CAMPFIRE ",total," triangles; fuel-clock / effects / saves checked")
	if errors.is_empty():print("PASS: test_campfire_model")
	quit(0 if errors.is_empty() else 1)
