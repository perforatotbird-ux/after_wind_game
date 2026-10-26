extends SceneTree
## Комплексный тест механик кулинарии и кухни (Cooking & Kitchen Suite)
## Покрывает:
## 1. Костёр (Campfire): слоты топлива (дерево 15 с, уголь 90 с, брикет 120 с).
## 2. Автономное горение костра и принадлежность к группе heat_sources.
## 3. Добавление и возврат топлива из инвентаря в слоты костра.
## 4. Печь-кухня (KitchenStove): требование восстановления (requires_rebuild), энергопотребление.
## 5. Градация качества блюд: Lv.1 -> хорошее, Lv.2 -> отличное.
## 6. Трекер прогресса (CookingProgress): учет уникальных блюд, грибов, вех Главы 2.

const WorldScene = preload("res://scenes/world/world.tscn")
const CampfireScript = preload("res://scripts/crafting/campfire.gd")
const KitchenStoveScript = preload("res://scripts/crafting/kitchen_stove.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")
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
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: КУЛИНАРИЯ И КУХНЯ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Узел Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	# -------------------------------------------------------------------------
	# 1. Механика Костра (Campfire)
	# -------------------------------------------------------------------------
	print("\n--- 1. Костёр: параметры, тепло и слоты топлива ---")
	var campfire = world.find_child("Campfire", true, false)
	if not campfire:
		# Если в сцене нет предразмещенного узла костра, создадим экземпляр для теста
		campfire = CampfireScript.new()
		world.add_child(campfire)

	check(campfire.is_in_group("heat_sources"), "Костёр должен состоять в группе heat_sources")
	check(campfire.fuel_burn_times.get("wood", 0.0) == 15.0, "Древесина в костре должна гореть 15 с")
	check(campfire.fuel_burn_times.get("coal", 0.0) == 90.0, "Уголь в костре должен гореть 90 с")
	check(campfire.fuel_burn_times.get("fuel_briquette", 0.0) == 120.0, "Брикет в костре должен гореть 120 с")

	# Загрузка топлива из инвентаря
	inv.clear()
	inv.add_item("wood", 5)
	var added = campfire.add_fuel_from_inventory(inv, "wood", 3)
	check(added == 3, "Должно добавиться 3 единицы древесины (добавлено: %d)" % added)
	check(inv.get_item_count("wood") == 2, "В инвентаре должно остаться 2 древесины")

	# Проверяем возврат топлива обратно в инвентарь (1 полено уже горит в топке, возвращаются остальные 2)
	var taken = campfire.take_fuel_from_slot(0, inv)
	check(taken > 0, "Должно быть возвращено топливо из слота")
	check(inv.get_item_count("wood") >= 4, "Не сгоревшая древесина должна вернуться в инвентарь")
	print("✅ Костёр: слоты топлива, время горения и перемещение ресурсов из/в инвентарь проверены.")

	# -------------------------------------------------------------------------
	# 2. Автономное горение костра
	# -------------------------------------------------------------------------
	print("\n--- 2. Автономное горение костра ---")
	inv.add_item("wood", 2)
	campfire.add_fuel_from_inventory(inv, "wood", 2)
	# Зажигаем топливо
	campfire._process(0.1)
	check(campfire.is_lit(), "Костёр с топливом должен загореться")
	var burn_left_before = campfire.fuel_burn_left
	campfire._process(5.0)
	check(campfire.fuel_burn_left < burn_left_before, "Оставшееся время горения должно уменьшаться (до: %.1f, после: %.1f)" % [burn_left_before, campfire.fuel_burn_left])
	print("✅ Автономное горение: таймер топлива костра корректно тикает.")

	# -------------------------------------------------------------------------
	# 3. Печь-кухня (KitchenStove)
	# -------------------------------------------------------------------------
	print("\n--- 3. Печь-кухня: восстановление и качество блюд ---")
	var stove = world.find_child("KitchenStove", true, false)
	if not stove:
		stove = KitchenStoveScript.new()
		world.add_child(stove)

	check(stove.requires_rebuild, "Печь-кухня изначально должна требовать восстановления")
	check(stove.has_fuel_slots, "Печь-кухня должна иметь слоты топлива")
	check(stove.fuel_slot_count == 2, "Печь-кухня должна иметь 2 слота топлива")

	# Восстанавливаем станок для проверки градаций качества
	stove.force_rebuilt()
	check(stove.rebuilt, "Печь-кухня должна быть в восстановленном состоянии")

	# Уровень 1 дает качество "хорошее"
	var q1 = stove.get_dish_quality()
	check(q1 == CookingProgress.QUALITY_GOOD, "На уровне 1 качество блюда должно быть 'хорошее' (получено: %s)" % q1)

	# Уровень 2 дает качество "отличное"
	if stove.level_state:
		stove.level_state.set_level(2)
	var q2 = stove.get_dish_quality()
	check(q2 == CookingProgress.QUALITY_GREAT, "На уровне 2 качество блюда должно быть 'отличное' (получено: %s)" % q2)
	print("✅ Печь-кухня: требования стройки, слоты и градации качества по уровням подтверждены.")

	# -------------------------------------------------------------------------
	# 4. Трекер прогресса кулинарии (CookingProgress)
	# -------------------------------------------------------------------------
	print("\n--- 4. Учёт блюд, грибов и вех Главы 2 (CookingProgress) ---")
	CookingProgress.reset()
	check(CookingProgress.get_dish_count() == 0, "После сброса должно быть 0 блюд")
	check(CookingProgress.mushrooms_collected == 0, "После сброса должно быть 0 собранных грибов")

	# Регистрация блюд
	CookingProgress.register_dish("fried_meat", 2, CookingProgress.QUALITY_PLAIN)
	check(CookingProgress.get_dish_count() == 1, "Должно быть зарегистрировано 1 уникальное блюдо")
	var dish_entry = CookingProgress.get_dish("fried_meat")
	check(dish_entry.get("count", 0) == 2, "Количество жареного мяса должно быть 2")
	check(dish_entry.get("quality", "") == CookingProgress.QUALITY_PLAIN, "Качество должно быть обычное")

	# Повышение качества того же блюда
	CookingProgress.register_dish("fried_meat", 1, CookingProgress.QUALITY_GREAT)
	check(CookingProgress.get_dish_count() == 1, "Повторная готовка не должна дублировать блюдо")
	dish_entry = CookingProgress.get_dish("fried_meat")
	check(dish_entry.get("count", 0) == 3, "Количество должно вырасти до 3")
	check(dish_entry.get("quality", "") == CookingProgress.QUALITY_GREAT, "Качество должно повыситься до 'отличное'")

	# Попытка понизить качество не должна ухудшать запись
	CookingProgress.register_dish("fried_meat", 1, CookingProgress.QUALITY_GOOD)
	dish_entry = CookingProgress.get_dish("fried_meat")
	check(dish_entry.get("quality", "") == CookingProgress.QUALITY_GREAT, "Качество не должно понижаться при худшей готовке")

	# Набор 5 разных блюд
	CookingProgress.register_dish("mushroom_soup", 1)
	CookingProgress.register_dish("baked_potato", 1)
	CookingProgress.register_dish("bread", 1)
	CookingProgress.register_dish("boiled_egg", 1)
	check(CookingProgress.get_dish_count() == 5, "Должно быть 5 разных блюд для вехи Главы 2")

	# Сбор грибов и восстановление станков
	CookingProgress.register_mushrooms(12)
	check(CookingProgress.mushrooms_collected == 12, "Должно быть учтено 12 собранных грибов")

	CookingProgress.register_rebuild("crusher")
	CookingProgress.register_rebuild("furnace")
	check(CookingProgress.is_machine_rebuilt("crusher"), "Дробилка должна быть отмечена восстановленной")
	check(CookingProgress.is_machine_rebuilt("furnace"), "Плавильня должна быть отмечена восстановленной")

	# Оценка вех Главы 2
	var eval_res = CookingProgress.evaluate(world)
	check(eval_res.has("tasks"), "Результат оценки должен содержать список tasks")
	print("✅ Трекер прогресса: учет блюд, защита от понижения качества и вехи Главы 2 полностью работают.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ КУЛИНАРИИ И КУХНИ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
