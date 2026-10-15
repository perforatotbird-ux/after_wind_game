extends CharacterBody3D

signal focused_interactable_changed(interactable: Area3D)
signal notification_received(text: String)
signal health_changed(current: float, max_val: float)
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
@export var jump_speed: float = 4.6
const JUMP_BUFFER_TIME := 0.12
const COYOTE_TIME := 0.10
var is_jumping := false
var _jump_buffer := 0.0
var _coyote_left := 0.0
var _jump_elapsed := 0.0
var _landing_left := 0.0
var _air_elapsed := 0.0
var hoe_grip: SkeletonModifier3D

@export_group("Stats")
@export var max_health: float = 100.0
@export var max_energy: float = 100.0
## Базовая скорость восстановления энергии в покое (%/сек реального времени).
## Ходьба снижает её в 4 раза, ночь — вдвое, голод/жажда — до четверти;
## при 24+ ч без сна естественная регенерация выключена совсем.
@export var energy_recovery_rate: float = 0.5
@export var max_thirst: float = 100.0
@export var thirst_decay_rate: float = 0.2
@export var max_hunger: float = 100.0
@export var hunger_decay_rate: float = 0.15
@export var max_wetness: float = 100.0
## Скорость высыхания (%/сек) на открытом воздухе в сухую погоду.
## 100 % влаги сохнет примерно 14 минут (баланс после замедления ×3).
@export var dry_rate_outdoor: float = 0.12
## Скорость высыхания в укрытии (дом стадии 1+).
@export var dry_rate_sheltered: float = 0.4
## Скорость высыхания у источника тепла (печь-плавильня).
@export var dry_rate_near_fire: float = 2.0
## Урон здоровью в секунду при полном истощении сил (энергия 0).
@export var exhaustion_damage_rate: float = 0.5
@export var sleep_deprivation_threshold: float = 24.0
@export var critical_sleep_threshold: float = 36.0

@export_group("Temperature")
## Ниже этой температуры воздуха (°C) персонаж начинает мёрзнуть на улице.
@export var cold_threshold_temperature: float = 2.0
## Урон здоровью в секунду при полной промерзании (температура на 10 °C ниже порога).
@export var cold_damage_rate: float = 0.6
## Множитель жажды в летний полдень (12:00–17:00).
@export var summer_heat_thirst_multiplier: float = 1.5

@export_group("Specialization")
@export var character_class: String = "miner"

const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const Seasons = preload("res://scripts/core/seasons.gd")

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

const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

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
	"jump_start": ["jump_start"],
	"jump_loop": ["jump_loop"],
	"jump_land": ["jump_land"],
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
## Семена, выбранные для посадки на делянке (R у делянки или кнопка в рюкзаке).
var selected_seed: String = ""

var health: float = 100.0
var energy: float = 100.0
var thirst: float = 100.0
var hunger: float = 100.0
var wetness: float = 0.0
var hours_without_sleep: float = 0.0
var _last_sleep_warning_hour: int = 0
## Одноразовое предупреждение «истощение подтачивает здоровье» (сбрасывается при восстановлении).
var _exhaustion_damage_warned: bool = false
## Предупреждения о холоде — по одному на эпизод промерзания.
var _cold_warned: bool = false
var _freezing_warned: bool = false
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
# Копание мотыгой (анимация dig) и набор воды (анимация scoop + капли).
var is_digging: bool = false
var _dig_elapsed: float = 0.0
var _dig_duration: float = 1.1
## Идёт переход отдыха/сна (RestTransition): движение и ввод заблокированы.
var is_resting: bool = false
var is_scooping: bool = false
var _scoop_elapsed: float = 0.0
var _scoop_duration: float = 1.2
var _scoop_from: Vector3 = Vector3.ZERO
var _scoop_droplets_done: bool = false
var _scoop_filled_done: bool = false

const AxeInHandScene = preload("res://scenes/tools/axe_inhand.tscn")
const ShovelInHandScene = preload("res://scenes/tools/hoe_inhand.tscn")
const HoeGripModifier = preload("res://scripts/player/hoe_grip_modifier.gd")
const BucketInHandScene = preload("res://scenes/tools/bucket_inhand.tscn")
const BucketFullInHandScene = preload("res://scenes/tools/bucket_full_inhand.tscn")
## Хват in-hand моделей в сокете ToolSocket.R героя: начало сокета — центр кулака,
## +Y — от мизинца к указательному (к голове инструмента), +X — к костяшкам (лезвие).
## Меш axe_inhand смоделирован топорищем вверх и головой вниз (-Y): в руке он был
## перевёрнут. Поворот на 180° вокруг X ставит голову над кулаком, сохраняя направление
## лезвия (+X), а сдвиг переносит хват к концу топорища (12 см от торца).
## Мотыга: ось черенка +Y; обе кисти и положение лезвия задаёт HoeTwoHandGrip.
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
## Шаги: накопленная дистанция до следующего звука шага (м).
var _step_distance: float = 0.0
const FOOTSTEP_STRIDE: float = 1.6
var _hud: Node = null
var _day_cycle: Node = null
var _weather_mgr: Node = null
var _season_mgr: Node = null
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
		anim_player.add_animation_library("tools", load("res://assets/animations/hero_actions.tres"))
		for a_name in ["idle", "walk", "jog", "run"]:
			var resolved: String = _resolve_anim(a_name)
			if resolved != "" and anim_player.has_animation(resolved):
				anim_player.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR
		play_character_anim("idle")
	
	if inventory and inventory.has_signal("tool_changed"):
		inventory.tool_changed.connect(_on_inventory_tool_changed)
	
	health = max_health
	energy = max_energy
	thirst = max_thirst
	hunger = max_hunger
	wetness = 0.0
	hours_without_sleep = 0.0
	_last_sleep_warning_hour = 0
	health_changed.emit(health, max_health)
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
	_update_jump_input(delta)
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_energy_regen(delta)
	_handle_thirst(delta)
	_handle_hunger(delta)
	_handle_wetness(delta)
	_handle_temperature(delta)
	_handle_sleep_need(delta)
	_handle_health(delta)
	_update_best_interactable()
	_handle_interaction_input()
	_try_step_up(delta)
	move_and_slide()
	_update_jump_state(delta)
	_update_footsteps(delta)
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
	if is_resting:
		return
	if event.is_action_pressed("jump") and not event.is_echo():
		if not _is_gameplay_blocked() and not (is_mining or is_digging or is_scooping):
			_jump_buffer = JUMP_BUFFER_TIME
		get_viewport().set_input_as_handled()
		return
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
	if event.is_action_pressed("toggle_inventory") and not event.is_echo():
		inventory_toggle_requested.emit()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match code:
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
			KEY_R, KEY_G, KEY_X:
				_farm_key(code)
			KEY_F5:
				quick_save()
			KEY_F9:
				quick_load()

