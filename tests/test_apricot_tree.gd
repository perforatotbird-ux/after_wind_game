extends SceneTree

## Комплексный тест абрикосового дерева, моделей, сбора урожая, рецептов и предметов.

const FruitTreeScript = preload("res://scripts/resources/fruit_tree.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")

class MockPlayer extends Node:
	var inventory: Node
	var energy: float = 100.0
	var messages: Array[String] = []

	func notify(t: String) -> void:
		messages.append(t)

	func consume_energy(amount: float) -> bool:
		energy = maxf(0.0, energy - amount)
		return true

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	Seasons.current_season = ""
	_test_items_and_icons()
	_test_recipes()
	_test_contract_reward()
	_test_tree_scene_and_visuals()
	_test_tree_growth_harvest_and_chop()
	_test_save_validation()

	if errors.is_empty():
		print("PASS: test_apricot_tree — абрикосовое дерево, сбор, рецепты и предметы проверены успешно")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)

func _test_items_and_icons() -> void:
	var expected_items: Array[String] = [
		"apricot", "apricot_sapling", "dried_apricot", "apricot_compote", "apricot_pie"
	]
	var inv: Node = preload("res://scripts/inventory/inventory.gd").new()
	for item_id in expected_items:
		var d: Dictionary = ItemDB.get_item(item_id)
		check(not d.is_empty(), "Предмет %s не найден в ItemDB" % item_id)
		check(inv.items.has(item_id), "Предмета %s нет в Inventory.items" % item_id)
		check(ItemIcons.STYLES.has(item_id), "Иконка для %s отсутствует в ItemIcons.STYLES" % item_id)

	# Проверка саженца
	check(ItemDB.is_fruit_sapling("apricot_sapling"), "apricot_sapling не распознаётся как саженец")
	check(ItemDB.get_tree_type("apricot_sapling") == "apricot_tree", "Неверный tree_type у apricot_sapling")

	# Проверка плода и еды
	check(ItemDB.is_edible("apricot"), "apricot должен быть съедобным")
	check(ItemDB.get_hunger_recovery("apricot") > 0.0, "apricot не восстанавливает сытость")
	check(ItemDB.get_thirst_recovery("apricot") > 0.0, "apricot не восстанавливает жажду")
	check(ItemDB.is_edible("dried_apricot"), "dried_apricot должен быть съедобным")
	check(ItemDB.is_edible("apricot_compote"), "apricot_compote должен быть съедобным")
	check(ItemDB.is_edible("apricot_pie"), "apricot_pie должен быть съедобным")
	check(ItemDB.get_hunger_recovery("apricot_pie") >= 60.0, "apricot_pie должен быть сытным (>=60%)")
	inv.free()

func _test_recipes() -> void:
	# 1. Прививка на верстаке
	var sapling_rec: Dictionary = RecipeDB.get_recipe("craft_apricot_sapling")
	check(not sapling_rec.is_empty(), "Рецепт craft_apricot_sapling не найден")
	check(sapling_rec.get("machine", "") == "workbench", "craft_apricot_sapling должен быть на верстаке")
	check(sapling_rec["inputs"].get("apricot", 0) == 2, "craft_apricot_sapling требует 2 абрикоса")
	check(sapling_rec["inputs"].get("wood", 0) == 1, "craft_apricot_sapling требует 1 дерево")
	check(sapling_rec["outputs"].get("apricot_sapling", 0) == 1, "craft_apricot_sapling даёт 1 саженец")

	# 2. Сушка в печи
	var dry_rec: Dictionary = RecipeDB.get_recipe("dry_apricots")
	check(not dry_rec.is_empty(), "Рецепт dry_apricots не найден")
	check(dry_rec.get("machine", "") == "furnace", "dry_apricots должен быть в печи")
	check(dry_rec["inputs"].get("apricot", 0) == 3, "dry_apricots требует 3 абрикоса")
	check(dry_rec["outputs"].get("dried_apricot", 0) == 2, "dry_apricots даёт 2 кураги")

	# 3. Компот в печи
	var compote_rec: Dictionary = RecipeDB.get_recipe("cook_apricot_compote")
	check(not compote_rec.is_empty(), "Рецепт cook_apricot_compote не найден")
	check(compote_rec.get("machine", "") == "furnace", "cook_apricot_compote должен быть в печи")
	check(compote_rec["inputs"].get("apricot", 0) == 3, "cook_apricot_compote требует 3 абрикоса")
	check(compote_rec["outputs"].get("apricot_compote", 0) == 2, "cook_apricot_compote даёт 2 компота")

	# 4. Пирог в печи
	var pie_rec: Dictionary = RecipeDB.get_recipe("cook_apricot_pie")
	check(not pie_rec.is_empty(), "Рецепт cook_apricot_pie не найден")
	check(pie_rec.get("machine", "") == "furnace", "cook_apricot_pie должен быть в печи")
	check(pie_rec["inputs"].get("apricot", 0) == 3, "cook_apricot_pie требует 3 абрикоса")
	check(pie_rec["outputs"].get("apricot_pie", 0) == 2, "cook_apricot_pie даёт 2 пирога")

