extends RefCounted

## Процедурные модели делянки (всё в вершинных цветах, без текстур): грядка-клетка
## с бороздами, соломенная мульча под клетками, бортик из досок с колышками, табличка,
## разметка стройки (колышки и шнур), куча материалов и культуры по стадиям роста.
## Делянка любого размера собирается из этих частей, поэтому модель масштабируется
## без искажений. Меши кэшируются (общие для всех делянок).

const CELL: float = 1.0
## Отступ грядки внутри клетки — между клетками видна дорожка из мульчи.
const BED_INSET: float = 0.05
const BED_HEIGHT: float = 0.1
const BORDER_HEIGHT: float = 0.2
const BORDER_THICK: float = 0.06

const SOIL: Color = Color(0.5, 0.35, 0.22)
const SOIL_DARK: Color = Color(0.36, 0.24, 0.15)
const STRAW: Color = Color(0.6, 0.49, 0.29)
const WOOD: Color = Color(0.5, 0.35, 0.21)
const WOOD_DARK: Color = Color(0.36, 0.25, 0.15)
const GREEN: Color = Color(0.3, 0.58, 0.2)
const GREEN_LIGHT: Color = Color(0.48, 0.75, 0.3)
const GREEN_DARK: Color = Color(0.18, 0.42, 0.14)
const WITHERED: Color = Color(0.5, 0.4, 0.22)

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}

## Материал по вершинным цветам (instance color MultiMesh умножается на них).
static func material(two_sided: bool = false, unshaded_alpha: float = -1.0) -> StandardMaterial3D:
	var key := "%s|%s" % [two_sided, unshaded_alpha]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded_alpha >= 0.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
	_materials[key] = m
	return m

# --- Примитивы -----------------------------------------------------------------

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	# Лицевая сторона — та, куда смотрит n = (b - a) × (c - a); в Godot лицевые
	# треугольники идут по часовой, поэтому вершины выдаются в порядке a, c, b.
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(b)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)

## Ящик между углами lo и hi (повёрнутый на yaw вокруг центра основания).
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color, top_col: Color = Color(0, 0, 0, 0), yaw: float = 0.0) -> void:
	var c := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var b := Basis(Vector3.UP, yaw)
	var p := func(x: float, y: float, z: float) -> Vector3: return c + b * (Vector3(x, y, z) - c)
	var v := [p.call(lo.x, lo.y, lo.z), p.call(hi.x, lo.y, lo.z), p.call(hi.x, lo.y, hi.z), p.call(lo.x, lo.y, hi.z),
		p.call(lo.x, hi.y, lo.z), p.call(hi.x, hi.y, lo.z), p.call(hi.x, hi.y, hi.z), p.call(lo.x, hi.y, hi.z)]
	var tc: Color = top_col if top_col.a > 0.0 else col.lightened(0.08)
	_quad(st, v[7], v[6], v[5], v[4], tc)
	_quad(st, v[1], v[2], v[3], v[0], col.darkened(0.3))
	_quad(st, v[4], v[5], v[1], v[0], col)
	_quad(st, v[6], v[7], v[3], v[2], col.darkened(0.08))
	_quad(st, v[5], v[6], v[2], v[1], col.darkened(0.04))
	_quad(st, v[7], v[4], v[0], v[3], col.darkened(0.12))

## Сплюснутый «шар» (октаэдр с подразбиением) — клубни, комья, кроны.
static func _blob(st: SurfaceTool, center: Vector3, radius: Vector3, col: Color, rng: RandomNumberGenerator, rough: float = 0.15) -> void:
	var seg: int = 6
	var rings: int = 4
	var pts: Array = []
	for r in rings + 1:
		var row: Array = []
		var phi: float = PI * r / rings
		for s in seg:
			var th: float = TAU * s / seg
			var k: float = 1.0 + rng.randf_range(-rough, rough) if r > 0 and r < rings else 1.0
			row.append(center + Vector3(sin(phi) * cos(th) * radius.x * k, cos(phi) * radius.y * k, sin(phi) * sin(th) * radius.z * k))
		pts.append(row)
	for r in rings:
		for s in seg:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][(s + 1) % seg]
			var c: Vector3 = pts[r + 1][(s + 1) % seg]
			var d: Vector3 = pts[r + 1][s]
			var shade: Color = col.lightened(0.12 * (1.0 - float(r) / rings)).darkened(0.12 * float(r) / rings)
			_quad(st, a, b, c, d, shade)

