class_name ItemIcons
extends RefCounted

## Иконки предметов для клеточного инвентаря, окна станка и предметов на земле.
##
## Инструменты с готовой картинкой (assets/tools/*_icon.png) используют её; остальные
## иконки рисуются кодом (48×48, силуэт + тёмный контур + детали) и кэшируются.
## Форма и цвета задаются таблицей STYLES; неизвестные предметы получают «ящик»
## цвета своей категории. Чтобы добавить предмет — допишите строку в STYLES.

const ItemDB = preload("res://scripts/inventory/item_db.gd")

const SIZE: int = 48
const OUTLINE_GROW: float = 2.0

## item_id -> [форма, основной цвет, акцент]
const STYLES: Dictionary = {
	"wood": ["log", Color(0.55, 0.36, 0.2), Color(0.86, 0.7, 0.46)],
	"stone": ["rock", Color(0.55, 0.56, 0.58), Color(0.78, 0.8, 0.82)],
	"clay": ["clay", Color(0.72, 0.42, 0.28), Color(0.88, 0.6, 0.45)],
	"sand": ["pile", Color(0.9, 0.8, 0.52), Color(1.0, 0.93, 0.7)],
	"soil": ["pile", Color(0.37, 0.27, 0.18), Color(0.55, 0.42, 0.3)],
	"coal": ["coal", Color(0.16, 0.15, 0.16), Color(0.55, 0.56, 0.62)],
	"iron_ore": ["ore", Color(0.5, 0.48, 0.46), Color(0.78, 0.45, 0.24)],
	"water": ["drop", Color(0.25, 0.55, 0.9), Color(0.7, 0.88, 1.0)],
	"stone_dust": ["pile", Color(0.7, 0.7, 0.72), Color(0.92, 0.92, 0.94)],
	"sawdust": ["pile", Color(0.82, 0.66, 0.42), Color(0.95, 0.85, 0.62)],
	"coal_powder": ["coal", Color(0.16, 0.15, 0.16), Color(0.55, 0.56, 0.62)],
	"mortar": ["sack", Color(0.62, 0.6, 0.56), Color(0.85, 0.83, 0.78)],
	"poor_brick": ["brick", Color(0.6, 0.4, 0.32), Color(0.42, 0.3, 0.25)],
	"fuel_briquette": ["block", Color(0.25, 0.22, 0.2), Color(0.5, 0.36, 0.24)],
	"fired_brick": ["brick", Color(0.75, 0.3, 0.2), Color(0.52, 0.24, 0.18)],
	"glass": ["pane", Color(0.6, 0.85, 0.95), Color(1.0, 1.0, 1.0)],
	"metal_scrap": ["scrap", Color(0.5, 0.45, 0.42), Color(0.78, 0.55, 0.35)],
	"iron_ingot": ["ingot", Color(0.6, 0.63, 0.68), Color(0.86, 0.89, 0.93)],
	"clean_water": ["drop", Color(0.35, 0.75, 1.0), Color(0.88, 0.97, 1.0)],
	"bottled_water": ["bottle", Color(0.45, 0.75, 0.95), Color(0.95, 0.95, 1.0)],
	"seeds_carrot": ["seeds", Color(0.85, 0.55, 0.25), Color(1.0, 0.8, 0.5)],
	"seeds_potato": ["seeds", Color(0.65, 0.5, 0.35), Color(0.86, 0.73, 0.56)],
	"seeds_wheat": ["seeds", Color(0.88, 0.75, 0.4), Color(1.0, 0.93, 0.62)],
	"seeds_sunflower": ["seeds", Color(0.9, 0.75, 0.2), Color(0.3, 0.2, 0.1)],
	"seeds_onion": ["seeds", Color(0.2, 0.2, 0.2), Color(0.5, 0.5, 0.5)],
	"seeds_cabbage": ["seeds", Color(0.4, 0.6, 0.3), Color(0.7, 0.85, 0.5)],
	"seeds_tomato": ["seeds", Color(0.85, 0.65, 0.35), Color(0.95, 0.85, 0.6)],
	"seeds_pepper": ["seeds", Color(0.9, 0.8, 0.4), Color(1.0, 0.95, 0.7)],
	"seeds_bean": ["seeds", Color(0.6, 0.35, 0.2), Color(0.85, 0.6, 0.4)],
	"seeds_herbs": ["seeds", Color(0.45, 0.7, 0.35), Color(0.7, 0.9, 0.6)],
	"seeds_corn": ["seeds", Color(0.95, 0.8, 0.25), Color(1.0, 0.92, 0.5)],
	"seeds_pumpkin": ["seeds", Color(0.92, 0.9, 0.8), Color(0.8, 0.6, 0.3)],
	"apple_sapling": ["sapling", Color(0.35, 0.7, 0.3), Color(0.85, 0.15, 0.15)],
	"pear_sapling": ["sapling", Color(0.35, 0.7, 0.3), Color(0.82, 0.75, 0.2)],
	"cherry_sapling": ["sapling", Color(0.35, 0.7, 0.3), Color(0.68, 0.05, 0.15)],
	"apricot_sapling": ["sapling", Color(0.35, 0.7, 0.3), Color(0.96, 0.60, 0.15)],
	"carrot": ["carrot", Color(0.95, 0.5, 0.15), Color(0.35, 0.7, 0.25)],
	"potato": ["potato", Color(0.75, 0.6, 0.38), Color(0.9, 0.8, 0.6)],
	"red_berry": ["berries", Color(0.78, 0.08, 0.1), Color(0.3, 0.6, 0.2)],
	"blue_berry": ["berries", Color(0.18, 0.25, 0.75), Color(0.3, 0.6, 0.2)],
	"blackberry": ["berries", Color(0.12, 0.05, 0.16), Color(0.35, 0.62, 0.25)],
	"sea_buckthorn": ["berries", Color(0.95, 0.48, 0.06), Color(0.4, 0.66, 0.25)],
	# --- Глава 2 «Первый дым»: грибы и блюда ---
	"mushroom": ["mushroom", Color(0.78, 0.62, 0.42), Color(0.9, 0.86, 0.76)],
	"baked_potato": ["baked_potato", Color(0.82, 0.62, 0.32), Color(0.95, 0.82, 0.55)],
	"fried_carrot": ["fried", Color(0.95, 0.55, 0.18), Color(0.98, 0.76, 0.35)],
	"vegetable_soup": ["soup", Color(0.72, 0.66, 0.58), Color(0.9, 0.66, 0.35)],
	"berry_brew": ["drink", Color(0.62, 0.4, 0.45), Color(0.82, 0.26, 0.32)],
	"mushroom_stew": ["soup", Color(0.66, 0.56, 0.44), Color(0.85, 0.75, 0.55)],
	"dried_mushroom": ["dried", Color(0.78, 0.66, 0.46), Color(0.6, 0.5, 0.34)],
	"potato_mushroom_dish": ["plate", Color(0.8, 0.66, 0.4), Color(0.6, 0.46, 0.3)],
	"mushroom_soup": ["soup", Color(0.6, 0.5, 0.4), Color(0.88, 0.78, 0.58)],
	"glazed_carrot": ["fried", Color(0.95, 0.6, 0.2), Color(0.85, 0.25, 0.3)],
	"potato_pie": ["bread", Color(0.88, 0.68, 0.34), Color(0.66, 0.44, 0.22)],
	"berry_compote": ["drink", Color(0.7, 0.32, 0.38), Color(0.9, 0.55, 0.5)],
	"dried_apricot": ["dried", Color(0.85, 0.45, 0.12), Color(0.65, 0.35, 0.10)],
	"apricot_compote": ["drink", Color(0.92, 0.62, 0.22), Color(0.96, 0.78, 0.40)],
	"apricot_pie": ["bread", Color(0.92, 0.70, 0.32), Color(0.85, 0.50, 0.15)],
	"mushroom_sauce": ["sack", Color(0.56, 0.44, 0.32), Color(0.78, 0.66, 0.48)],
	"berry_sauce": ["sack", Color(0.62, 0.26, 0.32), Color(0.85, 0.45, 0.45)],
	"sapling": ["sapling", Color(0.35, 0.7, 0.3), Color(0.5, 0.34, 0.2)],
	"wheat": ["wheat", Color(0.92, 0.78, 0.35), Color(0.7, 0.55, 0.2)],
	"sunflower_seeds": ["seeds", Color(0.22, 0.2, 0.18), Color(0.9, 0.75, 0.2)],
	"onion": ["onion", Color(0.82, 0.58, 0.35), Color(0.45, 0.75, 0.3)],
	"cabbage": ["cabbage", Color(0.42, 0.72, 0.35), Color(0.7, 0.88, 0.55)],
	"tomato": ["tomato", Color(0.88, 0.22, 0.15), Color(0.35, 0.7, 0.25)],
	"pepper": ["pepper", Color(0.85, 0.18, 0.12), Color(0.35, 0.7, 0.25)],
	"bean": ["bean", Color(0.38, 0.68, 0.28), Color(0.6, 0.85, 0.4)],
	"herbs": ["herbs", Color(0.3, 0.68, 0.3), Color(0.55, 0.85, 0.45)],
	"corn": ["corn", Color(0.95, 0.82, 0.2), Color(0.4, 0.72, 0.3)],
	"pumpkin": ["pumpkin", Color(0.92, 0.52, 0.12), Color(0.4, 0.65, 0.25)],
	"apple": ["apple", Color(0.88, 0.18, 0.15), Color(0.35, 0.68, 0.25)],
	"pear": ["pear", Color(0.82, 0.74, 0.22), Color(0.45, 0.35, 0.2)],
	"cherry": ["cherry", Color(0.72, 0.08, 0.14), Color(0.4, 0.65, 0.25)],
	"apricot": ["apricot", Color(0.96, 0.60, 0.15), Color(0.35, 0.65, 0.25)],
	"bread": ["bread", Color(0.72, 0.45, 0.2), Color(0.88, 0.65, 0.35)],
	"fertilizer": ["sack", Color(0.55, 0.45, 0.3), Color(0.4, 0.66, 0.3)],
	"copper_wire": ["coil", Color(0.8, 0.45, 0.2), Color(0.96, 0.72, 0.46)],
	"iron_plate": ["plate", Color(0.58, 0.6, 0.64), Color(0.38, 0.4, 0.44)],
	"gear": ["gear", Color(0.62, 0.62, 0.6), Color(0.88, 0.88, 0.85)],
	"battery_cell": ["battery", Color(0.25, 0.6, 0.35), Color(0.85, 0.85, 0.85)],
	"street_lamp_item": ["lamp", Color(0.35, 0.35, 0.38), Color(1.0, 0.85, 0.35)],
	"wooden_handle": ["handle", Color(0.62, 0.42, 0.24), Color(0.84, 0.64, 0.42)],
	"bolt": ["bolt", Color(0.6, 0.62, 0.66), Color(0.4, 0.42, 0.45)],
	"fabric": ["fabric", Color(0.55, 0.6, 0.75), Color(0.76, 0.8, 0.92)],
	"leather_strap": ["strap", Color(0.5, 0.3, 0.18), Color(0.78, 0.72, 0.6)],
}

