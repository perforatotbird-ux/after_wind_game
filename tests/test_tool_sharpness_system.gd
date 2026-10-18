extends SceneTree

## Комплексный тест системы заточки и затупления инструментов.
## Проверяет:
## 1. Инициализацию и градации эффективности (Бритвенная, Рабочая, Затупленная, Критическая).
## 2. Списание остроты, множитель для закалённых инструментов Lv.2, защиту ведра и рюкзака.
## 3. Предмет «Точильный брусок» (whetstone) и рецепты верстака (craft_whetstone, sharpen_*).
## 4. Работу производственного станка (верстак доводит лезвие до 100%).
## 5. Сериализацию и восстановление данных через SaveManager.
## 6. Визуальные индикаторы и подсказки в HUD.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const HudScene = preload("res://scenes/ui/hud.tscn")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_sharpness_initialization_and_protection()
	_test_sharpness_efficiency_tiers()
	_test_sharpness_consumption_and_upgrade_discount()
	_test_whetstone_item_and_crafting()
	_test_workbench_sharpening_completion()
	_test_save_load_persistence()
	_test_hud_ui_indicators()

	if errors.is_empty():
		print("PASS: test_tool_sharpness_system — система заточки и обслуживания инструментов работает безупречно!")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)

func _test_sharpness_initialization_and_protection() -> void:
	var inv := Inventory.new()
	
	# Начальное состояние: 100% для рабочих режущих инструментов
	check(is_equal_approx(inv.get_tool_sharpness("axe"), 100.0), "Топор должен быть изначально заточен на 100%")
	check(is_equal_approx(inv.get_tool_sharpness("pickaxe"), 100.0), "Кирка должна быть изначально заточена на 100%")
	check(is_equal_approx(inv.get_tool_sharpness("shovel"), 100.0), "Мотыга должна быть изначально заточена на 100%")
	
	# Защита: ведро и рюкзак не тупятся
	check(inv.is_sharp_tool("axe"), "axe должен распознаваться как режущий инструмент")
	check(inv.is_sharp_tool("iron_axe"), "iron_axe должен распознаваться как режущий инструмент")
	check(inv.is_sharp_tool("pickaxe"), "pickaxe должен распознаваться как режущий инструмент")
	check(inv.is_sharp_tool("iron_pickaxe"), "iron_pickaxe должен распознаваться как режущий инструмент")
	check(inv.is_sharp_tool("shovel"), "shovel должен распознаваться как режущий инструмент")
	check(inv.is_sharp_tool("iron_shovel"), "iron_shovel должен распознаваться как режущий инструмент")
	check(not inv.is_sharp_tool("bucket"), "bucket не должен подлежать затуплению")
	check(not inv.is_sharp_tool("backpack"), "backpack не должен подлежать затуплению")
	check(is_equal_approx(inv.get_tool_sharpness("bucket"), 100.0), "Острота ведра всегда 100%")
	check(is_equal_approx(inv.get_tool_sharpness("backpack"), 100.0), "Острота рюкзака всегда 100%")
	
	inv.free()

