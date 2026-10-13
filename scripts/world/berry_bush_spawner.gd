extends Node3D

## Расставляет ягодные кусты в случайных свободных местах луга: не больше
## MAX_PER_TYPE кустов каждого вида. Места проверяются по маске MeadowDecor
## (не на зданиях, станках, жилах, валунах, у стволов, не во дворе и не вплотную
## к декоративным кустам). Зерно раскладки выбирается случайно в новой игре и
## сохраняется — после загрузки кусты стоят на тех же местах с тем же урожаем.

const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const MAX_PER_TYPE: int = 2
const BUSH_SCENES: Dictionary = {
	"red": preload("res://scenes/resources/berry_bush_red.tscn"),
	"blue": preload("res://scenes/resources/berry_bush_blue.tscn"),
	"black": preload("res://scenes/resources/berry_bush_black.tscn"),
	"sea": preload("res://scenes/resources/berry_bush_sea.tscn"),
}
const BUSH_ORDER: Array[String] = ["red", "blue", "black", "sea"]

## Сколько кустов каждого вида (больше MAX_PER_TYPE не ставится).
@export var bush_counts: Dictionary = {"red": 2, "blue": 2, "black": 2, "sea": 2}
## 0 — случайное зерно при каждой новой игре.
@export var spawn_seed: int = 0
## Кольцо вокруг центра базы, где ищутся места, м.
@export var min_radius: float = 9.0
@export var max_radius: float = 32.0
## Минимальное расстояние между ягодными кустами, м.
@export var min_spacing: float = 5.0

var current_seed: int = 0
var _spawned: bool = false
var _pending_states: Array = []

func _ready() -> void:
	current_seed = spawn_seed if spawn_seed != 0 else _random_seed()
	var decor := _get_decor()
	if decor and decor.counts.is_empty():
		decor.generated.connect(_on_decor_generated, CONNECT_ONE_SHOT)
	else:
		_on_decor_generated.call_deferred()

func _on_decor_generated() -> void:
	spawn(current_seed)

func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483646)

func _get_decor() -> Node:
	var parent := get_parent()
	if parent:
		for c in parent.get_children():
			if c.get_script() == MeadowDecor:
				return c
	return get_tree().get_first_node_in_group(MeadowDecor.GROUP) if is_inside_tree() else null

func get_bushes() -> Array:
	var out: Array = []
	for c in get_children():
		if c.is_in_group("berry_bushes") and not c.is_queued_for_deletion():
			out.append(c)
	return out

## Пересоздаёт кусты для зерна seed_value (раскладка детерминирована зерном).
func spawn(seed_value: int) -> void:
	current_seed = seed_value
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var decor := _get_decor()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array[Vector2] = []
	# Порядок фиксирован (BUSH_ORDER): раскладка red/blue от того же зерна
	# не меняется при добавлении новых видов — старые сейвы совместимы.
	for bush_type in BUSH_ORDER:
		var want: int = clampi(int(bush_counts.get(bush_type, 0)), 0, MAX_PER_TYPE)
		var made: int = 0
		var guard: int = 0
		while made < want and guard < 400:
			guard += 1
			var a: float = rng.randf() * TAU
			var p := Vector2(cos(a), sin(a)) * rng.randf_range(min_radius, max_radius)
			if not _spot_ok(decor, p, placed):
				continue
			var bush: Node3D = BUSH_SCENES[bush_type].instantiate()
			bush.name = "BerryBush%s%d" % [bush_type.capitalize(), made + 1]
			bush.position = Vector3(p.x, 0.0, p.y)
			bush.rotation.y = rng.randf() * TAU
			var s: float = rng.randf_range(0.9, 1.1)
			bush.scale = Vector3(s, s, s)
			add_child(bush)
			placed.append(p)
			made += 1
	_spawned = true
	if not _pending_states.is_empty():
		_apply_bush_states(_pending_states)
		_pending_states = []

func _spot_ok(decor: Node, p: Vector2, placed: Array[Vector2]) -> bool:
	for q in placed:
		if q.distance_to(p) < min_spacing:
			return false
	if decor == null or decor.mask.is_empty():
		return true
	return decor.is_bush_spot_free(p, 1.0)

func get_save_state() -> Dictionary:
	var states: Array = []
	for b in get_bushes():
		var st: Dictionary = b.get_save_state()
		st["type"] = b.bush_type
		states.append(st)
	return {"seed": current_seed, "bushes": states}

func apply_save_state(state: Dictionary) -> void:
	var seed_value: int = int(state.get("seed", 0))
	var states: Array = state.get("bushes", [])
	if seed_value == 0:
		return
	current_seed = seed_value
	if _spawned:
		spawn(seed_value)
		_apply_bush_states(states)
	else:
		_pending_states = states

func _apply_bush_states(states: Array) -> void:
	var bushes := get_bushes()
	for i in mini(bushes.size(), states.size()):
		if states[i] is Dictionary and str(states[i].get("type", bushes[i].bush_type)) == bushes[i].bush_type:
			bushes[i].apply_save_state(states[i])
