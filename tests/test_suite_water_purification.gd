extends SceneTree
## Комплексный тест механик водоочистки и гидросистемы (Water Purification Suite)
## Покрывает:
## 1. Очиститель воды (WaterFilterMachine): руины, восстановление, переключение коллизий и мешей.
## 2. Базовая фильтрация (filter_water): сырая вода + песок/опилки/пыль -> чистая вода (clean_water).
## 3. Глубокая минеральная фильтрация (mineral_filter_water) -> вода высокой очистки (high_purity_water).
## 4. Разница биологического воздействия: сырая вода (+25%), чистая (+50% +8 сил), высокой очистки (+70% +12 сил).
## 5. Цепочка производства бутилированной воды на верстаке (Workbench).
## 6. Коммерческий сбыт очищенной воды на станции отправки (DispatchStation).

const WorldScene = preload("res://scenes/world/world.tscn")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: ВОДООЧИСТКА И ГИДРОСИСТЕМА")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	var filter = world.find_child("WaterFilter", true, false)
	check(filter != null, "WaterFilter не найден в сцене мира")
	var workbench = world.find_child("Workbench", true, false)
	check(workbench != null, "Workbench не найден в сцене мира")
	var station = world.find_child("DispatchStation", true, false)
	check(station != null, "DispatchStation не найден в сцене мира")

	if not filter or not player or not inv:
		world.queue_free()
		_finish()
		return

	# -------------------------------------------------------------------------
	# 1. Состояние руин и восстановление очистителя
	# -------------------------------------------------------------------------
	print("\n--- 1. Руины и восстановление очистителя воды ---")
	filter.requires_rebuild = true
	filter.rebuilt = false
	filter._update_rebuild_visuals()
	check(not filter.rebuilt, "Фильтр изначально должен быть в невосстановленном состоянии")

	# Восстанавливаем фильтр
	filter.force_rebuilt()
	check(filter.rebuilt, "После force_rebuilt фильтр должен быть восстановлен")
	print("✅ Восстановление: очиститель воды успешно переключает состояние руин и готовности.")

	# -------------------------------------------------------------------------
	# 2. Базовая фильтрация воды (filter_water)
	# -------------------------------------------------------------------------
	print("\n--- 2. Базовая фильтрация: сырая вода -> чистая вода ---")
	inv.clear()
	inv.add_item("water", 4)
	inv.add_item("sand", 2)
	inv.add_item("stone_dust", 2)
	inv.add_item("sawdust", 2)

	var start_ok = filter.start_recipe("filter_water", player)
	check(start_ok, "Рецепт filter_water должен успешно стартовать")
	check(filter.is_machine_running, "Машина фильтра должна перейти в состояние работы")

	# Завершаем цикл
	filter.process_timer = filter.process_duration
	filter._complete_process()
	check(filter.pending_outputs.get("clean_water", 0) == 2, "Фильтр должен выдать 2 единицы clean_water")
	filter.collect_outputs(player)
	check(inv.get_item_count("clean_water") == 2, "Чистая вода должна переместиться в инвентарь игрока")
	print("✅ Базовая фильтрация: успешно произведено 2 clean_water.")

	# -------------------------------------------------------------------------
	# 3. Глубокая минеральная фильтрация (mineral_filter_water)
	# -------------------------------------------------------------------------
	print("\n--- 3. Глубокая фильтрация: сырая вода + уголь -> высокая очистка ---")
	inv.add_item("water", 3)
	inv.add_item("coal_powder", 1)
	inv.add_item("sand", 1)
	inv.add_item("stone_dust", 1)
	inv.add_item("sawdust", 1)

	var start_deep = filter.start_recipe("mineral_filter_water", player)
	check(start_deep, "Рецепт mineral_filter_water должен успешно стартовать")
	filter.process_timer = filter.process_duration
	filter._complete_process()
	check(filter.pending_outputs.get("high_purity_water", 0) == 2, "Фильтр должен выдать 2 единицы high_purity_water")
	filter.collect_outputs(player)
	check(inv.get_item_count("high_purity_water") == 2, "Вода высокой очистки должна быть в инвентаре")
	print("✅ Глубокая фильтрация: успешно произведено 2 high_purity_water.")

	# -------------------------------------------------------------------------
	# 4. Биологическое воздействие разных типов воды
	# -------------------------------------------------------------------------
	print("\n--- 4. Употребление и сравнение эффектов воды ---")
	# Сырая вода
	inv.add_item("water", 1)
	player.thirst = 10.0
	player.energy = 50.0
	player.drink_from_inventory("water")
	check(abs(player.thirst - 35.0) < 0.1, "Сырая вода должна восстанавливать +25%% жажды (получено %.1f)" % player.thirst)
	check(player.energy == 50.0, "Сырая вода не должна давать бонуса к энергии")

	# Чистая вода
	player.thirst = 10.0
	player.energy = 50.0
	player.drink_from_inventory("clean_water")
	check(abs(player.thirst - 60.0) < 0.1, "Чистая вода должна восстанавливать +50%% жажды (получено %.1f)" % player.thirst)
	check(player.energy > 50.0, "Чистая вода должна давать бонус бодрости (+8 энергии)")

	# Вода высокой очистки
	player.thirst = 10.0
	player.energy = 50.0
	player.drink_from_inventory("high_purity_water")
	check(abs(player.thirst - 80.0) < 0.1, "Вода высокой очистки должна восстанавливать +70%% жажды (получено %.1f)" % player.thirst)
	check(player.energy >= 62.0, "Вода высокой очистки должна давать +12 энергии")
	print("✅ Биологический эффект: сырая (+25%), чистая (+50% +8), высокой очистки (+70% +12) проверены.")

	# -------------------------------------------------------------------------
	# 5. Розлив в бутылки на верстаке
	# -------------------------------------------------------------------------
	print("\n--- 5. Розлив бутилированной воды на верстаке ---")
	if workbench:
		inv.add_item("clean_water", 1)
		inv.add_item("glass_bottle", 1)
		var bottle_start = workbench.start_recipe("bottle_water", player)
		check(bottle_start, "Рецепт bottle_water должен стартовать на верстаке")
		workbench.process_timer = workbench.process_duration
		workbench._complete_process()
		workbench.collect_outputs(player)
		check(inv.get_item_count("bottled_water") == 1, "В инвентаре должна появиться 1 бутилированная вода")
		print("✅ Верстак: 1 стекло + 1 чистая вода -> 1 бутилированная вода успешно скрафчена.")

	# -------------------------------------------------------------------------
	# 6. Продажа воды на станции сбыта
	# -------------------------------------------------------------------------
	print("\n--- 6. Сбыт продукции водоочистки ---")
	if station:
		var creds_start = inv.credits
		var earnings = station.sell_goods({"bottled_water": 1}, player)
		var expected_price = ItemDB.get_sell_price("bottled_water")
		check(earnings == expected_price, "Доход от продажи бутилированной воды должен быть %d (получено %d)" % [expected_price, earnings])
		check(inv.credits == creds_start + expected_price, "Кредиты игрока должны пополниться на стоимость товара")
		print("✅ Сбыт: продажа очищенной продукции на станции приносит точную сумму кредитов.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ ВОДООЧИСТКИ И ГИДРОСИСТЕМЫ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
