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
		"duration": 20.0,
		"energy_cost": 2.0,
		"description": "Измельчает 2 камня в 1 порцию тонкой каменной пыли."
	},
	"crush_wood": {
		"id": "crush_wood",
		"name": "Древесина → Опилки",
		"machine": "crusher",
		"inputs": {"wood": 2},
		"outputs": {"sawdust": 3},
		"duration": 18.0,
		"energy_cost": 2.0,
		"description": "Перемалывает 2 бревна в 3 порции древесных опилок."
	},
	"crush_coal": {
		"id": "crush_coal",
		"name": "Уголь → Угольный порошок (x2)",
		"machine": "crusher",
		"inputs": {"coal": 1},
		"outputs": {"coal_powder": 2},
		"duration": 16.0,
		"energy_cost": 2.0,
		"description": "Измельчение кускового каменного угля в мелкодисперсный порошок для смесей и фильтров."
	},
	"craft_brick": {
		"id": "craft_brick",
		"name": "Формовка: Говённый кирпич (x2)",
		"machine": "workbench",
		"inputs": {"stone_dust": 1, "clay": 2, "water": 1},
		"outputs": {"poor_brick": 2},
		"duration": 30.0,
		"energy_cost": 3.0,
		"description": "Замес двух порций глины с каменной пылью и водой в формы для сырого кирпича."
	},
	"craft_mortar": {
		"id": "craft_mortar",
		"name": "Замес: Строительный раствор (x2)",
		"machine": "workbench",
		"inputs": {"stone_dust": 2, "sand": 1, "water": 1},
		"outputs": {"mortar": 2},
		"duration": 25.0,
		"energy_cost": 2.0,
		"description": "Каменная пыль, песок и вода — раствор для кладки. Без него кирпичные стены дома и склада не встанут."
	},
	"craft_briquette": {
		"id": "craft_briquette",
		"name": "Прессование: Топливные брикеты (x2)",
		"machine": "workbench",
		"inputs": {"sawdust": 4, "clay": 1},
		"outputs": {"fuel_briquette": 2},
		"duration": 30.0,
		"energy_cost": 3.0,
		"description": "Прессование опилок с глиной-связкой в плотные блоки топлива. Угольные брикеты выгоднее."
	},
	"craft_whetstone": {
		"id": "craft_whetstone",
		"name": "Обработка: Точильный брусок (x1)",
		"machine": "workbench",
		"inputs": {"stone": 2, "sand": 1},
		"outputs": {"whetstone": 1},
		"duration": 20.0,
		"energy_cost": 2.0,
		"description": "Шлифовка прочного точильного бруска для полевого обслуживания инструмента. Можно изготовить на верстаке или прямо в меню рюкзака (2 камня, 1 песок)."
	},
	"sharpen_axe": {
		"id": "sharpen_axe",
		"name": "Заточка: Топор (100%)",
		"machine": "workbench",
		"inputs": {"water": 1},
		"outputs": {},
		"duration": 15.0,
		"energy_cost": 2.0,
		"description": "Обильное смачивание точильного круга водой и выведение идеальной режущей кромки топора."
	},
	"sharpen_pickaxe": {
		"id": "sharpen_pickaxe",
		"name": "Заточка: Кирка (100%)",
		"machine": "workbench",
		"inputs": {"water": 1},
		"outputs": {},
		"duration": 15.0,
		"energy_cost": 2.0,
		"description": "Заточка и правка закалённых клювов кирки на верстаке до идеального состояния."
	},
	"sharpen_shovel": {
		"id": "sharpen_shovel",
		"name": "Заточка: Мотыга (100%)",
		"machine": "workbench",
		"inputs": {"water": 1},
		"outputs": {},
		"duration": 15.0,
		"energy_cost": 2.0,
		"description": "Правка режущей кромки лопасти мотыги для лёгкого срезания дерна и грунта."
	},
	"smelt_brick": {
		"id": "smelt_brick",
		"name": "Обжиг: Обожжённый кирпич (x2)",
		"machine": "furnace",
		"inputs": {"poor_brick": 2},
		"outputs": {"fired_brick": 2},
		"duration": 50.0,
		"energy_cost": 2.0,
		"description": "Закалка сырых кирпичей в раскаленной печи. Топливо (уголь, дрова, брикеты) кладётся в топливные слоты печи."
	},
	"smelt_glass": {
		"id": "smelt_glass",
		"name": "Выплавка: Листовое стекло (x1)",
		"machine": "furnace",
		"inputs": {"sand": 3},
		"outputs": {"glass": 1},
		"duration": 55.0,
		"energy_cost": 2.5,
		"description": "Высокотемпературное плавление трёх порций кварцевого песка в прозрачное стекло. Топливо — в топливных слотах печи."
	},
	"craft_glass_bottle": {
		"id": "craft_glass_bottle",
		"name": "Выдувание: Стеклянная бутылка (x2)",
		"machine": "furnace",
		"inputs": {"glass": 1},
		"outputs": {"glass_bottle": 2},
		"duration": 22.0,
		"energy_cost": 2.0,
		"description": "Формовка и выдувание двух стеклянных бутылок из заготовки листового стекла."
	},
	"smelt_clay_pot": {
		"id": "smelt_clay_pot",
		"name": "Обжиг: Глиняный горшок (x1)",
		"machine": "furnace",
		"inputs": {"clay": 2},
		"outputs": {"clay_pot": 1},
		"duration": 25.0,
		"energy_cost": 2.5,
		"description": "Запекание формованного глиняного горшка в высокотемпературной печи."
	},
	"smelt_iron": {
		"id": "smelt_iron",
		"name": "Переплавка: Железный слиток (x1)",
		"machine": "furnace",
		"inputs": {"metal_scrap": 3},
		"outputs": {"iron_ingot": 1},
		"duration": 75.0,
		"energy_cost": 3.0,
		"description": "Переплавка ржавого металлолома в слиток: уходит много топлива — руда с углём выгоднее."
	},
	"smelt_iron_ore": {
		"id": "smelt_iron_ore",
		"name": "Плавка руды: Железный слиток (x1)",
		"machine": "furnace",
		"inputs": {"iron_ore": 2},
		"outputs": {"iron_ingot": 1},
		"duration": 60.0,
		"energy_cost": 3.0,
		"description": "Выплавка железа из руды жилы — основной источник слитков. Уголь загружается в топливный слот печи."
	},
	"press_coal_briquette": {
		"id": "press_coal_briquette",
		"name": "Прессование: Угольные брикеты (x3)",
		"machine": "workbench",
		"inputs": {"coal": 2, "sawdust": 1},
		"outputs": {"fuel_briquette": 3},
		"duration": 25.0,
		"energy_cost": 2.0,
		"description": "Угольная крошка с опилками прессуется в плотные топливные брикеты."
	},
	"filter_water": {
		"id": "filter_water",
		"name": "Песчаная фильтрация: Чистая вода (x2)",
		"machine": "water_filter",
		"inputs": {"water": 2, "sand": 1},
		"outputs": {"clean_water": 2},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Очистка мутной сырой воды через слой кварцевого песка в чистую питьевую воду."
	},
	"mineral_filter_water": {
		"id": "mineral_filter_water",
		"name": "Глубокая фильтрация: Чистая вода (x4)",
		"machine": "water_filter",
		"inputs": {"water": 3, "sand": 1, "stone_dust": 1},
		"outputs": {"clean_water": 4},
		"duration": 45.0,
		"energy_cost": 2.0,
		"description": "Многоступенчатая фильтрация песком и каменной пылью с повышенным выходом чистой воды."
	},
	"bottle_water": {
		"id": "bottle_water",
		"name": "Розлив: Бутилированная вода (x1)",
		"machine": "workbench",
		"inputs": {"clean_water": 1, "glass_bottle": 1},
		"outputs": {"bottled_water": 1},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Розлив фильтрованной воды в герметичные стеклянные бутылки для длительного хранения и продажи."
	},
	"craft_glassware_set": {
		"id": "craft_glassware_set",
		"name": "Сборка: Комплект стеклянной посуды (x1)",
		"machine": "workbench",
		"inputs": {"glass": 2, "glass_bottle": 1},
		"outputs": {"glassware_set": 1},
		"duration": 30.0,
		"energy_cost": 3.0,
		"description": "Тонкая шлифовка и комплектование набора посуды из листового стекла и бутылки."
	},
	"craft_coal_briquette": {
		"id": "craft_coal_briquette",
		"name": "Прессование: Угольные брикеты (x3)",
		"machine": "workbench",
		"inputs": {"coal_powder": 2, "clay": 1},
		"outputs": {"fuel_briquette": 3},
		"duration": 28.0,
		"energy_cost": 2.5,
		"description": "Прессование тонкого угольного порошка с глиной-связкой в плотные высококалорийные брикеты."
	},
	"craft_fertilizer": {
		"id": "craft_fertilizer",
		"name": "Смешивание: Био-удобрение (x2)",
		"machine": "workbench",
		"inputs": {"clay": 1, "sawdust": 2, "water": 1},
		"outputs": {"fertilizer": 2},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Смешивание обогащенной глины, органических опилок и воды в стимулирующее био-удобрение."
	},
	"extract_carrot_seeds": {
		"id": "extract_carrot_seeds",
		"name": "Селекция: Семена моркови (x2)",
		"machine": "workbench",
		"inputs": {"carrot": 1},
		"outputs": {"seeds_carrot": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Сбор и сушка отборных сортовых семян из выращенной моркови для повторного посева."
	},
	"extract_potato_seeds": {
		"id": "extract_potato_seeds",
		"name": "Подготовка: Семенной картофель (x2)",
		"machine": "workbench",
		"inputs": {"potato": 1},
		"outputs": {"seeds_potato": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Отбор и деление клубней картофеля на пророщенный посадочный материал."
	},
	"extract_wheat_seeds": {
		"id": "extract_wheat_seeds",
		"name": "Обмолот: Семена пшеницы (x3)",
		"machine": "workbench",
		"inputs": {"wheat": 1},
		"outputs": {"seeds_wheat": 3},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Ручной обмолот пшеничного снопа для получения чистого посевного зерна."
	},
	"extract_sunflower_seeds": {
		"id": "extract_sunflower_seeds",
		"name": "Селекция: Семена подсолнуха (x3)",
		"machine": "workbench",
		"inputs": {"sunflower_seeds": 1},
		"outputs": {"seeds_sunflower": 3},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Калибровка и сушка крупных семечек подсолнуха для весеннего посева."
	},
	"extract_onion_seeds": {
		"id": "extract_onion_seeds",
		"name": "Селекция: Семена лука (x2)",
		"machine": "workbench",
		"inputs": {"onion": 1},
		"outputs": {"seeds_onion": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Заготовка семян репчатого лука из спелых луковиц."
	},
	"extract_cabbage_seeds": {
		"id": "extract_cabbage_seeds",
		"name": "Селекция: Семена капусты (x2)",
		"machine": "workbench",
		"inputs": {"cabbage": 1},
		"outputs": {"seeds_cabbage": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Отбор стручков семян из кочана капусты."
	},
	"extract_tomato_seeds": {
		"id": "extract_tomato_seeds",
		"name": "Селекция: Семена томата (x3)",
		"machine": "workbench",
		"inputs": {"tomato": 1},
		"outputs": {"seeds_tomato": 3},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Смыв мякоти и сушка семян сочных спелых помидоров."
	},
	"extract_pepper_seeds": {
		"id": "extract_pepper_seeds",
		"name": "Селекция: Семена перца (x2)",
		"machine": "workbench",
		"inputs": {"pepper": 1},
		"outputs": {"seeds_pepper": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Извлечение и просушка семян сладкого болгарского перца."
	},
	"extract_bean_seeds": {
		"id": "extract_bean_seeds",
		"name": "Селекция: Семена фасоли (x3)",
		"machine": "workbench",
		"inputs": {"bean": 1},
		"outputs": {"seeds_bean": 3},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Лущение спелых стручков фасоли на посевные бобы."
	},
	"extract_herbs_seeds": {
		"id": "extract_herbs_seeds",
		"name": "Селекция: Семена пряных трав (x2)",
		"machine": "workbench",
		"inputs": {"herbs": 1},
		"outputs": {"seeds_herbs": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Сбор семян из цветущих соцветий пряных трав."
	},
	"extract_corn_seeds": {
		"id": "extract_corn_seeds",
		"name": "Селекция: Семена кукурузы (x2)",
		"machine": "workbench",
		"inputs": {"corn": 1},
		"outputs": {"seeds_corn": 2},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Вылущивание отборных зёрен из спелого початка кукурузы."
	},
	"extract_pumpkin_seeds": {
		"id": "extract_pumpkin_seeds",
		"name": "Селекция: Семена тыквы (x3)",
		"machine": "workbench",
		"inputs": {"pumpkin": 1},
		"outputs": {"seeds_pumpkin": 3},
		"duration": 15.0,
		"energy_cost": 1.0,
		"description": "Извлечение и сушка крупных тыквенных семечек."
	},
	"craft_apple_sapling": {
		"id": "craft_apple_sapling",
		"name": "Прививка: Саженец яблони (x1)",
		"machine": "workbench",
		"inputs": {"apple": 2, "wood": 1},
		"outputs": {"apple_sapling": 1},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Черенкование и прививка плодового черенка яблони на подвой из древесины."
	},
	"craft_pear_sapling": {
		"id": "craft_pear_sapling",
		"name": "Прививка: Саженец груши (x1)",
		"machine": "workbench",
		"inputs": {"pear": 2, "wood": 1},
		"outputs": {"pear_sapling": 1},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Прививка садовой сортовой груши на крепкий подвой."
	},
	"craft_cherry_sapling": {
		"id": "craft_cherry_sapling",
		"name": "Прививка: Саженец вишни (x1)",
		"machine": "workbench",
		"inputs": {"cherry": 4, "wood": 1},
		"outputs": {"cherry_sapling": 1},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Укоренение и прививка побега вишнёвого дерева."
	},
	"craft_apricot_sapling": {
		"id": "craft_apricot_sapling",
		"name": "Прививка: Саженец абрикоса (x1)",
		"machine": "workbench",
		"inputs": {"apricot": 2, "wood": 1},
		"outputs": {"apricot_sapling": 1},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Прививка плодового черенка абрикоса на подвой из древесины."
	},
	"bake_bread": {
		"id": "bake_bread",
		"name": "Выпечка: Домашний хлеб (x2)",
		"machine": "furnace",
		"inputs": {"wheat": 2, "clean_water": 1},
		"outputs": {"bread": 2},
		"duration": 45.0,
		"energy_cost": 2.5,
		"description": "Замес теста из молотой пшеницы и чистой воды с выпечкой подового хлеба. Топливо — в топливных слотах печи."
	},
	"dry_apricots": {
		"id": "dry_apricots",
		"name": "Сушка: Курага (x2)",
		"machine": "furnace",
		"inputs": {"apricot": 3},
		"outputs": {"dried_apricot": 2},
		"duration": 35.0,
		"energy_cost": 1.0,
		"description": "Термическая сушка спелых абрикосов в печи: получается сладкая питательная курага."
	},
	"cook_apricot_compote": {
		"id": "cook_apricot_compote",
		"name": "Варка: Абрикосовый компот (x2)",
		"machine": "furnace",
		"inputs": {"apricot": 3, "clean_water": 1},
		"outputs": {"apricot_compote": 2},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Сладкий наваристый компот из свежих абрикосов, сваренный в печи: отлично утоляет жажду и восстанавливает силы."
	},
	"cook_apricot_pie": {
		"id": "cook_apricot_pie",
		"name": "Выпечка: Абрикосовый пирог (x2)",
		"machine": "furnace",
		"inputs": {"apricot": 3, "wheat": 2, "clean_water": 1},
		"outputs": {"apricot_pie": 2},
		"duration": 55.0,
		"energy_cost": 3.0,
		"description": "Праздничный пирог с сочными абрикосами из печи: превосходная сытность."
	},

	# --- Компоненты улучшенных станков (доступны со Lv.2, min_level) ---
	"craft_steel_plate": {
		"id": "craft_steel_plate",
		"name": "Закалка: Стальная пластина (x1)",
		"machine": "workbench",
		"min_level": 2,
		"inputs": {"iron_plate": 2, "coal": 1},
		"outputs": {"steel_plate": 1},
		"duration": 40.0,
		"energy_cost": 2.5,
		"description": "Холодная закалка двух пластин с угольной присадкой на улучшенном верстаке. Деталь качественного ремонта и передовых станков."
	},
	"craft_precision_gear": {
		"id": "craft_precision_gear",
		"name": "Обкатка: Точная шестерня (x1)",
		"machine": "workbench",
		"min_level": 2,
		"inputs": {"gear": 2, "iron_plate": 1},
		"outputs": {"precision_gear": 1},
		"duration": 50.0,
		"energy_cost": 3.0,
		"description": "Прецизионная обкатка пары шестерён со шлифовкой зубьев. Без улучшенного верстака точность не удержать."
	},
	"smelt_steel": {
		"id": "smelt_steel",
		"name": "Передел: Стальной слиток (x1)",
		"machine": "furnace",
		"min_level": 2,
		"inputs": {"iron_ingot": 2},
		"outputs": {"steel_ingot": 1},
		"duration": 90.0,
		"energy_cost": 3.5,
		"description": "Двойной передел железа с углём из топливных слотов улучшенной печи. Долгий цикл, но сталь того стоит."
	},
	"brew_healing_water": {
		"id": "brew_healing_water",
		"name": "Настой: Целебная вода (x1)",
		"machine": "water_filter",
		"min_level": 2,
		"inputs": {"clean_water": 2, "glass": 1},
		"outputs": {"healing_water": 1},
		"duration": 35.0,
		"energy_cost": 1.5,
		"description": "Минеральный настой на глубоко очищенной воде в стерильной таре. Утоляет жажду и затягивает ссадины."
	},

	# --- Электрогенерация и освещение (Этап 10) ---
	"craft_copper_wire": {
		"id": "craft_copper_wire",
		"name": "Прокатка: Медный провод (x2)",
		"machine": "workbench",
		"inputs": {"metal_scrap": 1},
		"outputs": {"copper_wire": 2},
		"duration": 25.0,
		"energy_cost": 1.0,
		"description": "Вытяжка и изоляция медной электропроводки из цветных обрезков лома на верстаке."
	},
	"craft_iron_plate": {
		"id": "craft_iron_plate",
		"name": "Ковка: Металлическая пластина (x2)",
		"machine": "workbench",
		"inputs": {"iron_ingot": 1},
		"outputs": {"iron_plate": 2},
		"duration": 35.0,
		"energy_cost": 1.5,
		"description": "Холодная ковка и прокатка железного слитка в две плоские конструкционные пластины."
	},
	"craft_gear": {
		"id": "craft_gear",
		"name": "Выточка: Шестерня редуктора (x2)",
		"machine": "workbench",
		"inputs": {"iron_ingot": 1, "metal_scrap": 1},
		"outputs": {"gear": 2},
		"duration": 45.0,
		"energy_cost": 2.0,
		"description": "Выпиливание и шлифовка прочных зубчатых колес для поворотного механизма и вала ветряка."
	},
	"craft_battery_cell": {
		"id": "craft_battery_cell",
		"name": "Сборка: Аккумуляторный элемент (x1)",
		"machine": "workbench",
		"inputs": {"iron_plate": 1, "copper_wire": 2, "clay": 1, "coal": 1},
		"outputs": {"battery_cell": 1},
		"duration": 60.0,
		"energy_cost": 2.0,
		"description": "Электролитная ячейка в металлическом корпусе: угольный электрод, глиняный сепаратор и медные клеммы."
	},
	"craft_street_lamp": {
		"id": "craft_street_lamp",
		"name": "Сборка: Уличный фонарь (x1)",
		"machine": "workbench",
		"inputs": {"wood": 2, "glass": 1, "copper_wire": 1, "iron_plate": 1},
		"outputs": {"street_lamp_item": 1},
		"duration": 60.0,
		"energy_cost": 2.5,
		"description": "Изготовление уличного фонарного столба с защитным стеклянным плафоном и проводкой."
	},

	# --- Компоненты оснастки и инструменты Lv.2 (Этап 11) ---
	"craft_wooden_handle": {
		"id": "craft_wooden_handle",
		"name": "Выточка: Деревянная рукоять (x2)",
		"machine": "workbench",
		"inputs": {"wood": 2},
		"outputs": {"wooden_handle": 2},
		"duration": 20.0,
		"energy_cost": 1.0,
		"description": "Вытачивание гладких эргономичных деревянных рукоятей для инструментов из обтесанного полена."
	},
	"craft_bolt": {
		"id": "craft_bolt",
		"name": "Нарезка: Металлический болт (x2)",
		"machine": "workbench",
		"inputs": {"metal_scrap": 1},
		"outputs": {"bolt": 2},
		"duration": 20.0,
		"energy_cost": 1.0,
		"description": "Нарезка резьбы и ковка металлических болтов с гайками из отборного металлического лома."
	},
	"craft_fabric": {
		"id": "craft_fabric",
		"name": "Плетение: Плотная ткань (x1)",
		"machine": "workbench",
		"inputs": {"wheat": 3},
		"outputs": {"fabric": 1},
		"duration": 40.0,
		"energy_cost": 1.5,
		"description": "Плетение и прессование плотного растительного парусинового волокна из стеблей пшеницы."
	},
	"craft_leather_strap": {
		"id": "craft_leather_strap",
		"name": "Сборка: Усиленный ремень (x2)",
		"machine": "workbench",
		"inputs": {"fabric": 1, "metal_scrap": 1},
		"outputs": {"leather_strap": 2},
		"duration": 30.0,
		"energy_cost": 1.0,
		"description": "Изготовление усиленных ремней и стяжек с металлическими пряжками."
	},
	"upgrade_iron_axe": {
		"id": "upgrade_iron_axe",
		"name": "Кузница: Железный топор Lv.2",
		"machine": "workbench",
		"inputs": {"iron_ingot": 2, "wooden_handle": 1, "bolt": 2},
		"outputs": {"iron_axe": 1},
		"duration": 90.0,
		"energy_cost": 4.0,
		"description": "Ковка и сборка тяжелого железного топора Lv.2: рубит в 2 раза быстрее, дает +1 древесину и экономит 35% сил."
	},
	"upgrade_iron_pickaxe": {
		"id": "upgrade_iron_pickaxe",
		"name": "Кузница: Железная кирка Lv.2",
		"machine": "workbench",
		"inputs": {"iron_ingot": 3, "wooden_handle": 1, "bolt": 2},
		"outputs": {"iron_pickaxe": 1},
		"duration": 100.0,
		"energy_cost": 4.0,
		"description": "Сборка закаленной железной кирки Lv.2: раскалывает породу вдвое быстрее, дает +1 ресурс и тратит меньше сил."
	},
	"upgrade_iron_shovel": {
		"id": "upgrade_iron_shovel",
		"name": "Кузница: Железная мотыга Lv.2",
		"machine": "workbench",
		"inputs": {"iron_ingot": 1, "iron_plate": 1, "wooden_handle": 1, "bolt": 1},
		"outputs": {"iron_shovel": 1},
		"duration": 80.0,
		"energy_cost": 3.5,
		"description": "Ковка усиленной железной мотыги Lv.2: снижает трату энергии на вскопку вдвое (-50% сил) и ускоряет добычу глины."
	},
	"upgrade_reinforced_bucket": {
		"id": "upgrade_reinforced_bucket",
		"name": "Сборка: Усиленное ведро Lv.2",
		"machine": "workbench",
		"inputs": {"iron_plate": 2, "bolt": 2, "wood": 1},
		"outputs": {"reinforced_bucket": 1},
		"duration": 70.0,
		"energy_cost": 3.0,
		"description": "Сборка герметичного ведра со стальными обручами: черпает сразу удвоенную порцию чистой воды из резервуара."
	},
	"upgrade_large_backpack": {
		"id": "upgrade_large_backpack",
		"name": "Пошив: Большой рюкзак Lv.2",
		"machine": "workbench",
		"inputs": {"fabric": 3, "leather_strap": 2, "bolt": 2},
		"outputs": {"large_backpack": 1},
		"duration": 120.0,
		"energy_cost": 4.0,
		"description": "Пошив вместительного экспедиционного рюкзака: расширяет вместимость до 20 слотов и грузоподъемность до 75 кг."
	},

	# --- Глава 2 «Первый дым»: костёр ---------------------------------------------------
	# Ручной станок без энергии: жарка, варка, сушка и кипячение. Базовые блюда,
	# обычное качество (мастер-план 7.3). Топливо — дрова/уголь/брикеты в одном слоте.
	"cook_baked_potato": {
		"id": "cook_baked_potato",
		"name": "Печёный картофель (x2)",
		"machine": "campfire",
		"inputs": {"potato": 2},
		"outputs": {"baked_potato": 2},
		"duration": 30.0,
		"energy_cost": 1.0,
		"description": "Клубни в золе на углях костра: сырой картофель становится сытным горячим блюдом."
	},
	"cook_fried_carrot": {
		"id": "cook_fried_carrot",
		"name": "Жареная морковь (x2)",
		"machine": "campfire",
		"inputs": {"carrot": 3, "water": 1},
		"outputs": {"fried_carrot": 2},
		"duration": 25.0,
		"energy_cost": 1.0,
		"description": "Морковь нарезается и обжаривается на сковородке из листа — быстрый перекус в дорогу."
	},
	"cook_vegetable_soup": {
		"id": "cook_vegetable_soup",
		"name": "Овощной суп (x2)",
		"machine": "campfire",
		"inputs": {"carrot": 1, "potato": 1, "water": 2},
		"outputs": {"vegetable_soup": 2},
		"duration": 45.0,
		"energy_cost": 1.5,
		"description": "Горячая похлёбка в котелке над огнём: одновременно сытость и жажда."
	},
	"cook_berry_brew": {
		"id": "cook_berry_brew",
		"name": "Ягодный отвар (x2)",
		"machine": "campfire",
		"inputs": {"red_berry": 4, "water": 1},
		"outputs": {"berry_brew": 2},
		"duration": 20.0,
		"energy_cost": 0.5,
		"description": "Ягоды, залитые кипятком в котелке: быстрый горячий настой, восполняет жажду."
	},
	"cook_mushroom_stew": {
		"id": "cook_mushroom_stew",
		"name": "Грибная похлёбка (x2)",
		"machine": "campfire",
		"inputs": {"mushroom": 2, "water": 1},
		"outputs": {"mushroom_stew": 2},
		"duration": 35.0,
		"energy_cost": 1.0,
		"description": "Первый настоящий суп из лесных грибов — ради него и нужен костёр."
	},
	"dry_mushrooms": {
		"id": "dry_mushrooms",
		"name": "Сушка грибов (x2)",
		"machine": "campfire",
		"inputs": {"mushroom": 3},
		"outputs": {"dried_mushroom": 2},
		"duration": 40.0,
		"energy_cost": 0.5,
		"description": "Грибы сушатся над огнём и становятся лёгкой консервой: не портятся и не занимают места."
	},
	"boil_water": {
		"id": "boil_water",
		"name": "Кипячёная вода (x2)",
		"machine": "campfire",
		"inputs": {"water": 2},
		"outputs": {"clean_water": 2},
		"duration": 20.0,
		"energy_cost": 0.5,
		"description": "Альтернатива фильтру: довести сырую воду до кипения в котелке. Медленнее, зато работает без станка."
	},

	# --- Глава 2: печь-кухня (улучшенный станок готовки) --------------------------------
	# Средние блюда и соусы, качество на уровень выше костра (мастер-план 7.3).
	"cook_potato_mushroom": {
		"id": "cook_potato_mushroom",
		"name": "Картошка с грибами (x2)",
		"machine": "kitchen_stove",
		"inputs": {"potato": 2, "mushroom": 1, "clean_water": 1},
		"outputs": {"potato_mushroom_dish": 2},
		"duration": 40.0,
		"energy_cost": 2.0,
		"description": "Горячее блюдо с равномерной подачей: печь держит жар и картошка не разваривается в кашу."
	},
	"cook_mushroom_soup": {
		"id": "cook_mushroom_soup",
		"name": "Грибной суп (x2)",
		"machine": "kitchen_stove",
		"inputs": {"mushroom": 3, "carrot": 1, "clean_water": 2},
		"outputs": {"mushroom_soup": 2},
		"duration": 45.0,
		"energy_cost": 2.0,
		"description": "Наваренный суп с морковью — лучшая замена костровой похлёбке по сытости и жажде."
	},
	"cook_glazed_carrot": {
		"id": "cook_glazed_carrot",
		"name": "Глазурованная морковь (x3)",
		"machine": "kitchen_stove",
		"inputs": {"carrot": 4, "red_berry": 2, "clean_water": 1},
		"outputs": {"glazed_carrot": 3},
		"duration": 35.0,
		"energy_cost": 2.0,
		"description": "Ягодная глазурь на тушёной моркови — сладко, сытно и отлично утоляет жажду."
	},
	"cook_potato_pie": {
		"id": "cook_potato_pie",
		"name": "Картофельный пирог (x2)",
		"machine": "kitchen_stove",
		"inputs": {"potato": 3, "wheat": 2, "clean_water": 1},
		"outputs": {"potato_pie": 2},
		"duration": 60.0,
		"energy_cost": 3.0,
		"description": "Выпечка в духовом шкафу печи-кухни: самая сытная еда Главы 2."
	},
	"cook_berry_compote": {
		"id": "cook_berry_compote",
		"name": "Ягодный компот (x2)",
		"machine": "kitchen_stove",
		"inputs": {"red_berry": 4, "clean_water": 2},
		"outputs": {"berry_compote": 2},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Проваренный в чистой воде ягодный компот: восполняет жажду лучше кострового отвара."
	},
	"cook_mushroom_sauce": {
		"id": "cook_mushroom_sauce",
		"name": "Грибной соус (x2)",
		"machine": "kitchen_stove",
		"inputs": {"mushroom": 3, "clean_water": 1},
		"outputs": {"mushroom_sauce": 2},
		"duration": 35.0,
		"energy_cost": 2.0,
		"min_level": 2,
		"description": "Протёртые грибы с бульоном — приправа для блюд кухни Главы 5."
	},
	"cook_berry_sauce": {
		"id": "cook_berry_sauce",
		"name": "Ягодный соус (x2)",
		"machine": "kitchen_stove",
		"inputs": {"red_berry": 5, "clean_water": 1},
		"outputs": {"berry_sauce": 2},
		"duration": 30.0,
		"energy_cost": 1.5,
		"min_level": 2,
		"description": "Уваренная ягодная приправа — сладкая основа для выпечки и соусов Главы 5."
	},

	# --- Пивоварение и виноделие ---
	"mash_beer_wort": {
		"id": "mash_beer_wort",
		"name": "Затирание: Сырое пивное сусло",
		"machine": "campfire",
		"inputs": {"wheat": 3, "clean_water": 1, "clay_pot": 1},
		"outputs": {"beer_wort_raw": 1},
		"duration": 25.0,
		"energy_cost": 2.0,
		"description": "Затирание молотой пшеницы с горячей чистой водой в горшке. Получение сладкого солодового сусла."
	},
	"boil_beer_wort": {
		"id": "boil_beer_wort",
		"name": "Варка: Охмелённое сусло",
		"machine": "campfire",
		"inputs": {"beer_wort_raw": 1, "herbs": 1},
		"outputs": {"beer_wort_boiled": 1},
		"duration": 30.0,
		"energy_cost": 2.0,
		"description": "Кипячение сырого сусла с душистыми пряными травами на костре. Подготовка сусла к брожению на складе."
	},
	"prepare_berry_must": {
		"id": "prepare_berry_must",
		"name": "Отжим: Ягодное сусло",
		"machine": "workbench",
		"inputs": {"red_berry": 5, "clean_water": 1, "clay_pot": 1},
		"outputs": {"berry_must": 1},
		"duration": 20.0,
		"energy_cost": 2.0,
		"description": "Давление спелых сочных ягод в глиняном горшке с родниковой водой для будущего вина."
	},
	"prepare_grain_wash": {
		"id": "prepare_grain_wash",
		"name": "Замес: Зерновой затор (брага)",
		"machine": "workbench",
		"inputs": {"wheat": 3, "clean_water": 1, "clay_pot": 1},
		"outputs": {"grain_wash": 1},
		"duration": 20.0,
		"energy_cost": 2.0,
		"description": "Подготовка зернового затора из злаков и воды. Отправляется на склад для созревания браги."
	},

	# --- Дистилляция и настойки (Дистиллятор) ---
	"distill_moonshine": {
		"id": "distill_moonshine",
		"name": "Перегонка: Домашний самогон (x2)",
		"machine": "distiller",
		"inputs": {"fermented_wash": 1, "glass_bottle": 2},
		"outputs": {"moonshine": 2},
		"duration": 40.0,
		"energy_cost": 2.0,
		"description": "Дистилляция сброженной браги в медном кубе. Получение крепкого деревенского самогона (45°)."
	},
	"distill_spirit": {
		"id": "distill_spirit",
		"name": "Ректификация: Очищенный спирт (95°)",
		"machine": "distiller",
		"inputs": {"moonshine": 2, "glass_bottle": 1},
		"outputs": {"pure_spirit": 1},
		"duration": 50.0,
		"energy_cost": 2.5,
		"description": "Вторая дробная перегонка самогона с отсечением голов и хвостов. Чистейший спирт для медицины и настоек."
	},
	"filter_spirit": {
		"id": "filter_spirit",
		"name": "Угольная фильтрация: Чистый спирт",
		"machine": "distiller",
		"inputs": {"moonshine": 1, "coal_powder": 1, "glass_bottle": 1},
		"outputs": {"pure_spirit": 1},
		"duration": 35.0,
		"energy_cost": 1.5,
		"description": "Тонкая очистка самогона через угольную колонну до кристальной спиртовой чистоты."
	},
	"steep_blueberry": {
		"id": "steep_blueberry",
		"name": "Настаивание: Черничная настойка",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "blue_berry": 4, "glass_bottle": 1},
		"outputs": {"blueberry_tincture": 1},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Экстракция синих ягод в чистом спирту. Тонизирующая настойка для зрения и бодрости."
	},
	"steep_red_berry": {
		"id": "steep_red_berry",
		"name": "Настаивание: Брусничная настойка",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "red_berry": 4, "glass_bottle": 1},
		"outputs": {"red_berry_tincture": 1},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Ароматная ягодная настойка на спирту. Снимает усталость и ломоту в мышцах."
	},
	"steep_blackberry": {
		"id": "steep_blackberry",
		"name": "Настаивание: Ежевичная настойка",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "blackberry": 4, "glass_bottle": 1},
		"outputs": {"blackberry_tincture": 1},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Глубокая терпкая настойка на лесной ежевике, богатая витаминами и силой."
	},
	"steep_sea_buckthorn": {
		"id": "steep_sea_buckthorn",
		"name": "Настаивание: Облепиховый бальзам",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "sea_buckthorn": 4, "glass_bottle": 1},
		"outputs": {"sea_buckthorn_tincture": 1},
		"duration": 35.0,
		"energy_cost": 1.5,
		"description": "Концентрированный целебный бальзам на спирту и золотой облепихе (+30 к здоровью)."
	},
	"steep_mushroom": {
		"id": "steep_mushroom",
		"name": "Настаивание: Грибная настойка",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "mushroom": 3, "glass_bottle": 1},
		"outputs": {"mushroom_tincture": 1},
		"duration": 30.0,
		"energy_cost": 1.5,
		"description": "Старинный настой на свежих лесных грибах. Укрепляет выносливость и согревает тело."
	},
	"steep_special_mushroom": {
		"id": "steep_special_mushroom",
		"name": "Настаивание: Особая настойка на сушёных грибах",
		"machine": "distiller",
		"inputs": {"pure_spirit": 1, "dried_mushroom": 3, "herbs": 1, "glass_bottle": 1},
		"outputs": {"special_mushroom_tincture": 1},
		"duration": 40.0,
		"energy_cost": 2.0,
		"description": "Мощнейший таёжный эликсир из сушёных грибов и трав (+50 энергии, +20 здоровья)."
	}
}

## Рецепты станка данного типа, доступные на уровне level и выше.
## Компоненты улучшенных станков помечены min_level и появляются после апгрейда.
static func get_recipes_for_machine(machine_type: String, level: int = 1) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for r_id in RECIPES.keys():
		var r: Dictionary = RECIPES[r_id]
		if r.get("machine", "") != machine_type:
			continue
		if int(r.get("min_level", 1)) > maxi(1, level):
			continue
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
