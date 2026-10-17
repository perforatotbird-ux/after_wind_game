class_name WindTurbine
extends "res://scripts/interaction/interactable.gd"

## Ветроэлектрогенератор базы (Разделы 54, 57, 84 дизайн-документа).
##
## Выработка считается не «по погоде», а по фактической силе ветра из
## WindSystem (группа `wind_system`):
##   * ниже cut-in (3 м/с) — полное затишье, ротор стоит, выработки нет;
##   * от cut-in до номинала (13 м/с) — кубический рост мощности (физика
##     ветроколеса): вдвое сильнее ветер → вчетверо больше энергии;
##   * номинал (5.5 кВт) держится до cut-out (24 м/с);
##   * выше cut-out — аварийная защита: ротор останавливается, выработки нет.
##
## Машина изнашивается пропорционально времени активной работы под нагрузкой
## (MachineWear): изношенный ветряк теряет КПД, полностью убитый — не даёт тока
## до ремонта. Ремонт — [E]: детали вносятся из рюкзака частями, при полном
## комплекте состояние восстанавливается на 100 %.
##
## Вращает узел ротора Rotor_3_Blades_SPIN (запечённая анимация GLB отключена:
## оборотами управляет скрипт по силе ветра).

const MachineWearScript = preload("res://scripts/crafting/machine_wear.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const WindSystemScript = preload("res://scripts/world/wind_system.gd")

signal turbine_state_changed(state: int)

## Состояния машины для интерфейса и статус-света.
enum TurbineState { IDLE, RUNNING, WORN, PROTECTED, BROKEN }

## Ветер, ниже которого ротор не крутится (м/с).
const CUT_IN_WIND: float = 3.0
## Ветер, при котором достигается номинальная мощность (м/с).
const RATED_WIND: float = 13.0
## Ветер, выше которого ветряк уходит в защиту (м/с).
const CUT_OUT_WIND: float = 24.0
## Обороты ротора на 1 м/с ветра и предел оборотов (об/мин).
const ROTOR_RPM_PER_MS: float = 4.0
const ROTOR_MAX_RPM: float = 60.0
## Износ за игровой час активной работы при полной нагрузке (в % состояния).
const WEAR_PER_ACTIVE_HOUR: float = 0.8
## Множитель износа в грозу/ураган (повышенные нагрузки на вал и редуктор).
const STORM_WEAR_MULT: float = 1.5
## Потеря выработки у изношенной машины (состояние ≤ 50 %).
const WORN_OUTPUT_MULT: float = 0.75
## Детали для ремонта (вносятся частями из рюкзака).
const DEFAULT_REPAIR_COST: Dictionary = {"gear": 1, "iron_plate": 2, "bolt": 4}

@export var base_output: float = 5.5
@export var is_operational: bool = true
@export var wear_per_active_hour: float = WEAR_PER_ACTIVE_HOUR
@export var repair_cost: Dictionary = DEFAULT_REPAIR_COST

@onready var rotor_node: Node3D = get_node_or_null("TurbineHead/Rotor_3_Blades_SPIN")
@onready var status_light: OmniLight3D = get_node_or_null("StatusLight")

var wear: MachineWearScript
var _wind_sys: Node = null
var _season_mgr: Node = null
var _delivered: Dictionary = {}
var _notified_worn: bool = false
var _notified_broken: bool = false
var _last_state: int = TurbineState.IDLE

func _ready() -> void:
	super._ready()
	add_to_group("power_generators")
	object_name = "Ветрогенератор"
	prompt_action = "Осмотреть"
	if not rotor_node:
		rotor_node = get_node_or_null("TurbineHead/Rotor_3_Blades_SPIN")
	if not rotor_node:
		rotor_node = get_node_or_null("Rotor")
	if not status_light:
		status_light = get_node_or_null("StatusLight")
	wear = MachineWearScript.new()
	wear.max_condition = 100.0
	wear.condition = 100.0
	_disable_baked_animation()

## GLB приходит с готовой анимацией «Rotor_Spin_4s_Linear»: оборотами
## управляет скрипт, поэтому запечённую дорожку глушим.
func _disable_baked_animation() -> void:
	for node in find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		if ap:
			ap.stop()
			ap.active = false

func _process(delta: float) -> void:
	if wear == null:
		return
	_update_wear(delta)
	_spin_rotor(delta)
	_update_status_light()
	_update_notifications()
	_emit_state()

# --- Ветер и выработка ---------------------------------------------------------

## Система ветра мира (если её нет — берём базовую скорость текущей погоды).
func get_wind_system() -> Node:
	if _wind_sys == null or not is_instance_valid(_wind_sys):
		var tree := get_tree()
		_wind_sys = tree.get_first_node_in_group(WindSystemScript.GROUP) if tree else null
	return _wind_sys

func get_wind_speed() -> float:
	var wind_sys := get_wind_system()
	if wind_sys and wind_sys.has_method("get_wind_speed"):
		return float(wind_sys.get_wind_speed())
	# Запасной путь для сцен без WindSystem: база погоды как есть.
	var weather_mgr := _get_weather_manager()
	if weather_mgr and "current_weather" in weather_mgr:
		return float(WindSystemScript.WEATHER_BASE_WIND.get(int(weather_mgr.current_weather), 2.0))
	return 0.0

## Доля номинальной мощности по силе ветра: 0 — затишье/защита, 1 — номинал.
func get_wind_factor() -> float:
	var wind: float = get_wind_speed()
	if wind < CUT_IN_WIND or wind > CUT_OUT_WIND:
		return 0.0
	if wind >= RATED_WIND:
		return 1.0
	var t: float = (wind - CUT_IN_WIND) / (RATED_WIND - CUT_IN_WIND)
	return t * t * t

func get_current_output() -> float:
	if not is_operational or wear == null or wear.is_broken():
		return 0.0
	return base_output * get_wind_factor() * get_condition_output_mult()

func get_condition_output_mult() -> float:
	if wear == null:
		return 1.0
	if wear.is_broken():
		return 0.0
	return WORN_OUTPUT_MULT if wear.is_worn() else 1.0

func get_state() -> int:
	if wear == null:
		return TurbineState.IDLE
	if wear.is_broken():
		return TurbineState.BROKEN
	if not is_operational or get_wind_speed() < CUT_IN_WIND:
		return TurbineState.IDLE
	if get_wind_speed() > CUT_OUT_WIND:
		return TurbineState.PROTECTED
	return TurbineState.WORN if wear.is_worn() else TurbineState.RUNNING

func get_state_text() -> String:
	match get_state():
		TurbineState.RUNNING: return "Работает"
		TurbineState.WORN: return "Изношен — КПД снижен"
		TurbineState.PROTECTED: return "Защита: штормовой ветер"
		TurbineState.BROKEN: return "Сломан — нужен ремонт"
		_: return "Простаивает (затишье)"

func get_prompt() -> String:
	if needs_repair():
		return "[E] Ремонт ветряка (%d%%)" % int(round(wear.get_ratio() * 100.0))
	return "[E] %s (%s)" % [prompt_action, object_name]

## Ремонт предлагается только когда он осмыслен: машина износилась/сломалась
## или детали уже начали вносить. Иначе [E] — осмотр (иначе подсказка «Ремонт»
## висела бы с первых минут игры на 99 %).
func needs_repair() -> bool:
	if wear == null:
		return false
	if wear.get_ratio() <= MachineWearScript.WORN_RATIO:
		return true
	return not _delivered.is_empty()

# --- Ротор, износ, свет --------------------------------------------------------

func _current_rpm() -> float:
	if get_state() == TurbineState.BROKEN or get_state() == TurbineState.IDLE or get_state() == TurbineState.PROTECTED:
		return 0.0
	return minf(ROTOR_MAX_RPM, get_wind_speed() * ROTOR_RPM_PER_MS)

func _spin_rotor(delta: float) -> void:
	var rpm: float = _current_rpm()
	if rotor_node == null or rpm <= 0.0:
		return
	rotor_node.rotate_object_local(Vector3(0.0, 0.0, 1.0), rpm * TAU / 60.0 * delta)

func _update_wear(delta: float) -> void:
	if not is_operational or wear.is_broken():
		return
	var factor: float = get_wind_factor()
	if factor <= 0.0:
		return
	var hours: float = delta * _hours_per_second()
	var load: float = 0.4 + 0.6 * factor
	wear.add_wear(wear_per_active_hour * hours * load * _event_wear_mult())

## Реальных секунд в одном игровом часе.
func _hours_per_second() -> float:
	var tree := get_tree()
	if tree:
		var dc: Node = tree.get_first_node_in_group("day_night_cycle")
		if dc and dc.has_method("get_hours_per_second"):
			return maxf(0.0001, float(dc.get_hours_per_second()))
	if _season_mgr == null or not is_instance_valid(_season_mgr):
		_season_mgr = tree.get_first_node_in_group("season_manager") if tree else null
	if _season_mgr and _season_mgr.has_method("get_hours_per_second"):
		return maxf(0.0001, float(_season_mgr.get_hours_per_second()))
	return 1.0 / 60.0

func _event_wear_mult() -> float:
	var tree := get_tree()
	if tree == null:
		return 1.0
	if _season_mgr == null or not is_instance_valid(_season_mgr):
		_season_mgr = tree.get_first_node_in_group("season_manager")
	if _season_mgr == null or not _season_mgr.has_method("get_active_event"):
		return 1.0
	var event: String = str(_season_mgr.get_active_event())
	return STORM_WEAR_MULT if (event == "storm" or event == "hurricane") else 1.0

func _update_status_light() -> void:
	if status_light == null:
		return
	var color: Color
	var energy: float = 1.0
	match get_state():
		TurbineState.RUNNING:
			color = Color(0.35, 0.95, 0.45)
		TurbineState.WORN:
			color = Color(0.95, 0.7, 0.2)
		TurbineState.PROTECTED:
			color = Color(0.95, 0.35, 0.2)
			energy = 0.8
		TurbineState.BROKEN:
			color = Color(0.95, 0.15, 0.15)
			energy = 0.6
		_:
			color = Color(0.6, 0.65, 0.7)
			energy = 0.15
	status_light.light_color = color
	status_light.light_energy = energy

func _emit_state() -> void:
	var state: int = get_state()
	if state != _last_state:
		_last_state = state
		turbine_state_changed.emit(state)

func _update_notifications() -> void:
	if wear.is_broken():
		if not _notified_broken:
			_notified_broken = true
			_notified_worn = true
			_notify("⛔ Ветряк сломан — выработки нет. Нужен ремонт деталями ([E]).")
	elif wear.is_worn():
		if not _notified_worn:
			_notified_worn = true
			_notify("🛠 Ветряк изношен (%d%%) — выработка снижена, пора чинить ([E])." % int(round(wear.get_ratio() * 100.0)))

func _notify(text: String) -> void:
	var player := _get_player()
	if player and player.has_method("notify"):
		player.notify(text)

func _get_weather_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("weather_manager")

func _get_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player = tree.get_first_node_in_group("player")
	if player == null and get_parent():
		player = get_parent().find_child("Player", true, false)
	return player

# --- Взаимодействие: осмотр и ремонт -------------------------------------------

func _on_interacted(player: Node) -> void:
	if wear == null:
		return
	if needs_repair():
		_contribute_repair(player)
	else:
		_report_status(player)

## Вносит детали из рюкзака (по частям) и ремонтирует при полном комплекте.
func _contribute_repair(player: Node) -> bool:
	var inv = player.get("inventory") if player and "inventory" in player else null
	if inv == null:
		if player and player.has_method("notify"):
			player.notify("❌ Инвентарь игрока недоступен.")
		return false

	var brought: Array[String] = []
	for item_id in repair_cost.keys():
		var need: int = int(repair_cost[item_id]) - int(_delivered.get(item_id, 0))
		if need <= 0:
			continue
		var take: int = mini(need, int(inv.get_item_count(str(item_id))))
		if take > 0 and inv.remove_item(str(item_id), take):
			_delivered[item_id] = int(_delivered.get(item_id, 0)) + take
			brought.append("%s ×%d" % [ItemDB.get_item_name(str(item_id)), take])

	if not _repair_ready():
		if player and player.has_method("notify"):
			var msg: String = "📦 Внесено в «%s»" % object_name
			msg += (": " + ", ".join(brought) if not brought.is_empty() else "")
			var still: PackedStringArray = []
			for item_id in repair_cost.keys():
				var have: int = int(_delivered.get(item_id, 0))
				var need: int = int(repair_cost[item_id])
				if have < need:
					still.append("%s %d/%d" % [ItemDB.get_item_name(str(item_id)), have, need])
			if not still.is_empty():
				msg += ". Осталось: " + ", ".join(still)
			player.notify(msg)
		return false

	# Комплект собран — ремонт восстанавливает состояние полностью.
	wear.set_condition(wear.max_condition)
	_delivered.clear()
	_notified_worn = false
	_notified_broken = false
	AudioManager.play("build")
	if player and player.has_method("notify"):
		player.notify("🔧 Ветряк отремонтирован — выработка восстановлена (100 %).")
	return true

func _repair_ready() -> bool:
	for item_id in repair_cost.keys():
		if int(_delivered.get(item_id, 0)) < int(repair_cost[item_id]):
			return false
	return true

## Полный отчёт о машине: состояние, ветер, выработка, износ.
func get_status_text() -> String:
	var wind_sys := get_wind_system()
	var wind_text: String = wind_sys.get_status_text() if wind_sys and wind_sys.has_method("get_status_text") else "💨 Ветер: %.1f м/с" % get_wind_speed()
	var state: String = get_state_text()
	if get_state() == TurbineState.BROKEN or get_state() == TurbineState.IDLE or get_state() == TurbineState.PROTECTED:
		return "⚡ Ветрогенератор: %s. %s. Состояние: %s" % [state, wind_text, wear.get_status_text()]
	return "⚡ Ветрогенератор: %s, выработка %.2f кВт. %s. Состояние: %s" % [state, get_current_output(), wind_text, wear.get_status_text()]

func _report_status(player: Node) -> void:
	if player and player.has_method("notify"):
		player.notify(get_status_text())

# --- Сохранение ----------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {"condition": wear.condition if wear else 100.0, "delivered": _delivered.duplicate()}

func apply_save_state(state: Dictionary) -> void:
	if wear == null:
		return
	wear.set_condition(float(state.get("condition", wear.max_condition)))
	var delivered: Variant = state.get("delivered", {})
	_delivered = (delivered as Dictionary).duplicate() if delivered is Dictionary else {}
	_notified_worn = wear.is_worn()
	_notified_broken = wear.is_broken()
