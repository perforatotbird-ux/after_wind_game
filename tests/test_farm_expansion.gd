extends SceneTree
## Расширение фермы (раздел 8 мастер-плана): 9 новых культур делянок
## (предметы, семена, crop_db, рецепты, процедурный визуал), фруктовые деревья
## (рост, урожай, сезоны, рубка, сохранения) и посылки с семенами от Марты.

const CropDB = preload("res://scripts/farming/crop_db.gd")
const FarmMeshes = preload("res://scripts/farming/farm_field_meshes.gd")
const FruitTreeScript = preload("res://scripts/resources/fruit_tree.gd")
const FruitPlacerScript = preload("res://scripts/farming/fruit_tree_placer.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const Seasons = preload("res://scripts/core/seasons.gd")

class MockPlayer extends Node:
	var inventory: Node
	var messages: Array[String] = []
	func notify(t: String) -> void:
		messages.append(t)

var errors: Array[String] = []
var frames: int = 0
var mock: MockPlayer

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	Seasons.current_season = ""
	ContractDB.reset_completed()
	mock = MockPlayer.new()
	mock.inventory = InventoryScript.new()
	mock.add_child(mock.inventory)
	root.add_child(mock)
	_test_crops_db()
	_test_items_and_icons()
	_test_recipes()
	_test_meshes()
	_test_placer_setup()
	_test_old_plots_guard()
	_test_seed_contracts()
	_test_fruit_save_validation()

func _finish() -> void:
	mock.queue_free()
	ContractDB.reset_completed()
	Seasons.current_season = ""
	if errors.is_empty():
		print("PASS: test_farm_expansion — 9 культур, деревья, посылки Марты, сохранения")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)

func _process(_d: float) -> bool:
	frames += 1
	# Деревья трогают global_position — только в кадрах, когда узлы в дереве
	# (в _initialize root ещё не раздаёт inside_tree).
	if frames == 1:
		_test_fruit_trees()
		return false
	_finish()
	return true

# --- 1. Культуры в crop_db (числа из разделов 3.3/8.1 мастер-плана) ---
func _test_crops_db() -> void:
	var expected: Dictionary = {
		"sunflower": {"growth": 20.0, "yield": [2, 4], "seasons": ["summer"], "product": "sunflower_seeds"},
		"onion": {"growth": 14.0, "yield": [3, 5], "seasons": ["spring", "summer", "autumn"], "product": "onion"},
		"cabbage": {"growth": 26.0, "yield": [1, 2], "seasons": ["summer", "autumn"], "product": "cabbage"},
		"tomato": {"growth": 18.0, "yield": [3, 6], "seasons": ["summer"], "product": "tomato"},
		"pepper": {"growth": 22.0, "yield": [2, 4], "seasons": ["summer"], "product": "pepper"},
		"bean": {"growth": 12.0, "yield": [4, 8], "seasons": ["spring", "summer"], "product": "bean"},
		"herbs": {"growth": 8.0, "yield": [3, 6], "seasons": ["spring", "summer", "autumn"], "product": "herbs"},
		"corn": {"growth": 24.0, "yield": [2, 4], "seasons": ["summer"], "product": "corn"},
		"pumpkin": {"growth": 30.0, "yield": [1, 2], "seasons": ["summer", "autumn"], "product": "pumpkin"},
	}
	for crop in expected:
		check(CropDB.has_crop(crop), "Нет культуры %s в CropDB" % crop)
		var d: Dictionary = CropDB.get_crop(crop)
		var e: Dictionary = expected[crop]
		check(is_equal_approx(float(d["growth_hours"]), float(e["growth"])), "%s: рост %s, а не %s ч" % [crop, d["growth_hours"], e["growth"]])
		check(str(d.get("product", crop)) == str(e["product"]), "%s: продукт %s, а не %s" % [crop, d.get("product", crop), e["product"]])
		check(Array(d["yield"]) == Array(e["yield"]), "%s: урожай %s, а не %s" % [crop, d["yield"], e["yield"]])
		check(Array(d["seasons"]) == Array(e["seasons"]), "%s: сезоны %s, а не %s" % [crop, d["seasons"], e["seasons"]])
		check(float(d["moist_min"]) < float(d["moist_max"]), "%s: пустой диапазон влаги" % crop)
		check(Array(d["seeds_back"])[0] >= 1, "%s: нет возврата семян" % crop)
		check(float(d["soil_drain"]) > 0.0, "%s: нет истощения почвы" % crop)
		check(CropDB.crop_for_seed(str(d["seed"])) == crop, "%s: crop_for_seed не находит культуру" % crop)
		check(not ItemDB.get_item(str(d["seed"])).is_empty(), "%s: нет предмета семян %s" % [crop, d["seed"]])
		check(not ItemDB.get_item(str(e["product"])).is_empty(), "%s: нет предмета урожая %s" % [crop, e["product"]])
	for s in CropDB.all_seeds():
		check(not ItemDB.get_item(s).is_empty(), "Семена %s без предмета" % s)
	check(CropDB.all_seeds().size() >= 12, "В all_seeds меньше 12 (3 базовых + 9 новых)")
	# Старые культуры не сломаны: продукт совпадает с id.
	for old in ["carrot", "potato", "wheat"]:
		check(CropDB.get_crop_product(old) == old, "Продукт %s изменился" % old)

