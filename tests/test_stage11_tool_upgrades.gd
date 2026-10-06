extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const ResourceNode = preload("res://scripts/resources/resource_node.gd")
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 11...")
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
	print("=================================================================")
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 11: УЛУЧШЕНИЕ ИНСТРУМЕНТОВ LV.2 И ОСНАСТКА")
	print("=================================================================")
	
	ContractDB.reset_completed()
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var inv = player.get("inventory")
	if not inv:
		_fail("У игрока отсутствует компонент Inventory")
		return
	
	# -------------------------------------------------------------
	# 1. Проверка базы предметов ItemDB (компоненты и инструменты Lv.2)
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Реестр компонентов и инструментов Lv.2 в ItemDB ---")
	var components: Array[String] = ["wooden_handle", "bolt", "fabric", "leather_strap"]
	for c_id in components:
		var c_data: Dictionary = ItemDB.get_item(c_id)
		if c_data.is_empty():
			_fail("Компонент '%s' отсутствует в ItemDB" % c_id)
			return
		if c_data.get("category") != "component":
			_fail("Категория '%s' должна быть 'component'" % c_id)
			return
		if c_data.get("sell_price", 0) <= 0:
			_fail("Цена сбыта '%s' должна быть > 0" % c_id)
			return
		print("  • Компонент '%s': %s (вес: %.2f кг, цена: %d кр.)" % [
			c_id, c_data.name, c_data.weight, c_data.sell_price
		])
	
	var tools_lv2: Array[String] = ["iron_axe", "iron_pickaxe", "iron_shovel", "reinforced_bucket", "large_backpack"]
	for t_id in tools_lv2:
		var t_data: Dictionary = ItemDB.get_item(t_id)
		if t_data.is_empty():
			_fail("Инструмент/экипировка '%s' отсутствует в ItemDB" % t_id)
			return
		if t_data.get("level", 0) != 2:
			_fail("Уровень '%s' должен быть 2" % t_id)
			return
		print("  • Инструмент Lv.2 '%s': %s (тип: %s, уровень: %d, цена: %d кр.)" % [
			t_id, t_data.name, t_data.tool_type, t_data.level, t_data.sell_price
		])
	print("✅ Все компоненты и инструменты Lv.2 валидны в ItemDB.")

	# -------------------------------------------------------------
	# 2. Проверка производственных рецептов в RecipeDB
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Рецепты оснастки и кузницы в RecipeDB ---")
	var stage11_recipes: Array[String] = [
		"craft_wooden_handle", "craft_bolt", "craft_fabric", "craft_leather_strap",
		"upgrade_iron_axe", "upgrade_iron_pickaxe", "upgrade_iron_shovel",
		"upgrade_reinforced_bucket", "upgrade_large_backpack"
	]
	for r_id in stage11_recipes:
		var r_data: Dictionary = RecipeDB.get_recipe(r_id)
		if r_data.is_empty():
			_fail("Рецепт '%s' отсутствует в RecipeDB" % r_id)
			return
		if r_data.get("machine") != "workbench":
			_fail("Рецепт '%s' должен изготавливаться на верстаке ('workbench')" % r_id)
			return
		var inputs: Dictionary = r_data.get("inputs", {})
		for in_id in inputs.keys():
			if ItemDB.get_item(in_id).is_empty():
				_fail("Рецепт '%s': входной ресурс '%s' отсутствует в ItemDB" % [r_id, in_id])
				return
		var outputs: Dictionary = r_data.get("outputs", {})
		for out_id in outputs.keys():
			if ItemDB.get_item(out_id).is_empty():
				_fail("Рецепт '%s': выходной ресурс '%s' отсутствует в ItemDB" % [r_id, out_id])
				return
		print("  • Рецепт '%s': %s (затраты: %s -> выход: %s)" % [
			r_id, r_data.name, str(inputs), str(outputs)
		])
	print("✅ Все 9 рецептов верстака проверены и полностью корректны.")

	# -------------------------------------------------------------
	# 3. Инвентарь: улучшение инструментов и расширение рюкзака
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Механика улучшений в Inventory и Большой рюкзак ---")
	inv.clear()
	inv.max_slots = 12
	inv.max_weight = 50.0
	inv.tools = ["axe", "pickaxe", "shovel", "bucket", "backpack"] as Array[String]
	inv.equipped_tool = "axe"

	if inv.max_slots != 12 or inv.max_weight != 50.0:
		_fail("Начальные слоты/вес некорректны")
		return
	if inv.get_tool_level("axe") != 1:
		_fail("Начальный уровень топора должен быть 1")
		return

	# Добавляем большой рюкзак
	inv.add_item("large_backpack", 1)
	if inv.max_slots != 20:
		_fail("Большой рюкзак должен расширять вместимость до 20 слотов, сейчас: %d" % inv.max_slots)
		return
	if inv.max_weight != 75.0:
		_fail("Большой рюкзак должен расширять грузоподъемность до 75.0 кг, сейчас: %.1f" % inv.max_weight)
		return
	if not inv.tools.has("large_backpack"):
		_fail("large_backpack должен быть добавлен в список инструментов")
		return
	print("  • Большой рюкзак успешно применен: слоты = %d, грузоподъемность = %.1f кг." % [inv.max_slots, inv.max_weight])

	# Улучшаем топор до iron_axe
	inv.upgrade_tool("iron_axe")
	if not inv.is_tool_equipped("axe"):
		_fail("is_tool_equipped('axe') должен возвращать true для iron_axe!")
		return
	if not inv.is_tool_equipped("iron_axe"):
		_fail("is_tool_equipped('iron_axe') должен возвращать true!")
		return
	if inv.get_tool_level("axe") != 2:
		_fail("Уровень топора должен стать 2 после улучшения, сейчас: %d" % inv.get_tool_level("axe"))
		return
	if inv.get_equipped_tool() != "iron_axe":
		_fail("Экипированным инструментом должен стать 'iron_axe', сейчас: %s" % inv.get_equipped_tool())
		return
	print("  • Топор улучшен до Lv.2: экипирован '%s', get_tool_level('axe') = %d." % [
		inv.get_equipped_tool(), inv.get_tool_level("axe")
	])

	# Улучшаем кирку, лопату, ведро
	inv.upgrade_tool("iron_pickaxe")
	inv.upgrade_tool("iron_shovel")
	inv.upgrade_tool("reinforced_bucket")
	if inv.get_tool_level("pickaxe") != 2:
		_fail("Уровень кирки должен быть 2")
		return
	if inv.get_tool_level("shovel") != 2:
		_fail("Уровень лопаты должен быть 2")
		return
	if inv.get_tool_level("bucket") != 2:
		_fail("Уровень ведра должен быть 2")
		return
	print("  • Кирка, лопата и ведро успешно обновлены до Lv.2.")
	print("✅ Механика апгрейдов и расширения слотов в Inventory работает безупречно.")

	# -------------------------------------------------------------
	# 4. Добыча ресурсов: сравнение эффективности Lv.1 vs Lv.2
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Эффективность добычи дерева и камня (Lv.1 vs Lv.2) ---")
	var tree_node = ResourceNode.new()
	tree_node.resource_id = "wood"
	tree_node.resource_display_name = "Берёза"
	tree_node.required_tool = "axe"
	tree_node.max_hits = 4
	tree_node.current_hits = 4
	tree_node.yield_per_hit = 2
	tree_node.bonus_depleted_yield = 1
	tree_node.energy_cost = 4.0
	world.add_child(tree_node)

	# Тест с базовым топором Lv.1
	inv.tools = ["axe", "pickaxe", "shovel", "bucket", "backpack"] as Array[String]
	inv.equipped_tool = "axe"
	player.energy = 100.0
	inv.items["wood"] = 0

	tree_node._on_interacted(player)
	var energy_spent_lv1 = 100.0 - player.energy
	var wood_lv1 = inv.get_item_count("wood")
	var hits_remaining_lv1 = tree_node.current_hits
	print("  • Удар топором Lv.1: потрачено энергии = %.2f (ожидалось 4.0), добыто дерева = %d (ожидалось 2), остаток прочности = %d (ожидалось 3)" % [
		energy_spent_lv1, wood_lv1, hits_remaining_lv1
	])
	if abs(energy_spent_lv1 - 4.0) > 0.01:
		_fail("Трата энергии топором Lv.1 должна быть 4.0, факт: %.2f" % energy_spent_lv1)
		return
	if wood_lv1 != 2:
		_fail("Добыча дерева топором Lv.1 должна быть 2, факт: %d" % wood_lv1)
		return
	if hits_remaining_lv1 != 3:
		_fail("Остаток прочности после удара Lv.1 должен быть 3, факт: %d" % hits_remaining_lv1)
		return

	# Сброс дерева и тест с железным топором Lv.2
	tree_node.current_hits = 4
	inv.upgrade_tool("iron_axe")
	player.energy = 100.0
	inv.items["wood"] = 0

	tree_node._on_interacted(player)
	var energy_spent_lv2 = 100.0 - player.energy
	var wood_lv2 = inv.get_item_count("wood")
	var hits_remaining_lv2 = tree_node.current_hits
	print("  • Удар топором Lv.2: потрачено энергии = %.2f (ожидалось 2.6), добыто дерева = %d (ожидалось 3), остаток прочности = %d (ожидалось 2)" % [
		energy_spent_lv2, wood_lv2, hits_remaining_lv2
	])
	if abs(energy_spent_lv2 - 2.6) > 0.05:
		_fail("Трата энергии топором Lv.2 должна быть 2.6 (-35%%), факт: %.2f" % energy_spent_lv2)
		return
	if wood_lv2 != 3:
		_fail("Добыча дерева топором Lv.2 должна быть 3 (+1 бонус), факт: %d" % wood_lv2)
		return
	if hits_remaining_lv2 != 2:
		_fail("Остаток прочности после удара Lv.2 должен быть 2 (двойной урон), факт: %d" % hits_remaining_lv2)
		return
	tree_node.queue_free()
	print("✅ Добыча ресурсов инструментами Lv.2 дает подтвержденный бонус урона (+100%), выхода (+1) и экономии энергии (-35%).")

	# -------------------------------------------------------------
	# 5. Сельское хозяйство: вскопка железной лопатой (-50% энергии)
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Вскопка грядки железной лопатой Lv.2 ---")
	var plot1 = FarmlandPlot.new()
	world.add_child(plot1)

	# Вскопка базовой лопатой Lv.1
	inv.tools = ["axe", "pickaxe", "shovel", "bucket", "backpack"] as Array[String]
	inv.equipped_tool = "shovel"
	player.energy = 100.0
	plot1.till_soil(player)
	var energy_dig_lv1 = 100.0 - player.energy
	print("  • Вскопка лопатой Lv.1: потрачено энергии = %.1f (ожидалось 6.0)" % energy_dig_lv1)
	if abs(energy_dig_lv1 - 6.0) > 0.01:
		_fail("Вскопка базовой лопатой должна тратить 6.0 энергии, факт: %.1f" % energy_dig_lv1)
		return

	# Вскопка железной лопатой Lv.2
	var plot2 = FarmlandPlot.new()
	world.add_child(plot2)
	inv.upgrade_tool("iron_shovel")
	player.energy = 100.0
	plot2.till_soil(player)
	var energy_dig_lv2 = 100.0 - player.energy
	print("  • Вскопка лопатой Lv.2: потрачено энергии = %.1f (ожидалось 3.0)" % energy_dig_lv2)
	if abs(energy_dig_lv2 - 3.0) > 0.01:
		_fail("Вскопка железной лопатой должна тратить 3.0 энергии (-50%%), факт: %.1f" % energy_dig_lv2)
		return
	plot1.queue_free()
	plot2.queue_free()
	print("✅ Железная лопата сокращает затраты сил на вскопку вдвое (с 6 до 3).")

	# -------------------------------------------------------------
	# 6. Резервуар воды: набор усиленным ведром Lv.2
	# -------------------------------------------------------------
	print("\n--- Проверка 6: Набор чистой воды усиленным ведром Lv.2 ---")
	var reservoir = world.find_child("WaterReservoir", true, false)
	if not reservoir:
		_fail("WaterReservoir не найден в сцене World")
		return
	
	reservoir.current_water = 10
	player.thirst = 100.0 # Игрок сыт водой, поэтому набирает в ведро
	inv.items["clean_water"] = 0

	# Набор базовым ведром Lv.1
	inv.tools = ["axe", "pickaxe", "shovel", "bucket", "backpack"] as Array[String]
	inv.equipped_tool = "bucket"
	reservoir._on_interacted(player)
	var water_drawn_lv1 = inv.get_item_count("clean_water")
	print("  • Зачерпывание ведром Lv.1: набрано = %d л (остаток в баке: %d л)" % [water_drawn_lv1, reservoir.current_water])
	if water_drawn_lv1 != 1:
		_fail("Базовое ведро должно набирать 1 л, факт: %d" % water_drawn_lv1)
		return

	# Набор усиленным ведром Lv.2
	inv.upgrade_tool("reinforced_bucket")
	reservoir._on_interacted(player)
	var water_drawn_lv2 = inv.get_item_count("clean_water") - water_drawn_lv1
	print("  • Зачерпывание ведром Lv.2: набрано = %d л (остаток в баке: %d л)" % [water_drawn_lv2, reservoir.current_water])
	if water_drawn_lv2 != 2:
		_fail("Усиленное ведро Lv.2 должно набирать 2 л, факт: %d" % water_drawn_lv2)
		return
	print("✅ Усиленное ведро черпает двойную порцию чистой воды (2 л за раз).")

	# -------------------------------------------------------------
	# 7. Контракт: Оснащение экспедиции рудокопов (450 кредитов)
	# -------------------------------------------------------------
	print("\n--- Проверка 7: Выполнение контракта 'contract_master_tools' ---")
	var contract: Dictionary = ContractDB.get_contract("contract_master_tools")
	if contract.is_empty():
		_fail("Контракт 'contract_master_tools' не найден в ContractDB")
		return
	if contract.reward_credits != 450:
		_fail("Награда за контракт должна быть 450 кредитов, факт: %d" % contract.reward_credits)
		return
	
	inv.items["wooden_handle"] = 2
	inv.items["bolt"] = 4
	inv.items["fabric"] = 2
	inv.items["iron_ingot"] = 2
	inv.credits = 0

	if not ContractDB.can_fulfill(contract, inv):
		_fail("Контракт должен быть доступен для сдачи при наличии ресурсов")
		return
	
	var success = ContractDB.fulfill_contract("contract_master_tools", player)
	if not success:
		_fail("fulfill_contract вернул false")
		return
	if inv.credits != 450:
		_fail("Игроку должно быть начислено 450 кредитов, факт: %d" % inv.credits)
		return
	if inv.get_item_count("wooden_handle") != 0 or inv.get_item_count("bolt") != 0:
		_fail("Ресурсы контракта должны быть списаны из инвентаря")
		return
	if not ContractDB.is_completed("contract_master_tools"):
		_fail("Контракт должен быть помечен как выполненный")
		return
	print("  • Контракт успешно сдан! Начислено: %d кредитов. Остаток сырья списан." % inv.credits)
	print("✅ Контрактная экономика Этапа 11 работает безупречно.")

	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 11 УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)