## Делянка под прицелом: R — сменить семена, G — зона 1×1 / 3×3, X — отменить стройку.
func _farm_key(key: Key) -> void:
	if _is_gameplay_blocked():
		return
	_update_best_interactable()
	var t = current_interactable
	if not is_instance_valid(t) or not t.is_in_group("farm_fields"):
		return
	match key:
		KEY_R:
			t.cycle_seed(self)
		KEY_G:
			t.toggle_zone(self)
		KEY_X:
			t.request_cancel(self)
	focused_interactable_changed.emit(t)

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

func get_effective_max_energy() -> float:
	if hours_without_sleep >= critical_sleep_threshold:
		return 50.0
	elif hours_without_sleep >= sleep_deprivation_threshold:
		return 75.0
	return max_energy

func is_sleep_deprived() -> bool:
	return hours_without_sleep >= sleep_deprivation_threshold

func get_sleep_status_text() -> String:
	if hours_without_sleep >= critical_sleep_threshold:
		return "Критическое переутомление (без сна %.1f ч)" % hours_without_sleep
	elif hours_without_sleep >= sleep_deprivation_threshold:
		return "Бессонница (без сна %.1f ч)" % hours_without_sleep
	elif hours_without_sleep >= 18.0:
		return "Усталость (без сна %.1f ч)" % hours_without_sleep
	return "Бодр"

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

	# Дебаф от недостатка сна (> 24 часов)
	var s_mult: float = 1.0
	if hours_without_sleep >= critical_sleep_threshold:
		s_mult = 0.65 # -35% скорости при критическом недосыпе
	elif hours_without_sleep >= sleep_deprivation_threshold:
		s_mult = 0.80 # -20% скорости если без сна более суток
	elif hours_without_sleep >= 18.0:
		s_mult = 0.92 # -8% легкая вялость под вечер

	# Погода: метель и ураган замедляют (SeasonManager.get_speed_multiplier)
	var weather_mult: float = 1.0
	var sm := _find_season_mgr()
	if sm and sm.has_method("get_speed_multiplier"):
		weather_mult = float(sm.get_speed_multiplier())

	var mining_mult: float = 0.0 if (is_mining or is_digging or is_scooping) else 1.0
	return e_mult * t_mult * h_mult * w_mult * s_mult * weather_mult * mining_mult

func can_sprint() -> bool:
	if hours_without_sleep >= critical_sleep_threshold:
		return false # при критической бессоннице (>36ч) спринт заблокирован
	var min_e: float = 35.0 if hours_without_sleep >= sleep_deprivation_threshold else 20.0
	return energy >= min_e and thirst > 10.0 and hunger > 10.0

