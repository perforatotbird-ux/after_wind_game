extends Node3D

## Живой луг вокруг базы: густая трава пучками (колышется на ветру), полевые
## цветы куртинами, кусты с ягодами и цветами (с коллизией) и мелкий мусор после
## бури — камешки, ветки, листва под деревьями, грибы, обломки досок, кирпича и
## жести. Всё раскладывается детерминированно (seed) при загрузке мира и не
## попадает на станки, здания, грядки, жилы, валуны и стволы деревьев.
## Трава, цветы и мусор — MultiMesh (без коллизии и теней), кусты — StaticBody3D.

const MeadowGround = preload("res://scripts/world/meadow_ground.gd")
const MeadowGrass = preload("res://scripts/world/meadow_grass.gd")
const VoxelDepositScript = preload("res://scripts/world/voxel_deposit.gd")

const GROUP: String = "meadow_decor"
const BUSH_GROUP: String = "bushes"

## Флаги клеток маски раскладки (шаг MASK_RES м).
const NO_GRASS: int = 1
const NO_PROPS: int = 2
## Верх жилы: трава есть, но прячется над выкопанными блоками.
const DEPOSIT: int = 4
const GRASS_GROUP: String = "meadow_grass"
const MASK_RES: float = 0.25
## Чанки травы для отсечения по камере.
const CHUNK: float = 12.0
## Объекты крупнее этого (лопасти ветряка и т.п.) режутся до квадрата вокруг узла.
const MAX_FOOTPRINT: float = 9.0

@export var decor_seed: int = 4242
@export var area_size: Vector2 = Vector2(78, 78)
## Шаг сетки пучков травы, м (≈ 7 пучков на м²).
@export var grass_step: float = 0.36
## Дальше этого расстояния от камеры — упрощённая трава.
@export var grass_lod_distance: float = 36.0
@export var flower_count: int = 900
@export var bush_count: int = 46
@export var pebble_count: int = 380
@export var stick_count: int = 170
@export var leaf_count: int = 650
@export var mushroom_count: int = 70
@export var plank_count: int = 50
@export var brick_count: int = 45
@export var sheet_count: int = 22
## Генерировать при запуске (тесты могут отключить и вызвать generate() сами).
@export var auto_generate: bool = true

var mask: PackedByteArray = PackedByteArray()
var _dims: Vector2i = Vector2i.ZERO
var _yard: Rect2 = MeadowGround.DEFAULT_YARD
var _trees: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
## Сколько экземпляров каждого вида создано (для тестов и отладки).
var counts: Dictionary = {}
var bush_positions: Array[Vector3] = []
var _deposit_grass: Array = []

static var _mesh_cache: Dictionary = {}
static var _grass_material: ShaderMaterial = null
static var _flower_material: ShaderMaterial = null
static var _decor_material: StandardMaterial3D = null