## Лист-лезвие: от основания base по направлению dir длиной len, ширина width, изгиб bend вниз.
static func _blade(st: SurfaceTool, base: Vector3, dir: Vector3, length: float, width: float, bend: float, col: Color, tip_col: Color) -> void:
	var segs: int = 3
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var prev_l: Vector3 = base - side * width * 0.5
	var prev_r: Vector3 = base + side * width * 0.5
	for i in range(1, segs + 1):
		var t: float = float(i) / segs
		var center: Vector3 = base + dir * length * t + Vector3.DOWN * bend * t * t
		var w: float = width * (1.0 - t * 0.85) * 0.5
		var l: Vector3 = center - side * w
		var r: Vector3 = center + side * w
		var c: Color = col.lerp(tip_col, t)
		_quad(st, prev_l, prev_r, r, l, c)
		prev_l = l
		prev_r = r

## Стебель — тонкая трёхгранная призма.
static func _stalk(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
	var s2 := d.cross(s1).normalized()
	var off: Array = []
	for i in 3:
		var t: float = TAU * i / 3.0
		off.append((s1 * cos(t) + s2 * sin(t)) * r)
	for i in 3:
		var j: int = (i + 1) % 3
		_quad(st, a + off[i], a + off[j], b + off[j] * 0.6, b + off[i] * 0.6, col)

static func _finish(st: SurfaceTool) -> ArrayMesh:
	return st.commit()

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# --- Грядка и мульча -----------------------------------------------------------

## Грядка одной клетки: приподнятая земля с тремя бороздами вдоль Z (центр клетки в 0).
static func soil_cell() -> ArrayMesh:
	if _cache.has("soil"):
		return _cache["soil"]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var half: float = CELL * 0.5 - BED_INSET
	var top: float = half - 0.03
	var nx: int = 12
	var nz: int = 4
	var h := func(x: float) -> float:
		var t: float = (x + top) / (top * 2.0)
		return BED_HEIGHT + 0.035 * (0.5 + 0.5 * cos(TAU * 3.0 * t))
	var grid: Array = []
	for iz in nz + 1:
		var row: Array = []
		for ix in nx + 1:
			var x: float = lerpf(-top, top, float(ix) / nx)
			var z: float = lerpf(-top, top, float(iz) / nz)
			row.append(Vector3(x, h.call(x) + rng.randf_range(-0.006, 0.006), z))
		grid.append(row)
	for iz in nz:
		for ix in nx:
			var a: Vector3 = grid[iz][ix]
			var b: Vector3 = grid[iz][ix + 1]
			var c: Vector3 = grid[iz + 1][ix + 1]
			var d: Vector3 = grid[iz + 1][ix]
			var hy: float = (a.y + b.y + c.y + d.y) * 0.25
			var k: float = clampf((hy - BED_HEIGHT) / 0.035, 0.0, 1.0)
			var col: Color = SOIL_DARK.lerp(SOIL, k) * rng.randf_range(0.95, 1.05)
			col.a = 1.0
			_quad(st, a, d, c, b, col)
	# Скошенные бока грядки до земли.
	var edges := [[Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half)], [Vector3(half, 0.0, -half), Vector3(half, 0.0, half)],
		[Vector3(half, 0.0, half), Vector3(-half, 0.0, half)], [Vector3(-half, 0.0, half), Vector3(-half, 0.0, -half)]]
	for e in 4:
		var a0: Vector3 = edges[e][0]
		var b0: Vector3 = edges[e][1]
		var steps: int = nx if e % 2 == 0 else nz
		for i in steps:
			var p0: Vector3 = a0.lerp(b0, float(i) / steps)
			var p1: Vector3 = a0.lerp(b0, float(i + 1) / steps)
			var t0 := Vector3(clampf(p0.x, -top, top), 0.0, clampf(p0.z, -top, top))
			var t1 := Vector3(clampf(p1.x, -top, top), 0.0, clampf(p1.z, -top, top))
			t0.y = h.call(t0.x)
			t1.y = h.call(t1.x)
			_quad(st, t0, t1, p1, p0, SOIL_DARK)
	_cache["soil"] = _finish(st)
	return _cache["soil"]