func _handle_energy_regen(delta: float) -> void:
	var sprint_active: bool = Input.is_action_pressed("sprint") and can_sprint() and velocity.length_squared() > 1.0
	if sprint_active:
		var drain: float = 6.0
		if hours_without_sleep >= sleep_deprivation_threshold:
			drain = 9.0 # при бессоннице бег истощает гораздо сильнее
		consume_energy(drain * delta)
	else:
		var eff_max: float = get_effective_max_energy()
		if energy > eff_max:
			# Плавное снижение излишка при накатившей бессоннице
			energy = move_toward(energy, eff_max, 2.0 * delta)
			energy_changed.emit(energy, max_energy)
		elif energy < eff_max:
			# Бессонница (>= 24 ч) блокирует естественное восстановление —
			# силы возвращает только сон.
			if hours_without_sleep >= sleep_deprivation_threshold:
				return

			var regen: float = energy_recovery_rate
			# Голод и жажда снижают восстановление, но не обнуляют его: раньше
			# при сытости/жажде < 20% регенерация вставала полностью, и энергии
			# можно было набраться, только непрерывно перекусывая.
			if hunger < 20.0 or thirst < 20.0:
				regen *= 0.25
			elif hunger < 40.0 or thirst < 40.0:
				regen *= 0.5
			# При ходьбе восстановление сил снижается в 4 раза (25%)
			if velocity.length_squared() > 0.5:
				regen *= 0.25
			
			# Ночью на открытом воздухе регенерация энергии снижается вдвое
			if not is_instance_valid(_day_cycle) and get_tree() and get_tree().root:
				_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
			if _day_cycle and _day_cycle.has_method("is_night") and _day_cycle.is_night():
				regen *= 0.5
			# Промокший персонаж восстанавливает силы медленнее
			if wetness >= 50.0:
				regen *= 0.7
			energy = min(eff_max, energy + regen * delta)
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

	# Летний зной в полдень: жажда ×1.5 (раздел 12.3 мастер-плана)
	if Seasons.get_current_season() == Seasons.SUMMER:
		var current_hour: float = float(_day_cycle.current_hour) if (_day_cycle and "current_hour" in _day_cycle) else 12.0
		if current_hour >= 12.0 and current_hour <= 17.0:
			drain_rate *= summer_heat_thirst_multiplier
	
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

	# Проверка источника тепла (печь-плавильня, костёр)
	var is_near_fire: bool = is_near_heat()

	var old_wetness: float = wetness
	if is_raining and not is_sheltered:
		# Намокание под дождем (интенсивность дождя учитывается)
		var rate: float = 3.0 * intensity
		wetness = min(max_wetness, wetness + rate * delta)
	else:
		# Высыхание постепенное: на улице медленно, в доме быстрее, у печи — быстро.
		var dry_rate: float = dry_rate_outdoor
		if is_near_fire:
			dry_rate = dry_rate_near_fire
		elif is_sheltered:
			dry_rate = dry_rate_sheltered

		wetness = max(0.0, wetness - dry_rate * delta)

	if abs(old_wetness - wetness) > 0.01:
		wetness_changed.emit(wetness, max_wetness)

func dry_off(amount: float = 50.0) -> void:
	wetness = max(0.0, wetness - amount)
	wetness_changed.emit(wetness, max_wetness)
	notify("🔥 Вы обсохли и согрелись! Мокрота: %d%%." % int(wetness))

# --- Температура и сезон (раздел 12.3 мастер-плана) --------------------------------

func _find_season_mgr() -> Node:
	if not is_instance_valid(_season_mgr) and get_tree() and get_tree().root:
		_season_mgr = get_tree().root.find_child("SeasonManager", true, false)
	return _season_mgr

## Температура воздуха с учётом фазы суток, сезона и погоды, °C.
func get_ambient_temperature() -> int:
	var dc: Node = _find_day_cycle()
	var ambient: int = dc.get_ambient_temperature() if (dc and dc.has_method("get_ambient_temperature")) else 22
	if not is_instance_valid(_weather_mgr) and get_tree() and get_tree().root:
		_weather_mgr = get_tree().root.find_child("WeatherManager", true, false)
	if _weather_mgr and _weather_mgr.has_method("get_temperature_offset"):
		ambient += int(_weather_mgr.get_temperature_offset())
	return ambient

## Укрытие (дом) и источник тепла (печь, костёр) спасают от холода и сушат.
func _is_warm_sheltered() -> bool:
	if not is_instance_valid(_house) and get_tree() and get_tree().root:
		_house = get_tree().root.find_child("RepairableHouse", true, false)
	if _house and "current_stage" in _house and _house.current_stage >= 1:
		if global_position.distance_to(_house.global_position) < 5.2:
			return true
	return is_near_heat()

## Ближайший источник тепла (печь-плавильня, костёр) в пределах dry_rate_near_fire.
## Печи и костры помечаются группой heat_sources.
func is_near_heat() -> bool:
	if not is_instance_valid(_smelter) and get_tree() and get_tree().root:
		_smelter = get_tree().root.find_child("Smelter", true, false)
	if _smelter and global_position.distance_to(_smelter.global_position) < 4.2:
		return true
	if get_tree():
		for source in get_tree().get_nodes_in_group("heat_sources"):
			if is_instance_valid(source) and source.has_method("is_lit") and not source.is_lit():
				continue
			if is_instance_valid(source) and global_position.distance_to(source.global_position) < 4.2:
				return true
	return false

## Насколько персонаж мёрзнет, 0..1 (для подсказок и HUD).
func get_cold_exposure() -> float:
	if _is_warm_sheltered():
		return 0.0
	var ambient: int = get_ambient_temperature()
	if ambient >= cold_threshold_temperature:
		return 0.0
	var severity: float = (cold_threshold_temperature - float(ambient)) / 10.0
	# Мокрая одежда отводит тепло намного быстрее сухой.
	severity *= 1.0 + wetness / 100.0
	var sm := _find_season_mgr()
	if sm and sm.has_method("get_cold_damage_multiplier"):
		severity *= float(sm.get_cold_damage_multiplier())
	return clampf(severity, 0.0, 3.0)

## Мороз на улице без дома и огня: -здоровье, метель ускоряет вдвое.
func _handle_temperature(delta: float) -> void:
	var exposure: float = get_cold_exposure()
	if exposure > 0.0:
		var damage: float = cold_damage_rate * exposure * delta
		health = max(0.0, health - damage)
		health_changed.emit(health, max_health)
		if not _cold_warned:
			_cold_warned = true
			notify("🥶 Холодно! Найдите дом или разожгите печь — здоровье уходит.")
		elif exposure >= 1.0 and not _freezing_warned:
			_freezing_warned = true
			notify("❄️ Вы сильно мёрзнете! Здоровье падает — срочно к огню!")
	else:
		_cold_warned = false
		_freezing_warned = false

