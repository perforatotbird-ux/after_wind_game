extends SceneTree

# Тестовый набор для проверки системы производства домашнего алкоголя,
# бродильного цеха на складе, дистиллятора и обновлённой модели верстака.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ProductStorageScript = preload("res://scripts/buildings/product_storage.gd")
const DistillerScript = preload("res://scripts/crafting/distiller.gd")
const WorkbenchScene = preload("res://scenes/machines/workbench.tscn")
const DistillerScene = preload("res://scenes/machines/distiller.tscn")

var passed_tests: int = 0
var failed_tests: int = 0

func _init() -> void:
	print("\n========================================")
	print("🧪 ТЕСТИРОВАНИЕ СИСТЕМЫ ПРОИЗВОДСТВА АЛКОГОЛЯ")
	print("========================================\n")
	
	test_alcohol_items_and_attributes()
	test_beer_production_chain()
	test_wine_production_chain()
	test_distillation_and_spirits()
	test_workbench_model_and_collisions()
	test_save_load_persistence()
	
	print("\n========================================")
	if failed_tests == 0:
		print("🎉 ВСЕ ТЕСТЫ СИСТЕМЫ АЛКОГОЛЯ УСПЕШНО ПРОЙДЕНЫ! (Пройдено: %d)" % passed_tests)
		quit(0)
	else:
		print("❌ ТЕСТЫ ПРОВАЛЕНЫ: %d ошибок! (Пройдено: %d)" % [failed_tests, passed_tests])
		quit(1)

func assert_true(condition: bool, msg: String) -> void:
	if condition:
		print("  ✓ %s" % msg)
		passed_tests += 1
	else:
		printerr("  ✗ ОШИБКА: %s" % msg)
		failed_tests += 1

func test_alcohol_items_and_attributes() -> void:
	print("--- Тест 1: Регистрация предметов и атрибутов в ItemDB ---")
	
	var required_items = [
		"beer_wort_raw", "beer_wort_boiled", "berry_must", "grain_wash", "fermented_wash",
		"beer", "berry_wine", "moonshine", "pure_spirit",
		"blueberry_tincture", "red_berry_tincture", "blackberry_tincture",
		"sea_buckthorn_tincture", "mushroom_tincture", "special_mushroom_tincture"
	]
	
	for it_id in required_items:
		var item: Dictionary = ItemDB.get_item(it_id)
		assert_true(not item.is_empty(), "Предмет '%s' зарегистрирован в ItemDB" % it_id)
	
	# Проверка drinkable
	assert_true(ItemDB.is_drinkable("beer"), "Пиво является пригодным для питья")
	assert_true(ItemDB.is_drinkable("berry_wine"), "Вино является пригодным для питья")
	assert_true(ItemDB.is_drinkable("moonshine"), "Самогон является пригодным для питья")
	assert_true(ItemDB.is_drinkable("pure_spirit"), "Спирт является пригодным для питья")
	assert_true(ItemDB.is_drinkable("sea_buckthorn_tincture"), "Облепиховый бальзам можно пить")
	
	# Проверка согревания и бонусов
	assert_true(ItemDB.get_warmth_bonus("moonshine") >= 20.0, "Самогон даёт согревающий эффект (>= 20)")
	assert_true(ItemDB.get_warmth_bonus("pure_spirit") >= 30.0, "Спирт даёт мощный согревающий эффект (>= 30)")
	assert_true(ItemDB.get_health_bonus("sea_buckthorn_tincture") >= 25.0, "Облепиховая настойка лечит раны (>= 25)")
	
	# Проверка ферментации
	assert_true(ItemDB.is_fermentable("beer_wort_boiled"), "Сваренное пивное сусло пригодно для брожения")
	assert_true(ItemDB.is_fermentable("berry_must"), "Ягодное сусло пригодно для брожения")
	assert_true(ItemDB.is_fermentable("grain_wash"), "Зерновой затор пригоден для брожения")
	assert_true(not ItemDB.is_fermentable("beer_wort_raw"), "Сырое непроваренное сусло нельзя сбраживать")

