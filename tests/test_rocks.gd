extends SceneTree
## Камни по референсу: 1 большой валун (добывается киркой) + 3 малых декоративных,
## раскиданы по карте. Проверяет модели, коллизии, размещение и добычу.
const RockScene = preload("res://scenes/resources/rock_node.tscn")
const SMALL := ["res://scenes/props/rock_small_slab.tscn", "res://scenes/props/rock_small_spire.tscn", "res://scenes/props/rock_small_pebble.tscn"]
var errors: Array[String] = []
var world: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	# 1. Модели
	var rock: Node = RockScene.instantiate()
	var boulder := rock.get_node_or_null("Visual/Boulder") as MeshInstance3D
	check(boulder != null and boulder.mesh != null, "У RockNode нет меша валуна Visual/Boulder")
	if boulder:
		var sz: Vector3 = boulder.mesh.get_aabb().size
		check(sz.y > 1.2 and sz.x > 2.0, "Валун слишком мал: %s" % sz)
		var mat := boulder.mesh.surface_get_material(0) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null and mat.uv1_triplanar, "Материал камня без triplanar-текстуры")
	check(rock.required_tool == "pickaxe" and rock.resource_id == "stone", "Валун должен добываться киркой и давать камень")
	check(rock.get_node_or_null("SolidBody/SolidShape").shape is ConvexPolygonShape3D, "Коллизия валуна не по форме")
	rock.free()
	for p in SMALL:
		var r: Node = load(p).instantiate()
		check(r is StaticBody3D, "%s: корень не StaticBody3D" % p)
		var mi := r.get_node_or_null("Mesh") as MeshInstance3D
		check(mi != null and mi.mesh.get_aabb().size.y < 1.3, "%s: нет меша или он слишком большой" % p)
		var shapes := r.find_children("*", "CollisionShape3D", false, false)
		check(shapes.size() > 0, "%s: нет коллизии" % p)
		check(not r.has_method("_on_interacted"), "%s: малый камень не должен добываться" % p)
		r.free()
	# 2. Размещение на карте
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames > 3:
		return _finish()
	var big := world.get_node("Resources").get_children().filter(func(n): return n.scene_file_path == RockScene.resource_path)
	var small := world.get_node("Props/Rocks").get_children()
	check(big.size() >= 8, "На карте мало больших валунов: %d" % big.size())
	check(small.size() >= 30, "На карте мало малых камней: %d" % small.size())
	var kinds := {}
	for n in small:
		kinds[n.scene_file_path] = true
	check(kinds.size() == 3, "Использованы не все 3 вида малых камней")
	var all: Array = big + small
	var far := 0
	for i in all.size():
		var a: Vector3 = all[i].global_position
		if Vector2(a.x, a.z).length() > 15.0:
			far += 1
		for j in range(i + 1, all.size()):
			var b: Vector3 = all[j].global_position
			check(Vector2(a.x - b.x, a.z - b.z).length() > 1.2, "Камни %s и %s слиплись" % [all[i].name, all[j].name])
	check(far >= 20, "Камни не раскиданы по карте (далеко от базы только %d)" % far)
	# 3. Добыча киркой: валун истощается, твёрдое тело отключается
	var player = world.get_node("Player")
	var rock = big[big.size() - 1]
	player.inventory.equip_tool("pickaxe")
	var before: int = player.inventory.get_item_count("stone") if player.inventory.has_method("get_item_count") else 0
	for k in rock.max_hits:
		rock._on_interacted(player)
	check(rock.is_depleted, "Валун не истощился после %d ударов киркой" % rock.max_hits)
	if player.inventory.has_method("get_item_count"):
		check(player.inventory.get_item_count("stone") > before, "Камень не добавился в инвентарь")
	return false

func _finish() -> bool:
	if frames < 6:
		return false
	var big := world.get_node("Resources").get_children().filter(func(n): return n.scene_file_path == RockScene.resource_path)
	var rock = big[big.size() - 1]
	var small := world.get_node("Props/Rocks").get_children()
	check((rock.get_node("SolidBody/SolidShape") as CollisionShape3D).disabled, "Коллизия валуна не отключилась после истощения")
	if errors.is_empty():
		print("ТЕСТ ПРОЙДЕН: камни — %d валунов, %d малых, добыча киркой работает" % [big.size(), small.size()])
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("ТЕСТ ПРОВАЛЕН")
		quit(1)
	return true
