extends SceneTree
## Комплексный тест механик прогрессии базы и победы (Victory & Progression Suite)
## Покрывает:
## 1. Менеджер победы (VictoryManager): структура оценки готовности базы (8 ключевых задач).
## 2. Проверка состояния жилого дома (RepairableHouse: стадия 2 из 3).
## 3. Проверка состояния склада (RepairableStorage: стадия 2 из 3).
## 4. Проверка запуска станков (Crusher, Workbench, Smelter: completed_runs > 0).
## 5. Проверка подготовки пашни (FarmlandPlot: soil_state >= 1).
## 6. Проверка контрактов снабжения (ContractDB: минимум 2 сданных заказа).
## 7. Проверка экипировки мастера (инструмент Lv.2 или расширенный рюкзак).
## 8. Итоговый триггер победы: 100% прогресс и флаг is_victory.

const WorldScene = preload("res://scenes/world/world.tscn")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: ПРОГРЕССИЯ И ПОБЕДА")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	# -------------------------------------------------------------------------
	# 1. Начальная оценка прогресса восстановления базы
	# -------------------------------------------------------------------------
	print("\n--- 1. Начальное состояние чеклиста победы ---")
	ContractDB.completed_contracts.clear()
	var initial_eval = VictoryManager.evaluate_base_restored(world)
	check(initial_eval.has("is_victory"), "Оценка должна содержать флаг is_victory")
	check(initial_eval.has("progress_pct"), "Оценка должна содержать progress_pct")
	check(initial_eval.has("tasks"), "Оценка должна содержать список tasks")
	check(initial_eval["tasks"].size() == 8, "Чеклист восстановления должен состоять из 8 задач")
	check(not initial_eval["is_victory"], "В начале игры победа не должна быть достигнута")
	print("✅ Начальный чеклист: 8 задач, прогресс < 100%, победа не достигнута.")

	# -------------------------------------------------------------------------
	# 2. Моделирование выполнения условий
	# -------------------------------------------------------------------------
	print("\n--- 2. Пошаговое выполнение условий победы ---")
	# 1. Дом (стадия 2)
	var house = world.find_child("RepairableHouse", true, false)
	if house:
		house.current_stage = 2

	# 2. Склад (стадия 2)
	var storage = world.find_child("RepairableStorage", true, false)
	if storage:
		storage.current_stage = 2

	# 3, 4, 5. Станки: дробилка, верстак, плавильня
	var crusher = world.find_child("StoneCrusher", true, false)
	if not crusher: crusher = world.find_child("Crusher", true, false)
	if crusher: crusher.completed_runs = 1

	var bench = world.find_child("Workbench", true, false)
	if bench: bench.completed_runs = 1

	var smelter = world.find_child("Smelter", true, false)
	if smelter: smelter.completed_runs = 1

	# 6. Пашня: подготовленная грядка
	var plots = world.get_tree().get_nodes_in_group("farmland_plots")
	if not plots.is_empty():
		plots[0].soil_state = 1
	else:
		var dummy_plot = Node.new()
		dummy_plot.add_to_group("farmland_plots")
		dummy_plot.set("soil_state", 1)
		world.add_child(dummy_plot)

	# 7. Контракты снабжения: отмечаем 2 выполненных
	ContractDB.completed_contracts["contract_1"] = true
	ContractDB.completed_contracts["contract_2"] = true

	# 8. Инструмент мастера или рюкзак
	if inv:
		inv.equipped_tool = "iron_pickaxe"

	# -------------------------------------------------------------------------
	# 3. Финальная оценка и триггер победы
	# -------------------------------------------------------------------------
	print("\n--- 3. Финальная проверка условий победы ---")
	var final_eval = VictoryManager.evaluate_base_restored(world)
	check(final_eval["completed_count"] == final_eval["total_count"], "Все 8 условий должны быть выполнены (выполнено %d/%d)" % [final_eval["completed_count"], final_eval["total_count"]])
	check(final_eval["progress_pct"] == 100, "Прогресс восстановления должен быть 100%% (получено %d)" % final_eval["progress_pct"])
	check(final_eval["is_victory"], "Флаг победы is_victory должен стать true!")
	print("✅ Победа: все 8 критериев восстановления базы выполнены, статус победы активирован.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ ПРОГРЕССИИ И ПОБЕДЫ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
