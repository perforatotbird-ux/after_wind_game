class_name SaveManager
extends RefCounted

## Централизованный менеджер сохранения и загрузки игры (Этап 12, разделы 81, 88)
## Сериализует полное состояние мира, персонажа, инвентаря, грядок, зданий и прогресса в JSON

const SAVE_FILE_NAME: String = "user://savegame.json"
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")

static func save_game(world: Node, file_path: String = SAVE_FILE_NAME) -> bool:
	if not world or not is_instance_valid(world):
		push_error("SaveManager: узел World не передан или невалиден")
		return false
	
	var save_data: Dictionary = {}
	
	# 1. Метаданные сохранения
	save_data["meta"] = {
		"version": "1.0.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info().get("string", "Godot 4.3")
	}
	
	# 2. Игрок и специализация
	var player = world.find_child("Player", true, false)
	if player and is_instance_valid(player):
		save_data["player"] = {
			"character_class": player.character_class if "character_class" in player else "miner",
			"position": {
				"x": player.global_position.x,
				"y": player.global_position.y,
				"z": player.global_position.z
			},
			"energy": player.energy if "energy" in player else 100.0,
			"thirst": player.thirst if "thirst" in player else 100.0,
			"hunger": player.hunger if "hunger" in player else 100.0,
			"wetness": player.wetness if "wetness" in player else 0.0
		}
		
		# 3. Инвентарь
		var inv = player.get("inventory") if "inventory" in player else null
		if inv and is_instance_valid(inv):
			save_data["inventory"] = {
				"items": inv.items.duplicate(true) if "items" in inv else {},
				"tools": inv.tools.duplicate() if "tools" in inv else [],
				"equipped_tool": inv.equipped_tool if "equipped_tool" in inv else "axe",
				"max_slots": inv.max_slots if "max_slots" in inv else 12,
				"max_weight": inv.max_weight if "max_weight" in inv else 50.0,
				"credits": inv.credits if "credits" in inv else 0
			}
	
	# 4. Суточный цикл DayNightCycle
	var day_cycle = world.find_child("DayNightCycle", true, false)
	if day_cycle and is_instance_valid(day_cycle):
		save_data["day_night"] = {
			"current_day": day_cycle.current_day if "current_day" in day_cycle else 1,
			"current_hour": day_cycle.current_hour if "current_hour" in day_cycle else 8.0
		}
	
	# 5. Погода WeatherManager
	var weather_mgr = world.find_child("WeatherManager", true, false)
	if weather_mgr and is_instance_valid(weather_mgr):
		save_data["weather"] = {
			"current_weather": int(weather_mgr.current_weather) if "current_weather" in weather_mgr else 0
		}
	
	# 6. Здания (House & Storage)
	var buildings_data: Dictionary = {}
	var house = world.find_child("RepairableHouse", true, false)
	if house and is_instance_valid(house):
		buildings_data["house_stage"] = house.current_stage if "current_stage" in house else 0
	var storage = world.find_child("RepairableStorage", true, false)
	if storage and is_instance_valid(storage):
		buildings_data["storage_stage"] = storage.current_stage if "current_stage" in storage else 0
	save_data["buildings"] = buildings_data
	
	# 7. Энергетика (BatteryBank)
	var battery = world.find_child("BatteryBank", true, false)
	if battery and is_instance_valid(battery):
		save_data["energy"] = {
			"stored_energy": battery.stored_energy if "stored_energy" in battery else 35.0
		}
	
	# 8. Водоснабжение (WaterReservoir)
	var reservoir = world.find_child("WaterReservoir", true, false)
	if reservoir and is_instance_valid(reservoir):
		save_data["water"] = {
			"current_water": reservoir.current_water if "current_water" in reservoir else 6
		}
	
	# 9. Грядки (FarmlandPlots)
	var plots_array: Array = []
	for p in world.find_children("*", "", true, false):
		if p.is_in_group("farmland_plots") or p.get_script() == FarmlandPlot:
			plots_array.append({
				"name": p.name,
				"soil_state": int(p.soil_state),
				"crop_type": p.crop_type,
				"moisture": p.moisture,
				"growth_progress": p.growth_progress,
				"is_ripe": p.is_ripe,
				"is_fertilized": p.is_fertilized
			})
	save_data["farmland"] = plots_array
	
	# 10. Контракты
	const ContractDB = preload("res://scripts/economy/contract_db.gd")
	save_data["contracts"] = {
		"completed": ContractDB.completed_contracts.duplicate(true)
	}
	
	# Незавершённое производство: сырьё уже списано, поэтому сохраняем и процесс.
	var machines: Array = []
	var traders: Dictionary = {}
	for node in world.find_children("*", "", true, false):
		if node is ProductionMachine:
			machines.append({
				"path": str(world.get_path_to(node)),
				"recipe_id": node.active_recipe.get("id", "") if node.is_machine_running else "",
				"timer": node.process_timer,
				"duration": node.process_duration
			})
		if "starter_seeds_given" in node:
			traders[str(world.get_path_to(node))] = node.starter_seeds_given
	save_data["machines"] = machines
	save_data["traders"] = traders

	# Пишем во временный файл: не обнуляем последнее сохранение при сбое записи.
	var json_str: String = JSON.stringify(save_data, "\t")
	var temp_path: String = file_path + ".tmp"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Ошибка открытия файла для записи: " + file_path)
		return false
	
	file.store_string(json_str)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		push_error("SaveManager: ошибка записи сохранения: %d" % write_error)
		return false
	var rename_error: Error = DirAccess.rename_absolute(temp_path, file_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		push_error("SaveManager: ошибка замены сохранения: %d" % rename_error)
		return false
	
	if player and player.has_method("notify"):
		player.notify("💾 Игра успешно сохранена!")
	
	return true

static func load_game(world: Node, file_path: String = SAVE_FILE_NAME) -> bool:
	if not world or not is_instance_valid(world):
		push_error("SaveManager: узел World не передан")
		return false
	
	if not FileAccess.file_exists(file_path):
		push_warning("SaveManager: файл сохранения не найден: " + file_path)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("SaveManager: не удалось открыть файл: " + file_path)
		return false
	
	var content: String = file.get_as_text()
	file.close()
	
	var test_json = JSON.new()
	var parse_err = test_json.parse(content)
	if parse_err != OK:
		push_error("SaveManager: Ошибка парсинга JSON сохранения: %d" % parse_err)
		return false
	
	var save_data = test_json.data
	if typeof(save_data) != TYPE_DICTIONARY:
		push_error("SaveManager: некорректный формат данных сохранения")
		return false
	
	# Валидация ВСЕХ секций до первого изменения мира.
	if not _validate_save_data(save_data):
		push_warning("SaveManager: некорректные поля сохранения")
		return false

	# 1. Восстановление игрока и инвентаря
	var player = world.find_child("Player", true, false)
	if player and is_instance_valid(player) and save_data.has("player"):
		var p_data: Dictionary = save_data["player"]
		if p_data.has("character_class") and player.has_method("set_character_class"):
			player.set_character_class(p_data["character_class"], false)
		
		if p_data.has("position"):
			var pos_dict = p_data["position"]
			player.global_position = Vector3(
				pos_dict.get("x", player.global_position.x),
				pos_dict.get("y", player.global_position.y),
				pos_dict.get("z", player.global_position.z)
			)
		
		if p_data.has("energy"):
			player.energy = p_data["energy"]
			if player.has_signal("energy_changed"):
				player.energy_changed.emit(player.energy, player.max_energy)
		if p_data.has("thirst"):
			player.thirst = p_data["thirst"]
			if player.has_signal("thirst_changed"):
				player.thirst_changed.emit(player.thirst, player.max_thirst)
		if p_data.has("hunger"):
			player.hunger = p_data["hunger"]
			if player.has_signal("hunger_changed"):
				player.hunger_changed.emit(player.hunger, player.max_hunger)
		if p_data.has("wetness"):
			player.wetness = p_data["wetness"]
			if player.has_signal("wetness_changed"):
				player.wetness_changed.emit(player.wetness, player.max_wetness)
		
		# Инвентарь
		var inv = player.get("inventory") if "inventory" in player else null
		if inv and is_instance_valid(inv) and save_data.has("inventory"):
			var inv_data: Dictionary = save_data["inventory"]
			if inv_data.has("items"):
				inv.items = inv_data["items"].duplicate(true)
			if inv_data.has("tools"):
				var loaded_tools: Array[String] = []
				for t in inv_data["tools"]:
					loaded_tools.append(str(t))
				inv.tools = loaded_tools
			if inv_data.has("equipped_tool"):
				var saved_tool: String = inv_data["equipped_tool"]
				if inv.equipped_tool == saved_tool:
					inv._notify_tool_changed()
				else:
					inv.equip_tool(saved_tool)
			if inv_data.has("max_slots"):
				inv.max_slots = int(inv_data["max_slots"])
			if inv_data.has("max_weight"):
				inv.max_weight = float(inv_data["max_weight"])
			if inv_data.has("credits"):
				inv.credits = int(inv_data["credits"])
				if inv.has_signal("credits_changed"):
					inv.credits_changed.emit(inv.credits)
			if inv.has_signal("inventory_updated"):
				inv.inventory_updated.emit()
	
	# 2. Суточный цикл
	if save_data.has("day_night"):
		var dn_data: Dictionary = save_data["day_night"]
		var day_cycle = world.find_child("DayNightCycle", true, false)
		if day_cycle and is_instance_valid(day_cycle):
			var s_day: int = int(dn_data.get("current_day", 1))
			var s_hour: float = float(dn_data.get("current_hour", dn_data.get("time_of_day", 8.0)))
			if day_cycle.has_method("set_time"):
				day_cycle.set_time(s_day, s_hour)
			else:
				if "current_day" in day_cycle:
					day_cycle.current_day = s_day
				if "current_hour" in day_cycle:
					day_cycle.current_hour = s_hour
	
	# 3. Погода
	if save_data.has("weather"):
		var w_data: Dictionary = save_data["weather"]
		var weather_mgr = world.find_child("WeatherManager", true, false)
		if weather_mgr and is_instance_valid(weather_mgr) and w_data.has("current_weather"):
			if weather_mgr.has_method("set_weather"):
				weather_mgr.set_weather(int(w_data["current_weather"]))
	
	# 4. Здания
	if save_data.has("buildings"):
		var b_data: Dictionary = save_data["buildings"]
		var house = world.find_child("RepairableHouse", true, false)
		if house and is_instance_valid(house) and b_data.has("house_stage"):
			var target_stage = int(b_data["house_stage"])
			house.current_stage = target_stage
			if house.has_method("_update_visuals"):
				house._update_visuals()
			if house.has_method("_update_prompt_text"):
				house._update_prompt_text()
		var storage = world.find_child("RepairableStorage", true, false)
		if storage and is_instance_valid(storage) and b_data.has("storage_stage"):
			var target_stage = int(b_data["storage_stage"])
			storage.current_stage = target_stage
			if storage.has_method("_update_visuals"):
				storage._update_visuals()
			if storage.has_method("_update_prompt_text"):
				storage._update_prompt_text()
	
	# 5. Энергетика
	if save_data.has("energy"):
		var en_data: Dictionary = save_data["energy"]
		var stored_val: float = float(en_data.get("stored_energy", 30.0))
		var grid = world.find_child("PowerGrid", true, false)
		if grid and is_instance_valid(grid) and "current_stored" in grid:
			grid.current_stored = stored_val
		var battery = world.find_child("BatteryBank", true, false)
		if battery and is_instance_valid(battery):
			battery.stored_energy = stored_val
	
	# 6. Резервуар воды
	if save_data.has("water"):
		var wt_data: Dictionary = save_data["water"]
		var reservoir = world.find_child("WaterReservoir", true, false)
		if reservoir and is_instance_valid(reservoir) and wt_data.has("current_water"):
			reservoir.current_water = int(wt_data["current_water"])
			if reservoir.has_signal("water_level_changed"):
				reservoir.water_level_changed.emit(reservoir.current_water, reservoir.max_capacity)
	
	# 7. Грядки
	if save_data.has("farmland"):
		var plots_list = save_data["farmland"]
		var plots_by_name: Dictionary = {}
		for p in world.find_children("*", "", true, false):
			if p.is_in_group("farmland_plots") or p.get_script() == FarmlandPlot:
				plots_by_name[p.name] = p
		
		for p_state in plots_list:
			var p_name = p_state.get("name", "")
			var plot = plots_by_name.get(p_name, null)
			if plot and is_instance_valid(plot):
				plot.soil_state = int(p_state.get("soil_state", 0))
				plot.crop_type = p_state.get("crop_type", "")
				plot.moisture = float(p_state.get("moisture", 0.0))
				plot.growth_progress = float(p_state.get("growth_progress", 0.0))
				plot.is_ripe = bool(p_state.get("is_ripe", false))
				plot.is_fertilized = bool(p_state.get("is_fertilized", false))
				if plot.has_method("_update_visuals"):
					plot._update_visuals()
	
	# 8. Контракты
	if save_data.has("contracts"):
		var c_data: Dictionary = save_data["contracts"]
		const ContractDB = preload("res://scripts/economy/contract_db.gd")
		if c_data.has("completed"):
			ContractDB.completed_contracts = c_data["completed"].duplicate(true)
	
	# Старые сохранения без этих секций продолжают загружаться.
	for state in save_data.get("machines", []):
		var machine = world.get_node_or_null(NodePath(state["path"]))
		if not machine is ProductionMachine:
			continue
		var recipe: Dictionary = RecipeDB.get_recipe(state["recipe_id"])
		if not recipe.is_empty() and recipe.get("machine", "") != machine.machine_type:
			continue
		machine.active_recipe = recipe
		machine.process_timer = float(state["timer"])
		machine.process_duration = float(state["duration"])
		machine.is_machine_running = not recipe.is_empty()
		machine._last_user = player
		if machine.visual_node:
			machine.visual_node.position = machine._original_pos
	for path in save_data.get("traders", {}):
		var trader = world.get_node_or_null(NodePath(path))
		if trader and "starter_seeds_given" in trader:
			trader.starter_seeds_given = save_data["traders"][path]

	if player and player.has_method("notify"):
		player.notify("📂 Игра успешно загружена!")
	
	return true

static func has_save(file_path: String = SAVE_FILE_NAME) -> bool:
	return FileAccess.file_exists(file_path)

static func delete_save(file_path: String = SAVE_FILE_NAME) -> bool:
	if FileAccess.file_exists(file_path):
		var err = DirAccess.remove_absolute(file_path)
		return err == OK
	return false

# JSON numbers are floats, including values that were originally integers.
static func _is_number(value: Variant, minimum: float = -INF, maximum: float = INF) -> bool:
	return (typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value)) and value >= minimum and value <= maximum)

