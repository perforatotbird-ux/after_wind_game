extends SceneTree
## Жилы из разрушаемых вокселей: текстуры, генерация 1–3 ресурсов, дыра в земле,
## копание лопатой/киркой, прицел, шаг на уступ, сохранение и предметы.
const VoxelDeposit = preload("res://scripts/world/voxel_deposit.gd")
const VoxelTextures = preload("res://scripts/world/voxel_textures.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const SAVE_PATH := "user://test_voxel_deposits.json"
const M = VoxelDeposit.Mat

var errors: Array[String] = []
var world: Node
var player: Node
var frames := 0
var step := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	# 1. Текстуры: атлас из 8 тайлов с рамкой, тайлы различимы по цвету.
	var atlas: Image = VoxelTextures.get_atlas_image()
	check(atlas.get_width() == VoxelTextures.CELL * VoxelTextures.TILE_COUNT and atlas.get_height() == VoxelTextures.CELL, "Неверный размер атласа")
	var avgs: Array[Color] = []
	for t in VoxelTextures.TILE_COUNT:
		var img: Image = VoxelTextures.get_tile_image(t)
		var sum := Color(0, 0, 0, 0)
		for y in img.get_height():
			for x in img.get_width():
				sum += img.get_pixel(x, y)
		avgs.append(sum / float(img.get_width() * img.get_height()))
	for i in avgs.size():
		for j in range(i + 1, avgs.size()):
			if i == 1 and j == 2:
				continue # бок дёрна — это грунт с полосой травы
			var d: float = Vector3(avgs[i].r - avgs[j].r, avgs[i].g - avgs[j].g, avgs[i].b - avgs[j].b).length()
			check(d > 0.04, "Тайлы %s и %s слишком похожи" % [VoxelTextures.TILE_NAMES[i], VoxelTextures.TILE_NAMES[j]])
	var grass: Color = avgs[VoxelTextures.Tile.GRASS_TOP]
	check(absf(grass.r - 0.26) < 0.05 and absf(grass.g - 0.35) < 0.05, "Трава жилы не совпадает с цветом земли: %s" % grass)
	check(VoxelTextures.get_material().albedo_texture != null, "Нет материала вокселей")
	# 2. Предметы и рецепты
	for id in ["coal", "iron_ore"]:
		check(not ItemDB.get_item(id).is_empty(), "Нет предмета " + id)
		check(ItemIcons.STYLES.has(id), "Нет иконки " + id)
	var smelt: Dictionary = RecipeDB.get_recipe("smelt_iron_ore")
	check(smelt.get("inputs", {}).get("iron_ore", 0) == 2 and smelt.get("outputs", {}).has("iron_ingot"), "Нет плавки руды")
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	player = world.get_node("Player")

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if step == 0:
		step = 1
		_check_world()
		_check_digging()
		_check_aim()
		_prepare_step_pit()
		return false
	if step < 40:
		step += 1 # персонаж приземляется в яму
		return false
	_check_step_up()
	_check_save()
	return _finish()

func _deposits() -> Array:
	return get_nodes_in_group(VoxelDeposit.GROUP)

func _check_world() -> void:
	var deps: Array = _deposits()
	check(deps.size() == 3, "На карте должно быть 3 жилы, найдено %d" % deps.size())
	var mats := {"sand": M.SAND, "clay": M.CLAY, "coal": M.COAL, "iron_ore": M.IRON_ORE}
	for d in deps:
		check(d.active_resources.size() >= 1 and d.active_resources.size() <= 3, "%s: ресурсов не 1–3" % d.name)
		for id in mats:
			var n: int = d.count_material(mats[id])
			if id in d.active_resources:
				check(n >= 6, "%s: мало блоков %s (%d)" % [d.name, id, n])
			else:
				check(n == 0, "%s: лишний ресурс %s" % [d.name, id])
		var top: int = d.depth_cells - 1
		var all_soil := true
		for z in range(1, d.size_cells - 1):
			for x in range(1, d.size_cells - 1):
				all_soil = all_soil and d.get_voxel(Vector3i(x, top, z)) == M.SOIL
				check(d.get_voxel(Vector3i(x, 0, z)) == M.BEDROCK, "%s: нет скального дна" % d.name)
		check(all_soil, "%s: верхний слой должен быть грунтом с травой" % d.name)
		check(not d.is_cell_diggable(Vector3i(0, top, 5)) and not d.is_cell_diggable(Vector3i(5, 0, 5)), "%s: стенка/дно копаются" % d.name)
		check(d.get_node("VoxelMesh").mesh.get_surface_count() == 1, "%s: нет меша" % d.name)
		check(d.get_node("TerrainBody/Shape").shape.get_faces().size() > 0, "%s: нет коллизии" % d.name)
		# Земля вырезана: луч сверху в центр жилы попадает в тело вокселей.
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var c: Vector3 = d.global_position
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0.1, 3, 0.1), c + Vector3(0.1, -10, 0.1))
		var hit: Dictionary = space.intersect_ray(q)
		check(not hit.is_empty() and hit.collider.is_in_group(VoxelDeposit.TERRAIN_GROUP) and absf(hit.position.y) < 0.01, "%s: над жилой нет верхнего слоя вокселей (дыра в земле?)" % d.name)
	var ground: Node = world.get_node("Ground")
	check(ground.get_node("CollisionShape3D").disabled, "Цельная коллизия земли не заменена")
	var space2: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 3, 12), Vector3(0, -3, 12))
	var h2: Dictionary = space2.intersect_ray(q2)
	check(not h2.is_empty() and h2.collider == ground, "Земля вне жил пропала")