# --- 2. Предметы, иконки, слоты инвентаря ---
func _test_items_and_icons() -> void:
	var probe: Node = InventoryScript.new()
	for item_id in ["seeds_sunflower", "seeds_onion", "seeds_cabbage", "seeds_tomato",
			"seeds_pepper", "seeds_bean", "seeds_herbs", "seeds_corn", "seeds_pumpkin",
			"apple_sapling", "pear_sapling", "cherry_sapling",
			"sunflower_seeds", "onion", "cabbage", "tomato", "pepper", "bean",
			"herbs", "corn", "pumpkin", "apple", "pear", "cherry",
			"blackberry", "sea_buckthorn"]:
		check(not ItemDB.get_item(item_id).is_empty(), "Нет предмета %s" % item_id)
		check(probe.items.has(item_id), "Предмета %s нет в Inventory.items" % item_id)
		check(ItemIcons.STYLES.has(item_id), "Нет иконки %s" % item_id)
	probe.free()
	for food_id in ["sunflower_seeds", "onion", "cabbage", "tomato", "pepper", "bean",
			"herbs", "corn", "pumpkin", "apple", "pear", "cherry"]:
		check(ItemDB.is_edible(food_id), "%s несъедобен" % food_id)
		check(float(ItemDB.get_item(food_id).get("hunger_recovery", 0.0)) > 0.0, "У %s нет сытости" % food_id)
	for s in [["apple_sapling", "apple_tree"], ["pear_sapling", "pear_tree"], ["cherry_sapling", "cherry_tree"]]:
		check(ItemDB.is_fruit_sapling(s[0]), "%s не опознан как саженец" % s[0])
		check(ItemDB.get_tree_type(s[0]) == s[1], "У %s неверный tree_type" % s[0])
	check(not ItemDB.is_fruit_sapling("seeds_carrot"), "Обычные семена опознаны как саженец")

# --- 3. Рецепты: селекция семян и прививка саженцев ---
func _test_recipes() -> void:
	var probe: Node = InventoryScript.new()
	var ids: Array[String] = []
	for r in RecipeDB.RECIPES.values():
		ids.append(str(r["id"]))
	for rid in ["extract_sunflower_seeds", "extract_onion_seeds", "extract_cabbage_seeds",
			"extract_tomato_seeds", "extract_pepper_seeds", "extract_bean_seeds",
			"extract_herbs_seeds", "extract_corn_seeds", "extract_pumpkin_seeds",
			"craft_apple_sapling", "craft_pear_sapling", "craft_cherry_sapling"]:
		check(ids.has(rid), "Нет рецепта %s" % rid)
		var r: Dictionary = RecipeDB.get_recipe(rid)
		check(str(r.get("machine", "")) == "workbench", "%s не на верстаке" % rid)
		for part in ["inputs", "outputs"]:
			for item_id in r[part]:
				check(not ItemDB.get_item(item_id).is_empty(), "%s: неизвестный предмет %s" % [rid, item_id])
				check(probe.items.has(item_id), "%s: предмета %s нет в Inventory.items" % [rid, item_id])
	# Прививка даёт именно саженец из плодов.
	check(RecipeDB.get_recipe("craft_apple_sapling")["outputs"].has("apple_sapling"), "Прививка яблони даёт не саженец")
	check(RecipeDB.get_recipe("craft_cherry_sapling")["inputs"].has("cherry"), "Прививка вишни не из вишен")
	probe.free()

