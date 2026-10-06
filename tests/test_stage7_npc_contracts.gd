extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 7...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 7: NPC, КОНТРАКТЫ И СЮЖЕТ")
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
	
	var trader_npc = world.find_child("TraderNPC", true, false)
	if not trader_npc:
		_fail("TraderNPC (Степан) отсутствует в сцене")
		return
	
	var contract_board = world.find_child("ContractBoard", true, false)
	if not contract_board:
		_fail("ContractBoard (Доска заказов) отсутствует в сцене")
		return
	
	print("✅ Все ключевые узлы Этапа 7 (TraderNPC, ContractBoard, Player, HUD) найдены.")
	
	var inv = player.inventory
	if not inv:
		_fail("Инвентарь игрока недоступен")
		return
	
	# 1. Проверка реестра контрактов
	var all_contracts = ContractDB.get_all_contracts()
	if all_contracts.size() < 4:
		_fail("Ожидалось не менее 4 контрактов в ContractDB, получено: %d" % all_contracts.size())
		return
	print("✅ Реестр контрактов успешно загружен (всего: %d заказов от общин)." % all_contracts.size())
	
	# 2. Проверка диалога со Степаном и открытия окна контрактов
	trader_npc._on_interacted(player)
	if not hud.contract_window.visible:
		_fail("Окно контрактов не открылось при разговоре со Степаном")
		return
	if not hud.contract_dialogue_label.text.contains("Приветствую"):
		_fail("Текст приветствия Степана не отображен в окне диалога")
		return
	print("✅ Диалог с NPC Степаном функционирует, окно заказов успешно открывается.")
	
	# 3. Проверка взаимодействия с доской заказов
	hud.close_contract_window()
	if hud.contract_window.visible:
		_fail("Окно контрактов должно быть закрыто")
		return
	contract_board._on_interacted(player)
	if not hud.contract_window.visible:
		_fail("Окно контрактов не открылось при взаимодействии с доской объявлений")
		return
	print("✅ Информационный щит / Доска заказов также открывает интерфейс контрактов.")
	
	# 4. Проверка сдачи Контракта 1: «Первичное укрепление» (4 poor_brick, 6 wood -> +95 кредитов)
	var c1 = ContractDB.get_contract("contract_fortify")
	if c1.is_empty():
		_fail("Контракт contract_fortify не найден")
		return
	if ContractDB.can_fulfill(c1, inv):
		_fail("Контракт 1 не должен быть доступен для сдачи при пустом инвентаре")
		return
	
	inv.add_item("poor_brick", 4)
	inv.add_item("wood", 6)
	if not ContractDB.can_fulfill(c1, inv):
		_fail("Контракт 1 должен быть готов к сдаче после добавления материалов")
		return
	
	var creds_before = inv.credits
	var ok = ContractDB.fulfill_contract("contract_fortify", player)
	if not ok:
		_fail("Ошибка при выполнении fulfill_contract для contract_fortify")
		return
	if inv.get_item_count("poor_brick") != 0 or inv.get_item_count("wood") != 0:
		_fail("Ресурсы контракта 1 не списались из инвентаря")
		return
	if inv.credits != creds_before + 95:
		_fail("Награда за контракт 1 не начислена корректно (+95 кр., баланс: %d)" % inv.credits)
		return
	if not ContractDB.is_completed("contract_fortify"):
		_fail("Контракт 1 не помечен как выполненный")
		return
	print("✅ Контракт 1 (Укрепление времянки): списано 4 кирпича и 6 бревен, получено +95 кредитов.")
	
	# 5. Проверка сдачи Контракта 3: «Питьевая вода для разведки» (3 clean_water, 1 bottled_water -> +140 кр.)
	inv.add_item("clean_water", 3)
	inv.add_item("bottled_water", 1)
	creds_before = inv.credits
	ok = ContractDB.fulfill_contract("contract_pure_water", player)
	if not ok:
		_fail("Ошибка выполнения контракта чистой воды")
		return
	if inv.get_item_count("clean_water") != 0 or inv.get_item_count("bottled_water") != 0:
		_fail("Водные ресурсы не списались при сдаче контракта 3")
		return
	if inv.credits != creds_before + 140:
		_fail("Награда за контракт чистой воды не начислена (+140 кр.)")
		return
	print("✅ Контракт 3 (Вода для разведки): сдана партия фильтрованной воды, получено +140 кредитов.")
	
	# 6. Проверка сдачи Контракта 4: «Капитальные стройматериалы» (4 fired_brick, 2 glass, 1 iron_ingot -> +260 кр.)
	inv.add_item("fired_brick", 4)
	inv.add_item("glass", 2)
	inv.add_item("iron_ingot", 1)
	creds_before = inv.credits
	ok = ContractDB.fulfill_contract("contract_heavy_masonry", player)
	if not ok:
		_fail("Ошибка выполнения контракта стройматериалов")
		return
	if inv.credits != creds_before + 260:
		_fail("Награда за контракт 4 не начислена (+260 кр.)")
		return
	print("✅ Контракт 4 (Обожженный кирпич, стекло и слиток): получено +260 кредитов!")
	
	# 7. Проверка обновления карточек в HUD
	hud._refresh_contract_window()
	var cards_count = hud.contracts_list.get_child_count()
	if cards_count != all_contracts.size():
		_fail("Число карточек заказов в HUD (%d) не совпадает с числом контрактов (%d)" % [cards_count, all_contracts.size()])
		return
	print("✅ Интерфейс карточек заказов в HUD полностью отображает статусы и награды.")
	
	hud.close_contract_window()
	print("========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 7 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	quit(0)