const TOOL_SHAPES: Array[String] = ["axe", "pickaxe", "shovel", "bucket", "backpack"]

const CATEGORY_COLORS: Dictionary = {
	"resource": Color(0.6, 0.55, 0.45),
	"material": Color(0.62, 0.58, 0.52),
	"food": Color(0.85, 0.6, 0.3),
	"seed": Color(0.7, 0.6, 0.35),
	"component": Color(0.55, 0.6, 0.68),
	"tool": Color(0.62, 0.62, 0.65),
	"equipment": Color(0.5, 0.42, 0.3),
}

static var _cache: Dictionary = {}

## Текстура иконки предмета (никогда не null).
static func get_texture(item_id: String) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id]
	var tex: Texture2D = _load_file_icon(item_id)
	if tex == null:
		tex = ImageTexture.create_from_image(draw_icon(item_id))
	_cache[item_id] = tex
	return tex

## Основной цвет предмета (фон клетки, модель на земле).
static func get_color(item_id: String) -> Color:
	return _style_for(item_id)[1]

static func clear_cache() -> void:
	_cache.clear()

static func _load_file_icon(item_id: String) -> Texture2D:
	var nano_path: String = "res://assets/tools_nano_banana/%s_icon.png" % item_id
	if ResourceLoader.exists(nano_path):
		var res = load(nano_path)
		if res is Texture2D:
			return res
	var data: Dictionary = ItemDB.get_item(item_id)
	var candidates: Array[String] = []
	for key in ["icon_texture", "texture", "icon_path", "sprite"]:
		var p = data.get(key, "")
		if p is String and (p as String).begins_with("res://"):
			candidates.append(p)
	candidates.append("res://assets/tools/%s_icon.png" % item_id)
	for path in candidates:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				return res
	return null

