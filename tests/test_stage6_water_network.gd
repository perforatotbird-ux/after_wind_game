extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 6...")
	var world_node = WorldScene.instantiate()
	root.add_child(world_node)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	
	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _run_tests() -> void:
	print("========================================")
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 6: ВОДНЫЙ КОНТУР И ФИЛЬТРАЦИЯ")
	print("========================================")
	
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player отсутствует в сцене")
	
	var hud = world.get_node_or_null("HUD")
	if not hud: _fail("HUD отсутствует в сцене")
	
	var water_filter = world.find_child("WaterFilter", true, false)
	if not water_filter: _fail("Фильтр воды (WaterFilter) отсутствует в сцене")
	
	var water_reservoir = world.find_child("WaterReservoir", true, false)
	if not water_reservoir: _fail("Резервуар воды (WaterReservoir) отсутствует в сцене")
	
	var water_well = world.find_child("WaterWell", true, false)
	if not water_well: _fail("Колодец (WaterWell) отсутствует в сцене")
	
	var workbench = world.find_child("Workbench", true, false)
	if not workbench: _fail("Верстак (Workbench) отсутствует в сцене")
	
	var station = world.find_child("DispatchStation", true, false)
	if not station: _fail("Станция сбыта (DispatchStation) отсутствует в сцене")
	
	print("✅ Все ключевые узлы (WaterFilter, WaterReservoir, WaterWell, Player, HUD, Workbench, Station) найдены.")
	
	var inv = player.inventory
	if not inv: _fail("Инвентарь игрока недоступен")
	
	# 1. Проверка начального состояния жажды игрока и HUD
	if player.thirst < 95.0 or player.thirst > 100.0:
		_fail("Начальная жажда игрока вне диапазона 95..100 (получено %.2f)" % player.thirst)
		return
	if hud.thirst_bar.value < 95.0 or hud.thirst_bar.value > 100.0:
		_fail("Начальное значение шкалы жажды в HUD вне диапазона 95..100 (получено %.2f)" % hud.thirst_bar.value)
		return
	print("✅ Начальная шкала жажды (~100%) инициализирована в Player и HUD.")
	
	# 2. Проверка динамического расхода жажды и влияния на передвижение
	player._handle_thirst(20.0)
	if player.thirst >= 100.0: _fail("Жажда не убавилась при симуляции течения времени")
	
	player.thirst = 10.0
	player.thirst_changed.emit(player.thirst, player.max_thirst)
	if player.can_sprint(): _fail("Спринт должен блокироваться при критической жажде <= 10.0")
	var speed_mult = player.get_speed_multiplier()
	if speed_mult > 0.75: _fail("Скорость передвижения должна быть снижена при жажде 10% (получено %.2f)" % speed_mult)
	print("✅ Механика жажды: расход со временем, блокировка спринта и штраф к скорости подтверждены.")
	
	# 3. Проверка употребления сырой воды из инвентаря
	inv.add_item("water", 1)
	if inv.get_item_count("water") != 1: _fail("Не удалось добавить сырую воду в инвентарь")
	var drink_success = player.drink_from_inventory("water")
	if not drink_success: _fail("Ошибка вызова drink_from_inventory для сырой воды")
	if inv.get_item_count("water") != 0: _fail("Сырая вода не списалась после питья")
	if abs(player.thirst - 35.0) > 0.01: _fail("Жажда после сырой воды должна быть 35.0 (было 10 + 25), получено: %.1f" % player.thirst)
	print("✅ Питье сырой воды из рюкзака: ресурс списан, утолено +25% жажды.")
	
	# 4. Проверка взаимодействия с резервуаром питьевой воды
	var res_water_before = water_reservoir.current_water
	if res_water_before <= 0: _fail("В резервуаре должна быть вода по умолчанию")
	water_reservoir._on_interacted(player)
	if water_reservoir.current_water != res_water_before - 1: _fail("Резервуар не убавил объем воды при питье")
	if abs(player.thirst - 80.0) > 0.01: _fail("Жажда после резервуара должна быть 80.0 (35 + 45), получено: %.1f" % player.thirst)
	print("✅ Резервуар воды: успешное прямое утоление жажды (+45%) во дворе базы.")
	
	# 5. Проверка рецептов фильтрации воды
	var filter_recipes = RecipeDB.get_recipes_for_machine("water_filter")
	if filter_recipes.size() < 2: _fail("Ожидалось не менее 2 рецептов в фильтре, найдено: %d" % filter_recipes.size())
	
	# Добавляем сырье: 5 воды, 2 песка, 1 каменную пыль
	inv.add_item("water", 5)
	inv.add_item("sand", 2)
	inv.add_item("stone_dust", 1)
	
	# Запуск базовой песчаной фильтрации
	var start_res = water_filter.start_recipe("filter_water", player)
	if not start_res: _fail("Не удалось запустить рецепт filter_water в песчаном фильтре")
	water_filter.process_timer = water_filter.process_duration
	water_filter._complete_process()
	if water_filter.pending_outputs.get("clean_water", 0) != 2:
		_fail("Чистая вода должна накопиться в фильтре")
	water_filter.collect_outputs(player)
	
	if inv.get_item_count("clean_water") != 2:
		_fail("После filter_water ожидалось 2 clean_water, получено: %d" % inv.get_item_count("clean_water"))
	print("✅ Песчаный фильтр: 2 сырых воды + 1 песок -> 2 очищенных воды (успешно).")
	
	# Запуск глубокой минеральной фильтрации
	start_res = water_filter.start_recipe("mineral_filter_water", player)
	if not start_res: _fail("Не удалось запустить рецепт mineral_filter_water в фильтре")
	water_filter.process_timer = water_filter.process_duration
	water_filter._complete_process()
	if water_filter.pending_outputs.get("clean_water", 0) != 4:
		_fail("Дополнительная вода должна накопиться в фильтре")
	water_filter.collect_outputs(player)
	
	if inv.get_item_count("clean_water") != 6:
		_fail("После mineral_filter_water ожидалось 6 clean_water, получено: %d" % inv.get_item_count("clean_water"))
	print("✅ Глубокая фильтрация: 3 воды + 1 песок + 1 пыль -> +4 очищенных воды (итого 6 шт).")
	
	# 6. Питье чистой фильтрованной воды
	player.thirst = 30.0
	player.energy = 50.0
	player.drink_from_inventory("clean_water")
	if inv.get_item_count("clean_water") != 5: _fail("Clean_water не списалась при питье")
	if abs(player.thirst - 80.0) > 0.01: _fail("Очищенная вода должна дать +50% жажды (30 + 50 = 80), получено: %.1f" % player.thirst)
	if player.energy <= 50.0: _fail("Очищенная вода должна давать бонус бодрости к энергии")
	print("✅ Питье очищенной воды: +50% жажды и +8 бодрости к энергии.")
	
	# 7. Розлив воды в бутылки на верстаке (цепочка: Стекло + Чистая вода)
	inv.add_item("glass", 2)
	var bottle_recipe = RecipeDB.get_recipe("bottle_water")
	if bottle_recipe.is_empty(): _fail("Рецепт bottle_water не найден в RecipeDB")
	
	start_res = workbench.start_recipe("bottle_water", player)
	if not start_res: _fail("Не удалось запустить рецепт bottle_water на верстаке")
	workbench.process_timer = workbench.process_duration
	workbench._complete_process()
	if workbench.pending_outputs.get("bottled_water", 0) != 1:
		_fail("Бутилированная вода должна накопиться в верстаке")
	workbench.collect_outputs(player)
	
	if inv.get_item_count("bottled_water") != 1:
		_fail("Ожидалась 1 бутилированная вода, получено: %d" % inv.get_item_count("bottled_water"))
	print("✅ Производство на верстаке: 1 стекло + 1 очищенная вода -> 1 бутилированная вода.")
	
	# 8. Продажа бутилированной воды на станции сбыта
	var credits_start = inv.credits
	var earnings = station.sell_goods({"bottled_water": 1, "clean_water": 2}, player)
	# 1 * 52 + 2 * 15 = 52 + 30 = 82 кредита
	if earnings != 82: _fail("Ожидался доход 82 кредита от партии воды, получено: %d" % earnings)
	if inv.credits != credits_start + 82: _fail("Баланс игрока не обновился корректно (+82 кр.)")
	print("✅ Экономика и сбыт: продана 1 бутылка и 2 чистые воды за +82 кредита!")
	
	# 9. Проверка отображения в HUD
	if not hud.thirst_bar or not hud.thirst_label: _fail("Элементы ThirstBar/ThirstLabel в HUD отсутствуют")
	print("✅ Визуальные индикаторы жажды в интерфейсе HUD полностью валидны.")
	
	print("========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 6 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	quit(0)