## Мульча (солома) под всей делянкой w×h клеток, начало координат — угол делянки.
static func mulch(w: int, h: int) -> ArrayMesh:
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 131 + h
	var y: float = 0.025
	for z in h * 2:
		for x in w * 2:
			var a := Vector3(x * 0.5, y, z * 0.5)
			var col: Color = STRAW * rng.randf_range(0.85, 1.08)
			col.a = 1.0
			_quad(st, a, a + Vector3(0, 0, 0.5), a + Vector3(0.5, 0, 0.5), a + Vector3(0.5, 0, 0), col)
	# Соломинки поверх.
	for i in w * h * 6:
		var p := Vector3(rng.randf() * w, y + 0.004, rng.randf() * h)
		var d := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)) * 0.09
		var s := Vector3(-d.z, 0, d.x).normalized() * 0.006
		_quad(st, p - d - s, p - d + s, p + d + s, p + d - s, STRAW.lightened(rng.randf_range(0.0, 0.25)))
	return _finish(st)

# --- Бортик, табличка, стройка -----------------------------------------------------

## Сегменты бортика по периметру (по часовой от угла (0,0)). Каждый — [начало, конец].
static func border_segments(w: int, h: int) -> Array:
	var segs: Array = []
	var pts := [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
	for e in 4:
		var a: Vector2 = pts[e]
		var b: Vector2 = pts[(e + 1) % 4]
		var n: int = maxi(1, ceili(a.distance_to(b) / 2.0))
		for i in n:
			segs.append([a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n)])
	return segs

## Бортик из первых count сегментов (-1 — весь): доски в два ряда и колышки на стыках.
static func border(w: int, h: int, count: int = -1) -> ArrayMesh:
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 977 + h * 31
	var segs := border_segments(w, h)
	var n: int = segs.size() if count < 0 else mini(count, segs.size())
	var t: float = BORDER_THICK
	for i in n:
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var dir: Vector2 = (b - a).normalized()
		var out := Vector2(dir.y, -dir.x) # наружу при обходе по часовой (в XZ)
		var len: float = a.distance_to(b)
		var yaw: float = -atan2(dir.y, dir.x)
		var mid: Vector2 = (a + b) * 0.5 + out * t * 0.5
		for row in 2:
			var y0: float = row * BORDER_HEIGHT * 0.5 + 0.005
			var col: Color = WOOD.lerp(WOOD_DARK, rng.randf_range(0.0, 0.5))
			var lo := Vector3(mid.x - len * 0.5 + 0.01, y0, mid.y - t * 0.5)
			var hi := Vector3(mid.x + len * 0.5 - 0.01, y0 + BORDER_HEIGHT * 0.5 - 0.01, mid.y + t * 0.5)
			_box(st, lo, hi, col, Color(0, 0, 0, 0), yaw)
		# Колышек в начале сегмента.
		var pc: Vector2 = a + out * t * 0.5
		_post(st, Vector3(pc.x, 0, pc.y), 0.045, BORDER_HEIGHT + 0.09, WOOD_DARK)
	if n == segs.size():
		var pc0: Vector2 = segs[0][0]
		_post(st, Vector3(pc0.x - t * 0.5, 0, pc0.y - t * 0.5), 0.05, BORDER_HEIGHT + 0.1, WOOD_DARK)
	return _finish(st)

