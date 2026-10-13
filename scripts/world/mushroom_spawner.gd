extends Node3D

## Расставляет лесные грибы в тенистых местах: у стволов деревьев и под валунами,
## то есть там, где влажно и мало солнца (мастер-план 2.2). Места проверяются по
## маске MeadowDecor — не на зданиях, станках, жилах и не во дворе.
## Зерно раскладки случайно в каждой новой игре и сохраняется: после загрузки
## грибы стоят на тех же местах с тем же состоянием роста.

const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const MushroomScript = preload("res://scripts/resources/mushroom.gd")
const MushroomScene = preload("res://scenes/resources/mushroom.tscn")

const GROUP: String = "mushroom_patches"

## Сколько грибов ставим всего.
@export var mushroom_count: int = 10
## 0 — случайное зерно при каждой новой игре.
@export var spawn_seed: int = 0
## Насколько далеко от центра базы искать (грибы — у леса и валунов, дальше).
@export var min_radius: float = 10.0
@export var max_radius: float = 34.0
## Минимальное расстояние между грибами, м.
@export var min_spacing: float = 3.2
## Максимальный перебор кандидатов, прежде чем сдаться.
@export var max_tries: int = 300

var current_seed: int = 0
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

func get_mushrooms() -> Array:
	var out: Array = []
	for c in get_children():
		if c.is_in_group(MushroomScript.GROUP) and not c.is_queued_for_deletion():
			out.append(c)
	return out

## Пересоздаёт грибы для зерна seed_value (раскладка детерминирована зерном).
func spawn(seed_value: int) -> void:
	current_seed = seed_value
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var decor := _get_decor()
	var shade: Array[Vector2] = _collect_shaded_spots()
	var placed: Array[Vector2] = []
	var want: int = maxi(0, mushroom_count)
	var guard: int = 0
	while placed.size() < want and guard < max_tries:
		guard += 1
		var p: Vector2 = shade[rng.randi_range(0, shade.size() - 1)] if not shade.is_empty() else _random_spot(rng)
		if not _spot_ok(decor, p, placed):
			continue
		var shroom: Node3D = MushroomScene.instantiate()
		shroom.name = "Mushroom%d" % (placed.size() + 1)
		shroom.position = Vector3(p.x, 0.0, p.y)
		shroom.rotation.y = rng.randf() * TAU
		var s: float = rng.randf_range(0.85, 1.2)
		shroom.scale = Vector3(s, s, s)
		add_child(shroom)
		placed.append(p)
	if not _pending_states.is_empty():
		_apply_states(_pending_states)
		_pending_states = []

## Тенистые места: вокруг деревьев, валунов и выходов жил.
func _collect_shaded_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not is_inside_tree():
		return out
	var anchors: Array[Vector2] = []
	for group in ["trees", "voxel_deposits"]:
		for node in get_tree().get_nodes_in_group(group):
			anchors.append(Vector2(node.global_position.x, node.global_position.z))
	# Валуны лежат в контейнере «Rocks» и своей группы не имеют.
	for parent in get_tree().get_nodes_in_group("rock_props"):
		for node in parent.get_children():
			anchors.append(Vector2(node.global_position.x, node.global_position.z))
	for a in anchors:
		for i in 8:
			var ang: float = TAU * float(i) / 8.0
			out.append(a + Vector2(cos(ang), sin(ang)) * 1.6)
	return out

func _random_spot(rng: RandomNumberGenerator) -> Vector2:
	var ang: float = rng.randf() * TAU
	return Vector2(cos(ang), sin(ang)) * rng.randf_range(min_radius, max_radius)

func _spot_ok(decor: Node, p: Vector2, placed: Array[Vector2]) -> bool:
	if p.length() < min_radius or p.length() > max_radius:
		return false
	for q in placed:
		if q.distance_to(p) < min_spacing:
			return false
	if decor == null or decor.mask.is_empty():
		return true
	return decor.is_bush_spot_free(p, 1.0)

func get_save_state() -> Dictionary:
	var states: Array = []
	for m in get_mushrooms():
		states.append(m.get_save_state())
	return {"seed": current_seed, "mushrooms": states}

func apply_save_state(state: Dictionary) -> void:
	var seed_value: int = int(state.get("seed", 0))
	var states: Array = state.get("mushrooms", [])
	if seed_value == 0:
		return
	current_seed = seed_value
	if get_mushrooms().is_empty():
		_pending_states = states
		spawn(seed_value)
	else:
		_apply_states(states)

func _apply_states(states: Array) -> void:
	var nodes: Array = get_mushrooms()
	for i in mini(nodes.size(), states.size()):
		nodes[i].apply_save_state(states[i])

static func is_valid_save_state(state: Dictionary) -> bool:
	if not state is Dictionary:
		return false
	if not _is_int(state.get("seed", 0), 0):
		return false
	var list: Array = state.get("mushrooms", [])
	if not list is Array or list.size() > 512:
		return false
	for entry in list:
		if not entry is Dictionary or not (entry.get("has_mushroom") is bool):
			return false
		if not _is_int(entry.get("regrow_progress", 0.0), 0.0):
			return false
	return true

static func _is_int(value: Variant, minimum: float) -> bool:
	return (typeof(value) in [TYPE_INT, TYPE_FLOAT]) and is_finite(float(value)) and float(value) >= minimum