# --- 4. Процедурный визуал культур ---
func _test_meshes() -> void:
	for crop in ["carrot", "potato", "wheat", "sunflower", "onion", "cabbage",
			"tomato", "pepper", "bean", "herbs", "corn", "pumpkin"]:
		for stage in [0, 1, 2, 3]:
			var m: ArrayMesh = FarmMeshes.crop(crop, stage)
			check(m != null and m.get_surface_count() > 0, "Нет меша %s стадия %d" % [crop, stage])
		var w: ArrayMesh = FarmMeshes.crop(crop, 3, true)
		check(w != null and w.get_surface_count() > 0, "Нет увядшего меша %s" % crop)
	# Плотность посадки: крупные — 2×2, высокие — 2×3, остальные — по умолчанию.
	check(FarmMeshes._plant_spots("cabbage").size() == 4, "У капусты не 4 точки посадки")
	check(FarmMeshes._plant_spots("pumpkin").size() == 4, "У тыквы не 4 точки посадки")
	check(FarmMeshes._plant_spots("corn").size() == 6, "У кукурузы не 6 точек посадки")
	check(FarmMeshes._plant_spots("sunflower").size() == 6, "У подсолнуха не 6 точек посадки")
	# Неизвестная культура не роняет генерацию.
	check(FarmMeshes.crop("no_such_crop", 2) != null, "Фолбэк меша сломан")

# --- 5. Фруктовые деревья ---
func _test_fruit_trees() -> void:
	# Конфиги по мастер-плану: рост в днях, урожай, сезоны.
	var cfg_expect: Dictionary = {
		"apple_tree": {"grow": [24.0, 48.0], "yield": [4, 8], "seasons": ["autumn"], "fruit": "apple", "sapling": "apple_sapling"},
		"pear_tree": {"grow": [24.0, 72.0], "yield": [3, 6], "seasons": ["autumn"], "fruit": "pear", "sapling": "pear_sapling"},
		"cherry_tree": {"grow": [24.0, 48.0], "yield": [6, 12], "seasons": ["summer"], "fruit": "cherry", "sapling": "cherry_sapling"},
	}
	for t in cfg_expect:
		check(FruitTreeScript.CONFIGS.has(t), "Нет конфига %s" % t)
		var c: Dictionary = FruitTreeScript.CONFIGS[t]
		var e: Dictionary = cfg_expect[t]
		check(Array(c["grow_hours"]) == Array(e["grow"]), "%s: рост %s, а не %s ч" % [t, c["grow_hours"], e["grow"]])
		check(Array(c["yield_range"]) == Array(e["yield"]), "%s: урожай %s" % [t, c["yield_range"]])
		check(Array(c["seasons"]) == Array(e["seasons"]), "%s: сезоны %s" % [t, c["seasons"]])
		check(not ItemDB.get_item(str(c["fruit_id"])).is_empty(), "%s: нет плода %s" % [t, c["fruit_id"]])
		check(not ItemDB.get_item(str(c["sapling_id"])).is_empty(), "%s: нет саженца %s" % [t, c["sapling_id"]])
	# Рост саженец -> молодое -> взрослое с плодами (яблоня: 24 + 48 ч).
	var tree: Node = FruitTreeScript.new()
	root.add_child(tree)
	tree.set_process(false)
	tree.tree_type = "apple_tree"
	tree.stage = FruitTreeScript.Stage.SAPLING
	tree.has_fruit = false
	tree.advance_hours(23.0)
	check(tree.stage == FruitTreeScript.Stage.SAPLING, "Яблоня выросла раньше 24 ч")
	tree.advance_hours(1.0)
	check(tree.stage == FruitTreeScript.Stage.YOUNG, "Яблоня не перешла в молодое за 24 ч")
	tree.advance_hours(47.0)
	check(tree.stage == FruitTreeScript.Stage.YOUNG, "Яблоня созрела раньше 48 ч")
	tree.advance_hours(1.0)
	check(tree.stage == FruitTreeScript.Stage.MATURE and tree.has_fruit, "Яблоня не созрела за 24+48 ч")
	check(tree.is_in_group("fruit_trees"), "Дерево не в группе fruit_trees")
	# Сбор урожая: плоды в диапазоне, дерево пустеет.
	var before: int = mock.inventory.get_item_count("apple")
	tree.interact(mock)
	var got: int = mock.inventory.get_item_count("apple") - before
	check(got >= 4 and got <= 8, "Собрано яблок %d, а не 4–8" % got)
	check(not tree.has_fruit, "После сбора дерево осталось с плодами")
	tree.interact(mock)
	check(mock.inventory.get_item_count("apple") - before == got, "С пустого дерева собрался урожай")
	check(tree.current_hits == tree.max_hits - 1, "E по пустому дереву с топором не рубит")
	# Отрастание за 24 ч (сезоны выключены — круглый год).
	tree.advance_hours(24.0)
	check(tree.has_fruit, "Плоды не отросли за 24 ч")
	# Сезоны включены: яблоня плодоносит только осенью.
	tree.has_fruit = false
	tree.regrow_progress = 0.0
	for season in Seasons.ALL:
		Seasons.current_season = season
		tree.has_fruit = false
		tree.regrow_progress = 0.0
		tree.advance_hours(30.0)
		check(tree.has_fruit == (season == "autumn"), "Яблоня плодоносит в сезон %s" % season)
	Seasons.current_season = ""
	# Рубка топором Lv.1: 8 ударов, древесина и саженец, узел удаляется.
	tree.current_hits = tree.max_hits
	var wood_before: int = mock.inventory.get_item_count("wood")
	var sap_before: int = mock.inventory.get_item_count("apple_sapling")
	for i in 7:
		check(not tree.chop(mock), "Дерево упало раньше 8 ударов")
	check(tree.chop(mock), "Дерево не упало за 8 ударов")
	check(tree.is_queued_for_deletion(), "Срубленное дерево не удалено")
	check(mock.inventory.get_item_count("wood") - wood_before == 4, "За рубку должно быть 4 древесины (8×0.25+2)")
	check(mock.inventory.get_item_count("apple_sapling") - sap_before == 1, "Саженец не вернулся при рубке")
	# Сохранение: снимок и восстановление.
	var tree2: Node = FruitTreeScript.new()
	root.add_child(tree2)
	tree2.set_process(false)
	tree2.tree_type = "pear_tree"
	tree2.stage = FruitTreeScript.Stage.YOUNG
	tree2.growth_progress = 10.0
	tree2.has_fruit = false
	tree2.regrow_progress = 3.0
	tree2.current_hits = 2
	tree2.position = Vector3(5.0, 0.0, -7.0)
	var snap: Dictionary = tree2.get_save_state()
	var tree3: Node = FruitTreeScript.new()
	root.add_child(tree3)
	tree3.set_process(false)
	tree3.apply_save_state(snap)
	check(tree3.tree_type == "pear_tree" and tree3.stage == FruitTreeScript.Stage.YOUNG, "Сейв дерева: вид/стадия")
	check(is_equal_approx(tree3.growth_progress, 10.0), "Сейв дерева: прогресс роста")
	check(is_equal_approx(tree3.global_position.x, 5.0), "Сейв дерева: позиция")
	tree.queue_free()
	tree2.queue_free()
	tree3.queue_free()

