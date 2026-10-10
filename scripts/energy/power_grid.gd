class_name PowerGrid
extends Node

## Энергосеть базы (Разделы 54, 57, 84 дизайн-документа)
## Координирует выработку (ветряк), накопление (аккумуляторы) и потребление (фонари, приборы).

signal grid_updated(stored: float, capacity: float, generation: float, consumption: float, has_power: bool)

@export var max_capacity: float = 100.0
@export var current_stored: float = 30.0 # Начальный заряд 30 кВт·ч

var current_generation: float = 0.0
var current_consumption: float = 0.0
var has_power: bool = true

var _generators: Array[Node] = []
var _consumers: Array[Node] = []
var _batteries: Array[Node] = []

var _last_emitted_stored: float = -1.0
var _last_emitted_gen: float = -1.0
var _last_emitted_con: float = -1.0
var _last_emitted_has_power: bool = false
var _last_consumer_has_power: Variant = null

func _ready() -> void:
	# Ветряк, батарея и фонари добавляются в группы в своих _ready, которые идут
	# после сети (она выше в сцене): сканируем, когда весь мир готов.
	_scan_grid_devices()
	_update_grid(0.0)
	_rescan_when_ready.call_deferred()

func _rescan_when_ready() -> void:
	_scan_grid_devices()
	_update_grid(0.0)

func _process(delta: float) -> void:
	_update_grid(delta)

func _scan_grid_devices() -> void:
	var world = get_parent()
	if not world:
		return
	_generators.clear()
	_consumers.clear()
	_batteries.clear()
	_last_consumer_has_power = null
	for child in world.find_children("*", "", true, false):
		if child.is_in_group("power_generators") and not _generators.has(child):
			_generators.append(child)
		if child.is_in_group("power_consumers") and not _consumers.has(child):
			_consumers.append(child)
		if child.is_in_group("power_batteries") and not _batteries.has(child):
			_batteries.append(child)

func register_generator(gen: Node) -> void:
	if gen and not _generators.has(gen):
		_generators.append(gen)

func register_consumer(con: Node) -> void:
	if con and not _consumers.has(con):
		_consumers.append(con)
		if con.has_method("set_powered"):
			con.set_powered(has_power)

func register_battery(bat: Node) -> void:
	if bat and not _batteries.has(bat):
		_batteries.append(bat)

func _update_grid(delta: float) -> void:
	# 1. Расчет генерации
	var gen_sum: float = 0.0
	for gen in _generators:
		if is_instance_valid(gen) and gen.has_method("get_current_output"):
			gen_sum += gen.get_current_output()
	current_generation = gen_sum

	# 2. Расчет емкости батарей
	var cap_sum: float = 0.0
	for bat in _batteries:
		if is_instance_valid(bat) and "capacity" in bat:
			cap_sum += bat.capacity
	if cap_sum > 0.0:
		max_capacity = cap_sum

	# 3. Расчет потребления
	var con_sum: float = 0.0
	for con in _consumers:
		if is_instance_valid(con) and con.has_method("get_power_demand"):
			con_sum += con.get_power_demand()
	current_consumption = con_sum

	# 4. Баланс мощности
	var net: float = current_generation - current_consumption
	if delta > 0.0:
		if net > 0.0:
			current_stored = min(max_capacity, current_stored + net * delta)
		elif net < 0.0:
			current_stored = max(0.0, current_stored + net * delta)
	
	has_power = (current_generation >= current_consumption) or (current_stored > 0.05)

	# 5. Уведомление потребителей (только при изменении статуса питания)
	if _last_consumer_has_power != has_power:
		_last_consumer_has_power = has_power
		for con in _consumers:
			if is_instance_valid(con) and con.has_method("set_powered"):
				con.set_powered(has_power)
	
	# 6. Уведомление батарей
	for bat in _batteries:
		if is_instance_valid(bat) and bat.has_method("update_charge_display"):
			bat.update_charge_display(current_stored, max_capacity, net)

	var changed: bool = (absf(current_stored - _last_emitted_stored) >= 0.05
		or absf(current_generation - _last_emitted_gen) >= 0.05
		or absf(current_consumption - _last_emitted_con) >= 0.05
		or has_power != _last_emitted_has_power
		or delta == 0.0)
	if changed:
		_last_emitted_stored = current_stored
		_last_emitted_gen = current_generation
		_last_emitted_con = current_consumption
		_last_emitted_has_power = has_power
		grid_updated.emit(current_stored, max_capacity, current_generation, current_consumption, has_power)

func get_power_status_text() -> String:
	var net: float = current_generation - current_consumption
	var pct: int = int((current_stored / max_capacity) * 100.0) if max_capacity > 0.001 else 0
	var sign_str: String = "+" if net >= 0 else ""
	return "⚡ %d%% (%s%.1f кВт)" % [pct, sign_str, net]
