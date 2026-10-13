extends SceneTree
## Ягодные кусты: модели с ягодами и без, сбор (красный — 3, синий — 6,
## ежевика — 4, облепиха — 8 ягод), отрастание по сезонам (заглушка Seasons),
## ягоды без лечения здоровья (кроме лечебной облепихи), случайная раскладка
## в мире (не больше 2 кустов вида) и сохранение состояния.

const Seasons = preload("res://scripts/core/seasons.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")

class MockPlayer extends Node:
	var inventory: Node
	var messages: Array[String] = []
	func notify(t: String) -> void:
		messages.append(t)

var errors: Array[String] = []
var world: Node
var player: Node
var frames := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	Seasons.current_season = ""
	var mock := MockPlayer.new()
	mock.inventory = InventoryScript.new()
	mock.add_child(mock.inventory)
	root.add_child(mock)
	# 1. Предметы: разные сытость/жажда/сила, здоровье не лечат.
	var red: Dictionary = ItemDB.get_item("red_berry")
	var blue: Dictionary = ItemDB.get_item("blue_berry")
	check(red.get("name") == "Красная Ягода", "Нет предмета «Красная Ягода»")
	check(not blue.is_empty() and ItemDB.is_edible("blue_berry") and ItemDB.is_edible("red_berry"), "Ягоды несъедобны")
	for k in ["hunger_recovery", "thirst_recovery", "energy_bonus"]:
		check(float(red.get(k, 0)) > 0.0 and float(blue.get(k, 0)) > 0.0, "У ягод нет " + k)
		check(not is_equal_approx(float(red.get(k, 0)), float(blue.get(k, 0))), "Одинаковое %s у ягод" % k)
	check(red.has("health_bonus") and float(red["health_bonus"]) == 0.0 and float(blue.get("health_bonus", 1)) == 0.0, "Ягоды лечат здоровье")
	check(ItemIcons.STYLES.has("red_berry") and ItemIcons.STYLES.has("blue_berry"), "Нет иконок ягод")
	var black_item: Dictionary = ItemDB.get_item("blackberry")
	var sea_item: Dictionary = ItemDB.get_item("sea_buckthorn")
	check(black_item.get("name") == "Ежевика", "Нет предмета «Ежевика»")
	check(sea_item.get("name") == "Облепиха", "Нет предмета «Облепиха»")
	check(float(black_item.get("health_bonus", 1.0)) == 0.0, "Ежевика лечит здоровье")
	check(float(sea_item.get("health_bonus", 0.0)) > 0.0, "Облепиха не лечит (должна: лечебная ягода)")
	check(ItemIcons.STYLES.has("blackberry") and ItemIcons.STYLES.has("sea_buckthorn"), "Нет иконок новых ягод")
	# 2. Кусты: модели и сбор.
	for cfg in [["red", 3, "red_berry"], ["blue", 6, "blue_berry"], ["black", 4, "blackberry"], ["sea", 8, "sea_buckthorn"]]:
		var bush: Node = load("res://scenes/resources/berry_bush_%s.tscn" % cfg[0]).instantiate()
		root.add_child(bush)
		bush.set_process(false)
		var full: Node3D = bush.get_node("FullModel")
		var empty: Node3D = bush.get_node("EmptyModel")
		check(full.has_node("Berries") and not empty.has_node("Berries"), "%s: модель без ягод содержит ягоды" % cfg[0])
		check(empty.has_node("Leaves") and empty.has_node("Branches"), "%s: у пустого куста нет листвы/веток" % cfg[0])
		check(full.visible and not empty.visible, "%s: в начале не видна модель с ягодами" % cfg[0])
		var mat: StandardMaterial3D = (full.get_node("Berries") as MeshInstance3D).material_override
		if cfg[0] == "red":
			check(mat.albedo_color.r > mat.albedo_color.b * 3.0, "Красные ягоды не красные")
		elif cfg[0] == "blue":
			check(mat.albedo_color.b > mat.albedo_color.r * 3.0, "Синие ягоды не синие")
		elif cfg[0] == "black":
			check(mat.albedo_color.r < 0.15 and mat.albedo_color.b < 0.2, "Ежевика не тёмная")
		else:
			check(mat.albedo_color.r > 0.8 and mat.albedo_color.g > 0.3 and mat.albedo_color.g < mat.albedo_color.r, "Облепиха не оранжевая")
		var before: int = mock.inventory.get_item_count(cfg[2])
		bush.interact(mock)
		check(mock.inventory.get_item_count(cfg[2]) - before == cfg[1], "%s: собрано не %d ягод" % [cfg[0], cfg[1]])
		check(not bush.has_berries and not full.visible and empty.visible, "%s: после сбора не сменилась модель" % cfg[0])
		bush.interact(mock)
		check(mock.inventory.get_item_count(cfg[2]) - before == cfg[1], "%s: с пустого куста собрались ягоды" % cfg[0])
		check(bush.is_interactable and bush.get_prompt().contains("отрастут"), "%s: нет подсказки об отрастании" % cfg[0])
		# Сезоны выключены (заглушка) — отрастает круглый год.
		bush.advance_regrow(bush.regrow_hours + 1.0)
		check(bush.has_berries and full.visible, "%s: без системы сезонов ягоды не отросли" % cfg[0])
		bush.interact(mock)
		# Сезоны включены: рост только в свои сезоны (берутся из куста).
		for season in Seasons.ALL:
			Seasons.current_season = season
			bush.set_has_berries(false)
			bush.advance_regrow(bush.regrow_hours + 1.0)
			var should: bool = season in bush.grow_seasons
			check(bush.has_berries == should, "%s: неверный рост в сезон %s" % [cfg[0], season])
			if not should:
				check(bush.get_prompt().contains("сезон"), "%s: нет подсказки о сезоне" % cfg[0])
		Seasons.current_season = ""
		bush.queue_free()
	# 3. Еда проверяется в первом кадре (у игрока @onready-инвентарь).
	player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	mock.queue_free()

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		player.set_process(false)
		player.set_physics_process(false)
		player.inventory.add_item("red_berry", 2)
		player.health = 50.0
		player.hunger = 40.0
		player.eat_food("red_berry")
		check(is_equal_approx(player.health, 50.0), "Ягода вылечила здоровье")
		check(player.hunger > 40.0, "Ягода не утолила голод")
		player.queue_free()
		# 4. Мир.
		world = load("res://scenes/world/world.tscn").instantiate()
		root.add_child(world)
		return false
	var spawner: Node = world.get_node("BerryBushes")
	if spawner.get_bushes().is_empty() and frames < 30:
		return false
	var bushes: Array = spawner.get_bushes()
	var by_type := {"red": 0, "blue": 0, "black": 0, "sea": 0}
	var decor: Node = world.get_node("Meadow")
	for b in bushes:
		by_type[b.bush_type] += 1
		var p := Vector2(b.global_position.x, b.global_position.z)
		check(not (decor.get_mask_at(p) & MeadowDecor.NO_PROPS), "%s стоит на занятом месте" % b.name)
		for o in bushes:
			if o != b:
				check(Vector2(o.global_position.x, o.global_position.z).distance_to(p) >= 4.9, "Кусты слишком близко")
	check(by_type["red"] == 2 and by_type["blue"] == 2 and by_type["black"] == 2 and by_type["sea"] == 2, "В мире не 2+2+2+2 ягодных куста: %s" % by_type)
	# Сохранение: зерно и урожай восстанавливаются.
	var first: Node = bushes[0]
	var pos: Vector3 = first.global_position
	first.set_has_berries(false)
	first.regrow_progress = 5.0
	var state: Dictionary = JSON.parse_string(JSON.stringify(spawner.get_save_state()))
	spawner.spawn(spawner.current_seed + 17)
	spawner.apply_save_state(state)
	var restored: Array = spawner.get_bushes()
	check(restored.size() == 8, "После загрузки не 8 кустов")
	if restored.size() == 8:
		check(restored[0].global_position.distance_to(pos) < 0.01, "После загрузки куст на другом месте")
		check(not restored[0].has_berries and is_equal_approx(restored[0].regrow_progress, 5.0), "Не восстановлен урожай куста")
		check(restored[1].has_berries, "Лишний пустой куст после загрузки")
	if errors.is_empty():
		print("PASS: test_berry_bushes — кусты, сбор 3/6/4/8 ягод, сезоны, еда (облепиха лечит), раскладка 2×4, сохранение")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