func consume_energy(amount: float) -> void:
	var mult: float = 1.0
	if wetness >= 80.0:
		mult = 1.5 # мокрая тяжелая одежда забирает больше сил
	elif wetness >= 40.0:
		mult = 1.25
	
	if hours_without_sleep >= critical_sleep_threshold:
		mult *= 1.6 # критическая бессонница
	elif hours_without_sleep >= sleep_deprivation_threshold:
		mult *= 1.35 # бессонница более суток
	
	energy = max(0.0, energy - amount * mult)
	energy_changed.emit(energy, max_energy)

func _handle_sleep_need(delta: float) -> void:
	if not is_instance_valid(_day_cycle) and get_tree() and get_tree().root:
		_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	
	var hours_increment: float = 0.0
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		hours_increment = _day_cycle.get_hours_per_second() * delta
	else:
		# Резервный расчет, если DayNightCycle не найден (600 сек на сутки = 0.04 ч/сек)
		hours_increment = (24.0 / 600.0) * delta
	
	hours_without_sleep += hours_increment
	
	var current_h_int: int = int(hours_without_sleep)
	if current_h_int >= 18 and _last_sleep_warning_hour < 18:
		_last_sleep_warning_hour = 18
		notify("🥱 Наваливается усталость. Пора подумать о сне (18+ ч без сна).")
	elif current_h_int >= 24 and _last_sleep_warning_hour < 24:
		_last_sleep_warning_hour = 24
		notify("⚠️ Вы не спали более суток! Регенерация сил заблокирована, скорость снижена.")
	elif current_h_int >= 36 and _last_sleep_warning_hour < 36:
		_last_sleep_warning_hour = 36
		notify("☠️ Критическое переутомление! Персонаж теряет здоровье от бессонницы.")
	
	if hours_without_sleep >= 48.0:
		_on_sleep_collapse()

func _on_sleep_collapse() -> void:
	notify("😵 Вы потеряли сознание от предельного переутомления (48 часов без сна)!")
	if not is_instance_valid(_house) and get_tree() and get_tree().root:
		_house = get_tree().root.find_child("RepairableHouse", true, false)
	var house_stage: int = _house.current_stage if (_house and "current_stage" in _house) else 0
	var dc: Node = _find_day_cycle()
	var overlay: Control = preload("res://scripts/ui/collapse_transition.gd").new()
	overlay.setup(self, dc, house_stage)
	get_tree().root.add_child(overlay)
	# Игровая логика ставится на паузу, пока splash визуализирует обморок.
	get_tree().paused = true
	energy = 30.0
	health = max(20.0, health - 25.0)
	energy_changed.emit(energy, max_energy)
	health_changed.emit(health, max_health)
	_exhaustion_damage_warned = false

func _handle_health(delta: float) -> void:
	var old_health: float = health
	
	# 1. Урон от критических потребностей и истощения
	var damage_rate: float = 0.0
	if thirst <= 0.0:
		damage_rate += 1.2 # Сильное обезвоживание
	if hunger <= 0.0:
		damage_rate += 0.8 # Голод
	if energy <= 0.0:
		damage_rate += exhaustion_damage_rate # Истощение сил
	if hours_without_sleep >= critical_sleep_threshold:
		damage_rate += 0.4 # Критическое переутомление от бессонницы (> 36 часов)

	if damage_rate > 0.0:
		if not _exhaustion_damage_warned:
			_exhaustion_damage_warned = true
			notify("⚠️ Истощение подтачивает здоровье! Нужны еда, вода и отдых.")
		health = max(0.0, health - damage_rate * delta)
		if health <= 0.0:
			_on_collapse("exhaustion")
	else:
		_exhaustion_damage_warned = false
		# 2. Пассивное восстановление здоровья (если сыт, утолил жажду, есть силы и нет депривации сна)
		if health < max_health and hunger >= 70.0 and thirst >= 70.0 and energy >= 40.0 and hours_without_sleep < sleep_deprivation_threshold:
			var regen_rate: float = 0.4
			health = min(max_health, health + regen_rate * delta)
	
	if abs(old_health - health) > 0.01:
		health_changed.emit(health, max_health)

func take_damage(amount: float, reason: String = "") -> void:
	if amount <= 0.0:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_on_collapse(reason)

func heal(amount: float) -> void:
	if amount <= 0.0 or health >= max_health:
		return
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)

func _on_collapse(reason: String = "") -> void:
	if reason == "exhaustion":
		notify("💀 Вы упали без сил от истощения...")
	else:
		notify("💀 Вы потеряли сознание...")

	# Штраф: часть ресурсов рассыпается кучкой у точки падения.
	# Кредиты и инструменты (belt‑items) не выбрасываются.
	_apply_collapse_penalty()

	if not is_instance_valid(_house) and get_tree() and get_tree().root:
		_house = get_tree().root.find_child("RepairableHouse", true, false)
	if _house:
		global_position = _house.global_position + Vector3(0.0, 0.5, 2.0)
	else:
		global_position = Vector3(0.0, 0.5, 0.0)
	velocity = Vector3.ZERO

	health = max(20.0, health - 25.0)
	energy = 30.0
	hours_without_sleep = 0.0
	_last_sleep_warning_hour = 0
	_exhaustion_damage_warned = false

	health_changed.emit(health, max_health)
	energy_changed.emit(energy, max_energy)
	thirst_changed.emit(thirst, max_thirst)
	hunger_changed.emit(hunger, max_hunger)

	# Переход через splash: утро к дому (stage ≥ 2) или окно поражения.
	var house_stage: int = _house.current_stage if (_house and "current_stage" in _house) else 0
	var dc: Node = _find_day_cycle()
	var overlay: Control = preload("res://scripts/ui/collapse_transition.gd").new()
	overlay.setup(self, dc, house_stage)
	get_tree().root.add_child(overlay)
	get_tree().paused = true