static func _style_for(item_id: String) -> Array:
	if STYLES.has(item_id):
		return STYLES[item_id]
	var data: Dictionary = ItemDB.get_item(item_id)
	var tool_type: String = str(data.get("tool_type", ""))
	if tool_type.is_empty() and item_id in TOOL_SHAPES:
		tool_type = item_id
	if tool_type in TOOL_SHAPES:
		var lvl: int = int(data.get("level", 1))
		var metal: Color = Color(0.62, 0.62, 0.64) if lvl <= 1 else Color(0.78, 0.82, 0.9)
		if tool_type == "backpack":
			metal = Color(0.5, 0.42, 0.3) if lvl <= 1 else Color(0.4, 0.48, 0.36)
		return [tool_type, metal, Color(0.58, 0.38, 0.22)]
	var cat_color: Color = CATEGORY_COLORS.get(str(data.get("category", "")), Color(0.6, 0.6, 0.6))
	return ["box", cat_color, cat_color.lightened(0.3)]

## Рисует иконку: сначала расширенный силуэт тёмным цветом (контур), затем форму и детали.
static func draw_icon(item_id: String) -> Image:
	var img: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var style: Array = _style_for(item_id)
	var shape: String = style[0]
	var base: Color = style[1]
	var accent: Color = style[2]
	var outline: Color = base.darkened(0.6)
	outline.a = 1.0
	_shape(img, shape, outline, outline, OUTLINE_GROW)
	_shape(img, shape, base, accent, 0.0)
	return img

