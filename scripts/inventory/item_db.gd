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
	},

	# --- Сельское хозяйство и ферма (Этап 8, разделы 17, 31, 33) ---
	"seeds_carrot": {
		"id": "seeds_carrot",
		"name": "Семена моркови",
		"icon": "🥕",
		"category": "seeds",
		"crop_type": "carrot",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 5,
		"description": "Пакет сортовых семян сочной моркови для посева во влажные борозды."
	},
	"seeds_potato": {
		"id": "seeds_potato",
		"name": "Семенной картофель",
		"icon": "🥔",
		"category": "seeds",
		"crop_type": "potato",
		"weight": 0.2,
		"max_stack": 30,
		"sell_price": 6,
		"description": "Пророщенные клубни картофеля для посадки во взрыхлённую землю."
	},
	"seeds_wheat": {
		"id": "seeds_wheat",
		"name": "Семена пшеницы",
		"icon": "🌾",
		"category": "seeds",
		"crop_type": "wheat",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 4,
		"description": "Отборные яровые зерна пшеницы для засева пахотной грядки."
	},
	"carrot": {
		"id": "carrot",
		"name": "Свежая морковь",
		"icon": "🥕",
		"category": "food",
		"weight": 0.3,
		"max_stack": 30,
		"sell_price": 14,
		"is_edible": true,
		"hunger_recovery": 28.0,
		"thirst_recovery": 12.0,
		"energy_bonus": 10.0,
		"description": "Хрустящая сладкая морковь прямо с грядки (+28% сытости, +12% жажды, +10 энергии)."
	},
	"potato": {
		"id": "potato",
		"name": "Картофель",
		"icon": "🥔",
		"category": "food",
		"weight": 0.4,
		"max_stack": 30,
		"sell_price": 18,
		"is_edible": true,
		"hunger_recovery": 42.0,
		"thirst_recovery": 5.0,
		"energy_bonus": 15.0,
		"description": "Питательные плотные клубни картофеля (+42% сытости, +15 энергии)."
	},
	"wheat": {
		"id": "wheat",
		"name": "Сноп пшеницы",
		"icon": "🌾",
		"category": "crop",
		"weight": 0.5,
		"max_stack": 40,
		"sell_price": 12,
		"description": "Золотистые созревшие колосья пшеницы. Сырье для помола муки и выпечки."
	},
	"bread": {
		"id": "bread",
		"name": "Свежий хлеб",
		"icon": "🍞",
		"category": "food",
		"weight": 0.5,
		"max_stack": 20,
		"sell_price": 48,
		"is_edible": true,
		"hunger_recovery": 65.0,
		"energy_bonus": 25.0,
		"description": "Ароматный домашний хлеб из печи (+65% сытости, +25 энергии)."
	},
	"fertilizer": {
		"id": "fertilizer",
		"name": "Био-удобрение",
		"icon": "🧪",
		"category": "farming",
		"weight": 0.5,
		"max_stack": 30,
		"sell_price": 16,
		"description": "Смесь компоста, глины и золы. Ускоряет созревание культур на грядке в 2 раза."
	},

	# --- Электрогенерация и освещение (Этап 10, разделы 54, 57, 84) ---
	"copper_wire": {
		"id": "copper_wire",
		"name": "Медный провод",
		"icon": "🔌",
		"category": "component",
		"weight": 0.1,
		"max_stack": 40,
		"sell_price": 18,
		"description": "Изолированная витая медная жила для прокладки линий электропередач и проводки."
	},
	"iron_plate": {
		"id": "iron_plate",
		"name": "Металлическая пластина",
		"icon": "🛡️",
		"category": "component",
		"weight": 0.8,
		"max_stack": 25,
		"sell_price": 28,
		"description": "Прочный прокатанный лист железа для корпусов приборов и каркасов лопастей."
	},
	"gear": {
		"id": "gear",
		"name": "Механическая шестерня",
		"icon": "⚙️",
		"category": "component",
		"weight": 0.5,
		"max_stack": 30,
		"sell_price": 34,
		"description": "Точно выточенное зубчатое колесо редуктора для передачи вращения ротора ветряка."
	},
	"battery_cell": {
		"id": "battery_cell",
		"name": "Аккумуляторный элемент",
		"icon": "🔋",
		"category": "component",
		"weight": 1.2,
		"max_stack": 15,
		"sell_price": 55,
		"description": "Электрохимическая ячейка высокой емкости для накопления избыточной энергии ветрогенератора."
	},
	"street_lamp_item": {
		"id": "street_lamp_item",
		"name": "Комплект уличного фонаря",
		"icon": "🏮",
		"category": "building",
		"weight": 3.5,
		"max_stack": 5,
		"sell_price": 85,
		"description": "Готовый к установке уличный фонарный столб с плафоном, патроном и проводкой."
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

static func is_edible(item_id: String) -> bool:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("is_edible", false)
	return false

static func get_thirst_recovery(item_id: String) -> float:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("thirst_recovery", 0.0)
	return 0.0

static func get_hunger_recovery(item_id: String) -> float:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("hunger_recovery", 0.0)
	return 0.0

static func get_energy_bonus(item_id: String) -> float:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("energy_bonus", 0.0)
	return 0.0

static func is_seed(item_id: String) -> bool:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("category", "") == "seeds"
	return false

static func get_crop_type(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("crop_type", "")
	return ""