func _apply_collapse_penalty() -> void:
	if not inventory:
		return
	# Выбрасываем по 25 % от каждого ресурсного стека (не инструменты/снаряжение).
	var to_drop: Dictionary = {}
	var ids: Array = inventory.items.keys()
	for item_id in ids:
		if not inventory.item_uses_slots(item_id):
			continue
		var count: int = int(inventory.items[item_id])
		if count <= 0:
			continue
		var lose: int = maxi(1, int(count * 0.25))
		if lose <= 0:
			continue
		if inventory.remove_item(item_id, lose):
			to_drop[item_id] = lose
	for item_id in to_drop:
		DroppedItemScript.spawn(
			get_parent(), item_id, to_drop[item_id],
			global_position + Vector3(0.0, 0.3, 0.0)
		)
		notify("💀 Потеряно: %s ×%d" % [item_id, to_drop[item_id]])

func drink_water(amount: float = 40.0, is_clean: bool = true, energy_bonus: float = 0.0, health_bonus: float = 0.0) -> bool:
	# Обычное питьё при полной жажде не нужно; целебная вода пьётся ради здоровья.
	if thirst >= max_thirst and health_bonus <= 0.0:
		notify("💧 Вы пока не хотите пить (Жажда 100%).")
		return false

	thirst = min(max_thirst, thirst + amount)
	thirst_changed.emit(thirst, max_thirst)

	if energy_bonus > 0.0:
		energy = min(max_energy, energy + energy_bonus)
		energy_changed.emit(energy, max_energy)

	if health_bonus > 0.0:
		heal(health_bonus)

	if is_clean:
		notify("💧 Вы утолили жажду чистой водой! (+%d%% жажды, текущая: %d%%)" % [int(amount), int(thirst)])
	else:
		notify("⚠️ Вы выпили мутную сырую воду (+%d%% жажды, текущая: %d%%). Лучше фильтровать её!" % [int(amount), int(thirst)])
	AudioManager.play("drink")
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

	var item_data: Dictionary = ItemDB.get_item(target_item)
	# Целебные напитки пьют и при полной жажде — ради здоровья.
	if thirst >= max_thirst and float(item_data.get("health_bonus", 0.0)) <= 0.0:
		notify("💧 Вы пока не испытываете жажды (100%).")
		return false

	var rec: float = item_data.get("thirst_recovery", 30.0)
	var e_bon: float = item_data.get("energy_bonus", 0.0)
	var hp_bon: float = item_data.get("health_bonus", 0.0)
	var is_clean: bool = (target_item != "water")

	inventory.remove_item(target_item, 1)
	drink_water(rec, is_clean, e_bon, hp_bon)
	if hp_bon > 0.0:
		notify("🧪 Целебный настой затянул ссадины (+%d здоровья)." % int(hp_bon))
	return true

func eat_food(food_item_id: String) -> bool:
	if not inventory:
		return false
	if inventory.get_item_count(food_item_id) <= 0:
		notify("ℹ️ У вас нет этого продукта!")
		return false
	
	if hunger >= max_hunger and energy >= max_energy and health >= max_health:
		notify("🍽️ Вы не голодны и полны сил (Сытость 100%).")
		return false
	
	var item_data: Dictionary = ItemDB.get_item(food_item_id)
	var h_rec: float = item_data.get("hunger_recovery", 25.0)
	var e_rec: float = item_data.get("energy_bonus", 10.0)
	var t_rec: float = item_data.get("thirst_recovery", 0.0)
	var hp_rec: float = item_data.get("health_bonus", 10.0)
	var item_name: String = item_data.get("name", food_item_id)
	var item_icon: String = item_data.get("icon", "🍎")

	inventory.remove_item(food_item_id, 1)

	hunger = min(max_hunger, hunger + h_rec)
	hunger_changed.emit(hunger, max_hunger)

	if hp_rec > 0.0 and health < max_health:
		health = min(max_health, health + hp_rec)
		health_changed.emit(health, max_health)

	if e_rec > 0.0:
		energy = min(get_effective_max_energy(), energy + e_rec)
		energy_changed.emit(energy, max_energy)

	if t_rec > 0.0:
		thirst = min(max_thirst, thirst + t_rec)
		thirst_changed.emit(thirst, max_thirst)

	notify("%s Вы съели %s! (+%d%% сытости, текущая: %d%%)" % [item_icon, item_name, int(h_rec), int(hunger)])
	AudioManager.play("eat")
	return true