# --- 6. Плейсер саженцев: саженец -> вид дерева ---
func _test_placer_setup() -> void:
	var placer: Node = FruitPlacerScript.new()
	placer.setup(null, null, "pear_sapling")
	check(placer.tree_type == "pear_tree", "Саженец груши даёт %s" % placer.tree_type)
	placer.setup(null, null, "cherry_sapling")
	check(placer.tree_type == "cherry_tree", "Саженец вишни даёт %s" % placer.tree_type)
	placer.setup(null, null, "apple_sapling")
	check(placer.tree_type == "apple_tree", "Саженец яблони даёт %s" % placer.tree_type)
	placer.free()

# --- 7. Старые грядки: только базовые культуры ---
func _test_old_plots_guard() -> void:
	var plot: Node = FarmlandPlot.new()
	plot.soil_state = FarmlandPlot.SoilState.TILLED
	mock.inventory.add_item("seeds_tomato", 2)
	mock.inventory.add_item("seeds_carrot", 2)
	check(not plot.plant_crop("seeds_tomato", mock), "Старая грядка приняла томат")
	check(plot.crop_type == "", "Тип культуры изменился от запрещённой посадки")
	check(mock.inventory.get_item_count("seeds_tomato") == 2, "Семена томата списались зря")
	check(plot.plant_crop("seeds_carrot", mock), "Старая грядка не приняла морковь")
	check(plot.crop_type == "carrot", "Не та культура на грядке")
	mock.inventory.remove_item("seeds_tomato", 2)
	mock.inventory.remove_item("seeds_carrot", 1)
	plot.free()