## Колышек с заострённым верхом.
static func _post(st: SurfaceTool, base: Vector3, r: float, height: float, col: Color) -> void:
	_box(st, base + Vector3(-r, 0, -r), base + Vector3(r, height, r), col)
	var top: Vector3 = base + Vector3(0, height + r * 1.4, 0)
	var c := [base + Vector3(-r, height, -r), base + Vector3(r, height, -r), base + Vector3(r, height, r), base + Vector3(-r, height, r)]
	for i in 4:
		_tri(st, c[(i + 1) % 4], c[i], top, col.lightened(0.1))

## Табличка на столбике (ставится снаружи у угла делянки).
static func sign_post() -> ArrayMesh:
	if _cache.has("sign"):
		return _cache["sign"]
	var st := _begin()
	_box(st, Vector3(-0.04, 0, -0.04), Vector3(0.04, 0.85, 0.04), WOOD_DARK)
	_box(st, Vector3(-0.3, 0.55, -0.025), Vector3(0.3, 0.88, 0.025), WOOD, WOOD.lightened(0.15))
	_box(st, Vector3(-0.32, 0.86, -0.035), Vector3(0.32, 0.9, 0.035), WOOD_DARK)
	_cache["sign"] = _finish(st)
	return _cache["sign"]

## Разметка стройки: колышки по углам и через 2 м, натянутый шнур.
static func survey(w: int, h: int) -> ArrayMesh:
	var st := _begin()
	var string_col := Color(0.92, 0.88, 0.75)
	for seg in border_segments(w, h):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		_post(st, Vector3(a.x, 0, a.y), 0.025, 0.32, Color(0.85, 0.7, 0.45))
		var d := Vector3(b.x - a.x, 0, b.y - a.y)
		var s := Vector3(-d.z, 0, d.x).normalized() * 0.008
		var p0 := Vector3(a.x, 0.25, a.y)
		var p1 := Vector3(b.x, 0.25, b.y)
		_quad(st, p0 - s, p1 - s, p1 + s, p0 + s, string_col)
		_quad(st, p0 + Vector3.UP * 0.008, p1 + Vector3.UP * 0.008, p1 - Vector3.UP * 0.008, p0 - Vector3.UP * 0.008, string_col)
	return _finish(st)

## Куча стройматериалов: брёвна, камни и мешок опилок.
static func material_pile() -> ArrayMesh:
	if _cache.has("pile"):
		return _cache["pile"]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3:
		_box(st, Vector3(-0.35, 0.0 + i * 0.0, -0.2 + i * 0.13), Vector3(0.35, 0.1, -0.1 + i * 0.13), WOOD.lerp(WOOD_DARK, i * 0.3))
	for i in 2:
		_box(st, Vector3(-0.32, 0.1, -0.13 + i * 0.13), Vector3(0.32, 0.2, -0.03 + i * 0.13), WOOD.lightened(0.05))
	for i in 5:
		_blob(st, Vector3(0.5 + rng.randf_range(-0.1, 0.1), 0.06, rng.randf_range(-0.2, 0.2)), Vector3(0.09, 0.07, 0.08), Color(0.55, 0.55, 0.57), rng, 0.25)
	_blob(st, Vector3(-0.6, 0.16, 0.05), Vector3(0.16, 0.17, 0.13), Color(0.78, 0.68, 0.48), rng, 0.08)
	_cache["pile"] = _finish(st)
	return _cache["pile"]

## Рамка подсветки клетки (центр 0, размер size×size клеток).
static func highlight(size: int) -> ArrayMesh:
	var key := "hl%d" % size
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var half: float = size * CELL * 0.5 - 0.02
	var y: float = BED_HEIGHT + 0.06
	var t: float = 0.05
	var col := Color(1.0, 0.95, 0.55, 0.85)
	for e in [[Vector3(-half, y, -half), Vector3(half, y, -half + t)], [Vector3(-half, y, half - t), Vector3(half, y, half)],
			[Vector3(-half, y, -half), Vector3(-half + t, y, half)], [Vector3(half - t, y, -half), Vector3(half, y, half)]]:
		var lo: Vector3 = e[0]
		var hi: Vector3 = e[1]
		_quad(st, lo, Vector3(lo.x, y, hi.z), hi, Vector3(hi.x, y, lo.z), col)
	var fill := Color(1.0, 0.95, 0.55, 0.12)
	_quad(st, Vector3(-half, y, -half), Vector3(-half, y, half), Vector3(half, y, half), Vector3(half, y, -half), fill)
	_cache[key] = _finish(st)
	return _cache[key]

