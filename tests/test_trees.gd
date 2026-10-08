extends SceneTree
## Деревья по референсам: дуб, молодой дуб, сосна, раскидистая сосна.
## Проверяет модели, небольшой лес на карте и рубку топором (пенёк, коллизия).
const KINDS := {
	"res://scenes/resources/tree_oak.tscn": "Visual/Tree",
	"res://scenes/resources/tree_oak_young.tscn": "Visual/Tree",
	"res://scenes/resources/tree_pine.tscn": "Visual/Tree",
	"res://scenes/resources/tree_pine_wide.tscn": "Visual/Tree",
}
var errors: Array[String] = []
var world: Node
var tree: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	# 1. Модели
	for p in KINDS:
		var t: Node = load(p).instantiate()
		var mi := t.get_node_or_null(KINDS[p]) as MeshInstance3D
		check(mi != null and mi.mesh != null, "%s: нет меша дерева" % p)
		if mi:
			var sz: Vector3 = mi.mesh.get_aabb().size
			check(sz.y > 4.5 and sz.y < 9.0, "%s: странная высота %s" % [p, sz.y])
			check(mi.mesh.get_surface_count() >= 2, "%s: нужны кора и листва/хвоя" % p)
		var stump := t.get_node_or_null("DepletedVisual") as Node3D
		check(stump != null and not stump.visible, "%s: пенёк должен быть скрыт до рубки" % p)
		check(t.required_tool == "axe" and t.resource_id == "wood", "%s: дерево должно рубиться топором и давать древесину" % p)
		check(t.get_node_or_null("SolidBody/SolidShape") is CollisionShape3D, "%s: нет твёрдой коллизии ствола" % p)
		check(t.is_in_group("trees"), "%s: не в группе trees" % p)
		t.free()
	# 2. Лес на карте
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _all_trees() -> Array:
	return world.find_children("*", "", true, false).filter(func(n): return KINDS.has(n.scene_file_path))

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames > 3:
		return _finish()
	var trees := _all_trees()
	var forest := world.get_node("Resources/Forest").get_children()
	check(forest.size() >= 30, "Лес слишком маленький: %d" % forest.size())
	var kinds := {}
	for n in trees:
		kinds[n.scene_file_path] = true
	check(kinds.size() == 4, "Использованы не все 4 вида деревьев")
	check(not ResourceLoader.exists("res://scenes/resources/tree_node.tscn"), "Старое примитивное дерево не удалено")
	for i in trees.size():
		var a: Vector3 = trees[i].global_position
		for j in range(i + 1, trees.size()):
			var b: Vector3 = trees[j].global_position
			check(Vector2(a.x - b.x, a.z - b.z).length() > 2.0, "Деревья %s и %s слиплись" % [trees[i].name, trees[j].name])
	# 3. Рубка: без топора нельзя, с топором дерево падает в пенёк
	var player = world.get_node("Player")
	tree = forest[0]
	player.inventory.equip_tool("pickaxe")
	tree._on_interacted(player)
	check(tree.current_hits == tree.max_hits, "Дерево рубится без топора")
	player.inventory.equip_tool("axe")
	for k in tree.max_hits:
		tree._on_interacted(player)
	check(tree.is_depleted, "Дерево не срублено после %d ударов топором" % tree.max_hits)
	check(tree.get_node("DepletedVisual").visible, "Пенёк не появился")
	return false

func _finish() -> bool:
	if frames < 6:
		return false
	check((tree.get_node("SolidBody/SolidShape") as CollisionShape3D).disabled, "Коллизия ствола не отключилась после рубки")
	if errors.is_empty():
		print("ТЕСТ ПРОЙДЕН: деревья — %d на карте, лес %d, рубка топором работает" % [_all_trees().size(), world.get_node("Resources/Forest").get_child_count()])
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("ТЕСТ ПРОВАЛЕН")
		quit(1)
	return true
