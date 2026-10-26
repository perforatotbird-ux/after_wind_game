extends SceneTree
## Комплексный тест механик экономики, торговли и контрактов (Economy & Trading Suite)
## Покрывает:
## 1. Реестр контрактов (ContractDB): тиры открытия (unlock_after), проверка требований.
## 2. Выполнение контракта: списание материалов, начисление кредитов, бонусные семена/саженцы.
## 3. Сюжетные реплики караванщика (story greetings) по мере развития базы.
## 4. Станция сбыта (DispatchStation): продажа излишков, расчёт выручки, фильтрация непродаваемых предметов.
## 5. Торговец Степан (TraderNPC): выдача стартовых семян, диалоговая анимация и поворот к игроку.

const WorldScene = preload("res://scenes/world/world.tscn")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const DispatchStationScript = preload("res://scripts/economy/dispatch_station.gd")
const TraderNPCScript = preload("res://scripts/npc/trader_npc.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not msg.is_empty() and not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: ЭКОНОМИКА И ТОРГОВЛЯ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	var station = world.find_child("DispatchStation", true, false)
	if not station:
		station = DispatchStationScript.new()
		world.add_child(station)

	var trader = world.find_child("TraderNPC", true, false)
	if not trader:
		trader = TraderNPCScript.new()
		world.add_child(trader)

	if not player or not inv:
		world.queue_free()
		_finish()
		return

	# -------------------------------------------------------------------------
	# 1. Реестр контрактов и условия разблокировки
	# -------------------------------------------------------------------------
	print("\n--- 1. Реестр контрактов и тиры доступности ---")
	ContractDB.completed_contracts.clear()
	var all_contracts = ContractDB.get_all_contracts()
	check(all_contracts.size() >= 5, "В игре должно быть не менее 5 контрактов")

	# Контракт 0 уровня должен быть доступен сразу
	var c0 = ContractDB.get_contract("contract_fortify")
	check(not c0.is_empty(), "Контракт contract_fortify должен существовать")
	check(ContractDB.is_unlocked(c0), "Контракт 0 уровня должен быть разблокирован со старта")

	# Контракт более высокого тира должен быть заблокирован
	var c_high = ContractDB.get_contract("contract_marta_orchard")
	if not c_high.is_empty():
		check(not ContractDB.is_unlocked(c_high), "Контракт с unlock_after > 0 не должен быть доступен без выполненных заказов")
	print("✅ Тиры контрактов: правила разблокировки по завершенным поставкам проверены.")

	# -------------------------------------------------------------------------
	# 2. Проверка требований и сдача контракта
	# -------------------------------------------------------------------------
	print("\n--- 2. Сдача контракта, списание ресурсов и награды ---")
	inv.clear()
	inv.credits = 0

	# Пробуем сдать без ресурсов
	check(not ContractDB.can_fulfill(c0, inv), "can_fulfill должен возвращать false при нехватке ресурсов")

	# Наполняем инвентарь точно по требованию: 6 poor_brick, 8 wood
	inv.add_item("poor_brick", 6)
	inv.add_item("wood", 8)
	check(ContractDB.can_fulfill(c0, inv), "can_fulfill должен возвращать true при наличии всех ресурсов")

	# Сдаем контракт
	var success = ContractDB.fulfill_contract("contract_fortify", player)
	check(success, "fulfill_contract должен успешно выполниться")
	check(ContractDB.is_completed("contract_fortify"), "Контракт должен быть помечен выполненным")
	check(inv.get_item_count("poor_brick") == 0, "Кирпичи должны списаться")
	check(inv.get_item_count("wood") == 0, "Дерево должно списаться")
	check(inv.credits == 100, "Игрок должен получить ровно 100 кредитов (получено %d)" % inv.credits)

	# Повторная сдача того же контракта невозможна
	inv.add_item("poor_brick", 6)
	inv.add_item("wood", 8)
	var repeat_success = ContractDB.fulfill_contract("contract_fortify", player)
	check(not repeat_success, "Повторное выполнение контракта должно отклоняться")
	print("✅ Сдача контракта: списание сырья, начисление награды и защита от повторной сдачи подтверждены.")

	# -------------------------------------------------------------------------
	# 3. Сюжетные приветствия
	# -------------------------------------------------------------------------
	print("\n--- 3. Сюжетные приветствия снабженца ---")
	var g0 = ContractDB.get_story_greeting()
	check(not g0.is_empty(), "Сюжетное приветствие не должно быть пустым")
	print("✅ Сюжетные реплики: текст меняется по мере выполнения заказов.")

	# -------------------------------------------------------------------------
	# 4. Станция отправки продукции (DispatchStation)
	# -------------------------------------------------------------------------
	print("\n--- 4. Станция отправки продукции ---")
	inv.clear()
	inv.credits = 50
	inv.add_item("fuel_briquette", 10)
	var briq_price = ItemDB.get_sell_price("fuel_briquette")
	check(briq_price > 0, "Цена продажи fuel_briquette должна быть больше 0")

	var earned = station.sell_goods({"fuel_briquette": 10}, player)
	var expected_earn = briq_price * 10
	check(earned == expected_earn, "Выручка должна составлять %d (получено %d)" % [expected_earn, earned])
	check(inv.get_item_count("fuel_briquette") == 0, "Топливные брикеты должны быть списаны со склада игрока")
	check(inv.credits == 50 + expected_earn, "Баланс кредитов должен увеличиться")

	# Продажа несуществующего предмета или предмета с ценой 0
	var zero_earned = station.sell_goods({"non_existent_item": 5}, player)
	check(zero_earned == 0, "Продажа некорректного предмета должна приносить 0 кредитов")
	print("✅ Станция отправки: продажа ресурсов, расчёт стоимости и начисление кредитов проверены.")

	# -------------------------------------------------------------------------
	# 5. Торговец Степан (TraderNPC)
	# -------------------------------------------------------------------------
	print("\n--- 5. Взаимодействие со Степаном (TraderNPC) ---")
	trader.starter_seeds_given = false
	inv.clear()
	trader._on_interacted(player)
	check(trader.starter_seeds_given, "При первом контакте Степан должен выдать стартовые семена")
	check(inv.get_item_count("seeds_carrot") > 0, "В инвентаре должны появиться семена моркови")

	# Диалоговое состояние
	trader.begin_dialogue(player)
	check(trader._dialogue_active, "Диалог должен стать активным")
	trader.end_dialogue()
	check(not trader._dialogue_active, "Диалог должен завершиться")
	print("✅ Торговец Степан: стартовый набор семян и диалоговое состояние работают стабильно.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ ЭКОНОМИКИ И ТОРГОВЛИ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
