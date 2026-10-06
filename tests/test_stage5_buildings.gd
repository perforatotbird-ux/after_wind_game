extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 5...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 5: ВОССТАНОВЛЕНИЕ ЗДАНИЙ")
	print("========================================")
	
	var world_node = root.get_node_or_null("World")
	if not world_node:
		_fail("Узел World не найден в корне дерева")
		return
	
	var player = world_node.get_node_or_null("Player")
	var hud = world_node.get_node_or_null("HUD")
	var props = world_node.get_node_or_null("Props")
	
	if not player: _fail("Player отсутствует в сцене")
	if not hud: _fail("HUD отсутствует в сцене")
	if not props: _fail("Props отсутствует в сцене")
	print("✅ Базовая сцена мира, игрок и HUD загружены.")
	
	var house = props.get_node_or_null("RepairableHouse")
	var storage = props.get_node_or_null("RepairableStorage")
	
	if not house: _fail("RepairableHouse отсутствует в Props")
	if not storage: _fail("RepairableStorage отсутствует в Props")
	print("✅ Разрушенный дом и склад найдены в сцене мира.")
	
	# Проверка начального состояния (Стадия 0)
	if house.current_stage != 0: _fail("Начальная стадия дома != 0")
	if storage.current_stage != 0: _fail("Начальная стадия склада != 0")
	if house.can_sleep(): _fail("Сон доступен в разрушенном доме ур. 0")
	print("✅ Начальное состояние зданий: Стадия 0 (Разрушено).")
	
	var inv = player.inventory
	if not inv:
		inv = player.get_node_or_null("Inventory")
	if not inv: _fail("Инвентарь игрока недоступен")
	print("✅ Инвентарь игрока успешно инициализирован.")
	
	# 1. Проверка нехватки ресурсов
	var check0 = house.can_upgrade(player)
	if check0.get("can_upgrade", false): _fail("Улучшение дома возможно без ресурсов")
	if check0.get("missing_credits", 0) <= 0: _fail("Должно не хватать кредитов")
	print("✅ Блокировка улучшения при нехватке материалов и кредитов проверена.")
	
	# 2. Улучшение дома до стадии 1 (wood: 6, stone: 4, cr: 20)
	inv.add_item("wood", 6)
	inv.add_item("stone", 4)
	inv.add_credits(20)
	
	var check1 = house.can_upgrade(player)
	if not check1.get("can_upgrade", false): _fail("Недостаточно ресурсов при наличии полного комплекта")
	
	var ok_up1 = house.upgrade(player)
	if not ok_up1: _fail("house.upgrade вернул false для стадии 1")
	if house.current_stage != 1: _fail("Стадия дома не переключилась на 1")
	if inv.get_item_count("wood") != 0: _fail("Древесина не списана")
	if inv.get_item_count("stone") != 0: _fail("Камень не списан")
	if inv.credits != 0: _fail("Кредиты не списаны")
	print("✅ Стадия 1 Дома: каркас возведен, списание ресурсов корректно.")
	
	# 3. Улучшение дома до стадии 2 (wood: 10, poor_brick: 6, cr: 50)
	inv.add_item("wood", 10)
	inv.add_item("poor_brick", 6)
	inv.add_credits(50)
	
	var ok_up2 = house.upgrade(player)
	if not ok_up2: _fail("house.upgrade вернул false для стадии 2")
	if house.current_stage != 2: _fail("Стадия дома не переключилась на 2")
	if not house.can_sleep(): _fail("Сон недоступен в доме ур. 2")
	print("✅ Стадия 2 Дома: дом восстановлен, кровать и сон разблокированы!")
	
	# 4. Проверка механики сна
	player.energy = 25.0
	house.sleep(player)
	if player.energy < 99.9: _fail("Сон не восстановил энергию игрока")
	print("✅ Механика сна: энергия восстановлена на 100%.")
	
	# 5. Улучшение Склада до стадии 1 (wood: 4, stone: 4, cr: 15)
	var prev_max_weight = inv.max_weight
	inv.add_item("wood", 4)
	inv.add_item("stone", 4)
	inv.add_credits(15)
	
	var ok_st1 = storage.upgrade(player)
	if not ok_st1: _fail("storage.upgrade вернул false")
	if storage.current_stage != 1: _fail("Стадия склада не переключилась на 1")
	if inv.max_weight <= prev_max_weight: _fail("Грузоподъемность не увеличилась")
	print("✅ Стадия 1 Склада: грузоподъемность увеличена с %.1f до %.1f кг!" % [prev_max_weight, inv.max_weight])
	
	# 6. Проверка окна HUD (RepairWindow)
	hud.open_repair_window(house)
	if not hud.repair_window.visible: _fail("Окно RepairWindow не открылось")
	if not hud.repair_sleep_button.visible: _fail("Кнопка сна должна отображаться для дома ур. 2")
	hud.close_repair_window()
	if hud.repair_window.visible: _fail("Окно RepairWindow не закрылось")
	print("✅ Окно RepairWindow и модальный интерфейс проверены.")
	
	print("========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 5 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	
	quit(0)
