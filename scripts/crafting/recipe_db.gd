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
