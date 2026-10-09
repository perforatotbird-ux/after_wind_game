class_name VoxelDeposit
extends "res://scripts/interaction/interactable.gd"

## Копаемая жила: участок земли из разрушаемых вокселей 0.5 м.
##
## Игрок наводит курсор (или просто смотрит) на блок грунта рядом с собой и бьёт
## лопатой или киркой: каждый блок разбивается за несколько ударов и выдаёт свой
## ресурс. Сверху участок неотличим от травы (кроме камешков-«выходов» породы),
## внутри — грунт и 1–3 вида простых ресурсов: песок, глина, уголь, железная руда.
## Внешнее кольцо блоков (стенки) и нижний слой (скальное основание) не копаются,
## чтобы яма не выходила за пределы участка.
##
## Сетка: x, z ∈ [0, size_cells), y ∈ [0, depth_cells); y = depth_cells - 1 — верхний
## слой на уровне земли (верх участка — y = 0 мира). Узел стоит в центре участка.
## Земля мира (ground_terrain.gd) вырезает под участок дыру по get_footprint_rect().
## Состояние вокселей и найденные ресурсы попадают в сохранение (секция «deposits»).

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const VoxelTextures = preload("res://scripts/world/voxel_textures.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

signal voxel_dug(cell: Vector3i, material: int)
signal resource_discovered(item_id: String)

const GROUP: String = "voxel_deposits"
## Группа твёрдых тел вокселей: на их уступы персонаж умеет шагать (player._try_step_up).
const TERRAIN_GROUP: String = "voxel_terrain"
const VOXEL_SIZE: float = 0.5
## Досягаемость блока от груди персонажа, м.
const REACH: float = 2.4
const NO_CELL: Vector3i = Vector3i(-1, -1, -1)
const MAX_VOXELS: int = 32 * 32 * 16

enum Mat { AIR, SOIL, SAND, CLAY, COAL, IRON_ORE, BEDROCK }
const MAT_COUNT: int = 7
const MAT_NAMES: Array[String] = ["Воздух", "Грунт", "Песок", "Глина", "Уголь", "Железная руда", "Скальное основание"]
## Тайл атласа VoxelTextures.Tile для каждого материала.
const MAT_TILES: Array[int] = [0, 2, 3, 4, 5, 6, 7]
## Средний цвет крошки при разрушении блока.
const MAT_COLORS: Array[Color] = [Color.WHITE, Color(0.37, 0.27, 0.18), Color(0.84, 0.74, 0.5), Color(0.69, 0.41, 0.29), Color(0.15, 0.14, 0.15), Color(0.62, 0.42, 0.3), Color(0.2, 0.2, 0.21)]
## Оттенок камешков-«выходов» на траве: уголь темнее, руда рыжее — видно издалека.
const MARKER_TINTS: Dictionary = {Mat.COAL: Color(0.45, 0.45, 0.47), Mat.IRON_ORE: Color(1.0, 0.7, 0.5), Mat.CLAY: Color(1.0, 0.85, 0.78)}
## Ударов на блок (инструментом 1 ур.), нужный инструмент, затраты энергии, добыча.
const MAT_HITS: Array[int] = [0, 1, 1, 2, 3, 4, 0]
const MAT_TOOL: Array[String] = ["", "shovel", "shovel", "shovel", "pickaxe", "pickaxe", ""]
const MAT_ENERGY: Array[float] = [0.0, 1.2, 1.4, 1.8, 2.4, 3.0, 0.0]
const MAT_ITEM: Array[String] = ["", "", "sand", "clay", "coal", "iron_ore", ""]
const MAT_YIELD: Array[int] = [0, 0, 2, 2, 2, 1, 0]
## Шанс найти камень в простом грунте.
const SOIL_STONE_CHANCE: float = 0.12

## Ресурсы, которые могут лежать в жиле, и их глубина (слой 0 — верхний, травяной).
const RESOURCE_MATS: Dictionary = {"sand": Mat.SAND, "clay": Mat.CLAY, "coal": Mat.COAL, "iron_ore": Mat.IRON_ORE}
const RESOURCE_ORDER: Array[String] = ["sand", "clay", "coal", "iron_ore"]
## item_id -> [мин. слой, макс. слой, мин. пятен, макс. пятен, мин. радиус, макс. радиус]
const RESOURCE_LAYOUT: Dictionary = {
	"sand": [1, 3, 2, 3, 1.8, 2.6],
	"clay": [1, 5, 2, 3, 1.6, 2.4],
	"coal": [2, 6, 2, 2, 1.4, 2.0],
	"iron_ore": [3, 6, 1, 2, 1.2, 1.7],
}

@export var deposit_name: String = "Жила"
## Сид генерации: одинаковый сид — одинаковое расположение ресурсов.
@export var deposit_seed: int = 1
## Ресурсы жилы (1–3 из sand, clay, coal, iron_ore). Пусто — выбираются по сиду.
@export var resource_types: PackedStringArray = PackedStringArray()
@export_range(6, 32) var size_cells: int = 16
@export_range(3, 16) var depth_cells: int = 8
## Наведение курсором мыши; без мыши (и в headless-тестах) — блок перед персонажем.
@export var use_mouse_aim: bool = true

## Материал каждого вокселя: индекс x + z * size + y * size * size.
var voxels: PackedByteArray = PackedByteArray()
## Накопленные удары по блокам, которые ещё не разрушены: Vector3i -> int.
var damage: Dictionary = {}
## Найденные игроком ресурсы этой жилы (item_id).
var discovered: Array[String] = []
var active_resources: Array[String] = []

## Свойства для персонажа (как у ResourceNode): инструмент и прочность блока под прицелом.
var required_tool: String = "shovel"
var current_hits: int = 0
var max_hits: int = 0

var _target: Vector3i = NO_CELL
var _target_ok: bool = false
var _prompt_dirty: bool = false
var _last_player: Node = null
var _aim_msec: int = 0
var _markers: Array = []
var _rng := RandomNumberGenerator.new()

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _body_shape: ConcavePolygonShape3D
var _highlight: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var _edge_material: StandardMaterial3D

const _DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## Углы граней единичного куба (против часовой стрелки снаружи); треугольники выводятся
## в обратном порядке — лицевая сторона Godot идёт по часовой стрелке.
const _FACE_CORNERS: Array = [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	object_name = deposit_name
	prompt_action = "Копать"
	_build_nodes()
	if voxels.size() != size_cells * size_cells * depth_cells:
		generate()
	rebuild()

# --- Генерация ---------------------------------------------------------------

func generate() -> void:
	var n: int = size_cells
	voxels = PackedByteArray()
	voxels.resize(n * n * depth_cells)
	voxels.fill(Mat.SOIL)
	for z in n:
		for x in n:
			voxels[_index(Vector3i(x, 0, z))] = Mat.BEDROCK
	damage.clear()
	discovered.clear()
	_markers.clear()
	_rng.seed = hash(deposit_seed)
	active_resources = _resolve_resources()
	var noise := FastNoiseLite.new()
	noise.seed = deposit_seed
	noise.frequency = 0.35
	for item_id in active_resources:
		var mat: int = RESOURCE_MATS[item_id]
		var lay: Array = RESOURCE_LAYOUT[item_id]
		var blobs: int = _rng.randi_range(lay[2], lay[3])
		for b in blobs:
			var center := Vector3(
				_rng.randf_range(2.0, n - 3.0),
				float(depth_cells - 1 - _rng.randi_range(lay[0], lay[1])),
				_rng.randf_range(2.0, n - 3.0))
			var r: float = _rng.randf_range(lay[4], lay[5])
			var radii := Vector3(r, maxf(0.9, r * 0.6), r * _rng.randf_range(0.75, 1.25))
			_stamp_blob(mat, center, radii, lay, noise)
			_markers.append([int(center.x) + _rng.randi_range(-1, 1), int(center.z) + _rng.randi_range(-1, 1), mat, _rng.randf(), _rng.randf()])

func _resolve_resources() -> Array[String]:
	var result: Array[String] = []
	for item_id in resource_types:
		if RESOURCE_MATS.has(item_id) and not item_id in result:
			result.append(item_id)
	if result.is_empty():
		var pool: Array[String] = RESOURCE_ORDER.duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: String = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		result = pool.slice(0, _rng.randi_range(1, 3))
	result = result.slice(0, 3)
	result.sort_custom(func(a, b): return RESOURCE_ORDER.find(a) < RESOURCE_ORDER.find(b))
	return result

func _stamp_blob(mat: int, center: Vector3, radii: Vector3, lay: Array, noise: FastNoiseLite) -> void:
	var lo := Vector3i(floori(center.x - radii.x - 1), floori(center.y - radii.y - 1), floori(center.z - radii.z - 1))
	var hi := Vector3i(ceili(center.x + radii.x + 1), ceili(center.y + radii.y + 1), ceili(center.z + radii.z + 1))
	var y_min: int = depth_cells - 1 - int(lay[1])
	var y_max: int = depth_cells - 1 - int(lay[0])
	for y in range(maxi(lo.y, y_min), mini(hi.y, y_max) + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var cell := Vector3i(x, y, z)
				if not _is_interior(cell) or get_voxel(cell) != Mat.SOIL:
					continue
				var d: Vector3 = (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) - center) / radii
				if d.length_squared() + noise.get_noise_3d(x, y, z) * 0.45 < 1.0:
					voxels[_index(cell)] = mat
	# Центр пятна всегда заполнен — ресурс гарантированно есть.
	var c := Vector3i(int(center.x), int(center.y), int(center.z))
	if _is_interior(c):
		voxels[_index(c)] = mat

# --- Доступ к сетке ----------------------------------------------------------

func _index(c: Vector3i) -> int:
	return c.x + c.z * size_cells + c.y * size_cells * size_cells

func is_inside(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < size_cells and c.y < depth_cells and c.z < size_cells

func _is_interior(c: Vector3i) -> bool:
	return c.x > 0 and c.z > 0 and c.y > 0 and c.x < size_cells - 1 and c.z < size_cells - 1 and c.y < depth_cells

func get_voxel(c: Vector3i) -> int:
	return voxels[_index(c)] if is_inside(c) else Mat.AIR

func is_solid(c: Vector3i) -> bool:
	return get_voxel(c) != Mat.AIR

## Можно ли копать блок: не воздух, не скальное основание и не внешняя стенка участка.
func is_cell_diggable(c: Vector3i) -> bool:
	var m: int = get_voxel(c)
	return m != Mat.AIR and m != Mat.BEDROCK and _is_interior(c)

func count_material(mat: int) -> int:
	var total: int = 0
	for v in voxels:
		if v == mat:
			total += 1
	return total

func _half_extent() -> float:
	return size_cells * VOXEL_SIZE * 0.5

## Нижний угол блока в локальных координатах узла.
func cell_to_local(c: Vector3i) -> Vector3:
	return Vector3(c.x * VOXEL_SIZE - _half_extent(), (c.y - depth_cells) * VOXEL_SIZE, c.z * VOXEL_SIZE - _half_extent())

func cell_center_global(c: Vector3i) -> Vector3:
	return to_global(cell_to_local(c) + Vector3.ONE * VOXEL_SIZE * 0.5)

## Позиция в сетке (дробная, в блоках) для локальной точки.
func _local_to_grid(p: Vector3) -> Vector3:
	return (p + Vector3(_half_extent(), depth_cells * VOXEL_SIZE, _half_extent())) / VOXEL_SIZE

func global_to_cell(p: Vector3) -> Vector3i:
	var g: Vector3 = _local_to_grid(to_local(p))
	return Vector3i(floori(g.x), floori(g.y), floori(g.z))

## Прямоугольник участка на плоскости XZ мира (для выреза в земле).
func get_footprint_rect() -> Rect2:
	var h: float = _half_extent()
	return Rect2(global_position.x - h, global_position.z - h, h * 2.0, h * 2.0)

# --- Прицел ------------------------------------------------------------------

## Вызывается персонажем каждый кадр, пока он рядом. Возвращает true, если есть блок в досягаемости.
func update_aim(player: Node3D) -> bool:
	_last_player = player
	_aim_msec = Time.get_ticks_msec()
	var cell: Vector3i = _pick_cell(player)
	if cell != _target:
		_target = cell
		_prompt_dirty = true
	_refresh_target(player)
	return _target != NO_CELL

func has_target() -> bool:
	return _target != NO_CELL

func get_target_cell() -> Vector3i:
	return _target

## Ручной выбор блока (тесты, подсказки). NO_CELL снимает прицел.
func set_target_cell(cell: Vector3i, player: Node = null) -> void:
	_target = cell if is_solid(cell) else NO_CELL
	_prompt_dirty = true
	_refresh_target(player)

func get_interaction_point() -> Vector3:
	return cell_center_global(_target) if _target != NO_CELL else global_position

func is_in_reach(player: Node3D) -> bool:
	return _target != NO_CELL and _cell_in_reach(_target, player, 0.35)

func _cell_in_reach(c: Vector3i, player: Node3D, slack: float = 0.0) -> bool:
	var chest: Vector3 = player.global_position + Vector3.UP * 1.0
	return chest.distance_to(cell_center_global(c)) <= REACH + slack

func _pick_cell(player: Node3D) -> Vector3i:
	if use_mouse_aim and DisplayServer.get_name() != "headless" and is_inside_tree():
		var cell: Vector3i = _pick_by_mouse(player)
		if cell != NO_CELL:
			return cell
	return _pick_by_facing(player)

func _pick_by_mouse(player: Node3D) -> Vector3i:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return NO_CELL
	var mouse: Vector2 = vp.get_mouse_position()
	if not vp.get_visible_rect().has_point(mouse):
		return NO_CELL
	var origin: Vector3 = to_local(cam.project_ray_origin(mouse))
	var dir: Vector3 = global_transform.basis.inverse() * cam.project_ray_normal(mouse)
	var cell: Vector3i = _raycast_cell(_local_to_grid(origin), dir)
	if cell != NO_CELL and _cell_in_reach(cell, player):
		return cell
	return NO_CELL

## Первый твёрдый блок на луче (координаты сетки), обход вокселей Amanatides–Woo.
func _raycast_cell(o: Vector3, d: Vector3) -> Vector3i:
	var size := Vector3(size_cells, depth_cells, size_cells)
	var t_enter: float = 0.0
	var t_exit: float = 1e9
	for a in 3:
		if absf(d[a]) < 1e-8:
			if o[a] < 0.0 or o[a] > size[a]:
				return NO_CELL
		else:
			var t1: float = (0.0 - o[a]) / d[a]
			var t2: float = (size[a] - o[a]) / d[a]
			t_enter = maxf(t_enter, minf(t1, t2))
			t_exit = minf(t_exit, maxf(t1, t2))
	if t_enter > t_exit:
		return NO_CELL
	var p: Vector3 = o + d * (t_enter + 1e-4)
	var cell := Vector3i(clampi(floori(p.x), 0, size_cells - 1), clampi(floori(p.y), 0, depth_cells - 1), clampi(floori(p.z), 0, size_cells - 1))
	var step := Vector3i(signi(int(signf(d.x))), signi(int(signf(d.y))), signi(int(signf(d.z))))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in 3:
		if absf(d[a]) >= 1e-8:
			var boundary: float = cell[a] + (1.0 if d[a] > 0.0 else 0.0)
			t_max[a] = (boundary - p[a]) / d[a]
			t_delta[a] = absf(1.0 / d[a])
	for i in size_cells * 3 + depth_cells * 2:
		if not is_inside(cell):
			return NO_CELL
		if is_solid(cell):
			return cell
		var axis: int = 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
	return NO_CELL

## Без мыши: стенка перед персонажем (сверху вниз), затем грунт перед ногами, затем под ногами.
func _pick_by_facing(player: Node3D) -> Vector3i:
	var root: Node3D = player.get("visual_root") as Node3D if "visual_root" in player else null
	var facing: Vector3 = -root.global_transform.basis.z if root else -player.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.001 else Vector3.FORWARD
	var feet: Vector3 = player.global_position
	for dy in [1.25, 0.75, 0.25, -0.25, -0.75]:
		var c: Vector3i = global_to_cell(feet + facing * 0.6 + Vector3.UP * dy)
		if is_cell_diggable(c) and _cell_in_reach(c, player):
			return c
	var below: Vector3i = global_to_cell(feet + Vector3.DOWN * 0.25)
	if is_cell_diggable(below) and _cell_in_reach(below, player):
		return below
	return NO_CELL

func _equipped_dig_tool(inv: Object) -> String:
	if inv == null:
		return "shovel"
	if inv.is_tool_equipped("shovel"):
		return "shovel"
	if inv.is_tool_equipped("pickaxe"):
		return "pickaxe"
	return ""

## Ударов на блок: мягкий грунт киркой копается на удар дольше, чем лопатой.
func hits_for(mat: int, tool_type: String) -> int:
	var hits: int = MAT_HITS[mat]
	if tool_type == "pickaxe" and MAT_TOOL[mat] == "shovel":
		hits += 1
	return hits

func _refresh_target(player: Node = null) -> void:
	var inv: Object = player.get("inventory") if player and "inventory" in player else null
	var tool_type: String = _equipped_dig_tool(inv)
	var ok: bool = false
	var new_max: int = 0
	var new_cur: int = 0
	var new_tool: String = "shovel"
	if _target != NO_CELL:
		var mat: int = get_voxel(_target)
		new_tool = MAT_TOOL[mat] if MAT_TOOL[mat] != "" else "shovel"
		if is_cell_diggable(_target):
			var use_tool: String = tool_type if tool_type != "" else new_tool
			new_max = hits_for(mat, use_tool)
			new_cur = maxi(0, new_max - int(damage.get(_target, 0)))
			ok = tool_type != "" and not (new_tool == "pickaxe" and tool_type != "pickaxe")
			# Мягкий грунт годится и под кирку: прицел не требует сменить инструмент.
			if new_tool == "shovel" and tool_type == "pickaxe":
				new_tool = "pickaxe"
	if ok != _target_ok or new_cur != current_hits or new_max != max_hits or new_tool != required_tool:
		_prompt_dirty = true
	_target_ok = ok
	current_hits = new_cur
	max_hits = new_max
	required_tool = new_tool
	_update_highlight()

func consume_prompt_dirty() -> bool:
	var was: bool = _prompt_dirty
	_prompt_dirty = false
	return was

func get_prompt() -> String:
	if _target == NO_CELL:
		return "%s: подойдите ближе к грунту" % deposit_name
	var mat: int = get_voxel(_target)
	var found: String = ""
	if not discovered.is_empty():
		var names: Array[String] = []
		for item_id in discovered:
			names.append(ItemDB.get_item_name(item_id))
		found = " · найдено: " + ", ".join(names)
	if mat == Mat.BEDROCK:
		return "Скальное основание — глубже не прокопать" + found
	if not _is_interior(_target):
		return "Край участка — дальше копать нельзя" + found
	var tool_data: Dictionary = ItemDB.get_item(MAT_TOOL[mat])
	var tool_label: String = "%s %s" % [tool_data.get("icon", ""), tool_data.get("name", MAT_TOOL[mat])]
	if MAT_TOOL[mat] == "shovel":
		tool_label = "🪏 лопата или ⛏️ кирка"
	if not _target_ok:
		return "%s: нужна %s (клавиши 1–5)%s" % [MAT_NAMES[mat], tool_label, found]
	return "[E/ЛКМ] Копать: %s (%s) [%d/%d]%s" % [MAT_NAMES[mat], tool_label, current_hits, max_hits, found]

# --- Копание -----------------------------------------------------------------

func _on_interacted(player: Node) -> void:
	if _target == NO_CELL or not is_solid(_target):
		_notify(player, "⛏️ Наведите курсор на грунт рядом с персонажем")
		return
	var cell: Vector3i = _target
	var mat: int = get_voxel(cell)
	if not is_cell_diggable(cell):
		_notify(player, "🪨 " + get_prompt())
		return
	var inv: Object = player.get("inventory") if "inventory" in player else null
	var tool_type: String = _equipped_dig_tool(inv)
	if tool_type == "" or (MAT_TOOL[mat] == "pickaxe" and tool_type != "pickaxe"):
		var need: Dictionary = ItemDB.get_item(MAT_TOOL[mat])
		var held: String = ItemDB.get_item_name(inv.get_equipped_tool()) if inv else "—"
		_notify(player, "⚠️ %s: нужна %s %s! В руках: %s." % [MAT_NAMES[mat], need.get("icon", ""), need.get("name", ""), held])
		return
	var level: int = inv.get_tool_level(tool_type) if inv and inv.has_method("get_tool_level") else 1
	var hit_power: int = 2 if level >= 2 else 1
	var energy: float = MAT_ENERGY[mat] * (0.65 if level >= 2 else 1.0)
	var is_ore: bool = mat == Mat.COAL or mat == Mat.IRON_ORE
	var is_miner: bool = "character_class" in player and player.character_class == "miner"
	if is_miner and is_ore:
		energy *= 0.8
	if player.has_method("consume_energy"):
		player.consume_energy(energy)
	if is_ore or tool_type == "pickaxe":
		AudioManager.play("hit_stone", randf_range(0.9, 1.05))
	else:
		AudioManager.play("hit_wood", randf_range(0.55, 0.7), -3.0)
	var hits: int = int(damage.get(cell, 0)) + hit_power
	var needed: int = hits_for(mat, tool_type)
	if hits < needed:
		damage[cell] = hits
		_spawn_crumbs(cell, mat, 4)
		_refresh_target(player)
		return
	_break_cell(cell, mat, player, level, is_miner)

func _break_cell(cell: Vector3i, mat: int, player: Node, level: int, is_miner: bool) -> void:
	voxels[_index(cell)] = Mat.AIR
	damage.erase(cell)
	var item_id: String = MAT_ITEM[mat]
	var amount: int = MAT_YIELD[mat]
	if mat == Mat.IRON_ORE and _rng.randf() < 0.5:
		amount += 1
	if item_id != "":
		if level >= 2:
			amount += 1
		if is_miner and (mat == Mat.COAL or mat == Mat.IRON_ORE):
			amount += 1
	elif _rng.randf() < SOIL_STONE_CHANCE:
		item_id = "stone"
		amount = 1
	if item_id != "" and amount > 0:
		_give(player, item_id, amount, cell)
		if item_id in RESOURCE_MATS and not item_id in discovered:
			discovered.append(item_id)
			resource_discovered.emit(item_id)
			_notify(player, "🔎 Найдена жила: %s! %s +%d" % [ItemDB.get_item_name(item_id), ItemDB.get_item_icon(item_id), amount])
		else:
			_notify(player, "%s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), amount])
	_spawn_crumbs(cell, mat, 12)
	rebuild()
	_target = NO_CELL
	current_hits = 0
	_prompt_dirty = true
	_update_highlight()
	voxel_dug.emit(cell, mat)

func _give(player: Node, item_id: String, amount: int, cell: Vector3i) -> void:
	var inv: Object = player.get("inventory") if "inventory" in player else null
	if inv and inv.add_item(item_id, amount):
		return
	# Рюкзак полон — добыча остаётся кучкой на краю ямы.
	DroppedItemScript.spawn(get_parent(), item_id, amount, cell_center_global(cell))

## Удар без прицела (тесты, отладка): копает указанный блок.
func dig_cell(cell: Vector3i, player: Node) -> void:
	set_target_cell(cell, player)
	interact(player)

func _notify(player: Node, text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)

# --- Узлы, меш и коллизия ----------------------------------------------------

func _build_nodes() -> void:
	var area_shape := CollisionShape3D.new()
	area_shape.name = "InteractionShape"
	var box := BoxShape3D.new()
	var height: float = depth_cells * VOXEL_SIZE + 2.0
	box.size = Vector3(size_cells * VOXEL_SIZE, height, size_cells * VOXEL_SIZE)
	area_shape.shape = box
	area_shape.position.y = -depth_cells * VOXEL_SIZE + height * 0.5
	add_child(area_shape)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "VoxelMesh"
	add_child(_mesh_instance)

	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_to_group(TERRAIN_GROUP)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	_body_shape = ConcavePolygonShape3D.new()
	_body_shape.backface_collision = true
	col.shape = _body_shape
	_body.add_child(col)
	add_child(_body)

	_highlight = MeshInstance3D.new()
	_highlight.name = "TargetHighlight"
	var hb := BoxMesh.new()
	hb.size = Vector3.ONE * VOXEL_SIZE * 1.04
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_mat.albedo_color = Color(1.0, 1.0, 0.6, 0.22)
	hb.material = _highlight_mat
	_highlight.mesh = hb
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	add_child(_highlight)
	# Рёбра блока под прицелом — чтобы подсветка читалась и на ярком песке.
	var edges := MeshInstance3D.new()
	edges.name = "Edges"
	var im := ImmediateMesh.new()
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.vertex_color_use_as_albedo = true
	edge_mat.no_depth_test = true
	edge_mat.render_priority = 1
	im.surface_begin(Mesh.PRIMITIVE_LINES, edge_mat)
	var h: float = VOXEL_SIZE * 0.53
	for a in 3:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p0 := Vector3.ZERO
				var p1 := Vector3.ZERO
				p0[a] = -h
				p1[a] = h
				p0[(a + 1) % 3] = sx * h
				p1[(a + 1) % 3] = sx * h
				p0[(a + 2) % 3] = sy * h
				p1[(a + 2) % 3] = sy * h
				im.surface_set_color(Color.WHITE)
				im.surface_add_vertex(p0)
				im.surface_set_color(Color.WHITE)
				im.surface_add_vertex(p1)
	im.surface_end()
	edges.mesh = im
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.add_child(edges)
	_edge_material = edge_mat

func _process(_delta: float) -> void:
	if _highlight and _highlight.visible:
		# Подсветка гаснет, если персонаж ушёл или выбрал другой объект.
		var focused: bool = is_instance_valid(_last_player) and _last_player.get("current_interactable") == self
		if not focused or Time.get_ticks_msec() - _aim_msec > 250:
			_highlight.visible = false

func _update_highlight() -> void:
	if _highlight == null:
		return
	if _target == NO_CELL:
		_highlight.visible = false
		return
	_highlight.position = cell_to_local(_target) + Vector3.ONE * VOXEL_SIZE * 0.5
	var ok: bool = _target_ok
	_highlight_mat.albedo_color = Color(0.55, 1.0, 0.5, 0.28) if ok else Color(1.0, 0.35, 0.3, 0.3)
	if _edge_material:
		_edge_material.albedo_color = Color(0.85, 1.0, 0.8) if ok else Color(1.0, 0.55, 0.5)
	_highlight.visible = is_instance_valid(_last_player) and _last_player.get("current_interactable") == self

## Перестраивает видимый меш (только открытые грани) и коллизию участка.
func rebuild() -> void:
	if _mesh_instance == null:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var faces := PackedVector3Array()
	var top: int = depth_cells - 1
	for y in depth_cells:
		var shade: float = 1.0 if y == top else clampf(0.97 - 0.035 * float(top - y), 0.72, 1.0)
		for z in size_cells:
			for x in size_cells:
				var c := Vector3i(x, y, z)
				var mat: int = get_voxel(c)
				if mat == Mat.AIR:
					continue
				var base: Vector3 = cell_to_local(c)
				for f in 6:
					var nb: Vector3i = c + _DIRS[f]
					var open: bool = (nb.y >= depth_cells) if not is_inside(nb) else get_voxel(nb) == Mat.AIR
					if not open:
						continue
					var tile: int = MAT_TILES[mat]
					if y == top and mat == Mat.SOIL:
						tile = 0 if f == 2 else (2 if f == 3 else 1)
					var s: float = shade * (0.8 if f == 3 else 1.0)
					_emit_face(verts, normals, uvs, colors, faces, f, base, Vector3.ONE * VOXEL_SIZE, tile, s)
	_emit_markers(verts, normals, uvs, colors)
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, VoxelTextures.get_material())
	_mesh_instance.mesh = mesh
	_body_shape.set_faces(faces)

func _emit_face(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, faces: Variant, f: int, base: Vector3, size: Vector3, tile: int, shade: float, tint: Color = Color.WHITE) -> void:
	var corners: Array = _FACE_CORNERS[f]
	var n := Vector3(_DIRS[f])
	var rect: Rect2 = VoxelTextures.tile_uv_rect(tile)
	var col := Color(shade * tint.r, shade * tint.g, shade * tint.b)
	var pts: Array[Vector3] = []
	var tex: Array[Vector2] = []
	for k in 4:
		var cc: Vector3 = corners[k]
		pts.append(base + cc * size)
		var uv: Vector2
		if f < 2:
			uv = Vector2(cc.z if f == 1 else 1.0 - cc.z, 1.0 - cc.y)
		elif f < 4:
			uv = Vector2(cc.x, cc.z)
		else:
			uv = Vector2(cc.x if f == 5 else 1.0 - cc.x, 1.0 - cc.y)
		tex.append(rect.position + uv * rect.size)
	for k in [0, 2, 1, 0, 3, 2]:
		verts.append(pts[k])
		normals.append(n)
		uvs.append(tex[k])
		colors.append(col)
		if faces != null:
			faces.append(pts[k])

## Камешки-«выходы» породы на траве над пятнами ресурсов (пропадают, если блок под ними выкопан).
func _emit_markers(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray) -> void:
	var top: int = depth_cells - 1
	for m in _markers:
		var c := Vector3i(clampi(m[0], 1, size_cells - 2), top, clampi(m[1], 1, size_cells - 2))
		if get_voxel(c) == Mat.AIR:
			continue
		var tint: Color = MARKER_TINTS.get(m[2], Color.WHITE)
		for k in 3:
			var sz := Vector3(0.12 + 0.04 * k, 0.06 + 0.02 * (k % 2), 0.11 + 0.035 * k)
			var off := Vector3(fmod(m[3] + k * 0.37, 1.0) * (VOXEL_SIZE - sz.x), VOXEL_SIZE, fmod(m[4] + k * 0.61, 1.0) * (VOXEL_SIZE - sz.z))
			var base: Vector3 = cell_to_local(c) + off
			for f in [0, 1, 2, 4, 5]:
				_emit_face(verts, normals, uvs, colors, null, f, base, sz, MAT_TILES[m[2]], 1.0, tint)

func _spawn_crumbs(cell: Vector3i, mat: int, amount: int) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.07
	var mat_res := StandardMaterial3D.new()
	mat_res.albedo_color = MAT_COLORS[mat]
	bm.material = mat_res
	p.mesh = bm
	p.position = cell_to_local(cell) + Vector3(0.25, 0.5, 0.25)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

# --- Сохранение --------------------------------------------------------------

## Воксели сохраняются RLE-списком [материал, длина, материал, длина, ...]:
## в JSON он короткий (жила — в основном длинные полосы грунта) и проверяется без декодеров.
func get_save_state() -> Dictionary:
	return {
		"seed": deposit_seed,
		"size": voxels.size(),
		"voxels": encode_voxels(voxels),
		"discovered": discovered.duplicate(),
	}

func apply_save_state(state: Dictionary) -> bool:
	if not is_valid_save_state(state) or int(state["size"]) != size_cells * size_cells * depth_cells:
		return false
	voxels = decode_voxels(state)
	damage.clear()
	discovered.clear()
	for item_id in state.get("discovered", []):
		discovered.append(str(item_id))
	_target = NO_CELL
	current_hits = 0
	_prompt_dirty = true
	rebuild()
	_update_highlight()
	return true

static func encode_voxels(data: PackedByteArray) -> Array:
	var rle: Array = []
	var i: int = 0
	while i < data.size():
		var j: int = i
		while j < data.size() and data[j] == data[i]:
			j += 1
		rle.append(int(data[i]))
		rle.append(j - i)
		i = j
	return rle

## Пустой массив, если данные некорректны (размер, материалы, длины полос).
static func decode_voxels(state: Dictionary) -> PackedByteArray:
	var size = state.get("size", 0)
	var rle = state.get("voxels", null)
	if not (size is int or size is float) or int(size) != size or int(size) <= 0 or int(size) > MAX_VOXELS:
		return PackedByteArray()
	if not rle is Array or rle.size() % 2 != 0:
		return PackedByteArray()
	var out := PackedByteArray()
	for k in range(0, rle.size(), 2):
		var m = rle[k]
		var n = rle[k + 1]
		if not (m is int or m is float) or not (n is int or n is float) or int(m) != m or int(n) != n:
			return PackedByteArray()
		if int(m) < 0 or int(m) >= MAT_COUNT or int(n) <= 0 or out.size() + int(n) > int(size):
			return PackedByteArray()
		var start: int = out.size()
		out.resize(start + int(n))
		for t in range(start, out.size()):
			out[t] = int(m)
	return out if out.size() == int(size) else PackedByteArray()

static func is_valid_save_state(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	var discovered_list = state.get("discovered", [])
	if not discovered_list is Array:
		return false
	for item_id in discovered_list:
		if not item_id is String or not RESOURCE_MATS.has(item_id):
			return false
	return not decode_voxels(state).is_empty()