# --- 8. Посылки от Марты: награда предметами ---
func _test_seed_contracts() -> void:
	var seeds: Dictionary = ContractDB.get_contract("contract_marta_seeds")
	var orchard: Dictionary = ContractDB.get_contract("contract_marta_orchard")
	check(not seeds.is_empty() and not orchard.is_empty(), "Нет контрактов-посылок от Марты")
	check(int(seeds.get("unlock_after", -1)) == 2, "Посылка семян открывается не после 2 заказов")
	check(int(orchard.get("unlock_after", -1)) == 4, "Саженцы открываются не после 4 заказов")
	check(not ContractDB.can_fulfill(seeds, mock.inventory), "Посылка доступна до открытия волны")
	# Открываем волну и сдаём.
	ContractDB.completed_contracts["contract_fortify"] = true
	ContractDB.completed_contracts["contract_fuel_reserve"] = true
	check(ContractDB.can_fulfill(seeds, mock.inventory) == false, "Посылка доступна без товаров")
	mock.inventory.add_item("carrot", 4)
	mock.inventory.add_item("potato", 4)
	mock.inventory.add_item("bread", 2)
	var credits_before: int = mock.inventory.credits
	check(ContractDB.can_fulfill(seeds, mock.inventory), "Посылка недоступна с товарами")
	check(ContractDB.fulfill_contract("contract_marta_seeds", mock), "Посылка не сдалась")
	check(mock.inventory.get_item_count("seeds_sunflower") == 3, "Нет семян подсолнуха из посылки")
	check(mock.inventory.get_item_count("seeds_onion") == 3, "Нет семян лука из посылки")
	check(mock.inventory.get_item_count("seeds_bean") == 4, "Нет семян фасоли из посылки")
	check(mock.inventory.get_item_count("seeds_herbs") == 3, "Нет семян трав из посылки")
	check(mock.inventory.credits > credits_before, "Нет кредитов за посылку")
	check(mock.inventory.get_item_count("carrot") == 0, "Морковь не списалась")
	# Саженцы закрыты до 4 заказов.
	check(not ContractDB.can_fulfill(orchard, mock.inventory), "Саженцы доступны раньше 4 заказов")
	ContractDB.completed_contracts["contract_pure_water"] = true
	ContractDB.completed_contracts["contract_grain_supply"] = true
	mock.inventory.clear()
	mock.inventory.add_item("wheat", 6)
	mock.inventory.add_item("bottled_water", 2)
	check(ContractDB.fulfill_contract("contract_marta_orchard", mock), "Саженцы не выдались")
	check(mock.inventory.get_item_count("apple_sapling") == 1, "Нет саженца яблони")
	check(mock.inventory.get_item_count("pear_sapling") == 1, "Нет саженца груши")
	check(mock.inventory.get_item_count("cherry_sapling") == 1, "Нет саженца вишни")
	check(mock.inventory.get_item_count("seeds_corn") == 2, "Нет семян кукурузы")
	check(mock.inventory.get_item_count("seeds_pumpkin") == 2, "Нет семян тыквы")
	ContractDB.reset_completed()

# --- 9. Секция fruit_trees в сохранениях ---
func _test_fruit_save_validation() -> void:
	var good: Dictionary = {"fruit_trees": [
		{"type": "apple_tree", "pos": [1.0, 0.0, 2.0], "stage": 2, "growth": 0.0, "has_fruit": true, "regrow": 0.0, "hits": 3},
		{"type": "cherry_tree", "pos": [3.0, 0.0, 4.0], "stage": 0, "growth": 5.0, "has_fruit": false, "regrow": 1.0, "hits": 3},
	]}
	check(SaveManagerScript._validate_save_data(good), "Корректные деревья отклонены")
	check(not SaveManagerScript._validate_save_data({"fruit_trees": {}}), "Секция-объект принята")
	check(not SaveManagerScript._validate_save_data({"fruit_trees": [{"type": "oak", "pos": [0, 0, 0]}]}), "Неизвестный вид принят")
	check(not SaveManagerScript._validate_save_data({"fruit_trees": [{"type": "apple_tree", "pos": [0, 0]}]}), "Короткая позиция принята")
	check(not SaveManagerScript._validate_save_data({"fruit_trees": [{"type": "apple_tree", "pos": [0, 0, 0], "stage": 5}]}), "Неверная стадия принята")
	# Без секции — старый сейв валиден.
	check(SaveManagerScript._validate_save_data({}), "Пустой сейв отклонён")
