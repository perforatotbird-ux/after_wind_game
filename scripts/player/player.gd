extends CharacterBody3D

signal focused_interactable_changed(interactable: Area3D)
signal notification_received(text: String)
signal energy_changed(current: float, max_val: float)
signal thirst_changed(current: float, max_val: float)
signal hunger_changed(current: float, max_val: float)
signal wetness_changed(current: float, max_val: float)
signal inventory_toggle_requested()
signal class_select_toggle_requested()
signal character_class_changed(class_id: String, c_name: String)

@export_group("Movement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.2
@export var acceleration: float = 12.0
@export var rotation_speed: float = 10.0

@export_group("Stats")
@export var max_energy: float = 100.0
@export var energy_recovery_rate: float = 2.0
@export var max_thirst: float = 100.0
@export var thirst_decay_rate: float = 0.2
@export var max_hunger: float = 100.0
@export var hunger_decay_rate: float = 0.15
@export var max_wetness: float = 100.0

@export_group("Specialization")
@export var character_class: String = "miner"

const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")

# Must match the authored Blender mine action (60 FPS, contact on frame 10).
const STRIKE_CONTACT_TIME: float = 0.15
const STRIKE_BUFFER_WINDOW: float = 0.12
const STRIKE_HIT_PAUSE: float = 0.025

@export_group("References")
@onready var visual_root: Node3D = $Visuals
@onready var interaction_detector: Area3D = $InteractionDetector
@onready var inventory: Node = $Inventory

var energy: float = 100.0
var thirst: float = 100.0
var hunger: float = 100.0
var wetness: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var nearby_interactables: Array[Area3D] = []
var current_interactable: Area3D = null

# Анимации и визуальные элементы героя (Blender MCP Stardew Protagonist)
var anim_player: AnimationPlayer = null
var equipped_pickaxe_mesh: Node3D = null
var sun_hat_mesh: Node3D = null
var current_anim: String = ""
var is_mining: bool = false
var _strike_elapsed: float = 0.0
var _strike_duration: float = 0.42
var _strike_target: Area3D = null
var _strike_impacted: bool = false
var _strike_buffered: bool = false
var _strike_held: bool = false
var _strike_pause_remaining: float = 0.0
var _hud: Node = null
var _day_cycle: Node = null
var _weather_mgr: Node = null
var _house: Node = null
var _smelter: Node = null

func _ready() -> void:
	if not inventory:
		# На случай если нода не добавлена в сцену явно
		inventory = InventoryScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	
	if interaction_detector:
		interaction_detector.area_entered.connect(_on_interaction_area_entered)
		interaction_detector.area_exited.connect(_on_interaction_area_exited)
	
	# Инициализация модели персонажа и анимаций
	anim_player = find_child("AnimationPlayer", true, false)
	equipped_pickaxe_mesh = find_child("Equipped_Pickaxe", true, false)
	sun_hat_mesh = find_child("Sun_Hat", true, false)
	if equipped_pickaxe_mesh:
		# Кирка появляется только в момент нажатия кнопки удара
		equipped_pickaxe_mesh.visible = false
	if anim_player:
		for a_name in ["idle", "walk", "run"]:
			if anim_player.has_animation(a_name):
				anim_player.get_animation(a_name).loop_mode = Animation.LOOP_LINEAR
		play_character_anim("idle")
	
	if inventory and inventory.has_signal("tool_changed"):
		inventory.tool_changed.connect(_on_inventory_tool_changed)
	
	energy = max_energy
	thirst = max_thirst
	hunger = max_hunger
	wetness = 0.0
	energy_changed.emit(energy, max_energy)
	thirst_changed.emit(thirst, max_thirst)
	hunger_changed.emit(hunger, max_hunger)
	wetness_changed.emit(wetness, max_wetness)

func _process(delta: float) -> void:
	# Render-frame clock: no physics-tick input delay or anonymous finish timers.
	_update_strike(delta)

func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_energy_regen(delta)
	_handle_thirst(delta)
	_handle_hunger(delta)
	_handle_wetness(delta)
	_update_best_interactable()
	_handle_interaction_input()
	move_and_slide()
	_update_character_animation()
	_check_bounds()

func _input(event: InputEvent) -> void:
	# Release must clear repetition even when a UI control consumes the event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_strike_held = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_strike_held = false
		_strike_buffered = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_gameplay_blocked():
			return
		_strike_held = true
		trigger_tool_strike()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		if not _is_gameplay_blocked():
			_update_best_interactable()
			if is_instance_valid(current_interactable):
				if _is_mining_resource(current_interactable):
					trigger_tool_strike()
				else:
					current_interactable.interact(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				equip_slot(0)
			KEY_2:
				equip_slot(1)
			KEY_3:
				equip_slot(2)
			KEY_4:
				equip_slot(3)
			KEY_5:
				equip_slot(4)
			KEY_U:
				drink_from_inventory()
			KEY_Y:
				eat_from_inventory()
			KEY_TAB, KEY_I:
				inventory_toggle_requested.emit()
			KEY_C:
				class_select_toggle_requested.emit()
			KEY_F5:
				quick_save()
			KEY_F9:
				quick_load()

func set_character_class(new_class_id: String, grant_starting_bonus: bool = false) -> bool:
	var c_data: Dictionary = CharacterClassDB.get_class_data(new_class_id)
	if c_data.is_empty():
		return false
	character_class = new_class_id
	var c_name: String = c_data.get("name", new_class_id)
	var c_icon: String = c_data.get("icon", "👤")
	
	if grant_starting_bonus and inventory:
		var items: Dictionary = c_data.get("starting_items", {})
		for it_id in items.keys():
			inventory.add_item(it_id, items[it_id])
		var creds: int = c_data.get("starting_credits", 0)
		if creds > 0:
			inventory.add_credits(creds)
	
	character_class_changed.emit(character_class, c_name)
	notify("%s Выбрана специализация: %s (%s)!" % [c_icon, c_name, c_data.get("title", "")])
	return true

func quick_save() -> bool:
	var world = get_tree().current_scene if get_tree().current_scene else (get_tree().root.find_child("World", true, false) if get_tree().root else null)
	if world:
		return SaveManager.save_game(world)
	return false

func quick_load() -> bool:
	var world = get_tree().current_scene if get_tree().current_scene else (get_tree().root.find_child("World", true, false) if get_tree().root else null)
	if world:
		return SaveManager.load_game(world)
	return false

func equip_slot(slot_index: int) -> void:
	if inventory:
		inventory.equip_slot(slot_index)
		# Обновляем подсказку текущего интерактивного объекта
		if current_interactable:
			focused_interactable_changed.emit(current_interactable)

func get_speed_multiplier() -> float:
	var e_mult: float = 1.0
	if energy >= 50.0:
		e_mult = 1.0
	elif energy >= 20.0:
		e_mult = 0.88
	elif energy > 0.0:
		e_mult = 0.70
	else:
		e_mult = 0.50

	var t_mult: float = 1.0
	if thirst >= 40.0:
		t_mult = 1.0
	elif thirst >= 15.0:
		t_mult = 0.88
	elif thirst > 0.0:
		t_mult = 0.72
	else:
		t_mult = 0.55

	var h_mult: float = 1.0
	if hunger >= 40.0:
		h_mult = 1.0
	elif hunger >= 15.0:
		h_mult = 0.90
	elif hunger > 0.0:
		h_mult = 0.75
	else:
		h_mult = 0.60

	var w_mult: float = 1.0
	if wetness >= 80.0:
		w_mult = 0.85
	elif wetness >= 40.0:
		w_mult = 0.92

	var mining_mult: float = 0.0 if is_mining else 1.0
	return e_mult * t_mult * h_mult * w_mult * mining_mult

func can_sprint() -> bool:
	return energy >= 20.0 and thirst > 10.0 and hunger > 10.0

func _handle_energy_regen(delta: float) -> void:
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		consume_energy(5.0 * delta)
	else:
		if energy < max_energy:
			var regen: float = energy_recovery_rate
			# Ночью на открытом воздухе регенерация энергии снижается вдвое
			if not is_instance_valid(_day_cycle) and get_tree() and get_tree().root:
				_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
			if _day_cycle and _day_cycle.has_method("is_night") and _day_cycle.is_night():
				regen *= 0.5
			# Промокший персонаж восстанавливает силы медленнее
			if wetness >= 50.0:
				regen *= 0.7
			energy = min(max_energy, energy + regen * delta)
			energy_changed.emit(energy, max_energy)

func _handle_thirst(delta: float) -> void:
	var drain_rate: float = thirst_decay_rate
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		drain_rate *= 1.6
	
	# В дневную жару (12:00-16:00) жажда нарастает интенсивнее
	if not is_instance_valid(_day_cycle) and get_tree() and get_tree().root:
		_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	if _day_cycle and "current_hour" in _day_cycle:
		var hour: int = _day_cycle.current_hour
		if hour >= 12 and hour <= 16:
			drain_rate *= 1.3
	
	var old_thirst: float = thirst
	thirst = max(0.0, thirst - drain_rate * delta)
	if abs(old_thirst - thirst) > 0.01:
		thirst_changed.emit(thirst, max_thirst)

func _handle_hunger(delta: float) -> void:
	var drain_rate: float = hunger_decay_rate
	var c_data: Dictionary = CharacterClassDB.get_class_data(character_class)
	drain_rate *= c_data.get("hunger_decay_mult", 1.0)
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		drain_rate *= 1.4

	var old_hunger: float = hunger
	hunger = max(0.0, hunger - drain_rate * delta)
	if abs(old_hunger - hunger) > 0.01:
		hunger_changed.emit(hunger, max_hunger)

func _handle_wetness(delta: float) -> void:
	if not is_instance_valid(_weather_mgr) and get_tree() and get_tree().root:
		_weather_mgr = get_tree().root.find_child("WeatherManager", true, false)
	var is_raining: bool = _weather_mgr.is_raining() if (_weather_mgr and _weather_mgr.has_method("is_raining")) else false
	var intensity: float = _weather_mgr.get_rain_intensity() if (_weather_mgr and _weather_mgr.has_method("get_rain_intensity")) else 0.0

	# Проверка укрытия (жилой дом стадии >= 1)
	var is_sheltered: bool = false
	if not is_instance_valid(_house) and get_tree() and get_tree().root:
		_house = get_tree().root.find_child("RepairableHouse", true, false)
	if _house and "current_stage" in _house and _house.current_stage >= 1:
		if global_position.distance_to(_house.global_position) < 5.2:
			is_sheltered = true

	# Проверка источника тепла (печь-плавильня)
	var is_near_fire: bool = false
	if not is_instance_valid(_smelter) and get_tree() and get_tree().root:
		_smelter = get_tree().root.find_child("Smelter", true, false)
	if _smelter and global_position.distance_to(_smelter.global_position) < 4.2:
		is_near_fire = true

	var old_wetness: float = wetness
	if is_raining and not is_sheltered:
		# Намокание под дождем
		var rate: float = 3.0 * intensity
		wetness = min(max_wetness, wetness + rate * delta)
	else:
		# Сушка
		var dry_rate: float = 1.0
		if is_near_fire:
			dry_rate = 8.5 # очень быстрая сушка у раскаленной печи
		elif is_sheltered:
			dry_rate = 5.0 # комфортная сушка в доме
		
		wetness = max(0.0, wetness - dry_rate * delta)

	if abs(old_wetness - wetness) > 0.01:
		wetness_changed.emit(wetness, max_wetness)

func dry_off(amount: float = 50.0) -> void:
	wetness = max(0.0, wetness - amount)
	wetness_changed.emit(wetness, max_wetness)
	notify("🔥 Вы обсохли и согрелись! Мокрота: %d%%." % int(wetness))

func consume_energy(amount: float) -> void:
	var mult: float = 1.0
	if wetness >= 80.0:
		mult = 1.5 # мокрая тяжелая одежда забирает больше сил
	elif wetness >= 40.0:
		mult = 1.25
	energy = max(0.0, energy - amount * mult)
	energy_changed.emit(energy, max_energy)

func drink_water(amount: float = 40.0, is_clean: bool = true, energy_bonus: float = 0.0) -> bool:
	if thirst >= max_thirst:
		notify("💧 Вы пока не хотите пить (Жажда 100%).")
		return false
	
	thirst = min(max_thirst, thirst + amount)
	thirst_changed.emit(thirst, max_thirst)
	
	if energy_bonus > 0.0:
		energy = min(max_energy, energy + energy_bonus)
		energy_changed.emit(energy, max_energy)
		
	if is_clean:
		notify("💧 Вы утолили жажду чистой водой! (+%d%% жажды, текущая: %d%%)" % [int(amount), int(thirst)])
	else:
		notify("⚠️ Вы выпили мутную сырую воду (+%d%% жажды, текущая: %d%%). Лучше фильтровать её!" % [int(amount), int(thirst)])
	return true

func drink_from_inventory(preferred_item_id: String = "") -> bool:
	if not inventory:
		return false
	
	var target_item: String = preferred_item_id
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		for it_id in ["bottled_water", "clean_water", "water"]:
			if inventory.get_item_count(it_id) > 0:
				target_item = it_id
				break
	
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		notify("ℹ️ В рюкзаке нет воды для питья!")
		return false
	
	if thirst >= max_thirst:
		notify("💧 Вы пока не испытываете жажды (100%).")
		return false
	
	var item_data: Dictionary = ItemDB.get_item(target_item)
	var rec: float = item_data.get("thirst_recovery", 30.0)
	var e_bon: float = item_data.get("energy_bonus", 0.0)
	var is_clean: bool = (target_item != "water")
	
	inventory.remove_item(target_item, 1)
	drink_water(rec, is_clean, e_bon)
	return true

func eat_food(food_item_id: String) -> bool:
	if not inventory:
		return false
	if inventory.get_item_count(food_item_id) <= 0:
		notify("ℹ️ У вас нет этого продукта!")
		return false
	
	if hunger >= max_hunger and energy >= max_energy:
		notify("🍽️ Вы не голодны и полны сил (Сытость 100%).")
		return false
	
	var item_data: Dictionary = ItemDB.get_item(food_item_id)
	var h_rec: float = item_data.get("hunger_recovery", 25.0)
	var e_rec: float = item_data.get("energy_bonus", 10.0)
	var t_rec: float = item_data.get("thirst_recovery", 0.0)
	var item_name: String = item_data.get("name", food_item_id)
	var item_icon: String = item_data.get("icon", "🍎")

	inventory.remove_item(food_item_id, 1)

	hunger = min(max_hunger, hunger + h_rec)
	hunger_changed.emit(hunger, max_hunger)

	if e_rec > 0.0:
		energy = min(max_energy, energy + e_rec)
		energy_changed.emit(energy, max_energy)

	if t_rec > 0.0:
		thirst = min(max_thirst, thirst + t_rec)
		thirst_changed.emit(thirst, max_thirst)

	notify("%s Вы съели %s! (+%d%% сытости, текущая: %d%%)" % [item_icon, item_name, int(h_rec), int(hunger)])
	return true

func eat_from_inventory(preferred_item_id: String = "") -> bool:
	if not inventory:
		return false
	
	var target_item: String = preferred_item_id
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		for it_id in ["bread", "potato", "carrot"]:
			if inventory.get_item_count(it_id) > 0:
				target_item = it_id
				break
	
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		notify("ℹ️ В рюкзаке нет готовой еды для перекуса!")
		return false
	
	return eat_food(target_item)

func rest_in_bed(new_day: int = -1) -> void:
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	if thirst < 35.0:
		thirst = 35.0
		thirst_changed.emit(thirst, max_thirst)
	if hunger < 35.0:
		hunger = 35.0
		hunger_changed.emit(hunger, max_hunger)
	wetness = 0.0
	wetness_changed.emit(wetness, max_wetness)
	if new_day > 0:
		notify("💤 Вы отлично выспались в тепле! Наступил День %d. Энергия 100%%." % new_day)
	else:
		notify("💤 Вы отлично выспались и полностью восстановили силы! Энергия 100%.")

func _check_bounds() -> void:
	if global_position.y < -5.0:
		global_position = Vector3(0.0, 0.5, 0.0)
		velocity = Vector3.ZERO

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		velocity.y = max(velocity.y, -25.0)
	else:
		if velocity.y < 0:
			velocity.y = -0.1

func _handle_movement(delta: float) -> void:
	if is_mining:
		# A short planted stance, not an ice-skating full-body animation.
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_sprinting: bool = Input.is_action_pressed("sprint") and can_sprint()
	var speed_mult: float = get_speed_multiplier()
	var target_speed: float = (sprint_speed if is_sprinting else walk_speed) * speed_mult
	
	var cam: Camera3D = get_viewport().get_camera_3d()
	var move_direction: Vector3 = Vector3.ZERO
	if cam:
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		move_direction = (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()
	else:
		move_direction = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	
	if move_direction.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, move_direction.x * target_speed, acceleration * delta * target_speed)
		velocity.z = move_toward(velocity.z, move_direction.z * target_speed, acceleration * delta * target_speed)
		
		if visual_root:
			var target_rot_y: float = atan2(-move_direction.x, -move_direction.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_rot_y, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * target_speed)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * target_speed)

func _on_interaction_area_entered(area: Area3D) -> void:
	if area.has_method("interact") and not nearby_interactables.has(area):
		nearby_interactables.append(area)

func _on_interaction_area_exited(area: Area3D) -> void:
	if area in nearby_interactables:
		nearby_interactables.erase(area)
		if current_interactable == area:
			_set_current_interactable(null)

func _update_best_interactable() -> void:
	nearby_interactables = nearby_interactables.filter(
		func(item): return is_instance_valid(item) and item.get("is_interactable") != false
	)
	
	if nearby_interactables.is_empty():
		_set_current_interactable(null)
		return
	
	var best_item: Area3D = null
	var min_score: float = INF
	var facing_dir: Vector3 = -visual_root.global_transform.basis.z if visual_root else Vector3.FORWARD
	facing_dir.y = 0.0
	if facing_dir.length_squared() > 0.001:
		facing_dir = facing_dir.normalized()
	else:
		facing_dir = Vector3.FORWARD
	
	for item in nearby_interactables:
		var to_item: Vector3 = item.global_position - global_position
		to_item.y = 0.0
		var dist: float = to_item.length()
		var dot: float = 1.0
		if dist > 0.001:
			dot = facing_dir.dot(to_item.normalized())
		# Объекты впереди (dot ~ 1.0) получают приоритет; объекты за спиной штрафуются
		var score: float = dist * (1.8 - 0.8 * clampf(dot, -1.0, 1.0))
		if score < min_score:
			min_score = score
			best_item = item
			
	_set_current_interactable(best_item)

func _set_current_interactable(new_target: Area3D) -> void:
	if current_interactable != new_target:
		current_interactable = new_target
		focused_interactable_changed.emit(current_interactable)

func _handle_interaction_input() -> void:
	# Input is dispatched once through _unhandled_input, after GUI consumption.
	pass

func _is_gameplay_blocked() -> bool:
	if get_tree().paused:
		return true
	if not is_instance_valid(_hud):
		_hud = get_tree().root.find_child("HUD", true, false)
	return is_instance_valid(_hud) and _hud.has_method("is_gameplay_input_blocked") and _hud.is_gameplay_input_blocked()

func _is_mining_resource(target: Area3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target.get("is_trader") == true or target.get("is_npc") == true:
		return false
	if "required_tool" in target and target.get("required_tool") in ["pickaxe", "axe", "shovel"]:
		return true
	if target.name.begins_with("Mock") or target.has_method("take_hit"):
		return true
	return not (target.get("is_machine") == true or target.get("is_container") == true)

func trigger_tool_strike() -> void:
	if _is_gameplay_blocked():
		_strike_held = false
		_strike_buffered = false
		return
	if is_mining:
		# One queued click, only near recovery; never an unbounded click backlog.
		if _strike_duration - _strike_elapsed <= STRIKE_BUFFER_WINDOW:
			_strike_buffered = true
		return
	if is_instance_valid(current_interactable) and not _is_mining_resource(current_interactable):
		# Machines, traders and water don't need a pickaxe animation.
		current_interactable.interact(self)
		_strike_held = false
		return
	_strike_target = current_interactable if is_instance_valid(current_interactable) else null
	if is_instance_valid(_strike_target) and visual_root:
		var dir_to_target: Vector3 = _strike_target.global_position - global_position
		dir_to_target.y = 0.0
		if dir_to_target.length_squared() > 0.001:
			var current_facing: Vector3 = -visual_root.global_transform.basis.z
			current_facing.y = 0.0
			if current_facing.length_squared() < 0.001 or current_facing.dot(dir_to_target.normalized()) > -0.2:
				visual_root.rotation.y = atan2(-dir_to_target.x, -dir_to_target.z)
	_play_interaction_swing()

func _update_strike(delta: float) -> void:
	if not is_mining:
		return
	if _is_gameplay_blocked():
		_strike_held = false
		_strike_buffered = false
		_finish_strike()
		return
	if _strike_pause_remaining > 0.0:
		_strike_pause_remaining = maxf(0.0, _strike_pause_remaining - delta)
		if _strike_pause_remaining <= 0.0 and anim_player:
			anim_player.speed_scale = 1.0
		return
	_strike_elapsed += delta
	if not _strike_impacted and _strike_elapsed >= STRIKE_CONTACT_TIME:
		_strike_impacted = true
		_apply_strike_contact()
	if _strike_elapsed >= _strike_duration:
		var repeat: bool = _strike_buffered or _strike_held
		_finish_strike()
		if repeat:
			_update_best_interactable()
			trigger_tool_strike()

func _apply_strike_contact() -> void:
	if not is_instance_valid(_strike_target) or _strike_target.get("is_interactable") == false:
		return
	if global_position.distance_to(_strike_target.global_position) > 2.5:
		return
	var old_hits = _strike_target.get("current_hits")
	_strike_target.interact(self)
	# ResourceNode owns sound and yield. Pause only this animation on a real hit.
	if is_instance_valid(_strike_target) and old_hits != null:
		var new_hits = _strike_target.get("current_hits")
		if new_hits != null and new_hits < old_hits:
			_trigger_hit_stop(STRIKE_HIT_PAUSE)
	focused_interactable_changed.emit(current_interactable if is_instance_valid(current_interactable) and current_interactable.get("is_interactable") != false else null)

func _trigger_hit_stop(duration: float = STRIKE_HIT_PAUSE) -> void:
	_strike_pause_remaining = duration
	if anim_player:
		anim_player.speed_scale = 0.0

func _finish_strike() -> void:
	is_mining = false
	_strike_buffered = false
	_strike_target = null
	_strike_pause_remaining = 0.0
	current_anim = ""
	if anim_player:
		anim_player.speed_scale = 1.0
	set_equipped_tool_visible(false)
	_update_character_animation()

func _on_inventory_tool_changed(_tool_id: String, _tool_name: String = "") -> void:
	# Кирка появляется только в момент нажатия кнопки удара
	if equipped_pickaxe_mesh and not is_mining:
		equipped_pickaxe_mesh.visible = false

func _update_character_animation() -> void:
	if not anim_player or is_mining:
		return
	
	var h_vel: Vector2 = Vector2(velocity.x, velocity.z)
	var speed: float = h_vel.length()
	
	if speed < 0.2:
		play_character_anim("idle")
	elif Input.is_action_pressed("sprint") and can_sprint():
		play_character_anim("run")
	else:
		play_character_anim("walk")

func play_character_anim(anim_name: String) -> void:
	if not anim_player or current_anim == anim_name:
		return
	if anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, 0.15)

func play_animation(anim_name: String) -> void:
	play_character_anim(anim_name)

func play_mining_animation() -> void:
	trigger_tool_strike()

func set_equipped_tool_visible(is_visible: bool) -> void:
	if equipped_pickaxe_mesh:
		equipped_pickaxe_mesh.visible = is_visible

func set_hat_visible(is_visible: bool) -> void:
	if sun_hat_mesh:
		sun_hat_mesh.visible = is_visible

func _play_interaction_swing() -> void:
	is_mining = true
	current_anim = "mine"
	_strike_elapsed = 0.0
	_strike_impacted = false
	_strike_buffered = false
	_strike_pause_remaining = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	set_equipped_tool_visible(true)
	_strike_duration = 0.42
	if anim_player and anim_player.has_animation("mine"):
		_strike_duration = anim_player.get_animation("mine").length
		anim_player.speed_scale = 1.0
		anim_player.play("mine", 0.0, 1.0)
		# Apply the first raised-tool pose now, not on the next animation tick.
		anim_player.advance(0.0)

func notify(text: String) -> void:
	notification_received.emit(text)
