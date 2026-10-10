extends Node3D
## Анимация дробилки камня (узел Visual/Animator в scenes/machines/crusher.tscn).
## Пока станок работает, маховики и шкив мотора крутятся, шатун ходит по эксцентрику,
## камни в бункере подпрыгивают, горит зелёная лампа, из лотка сыплется щебень и пыль.
## Скорость плавно набирается при запуске и плавно гаснет после остановки (инерция маховиков).

## Станок, чьё состояние показываем (по умолчанию — корень сцены дробилки).
@export var machine_path: NodePath = ^"../.."
## Обороты маховика на полном ходу, об/с.
@export var flywheel_rps: float = 1.6
## Передаточное число ремня (маховик / шкив).
@export var pulley_ratio: float = 4.8
## Ход эксцентрика шатуна, м.
@export var eccentric: float = 0.03
## Время разгона и выбега, с.
@export var spin_up_time: float = 1.4
@export var spin_down_time: float = 3.0
## Яркость лампы «работа».
@export var lamp_energy: float = 3.0

## Текущая скорость 0..1 (1 — полный ход).
var speed: float = 0.0
var flywheel_angle: float = 0.0
var pulley_angle: float = 0.0

var _machine: Node
var _flywheel: Node3D
var _pulley: Node3D
var _jaw: Node3D
var _stones: Node3D
var _lamp_mat: StandardMaterial3D
var _particles: Array[GPUParticles3D] = []
var _jaw_base: Vector3
var _stones_base: Vector3

func _ready() -> void:
	_machine = get_node_or_null(machine_path)
	var visual: Node = get_parent()
	_flywheel = visual.get_node_or_null("Flywheel")
	_pulley = visual.get_node_or_null("Pulley")
	_jaw = visual.get_node_or_null("Jaw")
	_stones = visual.get_node_or_null("Stones")
	if _jaw:
		_jaw_base = _jaw.position
	if _stones:
		_stones_base = _stones.position
	var lamp := visual.get_node_or_null("Lamp") as MeshInstance3D
	if lamp and lamp.mesh and lamp.mesh.surface_get_material(0) and _lamp_mat == null:
		# Своя копия материала: у каждой дробилки лампа горит независимо.
		_lamp_mat = (lamp.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		lamp.material_override = _lamp_mat
	_particles.clear()
	for n in ["GravelParticles", "DustParticles"]:
		var p := visual.get_node_or_null(n) as GPUParticles3D
		if p:
			p.emitting = false
			_particles.append(p)
	_apply(0.0)

func is_running() -> bool:
	return _machine != null and bool(_machine.get("is_machine_running"))

func _process(delta: float) -> void:
	var running := is_running()
	var target: float = 1.0 if running else 0.0
	var time: float = spin_up_time if target > speed else spin_down_time
	speed = move_toward(speed, target, delta / maxf(0.05, time))
	if speed <= 0.0 and not running:
		_set_effects(false, 0.0)
		return
	_apply(delta)
	_set_effects(running and speed > 0.6, speed)

func _apply(delta: float) -> void:
	# Разгон по мягкой кривой: маховик тяжёлый, набирает ход не сразу.
	var w: float = TAU * flywheel_rps * smoothstep(0.0, 1.0, speed)
	flywheel_angle = fmod(flywheel_angle + w * delta, TAU)
	pulley_angle = fmod(pulley_angle + w * pulley_ratio * delta, TAU)
	if _flywheel:
		_flywheel.rotation.x = -flywheel_angle
	if _pulley:
		_pulley.rotation.x = -pulley_angle
	var stroke: float = minf(1.0, speed * 4.0)
	if _jaw:
		var e: float = eccentric * stroke
		_jaw.position = _jaw_base + Vector3(0.0, cos(flywheel_angle) * e, sin(flywheel_angle) * e)
		_jaw.rotation.x = sin(flywheel_angle) * 0.025 * stroke
	if _stones:
		var hop: float = absf(sin(flywheel_angle * 2.0)) * 0.014 * speed
		_stones.position = _stones_base + Vector3(sin(flywheel_angle * 3.0) * 0.004 * speed, hop, 0.0)
		_stones.rotation.z = sin(flywheel_angle * 2.0 + 0.7) * 0.012 * speed

func _set_effects(on: bool, amount: float) -> void:
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = lamp_energy if is_running() else 0.0
	for p in _particles:
		if p.emitting != on:
			p.emitting = on
		p.amount_ratio = clampf(amount, 0.0, 1.0)
