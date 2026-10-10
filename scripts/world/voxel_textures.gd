class_name VoxelTextures
extends RefCounted

## Процедурные пиксельные текстуры грунта для копаемых жил (VoxelDeposit).
##
## Атлас — одна строка тайлов TILE×TILE пикселей, каждый с бесшовной «рамкой»
## PAD пикселей (копия противоположного края), чтобы mipmap-уровни не смешивали
## соседние тайлы. Текстура и материал строятся один раз и кэшируются.
## Цвет травы подобран под материал земли мира (Ground: 0.26, 0.35, 0.2).
## Превью: godot --headless --path . -s tools/export_voxel_textures.gd

const TILE: int = 32
const PAD: int = 8
const CELL: int = TILE + PAD * 2

enum Tile { GRASS_TOP, GRASS_SIDE, SOIL, SAND, CLAY, COAL, IRON_ORE, BEDROCK }
const TILE_COUNT: int = 8
const TILE_NAMES: Array[String] = ["Трава", "Дёрн (бок)", "Грунт", "Песок", "Глина", "Уголь", "Железная руда", "Скальное основание"]

static var _atlas_image: Image = null
static var _atlas_texture: ImageTexture = null
static var _material: StandardMaterial3D = null
static var _ground_material: StandardMaterial3D = null
## Размер блока жилы (VoxelDeposit.VOXEL_SIZE): один тайл на блок.
const VOXEL_STEP: float = 0.5

## UV-прямоугольник тайла внутри атласа (без рамки).
static func tile_uv_rect(tile: int) -> Rect2:
	var w: float = float(CELL * TILE_COUNT)
	var h: float = float(CELL)
	return Rect2((tile * CELL + PAD) / w, PAD / h, TILE / w, TILE / h)

static func get_atlas_image() -> Image:
	if _atlas_image == null:
		_atlas_image = _build_atlas()
	return _atlas_image

static func get_atlas_texture() -> ImageTexture:
	if _atlas_texture == null:
		var img: Image = get_atlas_image().duplicate()
		img.generate_mipmaps()
		_atlas_texture = ImageTexture.create_from_image(img)
	return _atlas_texture

static func get_material() -> StandardMaterial3D:
	if _material == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = get_atlas_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		_material = m
	return _material

## Материал земли мира: тот же тайл травы, что и на верху жил, мировой triplanar
## с шагом 0.5 м — трава на жилах и вокруг них совпадает пиксель в пиксель по сетке.
static func get_ground_material() -> StandardMaterial3D:
	if _ground_material == null:
		var img: Image = get_tile_image(Tile.GRASS_TOP)
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / VOXEL_STEP
		m.roughness = 0.95
		_ground_material = m
	return _ground_material

## Тайл без рамки (для превью и иконок).
static func get_tile_image(tile: int) -> Image:
	return get_atlas_image().get_region(Rect2i(tile * CELL + PAD, PAD, TILE, TILE))

# --- Генерация ---------------------------------------------------------------

static func _build_atlas() -> Image:
	var atlas: Image = Image.create_empty(CELL * TILE_COUNT, CELL, false, Image.FORMAT_RGBA8)
	for t in TILE_COUNT:
		var tile: Image = _draw_tile(t)
		for y in CELL:
			for x in CELL:
				atlas.set_pixel(t * CELL + x, y, tile.get_pixel(posmod(x - PAD, TILE), posmod(y - PAD, TILE)))
	return atlas