func _find(d: Node, mat: int) -> Vector3i:
	for y in range(d.depth_cells - 1, 0, -1):
		for z in range(1, d.size_cells - 1):
			for x in range(1, d.size_cells - 1):
				if d.get_voxel(Vector3i(x, y, z)) == mat:
					return Vector3i(x, y, z)
	return VoxelDeposit.NO_CELL

func _deposit_with(id: String) -> Node:
	for d in _deposits():
		if id in d.active_resources:
			return d
	return null

func _check_digging() -> void:
	var inv = player.inventory
	inv.equipped_tool = "shovel"
	var near: Node = world.get_node("Deposits/NearDeposit")
	var soil := Vector3i(5, near.depth_cells - 1, 5)
	var faces_before: int = near.get_node("TerrainBody/Shape").shape.get_faces().size()
	near.dig_cell(soil, player)
	check(near.get_voxel(soil) == M.AIR, "Грунт не выкопан лопатой за 1 удар")
	check(near.get_node("TerrainBody/Shape").shape.get_faces().size() > faces_before, "Коллизия не перестроена после копания")
	# Песок — лопатой за удар, +2.
	var sand_dep: Node = _deposit_with("sand")
	var sand: Vector3i = _find(sand_dep, M.SAND)
	var before: int = inv.get_item_count("sand")
	sand_dep.dig_cell(sand, player)
	check(sand_dep.get_voxel(sand) == M.AIR and inv.get_item_count("sand") == before + 2, "Песок: блок не выкопан или не +2")
	check("sand" in sand_dep.discovered, "Песок не отмечен найденным")
	# Глина — два удара.
	var clay_dep: Node = _deposit_with("clay")
	var clay: Vector3i = _find(clay_dep, M.CLAY)
	clay_dep.dig_cell(clay, player)
	check(clay_dep.get_voxel(clay) == M.CLAY and clay_dep.current_hits == 1, "Глина должна выдержать первый удар (осталось 1)")
	clay_dep.dig_cell(clay, player)
	check(clay_dep.get_voxel(clay) == M.AIR and inv.get_item_count("clay") >= 2, "Глина не выкопана за 2 удара")
	# Уголь — лопатой нельзя, киркой 3 удара.
	var coal_dep: Node = _deposit_with("coal")
	var coal: Vector3i = _find(coal_dep, M.COAL)
	coal_dep.dig_cell(coal, player)
	check(coal_dep.get_voxel(coal) == M.COAL and not coal_dep.damage.has(coal), "Уголь копается лопатой")
	inv.equipped_tool = "pickaxe"
	for i in 3:
		coal_dep.dig_cell(coal, player)
	check(coal_dep.get_voxel(coal) == M.AIR and inv.get_item_count("coal") >= 2, "Уголь не добыт киркой за 3 удара")
	var iron_dep: Node = _deposit_with("iron_ore")
	var iron: Vector3i = _find(iron_dep, M.IRON_ORE)
	for i in 3:
		iron_dep.dig_cell(iron, player)
	check(iron_dep.get_voxel(iron) == M.IRON_ORE, "Руда выкопана быстрее 4 ударов")
	iron_dep.dig_cell(iron, player)
	var ore: int = inv.get_item_count("iron_ore")
	check(iron_dep.get_voxel(iron) == M.AIR and ore >= 1 and ore <= 3, "Руда не добыта (%d)" % ore)
	# Скальное дно и стенку не выкопать.
	var bed := Vector3i(5, 0, 5)
	iron_dep.dig_cell(bed, player)
	check(iron_dep.get_voxel(bed) == M.BEDROCK, "Скальное основание выкопано")
	var wall := Vector3i(0, iron_dep.depth_cells - 1, 4)
	iron_dep.dig_cell(wall, player)
	check(iron_dep.get_voxel(wall) == M.SOIL, "Стенка участка выкопана")

