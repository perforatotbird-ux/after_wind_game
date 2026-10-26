class_name SolidFuelGenerator
extends "res://scripts/interaction/interactable.gd"

## Твердотопливный генератор электроэнергии базы.
## Дополнительный источник питания для энергосети (PowerGrid, группа power_generators).
## Работает на трёх видах твёрдого топлива с разной теплоотдачей и мощностью:
## * Древесина (wood) — 2.0 кВт, горит 30 с на 1 шт;
## * Уголь (coal) — 4.0 кВт, горит 75 с на 1 шт;
## * Топливные брикеты (fuel_briquette) — 6.0 кВт, горит 120 с на 1 шт.
## Имеет свой мини-инвентарь на 4 слота топлива (до 20 шт. в стеке).

signal generator_state_changed(is_running: bool, current_output: float)
signal fuel_slots_changed
signal generator_opened(generator: Node)

const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

## Характеристики топлива: мощность (кВт) и время горения 1 штуки (секунды).
const FUEL_PROPERTIES: Dictionary = {
	"wood": {
		"name": "Древесина",
		"power": 2.0,
		"burn_time": 30.0,
		"icon": "wood",
	},
	"coal": {
		"name": "Уголь",
		"power": 4.0,
		"burn_time": 75.0,
		"icon": "coal",
	},
	"fuel_briquette": {
		"name": "Топливный брикет",
		"power": 6.0,
		"burn_time": 120.0,
		"icon": "fuel_briquette",
	}
}

const VALID_FUELS: Array[String] = ["wood", "coal", "fuel_briquette"]
const FUEL_SLOT_COUNT: int = 4
const FUEL_SLOT_MAX_STACK: int = 20

@export var is_running: bool = false
@export var current_output: float = 0.0

@onready var status_light: OmniLight3D = get_node_or_null("StatusLight")

## 4 слота топлива: Array[Dictionary] вида {"item_id": String, "count": int}.
var fuel_slots: Array = []
var active_fuel_type: String = ""
var fuel_burn_left: float = 0.0
var fuel_burn_total: float = 0.0
var total_energy_produced: float = 0.0

var _flicker_timer: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group("power_generators")
	add_to_group("solid_generators")
	add_to_group("interactables")
	object_name = "Твердотопливный генератор"
	prompt_action = "Управление / Топливо"

	if not status_light:
		status_light = get_node_or_null("StatusLight")

	if fuel_slots.is_empty():
		for i in range(FUEL_SLOT_COUNT):
			fuel_slots.append({"item_id": "", "count": 0})

	_update_visuals()

func _process(delta: float) -> void:
	if is_running:
		if fuel_burn_left > 0.0:
			fuel_burn_left -= delta
			total_energy_produced += (current_output / 3600.0) * delta
			_apply_flicker(delta)
			if fuel_burn_left <= 0.0:
				fuel_burn_left = 0.0
				_try_consume_next_fuel()
		else:
			_try_consume_next_fuel()
	else:
		current_output = 0.0

	_update_visuals()

## Возвращает текущую генерацию в энергосеть базы (кВт).
func get_current_output() -> float:
	return current_output if is_running and fuel_burn_left > 0.0 else 0.0

## Запуск / остановка генератора.
func set_running(running: bool) -> bool:
	if is_running == running:
		return is_running

	if running:
		if fuel_burn_left > 0.0 or _has_any_fuel():
			is_running = true
			if fuel_burn_left <= 0.0:
				_try_consume_next_fuel()
			AudioManager.play("machine_start_0")
		else:
			is_running = false
			return false
	else:
		is_running = false
		current_output = 0.0
		AudioManager.play("machine_done_0")

	generator_state_changed.emit(is_running, current_output)
	_update_visuals()
	return is_running

func toggle_running() -> bool:
	return set_running(not is_running)

func start_generator() -> bool:
	return set_running(true)

func stop_generator() -> bool:
	set_running(false)
	return not is_running

