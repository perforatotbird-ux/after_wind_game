extends StaticBody3D

## Земля мира с вырезами под копаемые жилы (VoxelDeposit).
##
## Исходные меш и коллизия Ground — один ящик 80×1×80. Если в мире есть жилы,
## ящик заменяется полосами-ящиками вокруг их участков (get_footprint_rect):
## внутри выреза землю изображает и держит сама жила. Земля — шейдер луга
## (meadow_ground.gd): тот же пиксельный тайл травы, что и на верху жил, с
## пятнами сочной/сухой травы, проплешинами и вытоптанным двором базы.

const VoxelDepositScript = preload("res://scripts/world/voxel_deposit.gd")
const VoxelTextures = preload("res://scripts/world/voxel_textures.gd")
const MeadowGround = preload("res://scripts/world/meadow_ground.gd")

@export var ground_size: Vector2 = Vector2(80, 80)
@export var thickness: float = 1.0
## Вытоптанный двор базы (мировые x, z, размер) — рисуется шейдером луга.
@export var yard_rect: Rect2 = MeadowGround.DEFAULT_YARD

var _pieces: Array[Node] = []

func _ready() -> void:
	rebuild_holes.call_deferred()

func get_hole_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not is_inside_tree():
		return rects
	for d in get_tree().get_nodes_in_group(VoxelDepositScript.GROUP):
		if d is Node3D and d.has_method("get_footprint_rect"):
			var r: Rect2 = d.get_footprint_rect()
			rects.append(Rect2(r.position - Vector2(global_position.x, global_position.z), r.size))
	return rects

## Пересобирает куски земли; без жил оставляет исходный ящик.
func rebuild_holes() -> void:
	for p in _pieces:
		if is_instance_valid(p):
			p.queue_free()
	_pieces.clear()
	var rects: Array[Rect2] = get_hole_rects()
	var src_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	var src_col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if src_mesh:
		src_mesh.visible = rects.is_empty()
		src_mesh.material_override = MeadowGround.get_material(yard_rect)
	if src_col:
		src_col.disabled = not rects.is_empty()
	if rects.is_empty():
		return
	var material: Material = MeadowGround.get_material(yard_rect)
	var half: Vector2 = ground_size * 0.5
	var xs: Array[float] = [-half.x, half.x]
	var zs: Array[float] = [-half.y, half.y]
	for r in rects:
		for v in [r.position.x, r.end.x]:
			if v > -half.x and v < half.x and not v in xs:
				xs.append(v)
		for v in [r.position.y, r.end.y]:
			if v > -half.y and v < half.y and not v in zs:
				zs.append(v)
	xs.sort()
	zs.sort()
	for i in xs.size() - 1:
		var run_start: int = -1
		for j in zs.size():
			var solid: bool = false
			if j < zs.size() - 1:
				var center := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
				solid = true
				for r in rects:
					if r.has_point(center):
						solid = false
						break
			if solid and run_start < 0:
				run_start = j
			elif not solid and run_start >= 0:
				_add_piece(Rect2(xs[i], zs[run_start], xs[i + 1] - xs[i], zs[j] - zs[run_start]), material)
				run_start = -1

func _add_piece(r: Rect2, material: Material) -> void:
	var size := Vector3(r.size.x, thickness, r.size.y)
	var center := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = center
	add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	mi.position = center
	add_child(mi)
	_pieces.append(col)
	_pieces.append(mi)