func _test_sharpness_efficiency_tiers() -> void:
	var inv := Inventory.new()
	
	# 1. Бритвенная острота (100%..75%)
	inv.tool_sharpness["axe"] = 90.0
	var eff_razor := inv.get_sharpness_efficiency("axe")
	check(is_equal_approx(eff_razor.power_mult, 1.0), "Бритвенная острота: множитель урона 1.0")
	check(is_equal_approx(eff_razor.energy_cost_mult, 0.9), "Бритвенная острота: расход энергии 0.9 (-10%)")
	check(not eff_razor.is_dull, "Бритвенная острота: не затуплен")
	check(is_equal_approx(eff_razor.crit_bonus, 0.10), "Бритвенная острота: +10% шанс крита")
	check(eff_razor.status_name == "Бритвенная острота", "Название статуса: Бритвенная острота")

	# 2. Рабочая заточка (74%..35%)
	inv.tool_sharpness["axe"] = 55.0
	var eff_work := inv.get_sharpness_efficiency("axe")
	check(is_equal_approx(eff_work.power_mult, 1.0), "Рабочая заточка: множитель урона 1.0")
	check(is_equal_approx(eff_work.energy_cost_mult, 1.0), "Рабочая заточка: расход энергии 1.0")
	check(not eff_work.is_dull, "Рабочая заточка: не затуплен")
	check(is_equal_approx(eff_work.crit_bonus, 0.0), "Рабочая заточка: нет бонуса крита")
	check(eff_work.status_name == "Рабочая заточка", "Название статуса: Рабочая заточка")

	# 3. Затупленное (34%..10%)
	inv.tool_sharpness["axe"] = 25.0
	var eff_dull := inv.get_sharpness_efficiency("axe")
	check(is_equal_approx(eff_dull.power_mult, 0.75), "Затупленное: множитель урона 0.75 (-25%)")
	check(is_equal_approx(eff_dull.energy_cost_mult, 1.25), "Затупленное: расход энергии 1.25 (+25%)")
	check(eff_dull.is_dull, "Затупленное: помечен как is_dull")
	check(eff_dull.status_name == "Затупленное", "Название статуса: Затупленное")

	# 4. Критически тупое (9%..0%)
	inv.tool_sharpness["axe"] = 5.0
	var eff_blunt := inv.get_sharpness_efficiency("axe")
	check(is_equal_approx(eff_blunt.power_mult, 0.50), "Критически тупое: множитель урона 0.50 (-50%)")
	check(is_equal_approx(eff_blunt.energy_cost_mult, 1.50), "Критически тупое: расход энергии 1.50 (+50%)")
	check(eff_blunt.is_dull, "Критически тупое: помечен как is_dull")
	check(eff_blunt.status_name == "Критически тупое", "Название статуса: Критически тупое")

	inv.free()

func _test_sharpness_consumption_and_upgrade_discount() -> void:
	var inv := Inventory.new()
	
	# Списание у базового инструмента
	var s_after: float = inv.consume_tool_sharpness("pickaxe", 10.0)
	check(is_equal_approx(s_after, 90.0), "После списания 10%% острота должна быть 90%%, получено %.1f" % s_after)
	
	# Улучшенный инструмент Lv.2 изнашивается на 40% медленнее (множитель 0.6)
	inv.upgrade_tool("iron_pickaxe")
	check(inv.get_tool_level("pickaxe") == 2, "Уровень кирки должен быть 2 после улучшения")
	s_after = inv.consume_tool_sharpness("pickaxe", 10.0)
	# 90.0 - (10.0 * 0.6) = 84.0
	check(is_equal_approx(s_after, 84.0), "Инструмент Lv.2 должен потерять 6%% вместо 10%%, получено %.1f" % s_after)
	
	# Заточка точильным камнем на +40%
	var s_sharpened: float = inv.sharpen_tool("pickaxe", 40.0)
	# 84.0 + 40.0 = 124.0 -> clamp to 100.0
	check(is_equal_approx(s_sharpened, 100.0), "Заточка должна ограничиваться максимумом 100%%, получено %.1f" % s_sharpened)
	
	# Списание у нережущих предметов не изменяет ничего
	var b_res: float = inv.consume_tool_sharpness("bucket", 10.0)
	check(is_equal_approx(b_res, 100.0), "Списание у ведра должно возвращать 100.0")

	inv.free()

func _test_whetstone_item_and_crafting() -> void:
	# Предмет в ItemDB
	var item: Dictionary = ItemDB.get_item("whetstone")
	check(not item.is_empty(), "Предмет 'whetstone' должен существовать в ItemDB")
	check(item.get("name", "") == "Точильный камень", "Название предмета должно быть 'Точильный камень'")
	check(float(item.get("weight", 0.0)) == 0.5, "Вес точильного камня должен быть 0.5 кг")
	check(int(item.get("sell_price", 0)) == 18, "Цена продажи точильного камня должна быть 18")

	# Крафт точильного камня на верстаке
	var r_craft: Dictionary = RecipeDB.get_recipe("craft_whetstone")
	check(not r_craft.is_empty(), "Рецепт 'craft_whetstone' должен существовать в RecipeDB")
	check(r_craft.get("machine", "") == "workbench", "Крафт точильного камня должен происходить на верстаке")
	check(int(r_craft.get("inputs", {}).get("stone", 0)) == 2, "Рецепт точильного камня требует 2 камня")
	check(int(r_craft.get("inputs", {}).get("sand", 0)) == 1, "Рецепт точильного камня требует 1 песок")

	# Рецепты заточки инструментов на верстаке
	for t in ["axe", "pickaxe", "shovel"]:
		var r_sharp: Dictionary = RecipeDB.get_recipe("sharpen_" + t)
		check(not r_sharp.is_empty(), "Рецепт 'sharpen_%s' должен существовать" % t)
		check(r_sharp.get("machine", "") == "workbench", "Заточка должна быть на верстаке")
		check(int(r_sharp.get("inputs", {}).get("water", 0)) == 1, "Заточка требует 1 воду")

