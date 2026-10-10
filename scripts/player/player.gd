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
# Для новой модели шахтёра из Miner_Character_Package (Track_Pickaxe_Swing 1.5 c)
# длительность и момент контакта вычисляются от длины клипа:
# замах играется ускоренно (1.5x -> ~1.0 c), контакт на 55% замаха.
const STRIKE_CONTACT_TIME: float = 0.15
const STRIKE_BUFFER_WINDOW: float = 0.12
const STRIKE_HIT_PAUSE: float = 0.025
## Высота уступа жилы, на который персонаж поднимается сам (блок 0.5 м + запас).
const STEP_HEIGHT: float = 0.55
const STRIKE_CONTACT_FRACTION_LONG: float = 0.55
const STRIKE_CONTACT_FRACTION_SHORT: float = 0.38
const STRIKE_LONG_ANIM_THRESHOLD: float = 0.8
const STRIKE_LONG_ANIM_SPEED: float = 1.5

# Алиасы анимаций: логическое имя -> кандидаты в AnimationPlayer.
# Текущая модель (miner_package_model.tscn, tools/retarget_ual_to_miner.gd) содержит
# логические клипы idle/walk/jog/run/mine/chop/dig/scoop/... ретаргетированные из UAL1/UAL2.
# Остальные имена — для старых моделей (stardew/miner, Miner_Character_Package).
const ANIM_ALIASES: Dictionary = {
	"idle": ["idle", "Track_Idle", "ual_Idle"],
	"walk": ["walk", "Track_Walk", "ual_Walk", "Walk_Loop"],
	"jog": ["jog", "walk", "Track_Walk"],
	"run": ["run", "Track_Run", "ual_Sprint", "Sprint_Loop", "Jog_Fwd_Loop"],
	"mine": ["mine", "Track_Pickaxe_Swing", "Track_Pickaxe_Swing_Heavy", "ual_Chop"],
	"chop": ["chop", "mine", "ual_Chop", "Track_Pickaxe_Swing"],
	"dig": ["dig", "Track_Pickaxe_Dig_Loop", "Track_Pickaxe_Dig", "mine", "Track_Pickaxe_Swing"],
	"scoop": ["scoop", "Track_Pickaxe_Dig_Loop", "Track_Pickaxe_Dig", "idle", "Track_Idle"],
}
## Выше этой скорости (м/с) вместо шага играется лёгкий бег (jog): walk_speed = 4.5 м/с.
const JOG_SPEED_THRESHOLD: float = 2.2
## Пределы подгонки скорости клипа ходьбы под реальную скорость (против скольжения стоп).
const LOCOMOTION_SPEED_SCALE_MIN: float = 0.7
const LOCOMOTION_SPEED_SCALE_MAX: float = 1.6

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
# Динамическая экипировка: инструмент в руке соответствует экипированному слоту.
# Ключи словаря — tool_type из ItemDB ("axe", "pickaxe", "shovel", "bucket").
var tool_socket: BoneAttachment3D = null
var equipped_tool_nodes: Dictionary = {}
# Полное ведро (показывается после набора воды). Отдельный узел, не тип.
var bucket_full_mesh: Node3D = null
var bucket_filled: bool = false
var _bucket_full_timer: float = 0.0
# Копание лопатой (анимация dig) и набор воды (анимация scoop + капли).
var is_digging: bool = false
var _dig_elapsed: float = 0.0
var _dig_duration: float = 1.1
var is_scooping: bool = false
var _scoop_elapsed: float = 0.0
var _scoop_duration: float = 1.2
var _scoop_from: Vector3 = Vector3.ZERO
var _scoop_droplets_done: bool = false
var _scoop_filled_done: bool = false