static func _shape(img: Image, shape: String, base: Color, accent: Color, g: float) -> void:
	var d: bool = g == 0.0 # детали рисуем только во втором проходе
	var dark: Color = base.darkened(0.3)
	match shape:
		"log":
			_rect(img, 6, 15, 32, 18, base, g)
			_ellipse(img, 38, 24, 6, 9, accent, g)
			if d:
				_ellipse(img, 38, 24, 3, 5, base.darkened(0.15))
				_line(img, 10, 20, 30, 20, 1.5, dark)
				_line(img, 12, 28, 32, 28, 1.5, dark)
		"rock":
			_ellipse(img, 25, 26, 17, 12, base, g)
			_ellipse(img, 16, 32, 9, 7, base, g)
			if d:
				_ellipse(img, 20, 21, 6, 3, accent)
				_ellipse(img, 31, 31, 3, 2, dark)
		"pile":
			_ellipse(img, 24, 34, 18, 8, base, g)
			_ellipse(img, 24, 26, 12, 9, base, g)
			_ellipse(img, 24, 19, 6, 5, base, g)
			if d:
				for p in [Vector2(18, 30), Vector2(28, 27), Vector2(23, 21), Vector2(31, 35), Vector2(15, 36), Vector2(25, 33)]:
					_ellipse(img, p.x, p.y, 1.6, 1.6, accent)
		"drop":
			_ellipse(img, 24, 31, 11, 11, base, g)
			_ellipse(img, 24, 23, 8, 8, base, g)
			_ellipse(img, 24, 16, 5, 5, base, g)
			_ellipse(img, 24, 10, 2.5, 3, base, g)
			if d:
				_ellipse(img, 20, 29, 3, 4, accent)
		"brick":
			_rect(img, 6, 14, 36, 20, base, g)
			if d:
				_line(img, 6, 24, 42, 24, 1.5, accent)
				_line(img, 24, 14, 24, 24, 1.5, accent)
				_line(img, 15, 24, 15, 34, 1.5, accent)
				_line(img, 33, 24, 33, 34, 1.5, accent)
		"block":
			_rect(img, 10, 12, 28, 24, base, g)
			if d:
				_rect(img, 10, 12, 28, 6, accent)
				_line(img, 14, 27, 34, 27, 1.5, base.lightened(0.15))
		"pane":
			_rect(img, 9, 9, 30, 30, base, g)
			if d:
				_line(img, 14, 30, 30, 14, 2.5, accent)
				_line(img, 22, 34, 34, 22, 1.5, accent)
		"ingot":
			_rect(img, 8, 24, 32, 12, base, g)
			_rect(img, 13, 16, 22, 8, base, g)
			if d:
				_rect(img, 13, 16, 22, 4, accent)
				_line(img, 10, 30, 38, 30, 1.0, dark)
		"scrap":
			_line(img, 9, 34, 30, 13, 7, base, g)
			_line(img, 17, 38, 39, 27, 6, base, g)
			_ellipse(img, 36, 15, 5, 4, base, g)
			if d:
				_line(img, 12, 31, 27, 16, 1.5, accent)
				_ellipse(img, 36, 14, 2, 1.5, accent)
		"bottle":
			_rect(img, 16, 18, 16, 24, base, g)
			_rect(img, 20, 9, 8, 10, base, g)
			_rect(img, 19, 5, 10, 5, accent, g)
			if d:
				_rect(img, 16, 26, 16, 8, accent)
				_line(img, 19, 20, 19, 40, 1.5, Color(1, 1, 1, 0.7))
		"seeds":
			_ellipse(img, 16, 28, 5, 7, base, g)
			_ellipse(img, 27, 21, 5, 7, base, g)
			_ellipse(img, 33, 32, 5, 7, base, g)
			if d:
				_ellipse(img, 15, 26, 1.5, 3, accent)
				_ellipse(img, 26, 19, 1.5, 3, accent)
				_ellipse(img, 32, 30, 1.5, 3, accent)
		"carrot":
			_line(img, 19, 14, 28, 42, 9, base, g)
			_line(img, 19, 13, 12, 4, 3, accent, g)
			_line(img, 19, 13, 21, 3, 3, accent, g)
			_line(img, 19, 13, 28, 6, 3, accent, g)
			if d:
				_line(img, 19, 23, 24, 22, 1.2, dark)
				_line(img, 22, 31, 27, 30, 1.2, dark)
		"potato":
			_ellipse(img, 24, 26, 16, 12, base, g)
			if d:
				_ellipse(img, 19, 21, 4, 2, accent)
				for p in [Vector2(18, 27), Vector2(29, 22), Vector2(26, 32), Vector2(33, 28)]:
					_ellipse(img, p.x, p.y, 1.5, 1.5, dark)
		"berries":
			_line(img, 24, 8, 24, 16, 2.5, accent, g)
			_ellipse(img, 30, 10, 6, 3, accent, g)
			for p in [Vector2(17, 26), Vector2(31, 26), Vector2(24, 37)]:
				_ellipse(img, p.x, p.y, 8, 8, base, g)
			if d:
				for p2 in [Vector2(14, 23), Vector2(28, 23), Vector2(21, 34)]:
					_ellipse(img, p2.x, p2.y, 2, 2, Color(1, 1, 1, 0.75))
		"wheat":
			_line(img, 24, 44, 24, 12, 2.5, base, g)
			_ellipse(img, 24, 9, 2.5, 4, base, g)
			for i in range(5):
				var y: float = 13.0 + i * 5.0
				_ellipse(img, 20, y, 3, 4.5, base, g)
				_ellipse(img, 28, y, 3, 4.5, base, g)
			if d:
				for i in range(5):
					var y2: float = 13.0 + i * 5.0
					_ellipse(img, 19, y2 - 1, 1, 2, accent)
					_ellipse(img, 27, y2 - 1, 1, 2, accent)
		"sapling":
			_ellipse(img, 24, 40, 13, 5, accent, g)
			_line(img, 24, 40, 24, 14, 2.5, accent, g)
			_ellipse(img, 16, 24, 7, 3.5, base, g)
			_ellipse(img, 32, 19, 7, 3.5, base, g)
			_ellipse(img, 24, 11, 4, 6, base, g)
			if d:
				_line(img, 11, 24, 21, 24, 1.0, dark)
				_line(img, 27, 19, 37, 19, 1.0, dark)
				_ellipse(img, 20, 39, 3, 1.2, accent.lightened(0.25))
		"apple":
			_ellipse(img, 24, 27, 13, 13, base, g)
			_line(img, 24, 15, 24, 7, 2.5, accent, g)
			_ellipse(img, 29, 9, 4, 2.5, accent, g)
			if d:
				_ellipse(img, 19, 21, 4, 3, base.lightened(0.25))
				_ellipse(img, 24, 15, 2, 1.5, dark)
		"pear":
			_ellipse(img, 24, 31, 13, 11, base, g)
			_ellipse(img, 24, 20, 8, 8, base, g)
			_line(img, 24, 13, 26, 6, 2.0, accent, g)
			_ellipse(img, 28, 8, 3.5, 2, Color(0.35, 0.68, 0.25), g)
			if d:
				_ellipse(img, 20, 26, 4, 3, base.lightened(0.25))
		"cherry":
			_ellipse(img, 18, 32, 7, 7, base, g)
			_ellipse(img, 30, 29, 7, 7, base, g)
			_line(img, 18, 26, 24, 10, 2.0, accent, g)
			_line(img, 30, 23, 24, 10, 2.0, accent, g)
			_ellipse(img, 28, 10, 4, 2, accent, g)
			if d:
				_ellipse(img, 15, 29, 2, 2, Color(1, 1, 1, 0.65))
				_ellipse(img, 27, 26, 2, 2, Color(1, 1, 1, 0.65))
		"apricot":
			_ellipse(img, 24, 27, 12, 12, base, g)
			_line(img, 24, 15, 25, 8, 2.0, Color(0.45, 0.3, 0.15), g)
			_ellipse(img, 29, 9, 4, 2.2, accent, g)
			if d:
				_ellipse(img, 19, 23, 4, 3, base.lightened(0.28))
				_line(img, 24, 16, 23, 38, 1.2, dark)
		"onion":
			_ellipse(img, 24, 28, 14, 12, base, g)
			_line(img, 24, 17, 24, 7, 2.5, accent, g)
			_line(img, 24, 17, 20, 9, 2.0, accent, g)
			_line(img, 24, 17, 28, 9, 2.0, accent, g)
			if d:
				_ellipse(img, 24, 39, 2, 2, dark)
				_line(img, 18, 22, 18, 34, 1.2, dark)
				_line(img, 30, 22, 30, 34, 1.2, dark)
		"cabbage":
			_ellipse(img, 24, 25, 15, 14, base, g)
			if d:
				_ellipse(img, 24, 25, 10, 10, accent)
				_line(img, 14, 18, 24, 24, 2.0, base.lightened(0.15))
				_line(img, 34, 18, 24, 24, 2.0, base.lightened(0.15))
				_line(img, 24, 24, 24, 36, 2.0, base.lightened(0.15))
		"tomato":
			_ellipse(img, 24, 26, 14, 12, base, g)
			_ellipse(img, 24, 15, 5, 3, accent, g)
			_line(img, 24, 15, 24, 8, 2.5, accent, g)
			if d:
				_ellipse(img, 19, 21, 3.5, 2.5, base.lightened(0.3))
		"pepper":
			_ellipse(img, 24, 27, 10, 14, base, g)
			_rect(img, 22, 9, 4, 7, accent, g)
			if d:
				_ellipse(img, 21, 22, 3, 6, base.lightened(0.25))
				_line(img, 24, 17, 24, 37, 1.5, dark)
		"bean":
			_line(img, 14, 15, 34, 35, 7.0, base, g)
			if d:
				_ellipse(img, 19, 20, 3, 3, accent)
				_ellipse(img, 24, 25, 3, 3, accent)
				_ellipse(img, 29, 30, 3, 3, accent)
		"herbs":
			_line(img, 24, 40, 16, 14, 2.5, base, g)
			_line(img, 24, 40, 32, 14, 2.5, base, g)
			_line(img, 24, 40, 24, 10, 2.5, base, g)
			_ellipse(img, 14, 12, 5, 3, accent, g)
			_ellipse(img, 34, 12, 5, 3, accent, g)
			_ellipse(img, 24, 9, 3, 5, accent, g)
		"corn":
			_line(img, 24, 38, 24, 12, 11, base, g)
			_line(img, 16, 40, 20, 28, 3.5, accent, g)
			_line(img, 32, 40, 28, 28, 3.5, accent, g)
			if d:
				for ky in range(4):
					_line(img, 19, 16.0 + ky * 6.0, 29, 16.0 + ky * 6.0, 1.2, dark)
		"pumpkin":
			_ellipse(img, 24, 27, 16, 12, base, g)
			_ellipse(img, 16, 27, 11, 11, base, g)
			_ellipse(img, 32, 27, 11, 11, base, g)
			_rect(img, 22, 10, 4, 7, accent, g)
			if d:
				_ellipse(img, 24, 27, 7, 11, base.lightened(0.15))
				_line(img, 18, 17, 18, 37, 1.2, dark)
				_line(img, 30, 17, 30, 37, 1.2, dark)
		"bread":
			_ellipse(img, 24, 29, 18, 11, base, g)
			_ellipse(img, 24, 25, 16, 9, accent, g)
			if d:
				_line(img, 15, 21, 18, 28, 1.5, base)
				_line(img, 23, 19, 26, 27, 1.5, base)
				_line(img, 31, 20, 33, 26, 1.5, base)
		"sack":
			_ellipse(img, 24, 31, 15, 13, base, g)
			_rect(img, 19, 10, 10, 10, base, g)
			if d:
				_line(img, 17, 19, 31, 19, 2.0, accent)
				_ellipse(img, 24, 32, 5, 5, accent)
		"mushroom":
			# Шляпка и ножка гриба.
			_ellipse(img, 24, 21, 16, 11, base, g)
			_rect(img, 20, 24, 8, 14, accent, g)
			if d:
				_ellipse(img, 18, 18, 4, 3, base.lightened(0.35))
				_ellipse(img, 28, 16, 3, 2.5, base.lightened(0.35))
				_ellipse(img, 31, 22, 2.5, 2, base.lightened(0.35))
				_ellipse(img, 24, 27, 2.5, 3, accent.darkened(0.25))
		"baked_potato":
			_ellipse(img, 24, 27, 17, 13, base, g)
			if d:
				_ellipse(img, 18, 23, 4, 2.5, accent)
				_ellipse(img, 29, 30, 3.5, 2.5, accent)
				for p in [Vector2(22, 32), Vector2(33, 22), Vector2(16, 31)]:
					_ellipse(img, p.x, p.y, 1.5, 1.5, dark)
		"fried":
			# Жареные кусочки в золотистой корочке.
			_rect(img, 8, 22, 32, 14, base, g)
			if d:
				_rect(img, 11, 18, 26, 11, accent, g)
				for p in [Vector2(16, 23), Vector2(24, 20), Vector2(31, 24)]:
					_ellipse(img, p.x, p.y, 2.5, 2, base.darkened(0.2))
		"soup":
			# Миска с супом и пар.
			_ellipse(img, 24, 30, 16, 9, base, g)
			_ellipse(img, 24, 24, 16, 7, accent, g)
			if d:
				_ellipse(img, 24, 31, 11, 5, base.darkened(0.25))
				_ellipse(img, 19, 23, 4, 2.5, base.lightened(0.3))
				_line(img, 19, 17, 21, 12, 1.6, accent)
				_line(img, 29, 17, 27, 12, 1.6, accent)
		"drink":
			# Кружка с напитком.
			_rect(img, 14, 14, 18, 24, base, g)
			_ellipse(img, 23, 14, 9, 4, accent, g)
			if d:
				_ellipse(img, 23, 14, 7, 3, base.darkened(0.2))
				_line(img, 33, 20, 37, 30, 2.0, base)
				_line(img, 37, 30, 32, 31, 2.0, base)
		"dried":
			# Сушёные грибы в мешочке.
			_ellipse(img, 24, 29, 13, 14, base, g)
			_ellipse(img, 24, 15, 11, 4, accent, g)
			if d:
				_line(img, 17, 17, 31, 17, 1.6, base)
				_ellipse(img, 20, 27, 4, 5, base.lightened(0.2))
				_ellipse(img, 29, 32, 3.5, 4.5, base.lightened(0.2))
		"plate":
			_rect(img, 8, 11, 32, 26, base, g)
			if d:
				for p in [Vector2(12, 15), Vector2(36, 15), Vector2(12, 33), Vector2(36, 33)]:
					_ellipse(img, p.x, p.y, 2, 2, accent)
				_line(img, 15, 21, 33, 21, 1.0, base.lightened(0.2))
		"coil":
			_ellipse(img, 24, 24, 16, 16, base, g)
			if d:
				_ellipse(img, 24, 24, 12.5, 12.5, accent)
				_ellipse(img, 24, 24, 11, 11, base)
				_ellipse(img, 24, 24, 6, 6, base.darkened(0.45))
		"gear":
			_ellipse(img, 24, 24, 13, 13, base, g)
			for k in range(8):
				var ang: float = k * TAU / 8.0
				_line(img, 24, 24, 24 + cos(ang) * 18.0, 24 + sin(ang) * 18.0, 6, base, g)
			if d:
				_ellipse(img, 24, 24, 5, 5, base.darkened(0.5))
				_ellipse(img, 20, 19, 3, 2, accent)
		"battery":
			_rect(img, 13, 11, 22, 31, base, g)
			_rect(img, 20, 6, 8, 5, accent, g)
			if d:
				var bolt_c: Color = Color(1.0, 0.9, 0.3)
				_line(img, 27, 14, 21, 26, 2.0, bolt_c)
				_line(img, 21, 26, 28, 26, 2.0, bolt_c)
				_line(img, 28, 26, 22, 38, 2.0, bolt_c)
		"lamp":
			_line(img, 24, 42, 24, 18, 4, base, g)
			_rect(img, 16, 41, 16, 4, base, g)
			_ellipse(img, 24, 14, 10, 7, accent, g)
			if d:
				_ellipse(img, 24, 15, 6, 3, Color(1.0, 1.0, 0.82))
		"handle":
			_line(img, 11, 38, 37, 10, 7, base, g)
			if d:
				_line(img, 13, 35, 35, 12, 1.5, accent)
		"bolt":
			_rect(img, 14, 8, 20, 9, base, g)
			_rect(img, 20, 17, 8, 24, base, g)
			if d:
				_line(img, 16, 10, 32, 10, 1.5, base.lightened(0.25))
				for k in range(4):
					_line(img, 20, 22 + k * 5, 28, 20 + k * 5, 1.2, accent)
		"fabric":
			_rect(img, 8, 13, 32, 22, base, g)
			if d:
				for k in range(3):
					_line(img, 8, 18 + k * 6, 40, 18 + k * 6, 2.0, accent)
		"strap":
			_line(img, 6, 32, 42, 16, 8, base, g)
			_rect(img, 19, 17, 11, 12, accent, g)
			if d:
				_rect(img, 22, 20, 5, 6, base.darkened(0.4))
		"coal":
			_ellipse(img, 17, 30, 10, 8, base, g)
			_ellipse(img, 30, 27, 11, 9, base, g)
			_ellipse(img, 24, 19, 8, 6, base, g)
			if d:
				_ellipse(img, 14, 27, 3, 1.5, accent)
				_ellipse(img, 27, 23, 4, 1.5, accent)
				_ellipse(img, 22, 17, 2.5, 1.2, accent)
				_line(img, 24, 25, 28, 33, 1.0, base.lightened(0.15))
		"ore":
			_ellipse(img, 25, 26, 17, 12, base, g)
			_ellipse(img, 15, 32, 9, 7, base, g)
			if d:
				_ellipse(img, 20, 21, 6, 3, base.lightened(0.25))
				for p in [Vector2(18, 28), Vector2(29, 23), Vector2(32, 31), Vector2(24, 33), Vector2(13, 33)]:
					_ellipse(img, p.x, p.y, 2.6, 2.0, accent)
					_ellipse(img, p.x - 0.8, p.y - 0.8, 1.0, 0.8, accent.lightened(0.35))
		"clay":
			_ellipse(img, 24, 30, 17, 10, base, g)
			_ellipse(img, 21, 23, 9, 7, base, g)
			if d:
				_ellipse(img, 19, 21, 4, 2, accent)
		"axe":
			_line(img, 16, 42, 30, 8, 4, accent, g)
			_rect(img, 25, 7, 13, 13, base, g)
			if d:
				_line(img, 37, 8, 37, 19, 1.5, base.lightened(0.4))
		"pickaxe":
			_line(img, 18, 42, 27, 12, 4, accent, g)
			_line(img, 9, 17, 25, 10, 5, base, g)
			_line(img, 25, 10, 39, 15, 5, base, g)
		"shovel":
			_line(img, 16, 42, 29, 9, 4, accent, g)
			_rect(img, 26, 8, 17, 8, base, g)
			if d:
				_line(img, 29, 15, 42, 15, 1.5, base.lightened(0.35))
		"bucket":
			_rect(img, 12, 16, 24, 24, base, g)
			_rect(img, 10, 14, 28, 4, accent, g)
			if d:
				_line(img, 13, 15, 24, 6, 1.5, accent)
				_line(img, 24, 6, 35, 15, 1.5, accent)
				_rect(img, 12, 26, 24, 3, base.darkened(0.25))
		"backpack":
			_rect(img, 11, 12, 26, 30, base, g)
			_rect(img, 16, 8, 16, 6, base, g)
			if d:
				_rect(img, 11, 18, 26, 8, base.lightened(0.15))
				_rect(img, 21, 25, 6, 4, base.darkened(0.35))
		_:
			_rect(img, 10, 12, 28, 26, base, g)
			if d:
				_line(img, 10, 18, 38, 18, 1.5, accent)
				_line(img, 24, 12, 24, 38, 1.5, accent)