func _check_aim() -> void:
	var d: Node = world.get_node("Deposits/WestDeposit")
	# Луч сверху вниз — первый твёрдый блок столбца.
	var col := Vector3i(7, 0, 7)
	var hit: Vector3i = d._raycast_cell(Vector3(7.5, d.depth_cells + 3.0, 7.5), Vector3.DOWN)
	check(hit == Vector3i(7, d.depth_cells - 1, 7), "Луч не нашёл верхний блок: %s" % hit)
	d.voxels[d._index(Vector3i(7, d.depth_cells - 1, 7))] = M.AIR
	hit = d._raycast_cell(Vector3(7.5, d.depth_cells + 3.0, 7.5), Vector3(0.0, -1.0, 0.001).normalized())
	check(hit == Vector3i(7, d.depth_cells - 2, 7), "Луч не прошёл в яму: %s" % hit)
	d.voxels[d._index(Vector3i(7, d.depth_cells - 1, 7))] = M.SOIL
	# Без мыши — блок перед персонажем на уровне земли.
	player.global_position = d.cell_center_global(Vector3i(6, d.depth_cells - 1, 8)) + Vector3(0, 0.25, 0)
	player.visual_root.rotation.y = atan2(-1.0, 0.0) # лицом к +X
	check(d.update_aim(player), "Нет блока под прицелом рядом с персонажем")
	check(d.get_target_cell() == Vector3i(7, d.depth_cells - 1, 8), "Прицел не на блоке перед персонажем: %s" % d.get_target_cell())
	player._on_interaction_area_entered(d) # детектор сработал бы на следующем кадре физики
	player._update_best_interactable()
	check(player.current_interactable == d, "Жила не выбрана объектом взаимодействия")
	check(player._is_mining_resource(d), "Жила не считается добычей (замах)")
	check(d.get_prompt().contains("Грунт"), "Подсказка не про грунт: " + d.get_prompt())
	# Полный цикл удара через персонажа.
	player.inventory.equipped_tool = "shovel"
	var target: Vector3i = d.get_target_cell()
	player.trigger_tool_strike()
	for i in 60:
		if not player.is_mining:
			break
		player._update_strike(0.05)
	check(d.get_voxel(target) == M.AIR, "Удар персонажа не выкопал блок")
	# Далёкий блок вне досягаемости.
	d.set_target_cell(Vector3i(14, 2, 14), player)
	check(not d.is_in_reach(player), "Далёкий блок считается досягаемым")

var pit_dep: Node
var pit_cell := Vector3i(6, 0, 6)