## Взять следующее топливо из слотов по порядку (0..3).
func _try_consume_next_fuel() -> bool:
	for i in range(fuel_slots.size()):
		var slot: Dictionary = fuel_slots[i]
		var fid: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 0))
		if count > 0 and fid in VALID_FUELS:
			slot["count"] = count - 1
			if int(slot["count"]) <= 0:
				slot["item_id"] = ""
				slot["count"] = 0

			active_fuel_type = fid
			fuel_burn_total = float(FUEL_PROPERTIES[fid]["burn_time"])
			fuel_burn_left = fuel_burn_total
			current_output = float(FUEL_PROPERTIES[fid]["power"])

			fuel_slots_changed.emit()
			generator_state_changed.emit(is_running, current_output)
			return true

	# Топливо кончилось во всех слотах
	active_fuel_type = ""
	fuel_burn_left = 0.0
	fuel_burn_total = 0.0
	current_output = 0.0
	is_running = false
	generator_state_changed.emit(is_running, current_output)
	return false

func _has_any_fuel() -> bool:
	for slot in fuel_slots:
		if int(slot.get("count", 0)) > 0 and str(slot.get("item_id", "")) in VALID_FUELS:
			return true
	return false

## Добавить топливо в мини-инвентарь генератора.
## Возвращает количество реально добавленных предметов.
func add_fuel(item_id: String, amount: int) -> int:
	if not item_id in VALID_FUELS or amount <= 0:
		return 0

	var remaining: int = amount

	# 1. Сначала докладываем в существующие слоты с тем же топливом
	for slot in fuel_slots:
		if slot.get("item_id") == item_id:
			var cur: int = int(slot.get("count", 0))
			var space: int = FUEL_SLOT_MAX_STACK - cur
			if space > 0:
				var to_add: int = mini(remaining, space)
				slot["count"] = cur + to_add
				remaining -= to_add
				if remaining <= 0:
					break

	# 2. Затем занимаем пустые слоты
	if remaining > 0:
		for slot in fuel_slots:
			if str(slot.get("item_id", "")).is_empty() or int(slot.get("count", 0)) <= 0:
				var to_add: int = mini(remaining, FUEL_SLOT_MAX_STACK)
				slot["item_id"] = item_id
				slot["count"] = to_add
				remaining -= to_add
				if remaining <= 0:
					break

	var added: int = amount - remaining
	if added > 0:
		fuel_slots_changed.emit()
		# Если генератор был запущен, но стоял из-за отсутствия топлива — поджигаем
		if is_running and fuel_burn_left <= 0.0:
			_try_consume_next_fuel()

	return added

## Заправить генератор топливом указанного типа из инвентаря игрока.
func add_fuel_from_inventory(inv: Node, item_id: String, max_amount: int = -1) -> int:
	if inv == null or not item_id in VALID_FUELS:
		return 0

	var available: int = inv.get_item_count(item_id) if inv.has_method("get_item_count") else 0
	if available <= 0:
		return 0

	var wanted: int = available if max_amount <= 0 else mini(available, max_amount)
	var added: int = add_fuel(item_id, wanted)
	if added > 0 and inv.has_method("remove_item"):
		inv.remove_item(item_id, added)
	return added

## Забрать топливо из слота генератора в инвентарь игрока.
func take_fuel_to_inventory(slot_idx: int, inv: Node, count: int = -1) -> int:
	if inv == null or slot_idx < 0 or slot_idx >= fuel_slots.size():
		return 0

	var slot: Dictionary = fuel_slots[slot_idx]
	var fid: String = str(slot.get("item_id", ""))
	var cur: int = int(slot.get("count", 0))
	if fid.is_empty() or cur <= 0:
		return 0

	var to_take: int = cur if count <= 0 else mini(cur, count)
	var added: bool = inv.add_item(fid, to_take) if inv.has_method("add_item") else false
	if added:
		slot["count"] = cur - to_take
		if int(slot["count"]) <= 0:
			slot["item_id"] = ""
			slot["count"] = 0
		fuel_slots_changed.emit()
		return to_take
	return 0

## Забрать всё топливо из всех слотов генератора в рюкзак.
func take_all_fuel_to_inventory(inv: Node) -> int:
	if inv == null:
		return 0
	var total: int = 0
	for i in range(fuel_slots.size()):
		total += take_fuel_to_inventory(i, inv)
	return total