func _test_workbench_sharpening_completion() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	player.inventory.tool_sharpness["axe"] = 20.0
	check(is_equal_approx(player.inventory.get_tool_sharpness("axe"), 20.0), "У топора должно быть 20% заточки")

	var machine := ProductionMachine.new()
	machine.machine_type = "workbench"
	machine.requires_rebuild = false
	machine.rebuilt = true
	root.add_child(machine)

	player.inventory.add_item("water", 5)
	var started: bool = machine.start_recipe("sharpen_axe", player)
	check(started, "Рецепт заточки топора должен успешно запуститься")

	# Принудительно завершаем цикл
	machine.process_timer = machine.process_duration
	machine._complete_process()

	check(is_equal_approx(player.inventory.get_tool_sharpness("axe"), 100.0), "Топор после завершения заточки на верстаке должен быть 100%")

	machine.queue_free()
	player.queue_free()

func _test_save_load_persistence() -> void:
	var temp_save_path := "user://test_sharpness_save.json"
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	var player = PlayerScene.instantiate()
	player.name = "Player"
	world.add_child(player)

	# Выставляем разные проценты остроты
	player.inventory.tool_sharpness["axe"] = 82.5
	player.inventory.tool_sharpness["pickaxe"] = 44.0
	player.inventory.tool_sharpness["shovel"] = 12.0

	var save_ok: bool = SaveManager.save_game(world, temp_save_path)
	check(save_ok, "Сохранение игры должно пройти успешно")

	# Сбрасываем значения у игрока
	player.inventory.tool_sharpness["axe"] = 100.0
	player.inventory.tool_sharpness["pickaxe"] = 100.0
	player.inventory.tool_sharpness["shovel"] = 100.0

	var load_ok: bool = SaveManager.load_game(world, temp_save_path)
	check(load_ok, "Загрузка сохранения должна пройти успешно")

	check(is_equal_approx(player.inventory.get_tool_sharpness("axe"), 82.5), "Острота топора должна загрузиться как 82.5%")
	check(is_equal_approx(player.inventory.get_tool_sharpness("pickaxe"), 44.0), "Острота кирки должна загрузиться как 44.0%")
	check(is_equal_approx(player.inventory.get_tool_sharpness("shovel"), 12.0), "Острота мотыги должна загрузиться как 12.0%")

	DirAccess.remove_absolute(temp_save_path)
	world.queue_free()

func _test_hud_ui_indicators() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	player.inventory.tool_sharpness["axe"] = 65.0

	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud.bind_player(player)

	# Проверяем наличие полосок SharpnessBar на слотах 1-3
	for i in [0, 1, 2]:
		var btn: Button = hud.slot_buttons[i]
		var bar: ProgressBar = btn.get_node_or_null("SharpnessBar") as ProgressBar
		check(bar != null, "На слоте %d должен присутствовать узел SharpnessBar" % (i + 1))

	var slot1_btn: Button = hud.slot_buttons[0]
	var slot1_bar: ProgressBar = slot1_btn.get_node_or_null("SharpnessBar") as ProgressBar
	check(is_equal_approx(slot1_bar.value, 65.0), "Полоска остроты слота 1 должна показывать 65%%, получено %.1f" % slot1_bar.value)
	check("Заточка: 65%" in slot1_btn.tooltip_text, "Тултип слота 1 должен содержать строку 'Заточка: 65%%', найдено: '%s'" % slot1_btn.tooltip_text)

	hud.queue_free()
	player.queue_free()
