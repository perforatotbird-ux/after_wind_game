extends SceneTree
## Делянки: стоимость по размеру, размещение мышкой (растягивание, лимит 128 клеток,
## занятые места), доставка материалов, стройка 1 игровой день, клетки со своими
## семенами, влага/засуха/увядание, удобрение, качество, севооборот, дождь,
## сохранение и кнопка в рюкзаке.

const FarmField = preload("res://scripts/farming/farm_field.gd")
const Placer = preload("res://scripts/farming/farm_field_placer.gd")
const CropDB = preload("res://scripts/farming/crop_db.gd")
const Meshes = preload("res://scripts/farming/farm_field_meshes.gd")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")

var world: Node
var player: Node
var frames := 0
var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	# Стоимость растёт с размером.
	var c22: Dictionary = FarmField.cost_for(2, 2)
	var c816: Dictionary = FarmField.cost_for(8, 16)
	check(c22 == {"wood": 8, "stone": 1, "sawdust": 1}, "Стоимость 2×2: %s" % c22)
	for k in c22:
		check(int(c816[k]) > int(c22[k]), "Стоимость %s не растёт с размером" % k)
	# Меши строятся для всех культур и стадий.
	for crop in CropDB.CROPS:
		for stage in 4:
			check(Meshes.crop(crop, stage).get_surface_count() == 1, "Нет меша %s/%d" % [crop, stage])
		check(Meshes.crop(crop, 2, true).get_surface_count() == 1, "Нет увядшего меша " + crop)
	check(Meshes.border(5, 3).get_surface_count() == 1 and Meshes.border_segments(5, 3).size() == 10, "Бортик 5×3")
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _find_free_origin(w: int, h: int) -> Vector2i:
	for r in range(6, 30):
		for a in 24:
			var p := Vector2i(int(cos(TAU * a / 24.0) * r), int(sin(TAU * a / 24.0) * r))
			if Placer.check_rect(world, Rect2(p, Vector2(w, h))) == "":
				return p
	return Vector2i(9999, 9999)

