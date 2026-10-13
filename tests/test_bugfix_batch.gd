extends SceneTree

## Регрессионный тест пакета исправлений и доработок (fix/gameplay-bugs-and-systems):
## A. Потеря предметов при полном рюкзаке — добыча, урожай, вода, семена NPC.
## B. «Съесть» расходует выбранный предмет, а не первый по приоритету.
## C. Высыхание: медленное на улице, быстрее в доме и у печи, не зависит от FPS.
## D. Истощение сил (энергия 0) уроняет здоровье, с одноразовым предупреждением.
## E. Станки потребляют энергию сети; без питания цикл приостанавливается.
## F. Износ за циклы, блокировка запуска неисправного станка, ремонт.
## G. Топливные слоты печи: время горения, смена вида топлива, извлечение.
## H. Отдых/сон: время продвигается, статы меняются, итог «Вы отдыхали N ч».
## I. Save → resume: машина продолжает цикл (set_process + power_ok).
## J. Новая игра: сброс выполненных контрактов.
## K. Обморок: утро к дому (stage ≥ 2) vs Game Over + штраф ресурсов.

const WorldScene = preload("res://scenes/world/world.tscn")
const ResourceNodeScript = preload("res://scripts/resources/resource_node.gd")
const FarmlandPlotScript = preload("res://scripts/farming/farmland_plot.gd")
const WaterReservoirScript = preload("res://scripts/buildings/water_reservoir.gd")
const TraderNPCScript = preload("res://scripts/npc/trader_npc.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")
const InventoryPanelScript = preload("res://scripts/ui/inventory_panel.gd")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const save_manager_class = preload("res://scripts/core/save_manager.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")

var _test_executed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	var world_node = WorldScene.instantiate()
	root.add_child(world_node)

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