const AxeInHandScene = preload("res://scenes/tools/axe_inhand.tscn")
const ShovelInHandScene = preload("res://scenes/tools/shovel_inhand.tscn")
const BucketInHandScene = preload("res://scenes/tools/bucket_inhand.tscn")
const BucketFullInHandScene = preload("res://scenes/tools/bucket_full_inhand.tscn")
## Хват in-hand моделей в сокете ToolSocket.R героя: начало сокета — центр кулака,
## +Y — от мизинца к указательному (к голове инструмента), +X — к костяшкам (лезвие).
## Меш axe_inhand смоделирован топорищем вверх и головой вниз (-Y): в руке он был
## перевёрнут. Поворот на 180° вокруг X ставит голову над кулаком, сохраняя направление
## лезвия (+X), а сдвиг переносит хват к концу топорища (12 см от торца).
## Лопата (лезвие +Y) остаётся как есть: в клипе dig кисть повёрнута большим пальцем
## к земле, и лезвие смотрит в грунт.
const INHAND_GRIP: Dictionary = {
	"axe": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 0.20, 0.0)),
}
var current_anim: String = ""
var is_mining: bool = false
var _strike_elapsed: float = 0.0
var _strike_duration: float = 0.42
var _strike_contact_time: float = STRIKE_CONTACT_TIME
var _pickaxe_is_builtin: bool = false
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
	if equipped_pickaxe_mesh == null:
		# Модели с киркой, заскиненной в тело (кирка всегда в руке, отдельного узла нет).
		equipped_pickaxe_mesh = find_child("Pickaxe", true, false)
	_pickaxe_is_builtin = equipped_pickaxe_mesh != null and equipped_pickaxe_mesh.name != "Equipped_Pickaxe"
	_fix_new_model_culling()
	sun_hat_mesh = find_child("Sun_Hat", true, false)
	if sun_hat_mesh == null:
		# Шахтёр: каска с фонарём вынесена в отдельный меш при запекании модели.
		sun_hat_mesh = find_child("Character_Helmet", true, false)
	_setup_equipped_tool_socket()
	_refresh_tool_visibility()
	if anim_player:
		for a_name in ["idle", "walk", "jog", "run"]:
			var resolved: String = _resolve_anim(a_name)
			if resolved != "" and anim_player.has_animation(resolved):
				anim_player.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR
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
	_update_dig(delta)
	_update_scoop(delta)
	if _bucket_full_timer > 0.0:
		_bucket_full_timer -= delta
		if _bucket_full_timer <= 0.0 and bucket_filled:
			bucket_filled = false
			_refresh_tool_visibility()

func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_energy_regen(delta)
	_handle_thirst(delta)
	_handle_hunger(delta)
	_handle_wetness(delta)
	_update_best_interactable()
	_handle_interaction_input()
	_try_step_up(delta)
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

	var mining_mult: float = 0.0 if (is_mining or is_digging or is_scooping) else 1.0
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
	if is_mining or is_digging or is_scooping:
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
	for i in range(nearby_interactables.size() - 1, -1, -1):
		var item = nearby_interactables[i]
		if not is_instance_valid(item) or item.get("is_interactable") == false:
			nearby_interactables.remove_at(i)
	
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
		# Жилы (VoxelDeposit) выбирают блок под прицелом; без блока в досягаемости не участвуют.
		if item.has_method("update_aim") and not item.update_aim(self):
			continue
		var to_item: Vector3 = _interaction_point(item) - global_position
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
	# Подсказка жилы меняется вместе с блоком под прицелом.
	if is_instance_valid(best_item) and best_item.has_method("consume_prompt_dirty") and best_item.consume_prompt_dirty():
		focused_interactable_changed.emit(best_item)

## Точка, к которой персонаж поворачивается и от которой меряется дистанция.
func _interaction_point(item: Node3D) -> Vector3:
	if item.has_method("get_interaction_point"):
		return item.get_interaction_point()
	return item.global_position

## Шаг на уступ высотой в блок жилы (0.5 м): иначе из ямы не выбраться.
## Работает только для тел группы voxel_terrain — заборы и стены остаются препятствием.
func _try_step_up(delta: float) -> bool:
	if not is_on_floor():
		return false
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < 0.04:
		return false
	var motion: Vector3 = horiz * maxf(delta, 1.0 / 60.0)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit, 0.001, false, 4):
		return false
	var wall: bool = false
	for i in hit.get_collision_count():
		var collider: Object = hit.get_collider(i)
		if collider is Node and collider.is_in_group("voxel_terrain") and hit.get_normal(i).y < 0.7:
			wall = true
			break
	if not wall:
		return false
	var up: Vector3 = Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return false
	var raised: Transform3D = global_transform.translated(up)
	if test_move(raised, horiz.normalized() * 0.3):
		return false
	global_position += up
	return true

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
	if target.name.begins_with("Mock") or target.has_method("take_hit"):
		return true
	# Добывающие узлы — только ResourceNode с инструментом удара.
	# Станки, торговец, грядки, водоём-резервуар и вода (ведро) идут
	# через прямое взаимодействие без замаха киркой.
	if target.get("is_machine") == true or target.get("is_container") == true:
		return false
	# Пень срубленного дерева: посадка саженца без замаха топором.
	if target.get("is_depleted") == true:
		return false
	var req: Variant = target.get("required_tool") if "required_tool" in target else null
	if req == null:
		return false
	return req in ["pickaxe", "axe", "shovel"]

