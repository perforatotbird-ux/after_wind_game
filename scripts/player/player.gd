extends CharacterBody3D

signal focused_interactable_changed(interactable: Area3D)
signal notification_received(text: String)
signal energy_changed(current: float, max_val: float)
signal thirst_changed(current: float, max_val: float)
signal inventory_toggle_requested()

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

const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

@export_group("References")
@onready var visual_root: Node3D = $Visuals
@onready var interaction_detector: Area3D = $InteractionDetector
@onready var inventory: Node = $Inventory

var energy: float = 100.0
var thirst: float = 100.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var nearby_interactables: Array[Area3D] = []
var current_interactable: Area3D = null

func _ready() -> void:
	if not inventory:
		# На случай если нода не добавлена в сцену явно
		inventory = InventoryScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	
	if interaction_detector:
		interaction_detector.area_entered.connect(_on_interaction_area_entered)
		interaction_detector.area_exited.connect(_on_interaction_area_exited)
	
	energy = max_energy
	thirst = max_thirst
	energy_changed.emit(energy, max_energy)
	thirst_changed.emit(thirst, max_thirst)

func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_energy_regen(delta)
	_handle_thirst(delta)
	_update_best_interactable()
	_handle_interaction_input()
	move_and_slide()
	_check_bounds()

func _unhandled_input(event: InputEvent) -> void:
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
			KEY_TAB, KEY_I:
				inventory_toggle_requested.emit()

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

	return e_mult * t_mult

func can_sprint() -> bool:
	return energy >= 20.0 and thirst > 10.0

func _handle_energy_regen(delta: float) -> void:
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		consume_energy(5.0 * delta)
	else:
		if energy < max_energy:
			var regen: float = energy_recovery_rate
			# Ночью на открытом воздухе регенерация энергии снижается вдвое
			var day_cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
			if day_cycle and day_cycle.has_method("is_night") and day_cycle.is_night():
				regen *= 0.5
			energy = min(max_energy, energy + regen * delta)
			energy_changed.emit(energy, max_energy)

func _handle_thirst(delta: float) -> void:
	var drain_rate: float = thirst_decay_rate
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		drain_rate *= 1.6
	
	# В дневную жару (12:00-16:00) жажда нарастает интенсивнее
	var day_cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
	if day_cycle and "current_hour" in day_cycle:
		var hour: int = day_cycle.current_hour
		if hour >= 12 and hour <= 16:
			drain_rate *= 1.3
	
	var old_thirst: float = thirst
	thirst = max(0.0, thirst - drain_rate * delta)
	if abs(old_thirst - thirst) > 0.01:
		thirst_changed.emit(thirst, max_thirst)

func consume_energy(amount: float) -> void:
	energy = max(0.0, energy - amount)
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

func rest_in_bed(new_day: int = -1) -> void:
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	if thirst < 35.0:
		thirst = 35.0
		thirst_changed.emit(thirst, max_thirst)
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
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_sprinting: bool = Input.is_action_pressed("sprint") and can_sprint()
	var speed_mult: float = get_speed_multiplier()
	var target_speed: float = (sprint_speed if is_sprinting else walk_speed) * speed_mult
	
	var move_direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	
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
	var min_dist: float = INF
	
	for item in nearby_interactables:
		var dist: float = global_position.distance_to(item.global_position)
		if dist < min_dist:
			min_dist = dist
			best_item = item
			
	_set_current_interactable(best_item)

func _set_current_interactable(new_target: Area3D) -> void:
	if current_interactable != new_target:
		current_interactable = new_target
		focused_interactable_changed.emit(current_interactable)

func _handle_interaction_input() -> void:
	if Input.is_action_just_pressed("interact"):
		if current_interactable and current_interactable.has_method("interact"):
			# Анимация взмаха/наклона персонажа
			_play_interaction_swing()
			current_interactable.interact(self)
			# Обновляем текст подсказки после взаимодействия (например убавилась прочность)
			if current_interactable and current_interactable.get("is_interactable") != false:
				focused_interactable_changed.emit(current_interactable)
			else:
				focused_interactable_changed.emit(null)

func _play_interaction_swing() -> void:
	if not visual_root:
		return
	var tw: Tween = create_tween()
	var orig_rot: Vector3 = visual_root.rotation
	tw.tween_property(visual_root, "rotation:x", orig_rot.x - 0.25, 0.08)
	tw.tween_property(visual_root, "rotation:x", orig_rot.x, 0.12)

func notify(text: String) -> void:
	notification_received.emit(text)