func _count_piles(item_id: String) -> int:
	var total: int = 0
	for n in root.get_tree().get_nodes_in_group("dropped_items"):
		if is_instance_valid(n) and n.item_id == item_id:
			total += int(n.amount)
	return total

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("========================================")
	print("🧪 ТЕСТ ПАКЕТА ИСПРАВЛЕНИЙ (баги + доработки)")
	print("========================================")
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player отсутствует в сцене")
	var inv = player.inventory
	if not inv: _fail("Инвентарь игрока недоступен")
	var notifications: Array[String] = []
	player.notification_received.connect(func(t: String): notifications.append(t))

	# ---------- A. Потеря предметов при полном рюкзаке ----------
	print("\n--- A. Полный рюкзак: ничего не пропадает ---")
	_fill_backpack(inv)
	check(not inv.can_add_item("stone", 1), "Рюкзак заполнен (stone не помещается)")

	# A1. Добыча из ресурсного узла: кучка на земле, узел истощён, рюкзак не изменился
	var rn = ResourceNodeScript.new()
	rn.resource_id = "stone"
	rn.resource_display_name = "Камень"
	rn.required_tool = "pickaxe"
	rn.max_hits = 1
	rn.current_hits = 1
	rn.yield_per_hit = 1
	rn.bonus_depleted_yield = 1
	rn.energy_cost = 0.0
	root.add_child(rn)
	rn.global_position = Vector3(60.0, 0.5, 60.0)
	inv.equip_tool("pickaxe")
	var stone_before: int = inv.get_item_count("stone")
	rn.interact(player)
	check(rn.is_depleted, "Ресурсный узел истощён после удара")
	check(inv.get_item_count("stone") == stone_before, "Добыча не попала в полный рюкзак")
	check(_count_piles("stone") >= 2, "Добыча лежит кучкой на земле (×2)")
	rn.queue_free()

	# A2. Урожай грядки при полном рюкзаке — кучка, грядка сброшена
	var plot = FarmlandPlotScript.new()
	root.add_child(plot)
	plot.global_position = Vector3(64.0, 0.5, 60.0)
	plot.crop_type = "carrot"
	plot.is_ripe = true
	var carrot_before: int = inv.get_item_count("carrot")
	plot.harvest_crop(player)
	check(inv.get_item_count("carrot") == carrot_before, "Урожай не попал в полный рюкзак")
	check(_count_piles("carrot") >= 3, "Урожай лежит кучкой на земле")
	check(plot.crop_type == "" and not plot.is_ripe, "Грядка после сбора сброшена (урожай не задвоен)")
	plot.queue_free()

	# A3. Резервуар: вода не списывается, если ей некуда деться
	var reservoir = WaterReservoirScript.new()
	root.add_child(reservoir)
	reservoir.current_water = 6
	player.thirst = player.max_thirst
	var water_before: int = inv.get_item_count("clean_water")
	reservoir.interact(player)
	check(reservoir.current_water == 6, "Резервуар не опустел при полном рюкзаке")
	check(inv.get_item_count("clean_water") == water_before, "Вода не исчезла и не появилась из ниоткуда")
	inv.remove_item("stone", inv.get_max_stack("stone")) # освобождаем слот
	reservoir.interact(player)
	check(reservoir.current_water == 5, "После освобождения слота вода набрана (6 -> 5)")
	check(inv.get_item_count("clean_water") == water_before + 1, "Чистая вода попала в рюкзак")
	reservoir.queue_free()

	# A4. Семена Степана при полном рюкзаке — кучка у NPC, флаг выдачи стоит
	_fill_backpack(inv)
	var trader = TraderNPCScript.new()
	root.add_child(trader)
	trader.global_position = Vector3(68.0, 0.5, 60.0)
	trader.interact(player)
	check(trader.starter_seeds_given, "Степан помнит, что семена выдал")
	check(_count_piles("seeds_carrot") >= 3 and _count_piles("seeds_wheat") >= 3,
		"Семена лежат кучкой на земле и не пропали")
	trader.queue_free()
	inv.clear()
	inv.max_slots = 12

	# ---------- B. Съедается выбранный предмет ----------
	print("\n--- B. «Съесть» ест то, что выбрано ---")
	player.hunger = 50.0
	inv.add_item("potato", 3)
	inv.add_item("blue_berry", 2)
	var panel = InventoryPanelScript.new()
	panel.setup(player)
	root.add_child(panel)
	panel._selected = "blue_berry"
	panel._on_use_pressed()
	check(inv.get_item_count("blue_berry") == 1, "Синяя ягода уменьшилась на 1 (съедена выбранная)")
	check(inv.get_item_count("potato") == 3, "Картофель не тронут")
	panel._selected = "blue_berry"
	panel._on_use_pressed()
	check(inv.get_item_count("blue_berry") == 0 and inv.get_item_count("potato") == 3,
		"Повторное «Съесть» снова бёрёт выбранную ягодy, не картофель")
	panel.close()

	# ---------- C. Высыхание ----------
	print("\n--- C. Постепенное высыхание ---")
	var weather = world.find_child("WeatherManager", true, false)
	player.global_position = Vector3(50.0, 0.5, 50.0) # подальше от дома и печи
	if weather:
		weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)
	player.wetness = 100.0
	player._handle_wetness(10.0)
	check(player.wetness > 90.0 and player.wetness < 99.5,
		"На улице за 10 с сохнет медленно (100 -> %.1f)" % player.wetness)
	check(absf(player.wetness - (100.0 - player.dry_rate_outdoor * 10.0)) < 0.5,
		"Скорость сушки на улице равна dry_rate_outdoor и умножается на delta (FPS-независимость)")
	var smelter = world.find_child("Smelter", true, false)
	# Глава 2: печь стартует разрушенной — топливо и обжиг проверяем на живой печи.
	smelter.force_rebuilt()
	player.global_position = smelter.global_position + Vector3(1.5, 0.0, 0.0)
	player.wetness = 100.0
	player._handle_wetness(5.0)
	# dry_rate_near_fire ×1/3 (6.0 -> 2.0): за 5 с 90.0, но всё равно быстрее, чем на улице (≈98.8).
	check(player.wetness < 92.0,
		"У печи сушка заметно быстрее, чем на улице (100 -> %.1f)" % player.wetness)
	check(absf(player.wetness - (100.0 - player.dry_rate_near_fire * 5.0)) < 0.5,
		"Скорость сушки у печи равна dry_rate_near_fire и умножается на delta")
	player.global_position = Vector3(50.0, 0.5, 50.0)
	if weather:
		weather.set_weather(WeatherManagerScript.WeatherType.RAIN)
		player.wetness = 0.0
		player._handle_wetness(5.0)
		check(player.wetness > 0.0, "Под дождём персонаж намокает")
		weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)

	# C1. Новые скорости высыхания — все ×1/3
	print("\n--- C1. Скорости высыхания ×1/3 ---")
	check(absf(player.dry_rate_outdoor - 0.12) < 0.001, "dry_rate_outdoor = 0.12 (было 0.35)")
	check(absf(player.dry_rate_sheltered - 0.4) < 0.001, "dry_rate_sheltered = 0.4 (было 1.2)")
	check(absf(player.dry_rate_near_fire - 2.0) < 0.001, "dry_rate_near_fire = 2.0 (было 6.0)")
	# Намокание под дождем: 3.0 * intensity (RAIN=1.0 → 3.0), не изменено.
	if weather:
		weather.set_weather(WeatherManagerScript.WeatherType.HEAVY_RAIN)
	player.wetness = 0.0
	player._handle_wetness(1.0)
	check(player.wetness > 0.0 and player.wetness <= 6.5,
		"Намокание под сильным дождём не тронуто (3.0 * 2.0 * 1.0 = 6.0, факт: %.1f)" % player.wetness)
	# Погоду возвращаем к ясной: дальше идут секции сети/машин, которым нужен
	# слабый ветер (иначе в шторм ветряк покрывает потребление и батарея не разряжается).
	if weather:
		weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)

	# ---------- I. Save → resume: машины продолжают работать ----------
	print("\n--- I. Save → resume: машины возобновляют цикл ---")
	ContractDB.reset_completed()
	# Узлы ищутся здесь же: объявления crusher/grid ниже по функции видны
	# только после своих строк, поэтому у секции свои локальные имена.
	var crusher_i = world.find_child("StoneCrusher", true, false)
	var grid_i = world.get_node_or_null("PowerGrid")
	if crusher_i == null or grid_i == null:
		_fail("Не найдены StoneCrusher/PowerGrid для теста save/resume")
		return
	# Глава 2: дробилка стартует разрушенной — здесь проверяется возобновление цикла.
	crusher_i.force_rebuilt()
	inv.add_item("stone", 20)
	check(crusher_i.start_batch("crush_stone", 4, player), "Запущена партия для теста save/resume")
	grid_i._update_grid(0.1)
	crusher_i._process(0.5)
	check(crusher_i.process_timer > 0.0, "Таймер цикла растёт во время работы")
	# Сохранение и загрузка в том же мире (валидный ручной слот, после теста удаляется).
	SaveSlots.save_to_slot(world, "slot_1")
	check(SaveSlots.has_slot("slot_1"), "Слот сохранения создан")
	SaveSlots.load_from_slot(world, "slot_1")
	var crusher2 = world.find_child("StoneCrusher", true, false)
	check(crusher2 == crusher_i, "Машина сохранилась в том же узле")
	check(crusher2.is_processing(), "Машина продолжает процессить после загрузки (set_process(true) восстановлен)")
	check(crusher2.power_ok, "power_ok восстановлен из PowerGrid.has_power после загрузки")
	check(crusher2.is_machine_running, "Машина считается работающей после загрузки")
	check(absf(crusher2.process_timer - crusher_i.process_timer) < 0.001,
		"Таймер цикла сохраняется и не сбрасывается при загрузке")
	crusher2.cancel_batch()
	SaveSlots.delete_slot("slot_1")

	# ---------- J. Новая игра: сброс прогресса контрактов ----------
	print("\n--- J. Сброс контрактов при новой игре ---")
	ContractDB.completed_contracts["contract_test"] = true
	check(ContractDB.get_completed_count() == 1, "Контракт помечен выполненным")
	ContractDB.reset_completed()
	check(ContractDB.get_completed_count() == 0, "reset_completed() очищает выполненные контракты")
	check(ContractDB.get_all_contracts().filter(func(c): return ContractDB.is_unlocked(c)).size() >= 1,
		"Базовые заказы доступны после сброса")

	# ---------- K. Обморок и поражение ----------
	print("\n--- K. Обморок: утро к дому vs Game Over ---")
	var house = world.find_child("RepairableHouse", true, false)
	# K1. Без дома (stage 0) — game over overlay
	house.current_stage = 0
	inv.add_item("wood", 10)
	var wood_before: int = inv.get_item_count("wood")
	player.health = 0.0
	# В headless режиме overlay мгновенно применяется, player._on_collapse вызывается.
	player._on_collapse("test")
	check(player.health >= 20.0, "Здоровье восстановлено после обморока (>= 20)")
	check(inv.get_item_count("wood") < wood_before, "Штраф: часть ресурсов рассыпалась кучкой у точки падения")
	# В headless overlay создаётся, но не блокирует — проверяем, что не вылетело.
	check(_count_piles("wood") >= 1, "Рассыпанные ресурсы лежат на земле")

	# K2. С домом stage ≥ 2 — утренний отскок к дому
	house.current_stage = 2
	player.health = 0.0
	inv.clear(); inv.add_item("wood", 10)
	var drop_parent = world
	player._on_collapse("exhaustion")
	check(player.global_position.distance_to(house.global_position) < 3.0,
		"При stage дома ≥ 2 игрок рядом с домом после обморока")
	check(player.health > 0.0, "Здоровье восстановлено после утреннего отскока")
	# Сброс контрактов для чистоты остальных тестов
	ContractDB.reset_completed()

	print("\n--- D. Истощение влияет на здоровье ---")
	player.energy = 0.0
	player.hunger = 100.0
	player.thirst = 100.0
	player.health = 100.0
	notifications.clear()
	player._handle_health(1.0)
	check(absf(player.health - 99.5) < 0.01, "Энергия 0: здоровье -0.5/с (100 -> %.1f)" % player.health)
	check(notifications.any(func(t): return "Истощение" in t), "Одноразовое предупреждение об истощении")
	notifications.clear()
	player._handle_health(1.0)
	check(notifications.is_empty(), "Предупреждение не повторяется каждый кадр")
	player.energy = 100.0
	player.health = 100.0

	# ---------- E. Питание станков от сети ----------
	print("\n--- E. Станки потребляют энергию сети ---")
	var grid = world.get_node_or_null("PowerGrid")
	var turbine = world.find_child("WindTurbine", true, false)
	var crusher = world.find_child("StoneCrusher", true, false)
	if not grid or not turbine or not crusher: _fail("Не найдены PowerGrid/WindTurbine/StoneCrusher")
	# Глава 2: дробилка стартует разрушенной — потребление сети проверяем на живой.
	crusher.force_rebuilt()
	player.energy = 100.0
	inv.add_item("stone", 30)
	check(crusher.start_batch("crush_stone", 5, player), "Партия дробилки запущена")
	grid._update_grid(0.0)
	check(grid.current_consumption >= 2.9, "Сеть видит потребление работающей дробилки (>= 3 кВт): %.1f" % grid.current_consumption)
	var stored_before: float = grid.current_stored
	grid._update_grid(1.0)
	check(grid.current_stored < stored_before, "Заряд батареи уменьшается, пока станок работает")
	# Глубокий разряд: станок встаёт, таймер цикла замирает
	grid.current_stored = 0.01
	turbine.is_operational = false
	grid._update_grid(0.1)
	check(not grid.has_power, "Сеть обесточена при пустой батарее")
	check(not crusher.power_ok, "Дробилка получила сигнал «нет питания»")
	var frozen_timer: float = crusher.process_timer
	crusher._process(0.5)
	check(absf(crusher.process_timer - frozen_timer) < 0.001, "Без питания таймер цикла стоит (сырьё не теряется)")
	# Питание вернулось — партия продолжается
	turbine.is_operational = true
	grid.current_stored = 50.0
	grid._update_grid(0.1)
	check(grid.has_power and crusher.power_ok, "Питание восстановлено (гистерезис 15 %)")
	crusher._process(0.5)
	check(crusher.process_timer > frozen_timer, "После восстановления питания цикл продолжился")
	crusher.cancel_batch()

	# ---------- F. Износ и ремонт ----------
	print("\n--- F. Износ и ремонт станка ---")
	crusher.wear.set_condition(0.0)
	inv.add_item("stone", 10)
	check(not crusher.start_batch("crush_stone", 1, player), "Неисправный станок (0%%) не запускается")
	var bolt_before: int = inv.get_item_count("bolt")
	check(not crusher.repair_machine(player), "Ремонт без ресурсов отклонён")
	check(inv.get_item_count("bolt") == bolt_before, "Ресурсы при неудачном ремонте не списались")
	inv.add_item("bolt", 2)
	inv.add_item("wooden_handle", 1)
	check(crusher.repair_machine(player), "Ремонт с ресурсами выполнен")
	check(absf(crusher.wear.condition - 50.0) < 0.01, "Ремонт восстановил +50%% состояния")
	check(inv.get_item_count("bolt") == 0 and inv.get_item_count("wooden_handle") == 0, "Ресурсы ремонта списаны")
	inv.add_item("bolt", 2)
	inv.add_item("wooden_handle", 1)
	crusher.repair_machine(player)
	check(crusher.wear.get_ratio() >= 1.0, "Второй ремонт довёл состояние до 100 %")
	crusher.wear.set_condition(40.0)
	check(crusher.wear.is_worn() and crusher.wear.get_speed_mult() > 1.0, "Изношенный станок работает медленнее")
	player.energy = 100.0
	crusher.start_batch("crush_stone", 1, player)
	check(absf(crusher.process_duration - 20.0 * 1.25) < 0.01, "Цикл изношенного станка длится ×1.25")
	crusher.cancel_batch()
	crusher.wear.set_condition(100.0)

	# ---------- G. Топливные слоты печи ----------
	print("\n--- G. Топливо печи: горение и смена вида ---")
	if not smelter.has_fuel_slots: _fail("У печи нет топливных слотов")
	inv.add_item("coal", 1)
	inv.add_item("wood", 1)
	inv.add_item("sand", 6)
	smelter.add_fuel_from_inventory(inv, "coal")
	smelter.add_fuel_from_inventory(inv, "wood")
	player.energy = 100.0
	check(smelter.start_recipe("smelt_glass", player), "Печь запущена с топливом в слотах")
	check(smelter.active_fuel_slot == 0 and absf(smelter.fuel_burn_left - smelter.get_fuel_burn_time("coal")) < 0.01,
		"Первой загорается единица угля (%.0f с)" % smelter.fuel_burn_left)
	smelter.fuel_burn_left = 0.01
	smelter._process(0.1)
	smelter._process(0.1) # второй тик: уголь догорел — разжигается следующее топливо
	check(smelter.fuel_burn_left > smelter.get_fuel_burn_time("wood") - 1.0
		and smelter.fuel_burn_left <= smelter.get_fuel_burn_time("wood")
		and smelter.fuel_burn_left < smelter.get_fuel_burn_time("coal"),
		"После угля загораются дрова — у вида топлива своё время горения (%.0f с)" % smelter.fuel_burn_left)
	var back: int = smelter.take_fuel_from_slot(1, inv)
	check(back == 0, "Горящее топливо из активного слота уже списано")
	smelter.cancel_batch()
	smelter.fuel_slots[0]["count"] = 0
	smelter.fuel_slots[0]["item_id"] = ""
	smelter.fuel_burn_left = 0.0
	smelter.active_fuel_slot = -1

	# ---------- H. Отдых и сон ----------
	print("\n--- H. Переход отдыха с ускорением времени ---")
	var dc = world.find_child("DayNightCycle", true, false)
	dc.set_time(1, 23.0)
	player.energy = 20.0
	player.health = 50.0
	player.wetness = 80.0
	player.hunger = 100.0
	player.thirst = 100.0
	notifications.clear()
	player.start_rest(7.0, true)
	check(absf(dc.current_hour - 6.0) < 0.01 and dc.current_day == 2, "Время продвинулось на 7 ч (23:00 -> 06:00, День 2)")
	check(player.energy >= 99.9, "Сон восстановил энергию (20 -> %.0f)" % player.energy)
	check(player.health >= 99.9, "Сон восстановил здоровье (50 -> %.0f)" % player.health)
	check(player.wetness <= 0.01, "За сон мокрая одежда высохла (80 -> %.0f)" % player.wetness)
	check(player.thirst >= 35.0 and player.thirst < 40.0, "Жажда после сна не ниже 35 %% (сброс)")
	check(notifications.any(func(t): return "отдыхали 7 ч" in t), "Итог: «Вы отдыхали 7 ч»")
	check(not player.is_resting, "Флаг отдыха снят")
	# Короткий отдых слабее сна
	dc.set_time(2, 12.0)
	player.energy = 50.0
	player.start_rest(2.0, false)
	check(player.energy < 70.0 and player.energy > 60.0, "Короткий отдых (2 ч) восстановил ~12 энергии (%.0f)" % player.energy)
	check(absf(dc.current_hour - 14.0) < 0.01, "Короткий отдых продвинул время на 2 ч")

	print("========================================")
	if _errors.is_empty():
		print("🎉 ВСЕ ПРОВЕРКИ ПАКЕТА ИСПРАВЛЕНИЙ ПРОЙДЕНЫ!")
		print("========================================")
		quit(0)
	else:
		for e in _errors:
			print("ПРОВАЛЕН: ", e)
		print("========================================")
		quit(1)

## Заполняет рюкзак до отказа: один полный стек камня занимает единственный слот.
func _fill_backpack(inv: Node) -> void:
	inv.clear()
	inv.max_slots = 1
	inv.add_item("stone", inv.get_max_stack("stone"))
