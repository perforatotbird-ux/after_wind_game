extends SceneTree

## Генератор деревьев по референсам (стилизованные дуб и сосна).
##  * Дуб: мощный ствол с корневыми наплывами, ветви к «облакам» листвы; каждое облако —
##    тёмное ядро + черепица из крупных лопастных листьев (светлый верх, тёмный низ).
##  * Сосна: прямой ствол, голый снизу (сухие сучки), ярусы поникших «лап» —
##    плоских веерных ветвей с пальцами-хвоинками, к верхушке короче (конус).
## Варианты: tree_oak (большой дуб), tree_oak_young (молодой стройный дуб),
##           tree_pine (коническая сосна), tree_pine_wide (раскидистая сосна).
## Модели детерминированы (seed). Кора — triplanar-нет: UV по стволу, текстура встроена
## в материал (PortableCompressedTexture2D) — бинарников в репозитории нет.
##
## Запуск (из корня проекта):
##   python3 tools/generate_tree_textures.py
##   Godot --headless --path . -s tools/generate_trees.gd

const OUT := "res://assets/models/trees/"
const SCENES := "res://scenes/resources/"
const BARK_PNG := "res://.godot/bark_albedo.png"
const UP := Vector3.UP

## Параметры вариантов и ресурсные характеристики (ResourceNode).
const TREES: Dictionary = {
	"tree_oak": {"kind": "oak", "seed": 101, "name": "Дуб", "hits": 4, "yield": 3, "bonus": 3,
		"trunk_h": 2.3, "r0": 0.42, "r1": 0.26, "crown_c": Vector3(0, 4.0, 0), "crown_r": Vector3(2.5, 1.5, 2.4),
		"clumps": 13, "clump_r": [0.85, 1.25]},
	"tree_oak_young": {"kind": "oak_young", "seed": 202, "name": "Молодой дуб", "hits": 3, "yield": 2, "bonus": 2,
		"trunk_h": 4.4, "r0": 0.17, "r1": 0.08, "clumps": 6, "clump_r": [0.55, 0.8]},
	"tree_pine": {"kind": "pine", "seed": 303, "name": "Сосна", "hits": 3, "yield": 2, "bonus": 2,
		"h": 7.2, "r0": 0.2, "r1": 0.03, "bare": 2.3, "spread": 1.7},
	"tree_pine_wide": {"kind": "pine_wide", "seed": 404, "name": "Сосна", "hits": 4, "yield": 3, "bonus": 3,
		"h": 6.4, "r0": 0.32, "r1": 0.05, "bare": 1.4, "spread": 2.3},
}

var rng := RandomNumberGenerator.new()
var bark_st: SurfaceTool
var leaf_st: SurfaceTool
var mats: Dictionary = {}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_make_materials()
	for name in TREES:
		var p: Dictionary = TREES[name]
		rng.seed = p["seed"]
		_begin()
		var trunk_r := 0.0
		match p["kind"]:
			"oak":
				trunk_r = _oak(p)
			"oak_young":
				trunk_r = _oak_young(p)
			"pine", "pine_wide":
				trunk_r = _pine(p)
		var leaf_mat: Material = mats["needles"] if String(p["kind"]).begins_with("pine") else mats["leaves"]
		var bark_mat: Material = mats["bark_pine"] if String(p["kind"]).begins_with("pine") else mats["bark_oak"]
		var mesh := _commit(bark_mat, leaf_mat)
		ResourceSaver.save(mesh, OUT + name + ".tres")
		# Пень.
		rng.seed = int(p["seed"]) + 7
		_begin()
		_stump(trunk_r, p["kind"])
		var stump := _commit(bark_mat, mats["wood_cut"])
		ResourceSaver.save(stump, OUT + name + "_stump.tres")
		var a := mesh.get_aabb()
		print("%-16s tris=%d size=%s trunk_r=%.2f" % [name, _tri_count(mesh), a.size, trunk_r])
		_save_scene(name, p, load(OUT + name + ".tres"), load(OUT + name + "_stump.tres"), trunk_r)
	quit()

