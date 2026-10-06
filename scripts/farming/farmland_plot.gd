class_name FarmlandPlot
extends "res://scripts/interaction/interactable.gd"

## Интерактивная грядка / Участок фермы (Разделы 17, 31, 33 дизайн-документа)
## Поддерживает вскопку лопатой, посадку культур, полив, внесение удобрений и сбор урожая

const ItemDB = preload("res://scripts/inventory/item_db.gd")

signal plot_tilled()
signal crop_planted(crop_type: String)
signal plot_watered(current_moisture: float)
signal fertilizer_applied()
signal crop_ripe(crop_type: String)
signal crop_harvested(crop_type: String, yield_count: int, seed_count: int)

enum SoilState {
	UNTILLED, # Заросшая сорняками целина
	TILLED    # Вскопанная пахотная земля
}

@export var initial_state: SoilState = SoilState.UNTILLED
@export var max_moisture: float = 100.0
@export var moisture_decay_rate: float = 0.6
@export var growth_time_total: float = 40.0

var soil_state: SoilState = SoilState.UNTILLED
var moisture: float = 0.0
var is_fertilized: bool = false
var crop_type: String = "" # "carrot", "potato", "wheat"
var growth_progress: float = 0.0 # 0.0 - 100.0
var is_ripe: bool = false

# Визуальные ссылки
@export var visuals_root: Node3D
@export var untilled_mesh: MeshInstance3D
@export var tilled_mesh: MeshInstance3D
@export var crops_sprout: Node3D
@export var crops_growing: Node3D
@export var crops_mature: Node3D
@export var harvest_light: OmniLight3D

# Материалы для почвы
var _mat_untilled: StandardMaterial3D = null
var _mat_tilled_dry: StandardMaterial3D = null
var _mat_tilled_wet: StandardMaterial3D = null

func _ready() -> void:
	super._ready()
	add_to_group("farmland_plots")
	object_name = "Грядка"
	prompt_action = "Осмотреть"
	soil_state = initial_state

	_init_materials()
	_resolve_node_references()
	_update_visuals()

func _resolve_node_references() -> void:
	if not visuals_root:
		visuals_root = get_node_or_null("Visuals")
	if visuals_root:
		if not untilled_mesh:
			untilled_mesh = visuals_root.get_node_or_null("UntilledBed")
		if not tilled_mesh:
			tilled_mesh = visuals_root.get_node_or_null("TilledBed")
		if not crops_sprout:
			crops_sprout = visuals_root.get_node_or_null("Crops/Sprouts")
		if not crops_growing:
			crops_growing = visuals_root.get_node_or_null("Crops/Growing")
		if not crops_mature:
			crops_mature = visuals_root.get_node_or_null("Crops/Mature")
		if not harvest_light:
			harvest_light = visuals_root.get_node_or_null("HarvestLight")

func _init_materials() -> void:
	# Сухая целина
	_mat_untilled = StandardMaterial3D.new()
	_mat_untilled.albedo_color = Color(0.42, 0.36, 0.28) # серо-бурый грунт с остатками сорняков
	_mat_untilled.roughness = 0.95

	# Вскопанная сухая почва
	_mat_tilled_dry = StandardMaterial3D.new()
	_mat_tilled_dry.albedo_color = Color(0.48, 0.33, 0.20) # теплый рыхлый суглинок
	_mat_tilled_dry.roughness = 0.9

	# Напитанный влагой плодородный чернозем
	_mat_tilled_wet = StandardMaterial3D.new()
	_mat_tilled_wet.albedo_color = Color(0.20, 0.13, 0.08) # насыщенный темный гумус
	_mat_tilled_wet.roughness = 0.55

