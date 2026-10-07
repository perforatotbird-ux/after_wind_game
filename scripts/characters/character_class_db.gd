class_name CharacterClassDB
extends RefCounted

## Реестр архетипов и специализаций персонажей (Разделы 1, 39, 40 дизайн-документа)

const CLASSES: Dictionary = {
	"miner": {
		"id": "miner",
		"name": "Шахтёр",
		"icon": "⛏️",
		"portrait": "res://assets/sprites/miner_portrait.png",
		"sprite": "res://assets/sprites/miner_isometric.png",
		"title": "Специалист по добыче",
		"description": "Опытный проходчик и геолог. Мастерски раскалывает скальные породы, добывает руды и извлекает скрытые залежи металлолома.",
		"perks": [
			"🪨 +1 бонусный ресурс при добыче камня и металлолома",
			"⚡ -20% расход энергии при работе киркой",
			"📦 Стартовый комплект: +5 камня, +2 металлолома"
		],
		"starting_items": {
			"stone": 5,
			"metal_scrap": 2
		},
		"starting_credits": 0,
		"mining_bonus_yield": 1,
		"mining_energy_mult": 0.80,
		"crop_growth_mult": 1.0,
		"hunger_decay_mult": 1.0,
		"machine_speed_mult": 1.0,
		"machine_energy_mult": 1.0
	},
	"farmer": {
		"id": "farmer",
		"name": "Фермер",
		"icon": "🌾",
		"portrait": "res://assets/sprites/farmer_portrait.png",
		"sprite": "res://assets/sprites/farmer_isometric.png",
		"title": "Специалист по агрономии и выживанию",
		"description": "Знаток почв, селекции и ботаники. Умеет ускорять созревание культур и исключительно экономен в расходе пищи.",
		"perks": [
			"🌱 +35% к скорости роста культур на грядках",
			"🍞 -25% расход сытости (медленнее голодает)",
			"📦 Стартовый комплект: семена моркови (x2), картофеля (x2), пшеницы (x2), био-удобрение (x1)"
		],
		"starting_items": {
			"seeds_carrot": 2,
			"seeds_potato": 2,
			"seeds_wheat": 2,
			"fertilizer": 1
		},
		"starting_credits": 0,
		"mining_bonus_yield": 0,
		"mining_energy_mult": 1.0,
		"crop_growth_mult": 1.35,
		"hunger_decay_mult": 0.75,
		"machine_speed_mult": 1.0,
		"machine_energy_mult": 1.0
	},
	"scientist": {
		"id": "scientist",
		"name": "Учёный",
		"icon": "🔬",
		"portrait": "res://assets/sprites/miner_portrait.png",
		"sprite": "res://assets/sprites/miner_isometric.png",
		"title": "Специалист по переработке и исследованиям",
		"description": "Инженер-технолог и исследователь. Максимально оптимизирует производственные линии, работу дробилок, печей и верстака.",
		"perks": [
			"⚙️ +40% скорость работы всех машин (дробилка, печь, верстак, фильтр)",
			"⚡ -50% затрат энергии игрока на запуск технологических процессов",
			"📦 Стартовый комплект: +50 кредитов, +2 медных провода, +1 металлическая пластина"
		],
		"starting_items": {
			"copper_wire": 2,
			"iron_plate": 1
		},
		"starting_credits": 50,
		"mining_bonus_yield": 0,
		"mining_energy_mult": 1.0,
		"crop_growth_mult": 1.0,
		"hunger_decay_mult": 1.0,
		"machine_speed_mult": 1.40,
		"machine_energy_mult": 0.50
	}
}

static func get_class_data(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, CLASSES["miner"])

static func get_all_classes() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for k in ["miner", "farmer", "scientist"]:
		list.append(CLASSES[k])
	return list

static func get_class_display_name(class_id: String) -> String:
	if CLASSES.has(class_id):
		return CLASSES[class_id].get("name", class_id)
	return class_id

static func get_class_icon(class_id: String) -> String:
	if CLASSES.has(class_id):
		return CLASSES[class_id].get("icon", "👤")
	return "👤"