# --- Культуры ------------------------------------------------------------------------

## Меш культуры для стадии: 0 — посев, 1 — всходы, 2 — рост, 3 — зрелая. withered — увядшая.
static func crop(crop_id: String, stage: int, withered: bool = false) -> ArrayMesh:
	var key := "%s|%d|%s" % [crop_id, stage, withered]
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var spots: Array = _plant_spots(crop_id)
	for p in spots:
		var base := Vector3(p.x + rng.randf_range(-0.03, 0.03), BED_HEIGHT + 0.02, p.y + rng.randf_range(-0.03, 0.03))
		if withered:
			_withered_plant(st, crop_id, base, rng)
			continue
		match stage:
			0:
				_blob(st, base + Vector3(0, -0.01, 0), Vector3(0.05, 0.025, 0.05), SOIL_DARK.darkened(0.1), rng, 0.2)
			1:
				_sprout(st, base, rng)
			_:
				match crop_id:
					"carrot":
						_carrot(st, base, rng, stage == 3)
					"potato":
						_potato(st, base, rng, stage == 3)
					"wheat":
						_wheat(st, base, rng, stage == 3)
					"sunflower":
						_sunflower(st, base, rng, stage == 3)
					"onion":
						_onion(st, base, rng, stage == 3)
					"cabbage":
						_cabbage(st, base, rng, stage == 3)
					"tomato":
						_tomato(st, base, rng, stage == 3)
					"pepper":
						_pepper(st, base, rng, stage == 3)
					"bean":
						_bean(st, base, rng, stage == 3)
					"herbs":
						_herbs(st, base, rng, stage == 3)
					"corn":
						_corn(st, base, rng, stage == 3)
					"pumpkin":
						_pumpkin(st, base, rng, stage == 3)
					_:
						_sprout(st, base, rng)
	_cache[key] = _finish(st)
	return _cache[key]

## Точки посадки в клетке: морковь — 2 ряда по 3, картофель/тыква/капуста — 2×2, пшеница — 4×4.
static func _plant_spots(crop_id: String) -> Array:
	var out: Array = []
	match crop_id:
		"potato", "cabbage", "pumpkin":
			for x in [-0.2, 0.2]:
				for z in [-0.2, 0.2]:
					out.append(Vector2(x, z))
		"wheat":
			for x in 4:
				for z in 4:
					out.append(Vector2(-0.3 + x * 0.2, -0.3 + z * 0.2))
		"corn", "sunflower":
			for x in [-0.18, 0.18]:
				for z in [-0.24, 0.0, 0.24]:
					out.append(Vector2(x, z))
		_:
			for x in [-0.15, 0.15]:
				for z in [-0.28, 0.0, 0.28]:
					out.append(Vector2(x, z))
	return out

static func _sprout(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator) -> void:
	var top: Vector3 = base + Vector3(0, 0.06, 0)
	_stalk(st, base, top, 0.006, GREEN)
	var a: float = rng.randf() * TAU
	for k in 2:
		var d := Vector3(cos(a + PI * k), 0.25, sin(a + PI * k)).normalized()
		_blade(st, top, d, 0.05, 0.04, 0.0, GREEN, GREEN_LIGHT)