func _process(delta: float) -> void:
	# Высыхание почвы
	if moisture > 0.0:
		moisture = max(0.0, moisture - moisture_decay_rate * delta)
		_update_soil_material()

	# Развитие культуры
	if crop_type != "" and not is_ripe:
		var speed_mult: float = 1.0
		if moisture <= 5.0:
			speed_mult = 0.15 # без полива культура едва развивается
		
		if is_fertilized:
			speed_mult *= 2.0 # удобрение ускоряет вегетацию вдвое
		
		# Бонус специализации Фермер (Этап 12)
		var player_node: Node = get_tree().root.find_child("Player", true, false)
		if player_node and "character_class" in player_node and player_node.character_class == "farmer":
			speed_mult *= 1.35
		
		var step: float = (100.0 / growth_time_total) * speed_mult * delta
		growth_progress = min(100.0, growth_progress + step)
		
		if growth_progress >= 100.0:
			growth_progress = 100.0
			is_ripe = true
			crop_ripe.emit(crop_type)
		
		_update_crop_visuals()

func get_prompt() -> String:
	if soil_state == SoilState.UNTILLED:
		return "[E] Вскопать грядку (Нужна лопата)"
	
	if crop_type == "":
		if moisture > 10.0:
			return "[E] Засеять семена (Влажность: %d%%)" % int(moisture)
		else:
			return "[E] Засеять семена / Полить (Сухая земля)"
	
	var c_name: String = ItemDB.get_item_name(crop_type)
	if is_ripe:
		return "[E] Собрать урожай: %s (Созрело!)" % c_name
	
	var fert_txt: String = " (Удобрено)" if is_fertilized else ""
	return "[E] %s: Рост %d%% | Влажность %d%%%s" % [c_name, int(growth_progress), int(moisture), fert_txt]

func _on_interacted(player: Node) -> void:
	# 1. Если земля не вскопана — требуем лопату
	if soil_state == SoilState.UNTILLED:
		till_soil(player)
		return
	
	# 2. Если земля вскопана и пуста — пытаемся посадить семена или полить
	if crop_type == "":
		var inv = player.get("inventory") if player else null
		if not inv:
			return
		
		# Ищем семена в инвентаре
		var seed_to_plant: String = ""
		for s_id in ["seeds_carrot", "seeds_potato", "seeds_wheat"]:
			if inv.get_item_count(s_id) > 0:
				seed_to_plant = s_id
				break
		
		if seed_to_plant != "":
			plant_crop(seed_to_plant, player)
			return
		
		# Если семян нет, проверяем воду для предварительного полива
		if inv.get_item_count("water") > 0 or inv.get_item_count("clean_water") > 0:
			if moisture < 85.0:
				water_plot(50.0, player)
				return
		
		if player.has_method("notify"):
			player.notify("🌱 Грядка готова к посеву. Нужны семена моркови, картофеля или пшеницы!")
		return
	
	# 3. Если созрел урожай — собираем
	if is_ripe:
		harvest_crop(player)
		return
	
	# 4. Если культура растет — проверяем полив или удобрение
	var inv = player.get("inventory") if player else null
	if inv:
		if (inv.get_item_count("water") > 0 or inv.get_item_count("clean_water") > 0) and moisture < 75.0:
			water_plot(50.0, player)
			return
		
		if inv.get_item_count("fertilizer") > 0 and not is_fertilized:
			apply_fertilizer(player)
			return
	
	var c_name: String = ItemDB.get_item_name(crop_type)
	if player.has_method("notify"):
		var moist_status: String = "земля влажная" if moisture > 15.0 else "требуется полив!"
		player.notify("🌱 %s растет (%d%%). Почва: %d%% (%s)." % [c_name, int(growth_progress), int(moisture), moist_status])

