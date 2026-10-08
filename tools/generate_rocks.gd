extends SceneTree

## Генератор моделей камней по референсу (стилизованные «рубленые» валуны, тёмный сланец).
## Каждый камень — один или несколько выпуклых многогранников, полученных пересечением
## случайных полупространств, касающихся эллипсоида (грани-сколы), плюс плоское дно.
## Неровные формы (скала-«шпиль», плита с уступом) — объединение нескольких кусков.
##
## Результат (детерминированный, seed фиксирован):
##   assets/models/rocks/rock_material.tres          — общий материал (встроенная triplanar-текстура трещин)
##   assets/models/rocks/rock_boulder_large.tres     — большой валун (ресурс «Камень», кирка)
##   assets/models/rocks/rock_boulder_large_shape.tres — его коллизия (ConvexPolygonShape3D)
##   assets/models/rocks/rock_small_{slab,spire,pebble}.tres + scenes/props/rock_small_*.tscn
##
## Запуск (из корня проекта):
##   python3 tools/generate_rock_texture.py
##   Godot --headless --path . -s tools/generate_rocks.gd

const OUT_DIR := "res://assets/models/rocks/"
## Текстура: python3 tools/generate_rock_texture.py -> .godot/rock_albedo.png (кэш вне git),
## встраивается в материал оттенками серого (L8) с mipmap-ами — бинарников в репозитории нет.
const TEXTURE_PNG := "res://.godot/rock_albedo.png"

# chunk: [радиусы, центр, поворот (эйлер, рад), число плоскостей, глубина сколов, seed]
const ROCKS: Dictionary = {
	"rock_boulder_large": [
		[Vector3(1.45, 1.0, 1.1), Vector3(0.0, 0.55, 0.0), Vector3(0.12, 0.5, 0.4), 17, 0.17, 14],
	],
	"rock_small_slab": [
		[Vector3(0.8, 0.17, 0.55), Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.2, 0.03), 18, 0.1, 21],
		[Vector3(0.55, 0.1, 0.38), Vector3(0.1, 0.2, -0.03), Vector3(0.0, -0.15, 0.0), 14, 0.08, 22],
	],
	"rock_small_spire": [
		[Vector3(0.26, 0.72, 0.24), Vector3(0.0, 0.55, 0.0), Vector3(0.0, 0.3, 0.12), 16, 0.12, 31],
		[Vector3(0.2, 0.42, 0.19), Vector3(-0.2, 0.3, 0.06), Vector3(0.1, 0.0, -0.22), 14, 0.12, 32],
		[Vector3(0.19, 0.17, 0.17), Vector3(0.24, 0.1, 0.08), Vector3(0.0, 0.4, 0.0), 12, 0.1, 33],
	],
	"rock_small_pebble": [
		[Vector3(0.55, 0.38, 0.44), Vector3(0.0, 0.28, 0.0), Vector3(0.15, 0.3, 0.0), 30, 0.07, 41],
	],
}
const SMALL := ["rock_small_slab", "rock_small_spire", "rock_small_pebble"]

func _init() -> void:
	var mat := _make_material()
	ResourceSaver.save(mat, OUT_DIR + "rock_material.tres")
	mat = load(OUT_DIR + "rock_material.tres")
	for name in ROCKS:
		var hulls: Array = []
		var mesh := _build_rock(ROCKS[name], hulls, mat)
		var mpath: String = OUT_DIR + name + ".tres"
		ResourceSaver.save(mesh, mpath)
		var aabb := mesh.get_aabb()
		print("%-20s tris=%d size=%s" % [name, mesh.surface_get_array_len(0) / 3, aabb.size])
		var shapes: Array[ConvexPolygonShape3D] = []
		for h in hulls:
			var s := ConvexPolygonShape3D.new()
			s.points = PackedVector3Array(h)
			shapes.append(s)
		if name == "rock_boulder_large":
			ResourceSaver.save(shapes[0], OUT_DIR + name + "_shape.tres")
		else:
			_save_prop_scene(name, load(mpath), shapes)
	quit()