static func _draw_tile(t: int) -> Image:
	var img: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + t * 104729
	match t:
		Tile.GRASS_TOP:
			_grain(img, rng, Color(0.22, 0.36, 0.11), 0.05, 0.03)
			for i in 34:
				var c: Color = Color(0.29, 0.44, 0.14) if rng.randf() < 0.6 else Color(0.16, 0.27, 0.08)
				var x: int = rng.randi_range(0, TILE - 1)
				var y: int = rng.randi_range(0, TILE - 1)
				_px(img, x, y, c)
				_px(img, x, y + 1, c.darkened(0.12))
			for i in 4:
				_px(img, rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), Color(0.42, 0.36, 0.26))
		Tile.SOIL, Tile.GRASS_SIDE:
			_grain(img, rng, Color(0.37, 0.27, 0.18), 0.07, 0.04)
			_blobs(img, rng, 7, 1.0, 2.0, Color(0.3, 0.21, 0.14), 0.04)
			_blobs(img, rng, 5, 0.6, 1.2, Color(0.5, 0.47, 0.42), 0.05)
			_blobs(img, rng, 4, 0.5, 0.9, Color(0.47, 0.36, 0.24), 0.03)
			if t == Tile.GRASS_SIDE:
				for x in TILE:
					var depth: int = 5 + int(round(sin(x * 1.3) * 1.2 + rng.randf_range(-1.0, 2.0)))
					for y in depth:
						var c := Color(0.25, 0.345, 0.195)
						c = c.lightened(rng.randf_range(0.0, 0.08)) if rng.randf() < 0.5 else c.darkened(rng.randf_range(0.0, 0.1))
						if y == depth - 1:
							c = c.darkened(0.25)
						_px(img, x, y, c)
		Tile.SAND:
			_grain(img, rng, Color(0.84, 0.74, 0.5), 0.05, 0.05)
			for y in TILE:
				var band: float = sin((y + sin(y * 0.2) * 2.0) * TAU / 8.0) * 0.025
				for x in TILE:
					_px(img, x, y, img.get_pixel(x, y).lightened(band) if band > 0 else img.get_pixel(x, y).darkened(-band))
			for i in 40:
				var c: Color = Color(0.95, 0.88, 0.66) if rng.randf() < 0.5 else Color(0.66, 0.56, 0.36)
				_px(img, rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), c)
		Tile.CLAY:
			_grain(img, rng, Color(0.69, 0.41, 0.29), 0.03, 0.025)
			for y in TILE:
				var band: float = sin(y * TAU / 16.0 + sin(y * 0.7) * 0.6) * 0.06
				for x in TILE:
					var c: Color = img.get_pixel(x, y)
					_px(img, x, y, c.lightened(band) if band > 0 else c.darkened(-band))
			_cracks(img, rng, 3, Color(0.5, 0.29, 0.2))
			_blobs(img, rng, 4, 0.8, 1.5, Color(0.78, 0.52, 0.38), 0.03)
		Tile.COAL:
			_grain(img, rng, Color(0.36, 0.35, 0.34), 0.05, 0.04)
			_blobs(img, rng, 8, 1.8, 3.2, Color(0.09, 0.085, 0.09), 0.02, true)
			_blobs(img, rng, 5, 1.0, 1.8, Color(0.14, 0.13, 0.14), 0.02)
		Tile.IRON_ORE:
			_grain(img, rng, Color(0.47, 0.45, 0.43), 0.05, 0.04)
			_cracks(img, rng, 2, Color(0.36, 0.34, 0.33))
			_blobs(img, rng, 9, 1.4, 2.4, Color(0.68, 0.38, 0.2), 0.04, true)
			_blobs(img, rng, 5, 0.8, 1.4, Color(0.84, 0.62, 0.46), 0.03)
		Tile.BEDROCK:
			_grain(img, rng, Color(0.2, 0.2, 0.21), 0.07, 0.05)
			_blobs(img, rng, 9, 1.5, 3.0, Color(0.3, 0.3, 0.31), 0.04)
			_cracks(img, rng, 4, Color(0.1, 0.1, 0.11))
	return img

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, TILE), posmod(y, TILE), Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1), 1.0))

## Базовый цвет с попиксельным шумом и мягкими пятнами (бесшовно).
static func _grain(img: Image, rng: RandomNumberGenerator, base: Color, pixel_var: float, patch_var: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / 9.0
	for y in TILE:
		for x in TILE:
			# Тор: шум по окружностям даёт бесшовный тайл.
			var ax: float = float(x) / TILE * TAU
			var ay: float = float(y) / TILE * TAU
			var n: float = noise.get_noise_3d(cos(ax) * 8.0, sin(ax) * 8.0 + cos(ay) * 8.0, sin(ay) * 8.0)
			var v: float = n * patch_var + rng.randf_range(-pixel_var, pixel_var)
			_px(img, x, y, Color(base.r + v, base.g + v * 0.95, base.b + v * 0.85))

## Округлые вкрапления с бликом сверху-слева и тенью снизу-справа.
static func _blobs(img: Image, rng: RandomNumberGenerator, count: int, r_min: float, r_max: float, color: Color, jitter: float, shine: bool = false) -> void:
	# Стратифицированная раскладка: пятна равномерно по тайлу, без скоплений в углу.
	var g: int = maxi(1, int(ceil(sqrt(float(count)))))
	var cells: Array[int] = []
	for k in g * g:
		cells.append(k)
	for k in range(cells.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, k)
		var tmp: int = cells[k]
		cells[k] = cells[j]
		cells[j] = tmp
	for i in count:
		var cell: int = cells[i % cells.size()]
		var cx: float = (float(cell % g) + rng.randf_range(0.15, 0.85)) * TILE / g
		var cy: float = (float(cell / g) + rng.randf_range(0.15, 0.85)) * TILE / g
		var r: float = rng.randf_range(r_min, r_max)
		var ri: int = int(ceil(r)) + 1
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d: float = Vector2(dx + 0.5 - fmod(cx, 1.0), dy + 0.5 - fmod(cy, 1.0)).length()
				if d > r:
					continue
				var c: Color = color.lightened(rng.randf_range(0.0, jitter))
				if d > r - 0.9 and dx + dy > 0:
					c = c.darkened(0.25)
				elif dx + dy < -r * 0.6:
					c = c.lightened(0.35 if shine else 0.12)
				_px(img, int(cx) + dx, int(cy) + dy, c)

## Тонкие ломаные трещины.
static func _cracks(img: Image, rng: RandomNumberGenerator, count: int, color: Color) -> void:
	for i in count:
		var p := Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var dir: float = rng.randf() * TAU
		for s in rng.randi_range(6, 14):
			_px(img, int(p.x), int(p.y), color)
			dir += rng.randf_range(-0.7, 0.7)
			p += Vector2(cos(dir), sin(dir))