static func _is_integer(value: Variant, minimum: float = 0.0, maximum: float = INF) -> bool:
	return _is_number(value, minimum, maximum) and float(value) == floor(float(value))

static func _validate_save_data(data: Dictionary) -> bool:
	for section in ["meta", "player", "inventory", "day_night", "weather", "buildings", "energy", "water", "contracts", "traders"]:
		if data.has(section) and not data[section] is Dictionary:
			return false
	var p: Dictionary = data.get("player", {})
	if p.has("character_class"):
		if not p["character_class"] is String or CharacterClassDB.get_class_data(p["character_class"]).is_empty():
			return false
	for key in ["energy", "thirst", "hunger", "wetness"]:
		if p.has(key) and not _is_number(p[key], 0.0):
			return false
	if p.has("position"):
		if not p["position"] is Dictionary:
			return false
		for axis in ["x", "y", "z"]:
			if p["position"].has(axis) and not _is_number(p["position"][axis]):
				return false
	var inv: Dictionary = data.get("inventory", {})
	if inv.has("items"):
		if not inv["items"] is Dictionary:
			return false
		for key in inv["items"]:
			if ItemDB.get_item(key).is_empty() or not _is_integer(inv["items"][key]):
				return false
	if inv.has("tools"):
		if not inv["tools"] is Array:
			return false
		for tool in inv["tools"]:
			if not tool is String or ItemDB.get_item(tool).get("category", "") not in ["tool", "equipment"]:
				return false
	if inv.has("equipped_tool"):
		if not inv["equipped_tool"] is String or ItemDB.get_item(inv["equipped_tool"]).is_empty():
			return false
		if inv.has("tools") and not inv["tools"].has(inv["equipped_tool"]):
			return false
	for key in ["max_slots", "credits"]:
		if inv.has(key) and not _is_integer(inv[key]):
			return false
	if inv.has("max_weight") and not _is_number(inv["max_weight"], 0.0):
		return false
	var dn: Dictionary = data.get("day_night", {})
	if dn.has("current_day") and not _is_integer(dn["current_day"], 1.0):
		return false
	for key in ["current_hour", "time_of_day"]:
		if dn.has(key) and not _is_number(dn[key], 0.0, 24.0):
			return false
	var weather: Dictionary = data.get("weather", {})
	if weather.has("current_weather") and not _is_integer(weather["current_weather"], 0.0, 3.0):
		return false
	var buildings: Dictionary = data.get("buildings", {})
	for key in ["house_stage", "storage_stage"]:
		if buildings.has(key) and not _is_integer(buildings[key], 0.0, 3.0):
			return false
	var energy: Dictionary = data.get("energy", {})
	if energy.has("stored_energy") and not _is_number(energy["stored_energy"], 0.0):
		return false
	var water: Dictionary = data.get("water", {})
	if water.has("current_water") and not _is_integer(water["current_water"]):
		return false
	if data.has("farmland"):
		if not data["farmland"] is Array:
			return false
		for plot in data["farmland"]:
			if not plot is Dictionary or not plot.get("name", "") is String:
				return false
			if not _is_integer(plot.get("soil_state", 0), 0.0, 1.0):
				return false
			if plot.get("crop_type", "") not in ["", "carrot", "potato", "wheat"]:
				return false
			for key in ["moisture", "growth_progress"]:
				if not _is_number(plot.get(key, 0.0), 0.0, 100.0):
					return false
			for key in ["is_ripe", "is_fertilized"]:
				if not plot.get(key, false) is bool:
					return false
	var contracts: Dictionary = data.get("contracts", {})
	if contracts.has("completed"):
		if not contracts["completed"] is Dictionary:
			return false
		for key in contracts["completed"]:
			if not contracts["completed"][key] is bool:
				return false
	if data.has("machines"):
		if not data["machines"] is Array:
			return false
		for state in data["machines"]:
			if not state is Dictionary or not _is_relative_path(state.get("path", "")):
				return false
			var recipe_id = state.get("recipe_id", "")
			if not recipe_id is String or (recipe_id != "" and RecipeDB.get_recipe(recipe_id).is_empty()):
				return false
			if not _is_number(state.get("duration"), 0.01) or not _is_number(state.get("timer"), 0.0, state["duration"]):
				return false
	for path in data.get("traders", {}):
		if not _is_relative_path(path) or not data["traders"][path] is bool:
			return false
	return true

static func _is_relative_path(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.begins_with("/") and not ".." in value.split("/") and not ":" in value
