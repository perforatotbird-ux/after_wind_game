extends SceneTree

## Тест механики улучшения машин: уровни Lv.1→Lv.2→Lv.3, множители скорости,
## износа, питания и силы, бонус выхода, рецепты min_level, качественный ремонт,
## КПД топлива печи, сохранение уровня, блок апгрейда в окне станка.

const WorldScene = preload("res://scenes/world/world.tscn")
const MachinePanelScript = preload("res://scripts/ui/machine_panel.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")

var _test_executed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	root.add_child(WorldScene.instantiate())

func check(ok: bool, msg: String) -> void:
	if ok:
		print("  ✅ " + msg)
	else:
		_errors.append(msg)
		print("  ❌ " + msg)

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("========================================")
	print("🧪 ТЕСТ УЛУЧШЕНИЯ МАШИН (уровни, скорость, износ, компоненты)")
	print("========================================")
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player отсутствует")
	var inv = player.inventory
	var crusher = world.find_child("StoneCrusher", true, false)
	var workbench = world.find_child("Workbench", true, false)
	var smelter = world.find_child("Smelter", true, false)
	if not crusher or not workbench or not smelter: _fail("Не найдены станки")
	player.energy = 100.0

	# ---------- 1. Гейтинг: без ресурсов улучшения нет ----------
	print("\n--- 1. Улучшение: гейтинг и уровень Lv.2 ---")
	check(crusher.get_level() == 1, "Станок стартует на Lv.1")
	check(crusher.can_upgrade(), "Есть следующий уровень и стоимость")
	var stone_before: int = inv.get_item_count("stone")
	check(not crusher.upgrade_machine(player), "Без деталей улучшение отклонено")
	check(inv.get_item_count("stone") == stone_before, "Детали при отказе не списались")

	# ---------- 2. Апгрейд до Lv.2 и эффекты ----------
	inv.add_item("stone", 6)
	inv.add_item("iron_plate", 4)
	inv.add_item("gear", 2)
	inv.add_item("bolt", 4)
	check(crusher.upgrade_machine(player), "Улучшение до Lv.2 выполнено")
	check(crusher.get_level() == 2, "Уровень станка Lv.2")
	check(absf(crusher.wear.max_condition - 120.0) < 0.01, "Ресурс станка вырос до 120")

	# Скорость: crush_stone 20 с → 15 с
	inv.add_item("stone", 4)
	player.energy = 100.0
	check(crusher.start_batch("crush_stone", 1, player), "Партия запущена на Lv.2")
	check(absf(crusher.process_duration - 15.0) < 0.01, "Цикл Lv.2 длится ×0.75 (20 → %.1f с)" % crusher.process_duration)
	check(absf(crusher.get_power_demand() - 3.9) < 0.01, "Потребление сети Lv.2 ×1.3 (3.9 кВт)")
	crusher._complete_process()
	check(absf(crusher.wear.condition - 119.7) < 0.01, "Износ за цикл Lv.2 — 0.3 (120 → %.1f)" % crusher.wear.condition)
	check(int(crusher.pending_outputs.get("stone_dust", 0)) == 2, "Бонус выхода дробилки: 2 камня → 2 пыли")
	crusher.collect_outputs(player)
	crusher.cancel_batch()

	# ---------- 3. Рецепты min_level: появляются только после апгрейда ----------
	print("\n--- 3. Компоненты Lv.2 с улучшенного верстака ---")
	var lv1_recipes: Array = RecipeDB.get_recipes_for_machine("workbench", 1)
	var lv2_recipes: Array = RecipeDB.get_recipes_for_machine("workbench", 2)
	var has_steel_at_1: bool = false
	for r in lv1_recipes:
		if str(r.get("id", "")) == "craft_steel_plate": has_steel_at_1 = true
	var has_steel_at_2: bool = false
	for r in lv2_recipes:
		if str(r.get("id", "")) == "craft_steel_plate": has_steel_at_2 = true
	check(not has_steel_at_1 and has_steel_at_2, "Стальная пластина — рецепт Lv.2 (нет на Lv.1, есть на Lv.2)")
	# На базовом верстаке рецепт недоступен даже с ресурсами
	inv.add_item("iron_plate", 6)
	inv.add_item("coal", 4)
	player.energy = 100.0
	check(not workbench.start_recipe("craft_steel_plate", player), "На Lv.1 верстак отказывает в рецепте Lv.2")
	inv.add_item("wooden_handle", 2)
	inv.add_item("gear", 2)
	inv.add_item("bolt", 4)
	check(workbench.upgrade_machine(player), "Верстак улучшен до Lv.2")
	check(workbench.start_recipe("craft_steel_plate", player), "На Lv.2 рецепт работает")
	workbench._complete_process()
	check(int(workbench.pending_outputs.get("steel_plate", 0)) == 1, "Стальная пластина изготовлена")
	workbench.collect_outputs(player)

	# ---------- 4. Качественный ремонт (+70%) ----------
	print("\n--- 4. Качественный ремонт стальными деталями ---")
	workbench.wear.set_condition(30.0)
	inv.add_item("bolt", 4)
	inv.add_item("steel_plate", 2) # +1 пластина уже есть из крафта
	check(workbench.repair_machine(player, true), "Качественный ремонт выполнен")
	check(absf(workbench.wear.condition - 114.0) < 0.01, "Качественный ремонт: +70%% (30 → %.0f)" % workbench.wear.condition)
	check(inv.get_item_count("bolt") == 2 and inv.get_item_count("steel_plate") == 2, "Стальные детали списаны (2 болта, 1 пластина)")
	workbench.wear.set_condition(30.0)
	inv.add_item("wooden_handle", 1)
	check(workbench.repair_machine(player), "Обычный ремонт работает как раньше")
	check(absf(workbench.wear.condition - 90.0) < 0.01, "Обычный ремонт: +50%% (30 → %.0f)" % workbench.wear.condition)

	# ---------- 5. КПД топлива печи на Lv.2 ----------
	print("\n--- 5. Печь Lv.2: КПД топлива ×1.3 ---")
	inv.add_item("coal", 2)
	smelter.add_fuel_from_inventory(inv, "coal")
	player.energy = 100.0
	inv.add_item("poor_brick", 2)
	check(smelter.start_recipe("smelt_brick", player), "Печь Lv.1 запущена")
	smelter.fuel_burn_left = 240.0
	smelter._process(1.0)
	check(absf(smelter.fuel_burn_left - 239.0) < 0.01, "Lv.1: уголь горит 1:1 (240 → %.2f)" % smelter.fuel_burn_left)
	smelter.cancel_batch()
	inv.add_item("fired_brick", 6)
	inv.add_item("iron_plate", 6)
	inv.add_item("gear", 2)
	inv.add_item("bolt", 4)
	check(smelter.upgrade_machine(player), "Печь улучшена до Lv.2")
	inv.add_item("poor_brick", 2)
	check(smelter.start_recipe("smelt_brick", player), "Печь Lv.2 запущена")
	smelter.fuel_burn_left = 240.0
	smelter._process(1.0)
	check(absf(smelter.fuel_burn_left - (240.0 - 1.0 / 1.3)) < 0.01, "Lv.2: КПД ×1.3 (240 → %.2f)" % smelter.fuel_burn_left)
	smelter.cancel_batch()

	# ---------- 6. Улучшение до Lv.3 и предел ----------
	print("\n--- 6. Lv.3 и максимальный уровень ---")
	check(not crusher.upgrade_machine(player), "Пока станок работает, улучшение отклонено")
	crusher.cancel_batch()
	inv.add_item("steel_plate", 4)
	inv.add_item("precision_gear", 2)
	inv.add_item("iron_plate", 4)
	inv.add_item("bolt", 6)
	check(crusher.upgrade_machine(player), "Дробилка улучшена до Lv.3")
	check(crusher.get_level() == 3, "Уровень станка Lv.3")
	check(not crusher.can_upgrade(), "Lv.3 — максимум, улучшение недоступно")
	check(not crusher.upgrade_machine(player), "Повторное улучшение отклонено")
	inv.add_item("stone", 4)
	player.energy = 100.0
	crusher.start_batch("crush_stone", 1, player)
	check(absf(crusher.process_duration - 12.0) < 0.01, "Цикл Lv.3 длится ×0.6 (20 → %.1f с)" % crusher.process_duration)
	crusher._complete_process()
	check(int(crusher.pending_outputs.get("stone_dust", 0)) == 3, "Бонус выхода Lv.3: 2 камня → 3 пыли")
	crusher.collect_outputs(player)
	crusher.cancel_batch()

	# ---------- 7. Сохранение уровня ----------
	print("\n--- 7. Уровень сохраняется ---")
	check(SaveManager.save_game(world), "Игра сохранена")
	var saved_level: int = crusher.get_level()
	crusher.level_state.set_level(1)
	crusher.wear.max_condition = 100.0
	check(SaveManager.load_game(world), "Игра загружена")
	check(crusher.get_level() == saved_level, "Уровень станка восстановлен из сейва (Lv.%d)" % crusher.get_level())

	# ---------- 8. Окно станка: бейдж уровня и блок улучшения ----------
	print("\n--- 8. Окно станка ---")
	var panel = MachinePanelScript.new()
	panel.setup(crusher, player)
	root.add_child(panel)
	panel._refresh()
	check("Lv.3" in panel._title_label.text, "В заголовке окна бейдж уровня (Lv.3)")
	check(not panel._upgrade_btn.visible, "На максимальном уровне блок улучшения скрыт")
	check(panel._repair_q_btn.visible, "Кнопка качественного ремонта на месте")
	panel.close()

	print("========================================")
	if _errors.is_empty():
		print("🎉 ВСЕ ПРОВЕРКИ УЛУЧШЕНИЯ МАШИН ПРОЙДЕНЫ!")
		print("========================================")
		quit(0)
	else:
		for e in _errors:
			print("ПРОВАЛЕН: ", e)
		print("========================================")
		quit(1)
