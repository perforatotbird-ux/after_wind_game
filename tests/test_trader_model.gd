extends SceneTree
## Странствующий торговец: скелет, PBR, весовые привязки, клипы и живой диалог.
var world: Node3D
var frames := 0
var errors: Array[String] = []

func _initialize() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FAIL: " + message)

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 4: return false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var trader = world.find_child("TraderNPC", true, false)
	var player = world.get_node("Player")
	var hud = world.find_child("HUD", true, false)
	var sk := trader.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := trader.animation_player as AnimationPlayer
	check(sk != null and sk.get_bone_count() == 17, "17-костный скелет торговца")
	check(ap != null, "AnimationPlayer подключён к NPC")
	if sk == null or ap == null:
		quit(1); return true
	check(trader.get_node_or_null("Visual/Body") == null, "Старая капсула удалена")
	check(trader.get_node_or_null("Visual/HatTop") == null, "Старая шляпа удалена")
	check(trader.has_node("Cargo/Crate1") and trader.has_node("SolidBody/SolidShape"), "Груз и коллизия сохранены")
	var meshes := sk.find_children("TraderBody*", "MeshInstance3D", false, false)
	check(meshes.size() == 4, "Четыре части общего skinned-меша")
	var tris := 0
	for mi in meshes:
		check(mi.skin != null and mi.skin.get_bind_count() == 17, "Skin всех частей")
		check(mi.get_node(mi.skeleton) == sk, "Общий Skeleton3D")
		var arr: Array = mi.mesh.surface_get_arrays(0)
		tris += arr[Mesh.ARRAY_INDEX].size() / 3
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for i in arr[Mesh.ARRAY_VERTEX].size():
			var total := 0.0
			for j in 4:
				check(bones[i * 4 + j] >= 0 and bones[i * 4 + j] < 17, "Веса ссылаются на существующие кости")
				total += weights[i * 4 + j]
			check(absf(total - 1.0) < 0.002, "Нормализованные веса")
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		check(mat.albedo_texture.get_width() == 1024 and mat.normal_enabled and mat.normal_texture != null, "Цвет и нормали PBR")
	check(tris >= 20000 and tris <= 30000, "Бюджет модели 20–30 тыс. треугольников")
	for name_ in ["idle", "greet", "talk", "walk"]:
		check(ap.has_animation(name_), "Клип " + name_)
		var anim := ap.get_animation(name_)
		check(anim.loop_mode == (Animation.LOOP_LINEAR if name_ in ["idle", "walk"] else Animation.LOOP_NONE), "Цикл " + name_)
		for bone in sk.get_bone_count():
			var path := NodePath("TraderRig/Skeleton3D:" + sk.get_bone_name(bone))
			check(anim.find_track(path, Animation.TYPE_ROTATION_3D) >= 0, "Сброс костей при переходе " + name_)
	# CPU skinning: no floating idle/greet/talk, no original whole-model bobbing.
	for name_ in ["idle", "greet", "talk"]:
		ap.play(name_, 0.0); ap.seek(ap.get_animation(name_).length * 0.5, true); ap.pause(); ap.advance(0.0)
		sk.force_update_all_bone_transforms()
		var low := INF; var high := -INF
		for mi in meshes:
			var arr: Array = mi.mesh.surface_get_arrays(0)
			for i in range(0, arr[Mesh.ARRAY_VERTEX].size(), 5):
				var point := Vector3.ZERO
				for j in 4:
					var weight: float = arr[Mesh.ARRAY_WEIGHTS][i * 4 + j]
					var bi: int = arr[Mesh.ARRAY_BONES][i * 4 + j]
					var bone: int = mi.skin.get_bind_bone(bi)
					point += weight * (sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bi) * arr[Mesh.ARRAY_VERTEX][i])
				low = minf(low, point.y); high = maxf(high, point.y)
		print("POSE ", name_, " feet=", low, " height=", high)
		check(absf(low) < 0.035 and high > 1.72 and high < 1.9, "Стопы на земле и рост 1.8 м: " + name_)
	var old_y: float = trader.visual_node.position.y
	trader._process(0.8)
	check(is_equal_approx(old_y, trader.visual_node.position.y), "Модель не подпрыгивает целиком")
	# Real interaction retains seed grants, opens contracts, greets, then talks.
	trader.starter_seeds_given = false
	var inv = player.inventory
	inv.items.clear()
	trader.interact(player)
	check(hud.contract_window.visible and hud._current_active_npc == trader, "Окно контрактов открыто")
	check(ap.current_animation == "greet" and trader._dialogue_active, "Приветствие при взаимодействии")
	check(inv.get_item_count("seeds_carrot") == 3 and inv.get_item_count("seeds_potato") == 2 and inv.get_item_count("seeds_wheat") == 3, "Начальные семена сохранены")
	ap.advance(2.6)
	check(ap.current_animation == "talk", "Приветствие автоматически переходит в разговор")
	ap.advance(3.4)
	check(ap.current_animation == "talk", "Жесты продолжаются при открытом диалоге")
	hud.close_contract_window()
	check(not trader._dialogue_active and ap.current_animation == "idle", "Закрытие окна возвращает ожидание")
	trader.interact(player)
	check(inv.get_item_count("seeds_carrot") == 3, "Повторный разговор не выдаёт семена снова")
	hud.open_contract_window(world.find_child("ContractBoard", true, false))
	check(not trader._dialogue_active and ap.current_animation == "idle", "Доска заказов завершает разговор NPC")
	hud.close_contract_window()
	print("TRADER ", tris, " triangles, ", sk.get_bone_count(), " bones, 4 animations")
	if errors.is_empty(): print("PASS: test_trader_model")
	quit(0 if errors.is_empty() else 1)
	return true
