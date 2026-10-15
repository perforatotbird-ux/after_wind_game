class_name SaveManager
extends RefCounted

## Централизованный менеджер сохранения и загрузки игры (Этап 12, разделы 81, 88).
## Сериализует состояние мира, персонажа, инвентаря, грядок, зданий, машин (включая
## партии), ресурсных узлов, жил (выкопанные блоки), выброшенных предметов и прогресса в JSON. Формат
## версионируется (meta.format_version); старые сохранения мигрируют в _migrate_save_data.
## Описание формата — docs/DOCUMENTATION.md, раздел «Сохранения».

const SAVE_FILE_NAME: String = "user://savegame.json"
## Текущая версия формата. v1 — сохранения без format_version (до унификации).
const SAVE_FORMAT_VERSION: int = 2
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")
const FarmFieldScript = preload("res://scripts/farming/farm_field.gd")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const ResourceNodeScript = preload("res://scripts/resources/resource_node.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")
const VoxelDepositScript = preload("res://scripts/world/voxel_deposit.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const WarehouseInventory = preload("res://scripts/inventory/warehouse_inventory.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const CropDB = preload("res://scripts/farming/crop_db.gd")
const FruitTreeScript = preload("res://scripts/resources/fruit_tree.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const SeasonManagerScript = preload("res://scripts/world/season_manager.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")
const MushroomSpawnerScript = preload("res://scripts/world/mushroom_spawner.gd")
const CampfireScript = preload("res://scripts/crafting/campfire.gd")

static func save_game(world: Node, file_path: String = SAVE_FILE_NAME) -> bool:
	if not world or not is_instance_valid(world):
		push_error("SaveManager: узел World не передан или невалиден")
		return false
	
	var save_data: Dictionary = {}
	
	# 1. Метаданные сохранения
	save_data["meta"] = {
		"format_version": SAVE_FORMAT_VERSION,
		"version": "1.0.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info().get("string", "unknown")
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
			"health": player.health if "health" in player else 100.0,
			"energy": player.energy if "energy" in player else 100.0,
			"thirst": player.thirst if "thirst" in player else 100.0,
			"hunger": player.hunger if "hunger" in player else 100.0,
			"wetness": player.wetness if "wetness" in player else 0.0,
			"hours_without_sleep": player.hours_without_sleep if "hours_without_sleep" in player else 0.0,
			"skills": player.skills.serialize() if ("skills" in player and player.skills and player.skills.has_method("serialize")) else {}
		}
		
		# 3. Инвентарь (max_slots / max_weight — справочно: при загрузке пересчитываются)
		var inv = player.get("inventory") if "inventory" in player else null
		if inv and is_instance_valid(inv):
			save_data["inventory"] = {
				"items": inv.items.duplicate(true) if "items" in inv else {},
				"tools": inv.tools.duplicate() if "tools" in inv else [],
				"equipped_tool": inv.equipped_tool if "equipped_tool" in inv else "axe",
				"max_slots": inv.max_slots if "max_slots" in inv else 12,
				"max_weight": inv.max_weight if "max_weight" in inv else 50.0,
				"credits": inv.credits if "credits" in inv else 0,
				"slot_layout": inv.slot_layout.duplicate() if "slot_layout" in inv else [],
				"tool_sharpness": inv.tool_sharpness.duplicate() if "tool_sharpness" in inv else {"axe": 100.0, "pickaxe": 100.0, "shovel": 100.0}
			}
	
	# 4. Суточный цикл DayNightCycle
	var day_cycle = world.find_child("DayNightCycle", true, false)
	if day_cycle and is_instance_valid(day_cycle):
		save_data["day_night"] = {
			"current_day": day_cycle.current_day if "current_day" in day_cycle else 1,
			"current_hour": day_cycle.current_hour if "current_hour" in day_cycle else 8.0
		}
	
	# 5. Погода WeatherManager (включая фазу автоцикла)
	var weather_mgr = world.find_child("WeatherManager", true, false)
	if weather_mgr and is_instance_valid(weather_mgr):
		var w_save: Dictionary = {
			"current_weather": int(weather_mgr.current_weather) if "current_weather" in weather_mgr else 0
		}
		if "_timer" in weather_mgr:
			w_save["timer"] = maxf(0.0, float(weather_mgr._timer))
		if "_cycle_index" in weather_mgr:
			w_save["cycle_index"] = int(weather_mgr._cycle_index)
		save_data["weather"] = w_save
	
	# 5а. Сезоны и погодные события (SeasonManager)
	var season_mgr = world.find_child("SeasonManager", true, false)
	if season_mgr and is_instance_valid(season_mgr) and season_mgr.has_method("get_save_state"):
		save_data["seasons"] = season_mgr.get_save_state()
	elif Seasons.is_enabled():
		# Узла нет (тест/минимальная сцена) — сохраняем хотя бы календарь.
		save_data["seasons"] = {
			"enabled": true,
			"total_day": day_cycle.current_day if (day_cycle and "current_day" in day_cycle) else 1,
			"current_season": Seasons.get_current_season(),
			"day_in_season": Seasons.get_day_in_season(),
			"year": Seasons.get_year(),
			"active_event": "",
			"event_hours_left": 0.0
		}
	
	# 6. Здания (House & Storage)
	var buildings_data: Dictionary = {}
	var house = world.find_child("RepairableHouse", true, false)
	if house and is_instance_valid(house):
		buildings_data["house_stage"] = house.current_stage if "current_stage" in house else 0
		# Накопленные внутри дома материалы достройки (стадия применяется,
		# только когда комплект собран — промежуточные взносы не теряются).
		if "delivered" in house:
			buildings_data["house_delivered"] = (house.delivered as Dictionary).duplicate(true)
			buildings_data["house_delivered_credits"] = int(house.delivered_credits) if "delivered_credits" in house else 0
	var storage = world.find_child("RepairableStorage", true, false)
	if storage and is_instance_valid(storage):
		buildings_data["storage_stage"] = storage.current_stage if "current_stage" in storage else 0
		if "delivered" in storage:
			buildings_data["storage_delivered"] = (storage.delivered as Dictionary).duplicate(true)
			buildings_data["storage_delivered_credits"] = int(storage.delivered_credits) if "delivered_credits" in storage else 0
	if storage and "storage_inventory" in storage:
		buildings_data["storage_inventory"] = storage.storage_inventory.export_state()
	save_data["buildings"] = buildings_data
	
	# 7. Энергетика (BatteryBank)
	var battery = world.find_child("BatteryBank", true, false)
	var energy_grid = world.find_child("PowerGrid", true, false)
	if battery and is_instance_valid(battery):
		save_data["energy"] = {
			"stored_energy": battery.stored_energy if "stored_energy" in battery else 35.0,
			"source_mode": int(energy_grid.get("source_mode")) if energy_grid and "source_mode" in energy_grid else 0
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
	save_data["contracts"] = {
		"completed": ContractDB.completed_contracts.duplicate(true)
	}
	
	# 11. Прогресс финала
	var hud = world.find_child("HUD", true, false)
	save_data["progress"] = {
		"victory_shown": bool(hud._victory_shown) if (hud and "_victory_shown" in hud) else false
	}
	
	# 12. Машины (незавершённое производство и партия, счётчик циклов, ожидающая
	# продукция), торговцы, ресурсные узлы и выброшенные предметы.
	var machines: Array = []
	var traders: Dictionary = {}
	var resources: Array = []
	var dropped: Array = []
	var deposits: Array = []
	for node in world.find_children("*", "", true, false):
		if node is ProductionMachine:
			var machine_data: Dictionary = {
				"path": str(world.get_path_to(node)),
				"recipe_id": node.active_recipe.get("id", "") if node.is_machine_running else "",
				"timer": node.process_timer,
				"duration": node.process_duration,
				"completed_runs": node.completed_runs,
				"pending_outputs": node.pending_outputs.duplicate(true),
				"batch_total": node.batch_cycles_total,
				"batch_done": node.batch_cycles_done,
				"batch_to_buffer": node.batch_to_buffer,
				"level": int(node.get_level()) if node.level_state else 1,
				"wear": float(node.wear.condition) if node.wear else 100.0,
				"fuel_slots": node.fuel_slots.duplicate(true) if node.has_fuel_slots else [],
				"fuel_burn_left": maxf(0.0, float(node.fuel_burn_left)),
				"rebuilt": bool(node.rebuilt) if "rebuilt" in node else true,
				# Компоненты, накопленные внутри станка для текущей работы
				# (восстановление/ремонт/улучшение идут порциями).
				"job_stash": node.job_stash.duplicate(true) if "job_stash" in node else {},
				"job_credits": node.job_credits.duplicate(true) if "job_credits" in node else {}
			}
			if node is CampfireScript:
				machine_data["fire_has_burned"] = node.has_burned
			machines.append(machine_data)
		elif node is ResourceNodeScript:
			resources.append({
				"path": str(world.get_path_to(node)),
				"is_depleted": bool(node.is_depleted),
				"respawn_timer": maxf(0.0, float(node.respawn_timer)),
				"current_hits": maxi(0, int(node.current_hits)),
				"is_growing": bool(node.is_growing),
				"growth_hours": maxf(0.0, float(node.growth_progress_hours))
			})
		elif node is VoxelDepositScript:
			var dep_state: Dictionary = node.get_save_state()
			dep_state["path"] = str(world.get_path_to(node))
			deposits.append(dep_state)
		elif node.is_in_group(DroppedItemScript.GROUP) and "item_id" in node and not node.is_queued_for_deletion():
			if int(node.amount) > 0:
				dropped.append({
					"item_id": str(node.item_id),
					"amount": int(node.amount),
					"x": node.global_position.x,
					"y": node.global_position.y,
					"z": node.global_position.z
				})
		if "starter_seeds_given" in node:
			traders[str(world.get_path_to(node))] = node.starter_seeds_given
	save_data["machines"] = machines
	save_data["traders"] = traders
	save_data["resources"] = resources
	save_data["dropped_items"] = dropped
	save_data["deposits"] = deposits
	# 13а. Делянки: размер, стадия стройки, принесённые материалы и все клетки.
	var fields_arr: Array = []
	for f in (world.get_tree().get_nodes_in_group("farm_fields") if world.is_inside_tree() else []):
		if is_instance_valid(f) and not f.is_queued_for_deletion() and world.is_ancestor_of(f):
			fields_arr.append(f.get_save_state())
	save_data["farm_fields"] = fields_arr
	# 13б. Фруктовые деревья: координаты, вид, стадия, плоды и прогресс.
	var fruit_trees_arr: Array = []
	for ft in (world.get_tree().get_nodes_in_group("fruit_trees") if world.is_inside_tree() else []):
		if is_instance_valid(ft) and not ft.is_queued_for_deletion() and world.is_ancestor_of(ft):
			fruit_trees_arr.append(ft.get_save_state())
	save_data["fruit_trees"] = fruit_trees_arr
	# 13. Ягодные кусты: зерно раскладки и урожай каждого куста.
	var berry_spawner = world.find_child("BerryBushes", true, false)
	if berry_spawner and berry_spawner.has_method("get_save_state"):
		save_data["berry_bushes"] = berry_spawner.get_save_state()
	# 13г. Лесные грибы: раскладка и состояние каждого гриба.
	var shroom_spawner = world.find_child("MushroomPatches", true, false)
	if shroom_spawner and shroom_spawner.has_method("get_save_state"):
		save_data["mushrooms"] = shroom_spawner.get_save_state()

	# 13д. Глава 2 «Первый дым»: готовые блюда, грибы и восстановленные станки.
	save_data["cooking"] = CookingProgress.get_save_state()

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

static func get_format_version(data: Dictionary) -> int:
	var meta = data.get("meta", {})
	if meta is Dictionary and meta.has("format_version"):
		return int(meta["format_version"])
	return 1

## Приводит данные старых версий к текущему формату (без изменения мира).
## Новые необязательные поля v2 (machines.batch_total / batch_done / batch_to_buffer,
## секция dropped_items, секция seasons) версию не меняют: без них действуют
## значения по умолчанию.
static func _migrate_save_data(data: Dictionary, from_version: int) -> Dictionary:
	var migrated: Dictionary = data.duplicate(true)
	if from_version < 2:
		# v1 -> v2: новые секции (resources, progress, weather.timer/cycle_index,
		# machines.completed_runs/pending_outputs) необязательны; лимиты инвентаря
		# больше не берутся из файла, а пересчитываются по рюкзаку и зданиям.
		if not migrated.has("meta"):
			migrated["meta"] = {}
		migrated["meta"]["format_version"] = 2
	return migrated

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
	
	var raw_data = test_json.data
	if typeof(raw_data) != TYPE_DICTIONARY:
		push_error("SaveManager: некорректный формат данных сохранения")
		return false
	
	# Валидация ВСЕХ секций до первого изменения мира.
	if not _validate_save_data(raw_data):
		push_warning("SaveManager: некорректные поля сохранения")
		return false
	
	var format_version: int = get_format_version(raw_data)
	if format_version > SAVE_FORMAT_VERSION:
		push_warning("SaveManager: сохранение создано более новой версией игры (формат %d > %d)" % [format_version, SAVE_FORMAT_VERSION])
		return false
	var save_data: Dictionary = _migrate_save_data(raw_data, format_version)

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
		
		if p_data.has("health"):
			player.health = p_data["health"]
			if player.has_signal("health_changed"):
				player.health_changed.emit(player.health, player.max_health)
		if p_data.has("hours_without_sleep"):
			player.hours_without_sleep = p_data["hours_without_sleep"]
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
		if p_data.has("skills") and "skills" in player and player.skills and player.skills.has_method("deserialize"):
			player.skills.deserialize(p_data["skills"])
	
	var inv = null
	if player and is_instance_valid(player) and "inventory" in player:
		inv = player.get("inventory")
	if inv and is_instance_valid(inv) and save_data.has("inventory"):
		var inv_data: Dictionary = save_data["inventory"]
		if inv_data.has("items"):
			var loaded_items: Dictionary = {}
			for key in inv_data["items"]:
				loaded_items[key] = int(inv_data["items"][key])
			inv.items = loaded_items
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
		if inv_data.has("credits"):
			inv.credits = int(inv_data["credits"])
			if inv.has_signal("credits_changed"):
				inv.credits_changed.emit(inv.credits)
		if inv_data.has("tool_sharpness") and "tool_sharpness" in inv and inv_data["tool_sharpness"] is Dictionary:
			for key in inv_data["tool_sharpness"]:
				inv.tool_sharpness[str(key)] = float(inv_data["tool_sharpness"][key])
	if inv and is_instance_valid(inv):
		# Лимиты не доверяем файлу: пересчитываем по рюкзаку на поясе.
		if inv.has_method("recalculate_capacity"):
			inv.recalculate_capacity()
		# Раскладка клеток рюкзака (старые сохранения без неё — раскладка по умолчанию).
		if inv.has_method("set_slot_layout"):
			var layout: Variant = save_data["inventory"].get("slot_layout", []) if save_data.has("inventory") and save_data["inventory"] is Dictionary else []
			inv.set_slot_layout(layout if layout is Array else [])
		if inv.has_signal("inventory_updated"):
			inv.inventory_updated.emit()
	
	# 2. Суточный цикл
	var day_cycle = world.find_child("DayNightCycle", true, false)
	if save_data.has("day_night"):
		var dn_data: Dictionary = save_data["day_night"]
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
	
	# 3. Погода (set_weather может сбросить таймер — фазу цикла выставляем после)
	if save_data.has("weather"):
		var w_data: Dictionary = save_data["weather"]
		var weather_mgr = world.find_child("WeatherManager", true, false)
		if weather_mgr and is_instance_valid(weather_mgr):
			if w_data.has("current_weather") and weather_mgr.has_method("set_weather"):
				weather_mgr.set_weather(int(w_data["current_weather"]))
			if w_data.has("timer") and "_timer" in weather_mgr:
				weather_mgr._timer = float(w_data["timer"])
			if w_data.has("cycle_index") and "_cycle_index" in weather_mgr:
				var max_idx: int = 6
				if "_cycle_sequence" in weather_mgr:
					max_idx = maxi(0, weather_mgr._cycle_sequence.size() - 1)
				weather_mgr._cycle_index = clampi(int(w_data["cycle_index"]), 0, max_idx)
	
	# 3а. Сезоны и погодные события (календарь привязан к игровому дню суточного цикла)
	var season_mgr = world.find_child("SeasonManager", true, false)
	if season_mgr and is_instance_valid(season_mgr) and season_mgr.has_method("apply_save_state"):
		var s_data: Dictionary = save_data.get("seasons", {})
		if day_cycle and is_instance_valid(day_cycle) and "current_day" in day_cycle:
			s_data = s_data.duplicate(true)
			s_data["total_day"] = int(day_cycle.current_day)
		season_mgr.apply_save_state(s_data)
	elif save_data.has("seasons"):
		var s_data2: Dictionary = save_data["seasons"]
		var saved_season: String = str(s_data2.get("current_season", ""))
		if bool(s_data2.get("enabled", false)) and Seasons.ALL.has(saved_season):
			Seasons.activate(saved_season, int(s_data2.get("day_in_season", 1)))
		else:
			Seasons.disable()
	
	# 4. Здания
	var house = world.find_child("RepairableHouse", true, false)
	var storage = world.find_child("RepairableStorage", true, false)
	if save_data.has("buildings"):
		var b_data: Dictionary = save_data["buildings"]
		if house and is_instance_valid(house) and b_data.has("house_stage"):
			_restore_building_stage(house, int(b_data["house_stage"]))
		if storage and is_instance_valid(storage) and b_data.has("storage_stage"):
			_restore_building_stage(storage, int(b_data["storage_stage"]))
		# Накопленные внутри зданий материалы достройки (если сохранены).
		_restore_building_delivery(house, b_data, "house")
		_restore_building_delivery(storage, b_data, "storage")
	# Старые сейвы не содержат склада: очищаем его, а не дублируем текущие вещи.
	if storage and "storage_inventory" in storage:
		storage.storage_inventory.restore_state(save_data.get("buildings", {}).get("storage_inventory", {}))
	# Бонусы грузоподъёмности от зданий выставляются всегда (идемпотентно).
	for building in [house, storage]:
		if building and is_instance_valid(building) and building.has_method("apply_capacity_bonus"):
			building.apply_capacity_bonus(player)
	
	# 5. Энергетика
	if save_data.has("energy"):
		var en_data: Dictionary = save_data["energy"]
		var stored_val: float = float(en_data.get("stored_energy", 30.0))
		var grid = world.find_child("PowerGrid", true, false)
		if grid and is_instance_valid(grid) and "current_stored" in grid:
			grid.current_stored = stored_val
			# Источник питания (Сеть/Ветряк/Батарея); в старых сейвах — Сеть.
			if "source_mode" in grid and en_data.has("source_mode"):
				grid.source_mode = clampi(int(en_data["source_mode"]), 0, 2)
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
	
	# 8. Контракты. Старый сейв без секции не должен наследовать прогресс
	# из другой игровой сессии, так как ContractDB хранит данные статически.
	ContractDB.reset_completed()
	if save_data.has("contracts"):
		var c_data: Dictionary = save_data["contracts"]
		if c_data.has("completed") and c_data["completed"] is Dictionary:
			ContractDB.completed_contracts = c_data["completed"].duplicate(true)
	
	# 9. Прогресс финала
	if save_data.has("progress"):
		var hud = world.find_child("HUD", true, false)
		if hud and "_victory_shown" in hud:
			hud._victory_shown = bool(save_data["progress"].get("victory_shown", false))
	
	# 10. Машины (старые сохранения без этих секций продолжают загружаться)
	for state in save_data.get("machines", []):
		var machine = world.get_node_or_null(NodePath(state["path"]))
		if not machine is ProductionMachine:
			continue
		var recipe: Dictionary = RecipeDB.get_recipe(state.get("recipe_id", ""))
		if not recipe.is_empty() and recipe.get("machine", "") != machine.machine_type:
			continue
		var running: bool = not recipe.is_empty()
		machine.active_recipe = recipe
		machine.process_timer = float(state["timer"])
		machine.process_duration = float(state["duration"])
		machine.is_machine_running = running
		machine._last_user = player
		machine.completed_runs = int(state.get("completed_runs", 0))
		# Партия: без полей — одиночный запуск (как до появления партий).
		if running:
			var total: int = clampi(int(state.get("batch_total", 1)), 1, ProductionMachine.MAX_BATCH_CYCLES)
			machine.batch_cycles_total = total
			machine.batch_cycles_done = clampi(int(state.get("batch_done", 0)), 0, total - 1)
			machine.batch_to_buffer = bool(state.get("batch_to_buffer", false))
		else:
			machine.batch_cycles_total = 0
			machine.batch_cycles_done = 0
			machine.batch_to_buffer = false
		# _ready() выключает _process у нового станка. Одной записи флага
		# is_machine_running недостаточно: после загрузки цикл иначе зависает.
		machine.set_process(running)
		machine._last_emitted_progress = -1.0
		var grid = world.find_child("PowerGrid", true, false)
		if running and grid and "has_power" in grid:
			machine.power_ok = bool(grid.has_power)
		# Уровень станка — до износа: max_condition зависит от уровня.
		if machine.level_state and state.has("level"):
			machine.level_state.set_level(int(state["level"]))
			if machine.wear:
				var saved_ratio: float = machine.wear.get_ratio()
				machine.wear.max_condition = machine.level_state.get_max_condition()
				machine.wear.set_condition(saved_ratio * machine.wear.max_condition)
		# Износ и топливо (поля необязательные: старые сохранения — defaults).
		if machine.wear and state.has("wear"):
			machine.wear.set_condition(float(state["wear"]))
		if machine.has_fuel_slots and state.has("fuel_slots") and state["fuel_slots"] is Array:
			var saved_fuel: Array = state["fuel_slots"]
			machine.fuel_slots.clear()
			var slot_count: int = int(machine.fuel_slot_count) if "fuel_slot_count" in machine else ProductionMachine.FUEL_SLOTS
			for i in slot_count:
				if i < saved_fuel.size() and saved_fuel[i] is Dictionary:
					var fs: Dictionary = saved_fuel[i]
					var fid: String = str(fs.get("item_id", ""))
					var fcnt: int = clampi(int(fs.get("count", 0)), 0, ProductionMachine.FUEL_SLOT_STACK)
					if fid == "" or fcnt <= 0 or not fid in ProductionMachine.FUEL_ITEMS:
						fid = ""
						fcnt = 0
					machine.fuel_slots.append({"item_id": fid, "count": fcnt})
			machine.active_fuel_slot = -1
			machine.fuel_burn_left = maxf(0.0, float(state.get("fuel_burn_left", 0.0)))
			if machine.fuel_burn_left <= 0.0:
				machine._light_next_fuel()
		var pending: Dictionary = {}
		var saved_pending: Dictionary = state.get("pending_outputs", {})
		for item_id in saved_pending:
			if int(saved_pending[item_id]) > 0:
				pending[item_id] = int(saved_pending[item_id])
		machine.pending_outputs = pending
		# Восстановление станка (Глава 2): без поля считаем станок готовым —
		# старые сохранения не знали о разрушенных станках.
		if state.has("rebuilt"):
			machine.set_rebuilt(bool(state["rebuilt"]))
		# Компоненты, накопленные внутри станка для текущей работы (порционная
		# достройка): { kind: { item_id: количество } } + кредиты по работам.
		var saved_stash: Dictionary = state.get("job_stash", {})
		if saved_stash is Dictionary:
			for kind in machine.job_stash.keys():
				var kind_stash: Dictionary = saved_stash.get(str(kind), {})
				var clean: Dictionary = {}
				if kind_stash is Dictionary:
					for item_id in kind_stash.keys():
						var n: int = int(kind_stash[item_id])
						if n > 0:
							clean[str(item_id)] = n
				machine.job_stash[str(kind)] = clean
			var saved_credits: Dictionary = state.get("job_credits", {})
			if saved_credits is Dictionary:
				for kind in machine.job_credits.keys():
					machine.job_credits[str(kind)] = maxi(0, int(saved_credits.get(str(kind), 0)))
		if machine is CampfireScript:
			machine.has_burned = bool(state.get("fire_has_burned", false)) or machine.is_lit()
			machine.refresh_fire_visuals(true)
		if machine.visual_node:
			machine.visual_node.position = machine._original_pos
		if machine.has_signal("outputs_changed"):
			machine.outputs_changed.emit()
	
	# 11. Торговцы
	for path in save_data.get("traders", {}):
		var trader = world.get_node_or_null(NodePath(path))
		if trader and "starter_seeds_given" in trader:
			trader.starter_seeds_given = save_data["traders"][path]
	
	# 12. Ресурсные узлы (деревья, камни и т.п.)
	for r_state in save_data.get("resources", []):
		var res_node = world.get_node_or_null(NodePath(r_state["path"]))
		if not res_node is ResourceNodeScript:
			continue
		var depleted: bool = bool(r_state.get("is_depleted", false))
		if bool(res_node.is_depleted) != depleted:
			res_node._set_depleted(depleted)
		res_node.respawn_timer = float(r_state.get("respawn_timer", 0.0))
		res_node.current_hits = clampi(int(r_state.get("current_hits", res_node.current_hits)), 0, maxi(0, int(res_node.max_hits)))
		# Посаженный на пень саженец (в старых сохранениях полей нет).
		res_node.is_growing = false
		res_node.growth_progress_hours = 0.0
		if depleted and bool(r_state.get("is_growing", false)) and res_node.requires_planting:
			res_node.is_growing = true
			if res_node.depleted_visual_node:
				res_node.depleted_visual_node.visible = false
			if res_node.visual_node:
				res_node.visual_node.visible = true
			res_node.advance_growth(clampf(float(r_state.get("growth_hours", 0.0)), 0.0, float(res_node.growth_hours)))
	
	# 13. Жилы: выкопанные блоки и найденные ресурсы (в старых сохранениях секции нет).
	for dep_state in save_data.get("deposits", []):
		var deposit = world.get_node_or_null(NodePath(dep_state["path"]))
		if deposit is VoxelDepositScript:
			deposit.apply_save_state(dep_state)

	# 13в. Делянки: текущие убираются, сохранённые создаются заново (в старых сохранениях секции нет).
	if world.is_inside_tree():
		for f in world.get_tree().get_nodes_in_group("farm_fields"):
			if world.is_ancestor_of(f):
				f.get_parent().remove_child(f)
				f.queue_free()
	if save_data.get("farm_fields") is Array and not save_data["farm_fields"].is_empty():
		var fields_root: Node = world.get_node_or_null("FarmFields")
		if fields_root == null:
			fields_root = Node3D.new()
			fields_root.name = "FarmFields"
			world.add_child(fields_root)
		for f_state in save_data["farm_fields"]:
			var field = FarmFieldScript.spawn(fields_root, Vector3(float(f_state["x"]), 0.0, float(f_state["z"])), int(f_state["w"]), int(f_state["h"]))
			field.apply_save_state(f_state)

	# 13г. Фруктовые деревья (в старых сохранениях секции нет — остаются стартовые).
	if save_data.has("fruit_trees") and save_data["fruit_trees"] is Array:
		if world.is_inside_tree():
			for ft in world.get_tree().get_nodes_in_group("fruit_trees"):
				if world.is_ancestor_of(ft):
					ft.get_parent().remove_child(ft)
					ft.queue_free()
		var trees_root: Node = world.get_node_or_null("FruitTrees")
		if trees_root == null:
			trees_root = Node3D.new()
			trees_root.name = "FruitTrees"
			world.add_child(trees_root)
		for t_state in save_data["fruit_trees"]:
			var tree = FruitTreeScript.new()
			trees_root.add_child(tree)
			tree.apply_save_state(t_state)

	# 13б. Ягодные кусты (в старых сохранениях секции нет — остаётся новая раскладка).
	if save_data.get("berry_bushes") is Dictionary:
		var bush_spawner = world.find_child("BerryBushes", true, false)
		if bush_spawner and bush_spawner.has_method("apply_save_state"):
			bush_spawner.apply_save_state(save_data["berry_bushes"])

	# 13в. Лесные грибы (в старых сохранениях секции нет — остаётся новая раскладка).
	if save_data.get("mushrooms") is Dictionary:
		var shroom_spawner = world.find_child("MushroomPatches", true, false)
		if shroom_spawner and shroom_spawner.has_method("apply_save_state"):
			shroom_spawner.apply_save_state(save_data["mushrooms"])

	# 13г. Глава 2 «Первый дым»: блюда, грибы и восстановленные станки.
	CookingProgress.apply_save_state(save_data.get("cooking", {}) if save_data.get("cooking") is Dictionary else {})

	# 14. Выброшенные предметы: текущие кучки убираются, сохранённые создаются заново.
	# В старых сохранениях секции нет — тогда кучки тоже убираются (их не было).
	for node in world.find_children("*", "", true, false):
		if node.is_in_group(DroppedItemScript.GROUP) and node.has_method("consume"):
			node.consume()
	for d_state in save_data.get("dropped_items", []):
		var pos := Vector3(float(d_state.get("x", 0.0)), float(d_state.get("y", 0.0)), float(d_state.get("z", 0.0)))
		DroppedItemScript.spawn(world, str(d_state["item_id"]), int(d_state["amount"]), pos)

	if player and player.has_method("notify"):
		player.notify("📂 Игра успешно загружена!")
	
	return true

static func _restore_building_stage(building: Node, stage: int) -> void:
	var max_s: int = int(building.max_stage) if "max_stage" in building else stage
	building.current_stage = clampi(stage, 0, max_s)
	if building.has_method("_update_visuals"):
		building._update_visuals()
	if building.has_method("_update_prompt_text"):
		building._update_prompt_text()

## Накопленные внутри здания материалы/кредиты следующей стадии (достройка
## за несколько подходов). Ключ префикса: "house" / "storage".
static func _restore_building_delivery(building: Node, b_data: Dictionary, key: String) -> void:
	if building == null or not is_instance_valid(building) or not ("delivered" in building):
		return
	building.delivered.clear()
	building.delivered_credits = 0
	var saved: Dictionary = b_data.get(key + "_delivered", {})
	if saved is Dictionary:
		for item_id in saved.keys():
			var n: int = maxi(0, int(saved[item_id]))
			if n > 0:
				building.delivered[str(item_id)] = n
	building.delivered_credits = maxi(0, int(b_data.get(key + "_delivered_credits", 0)))

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
	for section in ["meta", "player", "inventory", "day_night", "weather", "seasons", "buildings", "energy", "water", "contracts", "traders", "progress"]:
		if data.has(section) and not data[section] is Dictionary:
			return false
	var meta: Dictionary = data.get("meta", {})
	if meta.has("format_version") and not _is_integer(meta["format_version"], 1.0):
		return false
	var p: Dictionary = data.get("player", {})
	if p.has("character_class"):
		if not p["character_class"] is String or CharacterClassDB.get_class_data(p["character_class"]).is_empty():
			return false
	for key in ["energy", "thirst", "hunger", "wetness", "health", "hours_without_sleep"]:
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
	if inv.has("slot_layout"):
		if not inv["slot_layout"] is Array or inv["slot_layout"].size() > 512:
			return false
		for cell in inv["slot_layout"]:
			if not cell is String:
				return false
	if inv.has("tool_sharpness"):
		if not inv["tool_sharpness"] is Dictionary:
			return false
		for key in inv["tool_sharpness"]:
			if not _is_number(inv["tool_sharpness"][key], 0.0, 100.0):
				return false
	var dn: Dictionary = data.get("day_night", {})
	if dn.has("current_day") and not _is_integer(dn["current_day"], 1.0):
		return false
	for key in ["current_hour", "time_of_day"]:
		if dn.has(key) and not _is_number(dn[key], 0.0, 24.0):
			return false
	var weather: Dictionary = data.get("weather", {})
	if weather.has("current_weather") and not _is_integer(weather["current_weather"], 0.0, 4.0):
		return false
	if weather.has("timer") and not _is_number(weather["timer"], 0.0):
		return false
	if weather.has("cycle_index") and not _is_integer(weather["cycle_index"], 0.0, 6.0):
		return false
	if data.has("seasons") and not SeasonManagerScript.is_valid_save_state(data["seasons"]):
		return false
	if data.has("cooking") and not CookingProgress.is_valid_save_state(data["cooking"]):
		return false
	if data.has("mushrooms") and not MushroomSpawnerScript.is_valid_save_state(data["mushrooms"]):
		return false
	var buildings: Dictionary = data.get("buildings", {})
	for key in ["house_stage", "storage_stage"]:
		if buildings.has(key) and not _is_integer(buildings[key], 0.0, 3.0):
			return false
	for key in ["house_delivered_credits", "storage_delivered_credits"]:
		if buildings.has(key) and not _is_integer(buildings[key]):
			return false
	for key in ["house_delivered", "storage_delivered"]:
		if buildings.has(key):
			if not buildings[key] is Dictionary:
				return false
			for item_id in buildings[key]:
				if ItemDB.get_item(str(item_id)).is_empty() or not _is_integer(buildings[key][item_id]):
					return false
	if buildings.has("storage_inventory") and not WarehouseInventory.is_valid_state(buildings["storage_inventory"]):
		return false
	var energy: Dictionary = data.get("energy", {})
	if energy.has("stored_energy") and not _is_number(energy["stored_energy"], 0.0):
		return false
	if energy.has("source_mode") and not _is_integer(energy["source_mode"], 0.0, 2.0):
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
			if plot.get("crop_type", "") != "" and not CropDB.has_crop(plot.get("crop_type", "")):
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
	var progress: Dictionary = data.get("progress", {})
	if progress.has("victory_shown") and not progress["victory_shown"] is bool:
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
			if state.has("completed_runs") and not _is_integer(state["completed_runs"]):
				return false
			if state.has("pending_outputs"):
				if not state["pending_outputs"] is Dictionary:
					return false
				for item_id in state["pending_outputs"]:
					if ItemDB.get_item(item_id).is_empty() or not _is_integer(state["pending_outputs"][item_id]):
						return false
			if state.has("batch_total") and not _is_integer(state["batch_total"], 0.0, float(ProductionMachine.MAX_BATCH_CYCLES)):
				return false
			if state.has("batch_done") and not _is_integer(state["batch_done"], 0.0, float(ProductionMachine.MAX_BATCH_CYCLES)):
				return false
			if state.has("batch_to_buffer") and not state["batch_to_buffer"] is bool:
				return false
			if state.has("level") and not _is_integer(state["level"], 1.0, 3.0):
				return false
			if state.has("wear") and not _is_number(state["wear"], 0.0, 150.0):
				return false
			if state.has("fuel_slots"):
				if not state["fuel_slots"] is Array or state["fuel_slots"].size() > 8:
					return false
				for fs in state["fuel_slots"]:
					if not fs is Dictionary:
						return false
					var fid = fs.get("item_id", "")
					if not fid is String or (fid != "" and not fid in ProductionMachine.FUEL_ITEMS):
						return false
					if not _is_integer(fs.get("count", 0), 0.0, float(ProductionMachine.FUEL_SLOT_STACK)):
						return false
			if state.has("fuel_burn_left") and not _is_number(state["fuel_burn_left"], 0.0, 10000.0):
				return false
			if state.has("fire_has_burned") and not state["fire_has_burned"] is bool:
				return false
			if state.has("rebuilt") and not state["rebuilt"] is bool:
				return false
			# Компоненты, накопленные внутри станка для текущей работы.
			if state.has("job_stash"):
				if not state["job_stash"] is Dictionary:
					return false
				for kind in state["job_stash"]:
					var kind_stash: Variant = state["job_stash"][kind]
					if not kind_stash is Dictionary:
						return false
					for item_id in kind_stash:
						if ItemDB.get_item(str(item_id)).is_empty() or not _is_integer(kind_stash[item_id]):
							return false
			if state.has("job_credits"):
				if not state["job_credits"] is Dictionary:
					return false
				for kind in state["job_credits"]:
					if not _is_integer(state["job_credits"][kind]):
						return false
	for path in data.get("traders", {}):
		if not _is_relative_path(path) or not data["traders"][path] is bool:
			return false
	if data.has("resources"):
		if not data["resources"] is Array:
			return false
		for r_state in data["resources"]:
			if not r_state is Dictionary or not _is_relative_path(r_state.get("path", "")):
				return false
			if r_state.has("is_depleted") and not r_state["is_depleted"] is bool:
				return false
			if r_state.has("respawn_timer") and not _is_number(r_state["respawn_timer"], 0.0):
				return false
			if r_state.has("current_hits") and not _is_integer(r_state["current_hits"]):
				return false
			if r_state.has("is_growing") and not r_state["is_growing"] is bool:
				return false
			if r_state.has("growth_hours") and not _is_number(r_state["growth_hours"], 0.0):
				return false
	if data.has("deposits"):
		if not data["deposits"] is Array:
			return false
		for dep_state in data["deposits"]:
			if not dep_state is Dictionary or not _is_relative_path(dep_state.get("path", "")):
				return false
			if not VoxelDepositScript.is_valid_save_state(dep_state):
				return false
	if data.has("farm_fields"):
		if not data["farm_fields"] is Array:
			return false
		for f_state in data["farm_fields"]:
			if not FarmFieldScript.is_valid_save_state(f_state):
				return false
	if data.has("fruit_trees"):
		if not data["fruit_trees"] is Array:
			return false
		for t_state in data["fruit_trees"]:
			if not t_state is Dictionary:
				return false
			var t_type = t_state.get("type", "")
			if not t_type is String or not FruitTreeScript.CONFIGS.has(t_type):
				return false
			if t_state.has("stage") and not _is_integer(t_state["stage"], 0.0, 2.0):
				return false
			if not t_state.has("pos") or not t_state["pos"] is Array or t_state["pos"].size() < 3:
				return false
			for val in t_state["pos"]:
				if not _is_number(val):
					return false
	if data.has("berry_bushes"):
		var bb = data["berry_bushes"]
		if not bb is Dictionary or not _is_integer(bb.get("seed", 0), 0.0, 2147483647.0) or not bb.get("bushes", []) is Array:
			return false
		for b_state in bb.get("bushes", []):
			if not b_state is Dictionary:
				return false
			if b_state.has("has_berries") and not b_state["has_berries"] is bool:
				return false
			if b_state.has("regrow_progress") and not _is_number(b_state["regrow_progress"], 0.0):
				return false
	if data.has("dropped_items"):
		if not data["dropped_items"] is Array:
			return false
		for d_state in data["dropped_items"]:
			if not d_state is Dictionary:
				return false
			var d_id = d_state.get("item_id", "")
			if not d_id is String or ItemDB.get_item(d_id).is_empty():
				return false
			if not _is_integer(d_state.get("amount"), 1.0):
				return false
			for axis in ["x", "y", "z"]:
				if not _is_number(d_state.get(axis)):
					return false
	return true

static func _is_relative_path(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.begins_with("/") and not ".." in value.split("/") and not ":" in value
