class_name RecipeDB
extends RefCounted

## База данных производственных рецептов
## Соответствует разделам 18, 19, 20, 21 дизайн-документа

const RECIPES: Dictionary = {
	"crush_stone": {
		"id": "crush_stone",
		"name": "Камень → Каменная пыль",
		"machine": "crusher",
		"inputs": {"stone": 2},
		"outputs": {"stone_dust": 1},
		"duration": 6.0,
		"energy_cost": 2.0,
		"description": "Измельчает 2 камня в 1 порцию тонкой каменной пыли."
	},
	"crush_wood": {
		"id": "crush_wood",
		"name": "Древесина → Опилки",
		"machine": "crusher",
		"inputs": {"wood": 2},
		"outputs": {"sawdust": 4},
		"duration": 6.0,
		"energy_cost": 2.0,
		"description": "Перемалывает 2 бревна в 4 порции древесных опилок."
	},
	"craft_brick": {
		"id": "craft_brick",
		"name": "Формовка: Говённый кирпич (x2)",
		"machine": "workbench",
		"inputs": {"stone_dust": 2, "clay": 1, "water": 1},
		"outputs": {"poor_brick": 2},
		"duration": 5.0,
		"energy_cost": 3.0,
		"description": "Замес глины с каменной пылью и водой в формы для сырого кирпича."
	},
	"craft_briquette": {
		"id": "craft_briquette",
		"name": "Прессование: Топливные брикеты (x2)",
		"machine": "workbench",
		"inputs": {"sawdust": 4, "water": 1},
		"outputs": {"fuel_briquette": 2},
		"duration": 5.0,
		"energy_cost": 3.0,
		"description": "Прессование опилок с водой в высококалорийные блоки топлива."
	},
	"smelt_brick": {
		"id": "smelt_brick",
		"name": "Обжиг: Обожжённый кирпич (x2)",
		"machine": "furnace",
		"inputs": {"poor_brick": 2, "fuel_briquette": 1},
		"outputs": {"fired_brick": 2},
		"duration": 5.0,
		"energy_cost": 2.0,
		"description": "Закалка сырых необожженных кирпичей в раскаленной печи с топливом."
	},
	"smelt_glass": {
		"id": "smelt_glass",
		"name": "Выплавка: Листовое стекло (x1)",
		"machine": "furnace",
		"inputs": {"sand": 2, "fuel_briquette": 1},
		"outputs": {"glass": 1},
		"duration": 5.5,
		"energy_cost": 2.0,
		"description": "Высокотемпературное плавление кварцевого песка в прозрачное стекло."
	},
	"smelt_iron": {
		"id": "smelt_iron",
		"name": "Переплавка: Железный слиток (x1)",
		"machine": "furnace",
		"inputs": {"metal_scrap": 2, "fuel_briquette": 2},
		"outputs": {"iron_ingot": 1},
		"duration": 6.5,
		"energy_cost": 3.0,
		"description": "Переплавка собранного ржавого металлолома в чистый прочный слиток железа."
	},
	"filter_water": {
		"id": "filter_water",
		"name": "Песчаная фильтрация: Чистая вода (x2)",
		"machine": "water_filter",
		"inputs": {"water": 2, "sand": 1},
		"outputs": {"clean_water": 2},
		"duration": 4.5,
		"energy_cost": 1.5,
		"description": "Очистка мутной сырой воды через слой кварцевого песка в чистую питьевую воду."
	},
	"mineral_filter_water": {
		"id": "mineral_filter_water",
		"name": "Глубокая фильтрация: Чистая вода (x4)",
		"machine": "water_filter",
		"inputs": {"water": 3, "sand": 1, "stone_dust": 1},
		"outputs": {"clean_water": 4},
		"duration": 5.0,
		"energy_cost": 2.0,
		"description": "Многоступенчатая фильтрация песком и каменной пылью с повышенным выходом чистой воды."
	},
	"bottle_water": {
		"id": "bottle_water",
		"name": "Розлив: Бутилированная вода (x1)",
		"machine": "workbench",
		"inputs": {"clean_water": 1, "glass": 1},
		"outputs": {"bottled_water": 1},
		"duration": 3.0,
		"energy_cost": 1.0,
		"description": "Розлив фильтрованной воды в герметичные стеклянные бутылки для длительного хранения и продажи."
	},
	"craft_fertilizer": {
		"id": "craft_fertilizer",
		"name": "Смешивание: Био-удобрение (x2)",
		"machine": "workbench",
		"inputs": {"clay": 1, "sawdust": 2, "water": 1},
		"outputs": {"fertilizer": 2},
		"duration": 4.0,
		"energy_cost": 2.0,
		"description": "Смешивание обогащенной глины, органических опилок и воды в стимулирующее био-удобрение."
	},
	"extract_carrot_seeds": {
		"id": "extract_carrot_seeds",
		"name": "Селекция: Семена моркови (x2)",
		"machine": "workbench",
		"inputs": {"carrot": 1},
		"outputs": {"seeds_carrot": 2},
		"duration": 3.0,
		"energy_cost": 1.0,
		"description": "Сбор и сушка отборных сортовых семян из выращенной моркови для повторного посева."
	},
	"extract_potato_seeds": {
		"id": "extract_potato_seeds",
		"name": "Подготовка: Семенной картофель (x2)",
		"machine": "workbench",
		"inputs": {"potato": 1},
		"outputs": {"seeds_potato": 2},
		"duration": 3.0,
		"energy_cost": 1.0,
		"description": "Отбор и деление клубней картофеля на пророщенный посадочный материал."
	},
	"extract_wheat_seeds": {
		"id": "extract_wheat_seeds",
		"name": "Обмолот: Семена пшеницы (x3)",
		"machine": "workbench",
		"inputs": {"wheat": 1},
		"outputs": {"seeds_wheat": 3},
		"duration": 3.0,
		"energy_cost": 1.0,
		"description": "Ручной обмолот пшеничного снопа для получения чистого посевного зерна."
	},
	"bake_bread": {
		"id": "bake_bread",
		"name": "Выпечка: Домашний хлеб (x2)",
		"machine": "furnace",
		"inputs": {"wheat": 2, "clean_water": 1, "fuel_briquette": 1},
		"outputs": {"bread": 2},
		"duration": 6.0,
		"energy_cost": 2.5,
		"description": "Замес теста из молотой пшеницы и чистой воды с последующей выпечкой подового хлеба в печи."
	},

	# --- Электрогенерация и освещение (Этап 10) ---
	"craft_copper_wire": {
		"id": "craft_copper_wire",
		"name": "Прокатка: Медный провод (x2)",
		"machine": "workbench",
		"inputs": {"metal_scrap": 1},
		"outputs": {"copper_wire": 2},
		"duration": 3.0,
		"energy_cost": 1.0,
		"description": "Вытяжка и изоляция медной электропроводки из цветных обрезков лома на верстаке."
	},
	"craft_iron_plate": {
		"id": "craft_iron_plate",
		"name": "Ковка: Металлическая пластина (x2)",
		"machine": "workbench",
		"inputs": {"iron_ingot": 1},
		"outputs": {"iron_plate": 2},
		"duration": 3.5,
		"energy_cost": 1.5,
		"description": "Холодная ковка и прокатка железного слитка в две плоские конструкционные пластины."
	},
	"craft_gear": {
		"id": "craft_gear",
		"name": "Выточка: Шестерня редуктора (x2)",
		"machine": "workbench",
		"inputs": {"iron_ingot": 1, "metal_scrap": 1},
		"outputs": {"gear": 2},
		"duration": 4.0,
		"energy_cost": 2.0,
		"description": "Выпиливание и шлифовка прочных зубчатых колес для поворотного механизма и вала ветряка."
	},
	"craft_battery_cell": {
		"id": "craft_battery_cell",
		"name": "Сборка: Аккумуляторный элемент (x1)",
		"machine": "workbench",
		"inputs": {"iron_plate": 1, "copper_wire": 2, "clay": 1},
		"outputs": {"battery_cell": 1},
		"duration": 4.5,
		"energy_cost": 2.0,
		"description": "Электролитная ячейка в герметичном металлическом корпусе с глиняным сепаратором и клеммами."
	},
	"craft_street_lamp": {
		"id": "craft_street_lamp",
		"name": "Сборка: Уличный фонарь (x1)",
		"machine": "workbench",
		"inputs": {"wood": 2, "glass": 1, "copper_wire": 1, "iron_plate": 1},
		"outputs": {"street_lamp_item": 1},
		"duration": 5.0,
		"energy_cost": 2.5,
		"description": "Изготовление уличного фонарного столба с защитным стеклянным плафоном и проводкой."
	}
}

static func get_recipes_for_machine(machine_type: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for r_id in RECIPES.keys():
		var r: Dictionary = RECIPES[r_id]
		if r.get("machine", "") == machine_type:
			list.append(r)
	return list

static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

static func can_craft(recipe: Dictionary, inventory: Node) -> bool:
	if not inventory or recipe.is_empty():
		return false
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		var needed: int = inputs[item_id]
		var available: int = inventory.get_item_count(item_id) if inventory.has_method("get_item_count") else 0
		if available < needed:
			return false
	return true
