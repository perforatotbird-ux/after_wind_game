extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 8...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 8: СЕЛЬСКОЕ ХОЗЯЙСТВО И ФЕРМА")
	print("========================================")
	
	ContractDB.reset_completed()
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var hud = world.get_node_or_null("HUD")
	if not hud:
		_fail("HUD отсутствует в сцене")
		return
	
	var inv = player.inventory
	if not inv:
		_fail("Инвентарь игрока отсутствует")
		return
	
	var plot1 = world.find_child("FarmlandPlot1", true, false)
	var plot2 = world.find_child("FarmlandPlot2", true, false)
	if not plot1 or not plot2:
		_fail("Грядки FarmlandPlot1 или FarmlandPlot2 отсутствуют в сцене")
		return
	
	var trader_npc = world.find_child("TraderNPC", true, false)
	if not trader_npc:
		_fail("TraderNPC отсутствует в сцене")
		return
	
	print("✅ Все ключевые узлы мира найдены (World, Player, HUD, FarmlandPlot1, FarmlandPlot2, TraderNPC).")
	
	# -------------------------------------------------------------
	# 1. Проверка ItemDB (семена, урожай, еда, удобрения)
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Реестр предметов ItemDB для агрономии ---")
	var required_items: Array[String] = [
		"seeds_carrot", "seeds_potato", "seeds_wheat",
		"carrot", "potato", "wheat", "bread", "fertilizer"
	]
	for it_id in required_items:
		var d = ItemDB.get_item(it_id)
		if d.is_empty():
			_fail("Предмет отсутствует в ItemDB: " + it_id)
			return
		print("  - Предмет '%s': %s (категория: %s)" % [it_id, d.get("name"), d.get("category")])
	
	if not ItemDB.is_seed("seeds_carrot") or ItemDB.get_crop_type("seeds_carrot") != "carrot":
		_fail("ItemDB.is_seed / get_crop_type для seeds_carrot некорректны")
		return
	if not ItemDB.is_seed("seeds_potato") or ItemDB.get_crop_type("seeds_potato") != "potato":
		_fail("ItemDB.is_seed / get_crop_type для seeds_potato некорректны")
		return
	if not ItemDB.is_seed("seeds_wheat") or ItemDB.get_crop_type("seeds_wheat") != "wheat":
		_fail("ItemDB.is_seed / get_crop_type для seeds_wheat некорректны")
		return
	if not ItemDB.is_edible("carrot") or ItemDB.get_hunger_recovery("carrot") <= 0:
		_fail("Морковь должна быть съедобной")
		return
	if not ItemDB.is_edible("bread") or ItemDB.get_hunger_recovery("bread") < 50:
		_fail("Хлеб должен быть высококалорийной съедобной пищей")
		return
	print("✅ База данных предметов агрономии и свойства культур полностью валидны.")
	
	# -------------------------------------------------------------
	# 2. Проверка рецептов агрономии и кулинарии RecipeDB
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Рецепты верстака и печи RecipeDB ---")
	var r_fert = RecipeDB.get_recipe("craft_fertilizer")
	if r_fert.is_empty() or r_fert.machine != "workbench":
		_fail("Рецепт craft_fertilizer отсутствует или назначен не верстаку")
		return
	var r_bread = RecipeDB.get_recipe("bake_bread")
	if r_bread.is_empty() or r_bread.machine != "furnace":
		_fail("Рецепт bake_bread отсутствует или назначен не печи")
		return
	var r_c_seeds = RecipeDB.get_recipe("extract_carrot_seeds")
	var r_p_seeds = RecipeDB.get_recipe("extract_potato_seeds")
	var r_w_seeds = RecipeDB.get_recipe("extract_wheat_seeds")
	if r_c_seeds.is_empty() or r_p_seeds.is_empty() or r_w_seeds.is_empty():
		_fail("Рецепты извлечения семян на верстаке не найдены")
		return
	print("✅ Все 5 новых рецептов (удобрение, селекция 3 видов семян, выпечка хлеба) подтверждены.")
	
	# -------------------------------------------------------------
	# 3. Проверка механики голода и питания игрока
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Параметры сытости, дебаффы и прием пищи ---")
	if not ("hunger" in player) or not ("max_hunger" in player):
		_fail("У игрока отсутствуют поля сытости hunger / max_hunger")
		return
	
	if player.hunger < 95.0 or player.hunger > 100.0:
		_fail("Начальная сытость должна быть близка к 100 (получено: %.1f)" % player.hunger)
		return
	
	# Проверка ограничения спринта при истощении
	player.hunger = 8.0
	if player.can_sprint():
		_fail("Игрок не должен иметь возможность спринтовать при hunger <= 10.0")
		return
	print("  - Блокировка бега при голоде <= 10.0: работает корректно.")
	
	# Проверка поедания моркови
	inv.add_item("carrot", 2)
	var old_h = player.hunger
	var ok_eat = player.eat_food("carrot")
	if not ok_eat:
		_fail("Поедание моркови завершилось неудачей")
		return
	if player.hunger <= old_h:
		_fail("Сытость не увеличилась после съеденной моркови")
		return
	if inv.get_item_count("carrot") != 1:
		_fail("Морковь не списалась из инвентаря при еде")
		return
	print("  - Поедание моркови: сытость поднялась с %.1f до %.1f" % [old_h, player.hunger])
	
	# Проверка поедания хлеба
	inv.add_item("bread", 1)
	player.hunger = 30.0
	player.eat_food("bread")
	if player.hunger < 90.0:
		_fail("Хлеб должен восстанавливать 65 сытости (текущая: %.1f)" % player.hunger)
		return
	print("  - Поедание свежего хлеба: сытость поднялась до %.1f" % player.hunger)
	
	# -------------------------------------------------------------
	# 4. Проверка диалога со Степаном (Стартовый набор семян)
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Получение семян от караванщика Степана ---")
	inv.items["seeds_carrot"] = 0
	inv.items["seeds_potato"] = 0
	inv.items["seeds_wheat"] = 0
	trader_npc.starter_seeds_given = false
	
	trader_npc.interact(player)
	if inv.get_item_count("seeds_carrot") < 1 or inv.get_item_count("seeds_potato") < 1 or inv.get_item_count("seeds_wheat") < 1:
		_fail("Степан не выдал стартовые семена при первом диалоге")
		return
	print("  - Семена получены от Степана: carrot=%d, potato=%d, wheat=%d" % [
		inv.get_item_count("seeds_carrot"),
		inv.get_item_count("seeds_potato"),
		inv.get_item_count("seeds_wheat")
	])
	
	# -------------------------------------------------------------
	# 5. Полный цикл грядки FarmlandPlot: Вскопка, Посев, Полив, Удобрение, Созревание, Сбор
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Полный агрономический цикл на грядке FarmlandPlot1 ---")
	plot1.soil_state = FarmlandPlot.SoilState.UNTILLED
	plot1.crop_type = ""
	plot1.moisture = 0.0
	plot1.is_fertilized = false
	plot1.growth_progress = 0.0
	plot1.is_ripe = false
	
	# Попытка вскопки без лопаты
	var orig_tools = inv.tools.duplicate()
	inv.tools.clear()
	inv.equipped_tool = "axe"
	inv.items["shovel"] = 0
	var till_fail = plot1.till_soil(player)
	if till_fail or plot1.soil_state == FarmlandPlot.SoilState.TILLED:
		_fail("Вскопка должна требовать лопату")
		return
	print("  - Попытка вскопки без лопаты: успешно отклонена.")
	
	# Вскопка с лопатой
	inv.tools = orig_tools
	inv.equipped_tool = "shovel"
	var player_energy_before = player.energy
	var till_ok = plot1.till_soil(player)
	if not till_ok or plot1.soil_state != FarmlandPlot.SoilState.TILLED:
		_fail("Вскопка с лопатой не сработала")
		return
	if player.energy >= player_energy_before:
		_fail("Вскопка должна расходовать энергию игрока")
		return
	print("  - Вскопка лопатой выполнена. Земля взрыхлена (TILLED). Энергия израсходована.")
	
	# Посадка моркови
	var carrot_seeds_before = inv.get_item_count("seeds_carrot")
	var plant_ok = plot1.plant_crop("seeds_carrot", player)
	if not plant_ok or plot1.crop_type != "carrot":
		_fail("Посадка семян моркови не удалась")
		return
	if inv.get_item_count("seeds_carrot") != carrot_seeds_before - 1:
		_fail("Семя моркови не было списано из инвентаря")
		return
	print("  - Семена моркови высажены на грядку (crop_type = carrot, growth = 0%%).")
	
	# Полив водой
	inv.add_item("water", 2)
	var water_count_before = inv.get_item_count("water")
	var water_ok = plot1.water_plot(50.0, player)
	if not water_ok or plot1.moisture < 49.0:
		_fail("Полив грядки не сработал (влажность: %.1f)" % plot1.moisture)
		return
	if inv.get_item_count("water") != water_count_before - 1:
		_fail("Вода не списалась из рюкзака при поливе")
		return
	print("  - Полив грядки: влажность достигла %.1f%%." % plot1.moisture)
	
	# Внесение био-удобрения
	inv.add_item("fertilizer", 1)
	var fert_ok = plot1.apply_fertilizer(player)
	if not fert_ok or not plot1.is_fertilized:
		_fail("Внесение био-удобрения не сработало")
		return
	if inv.get_item_count("fertilizer") != 0:
		_fail("Удобрение не списалось из рюкзака")
		return
	print("  - Био-удобрение внесено: is_fertilized = true.")
	
	# Прогресс роста
	plot1.force_grow(45.0)
	if plot1.growth_progress < 45.0 or plot1.is_ripe:
		_fail("Прогресс вегетации некорректен")
		return
	print("  - Стадия вегетации (45%%): кусты сформированы.")
	
	# Завершение созревания
	plot1.force_grow(55.0)
	if not plot1.is_ripe or plot1.growth_progress < 100.0:
		_fail("Культура должна перейти в состояние зрелости is_ripe == true")
		return
	print("  - Созревание (100%%): урожай готов к уборке (is_ripe = true).")
	
	# Сбор урожая
	var inv_carrots_before = inv.get_item_count("carrot")
	var inv_seeds_before = inv.get_item_count("seeds_carrot")
	var harvest_res = plot1.harvest_crop(player)
	if harvest_res.get("yield", 0) < 3:
		_fail("Урожай моркови меньше ожидаемого базового количества (получено: %d)" % harvest_res.get("yield", 0))
		return
	if inv.get_item_count("carrot") != inv_carrots_before + harvest_res["yield"]:
		_fail("Морковь не добавлена в инвентарь игрока")
		return
	if inv.get_item_count("seeds_carrot") != inv_seeds_before + harvest_res["seeds"]:
		_fail("Возвратные семена не добавлены в инвентарь игрока")
		return
	if plot1.crop_type != "" or plot1.is_ripe:
		_fail("Грядка не была сброшена после сбора урожая")
		return
	if plot1.soil_state != FarmlandPlot.SoilState.TILLED:
		_fail("Грядка должна оставаться вскопанной для следующего посева")
		return
	print("  - Урожай моркови успешно собран: +%d моркови, +%d семян. Грядка готова к новому циклу!" % [
		harvest_res["yield"], harvest_res["seeds"]
	])
	
	# -------------------------------------------------------------
	# 6. Проверка других культур (Картофель и Пшеница)
	# -------------------------------------------------------------
	print("\n--- Проверка 6: Посадка и сбор картофеля и пшеницы ---")
	inv.add_item("seeds_potato", 1)
	plot2.till_soil(player)
	plot2.plant_crop("seeds_potato", player)
	plot2.skip_growth_to_ripe()
	var pot_res = plot2.harvest_crop(player)
	if inv.get_item_count("potato") < pot_res["yield"]:
		_fail("Картофель не получен при сборе со второй грядки")
		return
	print("  - Картофель успешно выращен и собран (+%d шт)." % pot_res["yield"])
	
	inv.add_item("seeds_wheat", 1)
	plot2.plant_crop("seeds_wheat", player)
	plot2.skip_growth_to_ripe()
	var wheat_res = plot2.harvest_crop(player)
	if inv.get_item_count("wheat") < wheat_res["yield"]:
		_fail("Пшеница не получена при сборе урожая")
		return
	print("  - Пшеница успешно выращена и собрана (+%d шт)." % wheat_res["yield"])
	
	# -------------------------------------------------------------
	# 7. Проверка селекции семян на верстаке
	# -------------------------------------------------------------
	print("\n--- Проверка 7: Селекция семян и крафт удобрений на верстаке ---")
	inv.add_item("clay", 2)
	inv.add_item("sawdust", 4)
	inv.add_item("water", 2)
	if not RecipeDB.can_craft(r_fert, inv):
		_fail("Игрок должен иметь возможность создать био-удобрение при наличии ресурсов")
		return
	print("  - Проверка сырья для био-удобрения: пройдена.")
	
	if not RecipeDB.can_craft(r_c_seeds, inv):
		_fail("Игрок должен иметь возможность извлечь семена из моркови")
		return
	print("  - Проверка сырья для извлечения семян моркови: пройдена.")
	
	# -------------------------------------------------------------
	# 8. Проверка новых контрактов в ContractDB
	# -------------------------------------------------------------
	print("\n--- Проверка 8: Контракты на сельхозпродукцию в ContractDB ---")
	var c_harvest = ContractDB.get_contract("contract_fresh_harvest")
	if c_harvest.is_empty() or not c_harvest.requirements.has("carrot") or not c_harvest.requirements.has("potato"):
		_fail("Контракт contract_fresh_harvest отсутствует или некорректен")
		return
	
	var c_grain = ContractDB.get_contract("contract_grain_supply")
	if c_grain.is_empty() or not c_grain.requirements.has("wheat") or not c_grain.requirements.has("bread"):
		_fail("Контракт contract_grain_supply отсутствует или некорректен")
		return
	
	# Обеспечим ресурсы для выполнения контракта на свежий урожай
	inv.add_item("carrot", 10)
	inv.add_item("potato", 10)
	var can_f: bool = ContractDB.can_fulfill(c_harvest, inv)
	if not can_f:
		_fail("Контракт contract_fresh_harvest должен быть готов к сдаче")
		return
	
	var cr_before = inv.credits
	var ok_ful: bool = ContractDB.fulfill_contract("contract_fresh_harvest", player)
	if not ok_ful:
		_fail("Сдача контракта contract_fresh_harvest провалилась")
		return
	if inv.credits != cr_before + c_harvest.reward_credits:
		_fail("Награда за контракт не была выплачена (было: %d, стало: %d)" % [cr_before, inv.credits])
		return
	print("  - Контракт «Свежий урожай для поселка» сдан: +%d кредитов!" % c_harvest.reward_credits)
	
	# -------------------------------------------------------------
	# Завершение
	# -------------------------------------------------------------
	print("\n========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 8 (СЕЛЬСКОЕ ХОЗЯЙСТВО) УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	quit(0)
