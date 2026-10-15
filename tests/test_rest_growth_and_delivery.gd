extends SceneTree
## Регрессии: перемотка времени (отдых/сон) двигает рост и производство,
## выбранные семена садятся на старых грядках, компоненты копятся внутри
## строящихся/ремонтируемых объектов, диалог сна с ползунком.

const FarmField = preload("res://scripts/farming/farm_field.gd")
const Placer = preload("res://scripts/farming/farm_field_placer.gd")
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")
const SleepDialog = preload("res://scripts/ui/sleep_dialog.gd")

var world: Node
var player: Node
var inv: Node
var frames := 0
var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
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
	if frames < 4:
		return false
	player = world.find_child("Player", true, false)
	player.set_process(false)
	player.set_physics_process(false)
	inv = player.inventory
	inv.max_slots = 200
	if "max_weight" in inv:
		inv.max_weight = 10000.0
	_run_tests()
	return _finish()

func _run_tests() -> void:
	print("========================================")
	print("🧪 ПЕРЕМОТКА ВРЕМЕНИ, ДОСТАВКА КОМПОНЕНТОВ И СОН")
	print("========================================")

	var day_cycle = world.get_node_or_null("DayNightCycle")
	check(day_cycle != null, "В мире нет DayNightCycle")
	var crusher = world.find_child("StoneCrusher", true, false)
	check(crusher != null, "В мире нет дробилки")
	var house = world.find_child("RepairableHouse", true, false)
	check(house != null, "В мире нет дома")

	# ---------- 1. Перемотка времени растит урожай ----------
	var o: Vector2i = _find_free_origin(2, 2)
	var field = FarmField.spawn(world, Vector3(o.x, 0.0, o.y), 2, 2)
	for id in field.get_cost():
		inv_add(inv, id, int(field.get_cost()[id]))
	check(field.deliver_materials(player), "Материалы делянки не приняты")
	check(field.state == FarmField.State.BUILDING, "Стройка не началась")
	# Строим делянку прыжком времени: цикл постройки идёт по игровым часам.
	day_cycle.advance_hours(24.5)
	check(field.state == FarmField.State.READY, "За игровой день делянка не построилась")
	inv_add(inv, "seeds_carrot", 3)
	player.selected_seed = "seeds_carrot"
	field.work_cell(player, Vector2i(0, 0))
	check(field.get_cell(Vector2i(0, 0))["crop"] == "carrot", "Морковь не посажена")
	var growth_before: float = field.get_cell(Vector2i(0, 0))["growth"]
	# Перемотка суток должна двигать рост культур, а не только часы.
	for i in 6:
		field.get_cell(Vector2i(0, 0))["moisture"] = 80.0
		day_cycle.advance_hours(2.0)
	var growth_after: float = field.get_cell(Vector2i(0, 0))["growth"]
	check(growth_after > growth_before + 6.0, "Рост культур не догнал перемотку времени (+%.1f ч)" % (growth_after - growth_before))
	check(field.is_ripe(Vector2i(0, 0)), "Морковь не созрела за перемотанные сутки")
	print("✅ Перемотка времени растит урожай на делянках (+%.1f ч роста)." % (growth_after - growth_before))

	# ---------- 2. Перемотка времени работает в производстве ----------
	crusher.force_rebuilt()
	crusher.wear.set_condition(crusher.wear.max_condition)
	player.energy = 100.0
	inv_add(inv, "stone", 4)
	check(crusher.start_batch("crush_stone", 1, player), "Партия дробилки не запустилась")
	check(crusher.is_machine_running, "Дробилка не работает после запуска")
	# Игровой час = 60 реальных секунд: цикл 20 с успевает завершиться.
	day_cycle.advance_hours(1.0)
	check(not crusher.is_machine_running, "Цикл не завершился при перемотке часа")
	check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1, "Продукция не накопилась в станке при перемотке: %s" % crusher.pending_outputs)
	crusher.collect_outputs(player)
	print("✅ Перемотка времени ведёт производство: цикл завершён, продукция в станке.")

	# ---------- 3. Старые грядки сажают выбранные семена ----------
	var plot = FarmlandPlot.new()
	world.add_child(plot)
	# _ready() сбрасывает soil_state на initial_state — вскапываем после добавления.
	plot.soil_state = FarmlandPlot.SoilState.TILLED
	inv_add(inv, "seeds_carrot", 2)
	inv_add(inv, "seeds_potato", 2)
	var carrot_before: int = inv.get_item_count("seeds_carrot")
	var potato_before: int = inv.get_item_count("seeds_potato")
	player.selected_seed = "seeds_potato"
	plot._on_interacted(player)
	check(plot.crop_type == "potato", "Выбраны семена картофеля, а посажено: %s" % plot.crop_type)
	check(inv.get_item_count("seeds_carrot") == carrot_before, "Семена моркови не тронуты при выборе картофеля")
	check(inv.get_item_count("seeds_potato") == potato_before - 1, "Семена картофеля не списаны")
	# Перемотка времени растит и старые грядки.
	var plot_growth_before: float = plot.growth_progress
	day_cycle.advance_hours(1.0)
	check(plot.growth_progress > plot_growth_before, "Рост на старой грядке не догнал перемотку времени")
	print("✅ Грядка сажает выбранные игроком семена (картофель, не морковь) и растёт при перемотке.")
	plot.queue_free()

	# ---------- 4. Компоненты копятся внутри здания ----------
	house.current_stage = 0
	house.delivered.clear()
	house.delivered_credits = 0
	for id in ["wood", "stone", "sawdust", "poor_brick", "mortar"]:
		inv.remove_item(id, inv.get_item_count(id))
	inv_add(inv, "wood", 3)
	inv_add(inv, "stone", 6)
	inv.credits = 5
	check(not house.upgrade(player), "Стадия применилась без полного комплекта")
	check(house.current_stage == 0, "Стадия выросла без комплекта материалов")
	check(int(house.delivered.get("wood", 0)) == 3 and int(house.delivered.get("stone", 0)) == 6, "Материалы не накопились в доме: %s" % house.delivered)
	check(house.delivered_credits == 5, "Кредиты не накопились в доме")
	check(inv.get_item_count("wood") == 0, "Древесина не перенесена в дом")
	inv_add(inv, "wood", 5)
	inv.credits = 20
	check(house.upgrade(player), "Стадия не применилась после сбора комплекта")
	check(house.current_stage == 1, "Дом не перешёл на стадию 1")
	check(house.delivered.is_empty() and house.delivered_credits == 0, "Накопленное не очистилось после применения стадии")
	print("✅ Компоненты достройки копятся внутри дома и применяются комплектом.")

	# ---------- 5. Компоненты копятся внутри станка ----------
	crusher.level_state.set_level(1)
	crusher.job_stash["upgrade"] = {}
	crusher.job_credits["upgrade"] = 0
	for id in ["stone", "iron_plate", "gear", "bolt", "steel_plate", "precision_gear"]:
		inv.remove_item(id, inv.get_item_count(id))
	inv_add(inv, "stone", 2)
	inv_add(inv, "iron_plate", 2)
	check(not crusher.upgrade_machine(player), "Улучшение применилось без полного комплекта")
	check(crusher.get_level() == 1, "Уровень вырос без комплекта деталей")
	check(int(crusher.job_stash["upgrade"].get("stone", 0)) == 2, "Детали не накопились в станке: %s" % crusher.job_stash["upgrade"])
	inv_add(inv, "stone", 4)
	inv_add(inv, "iron_plate", 2)
	inv_add(inv, "gear", 2)
	inv_add(inv, "bolt", 4)
	check(crusher.upgrade_machine(player), "Улучшение не применилось после сбора деталей")
	check(crusher.get_level() == 2, "Станок не улучшен до Lv.2")
	check(crusher.job_stash["upgrade"].is_empty(), "Накопленные детали не очистились")
	print("✅ Детали улучшения копятся внутри станка и применяются комплектом.")

	# ---------- 6. Диалог сна: ползунок длительности ----------
	var dialog = SleepDialog.new()
	dialog.setup(house, player)
	world.add_child(dialog)
	check(absf(dialog.get_hours() - 6.0) < 0.01, "Сон по умолчанию не 6 ч (%.1f)" % dialog.get_hours())
	dialog._set_hours(3.0)
	check(absf(dialog.get_hours() - 3.0) < 0.01, "Ползунок не выставил 3 ч (%.1f)" % dialog.get_hours())
	dialog._set_hours(12.0)
	check(absf(dialog.get_hours() - 12.0) < 0.01, "Ползунок не выставил 12 ч")
	dialog.queue_free()
	print("✅ Диалог сна: ползунок длительности 1–12 ч (по умолчанию 6).")

	# ---------- 7. Сон не роняет сытость/жажду в ноль ----------
	player.hunger = 100.0
	player.thirst = 100.0
	player.energy = 30.0
	player.start_rest(8.0, true)
	check(player.energy >= 99.9, "Сон не восстановил энергию (%.0f)" % player.energy)
	check(player.thirst > 60.0, "Жажда после 8 ч сна провалилась (%.0f)" % player.thirst)
	check(player.hunger > 70.0, "Сытость после 8 ч сна провалилась (%.0f)" % player.hunger)
	check(player.visible, "Персонаж не вернулся в мир после сна")
	check(not player.is_resting, "Флаг отдыха не снят")
	print("✅ Сон 8 ч: энергия 100%%, жажда %.0f%%, сытость %.0f%% — без провала в ноль." % [player.thirst, player.hunger])

func inv_add(inv: Node, id: String, n: int) -> void:
	if id == "credits":
		inv.add_credits(n)
		return
	inv.add_item(id, n)

func _finish() -> bool:
	if errors.is_empty():
		print("========================================")
		print("🎉 ВСЕ ПРОВЕРКИ ПЕРЕМОТКИ, ДОСТАВКИ И СНА ПРОЙДЕНЫ!")
		print("========================================")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("========================================")
		print("❌ ТЕСТ ПРОВАЛЕН")
		print("========================================")
		quit(1)
	return true