func test_beer_production_chain() -> void:
	print("\n--- Тест 2: Производственная цепочка пива ---")
	
	# Рецепты костра
	var r_mash: Dictionary = RecipeDB.get_recipe("mash_beer_wort")
	assert_true(not r_mash.is_empty(), "Рецепт 'mash_beer_wort' существует")
	assert_true(r_mash.get("machine", "") == "campfire", "Затирание производится на костре")
	assert_true(r_mash.get("inputs", {}).has("wheat"), "Затирание требует пшеницу")
	assert_true(r_mash.get("outputs", {}).get("beer_wort_raw", 0) == 1, "Затирание даёт сырое пивное сусло")
	
	var r_boil: Dictionary = RecipeDB.get_recipe("boil_beer_wort")
	assert_true(not r_boil.is_empty(), "Рецепт 'boil_beer_wort' существует")
	assert_true(r_boil.get("machine", "") == "campfire", "Варка сусла производится на костре")
	assert_true(r_boil.get("inputs", {}).has("beer_wort_raw"), "Варка требует сырое сусло")
	assert_true(r_boil.get("inputs", {}).has("herbs"), "Варка требует травы (хмель)")
	assert_true(r_boil.get("outputs", {}).get("beer_wort_boiled", 0) == 1, "Варка даёт охмелённое сусло")
	
	# Тестирование бродильного цеха склада
	var storage = ProductStorageScript.new()
	storage.current_stage = 2 # склад восстановлен
	storage._init_default_stages()
	storage._init_fermentation_slots()
	
	var inv = InventoryScript.new()
	inv.max_slots = 10
	inv.base_max_weight = 50.0
	inv.add_item("beer_wort_boiled", 1)
	
	var started: bool = storage.start_fermentation(0, "beer_wort_boiled", 1, inv)
	assert_true(started, "Успешный запуск брожения пива в бочке #1")
	assert_true(inv.get_item_count("beer_wort_boiled") == 0, "Сусло списано из инвентаря игрока")
	
	# Симуляция процесса брожения
	storage._process(55.0)
	var slot: Dictionary = storage.fermentation_slots[0]
	assert_true(slot.get("status", "") == "ready", "Брожение пива завершено (статус ready)")
	assert_true(slot.get("output_item", "") == "beer", "Выходная продукция — пиво")
	assert_true(slot.get("output_count", 0) == 2, "Выход — 2 бутыли пива")
	
	var collected: int = storage.collect_fermentation(0, inv)
	assert_true(collected == 2, "Игрок забрал 2 бутыли пива в рюкзак")
	assert_true(inv.get_item_count("beer") == 2, "В рюкзаке появилось 2 ед. готового домашнего пива")
	assert_true(storage.fermentation_slots[0].get("status", "") == "idle", "Бочка снова свободна")
	
	storage.free()
	inv.free()

func test_wine_production_chain() -> void:
	print("\n--- Тест 3: Производственная цепочка вина ---")
	
	var r_must: Dictionary = RecipeDB.get_recipe("prepare_berry_must")
	assert_true(not r_must.is_empty(), "Рецепт 'prepare_berry_must' существует")
	assert_true(r_must.get("machine", "") == "workbench", "Отжим ягод производится на верстаке")
	assert_true(r_must.get("inputs", {}).has("red_berry"), "Отжим требует ягоды")
	
	var storage = ProductStorageScript.new()
	storage.current_stage = 2
	storage._init_default_stages()
	storage._init_fermentation_slots()
	
	var inv = InventoryScript.new()
	inv.max_slots = 10
	inv.base_max_weight = 50.0
	inv.add_item("berry_must", 1)
	
	var started: bool = storage.start_fermentation(1, "berry_must", 1, inv)
	assert_true(started, "Успешный запуск брожения вина в бочке #2")
	
	storage._process(60.0)
	assert_true(storage.fermentation_slots[1].get("status", "") == "ready", "Брожение вина завершено")
	assert_true(storage.fermentation_slots[1].get("output_item", "") == "berry_wine", "Выходная продукция — ягодное вино")
	
	var collected: int = storage.collect_fermentation(1, inv)
	assert_true(collected == 2, "Собрано 2 ед. вина в инвентарь")
	assert_true(inv.get_item_count("berry_wine") == 2, "Вино добавлено в инвентарь")
	
	storage.free()
	inv.free()