func trigger_tool_strike() -> void:
	if _is_gameplay_blocked():
		_strike_held = false
		_strike_buffered = false
		return
	if is_digging or is_scooping:
		return
	if is_mining:
		# One queued click, only near recovery; never an unbounded click backlog.
		if _strike_duration - _strike_elapsed <= STRIKE_BUFFER_WINDOW:
			_strike_buffered = true
		return
	if is_instance_valid(current_interactable) and not _is_mining_resource(current_interactable):
		# Machines, traders and water don't need a tool-swing animation.
		current_interactable.interact(self)
		_strike_held = false
		return
	_strike_target = current_interactable if is_instance_valid(current_interactable) else null
	if is_instance_valid(_strike_target) and visual_root:
		var dir_to_target: Vector3 = _interaction_point(_strike_target) - global_position
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
	if not _strike_impacted and _strike_elapsed >= _strike_contact_time:
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
	if _strike_target.has_method("is_in_reach"):
		if not _strike_target.is_in_reach(self):
			return
	elif global_position.distance_to(_strike_target.global_position) > 2.5:
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
	_refresh_tool_visibility()
	_update_character_animation()

func _on_inventory_tool_changed(_tool_id: String, _tool_name: String = "") -> void:
	_refresh_tool_visibility()

## Тип currently экипированного инструмента по ItemDB ("axe"/"pickaxe"/"shovel"/"bucket").
func _current_tool_type() -> String:
	if inventory == null:
		return "pickaxe"
	var eq: String = inventory.get_equipped_tool() if inventory.has_method("get_equipped_tool") else "pickaxe"
	var d: Dictionary = ItemDB.get_item(eq)
	return d.get("tool_type", "pickaxe")

## Создаёт BoneAttachment на кости ToolSocket.R и цепляет in-hand модели
## топора/лопаты/ведра. Кирка уже заскинена в модели персонажа — используем её узел.
## Новая модель из Miner_Character_Package не имеет кости ToolSocket.R:
## откатываемся на Pickaxe_Attachment_R / Hand_R / Hand.R.
const TOOL_SOCKET_BONES: Array[String] = [
	"ToolSocket.R", "Pickaxe_Attachment_R", "Hand_R", "Hand.R", "Hand.r", "hand_r",
	"mixamorig:RightHand", "RightHand",
]

func _find_tool_bone(skeleton: Skeleton3D) -> String:
	for b in TOOL_SOCKET_BONES:
		if skeleton.find_bone(b) != -1:
			return b
	return ""

func _setup_equipped_tool_socket() -> void:
	equipped_tool_nodes.clear()
	if equipped_pickaxe_mesh:
		equipped_tool_nodes["pickaxe"] = equipped_pickaxe_mesh
	if visual_root == null:
		return
	var skeleton := visual_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var bone_name: String = _find_tool_bone(skeleton)
	if bone_name == "":
		return
	# Модели персонажей уже содержат BoneAttachment на ToolSocket.R
	# (кость-родитель для Equipped_Pickaxe) — переиспользуем его.
	for child in skeleton.get_children():
		if child is BoneAttachment3D and child.bone_name == bone_name:
			tool_socket = child
			break
	if tool_socket == null:
		tool_socket = BoneAttachment3D.new()
		tool_socket.name = "ToolSocket_Runtime"
		tool_socket.bone_name = bone_name
		skeleton.add_child(tool_socket)
	_attach_inhand_tool("axe", AxeInHandScene)
	_attach_inhand_tool("shovel", ShovelInHandScene)
	_attach_inhand_tool("bucket", BucketInHandScene)
	_bucket_full_mesh_setup()

