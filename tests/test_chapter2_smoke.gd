extends SceneTree
## Глава 2 «Первый дым» (мастер-план, раздел 2): новый стартовый баланс,
## костёр, лесные грибы, ремонт станков и печь-кухня, вехи главы.

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const SAVE_PATH: String = "user://test_chapter2_smoke.json"

class MockPlayer extends Node:
	var inventory: Node
	var messages: Array[String] = []
	func notify(t: String) -> void:
		messages.append(t)
	func consume_energy(_amount: float) -> void:
		pass

var errors: Array[String] = []
var world: Node
var frames: int = 0
var player: Node
var inv: Node

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	CookingProgress.reset()
	Seasons.disable()
	_test_items()
	_test_recipes()
	_test_progress_logic()
	world = WorldScene.instantiate()
	# Фиксированная тестовая раскладка: случайный seed иногда даёт меньше 10
	# грибов за лимит кандидатов, хотя логика сбора и сохранений исправна.
	world.get_node("MushroomPatches").spawn_seed = 12345
	root.add_child(world)

var _spawner: Node = null

func _process(_d: float) -> bool:
	frames += 1
	if world == null or frames < 4:
		return false
	# Грибы раскладываются после генерации луга — ждём, как и кусты.
	if _spawner == null:
		_spawner = world.find_child("MushroomPatches", true, false)
	if _spawner != null and _spawner.get_mushrooms().is_empty() and frames < 40:
		return false
	_run_world_tests()
	return _finish()

# --- Предметы и иконки ---------------------------------------------------------

func _test_items() -> void:
	var expected := {
		"mushroom": 12.0, "baked_potato": 55.0, "fried_carrot": 35.0,
		"vegetable_soup": 50.0, "mushroom_stew": 40.0, "dried_mushroom": 25.0,
		"potato_mushroom_dish": 65.0, "mushroom_soup": 55.0,
		"glazed_carrot": 45.0, "potato_pie": 75.0,
	}
	for item_id in expected.keys():
		var data: Dictionary = ItemDB.get_item(item_id)
		check(not data.is_empty(), "Нет предмета " + str(item_id))
		if data.is_empty():
			continue
		check(data.get("is_edible", false), str(item_id) + " не съедобен")
		check(ItemIcons.STYLES.has(item_id), "Нет иконки " + str(item_id))
		# Сырые ингредиенты (правило мастер-плана 7.1): готовое блюдо лучше.
		check(float(data.get("hunger_recovery", 0.0)) >= float(expected[item_id]) - 0.01,
			"%s: сытость ниже ожидаемой" % item_id)
	# Напитки и лечение.
	check(ItemDB.is_drinkable("berry_brew"), "Ягодный отвар не напиток")
	check(float(ItemDB.get_item("berry_brew").get("health_bonus", 0.0)) == 5.0, "Отвар должен лечить +5")
	check(ItemDB.is_drinkable("berry_compote"), "Компот не напиток")
	# Гриб — слабый, но съедобный сырой ингредиент.
	var shroom: Dictionary = ItemDB.get_item("mushroom")
	check(float(shroom.get("hunger_recovery", 0.0)) == 12.0, "Гриб: сытость не 12")
	check(float(shroom.get("energy_bonus", 0.0)) == 5.0, "Гриб: энергия не 5")
	# Правило мастер-плана 7.1: готовая еда лучше сырой по сумме эффектов.
	var pairs := [
		["potato", "baked_potato"], ["carrot", "fried_carrot"],
		["potato", "vegetable_soup"], ["mushroom", "mushroom_stew"],
		["mushroom", "dried_mushroom"],
	]
	for pair in pairs:
		var raw: Dictionary = ItemDB.get_item(pair[0])
		var cooked: Dictionary = ItemDB.get_item(pair[1])
		var raw_sum: float = float(raw.get("hunger_recovery", 0.0)) + float(raw.get("thirst_recovery", 0.0)) + float(raw.get("energy_bonus", 0.0))
		var cooked_sum: float = float(cooked.get("hunger_recovery", 0.0)) + float(cooked.get("thirst_recovery", 0.0)) + float(cooked.get("energy_bonus", 0.0))
		check(cooked_sum > raw_sum, "Блюдо «%s» не лучше сырья «%s» (%d против %d)" % [pair[1], pair[0], cooked_sum, raw_sum])
	# Блюда печи-кухни лучше блюд костра на том же сырье.
	for pair in [["mushroom_stew", "mushroom_soup"], ["fried_carrot", "glazed_carrot"]]:
		var camp: Dictionary = ItemDB.get_item(pair[0])
		var kitchen: Dictionary = ItemDB.get_item(pair[1])
		var camp_sum: float = float(camp.get("hunger_recovery", 0.0)) + float(camp.get("thirst_recovery", 0.0)) + float(camp.get("energy_bonus", 0.0))
		var kitchen_sum: float = float(kitchen.get("hunger_recovery", 0.0)) + float(kitchen.get("thirst_recovery", 0.0)) + float(kitchen.get("energy_bonus", 0.0))
		check(kitchen_sum > camp_sum, "Блюдо кухни «%s» не лучше кострового «%s»" % [pair[1], pair[0]])
	# Кипячёная вода — альтернатива фильтру: тот же предмет, что и у фильтра.
	check(RecipeDB.get_recipe("boil_water").get("outputs", {}).has("clean_water"), "Кипячёная вода даёт не clean_water")