func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "RockSlate"
	m.albedo_color = Color(0.34, 0.345, 0.36)
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEXTURE_PNG))
	if img == null or img.is_empty():
		push_error("Нет %s — сначала запустите python3 tools/generate_rock_texture.py" % TEXTURE_PNG)
	else:
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		# Сжатая без потерь текстура хранится в .tres компактно (WebP/PNG внутри).
		PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
		var tex := PortableCompressedTexture2D.new()
		tex.keep_compressed_buffer = true
		tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		tex.resource_name = "RockCracks"
		m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.metallic = 0.0
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(0.55, 0.55, 0.55)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _build_rock(chunks: Array, hulls: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in chunks:
		var rng := RandomNumberGenerator.new()
		rng.seed = c[5]
		var planes := _planes(c[0], c[1], Basis.from_euler(c[2]), c[3], c[4], rng)
		var verts := _vertices(planes)
		# Фаски: по каждому ребру между гранями — узкая грань с нормалью-биссектрисой
		# (мягкие светлые кромки, как на референсе).
		var r: Vector3 = c[0]
		var bevel := minf(r.x, minf(r.y, r.z)) * 0.07
		var count := planes.size()
		for i in count:
			for j in range(i + 1, count):
				var ni: Vector3 = planes[i][0]
				var nj: Vector3 = planes[j][0]
				if ni == Vector3.DOWN or nj == Vector3.DOWN:
					continue
				var shared := 0
				for v in verts:
					if absf(ni.dot(v) - planes[i][1]) < 1e-4 and absf(nj.dot(v) - planes[j][1]) < 1e-4:
						shared += 1
				if shared < 2:
					continue
				var nb := (ni + nj).normalized()
				var hb := -INF
				for v in verts:
					hb = maxf(hb, nb.dot(v))
				planes.append([nb, hb - bevel * (1.0 - ni.dot(nj)) * 1.6, true])
		verts = _vertices(planes)
		hulls.append(verts)
		_emit_faces(st, planes, verts, rng)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh

## Плоскости n·x <= d: касательные к эллипсоиду, сдвинутые внутрь на случайную глубину скола.
func _planes(r: Vector3, center: Vector3, rot: Basis, count: int, cut: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	# Равномерные направления (спираль Фибоначчи) + случайное дрожание -> грани близкого размера.
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var rad := sqrt(1.0 - y * y)
		var th := golden * i + rng.randf() * 0.6
		var n := Vector3(cos(th) * rad, y, sin(th) * rad)
		n = (n + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))).normalized()
		var local_n := rot.transposed() * n
		var h := n.dot(center) + (local_n * r).length()
		var d := h * (1.0 - cut * pow(rng.randf(), 1.3)) if h > 0.0 else h
		out.append([n, d])
	# Дно: y >= 0.
	out.append([Vector3.DOWN, 0.0])
	return out

func _vertices(planes: Array) -> Array:
	var verts: Array = []
	var n := planes.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a: Vector3 = planes[i][0]
				var b: Vector3 = planes[j][0]
				var c: Vector3 = planes[k][0]
				var det := a.dot(b.cross(c))
				if absf(det) < 1e-6:
					continue
				var p: Vector3 = (b.cross(c) * planes[i][1] + c.cross(a) * planes[j][1] + a.cross(b) * planes[k][1]) / det
				var inside := true
				for q in planes:
					if (q[0] as Vector3).dot(p) > q[1] + 1e-5:
						inside = false
						break
				if not inside:
					continue
				var dup := false
				for v in verts:
					if (v as Vector3).distance_squared_to(p) < 1e-8:
						dup = true
						break
				if not dup:
					verts.append(p)
	return verts

func _emit_faces(st: SurfaceTool, planes: Array, verts: Array, rng: RandomNumberGenerator) -> void:
	for pl in planes:
		var n: Vector3 = pl[0]
		var on: Array = []
		for v in verts:
			if absf(n.dot(v) - pl[1]) < 1e-4:
				on.append(v)
		if on.size() < 3:
			continue
		var c := Vector3.ZERO
		for v in on:
			c += v
		c /= on.size()
		var u: Vector3 = ((on[0] as Vector3) - c).normalized()
		var w := n.cross(u)
		on.sort_custom(func(p, q): return atan2((p - c).dot(w), (p - c).dot(u)) < atan2((q - c).dot(w), (q - c).dot(u)))
		# Тон грани: верх светлее (как на референсе), лёгкий разброс между гранями.
		var up := clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
		var tone := lerpf(0.55, 1.3, pow(up, 1.6)) * rng.randf_range(0.93, 1.05)
		if pl.size() > 2:
			tone *= 1.14
		var col := Color(tone, tone, tone * 1.02)
		for t in range(1, on.size() - 1):
			var tri := [on[0], on[t], on[t + 1]]
			# Godot: лицевая сторона — обход по часовой стрелке.
			if ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0]).dot(n) > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for p in tri:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(p)

func _save_prop_scene(name: String, mesh: Mesh, shapes: Array[ConvexPolygonShape3D]) -> void:
	var root := StaticBody3D.new()
	root.name = name.to_pascal_case()
	root.collision_layer = 1
	root.collision_mask = 0
	root.add_to_group("rocks", true)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root.add_child(mi)
	for i in shapes.size():
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % i
		cs.shape = shapes[i]
		root.add_child(cs)
	for ch in root.get_children():
		ch.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "res://scenes/props/" + name + ".tscn")
	root.free()
