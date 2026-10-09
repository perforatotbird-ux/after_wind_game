extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 4...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 4: ТЕРМООБРАБОТКА И ПЛАВИЛЬНЯ")
	print("========================================")
	
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player отсутствует в сцене")
	
	var hud = world.get_node_or_null("HUD")
	if not hud: _fail("HUD отсутствует в сцене")
	
	var smelter = world.find_child("Smelter", true, false)
	if not smelter: _fail("Печь-плавильня (Smelter) отсутствует в сцене")
	
	var scrap_node = world.find_child("ScrapHeap1", true, false)
	if not scrap_node: _fail("ScrapHeap1 отсутствует в сцене")
	
	var station = world.find_child("DispatchStation", true, false)
	if not station: _fail("DispatchStation отсутствует в сцене")
	
	print("✅ Все ключевые узлы (Smelter, ScrapHeap1, Player, DispatchStation) найдены.")
	
	# 1. Проверка конфигурации печи и рецептов
	if smelter.machine_type != "furnace": _fail("machine_type печи != furnace")
	var furnace_recipes = RecipeDB.get_recipes_for_machine("furnace")
	if furnace_recipes.size() < 3: _fail("Ожидалось как минимум 3 рецепта печи, получено: %d" % furnace_recipes.size())
	print("✅ Рецепты печи-плавильни загружены (всего %d: обжиг кирпича, плавка стекла, переплавка железа и выпечка)." % furnace_recipes.size())
	
	var inv = player.inventory
	if not inv: _fail("Инвентарь игрока недоступен")
	
	# 2. Добыча металлолома
	inv.equip_tool("pickaxe")
	var initial_scrap = inv.get_item_count("metal_scrap")
	scrap_node.interact(player)
	var harvested_scrap = inv.get_item_count("metal_scrap")
	if harvested_scrap <= initial_scrap: _fail("Металлолом не был собран киркой")
	print("✅ Добыча сырья: металлолом успешно собран с кучи лома.")
	
	# 3. Тест рецепта 1: Обжиг кирпичей (2 poor_brick + 1 fuel_briquette -> 2 fired_brick)
	inv.add_item("poor_brick", 2)
	inv.add_item("fuel_briquette", 1)
	var ok_smelt1 = smelter.start_recipe("smelt_brick", player)
	if not ok_smelt1: _fail("Не удалось запустить smelt_brick")
	if not smelter.is_machine_running: _fail("Печь не перешла в рабочее состояние")
	if inv.get_item_count("poor_brick") != 0 or inv.get_item_count("fuel_briquette") != 0:
		_fail("Сырьё для кирпичей не списалось")
	
	smelter._complete_process() # завершение цикла
	if inv.get_item_count("fired_brick") != 2: _fail("Готовые обожженные кирпичи не выданы игроку")
	print("✅ Обжиг кирпича: 2 сырых кирпича + 1 брикет -> 2 прочных обожженных кирпича.")
	
	# 4. Тест рецепта 2: Выплавка стекла (2 sand + 1 fuel_briquette -> 1 glass)
	inv.add_item("sand", 3)
	inv.add_item("fuel_briquette", 1)
	var ok_smelt2 = smelter.start_recipe("smelt_glass", player)
	if not ok_smelt2: _fail("Не удалось запустить smelt_glass")
	smelter._complete_process()
	if inv.get_item_count("glass") != 1: _fail("Стекло не выдано игроку")
	print("✅ Выплавка стекла: 3 песка + 1 брикет -> 1 лист закаленного стекла.")
	
	# 5. Тест рецепта 3: Переплавка железа (3 metal_scrap + 2 fuel_briquette -> 1 iron_ingot)
	inv.add_item("metal_scrap", 3)
	inv.add_item("fuel_briquette", 2)
	var ok_smelt3 = smelter.start_recipe("smelt_iron", player)
	if not ok_smelt3: _fail("Не удалось запустить smelt_iron")
	smelter._complete_process()
	if inv.get_item_count("iron_ingot") != 1: _fail("Железный слиток не выдан игроку")
	print("✅ Переплавка металла: 3 металлолома + 2 брикета -> 1 слиток железа.")
	
	# 6. Проверка экономики и сбыта новой термопродукции
	var init_credits = inv.credits
	var earned = station.sell_goods({
		"fired_brick": 2, # 2 * 18 = 36
		"glass": 1,       # 1 * 22 = 22
		"iron_ingot": 1   # 1 * 35 = 35
	}, player) # Итого: 93 кредита
	
	if earned != 93: _fail("Ожидался доход 93 кредита, получено: %d" % earned)
	if inv.credits != init_credits + 93: _fail("Баланс кредитов игрока не совпал")
	if inv.get_item_count("fired_brick") != 0 or inv.get_item_count("glass") != 0 or inv.get_item_count("iron_ingot") != 0:
		_fail("Проданные товары не удалились из инвентаря")
	print("✅ Сбыт термопродукции: продано 2 кирпича, 1 стекло, 1 слиток на сумму +93 кредита.")
	
	# 7. Проверка окна печи в HUD
	hud.open_machine_window(smelter)
	if not hud.machine_window.visible: _fail("Окно печи не открылось в HUD")
	if not "🔥" in hud.machine_title_label.text: _fail("Заголовок окна печи не содержит иконку огня")
	hud.close_machine_window()
	if hud.machine_window.visible: _fail("Окно печи не закрылось")
	print("✅ Интерфейс печи-плавильни в HUD функционирует идеально.")
	
	print("========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 4 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	
	quit(0)