## Извлечь всё топливо и очистить слоты (возвращает список извлечённого).
func take_all_fuel() -> Array[Dictionary]:
	var extracted: Array[Dictionary] = []
	for slot in fuel_slots:
		var fid: String = str(slot.get("item_id", ""))
		var cnt: int = int(slot.get("count", 0))
		if not fid.is_empty() and cnt > 0:
			extracted.append({"item_id": fid, "count": cnt})
		slot["item_id"] = ""
		slot["count"] = 0
	fuel_slots_changed.emit()
	return extracted

func get_total_fuel_count() -> int:
	var s: int = 0
	for slot in fuel_slots:
		s += int(slot.get("count", 0))
	return s

## Суммарное оставшееся время горения всего загруженного топлива (секунды).
func get_total_fuel_burn_time() -> float:
	var total: float = fuel_burn_left
	for slot in fuel_slots:
		var fid: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 0))
		if fid in FUEL_PROPERTIES and count > 0:
			total += float(FUEL_PROPERTIES[fid]["burn_time"]) * count
	return total

func _apply_flicker(delta: float) -> void:
	if not status_light:
		return
	_flicker_timer += delta * 12.0
	var base_energy: float = 1.3 + sin(_flicker_timer) * 0.2 + sin(_flicker_timer * 2.3) * 0.1
	status_light.light_energy = maxf(0.5, base_energy)

func _update_visuals() -> void:
	if not status_light:
		return
	if is_running and fuel_burn_left > 0.0:
		status_light.light_color = Color(1.0, 0.55, 0.18, 1.0) # Огонь топки
	elif _has_any_fuel():
		status_light.light_color = Color(0.3, 0.9, 0.35, 1.0) # Готов к запуску
		status_light.light_energy = 0.8
	else:
		status_light.light_color = Color(0.85, 0.2, 0.2, 1.0) # Нет топлива
		status_light.light_energy = 0.5

func get_prompt() -> String:
	var status_text: String
	if is_running and fuel_burn_left > 0.0:
		var fuel_name: String = FUEL_PROPERTIES.get(active_fuel_type, {}).get("name", "Топливо")
		status_text = "Работает (%.1f кВт, %s: %.0f с)" % [current_output, fuel_name, fuel_burn_left]
	elif _has_any_fuel():
		status_text = "Остановлен (топливо есть: %d шт)" % get_total_fuel_count()
	else:
		status_text = "Нет топлива"
	return "[E] %s: %s" % [object_name, status_text]

func _on_interacted(player_node: Node) -> void:
	generator_opened.emit(self)

# --- Сериализация состояния для сохранения игры ---

func get_save_state() -> Dictionary:
	var clean_slots: Array = []
	for slot in fuel_slots:
		clean_slots.append({
			"item_id": str(slot.get("item_id", "")),
			"count": int(slot.get("count", 0))
		})
	return {
		"is_running": is_running,
		"active_fuel_type": active_fuel_type,
		"fuel_burn_left": fuel_burn_left,
		"fuel_burn_total": fuel_burn_total,
		"current_output": current_output,
		"total_energy_produced": total_energy_produced,
		"fuel_slots": clean_slots
	}

func apply_save_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	is_running = bool(data.get("is_running", false))
	active_fuel_type = str(data.get("active_fuel_type", ""))
	fuel_burn_left = maxf(0.0, float(data.get("fuel_burn_left", 0.0)))
	fuel_burn_total = maxf(0.0, float(data.get("fuel_burn_total", 0.0)))
	current_output = maxf(0.0, float(data.get("current_output", 0.0)))
	total_energy_produced = maxf(0.0, float(data.get("total_energy_produced", 0.0)))

	fuel_slots.clear()
	var saved_slots = data.get("fuel_slots", [])
	for i in range(FUEL_SLOT_COUNT):
		if i < saved_slots.size():
			var s = saved_slots[i]
			var fid = str(s.get("item_id", ""))
			var cnt = int(s.get("count", 0))
			if fid in VALID_FUELS and cnt > 0:
				fuel_slots.append({"item_id": fid, "count": cnt})
			else:
				fuel_slots.append({"item_id": "", "count": 0})
		else:
			fuel_slots.append({"item_id": "", "count": 0})

	if is_running and fuel_burn_left > 0.0 and active_fuel_type in FUEL_PROPERTIES:
		current_output = float(FUEL_PROPERTIES[active_fuel_type]["power"])

	_update_visuals()
