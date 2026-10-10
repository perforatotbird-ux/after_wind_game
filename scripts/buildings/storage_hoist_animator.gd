extends Node3D
## Ручной подъёмник логистического комплекса (узел Visuals/Stage3/HoistAnimator в
## scenes/buildings/repairable_storage.tscn). Работник «крутит» рукоять: шестерня-рукоятка
## вращает большую шестерню с барабаном, цепь укорачивается, и ящик с поддона поднимается,
## висит, покачиваясь на цепи, и опускается обратно. Цикл повторяется, пока стадия видна.

## Длительность полного цикла, с: покой → подъём → вис → спуск → покой.
@export var cycle_time: float = 12.0
## Высота подъёма ящика, м.
@export var lift_height: float = 0.45
## Радиус барабана лебёдки, м (угол шестерни = подъём / радиус).
@export var drum_radius: float = 0.06
## Передаточное число: большая шестерня / шестерня-рукоятка.
@export var gear_ratio: float = 2.83
## Амплитуда раскачивания груза, рад.
@export var sway_amplitude: float = 0.05

var time: float = 0.0
var lift: float = 0.0
var gear_angle: float = 0.0
var sway: float = 0.0

var _gear: Node3D
var _crank: Node3D
var _chain: Node3D
var _hook: Node3D
var _chain_len: float = 1.0

func _ready() -> void:
	var stage: Node = get_parent()
	_gear = stage.get_node_or_null("Gear")
	_crank = stage.get_node_or_null("Crank")
	_chain = stage.get_node_or_null("Chain")
	_hook = stage.get_node_or_null("Hook")
	if _chain and _hook:
		_chain_len = maxf(0.2, _chain.position.y - _hook.position.y)
	_apply()

## Доля подъёма 0..1 в момент t цикла (плавные разгон и торможение).
func lift_fraction(t: float) -> float:
	var u := fposmod(t, cycle_time) / cycle_time
	if u < 0.12 or u > 0.88:
		return 0.0
	if u < 0.37:
		return smoothstep(0.12, 0.37, u)
	if u < 0.63:
		return 1.0
	return 1.0 - smoothstep(0.63, 0.88, u)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	time += delta
	_apply()

func _apply() -> void:
	lift = lift_fraction(time) * lift_height
	gear_angle = lift / drum_radius
	# Груз качается, только когда оторван от поддона.
	sway = sway_amplitude * clampf(lift / 0.1, 0.0, 1.0) * sin(time * 2.2)
	if _gear:
		_gear.rotation.z = gear_angle
	if _crank:
		_crank.rotation.z = -gear_angle * gear_ratio
	if _chain:
		var len_now := _chain_len - lift
		_chain.scale = Vector3(1.0, len_now / _chain_len, 1.0)
		_chain.rotation.z = sway
		if _hook:
			# Маятник: крюк — на конце цепи, наклонён вместе с ней.
			_hook.position = _chain.position + Vector3(sin(sway) * len_now, -cos(sway) * len_now, 0.0)
			_hook.rotation.z = sway