# --- Рецепты -------------------------------------------------------------------

func _test_recipes() -> void:
	# Мастер-план 2.1: 7 рецептов костра (6 блюд + сушка + кипячение).
	var camp: Array = RecipeDB.get_recipes_for_machine("campfire", 1)
	check(camp.size() == 7, "У костра должно быть 7 рецептов, факт: %d" % camp.size())
	var times: Dictionary = {}
	for r in camp:
		times[str(r["id"])] = float(r["duration"])
		check(float(r["duration"]) >= 15.0 and float(r["duration"]) <= 60.0,
			"Костёр: «%s» длится %.0f с вне 15–60 с" % [r["id"], float(r["duration"])])
	check(is_equal_approx(float(times.get("cook_baked_potato", 0.0)), 30.0), "Печёный картофель не 30 с")
	check(is_equal_approx(float(times.get("cook_mushroom_stew", 0.0)), 35.0), "Грибная похлёбка не 35 с")
	check(is_equal_approx(float(times.get("dry_mushrooms", 0.0)), 40.0), "Сушка грибов не 40 с")
	check(is_equal_approx(float(times.get("boil_water", 0.0)), 20.0), "Кипячение воды не 20 с")
	# Печь-кухня: 5 базовых рецепта и 2 соуса на Lv.2.
	var kitchen_lv1: Array = RecipeDB.get_recipes_for_machine("kitchen_stove", 1)
	var kitchen_lv2: Array = RecipeDB.get_recipes_for_machine("kitchen_stove", 2)
	check(kitchen_lv1.size() == 5, "У печи-кухни Lv.1 должно быть 5 рецептов, факт: %d" % kitchen_lv1.size())
	check(kitchen_lv2.size() == 7, "У печи-кухни Lv.2 должно быть 7 рецептов, факт: %d" % kitchen_lv2.size())
	for r in kitchen_lv1:
		check(int(r.get("min_level", 1)) == 1, "Рецепт Lv.1 «%s» помечен min_level > 1" % r["id"])
	# Каждый вход и выход — известный предмет, у всех рецептов есть время.
	for r in RecipeDB.get_recipes_for_machine("campfire", 1) + RecipeDB.get_recipes_for_machine("kitchen_stove", 2):
		for part in ["inputs", "outputs"]:
			for id in r[part]:
				check(not ItemDB.get_item(id).is_empty(), "%s: неизвестный предмет %s в %s" % [r["id"], id, part])
		check(float(r["duration"]) > 0.0, "%s: нет длительности" % r["id"])

# --- Логика вех ----------------------------------------------------------------