# ---------------------------------------------------------------- materials

func _make_materials() -> void:
	var tex: Texture2D = null
	var img := Image.load_from_file(ProjectSettings.globalize_path(BARK_PNG))
	if img == null or img.is_empty():
		push_error("Нет %s — сначала запустите python3 tools/generate_tree_textures.py" % BARK_PNG)
	else:
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
		var t := PortableCompressedTexture2D.new()
		t.keep_compressed_buffer = true
		t.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		t.resource_name = "Bark"
		# Отдельный ресурс: обе коры ссылаются на одну текстуру (не дублируется в .tres).
		ResourceSaver.save(t, OUT + "bark_texture.tres")
		tex = load(OUT + "bark_texture.tres")
	for key in ["bark_oak", "bark_pine"]:
		var m := StandardMaterial3D.new()
		m.resource_name = key
		m.albedo_color = Color(0.5, 0.34, 0.22) if key == "bark_oak" else Color(0.4, 0.26, 0.2)
		m.albedo_texture = tex
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		ResourceSaver.save(m, OUT + key + ".tres")
		mats[key] = load(OUT + key + ".tres")
	for key in ["leaves", "needles", "wood_cut"]:
		var m := StandardMaterial3D.new()
		m.resource_name = key
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.88 if key != "wood_cut" else 0.95
		if key != "wood_cut":
			# Листья/лапы — односторонняя геометрия, видимая с обеих сторон.
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ResourceSaver.save(m, OUT + key + ".tres")
		mats[key] = load(OUT + key + ".tres")

# ---------------------------------------------------------------- mesh helpers

func _begin() -> void:
	bark_st = SurfaceTool.new()
	bark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf_st = SurfaceTool.new()
	leaf_st.begin(Mesh.PRIMITIVE_TRIANGLES)