func _attach_inhand_tool(tool_type: String, scene: PackedScene) -> void:
	if tool_socket == null or scene == null:
		return
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "Equipped_" + tool_type.capitalize()
	inst.visible = false
	if INHAND_GRIP.has(tool_type):
		inst.transform = INHAND_GRIP[tool_type]
	tool_socket.add_child(inst)
	equipped_tool_nodes[tool_type] = inst

func _bucket_full_mesh_setup() -> void:
	if tool_socket == null or BucketFullInHandScene == null:
		return
	var inst := BucketFullInHandScene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "Equipped_BucketFull"
	inst.visible = false
	tool_socket.add_child(inst)
	bucket_full_mesh = inst

## Единая точка управления видимостью: во время замаха виден инструмент,
## соответствующий экипированному слоту; вне замаха все скрыты, кроме ведра
## (ведро несут в руке постоянно — у него нет анимации удара, только набор воды).
func _hide_all_tools() -> void:
	for k in equipped_tool_nodes:
		var n: Node3D = equipped_tool_nodes[k]
		if is_instance_valid(n):
			n.visible = false
	if is_instance_valid(bucket_full_mesh):
		bucket_full_mesh.visible = false

func _show_bucket() -> void:
	if bucket_filled and is_instance_valid(bucket_full_mesh):
		bucket_full_mesh.visible = true
	elif equipped_tool_nodes.has("bucket"):
		equipped_tool_nodes["bucket"].visible = true

func _refresh_tool_visibility() -> void:
	_hide_all_tools()
	if is_digging:
		# Копание всегда лопатой, даже если экипирован другой инструмент.
		if equipped_tool_nodes.has("shovel"):
			equipped_tool_nodes["shovel"].visible = true
		return
	if is_scooping:
		_show_bucket()
		return
	var t := _current_tool_type()
	if not equipped_tool_nodes.has(t):
		return
	if is_mining:
		if t == "bucket":
			_show_bucket()
		else:
			equipped_tool_nodes[t].visible = true
	elif t == "bucket":
		_show_bucket()
	elif t == "pickaxe" and _pickaxe_is_builtin:
		# Встроенная кирка новой модели — часть образа шахтёра, несём в руке всегда.
		equipped_tool_nodes[t].visible = true

func _update_character_animation() -> void:
	if not anim_player or is_mining or is_digging or is_scooping:
		return
	
	var h_vel: Vector2 = Vector2(velocity.x, velocity.z)
	var speed: float = h_vel.length()
	
	if speed < 0.2:
		play_character_anim("idle")
	elif Input.is_action_pressed("sprint") and can_sprint():
		play_character_anim("run")
	elif speed > JOG_SPEED_THRESHOLD:
		play_character_anim("jog")
	else:
		play_character_anim("walk")
	_match_locomotion_speed(speed)

## Подгоняет темп клипа ходьбы/бега под скорость персонажа (metadata/ground_speed
## записывает tools/retarget_ual_to_miner.gd), чтобы стопы не скользили.
func _match_locomotion_speed(speed: float) -> void:
	if current_anim == "" or not anim_player.has_animation(current_anim):
		return
	var anim: Animation = anim_player.get_animation(current_anim)
	if anim.has_meta("ground_speed") and float(anim.get_meta("ground_speed")) > 0.01 and speed >= 0.2:
		var ratio: float = speed / float(anim.get_meta("ground_speed"))
		anim_player.speed_scale = clampf(ratio, LOCOMOTION_SPEED_SCALE_MIN, LOCOMOTION_SPEED_SCALE_MAX)
	else:
		anim_player.speed_scale = 1.0

func play_character_anim(anim_name: String) -> void:
	if not anim_player:
		return
	var resolved: String = _resolve_anim(anim_name)
	if resolved == "" or current_anim == resolved:
		return
	if anim_player.has_animation(resolved):
		current_anim = resolved
		anim_player.play(resolved, 0.15)