func eat_from_inventory(preferred_item_id: String = "") -> bool:
	if not inventory:
		return false
	
	var target_item: String = preferred_item_id
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		# Порядок перекуса: хлеб и овощи → огородные новинки и фрукты → ягоды
		# (лечебная облепиха — самой последней, чтобы не тратить лекарство).
		for it_id in ["bread", "potato", "carrot",
				"corn", "pumpkin", "cabbage", "bean", "onion", "tomato", "pepper",
				"apricot_pie", "dried_apricot", "apricot_compote",
				"sunflower_seeds", "herbs", "apple", "pear", "cherry", "apricot",
				"red_berry", "blue_berry", "blackberry", "sea_buckthorn"]:
			if inventory.get_item_count(it_id) > 0:
				target_item = it_id
				break
	
	if target_item == "" or inventory.get_item_count(target_item) <= 0:
		notify("ℹ️ В рюкзаке нет готовой еды для перекуса!")
		return false
	
	return eat_food(target_item)

func rest_in_bed(new_day: int = -1) -> void:
	hours_without_sleep = 0.0
	_last_sleep_warning_hour = 0
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	health = max_health
	health_changed.emit(health, max_health)
	if thirst < 35.0:
		thirst = 35.0
		thirst_changed.emit(thirst, max_thirst)
	if hunger < 35.0:
		hunger = 35.0
		hunger_changed.emit(hunger, max_hunger)
	wetness = 0.0
	wetness_changed.emit(wetness, max_wetness)
	if new_day > 0:
		notify("💤 Вы отлично выспались в тепле! Наступил День %d. Здоровье и энергия 100%%." % new_day)
	else:
		notify("💤 Вы отлично выспались и полностью восстановили силы! Здоровье и энергия 100%.")

# ---------------------------------------------------------------------------
# Отдых и сон (переход с ускорением времени, RestTransition)
# ---------------------------------------------------------------------------

## Запускает отдых на hours игровых часов (is_sleep — сон в кровати: к концу
## энергия и здоровье восстанавливаются полностью). В игре показывает переход
## с часами; в headless-режиме (тесты) применяет результат мгновенно.
func start_rest(hours: float, is_sleep: bool = false) -> void:
	if is_resting or hours <= 0.0:
		return
	var dc: Node = _find_day_cycle()
	if DisplayServer.get_name() == "headless" or dc == null or not dc.has_method("advance_hours"):
		if dc and dc.has_method("advance_hours"):
			dc.advance_hours(hours)
		_apply_rest_step(hours, hours, hours, is_sleep)
		_finish_rest(hours, is_sleep)
		return
	is_resting = true
	# Персонаж исчезает из мира на время отдыха/сна.
	visible = false
	# Переход рисуется поверх HUD (CanvasLayer выше слоя интерфейса).
	var layer := CanvasLayer.new()
	layer.layer = 128
	get_tree().root.add_child(layer)
	var overlay: Node = preload("res://scripts/ui/rest_transition.gd").new()
	overlay.setup(self, dc, hours, is_sleep)
	layer.add_child(overlay)
	overlay.tree_exited.connect(layer.queue_free)

func _find_day_cycle() -> Node:
	if not is_instance_valid(_day_cycle) and get_tree() and get_tree().root:
		_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	return _day_cycle

## Один шаг симуляции отдыха за hours игровых часов из total (elapsed — сколько
## часов отдыха уже прошло, включая этот шаг). Сон: энергия и здоровье к концу
## выходят на максимум; организм тратит воду и еду (во сне — медленнее),
## мокрая одежда сохнет в тепле дома.
func _apply_rest_step(hours: float, total: float, elapsed: float, is_sleep: bool) -> void:
	if hours <= 0.0:
		return
	var frac: float = clampf(elapsed / maxf(0.01, total), 0.0, 1.0)
	if is_sleep:
		var eff_max: float = get_effective_max_energy()
		energy = lerpf(energy, eff_max, frac)
		energy_changed.emit(energy, max_energy)
		if hunger >= 25.0 and thirst >= 25.0:
			health = lerpf(health, max_health, frac)
			health_changed.emit(health, max_health)
		hours_without_sleep = 0.0
		_last_sleep_warning_hour = 0
	else:
		# Короткий отдых восстанавливает силы слабее полноценного сна.
		energy = minf(get_effective_max_energy(), energy + 6.0 * hours)
		energy_changed.emit(energy, max_energy)
	# Расход сил переводим из игровых часов в реальные секунды по текущей
	# скорости суток (было захардкожено 60 с/ч): при изменённой длине часа
	# статы должны съедать столько же, сколько при обычной игре.
	var dc: Node = _find_day_cycle()
	var sec_per_hour: float = 60.0
	if dc and dc.has_method("get_seconds_per_game_hour"):
		sec_per_hour = float(dc.get_seconds_per_game_hour())
	# Во сне метаболизм замедляется: иначе за ночь сытость и жажда падали
	# в ноль, а после сна подпрыгивали до 35% — статус персонажа «баговал».
	var metabolism: float = 0.35 if is_sleep else 0.6
	thirst = maxf(0.0, thirst - thirst_decay_rate * sec_per_hour * hours * metabolism)
	thirst_changed.emit(thirst, max_thirst)
	hunger = maxf(0.0, hunger - hunger_decay_rate * sec_per_hour * hours * metabolism)
	hunger_changed.emit(hunger, max_hunger)
	wetness = maxf(0.0, wetness - dry_rate_sheltered * sec_per_hour * hours)
	wetness_changed.emit(wetness, max_wetness)

