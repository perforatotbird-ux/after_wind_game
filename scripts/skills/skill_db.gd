class_name SkillDB
extends RefCounted

## Центральная база данных и реестр навыков персонажа («Learn by doing»).
## Содержит 11 специализированных навыков, формулы опыта и расчёт пассивных бонусов.

const MAX_LEVEL: int = 10

## Пороги суммарного опыта для каждого уровня (индекс = уровень - 1).
## Lv.1 = 0, Lv.2 = 400, ..., Lv.10 = 13000 (MAX).
const XP_THRESHOLDS: Array[int] = [
	0,      # Lv. 1
	400,    # Lv. 2
	1000,   # Lv. 3
	1800,   # Lv. 4
	2800,   # Lv. 5
	4000,   # Lv. 6
	5600,   # Lv. 7
	7600,   # Lv. 8
	10000,  # Lv. 9
	13000   # Lv. 10 (MAX)
]

const SKILL_IDS: Array[String] = [
	"woodcutting",
	"mining",
	"farming",
	"orchard",
	"foraging",
	"hydrology",
	"crafting",
	"cooking",
	"construction",
	"trading",
	"athletics"
]

const SKILLS_CONFIG: Dictionary = {
	"woodcutting": {
		"id": "woodcutting",
		"name": "Рубка леса",
		"icon": "🪓",
		"color": Color(0.4, 0.78, 0.38),
		"description": "Валка деревьев, корчевание пней и заготовка древесины.",
		"actions": "Удары топором по деревьям, валка деревьев, сруб пней."
	},
	"mining": {
		"id": "mining",
		"name": "Горное дело",
		"icon": "⛏️",
		"color": Color(0.65, 0.7, 0.75),
		"description": "Раскалывание камня, добыча металлолома и воксельных руд.",
		"actions": "Удары киркой по камню и металлолому, выработка жил."
	},
	"farming": {
		"id": "farming",
		"name": "Земледелие",
		"icon": "🌾",
		"color": Color(0.9, 0.82, 0.35),
		"description": "Возделывание почвы на делянках, полив и сбор урожая.",
		"actions": "Посадка семян, полив делянки, внесение удобрений, сбор урожая."
	},
	"orchard": {
		"id": "orchard",
		"name": "Садоводство",
		"icon": "🍎",
		"color": Color(0.95, 0.45, 0.4),
		"description": "Посадка плодовых деревьев (яблони, вишни, абрикос) и сбор спелых фруктов.",
		"actions": "Посадка саженцев плодовых деревьев, сбор плодов."
	},
	"foraging": {
		"id": "foraging",
		"name": "Собирательство",
		"icon": "🫐",
		"color": Color(0.55, 0.5, 0.85),
		"description": "Поиск диких ягодных кустов, грибов и целебных дикоросов.",
		"actions": "Сбор ягод с кустов, сбор грибов на лугах."
	},
	"hydrology": {
		"id": "hydrology",
		"name": "Водопользование",
		"icon": "💧",
		"color": Color(0.35, 0.75, 0.95),
		"description": "Добыча воды ведром из озера/колодца, очистка в фильтре.",
		"actions": "Набор воды ведром, фильтрация в станке, пополнение резервуара."
	},
	"crafting": {
		"id": "crafting",
		"name": "Ремесло и машины",
		"icon": "⚙️",
		"color": Color(0.85, 0.6, 0.35),
		"description": "Работа на верстаке, в дробилке и печи, починка механизмов.",
		"actions": "Завершение производственных циклов, ремонт станков."
	},
	"cooking": {
		"id": "cooking",
		"name": "Кулинария",
		"icon": "🍲",
		"color": Color(0.95, 0.65, 0.4),
		"description": "Приготовление питательных блюд на костре и кухонной плите.",
		"actions": "Приготовление блюд на костре и плите."
	},
	"construction": {
		"id": "construction",
		"name": "Строительство",
		"icon": "🔨",
		"color": Color(0.75, 0.65, 0.55),
		"description": "Восстановление дома, склада, постройка делянок и апгрейды.",
		"actions": "Сдача стройматериалов в здания, завершение этапов постройки."
	},
	"trading": {
		"id": "trading",
		"name": "Торговля",
		"icon": "📜",
		"color": Color(0.95, 0.75, 0.3),
		"description": "Выполнение заказов на доске контрактов и сделки с караванщиком.",
		"actions": "Сдача контрактов, купля-продажа товаров у Степана."
	},
	"athletics": {
		"id": "athletics",
		"name": "Атлетика",
		"icon": "🏃",
		"color": Color(0.35, 0.85, 0.75),
		"description": "Физическая выносливость, дыхание, бег со снаряжением и прыжки.",
		"actions": "Спринтерский бег, прыжки, работа под нагрузкой."
	}
}