func till_soil(player: Node) -> bool:
	var inv = player.get("inventory") if player else null
	var has_shovel: bool = false
	var shovel_level: int = 1
	if inv:
		if inv.has_method("is_tool_equipped") and inv.is_tool_equipped("shovel"):
			has_shovel = true
		elif inv.equipped_tool in ["shovel", "iron_shovel"] or inv.tools.has("shovel") or inv.tools.has("iron_shovel") or inv.get_item_count("shovel") > 0 or inv.get_item_count("iron_shovel") > 0:
			has_shovel = true
		if inv.has_method("get_tool_level"):
			shovel_level = inv.get_tool_level("shovel")
	
	if not has_shovel:
		if player and player.has_method("notify"):
			player.notify("⚠️ Для вскопки земли нужна лопата!")
		return false
	
	var energy_needed: float = 6.0
	if shovel_level >= 2:
		energy_needed = 3.0
	
	if player and player.has_method("consume_energy"):
		player.consume_energy(energy_needed)
	
	soil_state = SoilState.TILLED
	plot_tilled.emit()
	_update_visuals()
	_play_dig_bounce()
	
	if player and player.has_method("notify"):
		var shovel_info: String = " (легкая работа железной лопатой -50% сил)" if shovel_level >= 2 else ""
		player.notify("🌾 Вы вскопали грядку и подготовили борозды к посеву!%s" % shovel_info)
	return true

func plant_crop(seed_id: String, player: Node = null) -> bool:
	if soil_state != SoilState.TILLED or crop_type != "":
		return false
	
	var target_crop: String = ItemDB.get_crop_type(seed_id)
	if target_crop == "":
		return false
	
	if player:
		var inv = player.get("inventory") if "inventory" in player else null
		if inv:
			if inv.get_item_count(seed_id) <= 0:
				return false
			inv.remove_item(seed_id, 1)
	
	crop_type = target_crop
	growth_progress = 0.0
	is_ripe = false
	is_fertilized = false
	
	crop_planted.emit(crop_type)
	_update_visuals()
	_play_plant_pop()
	
	if player and player.has_method("notify"):
		var c_name: String = ItemDB.get_item_name(crop_type)
		player.notify("🌱 Посажена культура: %s! Регулярно поливайте для быстрого роста." % c_name)
	return true

func water_plot(amount: float = 50.0, player: Node = null) -> bool:
	if soil_state != SoilState.TILLED:
		return false
	
	if player:
		var inv = player.get("inventory") if "inventory" in player else null
		if inv:
			if inv.get_item_count("clean_water") > 0:
				inv.remove_item("clean_water", 1)
			elif inv.get_item_count("water") > 0:
				inv.remove_item("water", 1)
			else:
				if player.has_method("notify"):
					player.notify("ℹ️ У вас нет воды для полива!")
				return false
	
	moisture = min(max_moisture, moisture + amount)
	plot_watered.emit(moisture)
	_update_soil_material()
	_play_water_ripple()
	
	if player and player.has_method("notify"):
		var c_name: String = ItemDB.get_item_name(crop_type) if crop_type != "" else "грядка"
		player.notify("💧 Полив: %s увлажнена (+%d%%, текущая влажность %d%%)!" % [c_name, int(amount), int(moisture)])
	return true

func apply_fertilizer(player: Node = null) -> bool:
	if is_fertilized or crop_type == "":
		return false
	
	if player:
		var inv = player.get("inventory") if "inventory" in player else null
		if inv:
			if inv.get_item_count("fertilizer") <= 0:
				return false
			inv.remove_item("fertilizer", 1)
	
	is_fertilized = true
	fertilizer_applied.emit()
	
	if player and player.has_method("notify"):
		player.notify("✨ Внесено био-удобрение! Скорость созревания увеличена вдвое.")
	return true