## Завершение отдыха: итоговое сообщение и автосохранение после сна.
func _finish_rest(actual_hours: float, is_sleep: bool) -> void:
	is_resting = false
	# Персонаж возвращается в мир.
	visible = true
	var hours_int: int = maxi(1, int(round(actual_hours)))
	if is_sleep:
		# Просыпаться полностью обессиленным нельзя: нижняя граница сытости
		# и жажды после сна — 20% (без прежнего прыжка «в ноль и сразу 35%»).
		if thirst < 20.0:
			thirst = 20.0
			thirst_changed.emit(thirst, max_thirst)
		if hunger < 20.0:
			hunger = 20.0
			hunger_changed.emit(hunger, max_hunger)
		var new_day: int = 0
		var dc: Node = _find_day_cycle()
		if dc and "current_day" in dc:
			new_day = int(dc.current_day)
		notify("💤 Вы отдыхали %d ч. Энергия: %d%%, здоровье: %d%%." % [hours_int, int(energy), int(health)])
		if new_day > 0:
			notify("🌅 Наступил День %d." % new_day)
		quick_save()
	else:
		notify("🛌 Вы отдыхали %d ч. Энергия: %d%%." % [hours_int, int(energy)])

func _check_bounds() -> void:
	if global_position.y < -5.0:
		global_position = Vector3(0.0, 0.5, 0.0)
		velocity = Vector3.ZERO

## Ввод проходит через unhandled_input: пробел в меню не запускает прыжок.
func _update_jump_input(delta: float) -> void:
	_landing_left = maxf(0.0, _landing_left - delta)
	if _is_gameplay_blocked() or is_resting or is_mining or is_digging or is_scooping:
		_jump_buffer = 0.0
		return
	if is_on_floor() and not is_jumping:
		_coyote_left = COYOTE_TIME
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)
	if _jump_buffer > 0.0 and _coyote_left > 0.0 and not is_jumping:
		velocity.y = jump_speed
		is_jumping = true
		_jump_elapsed = 0.0
		_landing_left = 0.0
		_jump_buffer = 0.0
		_coyote_left = 0.0
		current_anim = ""
		_update_character_animation()
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

func _update_jump_state(delta: float) -> void:
	if is_jumping:
		_jump_elapsed += delta
	if not is_on_floor():
		_air_elapsed += delta
	elif is_jumping or _air_elapsed > 0.15:
		is_jumping = false
		_air_elapsed = 0.0
		_landing_left = 0.28
		current_anim = ""
	else:
		_air_elapsed = 0.0

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		velocity.y = max(velocity.y, -25.0)
	else:
		if velocity.y < 0:
			velocity.y = -0.1

func _handle_movement(delta: float) -> void:
	if is_mining or is_digging or is_scooping or is_resting:
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
	if not is_on_floor() or is_jumping or velocity.y > 0.0:
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

## Жила с копаемым блоком строго под курсором мыши (для удара мотыгой).
## Возвращает null без мыши/headless или если курсор не на копаемом блоке в досягаемости.
func _deposit_under_cursor() -> Area3D:
	for item in nearby_interactables:
		if not is_instance_valid(item) or not item.is_in_group("voxel_deposits"):
			continue
		if item.get("is_interactable") == false:
			continue
		if item.has_method("aim_at_cursor") and item.aim_at_cursor(self):
			return item
	return null

func trigger_tool_strike() -> void:
	if _is_gameplay_blocked():
		_strike_held = false
		_strike_buffered = false
		return
	if is_digging or is_scooping or is_jumping or _air_elapsed > 0.12:
		return
	if is_mining:
		# One queued click, only near recovery; never an unbounded click backlog.
		if _strike_duration - _strike_elapsed <= STRIKE_BUFFER_WINDOW:
			_strike_buffered = true
		return
	# Кучки с земли подбираются клавишей E: удар ЛКМ их игнорирует и бьёт инструментом.
	var current_is_pile: bool = is_instance_valid(current_interactable) and current_interactable.is_in_group("dropped_items")
	if is_instance_valid(current_interactable) and not current_is_pile and not _is_mining_resource(current_interactable):
		# Machines, traders and water don't need a tool-swing animation.
		current_interactable.interact(self)
		_strike_held = false
		return
	_strike_target = null if current_is_pile else (current_interactable if is_instance_valid(current_interactable) else null)
	if _current_tool_type() == "shovel":
		# Мотыга бьёт туда, куда указывает курсор мыши, а не по направлению взгляда.
		var cursor_hit: Area3D = _deposit_under_cursor()
		if is_instance_valid(cursor_hit):
			_strike_target = cursor_hit
	if is_instance_valid(_strike_target) and visual_root:
		var dir_to_target: Vector3 = _interaction_point(_strike_target) - global_position
		dir_to_target.y = 0.0
		if dir_to_target.length_squared() > 0.001:
			if _current_tool_type() == "shovel" and _strike_target.is_in_group("voxel_deposits"):
				# Мотыга всегда доворачивается к курсору — даже через спину.
				visual_root.rotation.y = atan2(-dir_to_target.x, -dir_to_target.z)
			else:
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
## топора/мотыги/ведра. Кирка уже заскинена в модели персонажа — используем её узел.
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
	hoe_grip = HoeGripModifier.new()
	hoe_grip.name = "HoeTwoHandGrip"
	hoe_grip.player = self
	skeleton.add_child(hoe_grip)

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
## соответствующий экипированному слоту, и остаётся видимым в покое/ходьбе.
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
		# Работа с грунтом всегда мотыгой, даже если выбран другой инструмент.
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
	elif t in ["axe", "pickaxe", "shovel"]:
		# Экипированный инструмент остаётся в руке и после удара.
		equipped_tool_nodes[t].visible = true