# ---------------------------------------------------------------------------
# Примитивы (g — расширение для контура)
# ---------------------------------------------------------------------------

static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color, g: float = 0.0) -> void:
	var ex: float = rx + g
	var ey: float = ry + g
	if ex <= 0.0 or ey <= 0.0:
		return
	for y in range(maxi(0, int(cy - ey) - 1), mini(SIZE, int(cy + ey) + 2)):
		for x in range(maxi(0, int(cx - ex) - 1), mini(SIZE, int(cx + ex) + 2)):
			var dx: float = (x + 0.5 - cx) / ex
			var dy: float = (y + 0.5 - cy) / ey
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)

static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color, g: float = 0.0) -> void:
	var gi: int = int(g)
	for yy in range(maxi(0, y - gi), mini(SIZE, y + h + gi)):
		for xx in range(maxi(0, x - gi), mini(SIZE, x + w + gi)):
			img.set_pixel(xx, yy, c)

static func _line(img: Image, x0: float, y0: float, x1: float, y1: float, thick: float, c: Color, g: float = 0.0) -> void:
	var r: float = thick * 0.5 + g
	var a: Vector2 = Vector2(x0, y0)
	var b: Vector2 = Vector2(x1, y1)
	var ab: Vector2 = b - a
	var len_sq: float = maxf(0.0001, ab.length_squared())
	for y in range(maxi(0, int(minf(y0, y1) - r) - 1), mini(SIZE, int(maxf(y0, y1) + r) + 2)):
		for x in range(maxi(0, int(minf(x0, x1) - r) - 1), mini(SIZE, int(maxf(x0, x1) + r) + 2)):
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
			if p.distance_to(a + ab * t) <= r:
				img.set_pixel(x, y, c)
