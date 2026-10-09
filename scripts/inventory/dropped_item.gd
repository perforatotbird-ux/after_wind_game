class_name DroppedItem
extends "res://scripts/interaction/interactable.gd"

## Предмет, выброшенный из рюкзака на землю. Подбирается по [E]: если места в рюкзаке
## мало — берётся сколько влезет, остаток лежит дальше. Одинаковые предметы,
## брошенные рядом (MERGE_RADIUS), складываются в одну кучку. Сохраняются в сейве
## (секция dropped_items, см. save_manager.gd).

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const SCRIPT_PATH: String = "res://scripts/inventory/dropped_item.gd"
const GROUP: String = "dropped_items"
const MERGE_RADIUS: float = 1.2
const DROP_DISTANCE: float = 1.1

var item_id: String = ""
var amount: int = 0

var _visual: Node3D
var _label: Label3D
var _time: float = 0.0

## Создаёт кучку предметов в точке pos (или добавляет к ближайшей кучке того же предмета).
static func spawn(parent: Node, p_item_id: String, p_amount: int, pos: Vector3) -> Node:
	if parent == null or p_amount <= 0 or ItemDB.get_item(p_item_id).is_empty():
		return null
	if parent.is_inside_tree():
		for n in parent.get_tree().get_nodes_in_group(GROUP):
			if not is_instance_valid(n) or n.is_queued_for_deletion():
				continue
			if n.item_id == p_item_id and n.global_position.distance_to(pos) <= MERGE_RADIUS:
				n.amount += p_amount
				n._refresh_visual()
				return n
	var d = load(SCRIPT_PATH).new()
	d.item_id = p_item_id
	d.amount = p_amount
	d.name = "Dropped_%s" % p_item_id
	parent.add_child(d, true)
	if d.is_inside_tree():
		d.global_position = pos
	else:
		d.position = pos
	return d

## Выбрасывает amount предметов из рюкзака игрока на землю перед ним.
## Возвращает кучку или null (нельзя выбросить: инструмент, не хватает количества).
static func drop_from_player(player: Node, p_item_id: String, p_amount: int) -> Node:
	if player == null or not ("inventory" in player) or player.inventory == null:
		return null
	var inv = player.inventory
	if not inv.drop_item(p_item_id, p_amount):
		return null
	var fwd: Vector3 = Vector3.FORWARD
	var facing: Node3D = player.get_node_or_null("Visuals") as Node3D
	if facing == null and player is Node3D:
		facing = player
	if facing and facing.is_inside_tree():
		fwd = -facing.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var origin: Vector3 = player.global_position if player is Node3D and player.is_inside_tree() else Vector3.ZERO
	var pos: Vector3 = origin + fwd * DROP_DISTANCE + Vector3(randf_range(-0.2, 0.2), 0.05, randf_range(-0.2, 0.2))
	var node: Node = spawn(player.get_parent(), p_item_id, p_amount, pos)
	if node == null:
		# Некуда положить — возвращаем в рюкзак, чтобы ничего не потерять.
		inv.items[p_item_id] = int(inv.items.get(p_item_id, 0)) + p_amount
		inv.inventory_updated.emit()
		return null
	if player.has_method("notify"):
		player.notify("🫳 Выброшено: %s %s ×%d (%.1f кг)" % [
			ItemDB.get_item_icon(p_item_id), ItemDB.get_item_name(p_item_id), p_amount,
			float(ItemDB.get_item(p_item_id).get("weight", 1.0)) * p_amount
		])
	return node

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	object_name = ItemDB.get_item_name(item_id)
	prompt_action = "Подобрать"
	_build()
	_refresh_visual()

func _build() -> void:
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	cs.shape = sphere
	cs.position = Vector3(0, 0.3, 0)
	add_child(cs)
	
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ItemIcons.get_color(item_id)
	mat.roughness = 0.8
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0, 0.18, 0)
	_visual.add_child(mesh_inst)
	
	var sprite := Sprite3D.new()
	sprite.texture = ItemIcons.get_texture(item_id)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.01
	sprite.position = Vector3(0, 0.75, 0)
	add_child(sprite)
	
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.005
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.9, 0.45)
	_label.position = Vector3(0, 1.12, 0)
	add_child(_label)

func _refresh_visual() -> void:
	if _label:
		_label.text = "×%d" % amount

func _process(delta: float) -> void:
	_time += delta
	if _visual:
		_visual.rotation.y += delta * 1.2
		_visual.position.y = 0.05 + sin(_time * 2.0) * 0.04

func get_prompt() -> String:
	return "[E] Подобрать: %s %s ×%d (%.1f кг)" % [
		ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), amount,
		float(ItemDB.get_item(item_id).get("weight", 1.0)) * amount
	]

func _on_interacted(player: Node) -> void:
	if player == null or not ("inventory" in player) or player.inventory == null:
		return
	var inv = player.inventory
	var fit: int = inv.get_max_addable(item_id, amount)
	if fit <= 0:
		if player.has_method("notify"):
			player.notify("⚠️ В рюкзаке нет места для «%s»" % ItemDB.get_item_name(item_id))
		return
	if not inv.add_item(item_id, fit):
		return
	amount -= fit
	AudioManager.play("pickup")
	if player.has_method("notify"):
		var tail: String = "" if amount <= 0 else " (на земле осталось %d)" % amount
		player.notify("🎒 Подобрано: %s %s +%d%s" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), fit, tail])
	if amount <= 0:
		consume()
	else:
		_refresh_visual()

## Убирает кучку из мира (сразу выходит из группы, чтобы не попасть в сейв).
func consume() -> void:
	is_interactable = false
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	queue_free()