func _commit(m0: Material, m1: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	bark_st.index()
	bark_st.commit(mesh)
	mesh.surface_set_material(0, m0)
	leaf_st.index()
	leaf_st.commit(mesh)
	mesh.surface_set_material(1, m1)
	return mesh

func _tri_count(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return n

## Треугольник с правильным (по часовой) обходом относительно средней нормали.
func _tri(st: SurfaceTool, p: Array, n: Array, c: Array, uv: Array = []) -> void:
	var order := [0, 1, 2]
	var avg: Vector3 = (n[0] + n[1] + n[2])
	if ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).dot(avg) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_color(c[i])
		st.set_normal((n[i] as Vector3).normalized())
		if not uv.is_empty():
			st.set_uv(uv[i])
		st.add_vertex(p[i])

func _bezier(a: Vector3, b: Vector3, c: Vector3, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out

func _bezier3(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var t := float(i) / n
		var ab := a.lerp(b, t); var bc := b.lerp(c, t); var cd := c.lerp(d, t)
		out.append(ab.lerp(bc, t).lerp(bc.lerp(cd, t), t))
	return out

## Трубка вдоль полилинии: радиусы по точкам, параллельный перенос рамки.
## flare: {"amp", "lobes", "decay", "phase"} — корневые наплывы у основания.
func _tube(pts: Array, rad: Array, sides: int, col0: Color, col1: Color, flare: Dictionary = {}, cap := true) -> void:
	var n := pts.size()
	var T: Array = []
	for i in n:
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, n - 1)]
		T.append((b - a).normalized())
	var N0: Vector3 = (T[0] as Vector3).cross(Vector3.RIGHT if absf((T[0] as Vector3).x) < 0.9 else Vector3.FORWARD).normalized()
	var frames: Array = []
	var Nc := N0
	for i in n:
		var t: Vector3 = T[i]
		Nc = (Nc - t * Nc.dot(t)).normalized()
		frames.append([Nc, t.cross(Nc).normalized()])
	var u_rep := maxf(1.0, roundf(TAU * float(rad[0]) / 0.45))
	var rings: Array = []
	var s_len := 0.0
	for i in n:
		if i > 0:
			s_len += (pts[i] - pts[i - 1] as Vector3).length()
		var ring: Array = []
		var h: float = (pts[i] as Vector3).y
		for j in sides + 1:
			var ang := TAU * j / sides
			var dir: Vector3 = frames[i][0] * cos(ang) + frames[i][1] * sin(ang)
			var r: float = rad[i]
			if not flare.is_empty():
				var lob := pow(maxf(0.0, cos(flare["lobes"] * ang + flare["phase"])), 2.0)
				r *= 1.0 + flare["amp"] * exp(-h / flare["decay"]) * (0.3 + 0.7 * lob)
			var col := col0.lerp(col1, float(i) / maxf(1.0, n - 1))
			ring.append([pts[i] + dir * r, dir, Vector2(u_rep * j / sides, s_len / 0.9), col])
		rings.append(ring)
	for i in n - 1:
		for j in sides:
			var a: Array = rings[i][j]; var b: Array = rings[i + 1][j]
			var c: Array = rings[i + 1][j + 1]; var d: Array = rings[i][j + 1]
			_tri(bark_st, [a[0], b[0], c[0]], [a[1], b[1], c[1]], [a[3], b[3], c[3]], [a[2], b[2], c[2]])
			_tri(bark_st, [a[0], c[0], d[0]], [a[1], c[1], d[1]], [a[3], c[3], d[3]], [a[2], c[2], d[2]])
	if cap:
		var tip: Vector3 = pts[n - 1] + (T[n - 1] as Vector3) * float(rad[n - 1]) * 1.2
		var last: Array = rings[n - 1]
		for j in sides:
			_tri(bark_st, [last[j][0], last[j + 1][0], tip], [last[j][1], last[j + 1][1], T[n - 1]],
				[last[j][3], last[j + 1][3], last[j][3]], [last[j][2], last[j + 1][2], last[j][2]])

func _radii(n: int, r0: float, r1: float, pw := 1.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(lerpf(r0, r1, pow(float(i) / (n - 1), pw)))
	return out

# ---------------------------------------------------------------- oak

const BARK_DARK := Color(0.62, 0.6, 0.55)
const BARK_MID := Color(1.0, 1.0, 1.0)

func _oak(p: Dictionary) -> float:
	var th: float = p["trunk_h"]
	var top := Vector3(rng.randf_range(-0.15, 0.15), th, rng.randf_range(-0.15, 0.15))
	var trunk := _bezier3(Vector3.ZERO, Vector3(0, th * 0.35, 0), Vector3(top.x * 0.3, th * 0.7, top.z * 0.3), top, 10)
	var flare := {"amp": 0.75, "lobes": 5.0, "decay": 0.45, "phase": rng.randf() * TAU}
	_tube(trunk, _radii(trunk.size(), p["r0"], p["r1"], 0.8), 14, BARK_DARK, BARK_MID, flare, false)
	# Облака листвы на оболочке эллипсоида кроны (верхняя полусфера + пояс).
	var cc: Vector3 = p["crown_c"]
	var cr: Vector3 = p["crown_r"]
	var k: int = p["clumps"]
	var centers: Array = [cc + Vector3(0, cr.y * 0.55, 0)]
	var golden := PI * (3.0 - sqrt(5.0))
	for i in k - 1:
		var y := 0.85 - 1.25 * float(i) / (k - 2)
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var a := golden * i + rng.randf_range(-0.3, 0.3)
		centers.append(cc + Vector3(cos(a) * rr * cr.x, y * cr.y, sin(a) * rr * cr.z) * rng.randf_range(0.78, 0.95))
	var cr_range: Array = p["clump_r"]
	for c in centers:
		var r := rng.randf_range(cr_range[0], cr_range[1])
		# Ветвь: от верха ствола к облаку, с подъёмом.
		var start := trunk[int(rng.randf_range(0.75, 0.95) * (trunk.size() - 1))] as Vector3
		var out: Vector3 = c - start
		var ctrl := start + Vector3(out.x * 0.25, out.y * 0.55 + 0.3, out.z * 0.25)
		var end: Vector3 = c - out.normalized() * r * 0.35
		var br := _bezier(start, ctrl, end, 6)
		_tube(br, _radii(br.size(), float(p["r1"]) * 0.7, 0.05, 0.9), 7, BARK_MID, BARK_MID)
		_leaf_clump(c, r)
	return p["r0"]

func _oak_young(p: Dictionary) -> float:
	var th: float = p["trunk_h"]
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var trunk := _bezier3(Vector3.ZERO, Vector3(0, th * 0.4, 0) - lean * 0.3, Vector3(0, th * 0.75, 0) + lean, Vector3(0, th, 0) + lean * 0.6, 10)
	var flare := {"amp": 0.5, "lobes": 4.0, "decay": 0.3, "phase": rng.randf() * TAU}
	_tube(trunk, _radii(trunk.size(), p["r0"], p["r1"], 1.0), 9, BARK_DARK, BARK_MID, flare)
	var cr_range: Array = p["clump_r"]
	var top: Vector3 = trunk[trunk.size() - 1]
	_leaf_clump(top + Vector3(0, 0.35, 0), cr_range[1])
	var k: int = p["clumps"]
	for i in k - 1:
		var t := lerpf(0.5, 0.85, float(i) / (k - 2))
		var start := trunk[int(t * (trunk.size() - 1))] as Vector3
		var a := TAU * 0.38 * i + rng.randf_range(-0.4, 0.4)
		var length := lerpf(1.1, 0.6, float(i) / (k - 2))
		var end: Vector3 = start + Vector3(cos(a) * length, 0.55 + 0.3 * length, sin(a) * length)
		var br := _bezier(start, start + Vector3(cos(a) * length * 0.4, 0.25, sin(a) * length * 0.4), end, 5)
		_tube(br, _radii(br.size(), float(p["r0"]) * 0.4, 0.03), 6, BARK_MID, BARK_MID)
		_leaf_clump(end + Vector3(0, 0.2, 0), rng.randf_range(cr_range[0], cr_range[1]))
	# Сухой сучок на стволе (как на референсе).
	var s0 := trunk[4] as Vector3
	_tube([s0, s0 + Vector3(0.25, 0.12, 0.05)], [0.035, 0.012], 5, BARK_MID, BARK_MID)
	return p["r0"]

const LEAF_DARK := Color(0.09, 0.22, 0.1)
const LEAF_MID := Color(0.2, 0.4, 0.16)
const LEAF_LIGHT := Color(0.42, 0.6, 0.24)

## Облако листвы: тёмное ядро + крупные лопастные листья черепицей по сфере.
func _leaf_clump(c: Vector3, r: float) -> void:
	# Ядро (закрывает просветы между листьями).
	var golden := PI * (3.0 - sqrt(5.0))
	var core_n := 42
	var core_pts: Array = []
	for i in core_n:
		var y := 1.0 - 2.0 * (i + 0.5) / core_n
		var rr := sqrt(1.0 - y * y)
		var a := golden * i
		core_pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
	var hull := _sphere_tris(core_pts)
	for t in hull:
		var ps: Array = []; var ns: Array = []; var cs: Array = []
		for idx in t:
			var d: Vector3 = core_pts[idx]
			ps.append(c + d * r * 0.78 * Vector3(1, 0.85, 1))
			ns.append(d)
			cs.append(LEAF_DARK.lerp(LEAF_MID, clampf(d.y * 0.5 + 0.4, 0, 1)))
		_tri(leaf_st, ps, ns, cs)
	# Листья.
	var count := int(62.0 * r * r) + 14
	for i in count:
		var y := 1.0 - 1.75 * (i + 0.5) / count   # от макушки до ~ -0.75 (снизу листьев меньше)
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var a := golden * i + rng.randf_range(-0.2, 0.2)
		var n := Vector3(cos(a) * rr, y, sin(a) * rr).normalized()
		var size := r * rng.randf_range(0.42, 0.55)
		_leaf(c + n * r * Vector3(1, 0.85, 1) * rng.randf_range(0.86, 1.0), n, size)

## Лопастной лист: веер из центра, контур r(θ) с 5 лопастями; висит «черепицей» вниз.
func _leaf(at: Vector3, n: Vector3, size: float) -> void:
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if down.length() < 0.05:
		down = Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5)
	var t := down.normalized()
	var b := n.cross(t).normalized()
	# Лёгкий наклон наружу: лист «отслаивается» от облака.
	var tilt := 0.35
	var tt := (t * cos(tilt) + n * sin(tilt)).normalized()
	var nn := tt.cross(b).normalized() * signf(tt.cross(b).dot(n))
	var center := at + tt * size * 0.35
	var shade := clampf(n.y * 0.55 + 0.45, 0.0, 1.0)
	var base_col := LEAF_DARK.lerp(LEAF_MID, shade).lerp(LEAF_LIGHT, pow(shade, 3.0) * 0.8)
	base_col = base_col * rng.randf_range(0.9, 1.1)
	var center_col := base_col.lerp(LEAF_LIGHT, 0.45 * shade + 0.1)
	var edge_col := base_col * 0.82
	var shade_n := (n * 0.75 + UP * 0.35).normalized()
	var seg := 10
	var pts: Array = []
	for k in seg:
		var th := TAU * k / seg
		var lobe := 0.72 + 0.28 * absf(cos(2.5 * th))
		var rad := size * 0.5 * lobe
		# Вытянут вдоль tt (к кончику) и немного прогнут.
		var lp := tt * cos(th) * rad * 1.15 + b * sin(th) * rad
		lp += nn * (-0.12 * size * (1.0 - absf(sin(th))))
		pts.append(center + lp)
	for k in seg:
		_tri(leaf_st, [center + nn * size * 0.04, pts[k], pts[(k + 1) % seg]], [shade_n, shade_n, shade_n], [center_col, edge_col, edge_col])

## Треугольники выпуклой оболочки точек на единичной сфере (перебор: точек мало).
func _sphere_tris(pts: Array) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a: Vector3 = pts[i]; var b: Vector3 = pts[j]; var c: Vector3 = pts[k]
				var nrm := (b - a).cross(c - a)
				if nrm.length_squared() < 1e-10:
					continue
				nrm = nrm.normalized()
				var d := nrm.dot(a)
				var pos := 0; var neg := 0
				for m in n:
					if m == i or m == j or m == k:
						continue
					var s := nrm.dot(pts[m]) - d
					if s > 1e-6: pos += 1
					elif s < -1e-6: neg += 1
					if pos > 0 and neg > 0: break
				if pos == 0 or neg == 0:
					out.append([i, j, k])
	return out

# ---------------------------------------------------------------- pine

const NEEDLE_DARK := Color(0.05, 0.14, 0.09)
const NEEDLE_MID := Color(0.1, 0.24, 0.13)
const NEEDLE_LIGHT := Color(0.24, 0.4, 0.2)

func _pine(p: Dictionary) -> float:
	var h: float = p["h"]
	var wide := String(p["kind"]) == "pine_wide"
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var trunk := _bezier3(Vector3.ZERO, Vector3(0, h * 0.33, 0), Vector3(0, h * 0.66, 0) + lean, Vector3(0, h, 0) + lean * 1.5, 14)
	var flare := {"amp": 0.45 if wide else 0.3, "lobes": 4.0, "decay": 0.35, "phase": rng.randf() * TAU}
	_tube(trunk, _radii(trunk.size(), p["r0"], p["r1"], 1.0), 10, BARK_DARK, BARK_MID, flare)
	var trunk_at := func(y: float) -> Vector3:
		var t := clampf(y / h, 0.0, 1.0) * (trunk.size() - 1)
		var i := mini(int(t), trunk.size() - 2)
		return (trunk[i] as Vector3).lerp(trunk[i + 1], t - i)
	var bare: float = p["bare"]
	var spread: float = p["spread"]
	# Сухие сучки на голом стволе.
	for i in 3:
		var y := lerpf(bare * 0.45, bare * 0.95, float(i) / 2.0)
		var a := rng.randf() * TAU
		var s0: Vector3 = trunk_at.call(y)
		var d := Vector3(cos(a), -0.15, sin(a))
		_tube([s0, s0 + d * 0.35, s0 + d * 0.5 + Vector3(0, 0.08, 0)], [0.03, 0.018, 0.01], 5, BARK_MID, BARK_MID)
	var golden := PI * (3.0 - sqrt(5.0))
	var idx := 0
	if not wide:
		# Коническая: частые ярусы, длина лап убывает к вершине.
		var y := bare
		while y < h - 0.35:
			var f := (y - bare) / (h - bare)
			var length := spread * pow(1.0 - f, 0.85) + 0.35
			for k in 5:
				var a := golden * idx + rng.randf_range(-0.25, 0.25)
				idx += 1
				_pine_branch(trunk_at.call(y + rng.randf_range(-0.08, 0.08)), a, length * rng.randf_range(0.85, 1.1), f, 0.18)
			y += lerpf(0.3, 0.22, f)
	else:
		# Раскидистая: 4 яруса длинных «рук» с веерами лап + плотная крона наверху.
		var tiers := [[bare + 0.3, 2.3], [bare + 1.4, 2.0], [bare + 2.5, 1.75], [bare + 3.4, 1.4]]
		for tier in tiers:
			var count := 4
			for k in count:
				var a := golden * idx + rng.randf_range(-0.3, 0.3)
				idx += 1
				var s0: Vector3 = trunk_at.call(tier[0] + rng.randf_range(-0.15, 0.15))
				var length: float = tier[1] * rng.randf_range(0.8, 1.1)
				var dir := Vector3(cos(a), 0.0, sin(a))
				var arm_end := s0 + dir * length * 0.65 + Vector3(0, 0.25, 0)
				var arm := _bezier(s0, s0 + dir * length * 0.35 + Vector3(0, 0.25, 0), arm_end, 5)
				_tube(arm, _radii(arm.size(), float(p["r0"]) * 0.32, 0.03), 6, BARK_MID, BARK_MID)
				var f := (float(tier[0]) - bare) / (h - bare)
				for m in 5:
					var fa: float = a + (m - 2) * 0.5 + rng.randf_range(-0.12, 0.12)
					_pine_branch(arm_end + Vector3(0, rng.randf_range(-0.1, 0.15), 0), fa, length * rng.randf_range(0.45, 0.65), f, 0.22)
				for m in 2:
					_pine_branch(arm[2] + Vector3(0, 0.05, 0), a + (m - 0.5) * 1.1, length * 0.4, f, 0.2)
		var y := bare + 3.9
		while y < h - 0.3:
			var f := (y - bare) / (h - bare)
			var length := 1.4 * pow(1.0 - f, 0.7) + 0.35
			for k in 4:
				var a := golden * idx + rng.randf_range(-0.25, 0.25)
				idx += 1
				_pine_branch(trunk_at.call(y), a, length * rng.randf_range(0.85, 1.1), f, 0.15)
			y += 0.28
	# Верхушка: пучок лап вверх.
	var tip: Vector3 = trunk[trunk.size() - 1]
	for k in 4:
		_pine_frond(tip - Vector3(0, 0.15, 0), Vector3(cos(k * 1.57) * 0.35, 1.0, sin(k * 1.57) * 0.35).normalized(), 0.55, 1.0, 0.0)
	_pine_frond(tip - Vector3(0, 0.3, 0), UP, 0.6, 1.0, 0.0)
	return p["r0"]

## Ветка-лапа: короткая тонкая ветвь + плоская поникшая веерная лапа.
func _pine_branch(start: Vector3, ang: float, length: float, f: float, up: float) -> void:
	var dir := Vector3(cos(ang), up, sin(ang)).normalized()
	_tube([start, start + dir * length * 0.4], [0.03, 0.015], 4, BARK_MID, BARK_MID, {}, false)
	_pine_frond(start + dir * 0.05, dir, length, f, 0.35 + 0.25 * (1.0 - f))
	# Второй, чуть меньший слой под основным — лапа становится пышной.
	var d2 := dir.rotated(UP, rng.randf_range(-0.35, 0.35))
	_pine_frond(start + dir * 0.12 - Vector3(0, 0.07, 0), d2, length * 0.8, f, 0.5 + 0.25 * (1.0 - f))

## Лапа: центральная полоса + «пальцы» по бокам и на конце; прогиб вниз (droop).
func _pine_frond(origin: Vector3, dir: Vector3, length: float, f: float, droop: float) -> void:
	var x := dir.normalized()
	var side := x.cross(UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var upv := side.cross(x).normalized()
	if upv.y < 0.0:
		upv = -upv
	var tone := lerpf(0.9, 1.12, f) * rng.randf_range(0.92, 1.08)
	var to_world := func(lx: float, lz: float) -> Vector3:
		var u := lx / length
		var ly := -droop * length * u * u - 0.22 * absf(lz) * (0.4 + u)
		return origin + x * lx + side * lz + upv * ly
	var nrm := (upv * 0.75 + Vector3(x.x, 0, x.z) * 0.45).normalized()
	var fingers: Array = []
	# Центральная полоса (основа лапы).
	fingers.append([0.0, 0.0, 0.0, length * 1.02, length * 0.17])
	var nf := 5
	for k in nf:
		var u := lerpf(0.22, 0.8, float(k) / (nf - 1))
		for s in [-1.0, 1.0]:
			var fa: float = s * lerpf(0.75, 0.5, u)     # угол пальца к оси
			fingers.append([u * length, fa, 0.0, length * lerpf(0.46, 0.28, u) * rng.randf_range(0.85, 1.1), length * 0.12])
	for fg in fingers:
		var bx: float = fg[0]
		var fa: float = fg[1]
		var fl: float = fg[3]
		var fw: float = fg[4]
		var axis := Vector2(cos(fa), sin(fa))       # (вдоль x, вдоль side)
		var perp := Vector2(-axis.y, axis.x)
		var outline: Array = []
		var seg := 4
		for i in seg + 1:
			var t := float(i) / seg
			var w := fw * sin(PI * minf(1.0, t * 1.15)) * (1.0 - 0.35 * t)
			outline.append([t, w])
		var left: Array = []; var right: Array = []
		for o in outline:
			var t: float = o[0]
			var w: float = o[1]
			var c2 := Vector2(bx, 0) + axis * fl * t
			left.append(c2 + perp * w)
			right.append(c2 - perp * w)
		for i in seg:
			var t0 := float(i) / seg
			var t1 := float(i + 1) / seg
			var c0 := NEEDLE_DARK.lerp(NEEDLE_MID, t0).lerp(NEEDLE_LIGHT, pow(t0, 2.0) * 0.6) * tone
			var c1 := NEEDLE_DARK.lerp(NEEDLE_MID, t1).lerp(NEEDLE_LIGHT, pow(t1, 2.0) * 0.6) * tone
			var a0: Vector2 = left[i]; var a1: Vector2 = left[i + 1]
			var b0: Vector2 = right[i]; var b1: Vector2 = right[i + 1]
			var P := [to_world.call(a0.x, a0.y), to_world.call(a1.x, a1.y), to_world.call(b1.x, b1.y), to_world.call(b0.x, b0.y)]
			_tri(leaf_st, [P[0], P[1], P[2]], [nrm, nrm, nrm], [c0, c1, c1])
			_tri(leaf_st, [P[0], P[2], P[3]], [nrm, nrm, nrm], [c0, c1, c0])

# ---------------------------------------------------------------- stump

func _stump(r0: float, kind: String) -> void:
	var h := 0.45
	var pts := [Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h, 0)]
	var flare := {"amp": 0.7 if kind == "oak" else 0.4, "lobes": 5.0 if kind == "oak" else 4.0, "decay": 0.3, "phase": rng.randf() * TAU}
	_tube(pts, [r0, r0 * 0.97, r0 * 0.95], 14, BARK_DARK, BARK_MID, flare, false)
	# Спил: годичные кольца цветами вершин.
	var c := Vector3(0, h, 0)
	var sides := 14
	var ring_cols := [Color(0.82, 0.66, 0.44), Color(0.7, 0.54, 0.34), Color(0.8, 0.64, 0.42), Color(0.62, 0.45, 0.28)]
	var radii := [0.0, 0.3, 0.55, 0.8, 0.95]
	for k in range(1, radii.size()):
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			var p00: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * r0 * 0.95 * float(radii[k - 1])
			var p01: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * r0 * 0.95 * float(radii[k - 1])
			var p10: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * r0 * 0.95 * float(radii[k])
			var p11: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * r0 * 0.95 * float(radii[k])
			var col0: Color = ring_cols[(k - 1) % ring_cols.size()]
			var col1: Color = ring_cols[k % ring_cols.size()] if k < radii.size() - 1 else Color(0.45, 0.3, 0.2)
			_tri(leaf_st, [p00, p10, p11], [UP, UP, UP], [col0, col1, col1])
			if k > 1:
				_tri(leaf_st, [p00, p11, p01], [UP, UP, UP], [col0, col1, col0])

# ---------------------------------------------------------------- scenes

func _save_scene(name: String, p: Dictionary, mesh: Mesh, stump: Mesh, trunk_r: float) -> void:
	var root := Area3D.new()
	root.name = name.to_pascal_case()
	root.collision_layer = 8
	root.collision_mask = 0
	root.set_script(load("res://scripts/resources/resource_node.gd"))
	root.set("resource_id", "wood")
	root.set("resource_display_name", p["name"])
	root.set("required_tool", "axe")
	root.set("action_verb", "Рубить")
	root.set("max_hits", p["hits"])
	root.set("current_hits", p["hits"])
	root.set("yield_per_hit", p["yield"])
	root.set("bonus_depleted_yield", p["bonus"])
	root.add_to_group("trees", true)
	var area_shape := CollisionShape3D.new()
	area_shape.name = "CollisionShape3D"
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.9 + trunk_r
	cyl.height = 3.0
	area_shape.shape = cyl
	area_shape.position = Vector3(0, 1.5, 0)
	root.add_child(area_shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	root.add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Tree"
	mi.mesh = mesh
	visual.add_child(mi)
	var dep := Node3D.new()
	dep.name = "DepletedVisual"
	dep.visible = false
	root.add_child(dep)
	var smi := MeshInstance3D.new()
	smi.name = "Stump"
	smi.mesh = stump
	dep.add_child(smi)
	var body := StaticBody3D.new()
	body.name = "SolidBody"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var solid := CollisionShape3D.new()
	solid.name = "SolidShape"
	var sc := CylinderShape3D.new()
	sc.radius = trunk_r * 1.15
	sc.height = 2.4
	solid.shape = sc
	solid.position = Vector3(0, 1.2, 0)
	body.add_child(solid)
	root.set("visual_node", visual)
	root.set("depleted_visual_node", dep)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, SCENES + name + ".tscn")
	root.free()

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)