func _update_character_animation() -> void:
	if not anim_player or is_mining or is_digging or is_scooping:
		return
	if is_jumping:
		play_character_anim("jump_start" if _jump_elapsed < 0.20 else "jump_loop")
		anim_player.speed_scale = 6.7 if _jump_elapsed < 0.20 else 1.0
		return
	if _air_elapsed > 0.12:
		play_character_anim("jump_loop")
		anim_player.speed_scale = 1.0
		return
	if _landing_left > 0.0:
		play_character_anim("jump_land")
		anim_player.speed_scale = 4.5
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
	if logical_name == "dig" and anim_player and anim_player.has_animation("tools/hoe_dig"):
		return "tools/hoe_dig"
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

## Работа мотыгой: поза dig (fallback — mine), в руке мотыга с двуручным хватом.
## Возвращает false, если персонаж занят другим действием.
func play_dig_animation(target: Node3D = null) -> bool:
	if is_mining or is_digging or is_scooping or is_resting or is_jumping or _air_elapsed > 0.12 or _is_gameplay_blocked():
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
## Звук шагов по пройденной дистанции: трава на земле, «грунт» на камне/постройках.
func _update_footsteps(delta: float) -> void:
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or h_speed < 0.6 or is_mining or is_digging or is_scooping:
		_step_distance = minf(_step_distance, FOOTSTEP_STRIDE * 0.5)
		return
	_step_distance += h_speed * delta
	if _step_distance < FOOTSTEP_STRIDE:
		return
	_step_distance = 0.0
	var on_grass := true
	for i in range(get_slide_collision_count()):
		var col: Object = get_slide_collision(i).get_collider()
		if col is Node and col.name != "Ground" and get_slide_collision(i).get_normal().y > 0.7:
			on_grass = false
			break
	var vol := -14.0 if h_speed < walk_speed + 0.5 else -11.0
	AudioManager.play("footstep_grass" if on_grass else "footstep_dirt", 1.0, vol)

func play_scoop_animation(source_pos: Vector3) -> bool:
	if is_mining or is_digging or is_scooping or is_resting or is_jumping or _air_elapsed > 0.12 or _is_gameplay_blocked():
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
		AudioManager.play("water_fill")
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
	AudioManager.play("swing", 1.0, -4.0)
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
		# Топор — chop; мотыга — двуручный hoe_dig; кирка — удар сверху mine,
		# но темп удара киркой — как удар топором по дереву.
		var tool_type: String = _current_tool_type()
		var swing_anim: String = _resolve_anim("dig" if tool_type == "shovel" else ("chop" if tool_type == "axe" else "mine"))
		if swing_anim != "":
			var timing: Array = _swing_timing(swing_anim)
			if tool_type == "pickaxe":
				timing = _pickaxe_timing()
			_strike_duration = timing[0]
			_strike_contact_time = timing[1]
			var swing: Animation = anim_player.get_animation(swing_anim)
			var play_speed: float = float(swing.length) / maxf(0.05, _strike_duration)
			current_anim = swing_anim
			anim_player.speed_scale = 1.0
			anim_player.play(swing_anim, 0.0, play_speed)
			# Apply the first raised-tool pose now, not on the next animation tick.
			anim_player.advance(0.0)

## Длительность замаха и момент контакта для клипа: метаданные contact_time/play_speed
## из запекания, иначе эвристика по длине. Возвращает [duration, contact_time].
func _swing_timing(anim_name: String) -> Array:
	var swing: Animation = anim_player.get_animation(anim_name)
	var swing_len: float = swing.length
	if swing.has_meta("contact_time"):
		# Запечённый клип: темп и момент контакта заданы в metadata
		# (tools/retarget_ual_to_miner.gd).
		var timed_speed: float = _anim_play_speed(anim_name, 1.0)
		return [swing_len / timed_speed, float(swing.get_meta("contact_time")) / timed_speed]
	# Длинный замах (1.5 c) играем ускоренно до ~1.0 c, контакт на 55% замаха.
	# Короткий замах старой модели (~0.42 c) — как есть, контакт на 38%.
	if swing_len >= STRIKE_LONG_ANIM_THRESHOLD:
		var duration: float = swing_len / STRIKE_LONG_ANIM_SPEED
		return [duration, duration * STRIKE_CONTACT_FRACTION_LONG]
	return [swing_len, swing_len * STRIKE_CONTACT_FRACTION_SHORT]

## Темп удара киркой: длительность замаха — как у топора по дереву (chop),
## а момент контакта — в той же фазе своего клипа, что у кирки (вспышка урона
## синхронна с приземлением головки, а не раньше/позже).
## Возвращает [duration, contact_time].
func _pickaxe_timing() -> Array:
	var chop_name: String = _resolve_anim("chop")
	var mine_name: String = _resolve_anim("mine")
	if chop_name == "" or mine_name == "":
		return _swing_timing(mine_name if mine_name != "" else chop_name)
	var chop_t: Array = _swing_timing(chop_name)
	var mine_t: Array = _swing_timing(mine_name)
	var frac: float = float(mine_t[1]) / maxf(0.05, float(mine_t[0]))
	return [float(chop_t[0]), float(chop_t[0]) * frac]

func notify(text: String) -> void:
	notification_received.emit(text)