## Темп проигрывания клипа из metadata/play_speed (задаётся при запекании), иначе fallback.
func _anim_play_speed(anim_name: String, fallback: float) -> float:
	if anim_player and anim_player.has_animation(anim_name):
		var a: Animation = anim_player.get_animation(anim_name)
		if a.has_meta("play_speed"):
			return maxf(0.05, float(a.get_meta("play_speed")))
	return fallback

## Возвращает первое существующее в AnimationPlayer имя из алиасов.
## Пустая строка — анимация отсутствует в текущей модели.
func _resolve_anim(logical_name: String) -> String:
	if anim_player == null:
		return ""
	if anim_player.has_animation(logical_name):
		return logical_name
	if ANIM_ALIASES.has(logical_name):
		for candidate in ANIM_ALIASES[logical_name]:
			if anim_player.has_animation(candidate):
				return candidate
	return ""

## Защита от исчезновения меша новой модели из-за AABB-отсечения.
func _fix_new_model_culling() -> void:
	if visual_root == null:
		return
	var meshes: Array[Node] = visual_root.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi:
			mi.extra_cull_margin = 5.0

func play_animation(anim_name: String) -> void:
	play_character_anim(anim_name)

func play_mining_animation() -> void:
	trigger_tool_strike()

## Поворачивает корпус лицом к мировой точке (для копания/набора воды).
func _face_toward(world_pos: Vector3) -> void:
	if not visual_root:
		return
	var dir: Vector3 = world_pos - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		visual_root.rotation.y = atan2(-dir.x, -dir.z)

## Копание лопатой: поза dig (fallback — mine), в руке принудительно лопата.
## Возвращает false, если персонаж занят другим действием.
func play_dig_animation(target: Node3D = null) -> bool:
	if is_mining or is_digging or is_scooping:
		return false
	if is_instance_valid(target):
		_face_toward(target.global_position)
	velocity.x = 0.0
	velocity.z = 0.0
	is_digging = true
	_dig_elapsed = 0.0
	_dig_duration = 1.1
	current_anim = "dig"
	if anim_player:
		var dig_anim: String = _resolve_anim("dig")
		if dig_anim != "":
			_dig_duration = anim_player.get_animation(dig_anim).length
			# Мокап-клип (2.0+ с) играем ускоренно, чтобы вскопка не вязала надолго;
			# темп берём из metadata/play_speed клипа, если он задан при запекании.
			var dig_speed: float = _anim_play_speed(dig_anim, 1.45 if _dig_duration > 1.5 else 1.0)
			_dig_duration = _dig_duration / dig_speed
			anim_player.speed_scale = 1.0
			anim_player.play(dig_anim, 0.1, dig_speed)
			current_anim = dig_anim
	_refresh_tool_visibility()
	return true

func _update_dig(delta: float) -> void:
	if not is_digging:
		return
	_dig_elapsed += delta
	if _dig_elapsed >= _dig_duration:
		_finish_dig()

func _finish_dig() -> void:
	is_digging = false
	_dig_elapsed = 0.0
	current_anim = ""
	_refresh_tool_visibility()
	_update_character_animation()

## Набор воды: персонаж выставляет ведро к источнику, капли перелетают
## из хранилища в ведро, модель меняется на наполненное.
func play_scoop_animation(source_pos: Vector3) -> bool:
	if is_mining or is_digging or is_scooping:
		return false
	_face_toward(source_pos)
	velocity.x = 0.0
	velocity.z = 0.0
	is_scooping = true
	_scoop_elapsed = 0.0
	_scoop_duration = 1.2
	_scoop_from = source_pos
	_scoop_droplets_done = false
	_scoop_filled_done = false
	current_anim = "scoop"
	if anim_player:
		var scoop_anim: String = _resolve_anim("scoop")
		if scoop_anim != "":
			var scoop_speed: float = _anim_play_speed(scoop_anim, 1.0)
			_scoop_duration = anim_player.get_animation(scoop_anim).length / scoop_speed
			anim_player.speed_scale = 1.0
			anim_player.play(scoop_anim, 0.1, scoop_speed)
			current_anim = scoop_anim
	_refresh_tool_visibility()
	return true

