extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const WeatherManager = preload("res://scripts/world/weather_manager.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 10...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 10: ЭЛЕКТРОГЕНЕРАЦИЯ И ОСВЕЩЕНИЕ")
	print("========================================")
	
	ContractDB.reset_completed()
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var hud = world.get_node_or_null("HUD")
	if not hud:
		_fail("HUD отсутствует в сцене")
		return
	
	var day_cycle = world.get_node_or_null("DayNightCycle")
	if not day_cycle:
		_fail("DayNightCycle отсутствует в сцене")
		return
	
	var weather_mgr = world.get_node_or_null("WeatherManager")
	if not weather_mgr:
		_fail("WeatherManager отсутствует в сцене")
		return
	
	var power_grid = world.get_node_or_null("PowerGrid")
	if not power_grid:
		_fail("PowerGrid отсутствует в сцене")
		return
	
	var turbine = world.find_child("WindTurbine", true, false)
	var battery = world.find_child("BatteryBank", true, false)
	var lamp1 = world.find_child("StreetLamp1", true, false)
	var lamp2 = world.find_child("StreetLamp2", true, false)
	
	if not turbine:
		_fail("WindTurbine отсутствует в Props")
		return
	if not battery:
		_fail("BatteryBank отсутствует в Props")
		return
	if not lamp1 or not lamp2:
		_fail("StreetLamp1 или StreetLamp2 отсутствуют в Props")
		return
	
	print("✅ Все ключевые узлы найдены (PowerGrid, WindTurbine, BatteryBank, StreetLamp1, StreetLamp2, HUD).")

	# -------------------------------------------------------------
	# 1. Проверка базы предметов ItemDB (компоненты электрики)
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Реестр компонентов электрификации в ItemDB ---")
	var electric_items: Array[String] = ["copper_wire", "iron_plate", "gear", "battery_cell", "street_lamp_item"]
	for item_id in electric_items:
		var item: Dictionary = ItemDB.get_item(item_id)
		if item.is_empty():
			_fail("Предмет '%s' отсутствует в ItemDB" % item_id)
			return
		if item.weight <= 0.0:
			_fail("Вес предмета '%s' должен быть > 0" % item_id)
			return
		if item.sell_price <= 0:
			_fail("Цена сбыта предмета '%s' должна быть > 0" % item_id)
			return
		print("  • Предмет '%s': %s (вес: %.1f кг, цена: %d кр.)" % [item_id, item.name, item.weight, item.sell_price])
	print("✅ База предметов ItemDB полностью валидна.")

	# -------------------------------------------------------------
	# 2. Проверка рецептов верстака RecipeDB
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Рецепты компонентов энергосети в RecipeDB ---")
	var electric_recipes: Array[String] = ["craft_copper_wire", "craft_iron_plate", "craft_gear", "craft_battery_cell", "craft_street_lamp"]
	for r_id in electric_recipes:
		var r: Dictionary = RecipeDB.get_recipe(r_id)
		if r.is_empty():
			_fail("Рецепт '%s' отсутствует в RecipeDB" % r_id)
			return
		if r.machine != "workbench":
			_fail("Рецепт '%s' должен производиться на верстаке" % r_id)
			return
		if r.inputs.is_empty() or r.outputs.is_empty():
			_fail("Рецепт '%s' имеет пустые inputs или outputs" % r_id)
			return
		print("  • Рецепт '%s': %s (машина: %s, время: %.1f сек)" % [r_id, r.name, r.machine, r.duration])
	print("✅ Рецепты крафта компонентов проверены успешно.")

	# -------------------------------------------------------------
	# 3. Контракт на электрификацию в ContractDB
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Контракт «Электрификация блокпоста» ---")
	var contract: Dictionary = ContractDB.get_contract("contract_electrification")
	if contract.is_empty():
		_fail("Контракт 'contract_electrification' отсутствует в ContractDB")
		return
	if contract.reward_credits != 320:
		_fail("Награда за контракт должна быть 320 кредитов (факт: %d)" % contract.reward_credits)
		return
	
	var inv = player.inventory
	inv.clear()
	if ContractDB.can_fulfill(contract, inv):
		_fail("Контракт не должен выполняться с пустым инвентарем")
		return
	
	inv.add_item("copper_wire", 4)
	inv.add_item("battery_cell", 2)
	inv.add_item("street_lamp_item", 1)
	# Заказ третьей волны: открывается после 3 выполненных заказов.
	if ContractDB.can_fulfill(contract, inv):
		_fail("Заказ электрификации не должен быть доступен до 3 выполненных заказов")
		return
	for done_id in ["contract_fortify", "contract_fuel_reserve", "contract_fresh_harvest"]:
		ContractDB.completed_contracts[done_id] = true
	if not ContractDB.can_fulfill(contract, inv):
		_fail("Контракт должен быть готов к сдаче при наличии 4 проводов, 2 аккумуляторов и фонаря")
		return
	
	player.inventory.credits = 100
	var fulfilled: bool = ContractDB.fulfill_contract("contract_electrification", player)
	if not fulfilled or player.inventory.credits != 420:
		_fail("Сдача контракта не начислила +320 кредитов (баланс: %d)" % player.inventory.credits)
		return
	if inv.get_item_count("copper_wire") != 0 or inv.get_item_count("battery_cell") != 0:
		_fail("Ресурсы контракта не были списаны из инвентаря")
		return
	print("✅ Контракт 'contract_electrification' успешно сдан (+320 кредитов).")

	# -------------------------------------------------------------
	# 4. Проверка Ветрогенератора WindTurbine
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Ветрогенератор и зависимость генерации от погоды ---")
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	var out_sunny: float = turbine.get_current_output()
	if out_sunny != 2.0:
		_fail("Выработка в солнечную погоду должна быть 2.0 кВт (факт: %f)" % out_sunny)
		return
	
	weather_mgr.set_weather(WeatherManager.WeatherType.OVERCAST)
	var out_overcast: float = turbine.get_current_output()
	if out_overcast != 3.5:
		_fail("Выработка в пасмурную погоду должна быть 3.5 кВт (факт: %f)" % out_overcast)
		return
	
	weather_mgr.set_weather(WeatherManager.WeatherType.RAIN)
	var out_rain: float = turbine.get_current_output()
	if out_rain != 5.5:
		_fail("Выработка в дождь должна быть 5.5 кВт (факт: %f)" % out_rain)
		return
	
	weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN)
	var out_heavy: float = turbine.get_current_output()
	if out_heavy != 8.5:
		_fail("Выработка в сильный ливень должна быть 8.5 кВт (факт: %f)" % out_heavy)
		return
	
	if turbine.rotor_node:
		var rot_before: float = turbine.rotor_node.rotation.z
		turbine._process(0.5)
		var rot_after: float = turbine.rotor_node.rotation.z
		if rot_before == rot_after:
			_fail("Ротор ветрогенератора должен вращаться во время работы")
			return
		print("  • Вращение ротора ветряка функционирует динамически.")
	
	turbine.interact(player)
	print("✅ Ветрогенератор масштабирует мощность от ветра (2.0 -> 3.5 -> 5.5 -> 8.5 кВт).")

	# -------------------------------------------------------------
	# 5. Проверка Аккумуляторного накопителя BatteryBank
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Аккумуляторный блок накопителей ---")
	if battery.capacity != 100.0:
		_fail("Емкость батарейного блока должна быть 100.0 кВт·ч")
		return
	
	# Проверка смены цветов индикатора заряда
	battery.update_charge_display(80.0, 100.0, 2.0)
	if battery.status_light and battery.status_light.light_color.g < 0.8:
		_fail("При заряде 80%% индикатор должен светиться зеленым")
		return
	
	battery.update_charge_display(35.0, 100.0, -1.0)
	if battery.status_light and battery.status_light.light_color.r < 0.8:
		_fail("При заряде 35%% индикатор должен светиться желтым")
		return
	
	battery.update_charge_display(10.0, 100.0, -2.0)
	if battery.status_light and (battery.status_light.light_color.r < 0.8 or battery.status_light.light_color.g > 0.4):
		_fail("При заряде 10%% индикатор должен светиться красным")
		return
	
	battery.interact(player)
	print("✅ Индикация и мониторинг емкости батарейного накопителя подтверждены.")

	# -------------------------------------------------------------
	# 6. Проверка Уличных фонарей StreetLamp и ночного освещения
	# -------------------------------------------------------------
	print("\n--- Проверка 6: Уличные фонари и автоматическое включение ночью ---")
	# Днем (12:00) фонари должны быть выключены
	day_cycle.current_hour = 12.0
	lamp1._update_lamp_state()
	if lamp1.is_on:
		_fail("Днем в 12:00 фонарь не должен гореть")
		return
	if lamp1.get_power_demand() != 0.0:
		_fail("Днем выключенный фонарь не должен потреблять энергию")
		return
	print("  • Дневной режим: фонари выключены, потребление 0.0 кВт.")
	
	# Ночью (22:00) при наличии питания фонари должны загореться
	day_cycle.current_hour = 22.0
	lamp1.set_powered(true)
	if not lamp1.is_on:
		_fail("Ночью при наличии питания фонарь должен гореть")
		return
	if lamp1.lamp_light and not lamp1.lamp_light.visible:
		_fail("Источник света OmniLight3D фонаря должен быть включен ночью")
		return
	if lamp1.get_power_demand() <= 0.0:
		_fail("Включенный фонарь должен запрашивать мощность питания (> 0)")
		return
	print("  • Ночной режим: фонарь горит (+%.1f кВт нагрузки), освещая базу." % lamp1.get_power_demand())
	
	# При обесточивании сети фонарь должен погаснуть
	lamp1.set_powered(false)
	if lamp1.is_on:
		_fail("При отсутствии питания фонарь должен погаснуть")
		return
	if lamp1.lamp_light and lamp1.lamp_light.visible:
		_fail("Свет обесточенного фонаря должен быть выключен")
		return
	print("  • Обесточивание: фонарь мгновенно гаснет без питания.")

	# -------------------------------------------------------------
	# 7. Проверка Энергосети PowerGrid и HUD
	# -------------------------------------------------------------
	print("\n--- Проверка 7: Энергосеть PowerGrid и статус в HUD ---")
	power_grid._scan_grid_devices()
	
	# Устанавливаем солнечную погоду и ночное время
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY) # генерация 2.0 кВт
	day_cycle.current_hour = 23.0 # оба фонаря активны: 0.4 + 0.4 = 0.8 кВт
	
	power_grid._update_grid(1.0)
	if power_grid.current_generation < 1.9:
		_fail("Генерация сети должна учитывать ветряк (~2.0 кВт, факт: %f)" % power_grid.current_generation)
		return
	if power_grid.current_consumption < 0.7:
		_fail("Потребление сети должно учитывать 2 активных фонаря (~0.8 кВт, факт: %f)" % power_grid.current_consumption)
		return
	if not power_grid.has_power:
		_fail("Сеть должна быть запитана при положительном балансе генерации")
		return
	
	# Проверка отображения в HUD
	hud.update_power_display(power_grid.current_stored, power_grid.max_capacity, power_grid.current_generation, power_grid.current_consumption, power_grid.has_power)
	if not hud.power_label:
		_fail("PowerLabel отсутствует в HUD")
		return
	if not ("Сеть" in hud.power_label.text and "⚡" in hud.power_label.text):
		_fail("HUD PowerLabel не отображает статус энергосети: %s" % hud.power_label.text)
		return
	print("  • HUD корректно отображает статус сети: %s" % hud.power_label.text)
	
	# Тест глубокого разряда аккумуляторов
	power_grid.current_stored = 0.0
	turbine.is_operational = false # отключаем генератор
	power_grid._update_grid(1.0)
	if power_grid.has_power:
		_fail("Без генерации и с 0%% аккумулятора сеть должна быть обесточена")
		return
	
	hud.update_power_display(0.0, 100.0, 0.0, 0.8, false)
	if not ("Обесточена" in hud.power_label.text):
		_fail("При отключении сети HUD должен показывать 'Обесточена': %s" % hud.power_label.text)
		return
	print("  • Аварийный режим обесточивания подтвержден: %s" % hud.power_label.text)

	print("\n========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 10 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	quit(0)