static func get_skill_data(skill_id: String) -> Dictionary:
	return SKILLS_CONFIG.get(skill_id, {})

static func get_all_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for sid in SKILL_IDS:
		list.append(SKILLS_CONFIG[sid])
	return list

static func get_xp_for_level(lvl: int) -> int:
	var idx: int = clampi(lvl - 1, 0, XP_THRESHOLDS.size() - 1)
	return XP_THRESHOLDS[idx]

## Вычисляет уровень по текущему суммарному количеству XP
static func calculate_level(xp: int) -> int:
	var lvl: int = 1
	for i in range(XP_THRESHOLDS.size() - 1, -1, -1):
		if xp >= XP_THRESHOLDS[i]:
			lvl = i + 1
			break
	return clampi(lvl, 1, MAX_LEVEL)

## Возвращает прогресс внутри текущего уровня от 0.0 до 1.0
static func get_level_progress(xp: int, level: int) -> float:
	if level >= MAX_LEVEL:
		return 1.0
	var current_base: int = get_xp_for_level(level)
	var next_base: int = get_xp_for_level(level + 1)
	var span: int = next_base - current_base
	if span <= 0:
		return 1.0
	return clampf(float(xp - current_base) / float(span), 0.0, 1.0)

## Скидка на расход энергии (топор, кирка, ведро): 3% за уровень (до -27% на Lv.10)
static func get_energy_discount(skill_id: String, level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	match skill_id:
		"woodcutting", "mining", "hydrology":
			return (lvl - 1) * 0.03
		"athletics":
			return (lvl - 1) * 0.025
	return 0.0

## Шанс получить дополнительную единицу добычи: 5% за уровень (до +45% на Lv.10)
static func get_bonus_yield_chance(skill_id: String, level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	match skill_id:
		"woodcutting", "mining", "hydrology", "foraging":
			return (lvl - 1) * 0.05
		"farming":
			return (lvl - 1) * 0.03
	return 0.0

## Бонус к шансу получить повышенное качество урожая: 4% за уровень
static func get_harvest_quality_bonus(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return (lvl - 1) * 0.04

## Шанс сохранить семечко при посадке на делянке: 3% за уровень
static func get_seed_save_chance(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return (lvl - 1) * 0.03

## Ускорение станков от ремесла: +2.5% за уровень (до +22.5%)
static func get_machine_speed_mult(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return 1.0 + (lvl - 1) * 0.025

## Снижение износа станков от ремесла: -2.5% за уровень (до -22.5%)
static func get_wear_discount(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return (lvl - 1) * 0.025

## Питательность приготовленной еды от кулинарии: +3% за уровень (до +27%)
static func get_cooking_nutrition_mult(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return 1.0 + (lvl - 1) * 0.03

## Прибавка к грузоподъёмности рюкзака от строительства: +1 кг за уровень
static func get_capacity_bonus(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return float(lvl - 1) * 1.0

## Прибавка к максимальной энергии от атлетики: +3 за уровень (+27 на Lv.10)
static func get_max_energy_bonus(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return float(lvl - 1) * 3.0

## Бонус к кредитам за контракты от торговли: +2% за уровень (до +18%)
static func get_trade_bonus_mult(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return 1.0 + (lvl - 1) * 0.02

## Скидка при покупке у караванщика: -2% за уровень (до -18%)
static func get_trade_discount_mult(level: int) -> float:
	var lvl := clampi(level, 1, MAX_LEVEL)
	return 1.0 - (lvl - 1) * 0.02

## Вычисляет общий уровень персонажа из словаря { skill_id: {"level": int, "xp": int} }
static func get_overall_level(skills_data: Dictionary) -> int:
	var sum_lvls: int = 0
	for sid in SKILL_IDS:
		var entry = skills_data.get(sid, {})
		sum_lvls += int(entry.get("level", 1))
	# Начальный общий уровень = 1, максимальный = 50
	var extra: int = maxi(0, sum_lvls - SKILL_IDS.size())
	return 1 + int(floor(float(extra) / 2.0))

## Текстовый ранг персонажа в зависимости от общего уровня
static func get_overall_title(overall_lvl: int) -> String:
	if overall_lvl >= 45:
		return "Легенда Пустоши"
	elif overall_lvl >= 35:
		return "Мастер Выживания"
	elif overall_lvl >= 25:
		return "Опытный Первопроходец"
	elif overall_lvl >= 15:
		return "Умелый Колонист"
	elif overall_lvl >= 7:
		return "Практик Пустоши"
	return "Новичок Бури"

## Возвращает текстовое описание активных перков для конкретного уровня навыка
static func get_perks_summary(skill_id: String, level: int) -> String:
	var lvl := clampi(level, 1, MAX_LEVEL)
	if lvl <= 1:
		return "Базовый уровень (бонусы откроются со 2-го уровня)"
	
	var lines: Array[String] = []
	match skill_id:
		"woodcutting":
			lines.append("⚡ -%d%% расход энергии при рубке" % int((lvl - 1) * 3))
			lines.append("🪵 +%d%% шанс доп. древесины" % int((lvl - 1) * 5))
			if lvl >= 5:
				lines.append("🌱 +25% шанс саженца при валке")
			if lvl >= 8:
				lines.append("💥 Шанс критического удара топором (-2 прочн.)")
		"mining":
			lines.append("⚡ -%d%% расход энергии кирки" % int((lvl - 1) * 3))
			lines.append("⛏️ +%d%% шанс доп. камня/металла" % int((lvl - 1) * 5))
			if lvl >= 4:
				lines.append("💎 Шанс сопутствующих минералов (песок, глина)")
			if lvl >= 8:
				lines.append("💥 Шанс мощного раскалывающего удара")
		"farming":
			lines.append("⭐ +%d%% шанс высокого качества урожая" % int((lvl - 1) * 4))
			lines.append("🌱 +%d%% шанс сберечь семя при посадке" % int((lvl - 1) * 3))
			lines.append("💧 Почва медленнее теряет влагу и плодородие")
			if lvl >= 7:
				lines.append("🌾 +20% шанс двойного сбора с клетки")
		"orchard":
			var extra_fruits = (1 if lvl >= 3 else 0) + (1 if lvl >= 6 else 0) + (1 if lvl >= 10 else 0)
			if extra_fruits > 0:
				lines.append("🍎 +%d плодов к сбору с деревьев" % extra_fruits)
			lines.append("⏳ -%d%% время созревания плодов" % int((lvl - 1) * 2.5))
		"foraging":
			lines.append("🫐 +%d%% шанс удвоенного сбора ягод/грибов" % int((lvl - 1) * 5))
			if lvl >= 5:
				lines.append("🌿 +20% питательности дикоросов")
		"hydrology":
			lines.append("⚡ -%d%% расход энергии при черпании воды" % int((lvl - 1) * 3))
			lines.append("💧 +%d%% шанс дополнительной порции воды" % int((lvl - 1) * 5))
			if lvl >= 7:
				lines.append("✨ 10% шанс сразу зачерпнуть чистую воду")
		"crafting":
			lines.append("⚙️ +%.1f%% скорость работы станков" % ((lvl - 1) * 2.5))
			lines.append("🛠️ -%.1f%% износ станков за цикл" % ((lvl - 1) * 2.5))
			if lvl >= 5:
				lines.append("♻️ 10% шанс безотходного крафта (сохранение сырья)")
		"cooking":
			lines.append("🍲 +%d%% сытность и энергия приготовленных блюд" % int((lvl - 1) * 3))
			lines.append("✨ +%d%% шанс приготовить шедевр (+1 порция)" % int((lvl - 1) * 4))
			lines.append("🔥 -%d%% расход топлива при готовке" % int((lvl - 1) * 2))
		"construction":
			lines.append("📦 +%d кг к вместимости рюкзака" % int(lvl - 1))
			lines.append("🔨 -%d%% материалов при ремонте построек" % int((lvl - 1) * 3))
		"trading":
			lines.append("💰 +%d%% выплата кредитов за контракты" % int((lvl - 1) * 2))
			lines.append("🏷️ -%d%% скидка на товары у караванщика" % int((lvl - 1) * 2))
		"athletics":
			lines.append("⚡ +%d к максимальному запасу энергии" % int((lvl - 1) * 3))
			lines.append("🏃 -%.1f%% расход энергии при спринте" % ((lvl - 1) * 2.5))
			lines.append("💨 +%d%% скорость восстановления сил в покое" % int((lvl - 1) * 3))

	return "\n".join(lines)