func _prepare_step_pit() -> void:
	# Яма 3×3 глубиной 1 блок; с одной стороны — уступ в 2 блока.
	pit_dep = world.get_node("Deposits/EastDeposit")
	var top: int = pit_dep.depth_cells - 1
	for z in range(5, 8):
		for x in range(5, 8):
			pit_dep.voxels[pit_dep._index(Vector3i(x, top, z))] = M.AIR
	for z in range(5, 8):
		pit_dep.voxels[pit_dep._index(Vector3i(4, top, z))] = M.AIR
		pit_dep.voxels[pit_dep._index(Vector3i(4, top - 1, z))] = M.AIR
		pit_dep.voxels[pit_dep._index(Vector3i(3, top - 1, z))] = M.SOIL
	pit_dep.rebuild()
	pit_cell = Vector3i(6, top - 1, 6)
	player.velocity = Vector3.ZERO
	player.global_position = pit_dep.cell_center_global(pit_cell) + Vector3(0.0, 0.3, 0.0)

func _check_step_up() -> void:
	var floor_y: float = pit_dep.cell_center_global(pit_cell).y + 0.25
	check(player.is_on_floor() and absf(player.global_position.y - floor_y) < 0.08, "Персонаж не стоит на дне ямы: y=%.2f" % player.global_position.y)
	# Уступ в 1 блок (+X): персонаж поднимается.
	var x_wall: float = pit_dep.cell_to_local(Vector3i(8, 0, 0)).x + pit_dep.global_position.x
	player.global_position.x = x_wall - 0.37
	player.velocity = Vector3(3.0, 0.0, 0.0)
	var y0: float = player.global_position.y
	check(player._try_step_up(0.1), "Нет шага на уступ в 1 блок")
	check(player.global_position.y > y0 + 0.5, "Шаг не поднял персонажа")
	# Стенка в 2 блока (-X): шага нет.
	player.global_position = pit_dep.cell_center_global(Vector3i(4, pit_cell.y - 1, 6)) + Vector3(0.0, 0.25, 0.0)
	var x_wall2: float = pit_dep.cell_to_local(Vector3i(4, 0, 0)).x + pit_dep.global_position.x
	player.global_position.x = x_wall2 + 0.37
	player.move_and_slide()
	player.velocity = Vector3(-3.0, 0.0, 0.0)
	check(not player._try_step_up(0.1), "Шаг сквозь стенку в 2 блока")

func _check_save() -> void:
	var d: Node = world.get_node("Deposits/NearDeposit")
	var state: Dictionary = d.get_save_state()
	check(VoxelDeposit.is_valid_save_state(state), "Состояние жилы не проходит проверку")
	var bad: Dictionary = state.duplicate()
	bad["voxels"] = [1, 5, 9, 3]
	check(not VoxelDeposit.is_valid_save_state(bad), "Битые воксели принимаются")
	var bad2: Dictionary = state.duplicate()
	bad2["discovered"] = ["gold"]
	check(not VoxelDeposit.is_valid_save_state(bad2), "Неизвестный ресурс принимается")
	var bad3: Dictionary = state.duplicate()
	bad3["size"] = int(state["size"]) + 1
	check(not VoxelDeposit.is_valid_save_state(bad3), "Неверная длина вокселей принимается")
	check(VoxelDeposit.decode_voxels(state) == d.voxels, "RLE не восстанавливает воксели")
	var dug := Vector3i(5, d.depth_cells - 1, 5)
	check(d.get_voxel(dug) == M.AIR, "Нет выкопанного блока для проверки сохранения")
	player.global_position = Vector3(0, 0.2, 0)
	check(SaveManager.save_game(world, SAVE_PATH), "Сохранение не удалось")
	d.generate()
	d.rebuild()
	check(d.get_voxel(dug) == M.SOIL, "generate() не восстановил блок")
	check(SaveManager.load_game(world, SAVE_PATH), "Загрузка не удалась")
	check(d.get_voxel(dug) == M.AIR, "Выкопанный блок не восстановлен из сохранения")
	var text: String = FileAccess.get_file_as_string(SAVE_PATH)
	var data: Dictionary = JSON.parse_string(text)
	data["deposits"][0]["voxels"] = "@@@"
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	check(not SaveManager.load_game(world, SAVE_PATH), "Битая секция deposits принята")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_voxel_deposits — жилы, копание, прицел, уступы, сохранение")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