const PLANT_SHADER: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float wind = 0.07;
uniform bool use_custom = false;
varying vec3 v_custom;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y;
	float s = sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.22) * 0.7 + sin(TIME * 2.9 + wp.x * 0.9 - wp.z * 0.6) * 0.3;
	VERTEX.x += s * wind * h * h;
	VERTEX.z += s * wind * 0.6 * h * h;
	// Нормаль вверх: трава освещается как земля, без тёмных изнанок.
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_custom = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (use_custom) {
		c = mix(c, v_custom, UV.x);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
"""

func _ready() -> void:
	add_to_group(GROUP)
	if auto_generate:
		generate.call_deferred()

## Полная пересборка декора.
func generate() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	counts.clear()
	bush_positions.clear()
	_rng.seed = decor_seed
	_noise.seed = decor_seed
	_noise.frequency = 0.07
	_noise.fractal_octaves = 3
	var ground := get_parent().get_node_or_null("Ground") if get_parent() else null
	if ground and "yard_rect" in ground:
		_yard = ground.yard_rect
	_build_mask()
	# Каждый слой со своим зерном: изменение одного слоя не сдвигает остальные.
	_rng.seed = decor_seed + 1
	_spawn_grass()
	_rng.seed = decor_seed + 2
	_spawn_flowers()
	_rng.seed = decor_seed + 3
	_spawn_bushes()
	_rng.seed = decor_seed + 4
	_spawn_debris()

# --- Маска свободного места ----------------------------------------------------

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x + area_size.x * 0.5) / MASK_RES)), int(floor((p.y + area_size.y * 0.5) / MASK_RES)))

func get_mask_at(p: Vector2) -> int:
	var c: Vector2i = _cell(p)
	if c.x < 0 or c.y < 0 or c.x >= _dims.x or c.y >= _dims.y:
		return NO_GRASS | NO_PROPS
	return mask[c.y * _dims.x + c.x]

func _mark_rect(r: Rect2, flags: int) -> void:
	var a: Vector2i = _cell(r.position)
	var b: Vector2i = _cell(r.end)
	for y in range(maxi(0, a.y), mini(_dims.y, b.y + 1)):
		for x in range(maxi(0, a.x), mini(_dims.x, b.x + 1)):
			mask[y * _dims.x + x] |= flags

func _mark_circle(center: Vector2, radius: float, flags: int) -> void:
	var a: Vector2i = _cell(center - Vector2(radius, radius))
	var b: Vector2i = _cell(center + Vector2(radius, radius))
	for y in range(maxi(0, a.y), mini(_dims.y, b.y + 1)):
		for x in range(maxi(0, a.x), mini(_dims.x, b.x + 1)):
			var p := Vector2((x + 0.5) * MASK_RES - area_size.x * 0.5, (y + 0.5) * MASK_RES - area_size.y * 0.5)
			if p.distance_to(center) <= radius:
				mask[y * _dims.x + x] |= flags

## Прямоугольник XZ по мешам узла (в мировых координатах).
static func node_footprint(n: Node3D) -> Rect2:
	var have: bool = false
	var box := AABB()
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.position.y > n.global_position.y + 1.0:
			continue # высоко над землёй (лопасти, крыши-навесы) — не занимает место на траве
		box = b if not have else box.merge(b)
		have = true
	if not have:
		return Rect2(Vector2(n.global_position.x, n.global_position.z) - Vector2(0.6, 0.6), Vector2(1.2, 1.2))
	var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	if r.size.x > MAX_FOOTPRINT or r.size.y > MAX_FOOTPRINT:
		var c := Vector2(n.global_position.x, n.global_position.z)
		r = Rect2(c - Vector2(1.5, 1.5), Vector2(3.0, 3.0))
	return r

func _build_mask() -> void:
	_dims = Vector2i(int(ceil(area_size.x / MASK_RES)), int(ceil(area_size.y / MASK_RES)))
	mask = PackedByteArray()
	mask.resize(_dims.x * _dims.y)
	mask.fill(0)
	_trees.clear()
	var world := get_parent()
	if world == null:
		return
	# Жилы — сплошной вырез.
	for d in get_tree().get_nodes_in_group(VoxelDepositScript.GROUP):
		if d.has_method("get_footprint_rect"):
			_mark_rect((d.get_footprint_rect() as Rect2).grow(0.3), NO_PROPS)
			_mark_rect(d.get_footprint_rect() as Rect2, DEPOSIT)
	# Станки, здания, грядки, фонари, декоративные скалы.
	var props := world.get_node_or_null("Props")
	if props:
		for n in props.get_children():
			if n.name == "Rocks":
				for r in n.get_children():
					if r is Node3D:
						_mark_rect(node_footprint(r).grow(0.3), NO_GRASS | NO_PROPS)
			elif n is Node3D:
				_mark_rect(node_footprint(n).grow(0.4), NO_GRASS | NO_PROPS)
	# Ресурсы: стволы деревьев — кружок, остальное (валуны, лом, вода) — по мешам.
	for n in world.find_children("*", "Area3D", true, false):
		if not n.is_in_group("trees") and n.get("resource_id") == null:
			continue
		if n.is_in_group("trees"):
			_trees.append(n.global_position)
			_mark_circle(Vector2(n.global_position.x, n.global_position.z), 0.55, NO_GRASS | NO_PROPS)
		elif not (n is VoxelDepositScript):
			_mark_rect(node_footprint(n).grow(0.3), NO_GRASS | NO_PROPS)

func _yard_distance(p: Vector2) -> float:
	return MeadowGround.yard_signed_distance(p, _yard)

func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5), _rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5))

func _density(p: Vector2) -> float:
	return clampf(_noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5, 0.0, 1.0)

# --- Трава и цветы -------------------------------------------------------------

func _spawn_grass() -> void:
	# Сплошной ковёр: пучки по сетке с дрожанием (шаг grass_step), вид пучка —
	# по шуму: сочный луг, дикие высокие куртины, короткая трава у двора и на жилах.
	var kinds := MeadowGrass.Kind
	var lists: Dictionary = {} # "chunk|kind|variant" -> [[xf, color], ...]
	var far_lists: Dictionary = {}
	var deposit_refs: Dictionary = {} # тот же ключ -> [[индекс, жила], ...]
	var deposits: Array = get_tree().get_nodes_in_group(VoxelDepositScript.GROUP)
	var placed: int = 0
	var clover: int = 0
	var nx: int = int(area_size.x / grass_step)
	var ny: int = int(area_size.y / grass_step)
	for gy in ny:
		for gx in nx:
			var p := Vector2(-area_size.x * 0.5 + (gx + _rng.randf()) * grass_step, -area_size.y * 0.5 + (gy + _rng.randf()) * grass_step)
			var m: int = get_mask_at(p)
			if m & NO_GRASS:
				continue
			var sd: float = _yard_distance(p)
			if sd < -0.4:
				continue
			var on_deposit: bool = (m & DEPOSIT) != 0
			var dens: float = _density(p)
			var wild: float = _noise.get_noise_2d(p.x * 0.9 + 200.0, p.y * 0.9 - 40.0) * 0.5 + 0.5
			var dry: float = clampf(_noise.get_noise_2d(p.x * 1.7 + 50.0, p.y * 1.7) * 0.9 + 0.2, 0.0, 1.0)
			# У края двора — редкая примятая трава.
			var edge: float = clampf((sd + 0.4) / 2.6, 0.0, 1.0)
			if _rng.randf() > 0.25 + 0.75 * edge:
				continue
			var kind: int = kinds.LUSH
			var size: float = _rng.randf_range(0.8, 1.2) * (0.85 + 0.35 * dens)
			if on_deposit:
				pass # обычный луг: жилу выдают только камешки-выходы породы
			elif edge < 0.7:
				kind = kinds.SHORT
				size *= 1.0 + 0.6 * edge
			elif wild > 0.68 and _rng.randf() < 0.5:
				kind = kinds.TALL
			elif _rng.randf() < 0.22:
				kind = kinds.LUSH_WIDE
			elif dens < 0.3 and _rng.randf() < 0.5:
				kind = kinds.SHORT
				size *= 1.5
			var variant: int = _rng.randi() % int(MeadowGrass.VARIANTS[kind])
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(size, size * _rng.randf_range(0.85, 1.2), size))
			var xf := Transform3D(basis, Vector3(p.x, 0.0, p.y))
			var col: Color = Color(1.0, 1.0, 1.0).lerp(Color(1.18, 1.05, 0.62), dry * 0.55) * _rng.randf_range(0.9, 1.08)
			col = col.lerp(Color(0.85, 0.95, 0.8), (1.0 - dens) * 0.3)
			col.a = 1.0
			var chunk := Vector2i(int(floor(p.x / CHUNK)), int(floor(p.y / CHUNK)))
			var key := "%d|%d|%d|%d" % [chunk.x, chunk.y, kind, variant]
			if not lists.has(key):
				lists[key] = []
			if on_deposit:
				if not deposit_refs.has(key):
					deposit_refs[key] = []
				deposit_refs[key].append([lists[key].size(), _deposit_at(p, deposits)])
			lists[key].append([xf, col])
			placed += 1
			# Дальний план: каждый третий пучок — простой широкий, без жил.
			if placed % 3 == 0:
				var fk := "%d|%d" % [chunk.x, chunk.y]
				if not far_lists.has(fk):
					far_lists[fk] = []
				var fxf := Transform3D(basis.scaled(Vector3(1.35, 1.0, 1.35)), xf.origin)
				if on_deposit:
					if not deposit_refs.has("far|" + fk):
						deposit_refs["far|" + fk] = []
					deposit_refs["far|" + fk].append([far_lists[fk].size(), _deposit_at(p, deposits), fxf])
				far_lists[fk].append([fxf, col])
			# Клевер пятнами у корней.
			if not on_deposit and edge > 0.6:
				var cl: float = _noise.get_noise_2d(p.x * 1.3 - 90.0, p.y * 1.3 + 15.0)
				if cl > 0.2 and _rng.randf() < 0.55:
					var cp: Vector2 = p + Vector2(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.15, 0.15))
					var ck := "%d|%d|%d|%d" % [chunk.x, chunk.y, kinds.CLOVER, clover % 2]
					if not lists.has(ck):
						lists[ck] = []
					var cs: float = _rng.randf_range(0.8, 1.25)
					lists[ck].append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(cs, cs, cs)), Vector3(cp.x, 0.0, cp.y)), Color(1, 1, 1) * _rng.randf_range(0.85, 1.1)])
					clover += 1
	_deposit_grass.clear()
	for key in lists.keys():
		var parts: PackedStringArray = (key as String).split("|")
		var kind: int = int(parts[2])
		var mat: Material = MeadowGrass.get_clover_material() if kind == kinds.CLOVER else MeadowGrass.get_grass_material()
		var mmi := _add_multimesh("Grass_%s" % (key as String).replace("|", "_"), MeadowGrass.get_mesh(kind, int(parts[3])), mat, lists[key], false)
		mmi.visibility_range_end = grass_lod_distance + 4.0
		mmi.visibility_range_end_margin = 2.0
		mmi.add_to_group(GRASS_GROUP)
		if deposit_refs.has(key):
			for ref in deposit_refs[key]:
				if ref[1] != null:
					_deposit_grass.append([mmi, ref[0], ref[1], (lists[key][ref[0]][0] as Transform3D)])
	for fk in far_lists.keys():
		var far := _add_multimesh("GrassFar_%s" % (fk as String).replace("|", "_"), MeadowGrass.get_mesh(kinds.FAR, 0), MeadowGrass.get_grass_material(), far_lists[fk], false)
		far.visibility_range_begin = grass_lod_distance
		far.visibility_range_begin_margin = 2.0
		if deposit_refs.has("far|" + fk):
			for ref in deposit_refs["far|" + fk]:
				if ref[1] != null:
					_deposit_grass.append([far, ref[0], ref[1], ref[2]])
	counts["grass"] = placed
	counts["clover"] = clover
	_connect_deposits(deposits)
	sync_with_deposits()

func _deposit_at(p: Vector2, deposits: Array) -> Node:
	for d in deposits:
		if (d.get_footprint_rect() as Rect2).has_point(p):
			return d
	return null

func _connect_deposits(deposits: Array) -> void:
	for d in deposits:
		if d.has_signal("terrain_rebuilt") and not d.terrain_rebuilt.is_connected(sync_with_deposits):
			d.terrain_rebuilt.connect(sync_with_deposits)

## Прячет траву над выкопанными блоками верхнего слоя жил (после копания и загрузки).
func sync_with_deposits() -> void:
	var hidden: int = 0
	for ref in _deposit_grass:
		var mmi: MultiMeshInstance3D = ref[0]
		var d: Node = ref[2]
		if not is_instance_valid(mmi) or not is_instance_valid(d):
			continue
		var xf: Transform3D = ref[3]
		var cell: Vector3i = d.global_to_cell(Vector3(xf.origin.x, -0.25, xf.origin.z))
		var gone: bool = not d.is_solid(cell)
		mmi.multimesh.set_instance_transform(ref[1], Transform3D(Basis().scaled(Vector3.ZERO), xf.origin) if gone else xf)
		if gone:
			hidden += 1
	counts["grass_hidden"] = hidden

func _spawn_flowers() -> void:
	var palette: Array[Color] = [Color(0.96, 0.96, 0.92), Color(1.0, 0.86, 0.22), Color(0.4, 0.55, 1.0), Color(0.72, 0.42, 0.88), Color(0.95, 0.55, 0.7)]
	var items: Array = []
	var guard: int = 0
	while items.size() < flower_count and guard < flower_count * 6:
		guard += 1
		var center: Vector2 = _random_point()
		if get_mask_at(center) & (NO_GRASS | DEPOSIT) or _yard_distance(center) < 3.0:
			continue
		var color: Color = palette[_rng.randi() % palette.size()]
		var n: int = _rng.randi_range(12, 34)
		for i in n:
			if items.size() >= flower_count:
				break
			var p: Vector2 = center + Vector2(_rng.randfn(0.0, 1.3), _rng.randfn(0.0, 1.3))
			if get_mask_at(p) & (NO_GRASS | DEPOSIT) or _yard_distance(p) < 1.5:
				continue
			var s: float = _rng.randf_range(0.75, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y))
			var c: Color = color * _rng.randf_range(0.9, 1.08)
			c.a = 1.0
			items.append([xf, Color.WHITE, c])
	_add_multimesh("Flowers", _get_mesh("flower"), _get_flower_material(), items, false, true)
	counts["flowers"] = items.size()

# --- Кусты ---------------------------------------------------------------------

func _bush_spot_ok(p: Vector2, radius: float) -> bool:
	if _yard_distance(p) < 2.5:
		return false
	for o in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		if get_mask_at(p + o) & NO_PROPS:
			return false
	for t in _trees:
		if Vector2(t.x, t.z).distance_to(p) < 1.9:
			return false
	for b in bush_positions:
		if Vector2(b.x, b.z).distance_to(p) < 2.2:
			return false
	return true

func _spawn_bushes() -> void:
	var guard: int = 0
	while bush_positions.size() < bush_count and guard < bush_count * 40:
		guard += 1
		var p: Vector2
		if not _trees.is_empty() and _rng.randf() < 0.55:
			# Подлесок: кусты по опушкам.
			var t: Vector3 = _trees[_rng.randi() % _trees.size()]
			var a: float = _rng.randf() * TAU
			p = Vector2(t.x, t.z) + Vector2(cos(a), sin(a)) * _rng.randf_range(2.2, 5.5)
		else:
			p = _random_point()
		var s: float = _rng.randf_range(0.8, 1.4)
		if not _bush_spot_ok(p, 0.7 * s):
			continue
		var variant: int = _rng.randi() % 6
		var body := StaticBody3D.new()
		body.name = "Bush%d" % bush_positions.size()
		body.add_to_group(BUSH_GROUP)
		body.collision_mask = 0
		body.position = Vector3(p.x, 0.0, p.y)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = _get_mesh("bush_%d" % variant)
		mi.material_override = _get_decor_material()
		mi.rotation.y = _rng.randf() * TAU
		mi.scale = Vector3(s, s * _rng.randf_range(0.85, 1.1), s)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.5 * s
		cyl.height = 1.2 * s
		col.shape = cyl
		col.position.y = 0.6 * s
		body.add_child(col)
		add_child(body)
		bush_positions.append(body.position)
	counts["bushes"] = bush_positions.size()

# --- Мусор ---------------------------------------------------------------------

func _near_tree_point(r_min: float, r_max: float) -> Vector2:
	if _trees.is_empty():
		return _random_point()
	var t: Vector3 = _trees[_rng.randi() % _trees.size()]
	var a: float = _rng.randf() * TAU
	return Vector2(t.x, t.z) + Vector2(cos(a), sin(a)) * _rng.randf_range(r_min, r_max)

func _ring_point(r_min: float, r_max: float) -> Vector2:
	var a: float = _rng.randf() * TAU
	return Vector2(cos(a), sin(a)) * _rng.randf_range(r_min, r_max)

## kind: где искать точку ("any", "tree", "ring"); in_yard — можно ли во дворе.
func _scatter(name_: String, mesh_id: String, count: int, kind: String, in_yard: bool, palette: Array, scale_range: Vector2, y: float, tilt: float, stretch: Vector3 = Vector3.ONE, ring: Vector2 = Vector2(8, 28)) -> void:
	var items: Array = []
	var guard: int = 0
	while items.size() < count and guard < count * 12:
		guard += 1
		var p: Vector2
		match kind:
			"tree":
				p = _near_tree_point(0.7, 3.6)
			"ring":
				p = _ring_point(ring.x, ring.y)
			_:
				p = _random_point() if _rng.randf() < 0.75 else _near_tree_point(0.8, 4.0)
		if get_mask_at(p) & NO_PROPS:
			continue
		if not in_yard and _yard_distance(p) < 0.5:
			continue
		var s: float = _rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		if tilt > 0.0:
			basis = basis * Basis(Vector3.RIGHT, _rng.randf_range(-tilt, tilt)) * Basis(Vector3.FORWARD, _rng.randf_range(-tilt, tilt))
		basis = basis.scaled(Vector3(s * stretch.x, s * stretch.y, s * stretch.z))
		var xf := Transform3D(basis, Vector3(p.x, y * s, p.y))
		var c: Color = palette[_rng.randi() % palette.size()] * _rng.randf_range(0.85, 1.1)
		c.a = 1.0
		items.append([xf, c])
	_add_multimesh(name_, _get_mesh(mesh_id), _get_decor_material(), items, false)
	counts[name_.to_lower()] = items.size()

func _spawn_debris() -> void:
	_scatter("Pebbles", "pebble", pebble_count, "any", true,
		[Color(0.55, 0.55, 0.55), Color(0.62, 0.6, 0.56), Color(0.45, 0.44, 0.43), Color(0.6, 0.55, 0.48)],
		Vector2(0.07, 0.2), 0.15, 0.0, Vector3(1.0, 0.6, 1.0))
	_scatter("Sticks", "stick", stick_count, "any", true,
		[Color(0.42, 0.3, 0.2), Color(0.5, 0.38, 0.26), Color(0.35, 0.26, 0.18)],
		Vector2(0.4, 1.2), 0.03, 0.08)
	_scatter("Leaves", "leaf", leaf_count, "tree", false,
		[Color(0.72, 0.55, 0.2), Color(0.62, 0.38, 0.16), Color(0.45, 0.5, 0.2), Color(0.55, 0.3, 0.15), Color(0.8, 0.68, 0.3)],
		Vector2(0.8, 1.4), 0.012, 0.0)
	_scatter("Mushrooms", "mushroom", mushroom_count, "tree", false,
		[Color(0.62, 0.42, 0.26), Color(0.8, 0.22, 0.15), Color(0.85, 0.75, 0.6)],
		Vector2(0.6, 1.3), 0.0, 0.0)
	_scatter("Planks", "plank", plank_count, "ring", true,
		[Color(0.55, 0.45, 0.34), Color(0.47, 0.4, 0.33), Color(0.62, 0.52, 0.4)],
		Vector2(0.6, 1.3), 0.02, 0.12, Vector3.ONE, Vector2(7, 30))
	_scatter("Bricks", "brick", brick_count, "ring", true,
		[Color(0.66, 0.32, 0.22), Color(0.58, 0.3, 0.24), Color(0.72, 0.42, 0.3)],
		Vector2(0.7, 1.2), 0.035, 0.4, Vector3.ONE, Vector2(5, 22))
	_scatter("Sheets", "sheet", sheet_count, "ring", true,
		[Color(0.55, 0.36, 0.25), Color(0.5, 0.52, 0.54), Color(0.6, 0.42, 0.3)],
		Vector2(0.7, 1.3), 0.02, 0.15, Vector3.ONE, Vector2(9, 32))

# --- Сборка MultiMesh ----------------------------------------------------------

## items: [Transform3D, Color] или [Transform3D, Color, Color(custom)].
func _add_multimesh(node_name: String, mesh: Mesh, material: Material, items: Array, shadows: bool, custom: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = items.size()
	# Буфер целиком быстрее, чем set_instance_* для десятков тысяч пучков.
	var stride: int = 16 + (4 if custom else 0)
	var buf := PackedFloat32Array()
	buf.resize(items.size() * stride)
	for i in items.size():
		var xf: Transform3D = items[i][0]
		var c: Color = items[i][1]
		var o: int = i * stride
		buf[o] = xf.basis.x.x; buf[o + 1] = xf.basis.y.x; buf[o + 2] = xf.basis.z.x; buf[o + 3] = xf.origin.x
		buf[o + 4] = xf.basis.x.y; buf[o + 5] = xf.basis.y.y; buf[o + 6] = xf.basis.z.y; buf[o + 7] = xf.origin.y
		buf[o + 8] = xf.basis.x.z; buf[o + 9] = xf.basis.y.z; buf[o + 10] = xf.basis.z.z; buf[o + 11] = xf.origin.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		if custom:
			var u: Color = items[i][2]
			buf[o + 16] = u.r; buf[o + 17] = u.g; buf[o + 18] = u.b; buf[o + 19] = u.a
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

# --- Материалы -----------------------------------------------------------------

static func _get_grass_material() -> ShaderMaterial:
	if _grass_material == null:
		var sh := Shader.new()
		sh.code = PLANT_SHADER
		_grass_material = ShaderMaterial.new()
		_grass_material.shader = sh
	return _grass_material

static func _get_flower_material() -> ShaderMaterial:
	if _flower_material == null:
		_flower_material = ShaderMaterial.new()
		_flower_material.shader = _get_grass_material().shader
		_flower_material.set_shader_parameter("use_custom", true)
		_flower_material.set_shader_parameter("wind", 0.09)
	return _flower_material

static func _get_decor_material() -> StandardMaterial3D:
	if _decor_material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_decor_material = m
	return _decor_material

# --- Процедурные меши (кэшируются) ---------------------------------------------

static func _get_mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var mesh: Mesh
	match id:
		"grass":
			mesh = _build_grass_tuft(rng)
		"flower":
			mesh = _build_flower(rng)
		"pebble":
			mesh = _build_blob([[Vector3.ZERO, 1.0, Color.WHITE]], 0, 0.25, rng)
		"stick":
			mesh = _build_stick(rng)
		"leaf":
			mesh = _build_leaf()
		"mushroom":
			mesh = _build_mushroom()
		"plank":
			mesh = _build_box(Vector3(1.0, 0.04, 0.16), Color(1, 1, 1), true)
		"brick":
			mesh = _build_box(Vector3(0.22, 0.07, 0.11), Color(1, 1, 1), false)
		"sheet":
			mesh = _build_box(Vector3(0.55, 0.012, 0.38), Color(1, 1, 1), false)
		_:
			if id.begins_with("bush_"):
				mesh = _build_bush(int(id.substr(5)), rng)
	_mesh_cache[id] = mesh
	return mesh

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, center: Vector3 = Vector3(INF, INF, INF)) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if center.x != INF and n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(pair[1])
		st.add_vertex(pair[0])

static func _build_grass_tuft(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_c := Color(0.24, 0.36, 0.14)
	var mid_c := Color(0.38, 0.54, 0.22)
	var tip_c := Color(0.58, 0.72, 0.33)
	for i in 7:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.0, 0.09)
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var face: float = rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face))
		var lean_dir := Vector3(-side.z, 0.0, side.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var h: float = rng.randf_range(0.2, 0.4)
		var w: float = rng.randf_range(0.035, 0.055)
		var lean: float = rng.randf_range(0.05, 0.18)
		var mid: Vector3 = root + Vector3.UP * h * 0.55 + lean_dir * lean * 0.35
		var tip: Vector3 = root + Vector3.UP * h + lean_dir * lean
		var bl: Vector3 = root - side * w
		var br: Vector3 = root + side * w
		var ml: Vector3 = mid - side * w * 0.7
		var mr: Vector3 = mid + side * w * 0.7
		for v in [[bl, 0.0, base_c], [br, 0.0, base_c], [mr, 0.55, mid_c], [bl, 0.0, base_c], [mr, 0.55, mid_c], [ml, 0.55, mid_c], [ml, 0.55, mid_c], [mr, 0.55, mid_c], [tip, 1.0, tip_c]]:
			st.set_normal(Vector3.UP)
			st.set_color(v[2])
			st.set_uv(Vector2(0.0, v[1]))
			st.add_vertex(v[0])
	return st.commit()

static func _build_flower(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c := Color(0.25, 0.4, 0.16)
	var heart_c := Color(1.0, 0.85, 0.25)
	for i in 3:
		var a: float = rng.randf() * TAU
		var root := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.02, 0.1)
		var h: float = rng.randf_range(0.3, 0.46)
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var top: Vector3 = root + Vector3.UP * h + lean
		var side := Vector3(0.012, 0.0, 0.0).rotated(Vector3.UP, rng.randf() * TAU)
		for v in [[root - side, 0.0], [root + side, 0.0], [top, 1.0]]:
			st.set_normal(Vector3.UP)
			st.set_color(stem_c)
			st.set_uv(Vector2(0.0, v[1]))
			st.add_vertex(v[0])
		# Головка: пятилепестковая звезда, к краю — цвет куртины (INSTANCE_CUSTOM).
		var petals: int = 5
		var rad: float = rng.randf_range(0.045, 0.065)
		for k in petals:
			var a0: float = TAU * k / petals
			var a1: float = TAU * (k + 0.5) / petals
			var a2: float = TAU * (k + 1) / petals
			var p0: Vector3 = top + Vector3(cos(a0), 0.0, sin(a0)) * rad * 0.35
			var p1: Vector3 = top + Vector3(cos(a1), 0.01, sin(a1)) * rad
			var p2: Vector3 = top + Vector3(cos(a2), 0.0, sin(a2)) * rad * 0.35
			for v in [[top + Vector3.UP * 0.008, 0.0, heart_c], [p0, 0.6, heart_c], [p1, 1.0, Color.WHITE], [top + Vector3.UP * 0.008, 0.0, heart_c], [p1, 1.0, Color.WHITE], [p2, 0.6, heart_c]]:
				st.set_normal(Vector3.UP)
				st.set_color(v[2])
				st.set_uv(Vector2(v[1], 1.0))
				st.add_vertex(v[0])
	return st.commit()

## Низкополигональная «глыба» из икосфер: spheres = [[центр, радиус, цвет], ...].
static func _build_blob(spheres: Array, subdiv: int, jitter: float, rng: RandomNumberGenerator, extra: Callable = Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sph in spheres:
		var center: Vector3 = sph[0]
		var radius: float = sph[1]
		var color: Color = sph[2]
		var verts: Array = _icosphere(subdiv)
		var offs: Dictionary = {}
		for tri in verts:
			var pts: Array = []
			var cols: Array = []
			for v in tri:
				var key: Vector3i = Vector3i(round(v.x * 1000.0), round(v.y * 1000.0), round(v.z * 1000.0))
				if not offs.has(key):
					offs[key] = 1.0 + rng.randf_range(-jitter, jitter)
				pts.append(center + (v as Vector3) * radius * offs[key])
				cols.append(color * (0.85 + 0.25 * clampf(v.y * 0.5 + 0.5, 0.0, 1.0)))
			_tri(st, pts[0], pts[1], pts[2], cols[0], cols[1], cols[2], center)
	if extra.is_valid():
		extra.call(st)
	return st.commit()

static func _icosphere(subdiv: int) -> Array:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris: Array = []
	for face in f:
		tris.append([v[face[0]], v[face[1]], v[face[2]]])
	for s in subdiv:
		var next: Array = []
		for tri in tris:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var ab: Vector3 = ((a + b) * 0.5).normalized()
			var bc: Vector3 = ((b + c) * 0.5).normalized()
			var ca: Vector3 = ((c + a) * 0.5).normalized()
			next.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		tris = next
	return tris

static func _build_bush(variant: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var greens: Array[Color] = [Color(0.2, 0.36, 0.15), Color(0.25, 0.42, 0.17), Color(0.17, 0.31, 0.14), Color(0.3, 0.45, 0.2)]
	var spheres: Array = []
	var n: int = 3 + variant % 4
	for i in n:
		var a: float = TAU * i / n + rng.randf_range(-0.4, 0.4)
		var d: float = 0.0 if i == 0 else rng.randf_range(0.2, 0.42)
		var r: float = rng.randf_range(0.34, 0.5) if i > 0 else 0.52
		spheres.append([Vector3(cos(a) * d, r * 0.85 + rng.randf_range(0.0, 0.15), sin(a) * d), r, greens[rng.randi() % greens.size()]])
	# Варианты 4–5 — с ягодами (шиповник / рябина), 3 — цветущий.
	var dots: Color = Color(0.85, 0.12, 0.1) if variant >= 4 else (Color(0.97, 0.95, 0.9) if variant == 3 else Color(0, 0, 0, 0))
	var extra := Callable()
	if dots.a > 0.0:
		var berry_rng := RandomNumberGenerator.new()
		berry_rng.seed = 991 + variant
		extra = func(st: SurfaceTool) -> void:
			for k in 22:
				var sph: Array = spheres[berry_rng.randi() % spheres.size()]
				var dir := Vector3(berry_rng.randf_range(-1, 1), berry_rng.randf_range(-0.2, 1), berry_rng.randf_range(-1, 1)).normalized()
				var p: Vector3 = (sph[0] as Vector3) + dir * float(sph[1]) * 1.02
				var s: float = 0.035
				_tri(st, p + Vector3(-s, 0, -s), p + Vector3(s, 0, -s), p + Vector3(0, s * 1.6, 0), dots, dots, dots, p)
				_tri(st, p + Vector3(s, 0, -s), p + Vector3(0, 0, s), p + Vector3(0, s * 1.6, 0), dots, dots, dots, p)
				_tri(st, p + Vector3(0, 0, s), p + Vector3(-s, 0, -s), p + Vector3(0, s * 1.6, 0), dots, dots, dots, p)
	return _build_blob(spheres, 1, 0.18, rng, extra)

static func _build_stick(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(st, Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.02, 0.0), 0.032, 0.02, Color.WHITE)
	# Сучок.
	_add_prism(st, Vector3(0.05, 0.01, 0.0), Vector3(0.3, 0.03, 0.18), 0.016, 0.01, Color.WHITE)
	return st.commit()

static func _add_prism(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, c: Color) -> void:
	var axis: Vector3 = (b - a).normalized()
	var u: Vector3 = axis.cross(Vector3.UP)
	if u.length() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var w: Vector3 = axis.cross(u).normalized()
	var sides: int = 5
	for i in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		var d0: Vector3 = u * cos(a0) + w * sin(a0)
		var d1: Vector3 = u * cos(a1) + w * sin(a1)
		var mid: Vector3 = (a + b) * 0.5
		_tri(st, a + d0 * ra, b + d0 * rb, b + d1 * rb, c, c, c, mid)
		_tri(st, a + d0 * ra, b + d1 * rb, a + d1 * ra, c, c, c, mid)

static func _build_leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = [Vector3(-0.07, 0.0, 0.0), Vector3(0.0, 0.004, -0.04), Vector3(0.07, 0.0, 0.0), Vector3(0.0, 0.004, 0.04)]
	var c := Color.WHITE
	_tri(st, pts[0], pts[1], pts[2], c, c, c)
	_tri(st, pts[0], pts[2], pts[3], c, c, c)
	return st.commit()

static func _build_mushroom() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stem := Color(0.95, 0.92, 0.85)
	return _build_blob([[Vector3(0.0, 0.11, 0.0), 0.075, Color.WHITE]], 0, 0.1, rng, func(st: SurfaceTool) -> void:
		_add_prism(st, Vector3(0, 0.0, 0), Vector3(0, 0.1, 0.0001), 0.02, 0.018, stem))

static func _build_box(size: Vector3, c: Color, broken_end: bool) -> ArrayMesh:
	var h: Vector3 = size * 0.5
	var p: Array = [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	if broken_end:
		# Обломанный край доски — скошенный торец.
		p[1].x -= size.z * 0.8
		p[2].x -= size.z * 0.8
		p[6].x += size.z * 0.4
	var faces: Array = [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		_tri(st, p[f[0]], p[f[1]], p[f[2]], c, c, c, Vector3.ZERO)
		_tri(st, p[f[0]], p[f[2]], p[f[3]], c, c, c, Vector3.ZERO)
	return st.commit()
