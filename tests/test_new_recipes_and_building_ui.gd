extends SceneTree

## Тест новых предметов, рецептов и динамического отображения остатка материалов в окне ремонта.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const RepairableBuilding = preload("res://scripts/buildings/repairable_building.gd")
const HudScene = preload("res://scenes/ui/hud.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_new_items_in_item_db()
	_test_new_recipes_in_recipe_db()
	_test_building_repair_ui_dynamic_remaining()

	if errors.is_empty():
		print("PASS: test_new_recipes_and_building_ui — новые рецепты, предметы и UI ремонта работают корректно!")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)

func _test_new_items_in_item_db() -> void:
	var items_to_check: Array[String] = ["coal_powder", "glass_bottle", "clay_pot", "glassware_set"]
	for item_id in items_to_check:
		var item: Dictionary = ItemDB.get_item(item_id)
		check(not item.is_empty(), "Предмет '%s' отсутствует в ItemDB" % item_id)
		check(item.has("name") and not item["name"].is_empty(), "Предмет '%s' не имеет названия" % item_id)
		check(item.has("icon") and not item["icon"].is_empty(), "Предмет '%s' не имеет иконки" % item_id)
		check(item.has("category"), "Предмет '%s' не имеет категории" % item_id)
		check(item.has("sell_price") and item["sell_price"] > 0, "Предмет '%s' должен иметь положительную стоимость сбыта" % item_id)

func _test_new_recipes_in_recipe_db() -> void:
	# 1. Угольный порошок в дробилке
	var r_crush_coal: Dictionary = RecipeDB.get_recipe("crush_coal")
	check(not r_crush_coal.is_empty(), "Рецепт crush_coal отсутствует в RecipeDB")
	check(r_crush_coal.get("machine") == "crusher", "crush_coal должен быть привязан к дробилке (crusher)")
	check(r_crush_coal.get("inputs", {}).get("coal", 0) == 1, "crush_coal должен принимать 1 кусок угля")
	check(r_crush_coal.get("outputs", {}).get("coal_powder", 0) == 2, "crush_coal должен выдавать 2 порции угольного порошка")

	# 2. Стеклянная бутылка в печи
	var r_glass_bottle: Dictionary = RecipeDB.get_recipe("craft_glass_bottle")
	check(not r_glass_bottle.is_empty(), "Рецепт craft_glass_bottle отсутствует в RecipeDB")
	check(r_glass_bottle.get("machine") == "furnace", "craft_glass_bottle должен выполняться в печи (furnace)")
	check(r_glass_bottle.get("inputs", {}).get("glass", 0) == 1, "craft_glass_bottle должен требовать 1 стекло")
	check(r_glass_bottle.get("outputs", {}).get("glass_bottle", 0) == 2, "craft_glass_bottle должен производить 2 стеклянные бутылки")

	# 3. Глиняный горшок в печи
	var r_clay_pot: Dictionary = RecipeDB.get_recipe("smelt_clay_pot")
	check(not r_clay_pot.is_empty(), "Рецепт smelt_clay_pot отсутствует в RecipeDB")
	check(r_clay_pot.get("machine") == "furnace", "smelt_clay_pot должен выполняться в печи (furnace)")
	check(r_clay_pot.get("inputs", {}).get("clay", 0) == 2, "smelt_clay_pot должен требовать 2 глины")
	check(r_clay_pot.get("outputs", {}).get("clay_pot", 0) == 1, "smelt_clay_pot должен производить 1 глиняный горшок")

	# 4. Комплект стеклянной посуды на верстаке
	var r_glassware: Dictionary = RecipeDB.get_recipe("craft_glassware_set")
	check(not r_glassware.is_empty(), "Рецепт craft_glassware_set отсутствует в RecipeDB")
	check(r_glassware.get("machine") == "workbench", "craft_glassware_set должен выполняться на верстаке (workbench)")
	check(r_glassware.get("inputs", {}).has("glass"), "craft_glassware_set должен использовать стекло")
	check(r_glassware.get("inputs", {}).has("glass_bottle"), "craft_glassware_set должен использовать стеклянную бутылку")
	check(r_glassware.get("outputs", {}).get("glassware_set", 0) == 1, "craft_glassware_set должен производить 1 комплект посуды")

	# 5. Обновленный розлив воды в стеклянную бутылку
	var r_bottle_water: Dictionary = RecipeDB.get_recipe("bottle_water")
	check(r_bottle_water.get("inputs", {}).has("glass_bottle"), "Рецепт bottle_water должен использовать glass_bottle вместо абстрактного glass")
	check(r_bottle_water.get("inputs", {}).has("clean_water"), "Рецепт bottle_water должен использовать чистую воду")

func _test_building_repair_ui_dynamic_remaining() -> void:
	var hud = HudScene.instantiate()
	root.add_child(hud)

	var player = PlayerScene.instantiate()
	root.add_child(player)
	hud.bind_player(player)

	# Создаем здание с контролируемыми стадиями для теста
	var building: RepairableBuilding = RepairableBuilding.new()
	building.building_id = "test_workshop"
	building.building_title = "Тестовая мастерская"
	building.current_stage = 0
	building.max_stage = 1
	building.stages_config = [
		{
			"stage": 0,
			"name": "Руины",
			"description": "Разрушено",
			"cost_credits": 0,
			"cost_materials": {}
		},
		{
			"stage": 1,
			"name": "Восстановлено",
			"description": "Готово",
			"cost_credits": 50,
			"cost_materials": {
				"clay": 25
			}
		}
	]
	root.add_child(building)

	# Открываем окно ремонта
	hud.open_repair_window(building)
	check(hud.repair_window.visible, "Окно ремонта должно быть открыто")

	# Проверяем начальное состояние: ничего не внесено
	var labels_text: String = _get_requirements_text(hud)
	check(labels_text.contains("Требуется 25"), "Начальное требование должно содержать 'Требуется 25', получено:\n" + labels_text)
	check(labels_text.contains("внесено 0 / 25"), "Должно отображаться '(внесено 0 / 25)', получено:\n" + labels_text)

	# Игрок собирает 10 глины и вносит их в здание
	player.inventory.add_item("clay", 10)
	building.contribute(player)

	# Обновляем окно ремонта
	hud._refresh_repair_window()
	labels_text = _get_requirements_text(hud)

	# Ключевая проверка: «Требуется 25 меняется на 15»
	check(labels_text.contains("Требуется 15"), "После внесения 10 глины требование должно уменьшиться до 'Требуется 15', получено:\n" + labels_text)
	check(labels_text.contains("внесено 10 / 25"), "Должно отображаться '(внесено 10 / 25)', получено:\n" + labels_text)

	# Игрок вносит оставшиеся 15 глины и кредиты
	player.inventory.add_item("clay", 15)
	player.inventory.add_credits(50)
	var completed = building.contribute(player)
	check(completed, "После сдачи всех материалов и кредитов стадия должна быть применена")
	check(building.current_stage == 1, "Текущая стадия должна стать 1")

	hud.close_repair_window()
	building.queue_free()
	player.queue_free()
	hud.queue_free()

func _get_requirements_text(hud: Node) -> String:
	var res: String = ""
	if hud and hud.repair_requirements_list:
		for row in hud.repair_requirements_list.get_children():
			for ch in row.get_children():
				if ch is Label:
					res += ch.text + "\n"
	return res