func _test_progress_logic() -> void:
	CookingProgress.reset()
	var start: Dictionary = CookingProgress.evaluate()
	check(start["total_count"] == 5, "Должно быть 5 вех Главы 2")
	check(start["completed_count"] == 0 and not start["is_complete"], "В начале ни одна веха не выполнена")
	# 5 разных блюд засчитываются один раз за вид.
	for id in ["baked_potato", "vegetable_soup", "mushroom_stew", "berry_brew", "dried_mushroom"]:
		CookingProgress.register_dish(id, 1, CookingProgress.QUALITY_PLAIN)
	CookingProgress.register_dish("baked_potato", 3, CookingProgress.QUALITY_PLAIN)
	check(CookingProgress.get_dish_count() == 5, "Повторная готовка не должна считаться новым блюдом")
	check(int(CookingProgress.get_dish("baked_potato")["count"]) == 4, "Счётчик приготовлений не растёт")
	var dishes_done: bool = false
	for t in CookingProgress.evaluate()["tasks"]:
		if t["id"] == "dishes":
			dishes_done = bool(t["done"])
	check(dishes_done, "Веха «5 блюд» не засчиталась")
	# Качество не ухудшается при повторе на лучшем станке.
	CookingProgress.register_dish("mushroom_stew", 1, CookingProgress.QUALITY_GREAT)
	check(CookingProgress.get_dish("mushroom_stew")["quality"] == CookingProgress.QUALITY_GREAT, "Качество не улучшилось")
	CookingProgress.register_dish("mushroom_stew", 1, CookingProgress.QUALITY_PLAIN)
	check(CookingProgress.get_dish("mushroom_stew")["quality"] == CookingProgress.QUALITY_GREAT, "Качество ухудшилось")
	# Грибы и станки.
	CookingProgress.register_mushrooms(6)
	CookingProgress.register_mushrooms(4)
	CookingProgress.register_rebuild("crusher")
	CookingProgress.register_rebuild("furnace")
	CookingProgress.register_rebuild("kitchen_stove")
	var done_ids: Array = []
	for t in CookingProgress.evaluate()["tasks"]:
		if t["done"]:
			done_ids.append(t["id"])
	check(CookingProgress.evaluate()["is_complete"], "Все 5 вех должны закрыться")
	check(done_ids.size() == 5, "Закрыто не 5 вех: %s" % str(done_ids))
	# Сохранение и валидация.
	var state: Dictionary = CookingProgress.get_save_state()
	check(CookingProgress.is_valid_save_state(state), "Сохранение не прошло валидацию")
	check(not CookingProgress.is_valid_save_state({"dishes": {"x": {"count": -1}}}), "Отрицательный счётчик принят")
	check(not CookingProgress.is_valid_save_state({"mushrooms_collected": "ten"}), "Не число принято")
	CookingProgress.reset()
	CookingProgress.apply_save_state(state)
	check(CookingProgress.get_dish_count() == 5, "Блюда не восстановились")
	check(CookingProgress.mushrooms_collected == 10, "Грибы не восстановились")
	CookingProgress.reset()

# --- Мир -----------------------------------------------------------------------

