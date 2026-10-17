extends RefCounted

## Культуры для делянок (FarmField): время роста в игровых часах, потребность
## в воде (диапазон «нормальной» влажности и расход влаги в час), засухоустойчивость,
## сезоны (заглушка Seasons), урожай, возврат семян и истощение почвы.
##
## Механика (по мотивам Stardew Valley, Farming Simulator и RimWorld):
## * Влага клетки 0–100. В диапазоне [moist_min, moist_max] культура растёт с полной
##   скоростью и копит «уход» (качество урожая). Суше нормы — медленно, совсем сухая
##   земля — рост стоит и копятся часы засухи: после wither_hours культура вянет.
##   Переувлажнение (дожди, перелив) тоже тормозит рост — у картофеля сильнее всех.
## * Плодородие клетки 0–100: урожай его истощает (soil_drain), удобрение возвращает.
##   Богатая почва ускоряет рост, бедная — замедляет и отнимает часть урожая.
## * Севооборот: другая культура после прошлой на той же клетке — +1 к урожаю и
##   вдвое меньше истощения; одна и та же подряд — истощает почву сильнее.
## * Качество: доля часов роста в норме влажности → «обычный», «хороший» (+1), «отличный» (+2).

const QUALITY_GOOD: float = 0.6
const QUALITY_GREAT: float = 0.85
const QUALITY_NAMES: Array[String] = ["обычный", "хороший", "отличный"]
const QUALITY_STARS: Array[String] = ["", "★", "★★"]

## Испарение с пустой вскопанной клетки, % в игровой час.
const EMPTY_EVAPORATION: float = 1.5
## Множители роста.
const DRY_SPEED: float = 0.4
const RICH_SOIL: float = 70.0
const POOR_SOIL: float = 25.0
const RICH_SPEED: float = 1.2
const POOR_SPEED: float = 0.75
const FERTILIZED_SPEED: float = 1.5
const FARMER_SPEED: float = 1.35
## Плодородие: новая делянка, удобрение, максимум.
const START_FERTILITY: float = 60.0
const FERTILIZER_BONUS: float = 35.0
## Восстановление плодородия незасаженной («под паром») клетки, % в игровой час.
const FALLOW_RECOVERY: float = 0.5