func harvest_crop(player: Node) -> Dictionary:
	var result: Dictionary = {
		"crop": crop_type,
		"yield": 0,
		"seeds": 0
	}
	
	if not is_ripe or crop_type == "":
		return result
	
	var base_yield: int = 3
	if is_fertilized:
		base_yield += 1 # бонус удобрения
	
	var seed_yield: int = 2 # возврат семян для зацикленного воспроизводства
	
	result["yield"] = base_yield
	result["seeds"] = seed_yield
	
	var inv = player.get("inventory") if player else null
	if inv:
		inv.add_item(crop_type, base_yield)
		inv.add_item("seeds_" + crop_type, seed_yield)
	
	var harvested_crop_name: String = ItemDB.get_item_name(crop_type)
	crop_harvested.emit(crop_type, base_yield, seed_yield)
	
	if player and player.has_method("notify"):
		player.notify("🧺 Собран отличный урожай: %s x%d, семена x%d!" % [harvested_crop_name, base_yield, seed_yield])
	
	# Сброс грядки (остается вскопанной и сохраняет часть влаги)
	crop_type = ""
	growth_progress = 0.0
	is_ripe = false
	is_fertilized = false
	_update_visuals()
	
	return result

func force_grow(amount: float) -> void:
	if crop_type == "" or is_ripe:
		return
	growth_progress = min(100.0, growth_progress + amount)
	if growth_progress >= 100.0:
		is_ripe = true
		crop_ripe.emit(crop_type)
	_update_crop_visuals()

func skip_growth_to_ripe() -> void:
	if crop_type == "":
		return
	growth_progress = 100.0
	is_ripe = true
	crop_ripe.emit(crop_type)
	_update_crop_visuals()

func _update_visuals() -> void:
	if untilled_mesh:
		untilled_mesh.visible = (soil_state == SoilState.UNTILLED)
	if tilled_mesh:
		tilled_mesh.visible = (soil_state == SoilState.TILLED)
	
	_update_soil_material()
	_update_crop_visuals()

func _update_soil_material() -> void:
	if not tilled_mesh:
		return
	if moisture > 10.0:
		tilled_mesh.material_override = _mat_tilled_wet
	else:
		tilled_mesh.material_override = _mat_tilled_dry

func _update_crop_visuals() -> void:
	if not crops_sprout and not crops_growing and not crops_mature:
		return
	
	var has_crop: bool = (crop_type != "")
	var is_sprout: bool = has_crop and (growth_progress < 35.0)
	var is_vegetative: bool = has_crop and (growth_progress >= 35.0 and growth_progress < 100.0)
	var is_full_mature: bool = has_crop and (growth_progress >= 100.0)
	
	if crops_sprout:
		crops_sprout.visible = is_sprout
	if crops_growing:
		crops_growing.visible = is_vegetative
	if crops_mature:
		crops_mature.visible = is_full_mature
		_apply_crop_species_visuals(crops_mature)
	
	if harvest_light:
		harvest_light.visible = is_full_mature

func _apply_crop_species_visuals(mature_node: Node3D) -> void:
	if not mature_node:
		return
	for child in mature_node.get_children():
		var c_name: String = child.name.to_lower()
		if crop_type == "carrot":
			child.visible = c_name.contains("carrot") or c_name.contains("orange")
		elif crop_type == "potato":
			child.visible = c_name.contains("potato") or c_name.contains("bush")
		elif crop_type == "wheat":
			child.visible = c_name.contains("wheat") or c_name.contains("gold")
		else:
			child.visible = true

func _play_dig_bounce() -> void:
	if not visuals_root:
		return
	var tw: Tween = create_tween()
	var orig_y: float = visuals_root.position.y
	tw.tween_property(visuals_root, "position:y", orig_y + 0.08, 0.08)
	tw.tween_property(visuals_root, "position:y", orig_y, 0.12)

func _play_plant_pop() -> void:
	if not visuals_root:
		return
	var tw: Tween = create_tween()
	var orig_s: Vector3 = visuals_root.scale
	tw.tween_property(visuals_root, "scale", orig_s * 1.05, 0.09)
	tw.tween_property(visuals_root, "scale", orig_s, 0.11)

func _play_water_ripple() -> void:
	if not tilled_mesh:
		return
	var tw: Tween = create_tween()
	tw.tween_property(tilled_mesh, "scale:y", 1.15, 0.1)
	tw.tween_property(tilled_mesh, "scale:y", 1.0, 0.15)