func _process(_d: float) -> bool:
	frames += 1
	if world == null:
		errors.append("Мир не загрузился")
		return _finish()
	if frames < 4:
		return false
	player = world.find_child("Player", true, false)
	player.set_process(false)
	player.set_physics_process(false)
	var inv: Node = player.inventory
	inv.max_slots = 200
	if "max_weight" in inv:
		inv.max_weight = 10000.0
	# --- Размещение мышкой ---
	var placer = Placer.new()
	placer.setup(world, player)
	world.add_child(placer)
	var hud = world.find_child("HUD", true, false)
	if hud:
		check(hud.is_gameplay_input_blocked(), "Во время размещения персонаж не заблокирован")
	var o := _find_free_origin(4, 3)
	check(o.x != 9999, "Нет свободного места для делянки")
	placer.set_hover_world(Vector3(o.x + 0.5, 0, o.y + 0.5))
	placer.begin_drag()
	placer.set_hover_world(Vector3(o.x + 3.5, 0, o.y + 2.5))
	check(placer.get_cell_rect() == Rect2i(o.x, o.y, 4, 3), "Растягивание: %s" % placer.get_cell_rect())
	# Лимит 128 клеток при растягивании.
	placer.set_hover_world(Vector3(o.x + 20.5, 0, o.y + 20.5))
	var big: Rect2i = placer.get_cell_rect()
	check(big.size.x * big.size.y <= FarmField.MAX_CELLS and big.size.x * big.size.y >= 120, "Лимит клеток: %s" % big)
	placer.set_hover_world(Vector3(o.x + 3.5, 0, o.y + 2.5))
	var field = placer.end_drag()
	check(field != null and field.size == Vector2i(4, 3), "Делянка не поставлена")
	if field == null:
		return _finish()
	check(Placer.check_rect(world, Rect2(o, Vector2(2, 2))) != "", "Можно поставить делянку поверх другой")
	var smelter: Node3D = world.find_child("Smelter", true, false)
	if smelter:
		var sp := Vector2(smelter.global_position.x - 1, smelter.global_position.z - 1)
		check(Placer.check_rect(world, Rect2(sp, Vector2(2, 2))) != "", "Можно поставить делянку на плавильню")
	check(Placer.check_rect(world, Rect2(Vector2(o), Vector2(16, 9))) != "", "Пропущена делянка > 128 клеток")
	# --- Материалы и стройка ---
	check(field.state == FarmField.State.BLUEPRINT, "Новая делянка не в стадии разметки")
	var cost: Dictionary = field.get_cost()
	for id in cost:
		inv.add_item(id, int(cost[id]) - 1)
	field.deliver_materials(player)
	check(field.state == FarmField.State.BLUEPRINT, "Стройка началась без всех материалов")
	for id in cost:
		inv.add_item(id, 1)
	field.deliver_materials(player)
	check(field.state == FarmField.State.BUILDING, "Стройка не началась")
	field.advance_hours(12.0)
	check(field.state == FarmField.State.BUILDING and field._shown_cell_count() > 0 and field._shown_cell_count() < 12, "Стройка не показывает прогресс")
	field.advance_hours(12.5)
	check(field.state == FarmField.State.READY, "За игровой день делянка не построилась")
	check(field.get_node("SoilBeds").multimesh.instance_count == 12, "Не все грядки видны")
	# --- Посадка: каждая клетка своими семенами ---
	inv.add_item("seeds_carrot", 5)
	inv.add_item("seeds_potato", 5)
	inv.add_item("seeds_wheat", 5)
	player.selected_seed = "seeds_carrot"
	field.work_cell(player, Vector2i(0, 0))
	player.selected_seed = "seeds_potato"
	field.work_cell(player, Vector2i(1, 0))
	player.selected_seed = "seeds_wheat"
	field.work_cell(player, Vector2i(2, 0))
	check(field.get_cell(Vector2i(0, 0))["crop"] == "carrot" and field.get_cell(Vector2i(1, 0))["crop"] == "potato" and field.get_cell(Vector2i(2, 0))["crop"] == "wheat", "Клетки не засажены разными культурами")
	check(inv.get_item_count("seeds_carrot") == 4, "Семена не списаны")
	# Зона 3×3: посадка во все пустые клетки вокруг.
	field.zone_size = 3
	inv.add_item("seeds_carrot", 10)
	player.selected_seed = "seeds_carrot"
	var planted: int = field.plant(Vector2i(1, 1), "seeds_carrot", player)
	check(planted == 6, "Зона 3×3 посадила %d клеток (ожидалось 6 свободных)" % planted)
	field.zone_size = 1
	# --- Рост: полив в норме → отличное качество; засуха → увядание ---
	var cc := Vector2i(0, 0)
	for i in 12:
		field.get_cell(cc)["moisture"] = 70.0
		field.get_cell(Vector2i(2, 0))["moisture"] = 50.0
		field.advance_hours(1.0)
	check(field.is_ripe(cc), "Морковь не созрела за 12 ч при поливе")
	check(field.get_quality(cc) == 2, "Уход в норме не дал отличного качества")
	var before: int = inv.get_item_count("carrot")
	field.work_cell(player, cc)
	var got: int = inv.get_item_count("carrot") - before
	check(got >= 4, "Урожай отличной моркови мал: %d" % got)
	check(field.get_cell(cc)["last_crop"] == "carrot" and float(field.get_cell(cc)["fertility"]) < CropDB.START_FERTILITY, "Урожай не истощил почву")
	# Засуха: картофель без воды вянет.
	var pc := Vector2i(1, 0)
	field.get_cell(pc)["moisture"] = 0.0
	field.advance_hours(10.0)
	check(field.get_cell(pc)["withered"], "Картофель не завял от засухи")
	check(field.work_cell(player, pc) == "clear" and field.get_cell(pc)["crop"] == "", "Увядшее не убирается")
	# Переувлажнение тормозит картофель сильнее пшеницы.
	check(CropDB.moisture_factor("potato", 95.0) < CropDB.moisture_factor("wheat", 79.0), "Переувлажнение")
	check(CropDB.moisture_factor("carrot", 0.0) == 0.0 and CropDB.moisture_factor("carrot", 30.0) < 1.0, "Засуха не тормозит рост")
	# Полив и удобрение.
	inv.add_item("water", 2)
	inv.add_item("fertilizer", 1)
	var wc := Vector2i(3, 0)
	check(field.plant(wc, "seeds_wheat", player) == 1, "Пшеница не посажена")
	field.get_cell(wc)["moisture"] = 10.0
	check(field.work_cell(player, wc) == "water" and float(field.get_cell(wc)["moisture"]) >= 79.0, "Полив не сработал")
	check(field.work_cell(player, wc) == "fertilize" and field.get_cell(wc)["fertilized"], "Удобрение не внесено")
	# Севооборот: после моркови картофель даёт +1.
	var rng := RandomNumberGenerator.new()
	var d_same := {"crop": "potato", "fertilized": false, "last_crop": "potato", "fertility": 50.0}
	var d_rot := {"crop": "potato", "fertilized": false, "last_crop": "carrot", "fertility": 50.0}
	rng.seed = 1
	var y_same: int = FarmField.calc_yield(d_same, 0, rng)[0]
	rng.seed = 1
	var y_rot: int = FarmField.calc_yield(d_rot, 0, rng)[0]
	check(y_rot == y_same + 1, "Севооборот не даёт бонуса")
	# Дождь поливает делянку.
	var m0: float = float(field.get_cell(Vector2i(3, 2))["moisture"])
	field.apply_rain(30.0)
	check(float(field.get_cell(Vector2i(3, 2))["moisture"]) > m0, "Дождь не поливает делянку")
	# Прицел: клетка перед персонажем.
	player.global_position = field.cell_center_global(Vector2i(3, 2)) - Vector3(0, Meshes.BED_HEIGHT, 0)
	check(field.update_aim(player) and field.is_cell_valid(field.target_cell), "Нет клетки под прицелом")
	check(field.get_prompt() != "", "Нет подсказки")
	# --- Сохранение ---
	var st: Dictionary = JSON.parse_string(JSON.stringify(field.get_save_state()))
	check(FarmField.is_valid_save_state(st), "Невалидное сохранение делянки")
	var fields_root: Node = field.get_parent()
	var copy = FarmField.spawn(fields_root, Vector3(st["x"], 0, st["z"]), int(st["w"]), int(st["h"]))
	copy.apply_save_state(st)
	check(copy.state == FarmField.State.READY and copy.get_cell(wc)["fertilized"] and copy.get_cell(Vector2i(2, 1))["crop"] != "", "Сохранение делянки не восстановилось")
	copy.queue_free()
	var path := "user://test_farm_fields.json"
	check(SaveManager.save_game(world, path), "Игра не сохранилась")
	var txt := FileAccess.get_file_as_string(path)
	check(txt.contains("farm_fields"), "В файле нет секции farm_fields")
	field.queue_free()
	check(SaveManager.load_game(world, path), "Игра не загрузилась")
	var loaded: Array = get_nodes_in_group(FarmField.GROUP)
	check(loaded.size() == 1, "После загрузки делянок: %d" % loaded.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# --- Отмена стройки возвращает материалы ---
	var o2 := _find_free_origin(2, 2)
	var f2 = FarmField.spawn(fields_root, Vector3(o2.x, 0, o2.y), 2, 2)
	inv.add_item("wood", 3)
	var wood0: int = inv.get_item_count("wood")
	f2.deliver_materials(player)
	check(inv.get_item_count("wood") < wood0, "Материалы не приняты")
	f2.cancel_construction(player)
	check(inv.get_item_count("wood") == wood0, "Материалы не вернулись при отмене")
	# --- Кнопка в рюкзаке ---
	var panel = InventoryPanel.new()
	panel.setup(player)
	root.add_child(panel)
	check(panel.find_child("BuildFarmFieldButton", true, false) != null, "Нет кнопки «Делянка» в рюкзаке")
	var asked := [""]
	panel.build_requested.connect(func(k): asked[0] = k)
	panel.request_build("farm_field")
	check(asked[0] == "farm_field", "Кнопка не запрашивает размещение")
	panel.queue_free()
	return _finish()

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_farm_fields — делянки: размещение, стройка, клетки, рост, уход, сохранение")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