static func _carrot(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var n: int = 7 if mature else 5
	var length: float = 0.28 if mature else 0.16
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45).normalized()
		_blade(st, base, d, length * rng.randf_range(0.85, 1.1), 0.05, 0.06, GREEN_DARK, GREEN_LIGHT)
	if mature:
		var orange := Color(0.93, 0.47, 0.12)
		var tip: Vector3 = base + Vector3(0, -0.02, 0)
		var r: float = 0.035
		var ring: Array = []
		for i in 6:
			var t: float = TAU * i / 6.0
			ring.append(tip + Vector3(cos(t) * r, 0.03, sin(t) * r))
		for i in 6:
			_tri(st, ring[(i + 1) % 6], ring[i], tip + Vector3(0, 0.045, 0), orange.lightened(0.1))
			_tri(st, ring[i], ring[(i + 1) % 6], tip + Vector3(0, -0.04, 0), orange)

static func _potato(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var size: float = 1.0 if mature else 0.6
	_blob(st, base + Vector3(0, 0.1 * size, 0), Vector3(0.16, 0.11, 0.16) * size, GREEN, rng, 0.25)
	for k in 6:
		var a: float = TAU * k / 6.0 + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.35, sin(a)).normalized()
		_blade(st, base + Vector3(0, 0.08 * size, 0), d, 0.2 * size, 0.11 * size, 0.05 * size, GREEN_DARK, GREEN)
	if mature:
		for k in 4:
			var a2: float = rng.randf() * TAU
			var fp: Vector3 = base + Vector3(cos(a2) * 0.08, 0.22, sin(a2) * 0.08)
			_blob(st, fp, Vector3(0.025, 0.018, 0.025), Color(0.95, 0.93, 0.98), rng, 0.1)
			_blob(st, fp + Vector3(0, 0.012, 0), Vector3(0.008, 0.008, 0.008), Color(0.95, 0.8, 0.2), rng, 0.0)
		for k in 2:
			var a3: float = rng.randf() * TAU
			_blob(st, base + Vector3(cos(a3) * 0.13, -0.01, sin(a3) * 0.13), Vector3(0.045, 0.035, 0.04), Color(0.72, 0.56, 0.34), rng, 0.15)

static func _wheat(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var n: int = 3
	var height: float = 0.55 if mature else 0.28
	var stem_col: Color = Color(0.85, 0.72, 0.36) if mature else GREEN
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.5, 0.5)
		var lean := Vector3(cos(a) * 0.08, 1.0, sin(a) * 0.08).normalized()
		var top: Vector3 = base + lean * height * rng.randf_range(0.9, 1.1)
		_stalk(st, base, top, 0.006, stem_col)
		_blade(st, base + Vector3(0, 0.05, 0), Vector3(cos(a + 1.2), 0.8, sin(a + 1.2)).normalized(), height * 0.45, 0.025, 0.05, GREEN_DARK if not mature else Color(0.75, 0.65, 0.35), stem_col)
		if mature:
			var ear_col := Color(0.93, 0.78, 0.38)
			_blob(st, top + lean * 0.05, Vector3(0.018, 0.06, 0.018), ear_col, rng, 0.1)
			for j in 3:
				var e: Vector3 = top + lean * (0.02 + j * 0.03)
				_blade(st, e, (lean + Vector3(cos(a + j), 0, sin(a + j)) * 0.6).normalized(), 0.05, 0.004, 0.0, ear_col, ear_col.lightened(0.2))

