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
		"texture": "res://assets/tools/axe_icon.png",
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
		"texture": "res://assets/tools/pickaxe_icon.png",
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
		"name": "Мотыга",
		"icon": "⛏",
		"texture": "res://assets/tools/hoe_icon.tres",
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
		"texture": "res://assets/tools/bucket_icon.png",
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
		"weight": 0.25,
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
	"soil": {
		"id": "soil",
		"name": "Земля",
		"icon": "🟫",
		"category": "resource",
		"weight": 1.0,
		"max_stack": 50,
		"description": "Рыхлая земля из жилы. Пока ни во что не перерабатывается."
	},
	"coal": {
		"id": "coal",
		"name": "Уголь",
		"icon": "⚫",
		"category": "resource",
		"weight": 0.8,
		"max_stack": 50,
		"sell_price": 3,
		"description": "Каменный уголь из жилы. Топливо для печи: плавка руды и прессование брикетов."
	},
	"iron_ore": {
		"id": "iron_ore",
		"name": "Железная руда",
		"icon": "🟤",
		"category": "resource",
		"weight": 1.8,
		"max_stack": 30,
		"sell_price": 4,
		"description": "Порода с рыжими прожилками железа. В печи с углём переплавляется в слиток."
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
	"mortar": {
		"id": "mortar",
		"name": "Строительный раствор",
		"icon": "🪣",
		"category": "material",
		"weight": 1.2,
		"max_stack": 30,
		"sell_price": 3,
		"description": "Раствор из каменной пыли, песка и воды. Скрепляет кирпичную кладку при ремонте зданий."
	},
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
	"steel_plate": {
		"id": "steel_plate",
		"name": "Стальная пластина",
		"icon": "🔩",
		"category": "component",
		"weight": 1.0,
		"max_stack": 25,
		"sell_price": 45,
		"description": "Закалённая сталь клейма «База»: держит удар и жар. Деталь качественного ремонта и передовых станков."
	},
	"precision_gear": {
		"id": "precision_gear",
		"name": "Точная шестерня",
		"icon": "⚙️",
		"category": "component",
		"weight": 0.6,
		"max_stack": 25,
		"sell_price": 70,
		"description": "Шестерня с обкатанными зубьями: не дребезжит и не съедает мощность. Сердце передовой техники."
	},
	"steel_ingot": {
		"id": "steel_ingot",
		"name": "Стальной слиток",
		"icon": "⛓️",
		"category": "product",
		"weight": 1.6,
		"max_stack": 20,
		"sell_price": 78,
		"description": "Дважды переплавленное железо с присадкой угля. Из него выходят стальные пластины и точные шестерни."
	},
	"healing_water": {
		"id": "healing_water",
		"name": "Целебная вода",
		"icon": "🧪",
		"category": "product",
		"weight": 0.9,
		"max_stack": 20,
		"sell_price": 85,
		"is_drinkable": true,
		"thirst_recovery": 60.0,
		"energy_bonus": 12.0,
		"health_bonus": 15.0,
		"description": "Минерализованный настой на очищенной воде. Утоляет жажду, бодрит и затягивает ссадины (+15 здоровья)."
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
	"sapling": {
		"id": "sapling",
		"name": "Саженец",
		"icon": "🌱",
		"category": "seeds",
		"weight": 0.5,
		"max_stack": 20,
		"sell_price": 2,
		"description": "Молодое деревце с комом земли. Срубленные деревья сами не отрастают: посадите саженец на пень, и через несколько игровых часов там вырастет новое дерево."
	},
	"seeds_sunflower": {
		"id": "seeds_sunflower",
		"name": "Семена подсолнуха",
		"icon": "🌻",
		"category": "seeds",
		"crop_type": "sunflower",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 6,
		"description": "Отборные семена подсолнуха для посева. Любит солнце и устойчив к засухе."
	},
	"seeds_onion": {
		"id": "seeds_onion",
		"name": "Семена лука",
		"icon": "🧅",
		"category": "seeds",
		"crop_type": "onion",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 4,
		"description": "Чернушка — мелкие семена репчатого лука для посадки ранней весной."
	},
	"seeds_cabbage": {
		"id": "seeds_cabbage",
		"name": "Семена капусты",
		"icon": "🥬",
		"category": "seeds",
		"crop_type": "cabbage",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 5,
		"description": "Сортовые семена белокочанной капусты. Требует обильного полива."
	},
	"seeds_tomato": {
		"id": "seeds_tomato",
		"name": "Семена томата",
		"icon": "🍅",
		"category": "seeds",
		"crop_type": "tomato",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 5,
		"description": "Семена сочных грунтовых помидоров. Быстро откликаются на летнее тепло."
	},
	"seeds_pepper": {
		"id": "seeds_pepper",
		"name": "Семена перца",
		"icon": "🫑",
		"category": "seeds",
		"crop_type": "pepper",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 6,
		"description": "Семена сладкого болгарского перца. Теплолюбивая культура."
	},
	"seeds_bean": {
		"id": "seeds_bean",
		"name": "Семена фасоли",
		"icon": "🫘",
		"category": "seeds",
		"crop_type": "bean",
		"weight": 0.15,
		"max_stack": 30,
		"sell_price": 4,
		"description": "Сухие бобы для посадки. Обогащают почву азотом и быстро всходят."
	},
	"seeds_herbs": {
		"id": "seeds_herbs",
		"name": "Семена пряных трав",
		"icon": "🌿",
		"category": "seeds",
		"crop_type": "herbs",
		"weight": 0.1,
		"max_stack": 30,
		"sell_price": 3,
		"description": "Смесь семян укропа, петрушки и базилика. Скороспелая и неприхотливая культура."
	},
	"seeds_corn": {
		"id": "seeds_corn",
		"name": "Семена кукурузы",
		"icon": "🌽",
		"category": "seeds",
		"crop_type": "corn",
		"weight": 0.15,
		"max_stack": 30,
		"sell_price": 5,
		"description": "Золотистые зерна сахарной кукурузы. Вырастает в высокие пышные стебли."
	},
	"seeds_pumpkin": {
		"id": "seeds_pumpkin",
		"name": "Семена тыквы",
		"icon": "🎃",
		"category": "seeds",
		"crop_type": "pumpkin",
		"weight": 0.2,
		"max_stack": 30,
		"sell_price": 7,
		"description": "Крупные белые семена тыквы. Дают могучие плети и тяжелые плоды."
	},
	"apple_sapling": {
		"id": "apple_sapling",
		"name": "Саженец яблони",
		"icon": "🌱🍎",
		"category": "seeds",
		"tree_type": "apple_tree",
		"weight": 0.8,
		"max_stack": 10,
		"sell_price": 25,
		"description": "Молодое деревце яблони с крепким корнем. Посадите в саду, чтобы собирать сочные яблоки."
	},
	"pear_sapling": {
		"id": "pear_sapling",
		"name": "Саженец груши",
		"icon": "🌱🍐",
		"category": "seeds",
		"tree_type": "pear_tree",
		"weight": 0.8,
		"max_stack": 10,
		"sell_price": 25,
		"description": "Привитый саженец медовой груши для сада. Плодоносит крупными сладкими фруктами."
	},
	"cherry_sapling": {
		"id": "cherry_sapling",
		"name": "Саженец вишни",
		"icon": "🌱🍒",
		"category": "seeds",
		"tree_type": "cherry_tree",
		"weight": 0.8,
		"max_stack": 10,
		"sell_price": 30,
		"description": "Саженец вишнёвого дерева. Весной пышно цветет белым цветом, а летом осыпается ягодами."
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
	"red_berry": {
		"id": "red_berry",
		"name": "Красная Ягода",
		"icon": "🍒",
		"category": "food",
		"weight": 0.05,
		"max_stack": 40,
		"sell_price": 4,
		"is_edible": true,
		"hunger_recovery": 6.0,
		"thirst_recovery": 8.0,
		"energy_bonus": 4.0,
		"health_bonus": 0.0,
		"description": "Кисло-сладкая ягода с куста, растёт весной и летом (+6% сытости, +8% жажды, +4 силы; здоровье не лечит)."
	},
	"blue_berry": {
		"id": "blue_berry",
		"name": "Синяя Ягода",
		"icon": "🫐",
		"category": "food",
		"weight": 0.05,
		"max_stack": 40,
		"sell_price": 5,
		"is_edible": true,
		"hunger_recovery": 4.0,
		"thirst_recovery": 3.0,
		"energy_bonus": 9.0,
		"health_bonus": 0.0,
		"description": "Терпкая морозная ягода, вызревает зимой (+4% сытости, +3% жажды, +9 силы; здоровье не лечит)."
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
	"sunflower_seeds": {
		"id": "sunflower_seeds",
		"name": "Семечки подсолнуха",
		"icon": "🌻",
		"category": "food",
		"weight": 0.2,
		"max_stack": 40,
		"sell_price": 15,
		"is_edible": true,
		"hunger_recovery": 16.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 14.0,
		"description": "Питательные масличные семечки подсолнуха (+16% сытости, +14 энергии). Можно употреблять в пищу или пустить на семена."
	},
	"onion": {
		"id": "onion",
		"name": "Репчатый лук",
		"icon": "🧅",
		"category": "food",
		"weight": 0.2,
		"max_stack": 30,
		"sell_price": 12,
		"is_edible": true,
		"hunger_recovery": 14.0,
		"thirst_recovery": 5.0,
		"health_bonus": 5.0,
		"energy_bonus": 8.0,
		"description": "Острый репчатый лук. Укрепляет иммунитет и служит ценной приправой (+14% сытости, +5 здоровья)."
	},
	"cabbage": {
		"id": "cabbage",
		"name": "Кочан капусты",
		"icon": "🥬",
		"category": "food",
		"weight": 0.6,
		"max_stack": 20,
		"sell_price": 22,
		"is_edible": true,
		"hunger_recovery": 32.0,
		"thirst_recovery": 18.0,
		"health_bonus": 2.0,
		"energy_bonus": 10.0,
		"description": "Сочный хрустящий кочан капусты (+32% сытости, +18% жажды, +10 энергии)."
	},
	"tomato": {
		"id": "tomato",
		"name": "Спелый томат",
		"icon": "🍅",
		"category": "food",
		"weight": 0.25,
		"max_stack": 30,
		"sell_price": 16,
		"is_edible": true,
		"hunger_recovery": 20.0,
		"thirst_recovery": 22.0,
		"energy_bonus": 8.0,
		"description": "Спелый мясистый помидор прямо с куста (+20% сытости, +22% жажды)."
	},
	"pepper": {
		"id": "pepper",
		"name": "Сладкий перец",
		"icon": "🫑",
		"category": "food",
		"weight": 0.25,
		"max_stack": 30,
		"sell_price": 18,
		"is_edible": true,
		"hunger_recovery": 22.0,
		"thirst_recovery": 15.0,
		"energy_bonus": 12.0,
		"description": "Хрустящий сладкий перец, богатый витаминами (+22% сытости, +15% жажды, +12 энергии)."
	},
	"bean": {
		"id": "bean",
		"name": "Стручковая фасоль",
		"icon": "🫘",
		"category": "food",
		"weight": 0.15,
		"max_stack": 40,
		"sell_price": 10,
		"is_edible": true,
		"hunger_recovery": 18.0,
		"thirst_recovery": 5.0,
		"energy_bonus": 15.0,
		"description": "Нежные стручки фасоли, превосходный источник белка (+18% сытости, +15 энергии)."
	},
	"herbs": {
		"id": "herbs",
		"name": "Пряные травы",
		"icon": "🌿",
		"category": "food",
		"weight": 0.1,
		"max_stack": 40,
		"sell_price": 14,
		"is_edible": true,
		"hunger_recovery": 8.0,
		"thirst_recovery": 4.0,
		"health_bonus": 8.0,
		"energy_bonus": 12.0,
		"description": "Ароматный сбор лечебных и кулинарных трав (+8% сытости, +8 здоровья, +12 энергии)."
	},
	"corn": {
		"id": "corn",
		"name": "Початок кукурузы",
		"icon": "🌽",
		"category": "food",
		"weight": 0.35,
		"max_stack": 30,
		"sell_price": 20,
		"is_edible": true,
		"hunger_recovery": 36.0,
		"thirst_recovery": 5.0,
		"energy_bonus": 18.0,
		"description": "Сладкий налитой початок кукурузы (+36% сытости, +18 энергии)."
	},
	"pumpkin": {
		"id": "pumpkin",
		"name": "Спелая тыква",
		"icon": "🎃",
		"category": "food",
		"weight": 1.5,
		"max_stack": 15,
		"sell_price": 35,
		"is_edible": true,
		"hunger_recovery": 55.0,
		"thirst_recovery": 15.0,
		"energy_bonus": 20.0,
		"description": "Большая спелая тыква с золотистой мякотью (+55% сытости, +15% жажды, +20 энергии)."
	},
	"apple": {
		"id": "apple",
		"name": "Спелое яблоко",
		"icon": "🍎",
		"category": "food",
		"weight": 0.2,
		"max_stack": 30,
		"sell_price": 15,
		"is_edible": true,
		"hunger_recovery": 18.0,
		"thirst_recovery": 16.0,
		"energy_bonus": 10.0,
		"description": "Сочное хрустящее яблоко из сада (+18% сытости, +16% жажды, +10 энергии)."
	},
	"pear": {
		"id": "pear",
		"name": "Сочная груша",
		"icon": "🍐",
		"category": "food",
		"weight": 0.25,
		"max_stack": 30,
		"sell_price": 16,
		"is_edible": true,
		"hunger_recovery": 19.0,
		"thirst_recovery": 18.0,
		"energy_bonus": 10.0,
		"description": "Сладкая медовая груша (+19% сытости, +18% жажды, +10 энергии)."
	},
	"cherry": {
		"id": "cherry",
		"name": "Спелая вишня",
		"icon": "🍒",
		"category": "food",
		"weight": 0.05,
		"max_stack": 50,
		"sell_price": 8,
		"is_edible": true,
		"hunger_recovery": 8.0,
		"thirst_recovery": 10.0,
		"energy_bonus": 6.0,
		"description": "Горсть кисло-сладкой садовой вишни (+8% сытости, +10% жажды, +6 энергии)."
	},
	"blackberry": {
		"id": "blackberry",
		"name": "Ежевика",
		"icon": "🫐",
		"category": "food",
		"weight": 0.05,
		"max_stack": 50,
		"sell_price": 12,
		"is_edible": true,
		"hunger_recovery": 12.0,
		"thirst_recovery": 6.0,
		"health_bonus": 0.0,
		"energy_bonus": 8.0,
		"description": "Крупная сочная ежевика с лесной опушки (+12% сытости, +6% жажды, +8 энергии)."
	},
	"sea_buckthorn": {
		"id": "sea_buckthorn",
		"name": "Облепиха",
		"icon": "🟠",
		"category": "food",
		"weight": 0.05,
		"max_stack": 50,
		"sell_price": 18,
		"is_edible": true,
		"hunger_recovery": 6.0,
		"thirst_recovery": 6.0,
		"health_bonus": 10.0,
		"energy_bonus": 6.0,
		"description": "Янтарная лечебная ягода (+6% сытости, +6% жажды, +10 здоровья). Единственная ягода, которая лечит."
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

	# --- Глава 2 «Первый дым»: грибы и блюда костра ---
	# Сырые ингредиенты и готовые блюда. Правило мастер-плана (7.1): готовая еда
	# всегда лучше сырой по сумме эффектов — это и есть смысл кухни.
	"mushroom": {
		"id": "mushroom",
		"name": "Лесной гриб",
		"icon": "🍄",
		"category": "food",
		"weight": 0.1,
		"max_stack": 40,
		"sell_price": 9,
		"is_edible": true,
		"hunger_recovery": 12.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 5.0,
		"description": "Собирают в тени у деревьев и камней, летом и осенью. Съедобен сырым (+12% сытости, +5 энергии), но слаб — первый ингредиент кухни."
	},
	"baked_potato": {
		"id": "baked_potato",
		"name": "Печёный картофель",
		"icon": "🥔",
		"category": "food",
		"weight": 0.35,
		"max_stack": 30,
		"sell_price": 34,
		"is_edible": true,
		"hunger_recovery": 55.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 20.0,
		"description": "Картофель в золе на костре (+55% сытости, +20 энергии)."
	},
	"fried_carrot": {
		"id": "fried_carrot",
		"name": "Жареная морковь",
		"icon": "🥕",
		"category": "food",
		"weight": 0.25,
		"max_stack": 30,
		"sell_price": 26,
		"is_edible": true,
		"hunger_recovery": 35.0,
		"thirst_recovery": 18.0,
		"energy_bonus": 12.0,
		"description": "Кусочки моркови, подрумяненные на костре (+35% сытости, +18% жажды, +12 энергии)."
	},
	"vegetable_soup": {
		"id": "vegetable_soup",
		"name": "Овощной суп",
		"icon": "🍲",
		"category": "food",
		"weight": 0.4,
		"max_stack": 20,
		"sell_price": 32,
		"is_edible": true,
		"hunger_recovery": 50.0,
		"thirst_recovery": 30.0,
		"energy_bonus": 15.0,
		"description": "Горячая похлёбка из моркови и картофеля (+50% сытости, +30% жажды, +15 энергии)."
	},
	"berry_brew": {
		"id": "berry_brew",
		"name": "Ягодный отвар",
		"icon": "🍵",
		"category": "food",
		"weight": 0.3,
		"max_stack": 20,
		"sell_price": 30,
		"is_edible": true,
		"is_drinkable": true,
		"hunger_recovery": 0.0,
		"thirst_recovery": 20.0,
		"energy_bonus": 15.0,
		"health_bonus": 5.0,
		"description": "Горячий настой красной ягоды (+20% жажды, +15 энергии, +5 здоровья)."
	},
	"mushroom_stew": {
		"id": "mushroom_stew",
		"name": "Грибная похлёбка",
		"icon": "🍜",
		"category": "food",
		"weight": 0.4,
		"max_stack": 20,
		"sell_price": 36,
		"is_edible": true,
		"hunger_recovery": 40.0,
		"thirst_recovery": 25.0,
		"energy_bonus": 10.0,
		"description": "Наваристый суп из лесных грибов (+40% сытости, +25% жажды, +10 энергии)."
	},
	"dried_mushroom": {
		"id": "dried_mushroom",
		"name": "Сушёные грибы",
		"icon": "🥡",
		"category": "food",
		"weight": 0.08,
		"max_stack": 60,
		"sell_price": 22,
		"is_edible": true,
		"hunger_recovery": 25.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 8.0,
		"description": "Лёгкие и не портятся — запас в рюкзак на дальнюю вылазку (+25% сытости, +8 энергии)."
	},

	# --- Глава 2: блюда печи-кухни (качество на уровень выше костра) ---
	"potato_mushroom_dish": {
		"id": "potato_mushroom_dish",
		"name": "Картошка с грибами",
		"icon": "🥘",
		"category": "food",
		"weight": 0.45,
		"max_stack": 20,
		"sell_price": 62,
		"is_edible": true,
		"hunger_recovery": 65.0,
		"thirst_recovery": 10.0,
		"energy_bonus": 25.0,
		"description": "Горячее блюдо печи-кухни из картофеля и грибов (+65% сытости, +25 энергии)."
	},
	"mushroom_soup": {
		"id": "mushroom_soup",
		"name": "Грибной суп",
		"icon": "🍲",
		"category": "food",
		"weight": 0.45,
		"max_stack": 20,
		"sell_price": 60,
		"is_edible": true,
		"hunger_recovery": 55.0,
		"thirst_recovery": 35.0,
		"energy_bonus": 18.0,
		"description": "Наваренный в печи суп с морковью (+55% сытости, +35% жажды, +18 энергии)."
	},
	"glazed_carrot": {
		"id": "glazed_carrot",
		"name": "Глазурованная морковь",
		"icon": "🥕",
		"category": "food",
		"weight": 0.3,
		"max_stack": 30,
		"sell_price": 48,
		"is_edible": true,
		"hunger_recovery": 45.0,
		"thirst_recovery": 25.0,
		"energy_bonus": 16.0,
		"description": "Морковь в ягодной глазури (+45% сытости, +25% жажды, +16 энергии)."
	},
	"potato_pie": {
		"id": "potato_pie",
		"name": "Картофельный пирог",
		"icon": "🥧",
		"category": "food",
		"weight": 0.5,
		"max_stack": 20,
		"sell_price": 88,
		"is_edible": true,
		"hunger_recovery": 75.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 30.0,
		"description": "Выпечка печи-кухни с тестом из пшеницы (+75% сытости, +30 энергии)."
	},
	"berry_compote": {
		"id": "berry_compote",
		"name": "Ягодный компот",
		"icon": "🫗",
		"category": "food",
		"weight": 0.35,
		"max_stack": 20,
		"sell_price": 52,
		"is_edible": true,
		"is_drinkable": true,
		"hunger_recovery": 10.0,
		"thirst_recovery": 45.0,
		"energy_bonus": 12.0,
		"health_bonus": 6.0,
		"description": "Ягоды, проваренные в чистой воде (+45% жажды, +12 энергии, +6 здоровья)."
	},
	"mushroom_sauce": {
		"id": "mushroom_sauce",
		"name": "Грибной соус",
		"icon": "🫙",
		"category": "component",
		"weight": 0.2,
		"max_stack": 20,
		"sell_price": 45,
		"is_edible": true,
		"hunger_recovery": 12.0,
		"thirst_recovery": 0.0,
		"energy_bonus": 6.0,
		"description": "Соус-приправа из протёртых грибов. Ингредиент для блюд кухни Главы 5."
	},
	"berry_sauce": {
		"id": "berry_sauce",
		"name": "Ягодный соус",
		"icon": "🫗",
		"category": "component",
		"weight": 0.2,
		"max_stack": 20,
		"sell_price": 42,
		"is_edible": true,
		"hunger_recovery": 10.0,
		"thirst_recovery": 6.0,
		"energy_bonus": 5.0,
		"description": "Кисло-сладкая ягодная приправа. Ингредиент для блюд кухни Главы 5."
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
	},

	# --- Оснастка и инструменты Lv.2 (Этап 11, разделы 54, 55) ---
	"wooden_handle": {
		"id": "wooden_handle",
		"name": "Деревянная ручка",
		"icon": "🪵",
		"category": "component",
		"weight": 0.2,
		"max_stack": 30,
		"sell_price": 8,
		"description": "Обструганное и отшлифованное деревянное топорище для монтажа ручного инструмента."
	},
	"bolt": {
		"id": "bolt",
		"name": "Металлический болт",
		"icon": "🔩",
		"category": "component",
		"weight": 0.05,
		"max_stack": 50,
		"sell_price": 12,
		"description": "Прочный крепежный болт с гайкой из переплавленного металлолома для сборки узлов и инструментов."
	},
	"fabric": {
		"id": "fabric",
		"name": "Плотная ткань",
		"icon": "🧵",
		"category": "component",
		"weight": 0.3,
		"max_stack": 30,
		"sell_price": 22,
		"description": "Сотканное парусиновое полотно из растительных волокон для защитной экипировки и рюкзаков."
	},
	"leather_strap": {
		"id": "leather_strap",
		"name": "Усиленный ремень",
		"icon": "🎗️",
		"category": "component",
		"weight": 0.2,
		"max_stack": 25,
		"sell_price": 18,
		"description": "Прочная плетеная крепежная стропа для ремней рюкзака и подвески снаряжения."
	},
	"iron_axe": {
		"id": "iron_axe",
		"name": "Железный топор",
		"icon": "🪓",
		"texture": "res://assets/tools/axe_icon.png",
		"category": "tool",
		"tool_type": "axe",
		"level": 2,
		"power": 2.0,
		"weight": 1.5,
		"max_stack": 1,
		"sell_price": 95,
		"description": "Кованый топор с лезвием из закалённого железа. Рубит деревья вдвое быстрее, снижает усталость и даёт +1 древесину."
	},
	"iron_pickaxe": {
		"id": "iron_pickaxe",
		"name": "Железная кирка",
		"icon": "⛏️",
		"texture": "res://assets/tools/pickaxe_icon.png",
		"category": "tool",
		"tool_type": "pickaxe",
		"level": 2,
		"power": 2.0,
		"weight": 1.8,
		"max_stack": 1,
		"sell_price": 95,
		"description": "Закалённая металлическая кирка. Раскалывает камни за 2 удара вместо 3, снижает трату энергии и даёт +1 ресурс."
	},
	"iron_shovel": {
		"id": "iron_shovel",
		"name": "Железная мотыга",
		"icon": "🪚",
		"texture": "res://assets/tools/hoe_icon.tres",
		"category": "tool",
		"tool_type": "shovel",
		"level": 2,
		"power": 2.0,
		"weight": 1.2,
		"max_stack": 1,
		"sell_price": 95,
		"description": "Кованое стальное полотно мотыги. Вскапывает грядки вдвое легче (-50% энергии) и ускоряет сбор глины и песка."
	},
	"reinforced_bucket": {
		"id": "reinforced_bucket",
		"name": "Усиленное ведро",
		"icon": "🪣",
		"texture": "res://assets/tools/bucket_icon.png",
		"category": "tool",
		"tool_type": "bucket",
		"level": 2,
		"power": 2.0,
		"weight": 1.2,
		"max_stack": 1,
		"sell_price": 110,
		"description": "Окованное герметичное ведро со стальными обручами. Черпает сразу двойную порцию чистой воды."
	},
	"large_backpack": {
		"id": "large_backpack",
		"name": "Большой рюкзак",
		"icon": "🎒",
		"category": "equipment",
		"tool_type": "backpack",
		"level": 2,
		"slots": 20,
		"weight": 0.8,
		"max_stack": 1,
		"sell_price": 140,
		"description": "Экспедиционный рюкзак с боковыми карманами (20 слотов) и усиленными лямками (грузоподъемность: 75 кг)."
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

static func is_fruit_sapling(item_id: String) -> bool:
	if ITEMS.has(item_id):
		return ITEMS[item_id].has("tree_type")
	return false

static func get_tree_type(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id].get("tree_type", "")
	return ""