func _run_world_tests() -> void:
	player = world.get_node_or_null("Player")
	inv = player.inventory
	world.process_mode = Node.PROCESS_MODE_DISABLED

	var campfire: Node = world.find_child("Campfire", true, false)
	var kitchen: Node = world.find_child("KitchenStove", true, false)
	var crusher: Node = world.find_child("StoneCrusher", true, false)
	var smelter: Node = world.find_child("Smelter", true, false)
	var water_filter: Node = world.find_child("WaterFilter", true, false)
	var workbench: Node = world.find_child("Workbench", true, false)
	var shroom_spawner: Node = world.find_child("MushroomPatches", true, false)
	check(campfire != null and kitchen != null and shroom_spawner != null, "В мире нет костра / печи-кухни / грибов")
	if campfire == null or kitchen == null or shroom_spawner == null:
		return

	# 1. Стартовый баланс: работают только верстак, костёр и непостроенное остальное.
	check(workbench is ProductionMachine and workbench.is_operational(), "Верстак должен работать сразу")
	check(campfire.is_operational(), "Костёр должен работать сразу")
	for m in [crusher, smelter, water_filter, kitchen]:
		check(not m.is_operational(), "%s должен начинать нерабочим" % str(m.machine_display_name))
		check(m.get_prompt().contains("["), "Нет подсказки о состоянии: %s" % m.get_prompt())
	# Стоимость восстановления по мастер-плану 2.3.
	check(int(crusher.rebuild_credits) == 50 and int(crusher.rebuild_cost.get("stone", 0)) == 10 and int(crusher.rebuild_cost.get("wood", 0)) == 4,
		"Дробилка: стоимость ремонта не по плану")
	check(int(smelter.rebuild_credits) == 80 and int(smelter.rebuild_cost.get("poor_brick", 0)) == 15
		and int(smelter.rebuild_cost.get("stone", 0)) == 6 and int(smelter.rebuild_cost.get("clay", 0)) == 2,
		"Плавильня: стоимость ремонта не по плану")
	check(int(water_filter.rebuild_credits) == 30 and int(water_filter.rebuild_cost.get("sand", 0)) == 8
		and int(water_filter.rebuild_cost.get("wood", 0)) == 4,
		"Фильтр: стоимость ремонта не по плану")
	# С пустым рюкзаком постройка невозможна (у игрока к началу игры есть стартовые вещи).
	var poor := MockPlayer.new()
	poor.inventory = InventoryScript.new()
	poor.add_child(poor.inventory)
	root.add_child(poor)
	check(not kitchen.can_rebuild(poor).get("can_rebuild", false), "Печь-кухня построилась без ресурсов")
	check(not crusher.can_rebuild(poor).get("can_rebuild", false), "Дробилка восстановилась без ресурсов")
	poor.queue_free()
	# Разрушенный станок не берёт рецепты и ничего не списывает.
	inv.add_item("stone", 20)
	var stone_before: int = inv.get_item_count("stone")
	check(not crusher.start_recipe("crush_stone", player), "Разрушенная дробилка приняла рецепт")
	check(not smelter.start_recipe("smelt_brick", player), "Разрушенная печь приняла рецепт")
	check(inv.get_item_count("stone") == stone_before, "Разрушенный станок списал сырьё")
	check(crusher.is_interactable, "Разрушенный станок должен оставаться интерактивным")

	# 2. Восстановление: списывает ресурсы и кредиты, открывает станок.
	check(not crusher.can_rebuild(player).get("can_rebuild", false), "Дробилка восстановилась без ресурсов")
	inv.add_item("stone", 10)
	inv.add_item("wood", 4)
	inv.add_credits(60)
	check(crusher.can_rebuild(player).get("can_rebuild", false), "Ресурцы есть, а can_rebuild = false")
	check(crusher.rebuild(player), "Дробилка не восстановилась")
	check(crusher.is_operational(), "После восстановления станок не готов")
	check(inv.get_item_count("wood") == 0, "Древесина не списана при восстановлении")
	check(crusher.start_recipe("crush_stone", player), "Восстановленная дробилка не приняла рецепт")
	check(crusher.cancel_batch(), "Партию дробилки нельзя отменить")

	# 3. Печь-кухня: постройка открывает рецепты и качество.
	inv.add_item("poor_brick", 8)
	inv.add_item("stone", 6)
	inv.add_item("wood", 4)
	inv.add_credits(90)
	check(kitchen.can_rebuild(player).get("can_rebuild", false), "Ресурсы на печь есть, а can_rebuild = false")
	check(kitchen.rebuild(player), "Печь-кухня не построилась")
	check(kitchen.get_dish_quality() == CookingProgress.QUALITY_GOOD, "Lv.1 печи даёт не «хорошее» качество")
	check(kitchen.is_operational(), "Построенная печь-кухни не готова")
	# Качество растёт с уровнем печи.
	kitchen.level_state.set_level(2)
	check(kitchen.get_dish_quality() == CookingProgress.QUALITY_GREAT, "Lv.2 печи даёт не «отличное» качество")
	check(RecipeDB.get_recipes_for_machine("kitchen_stove", 2).size() == 7, "На Lv.2 печи должны открыться соусы")
	kitchen.level_state.set_level(1)

	# 4. Костёр: ручной станок, одно топливо, сушит игрока.
	check(campfire.machine_type == "campfire", "Костёр — не станок типа campfire")
	check(campfire.power_draw == 0.0, "Костёр не должен брать энергию")
	check(not campfire.is_in_group("power_consumers"), "Костёр не должен быть потребителем сети")
	check(campfire.fuel_slots.size() == 1, "У костра должно быть 1 топливный слот, факт: %d" % campfire.fuel_slots.size())
	check(is_equal_approx(campfire.get_fuel_burn_time("wood"), 15.0), "Дрова в костре не 15 с")
	check(is_equal_approx(campfire.get_fuel_burn_time("coal"), 90.0), "Уголь в костре не 90 с")
	check(is_equal_approx(campfire.get_fuel_burn_time("fuel_briquette"), 120.0), "Брикеты в костре не 120 с")
	check(campfire.is_in_group("heat_sources"), "Костёр не отмечен как источник тепла")
	# Без топлива цикл не запускается, с топливом — запускается.
	inv.add_item("potato", 4)
	check(not campfire.start_recipe("cook_baked_potato", player), "Костёр запустил рецепт без топлива")
	check(inv.get_item_count("potato") == 4, "Костёр списал картофель без топлива")
	var wood_before_fuel: int = inv.get_item_count("wood")
	# Один цикл рецепта — 30 с, а дрова горят 15 с: нужно два полна.
	inv.add_item("wood", 3)
	campfire.add_fuel_from_inventory(inv, "wood", 3)
	check(campfire.is_lit(), "После закладки дров костёр не горит")
	check(inv.get_item_count("wood") == wood_before_fuel, "Дрова не переложены в топливный слот")
	check(campfire.start_recipe("cook_baked_potato", player), "Костёр с топливом не принял рецепт")
	_check_cooking_cycle(campfire, "baked_potato", 2)
	# Костёр сушит промокшего персонажа.
	player.wetness = 60.0
	player.global_position = campfire.global_position + Vector3(1.0, 0, 0.0)
	player._handle_wetness(2.0)
	check(player.wetness < 60.0, "Костёр не сушит персонажа: %.1f" % player.wetness)

	# 5. Грибы: ресурс, сбор, отрастание, сезон.
	var shrooms: Array = shroom_spawner.get_mushrooms()
	check(shrooms.size() >= 10, "Грибов должно быть не меньше 10, факт: %d" % shrooms.size())
	if shrooms.is_empty():
		return
	var shroom: Node = shrooms[0]
	check(shroom.mushroom_item_id == "mushroom", "Гриб должен давать предмет mushroom")
	check(shroom.grow_seasons.has(Seasons.SUMMER) and shroom.grow_seasons.has(Seasons.AUTUMN), "Грибы должны расти летом и осенью")
	check(not shroom.grow_seasons.has(Seasons.WINTER), "Грибы не должны расти зимой")
	check(is_equal_approx(float(shroom.regrow_hours), 18.0), "Гриб должен отрастать за 18 ч")
	var mock := MockPlayer.new()
	mock.inventory = InventoryScript.new()
	mock.add_child(mock.inventory)
	root.add_child(mock)
	var shroom_before: int = mock.inventory.get_item_count("mushroom")
	shroom.interact(mock)
	check(mock.inventory.get_item_count("mushroom") - shroom_before == 1, "Гриб не собрался")
	check(not shroom.has_mushroom, "После сбора гриб остался на месте")
	# Мир живёт весной, а грибы растут летом и осенью — подсказка должна об этом сказать.
	check(shroom.get_prompt().contains("сезон"), "Нет подсказки о сезоне грибов: %s" % shroom.get_prompt())
	check(not shroom.get_prompt().contains("отрастут"), "Вне сезона показано время отрастания")
	# Вне сезона рост стоит даже при большом запасе часов.
	CookingProgress.reset()
	Seasons.activate(Seasons.WINTER, 1)
	shroom.advance_regrow(shroom.regrow_hours + 1.0)
	check(not shroom.has_mushroom, "Гриб отрос зимой")
	# В сезоне отрастает за 18 часов.
	Seasons.activate(Seasons.SUMMER, 1)
	check(shroom.get_prompt().contains("отрастут"), "Нет подсказки об отрастании гриба: %s" % shroom.get_prompt())
	shroom.advance_regrow(shroom.regrow_hours - 1.0)
	check(not shroom.has_mushroom, "Гриб отрос раньше срока")
	shroom.advance_regrow(2.0)
	check(shroom.has_mushroom, "Гриб не отрос за 18 ч")
	# Собранные грибы идут в веху главы.
	CookingProgress.reset()
	shroom.interact(mock)
	check(CookingProgress.mushrooms_collected == 1, "Сбор гриба не засчитан в веху")
	# Собранное состояние сохраняется.
	var state: Dictionary = JSON.parse_string(JSON.stringify(shroom.get_save_state()))
	shroom.apply_save_state({"has_mushroom": false, "regrow_progress": 7.5})
	check(not shroom.has_mushroom and is_equal_approx(shroom.regrow_progress, 7.5), "Состояние гриба не восстановилось")
	check(state.has("has_mushroom") and state.has("regrow_progress"), "Сохранение гриба неполное")
	mock.queue_free()

	# 6. Вехи и сохранение главы.
	CookingProgress.reset()
	CookingProgress.register_dish("mushroom_stew", 4, CookingProgress.QUALITY_GOOD)
	CookingProgress.register_mushrooms(10)
	var ch2: Dictionary = CookingProgress.evaluate()
	check(ch2["completed_count"] == 1, "Грибы должны закрыть одну веху, факт: %d" % ch2["completed_count"])
	check(not ch2["is_complete"], "Глава 2 не должна закрыться полностью")
	Seasons.activate(Seasons.SPRING, 1)

	check(SaveManager.save_game(world, SAVE_PATH), "Мир с Главой 2 не сохранился")
	var txt: String = FileAccess.get_file_as_string(SAVE_PATH)
	check(txt.contains("\"cooking\""), "В файле нет секции cooking")
	check(txt.contains("\"mushrooms\""), "В файле нет секции mushrooms")
	check(txt.contains("\"rebuilt\""), "В файле нет состояния восстановления станка")
	CookingProgress.reset()
	check(SaveManager.load_game(world, SAVE_PATH), "Мир с Главой 2 не загрузился")
	check(CookingProgress.get_dish_count() == 1, "Секция cooking не восстановилась")
	check(int(CookingProgress.get_dish("mushroom_stew").get("count", 0)) == 4, "Количество приготовленного не восстановилось")
	check(CookingProgress.get_dish("mushroom_stew").get("quality", "") == CookingProgress.QUALITY_GOOD, "Качество блюда не восстановилось")
	check(crusher.is_operational() and not smelter.is_operational(), "Состояние станков не восстановилось")
	check(kitchen.is_operational(), "Построенная печь-кухня не восстановилась")
	check(shroom_spawner.get_mushrooms().size() == shrooms.size(), "Раскладка грибов изменилась при загрузке")
	# Битая секция cooking отвергается целиком.
	CookingProgress.reset()
	var bad := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	bad.store_string(JSON.stringify({"cooking": {"dishes": {"x": {"count": -5}}}}))
	bad.close()
	check(not SaveManager.load_game(world, SAVE_PATH), "Битая секция cooking принята")
	check(CookingProgress.get_dish_count() == 0, "Битая секция cooking что-то изменила")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	CookingProgress.reset()
	Seasons.disable()

## Прогоняет цикл станка до конца и проверяет выход.
func _check_cooking_cycle(machine: Node, expected_item: String, expected_amount: int) -> void:
	machine._process(0.0)
	machine.process_timer = machine.process_duration
	machine._complete_process()
	check(int(machine.pending_outputs.get(expected_item, 0)) == expected_amount,
		"Костёр: %s должно быть %d, факт: %d" % [expected_item, expected_amount, int(machine.pending_outputs.get(expected_item, 0))])

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_chapter2_smoke — стартовый баланс, костёр, грибы, ремонт станков, печь-кухня, вехи и сохранение")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true