static func _sunflower(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var height: float = 0.65 if mature else 0.35
	var top: Vector3 = base + Vector3(0, height, 0)
	_stalk(st, base, top, 0.012, GREEN_DARK)
	for k in (6 if mature else 4):
		var a: float = k * (TAU / (6.0 if mature else 4.0)) + rng.randf_range(-0.2, 0.2)
		var y_off: float = (0.15 + k * 0.08) * (height / 0.65)
		var d := Vector3(cos(a), 0.3, sin(a)).normalized()
		_blade(st, base + Vector3(0, y_off, 0), d, 0.16, 0.08, 0.04, GREEN, GREEN_LIGHT)
	if mature:
		var head_center: Vector3 = top + Vector3(0, 0.04, 0.05)
		var yellow := Color(0.96, 0.78, 0.15)
		var brown := Color(0.32, 0.20, 0.10)
		_blob(st, head_center, Vector3(0.06, 0.06, 0.03), brown, rng, 0.05)
		for p in 10:
			var ang: float = TAU * p / 10.0
			var pd := Vector3(cos(ang), sin(ang), 0.1).normalized()
			_blade(st, head_center, pd, 0.08, 0.03, 0.01, yellow, yellow.lightened(0.15))

static func _onion(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var n: int = 6 if mature else 4
	var length: float = 0.24 if mature else 0.14
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.25, 0.25)
		var d := Vector3(cos(a) * 0.25, 1.0, sin(a) * 0.25).normalized()
		_blade(st, base, d, length * rng.randf_range(0.85, 1.15), 0.025, 0.03, GREEN, GREEN_LIGHT)
	if mature:
		var onion_col := Color(0.80, 0.55, 0.30)
		_blob(st, base + Vector3(0, 0.02, 0), Vector3(0.04, 0.035, 0.04), onion_col, rng, 0.1)

static func _cabbage(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var n: int = 8 if mature else 5
	var r: float = 0.18 if mature else 0.10
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.25, sin(a)).normalized()
		_blade(st, base + Vector3(0, 0.02, 0), d, r, 0.12 if mature else 0.07, 0.05, GREEN_DARK, GREEN)
	if mature:
		var head_col := Color(0.55, 0.82, 0.45)
		_blob(st, base + Vector3(0, 0.08, 0), Vector3(0.09, 0.075, 0.09), head_col, rng, 0.1)

static func _tomato(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var height: float = 0.45 if mature else 0.25
	var top: Vector3 = base + Vector3(0, height, 0)
	_stalk(st, base, top, 0.01, GREEN_DARK)
	for k in (6 if mature else 4):
		var a: float = k * (TAU / 5.0) + rng.randf_range(-0.2, 0.2)
		var y: float = 0.1 + k * 0.06 * (height / 0.45)
		var d := Vector3(cos(a), 0.4, sin(a)).normalized()
		_blade(st, base + Vector3(0, y, 0), d, 0.14, 0.06, 0.03, GREEN, GREEN_LIGHT)
	if mature:
		var red := Color(0.88, 0.20, 0.15)
		for t in 4:
			var ang: float = t * (TAU / 4.0) + rng.randf_range(-0.2, 0.2)
			var tp: Vector3 = base + Vector3(cos(ang) * 0.09, 0.18 + t * 0.05, sin(ang) * 0.09)
			_blob(st, tp, Vector3(0.03, 0.03, 0.03), red, rng, 0.05)

static func _pepper(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var height: float = 0.35 if mature else 0.20
	var top: Vector3 = base + Vector3(0, height, 0)
	_stalk(st, base, top, 0.009, GREEN_DARK)
	for k in (5 if mature else 3):
		var a: float = k * (TAU / 4.0) + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.35, sin(a)).normalized()
		_blade(st, base + Vector3(0, 0.08 + k * 0.05, 0), d, 0.12, 0.05, 0.03, GREEN, GREEN_LIGHT)
	if mature:
		var pepper_col := Color(0.85, 0.15, 0.12)
		for p in 3:
			var ang: float = p * (TAU / 3.0) + 0.3
			var pp: Vector3 = base + Vector3(cos(ang) * 0.08, 0.14, sin(ang) * 0.08)
			_blob(st, pp, Vector3(0.022, 0.04, 0.022), pepper_col, rng, 0.08)

static func _bean(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var height: float = 0.50 if mature else 0.28
	var top: Vector3 = base + Vector3(0, height, 0)
	_box(st, base + Vector3(-0.012, 0, -0.012), base + Vector3(0.012, height + 0.05, 0.012), WOOD_DARK)
	_stalk(st, base, top, 0.008, GREEN_DARK)
	for k in (7 if mature else 4):
		var a: float = k * 1.0 + rng.randf_range(-0.2, 0.2)
		var y: float = 0.06 + k * 0.06 * (height / 0.50)
		var d := Vector3(cos(a), 0.3, sin(a)).normalized()
		_blade(st, base + Vector3(0, y, 0), d, 0.09, 0.045, 0.02, GREEN, GREEN_LIGHT)
	if mature:
		var pod_col := Color(0.42, 0.72, 0.30)
		for p in 4:
			var a2: float = p * 1.5
			var bp: Vector3 = base + Vector3(cos(a2) * 0.05, 0.15 + p * 0.07, sin(a2) * 0.05)
			_blade(st, bp, Vector3(cos(a2) * 0.2, -1.0, sin(a2) * 0.2).normalized(), 0.09, 0.02, 0.02, pod_col, pod_col.lightened(0.1))

static func _herbs(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var n: int = 12 if mature else 6
	var len_val: float = 0.18 if mature else 0.10
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a) * 0.5, 0.85, sin(a) * 0.5).normalized()
		_stalk(st, base, base + lean * len_val, 0.004, GREEN)
		_blade(st, base + lean * (len_val * 0.5), lean, len_val * 0.55, 0.03, 0.03, GREEN_DARK, GREEN_LIGHT)

static func _corn(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var height: float = 0.75 if mature else 0.40
	var top: Vector3 = base + Vector3(0, height, 0)
	_stalk(st, base, top, 0.014, GREEN_DARK)
	for k in (8 if mature else 4):
		var a: float = k * (TAU / 4.0) + rng.randf_range(-0.15, 0.15)
		var y: float = 0.12 + k * 0.07 * (height / 0.75)
		var d := Vector3(cos(a), 0.2, sin(a)).normalized()
		_blade(st, base + Vector3(0, y, 0), d, 0.28, 0.065, 0.12, GREEN, GREEN_LIGHT)
	if mature:
		var yellow := Color(0.95, 0.82, 0.20)
		for c in 2:
			var ca: float = c * PI + 0.5
			var cp: Vector3 = base + Vector3(cos(ca) * 0.04, 0.32 + c * 0.12, sin(ca) * 0.04)
			_blob(st, cp, Vector3(0.025, 0.065, 0.025), yellow, rng, 0.05)
			_blade(st, cp + Vector3(0, -0.03, 0), Vector3(cos(ca), 0.6, sin(ca)).normalized(), 0.10, 0.03, 0.02, GREEN_LIGHT, GREEN)

static func _pumpkin(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator, mature: bool) -> void:
	var vine_len: float = 0.30 if mature else 0.15
	for v in 3:
		var va: float = v * (TAU / 3.0) + rng.randf_range(-0.2, 0.2)
		var vd := Vector3(cos(va), 0.05, sin(va)).normalized()
		_stalk(st, base, base + vd * vine_len, 0.007, GREEN_DARK)
		for l in (3 if mature else 2):
			var lp: Vector3 = base + vd * (l * 0.1)
			_blade(st, lp, (vd + Vector3(sin(va * 2.0), 0.4, cos(va * 2.0))).normalized(), 0.12, 0.09, 0.03, GREEN, GREEN_LIGHT)
	if mature:
		var orange := Color(0.92, 0.50, 0.12)
		var p_pos: Vector3 = base + Vector3(0.08, 0.06, 0.06)
		_blob(st, p_pos, Vector3(0.11, 0.08, 0.11), orange, rng, 0.15)
		_box(st, p_pos + Vector3(-0.015, 0.07, -0.015), p_pos + Vector3(0.015, 0.11, 0.015), GREEN_DARK)

static func _withered_plant(st: SurfaceTool, crop_id: String, base: Vector3, rng: RandomNumberGenerator) -> void:
	var n: int = 3 if crop_id in ["wheat", "corn", "sunflower"] else 5
	var len_base: float = 0.28 if crop_id in ["wheat", "corn", "sunflower"] else 0.16
	for k in n:
		var a: float = TAU * k / n + rng.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a), 0.6, sin(a)).normalized()
		_blade(st, base, d, len_base, 0.04, 0.1, WITHERED.darkened(0.2), WITHERED.lightened(0.15))