const CROPS: Dictionary = {
	# Лестница роста (игровые часы, 1 ч = 60 с реала): скороспелые дают
	# быстрый, но скромный урожай; поздние — долгий, но сытный и ценный.
	# 6–10 ч: зелень и бобовые → 12–18 ч: корнеплоды и летние овощи →
	# 20–24 ч: зерно и капуста → 28 ч: тыква-тяжеловес.
	"carrot": {
		"name": "Морковь",
		"seed": "seeds_carrot",
		"growth_hours": 10.0,
		"water_use": 5.0,
		"moist_min": 45.0,
		"moist_max": 90.0,
		"overwater_speed": 0.8,
		"wither_hours": 6.0,
		"seasons": ["spring", "summer", "autumn"],
		"yield": [2, 3],
		"seeds_back": [1, 2],
		"soil_drain": 12.0,
		"tip": "любит частый полив, но быстро созревает",
	},
	"potato": {
		"name": "Картофель",
		"seed": "seeds_potato",
		"growth_hours": 14.0,
		"water_use": 3.5,
		"moist_min": 30.0,
		"moist_max": 70.0,
		"overwater_speed": 0.45,
		"wither_hours": 9.0,
		"seasons": ["spring", "summer"],
		"yield": [2, 4],
		"seeds_back": [1, 2],
		"soil_drain": 20.0,
		"tip": "не любит переувлажнения и сильно истощает почву",
	},
	"wheat": {
		"name": "Пшеница",
		"seed": "seeds_wheat",
		"growth_hours": 20.0,
		"water_use": 2.5,
		"moist_min": 20.0,
		"moist_max": 80.0,
		"overwater_speed": 0.7,
		"wither_hours": 14.0,
		"seasons": ["summer", "autumn"],
		"yield": [3, 5],
		"seeds_back": [1, 3],
		"soil_drain": 8.0,
		"tip": "засухоустойчива, требует терпения, бережёт почву",
	},
	"sunflower": {
		"name": "Подсолнух",
		"seed": "seeds_sunflower",
		"product": "sunflower_seeds",
		"growth_hours": 18.0,
		"water_use": 3.0,
		"moist_min": 25.0,
		"moist_max": 65.0,
		"overwater_speed": 0.6,
		"wither_hours": 12.0,
		"seasons": ["summer"],
		"yield": [2, 4],
		"seeds_back": [1, 3],
		"soil_drain": 14.0,
		"tip": "любит солнце и засухоустойчив, дает ценные семечки",
	},
	"onion": {
		"name": "Лук",
		"seed": "seeds_onion",
		"product": "onion",
		"growth_hours": 12.0,
		"water_use": 4.0,
		"moist_min": 35.0,
		"moist_max": 75.0,
		"overwater_speed": 0.7,
		"wither_hours": 8.0,
		"seasons": ["spring", "summer", "autumn"],
		"yield": [3, 5],
		"seeds_back": [1, 2],
		"soil_drain": 10.0,
		"tip": "быстро всходит весной, неприхотлив к температуре",
	},
	"cabbage": {
		"name": "Капуста",
		"seed": "seeds_cabbage",
		"product": "cabbage",
		"growth_hours": 24.0,
		"water_use": 5.5,
		"moist_min": 40.0,
		"moist_max": 85.0,
		"overwater_speed": 0.8,
		"wither_hours": 7.0,
		"seasons": ["summer", "autumn"],
		"yield": [1, 2],
		"seeds_back": [1, 2],
		"soil_drain": 18.0,
		"tip": "влаголюбивая культура, формирует увесистый кочан",
	},
	"tomato": {
		"name": "Помидор",
		"seed": "seeds_tomato",
		"product": "tomato",
		"growth_hours": 16.0,
		"water_use": 4.5,
		"moist_min": 50.0,
		"moist_max": 90.0,
		"overwater_speed": 0.65,
		"wither_hours": 8.0,
		"seasons": ["summer"],
		"yield": [3, 6],
		"seeds_back": [1, 3],
		"soil_drain": 15.0,
		"tip": "требует обильного летнего тепла и умеренной влаги",
	},
	"pepper": {
		"name": "Сладкий перец",
		"seed": "seeds_pepper",
		"product": "pepper",
		"growth_hours": 20.0,
		"water_use": 3.5,
		"moist_min": 35.0,
		"moist_max": 70.0,
		"overwater_speed": 0.55,
		"wither_hours": 10.0,
		"seasons": ["summer"],
		"yield": [2, 4],
		"seeds_back": [1, 2],
		"soil_drain": 12.0,
		"tip": "аккуратно расходует влагу, любит тёплый летний зной",
	},
	"bean": {
		"name": "Фасоль",
		"seed": "seeds_bean",
		"product": "bean",
		"growth_hours": 10.0,
		"water_use": 3.0,
		"moist_min": 30.0,
		"moist_max": 65.0,
		"overwater_speed": 0.7,
		"wither_hours": 9.0,
		"seasons": ["spring", "summer"],
		"yield": [4, 8],
		"seeds_back": [2, 4],
		"soil_drain": 6.0,
		"tip": "быстро созревает и щадит плодородие почвы",
	},
	"herbs": {
		"name": "Пряные травы",
		"seed": "seeds_herbs",
		"product": "herbs",
		"growth_hours": 6.0,
		"water_use": 2.5,
		"moist_min": 30.0,
		"moist_max": 70.0,
		"overwater_speed": 0.85,
		"wither_hours": 12.0,
		"seasons": ["spring", "summer", "autumn"],
		"yield": [3, 6],
		"seeds_back": [1, 3],
		"soil_drain": 5.0,
		"tip": "самый быстрый урожай на грядке, растет три сезона",
	},
	"corn": {
		"name": "Кукуруза",
		"seed": "seeds_corn",
		"product": "corn",
		"growth_hours": 22.0,
		"water_use": 3.8,
		"moist_min": 35.0,
		"moist_max": 75.0,
		"overwater_speed": 0.6,
		"wither_hours": 11.0,
		"seasons": ["summer"],
		"yield": [2, 4],
		"seeds_back": [1, 2],
		"soil_drain": 16.0,
		"tip": "высокие злаковые стебли с плотными початками",
	},
	"pumpkin": {
		"name": "Тыква",
		"seed": "seeds_pumpkin",
		"product": "pumpkin",
		"growth_hours": 28.0,
		"water_use": 4.0,
		"moist_min": 40.0,
		"moist_max": 80.0,
		"overwater_speed": 0.7,
		"wither_hours": 10.0,
		"seasons": ["summer", "autumn"],
		"yield": [1, 2],
		"seeds_back": [1, 3],
		"soil_drain": 22.0,
		"tip": "зреет дольше всех, но дарит гигантский сытный плод",
	},
}

static func has_crop(crop: String) -> bool:
	return CROPS.has(crop)

static func get_crop(crop: String) -> Dictionary:
	return CROPS.get(crop, {})

static func get_crop_name(crop: String) -> String:
	return str(CROPS.get(crop, {}).get("name", crop))

static func get_crop_product(crop: String) -> String:
	var d: Dictionary = get_crop(crop)
	return str(d.get("product", crop))

static func crop_for_seed(seed_id: String) -> String:
	for c in CROPS:
		if CROPS[c]["seed"] == seed_id:
			return c
	return ""

static func all_seeds() -> Array[String]:
	var out: Array[String] = []
	for c in CROPS:
		out.append(str(CROPS[c]["seed"]))
	return out

## Множитель влажности: 1 в норме, меньше — при засухе или переувлажнении.
static func moisture_factor(crop: String, moisture: float) -> float:
	var d: Dictionary = get_crop(crop)
	if d.is_empty():
		return 0.0
	if moisture <= 0.0:
		return 0.0
	if moisture < float(d["moist_min"]):
		return DRY_SPEED
	if moisture > float(d["moist_max"]):
		return float(d["overwater_speed"])
	return 1.0

static func soil_factor(fertility: float) -> float:
	if fertility >= RICH_SOIL:
		return RICH_SPEED
	if fertility < POOR_SOIL:
		return POOR_SPEED
	return 1.0

static func quality_for(care_ratio: float) -> int:
	if care_ratio >= QUALITY_GREAT:
		return 2
	if care_ratio >= QUALITY_GOOD:
		return 1
	return 0

## Короткая справка о культуре для подсказок.
static func describe(crop: String) -> String:
	var d: Dictionary = get_crop(crop)
	if d.is_empty():
		return crop
	return "%s: %d ч, влага %d–%d%%, %s" % [d["name"], int(d["growth_hours"]), int(d["moist_min"]), int(d["moist_max"]), d["tip"]]
