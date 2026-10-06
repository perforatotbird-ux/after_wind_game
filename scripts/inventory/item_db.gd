class_name ItemDB
extends RefCounted

## База данных предметов игры "После бури"
## Соответствует разделам 14, 15, 16, 17 дизайн-документа

const ITEMS: Dictionary = {
	# --- Базовые инструменты ---
	"axe": {
		"id": "axe",
		"name": "Старый топор",
		"icon": "🪓",
		"category": "tool",
		"tool_type": "axe",
		"level": 1,
		"power": 1.0,
		"weight": 1.5,
		"max_stack": 1,
		"description": "Базовый инструмент для рубки деревьев и заготовки древесины."
	},
	"pickaxe": {
		"id": "pickaxe",
		"name": "Самодельная кирка",
		"icon": "⛏",
		"category": "tool",
		"tool_type": "pickaxe",
		"level": 1,
		"power": 1.0,
		"weight": 2.0,
		"max_stack": 1,
		"description": "Базовый инструмент для добычи камня и минералов."
	},
	"shovel": {
		"id": "shovel",
		"name": "Лопата",
		"icon": "⛏",
		"category": "tool",
		"tool_type": "shovel",
		"level": 1,
		"power": 1.0,
		"weight": 1.8,
		"max_stack": 1,
		"description": "Инструмент для сбора глины, песка и работы с грунтом."
	},
	"bucket": {
		"id": "bucket",
		"name": "Ведро",
		"icon": "💧",
		"category": "tool",
		"tool_type": "bucket",
		"level": 1,
		"power": 1.0,
		"weight": 1.0,
		"max_stack": 1,
		"description": "Используется для набора и переноски чистой воды. Не расходуется."
	},
	"backpack": {
		"id": "backpack",
		"name": "Рюкзак",
		"icon": "🎒",
		"category": "equipment",
		"tool_type": "backpack",
		"level": 1,
		"slots": 12,
		"weight": 0.5,
		"max_stack": 1,
		"description": "Походный рюкзак 1-го уровня (вместимость: 12 слотов)."
	},

	# --- Базовые ресурсы (Этап 1, разделы 16, 17) ---
	"wood": {
		"id": "wood",
		"name": "Древесина",
		"icon": "🌲",
		"category": "resource",
		"weight": 1.0,
		"max_stack": 50,
		"description": "Брёвна и ветки, поваленные бурей. Нужны для топлива и опилок."
	},
	"stone": {
		"id": "stone",
		"name": "Камень",
		"icon": "⛰",
		"category": "resource",
		"weight": 1.5,
		"max_stack": 50,
		"description": "Крепкая каменная порода. Измельчается в пыль для кирпичей."
	},
	"clay": {
		"id": "clay",
		"name": "Глина",
		"icon": "🧱",
		"category": "resource",
		"weight": 1.2,
		"max_stack": 50,
		"description": "Сырая вязкая глина. Основной компонент для обжига кирпичей."
	},
	"sand": {
		"id": "sand",
		"name": "Песок",
		"icon": "⏳",
		"category": "resource",
		"weight": 1.0,
		"max_stack": 50,
		"description": "Мелкий речной песок. Необходим для растворов и восстановления построек."
	},
	"water": {
		"id": "water",
		"name": "Сырая вода",
		"icon": "💧",
		"category": "resource",
		"weight": 0.8,
		"max_stack": 20,
		"sell_price": 1,
		"is_drinkable": true,
		"thirst_recovery": 25.0,
		"energy_bonus": 0.0,
		"description": "Сырая грунтовая вода. Утоляет немного жажды (+25%), но для пользы её лучше отфильтровать."
	},

	# --- Промежуточные материалы (Этап 3, разделы 18, 19) ---
	"stone_dust": {
		"id": "stone_dust",
		"name": "Каменная пыль",
		"icon": "⚪",
		"category": "material",
		"weight": 0.6,
		"max_stack": 50,
		"sell_price": 2,
		"description": "Измельчённый камень из дробилки. Необходима для создания кирпичей."
	},
	"sawdust": {
		"id": "sawdust",
		"name": "Опилки",
		"icon": "🍂",
		"category": "material",
		"weight": 0.3,
		"max_stack": 50,
		"sell_price": 1,
		"description": "Древесные опилки из дробилки. Сырьё для топливных брикетов."
	},

	# --- Готовая продукция (Этап 3, разделы 20, 21, 22; Этап 4, 6) ---
	"poor_brick": {
		"id": "poor_brick",
		"name": "Говённый кирпич",
		"icon": "🧱",
		"category": "product",
		"weight": 2.0,
		"max_stack": 50,
		"sell_price": 8,
		"description": "Кустарный кирпич раннего этапа. Дешёвый, но активно скупается станцией отправки."
	},
	"fuel_briquette": {
		"id": "fuel_briquette",
		"name": "Топливный брикет",
		"icon": "📦",
		"category": "product",
		"weight": 1.5,
		"max_stack": 50,
		"sell_price": 10,
		"description": "Прессованный топливный блок из опилок и воды. Высокая теплоотдача и спрос."
	},
	"metal_scrap": {
		"id": "metal_scrap",
		"name": "Металлолом",
		"icon": "🔩",
		"category": "resource",
		"weight": 2.0,
		"max_stack": 50,
		"sell_price": 5,
		"description": "Ржавые куски арматуры и деталей, разбросанные бурей по двору."
	},
	"fired_brick": {
		"id": "fired_brick",
		"name": "Обожжённый кирпич",
		"icon": "🧱",
		"category": "product",
		"weight": 1.8,
		"max_stack": 50,
		"sell_price": 18,
		"description": "Высокопрочный термостойкий кирпич, закаленный в плавильной печи."
	},
	"glass": {
		"id": "glass",
		"name": "Листовое стекло",
		"icon": "🪟",
		"category": "product",
		"weight": 1.2,
		"max_stack": 40,
		"sell_price": 22,
		"description": "Прозрачное закалённое стекло из выплавленного кварцевого песка."
	},
	"iron_ingot": {
		"id": "iron_ingot",
		"name": "Железный слиток",
		"icon": "🪙",
		"category": "product",
		"weight": 2.5,
		"max_stack": 40,
		"sell_price": 35,
		"description": "Очищенный железный слиток, выплавленный из металлолома в печи."
	},
	"clean_water": {
		"id": "clean_water",
		"name": "Очищенная вода",
		"icon": "💧",
		"category": "product",
		"weight": 0.8,
		"max_stack": 30,
		"sell_price": 15,
		"is_drinkable": true,
		"thirst_recovery": 50.0,
		"energy_bonus": 8.0,
		"description": "Кристально чистая фильтрованная вода. Восстанавливает +50% жажды и бодрит (+8 энергии)."
	},
	"bottled_water": {
		"id": "bottled_water",
		"name": "Бутилированная вода",
		"icon": "🧴",
		"category": "product",
		"weight": 1.1,
		"max_stack": 30,
		"sell_price": 52,
		"is_drinkable": true,
		"thirst_recovery": 85.0,
		"energy_bonus": 15.0,
		"description": "Премиальная родниковая вода в герметичной стеклянной бутылке (+85% жажды, +15 энергии, высокая цена сбыта)."
	}
}

static func get_item(item_id: String) -> Dictionary:
	if ITEMS.has(item_id):
		return ITEMS[item_id]
	return {}

static func get_item_name(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("name", item_id)
	return item_id

static func get_item_icon(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("icon", "📦")
	return "📦"

static func get_sell_price(item_id: String) -> int:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("sell_price", 0)
	return 0

static func is_drinkable(item_id: String) -> bool:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("is_drinkable", false)
	return false

static func get_thirst_recovery(item_id: String) -> float:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("thirst_recovery", 0.0)
	return 0.0

static func get_energy_bonus(item_id: String) -> float:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("energy_bonus", 0.0)
	return 0.0