func test_distillation_and_spirits() -> void:
	print("\n--- Тест 4: Дистиллятор, самогон, спирт и настойки ---")
	
	var dist_scene = DistillerScene.instantiate()
	assert_true(dist_scene != null, "Сцена distiller.tscn успешно инстанциирована")
	assert_true(dist_scene.machine_type == "distiller", "machine_type дистиллятора = 'distiller'")
	assert_true(dist_scene.has_fuel_slots, "Дистиллятор имеет слоты топлива")
	
	# Проверка рецептов самогона и спирта
	var r_moonshine = RecipeDB.get_recipe("distill_moonshine")
	assert_true(not r_moonshine.is_empty(), "Рецепт 'distill_moonshine' существует")
	assert_true(r_moonshine.get("inputs", {}).has("fermented_wash"), "Самогон требует сброженную брагу")
	assert_true(r_moonshine.get("inputs", {}).has("glass_bottle"), "Самогон требует бутылки")
	assert_true(r_moonshine.get("outputs", {}).get("moonshine", 0) == 2, "Самогон выдаёт 2 бутылки")
	
	var r_spirit = RecipeDB.get_recipe("distill_spirit")
	assert_true(not r_spirit.is_empty(), "Рецепт ректификации спирта 'distill_spirit' существует")
	assert_true(r_spirit.get("inputs", {}).has("moonshine"), "Ректификация спирта требует самогон")
	
	var r_filter = RecipeDB.get_recipe("filter_spirit")
	assert_true(not r_filter.is_empty(), "Рецепт угольной фильтрации спирта существует")
	assert_true(r_filter.get("inputs", {}).has("coal_powder"), "Фильтрация требует угольный порошок")
	
	# Проверка рецептов настоек на дистилляторе
	var tinctures = [
		"steep_blueberry", "steep_red_berry", "steep_blackberry",
		"steep_sea_buckthorn", "steep_mushroom", "steep_special_mushroom"
	]
	for t_id in tinctures:
		var r = RecipeDB.get_recipe(t_id)
		assert_true(not r.is_empty(), "Рецепт настойки '%s' существует" % t_id)
		assert_true(r.get("machine", "") == "distiller", "Настойка '%s' изготавливается на дистилляторе" % t_id)
		assert_true(r.get("inputs", {}).has("pure_spirit"), "Настойка '%s' требует чистый спирт" % t_id)
	
	dist_scene.free()

func test_workbench_model_and_collisions() -> void:
	print("\n--- Тест 5: Обновление модели верстака VERSTAK_edited.glb ---")
	
	var wb = WorkbenchScene.instantiate()
	assert_true(wb != null, "Сцена workbench.tscn успешно инстанциирована")
	
	var visual = wb.get_node_or_null("Visual")
	assert_true(visual != null, "Узел Visual присутствует в верстаке")
	
	var model = visual.get_node_or_null("WorkbenchModel")
	assert_true(model != null, "Узел WorkbenchModel с моделью VERSTAK_edited.glb подключен")
	assert_true(abs(model.scale.y - 1.85) < 0.05, "Масштаб модели скорректирован под рост игрока (~1.85)")
	
	var solid = wb.get_node_or_null("SolidBody/SolidShape")
	assert_true(solid != null, "Физическая коллизия SolidShape присутствует")
	assert_true(solid.shape is BoxShape3D, "SolidShape является BoxShape3D")
	
	wb.free()

func test_save_load_persistence() -> void:
	print("\n--- Тест 6: Сохранение и загрузка состояния брожения ---")
	
	var storage = ProductStorageScript.new()
	storage.current_stage = 2
	storage._init_default_stages()
	storage._init_fermentation_slots()
	
	storage.fermentation_slots[0] = {
		"status": "fermenting",
		"input_item": "beer_wort_boiled",
		"output_item": "beer",
		"count": 1,
		"output_count": 2,
		"timer": 25.5,
		"duration": 50.0
	}
	
	var saved_data = storage.export_fermentation_state()
	assert_true(saved_data is Array and saved_data.size() == 4, "Экспорт брожения успешен (4 слота)")
	
	var storage2 = ProductStorageScript.new()
	storage2.current_stage = 2
	storage2.restore_fermentation_state(saved_data)
	
	var slot0: Dictionary = storage2.fermentation_slots[0]
	assert_true(slot0.get("status", "") == "fermenting", "Статус слота #0 восстановлен ('fermenting')")
	assert_true(abs(float(slot0.get("timer", 0.0)) - 25.5) < 0.01, "Таймер слота #0 восстановлен (25.5 с)")
	assert_true(slot0.get("output_item", "") == "beer", "Выходная продукция слота #0 восстановлена ('beer')")
	
	storage.free()
	storage2.free()