func _test_contract_reward() -> void:
	var marta: Dictionary = {}
	for c in ContractDB.CONTRACTS:
		if c.get("id", "") == "contract_marta_orchard":
			marta = c
			break
	check(not marta.is_empty(), "Контракт contract_marta_orchard не найден")
	var rewards: Dictionary = marta.get("reward_items", {})
	check(rewards.get("apricot_sapling", 0) == 1, "Контракт Марты должен выдавать 1 apricot_sapling")

func _test_tree_scene_and_visuals() -> void:
	var scene: PackedScene = load("res://scenes/resources/tree_apricot.tscn")
	check(scene != null, "Не удалось загрузить сцену res://scenes/resources/tree_apricot.tscn")
	var tree: Node = scene.instantiate()
	root.add_child(tree)
	tree.set_process(false)

	check(tree.tree_type == "apricot_tree", "tree_type сцены должен быть apricot_tree")
	check(tree.object_name == "Абрикос", "object_name сцены должен быть Абрикос")
	check(tree._trunk_mesh != null, "У дерева должен быть ствол Trunk")
	check(tree._fruits_node != null, "У дерева должен быть узел плодов Fruits")
	check(tree._fruits_node.has_node("Apricots"), "В узле Fruits должен быть меш Apricots")
	check(tree._fruits_node.has_node("Stems"), "В узле Fruits должен быть меш Stems")
	tree.queue_free()

func _test_tree_growth_harvest_and_chop() -> void:
	var tree: Node = FruitTreeScript.new()
	root.add_child(tree)
	tree.set_process(false)
	tree.tree_type = "apricot_tree"
	tree.stage = FruitTreeScript.Stage.SAPLING
	tree.has_fruit = false

	# Рост саженец -> молодое (24 ч) -> взрослое (48 ч)
	tree.advance_hours(23.9)
	check(tree.stage == FruitTreeScript.Stage.SAPLING, "Абрикос не должен созреть раньше 24 ч")
	tree.advance_hours(0.2)
	check(tree.stage == FruitTreeScript.Stage.YOUNG, "Абрикос должен перейти в стадию YOUNG за 24 ч")
	check(not tree.has_fruit, "Молодой абрикос не должен иметь плодов")

	tree.advance_hours(47.9)
	check(tree.stage == FruitTreeScript.Stage.YOUNG, "Абрикос не должен созреть раньше 48 ч молодой стадии")
	tree.advance_hours(0.2)
	check(tree.stage == FruitTreeScript.Stage.MATURE, "Абрикос должен перейти в стадию MATURE")
	check(tree.has_fruit and tree._fruits_node.visible, "Взрослый абрикос должен иметь видимые плоды")

	# Сбор урожая
	var player: MockPlayer = MockPlayer.new()
	player.inventory = preload("res://scripts/inventory/inventory.gd").new()
	player.add_child(player.inventory)
	root.add_child(player)

	var count: int = tree.harvest(player)
	check(count >= 5 and count <= 9, "Урожай абрикосов должен быть в пределах 5..9, получено: %d" % count)
	check(player.inventory.get_item_count("apricot") == count, "В рюкзаке должно быть %d абрикосов" % count)
	check(not tree.has_fruit, "has_fruit должен стать false")
	check(not tree._fruits_node.visible, "Узел Fruits должен стать невидимым после сбора")

	# Сезонность отрастания: лето да, осень/зима/весна нет
	for season in ["autumn", "winter", "spring"]:
		Seasons.current_season = season
		tree.has_fruit = false
		tree.regrow_progress = 0.0
		tree.advance_hours(30.0)
		check(not tree.has_fruit, "Абрикосы не должны созревать в сезон %s" % season)

	Seasons.current_season = "summer"
	tree.has_fruit = false
	tree.regrow_progress = 0.0
	tree.advance_hours(24.0)
	check(tree.has_fruit and tree._fruits_node.visible, "Абрикосы должны вырасти летом за 24 ч")
	Seasons.current_season = ""

	# Рубка
	var wood_before: int = player.inventory.get_item_count("wood")
	var sap_before: int = player.inventory.get_item_count("apricot_sapling")
	for i in range(7):
		check(not tree.chop(player), "Дерево не должно упасть раньше 8 ударов")
	check(tree.chop(player), "Дерево должно упасть на 8-й удар")
	check(tree.is_queued_for_deletion(), "Срубленное дерево должно удаляться из сцены")
	check(player.inventory.get_item_count("wood") - wood_before == 4, "За рубку должно быть начислено 4 древесины")
	check(player.inventory.get_item_count("apricot_sapling") - sap_before == 1, "При рубке должен вернуться 1 саженец apricot_sapling")

	player.queue_free()

func _test_save_validation() -> void:
	var valid_data: Dictionary = {
		"meta": {"format_version": 2},
		"player": {"health": 100.0, "energy": 100.0, "thirst": 100.0, "hunger": 100.0, "pos": [0,0,0], "rot": 0},
		"fruit_trees": [
			{
				"type": "apricot_tree",
				"stage": 2,
				"growth": 0.0,
				"has_fruit": true,
				"regrow": 0.0,
				"hits": 8,
				"pos": [10.5, 0.0, -15.2]
			}
		]
	}
	check(SaveManagerScript._validate_save_data(valid_data), "Сейв с apricot_tree должен проходить валидацию")