func _update_scoop(delta: float) -> void:
	if not is_scooping:
		return
	_scoop_elapsed += delta
	# Моменты привязаны к длине клипа: капли — когда руки внизу (60%),
	# полное ведро — на подъёме (85%).
	if not _scoop_droplets_done and _scoop_elapsed >= _scoop_duration * 0.6:
		_scoop_droplets_done = true
		_spawn_scoop_droplets(_scoop_from)
	if not _scoop_filled_done and _scoop_elapsed >= _scoop_duration * 0.85:
		_scoop_filled_done = true
		bucket_filled = true
		_bucket_full_timer = 5.0
		_refresh_tool_visibility()
	if _scoop_elapsed >= _scoop_duration:
		_finish_scoop()

func _finish_scoop() -> void:
	is_scooping = false
	_scoop_elapsed = 0.0
	current_anim = ""
	_refresh_tool_visibility()
	_update_character_animation()

## Залп капель от источника к ведру по баллистической дуге (one-shot).
func _spawn_scoop_droplets(from_pos: Vector3) -> void:
	var bucket_node: Node3D = bucket_full_mesh if bucket_filled else equipped_tool_nodes.get("bucket")
	var target: Vector3 = global_position + Vector3(0, 1.0, 0)
	if is_instance_valid(bucket_node):
		target = bucket_node.global_position
	elif is_instance_valid(tool_socket):
		target = tool_socket.global_position
	var emit: Vector3 = from_pos + Vector3(0, 0.5, 0)
	var flight: float = 0.55
	var vel: Vector3 = (target - emit) / flight + Vector3(0, 0.5 * 9.8 * flight, 0)
	var parts := GPUParticles3D.new()
	parts.name = "ScoopDroplets"
	parts.amount = 28
	parts.lifetime = 0.7
	parts.one_shot = true
	parts.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.direction = vel.normalized()
	pm.spread = 10.0
	pm.initial_velocity_min = vel.length() * 0.9
	pm.initial_velocity_max = vel.length() * 1.1
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	parts.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.025
	dot.height = 0.05
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(0.35, 0.65, 0.95)
	dot_mat.roughness = 0.1
	dot.material = dot_mat
	parts.draw_pass_1 = dot
	var parent := get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(parts)
	parts.global_position = emit
	parts.emitting = true
	get_tree().create_timer(2.0).timeout.connect(parts.queue_free)

func set_equipped_tool_visible(is_visible: bool) -> void:
	_hide_all_tools()
	if is_visible:
		var t := _current_tool_type()
		if t == "bucket":
			_show_bucket()
		elif equipped_tool_nodes.has(t):
			equipped_tool_nodes[t].visible = true

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
	_strike_contact_time = STRIKE_CONTACT_TIME
	if anim_player:
		# Топор рубит горизонтально (chop), остальные инструменты — удар сверху (mine).
		var swing_anim: String = _resolve_anim("chop" if _current_tool_type() == "axe" else "mine")
		if swing_anim != "":
			var swing: Animation = anim_player.get_animation(swing_anim)
			var swing_len: float = swing.length
			var swing_speed: float = 1.0
			if swing.has_meta("contact_time"):
				# Запечённый клип: темп и момент контакта заданы в metadata
				# (tools/retarget_ual_to_miner.gd).
				swing_speed = _anim_play_speed(swing_anim, 1.0)
				_strike_duration = swing_len / swing_speed
				_strike_contact_time = float(swing.get_meta("contact_time")) / swing_speed
			# Длинный замах (1.5 c) играем ускоренно до ~1.0 c, контакт на 55% замаха.
			# Короткий замах старой модели (~0.42 c) — как есть, контакт на 38%.
			elif swing_len >= STRIKE_LONG_ANIM_THRESHOLD:
				swing_speed = STRIKE_LONG_ANIM_SPEED
				_strike_duration = swing_len / swing_speed
				_strike_contact_time = _strike_duration * STRIKE_CONTACT_FRACTION_LONG
			else:
				_strike_duration = swing_len
				_strike_contact_time = _strike_duration * STRIKE_CONTACT_FRACTION_SHORT
			current_anim = swing_anim
			anim_player.speed_scale = 1.0
			anim_player.play(swing_anim, 0.0, swing_speed)
			# Apply the first raised-tool pose now, not on the next animation tick.
			anim_player.advance(0.0)

func notify(text: String) -> void:
	notification_received.emit(text)
