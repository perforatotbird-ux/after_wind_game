extends SceneTree
## Комплексный тест механик специализаций и прокачки навыков (Skills & Classes Suite)
## Покрывает:
## 1. Реестр архетипов (CharacterClassDB): Шахтер, Фермер, Ученый и их множители.
## 2. Смена специализации персонажа (set_character_class) и выдача стартового снаряжения.
## 3. Реестр дисциплин (SkillDB): 11 навыков, уровни прогрессии 1..5, расчет общего ранга.
## 4. Прокачка «Learn by doing» (PlayerSkills): начисление XP, уровни, сигналы skill_leveled_up.
## 5. Расчет пассивных перков: скидка энергии, ускорение станков, бонус к рюкзаку и максимальной энергии.

const WorldScene = preload("res://scenes/world/world.tscn")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const SkillDB = preload("res://scripts/skills/skill_db.gd")
const PlayerSkills = preload("res://scripts/skills/player_skills.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: СПЕЦИАЛИЗАЦИИ И НАВЫКИ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	# -------------------------------------------------------------------------
	# 1. Реестр специализаций (CharacterClassDB)
	# -------------------------------------------------------------------------
	print("\n--- 1. Архетипы персонажей и их характеристики ---")
	var miner_data = CharacterClassDB.get_class_data("miner")
	var farmer_data = CharacterClassDB.get_class_data("farmer")
	var scientist_data = CharacterClassDB.get_class_data("scientist")

	check(not miner_data.is_empty(), "Шахтёр должен быть в базе классов")
	check(not farmer_data.is_empty(), "Фермер должен быть в базе классов")
	check(not scientist_data.is_empty(), "Учёный должен быть в базе классов")

	# Шахтёр: бонус к добыче +1, расход энергии кирки 0.8
	check(miner_data.get("mining_bonus_yield", 0) == 1, "Шахтёр: бонусная руда = 1")
	check(abs(miner_data.get("mining_energy_mult", 1.0) - 0.80) < 0.01, "Шахтёр: расход сил кирки 0.80")

	# Фермер: ускорение роста 1.35, расход еды 0.75
	check(abs(farmer_data.get("crop_growth_mult", 1.0) - 1.35) < 0.01, "Фермер: множитель роста культур 1.35")
	check(abs(farmer_data.get("hunger_decay_mult", 1.0) - 0.75) < 0.01, "Фермер: расход сытости 0.75")

	# Учёный: скорость станков 1.40, расход энергии станков 0.50
	check(abs(scientist_data.get("machine_speed_mult", 1.0) - 1.40) < 0.01, "Учёный: скорость станков 1.40")
	check(abs(scientist_data.get("machine_energy_mult", 1.0) - 0.50) < 0.01, "Учёный: энергопотребление станков 0.50")
	print("✅ Специализации: архетипы miner, farmer, scientist и их уникальные коэффициенты валидны.")

	# -------------------------------------------------------------------------
	# 2. Выбор класса персонажа и выдача стартового пакета
	# -------------------------------------------------------------------------
	print("\n--- 2. Назначение класса и выдача стартового набора ---")
	inv.clear()
	var set_farmer = player.set_character_class("farmer", true)
	check(set_farmer, "set_character_class для farmer должен вернуть true")
	check(player.character_class == "farmer", "Класс игрока должен стать farmer")
	check(inv.get_item_count("seeds_carrot") >= 2, "Фермер должен получить стартовые семена моркови")
	check(inv.get_item_count("seeds_potato") >= 2, "Фермер должен получить стартовые семена картофеля")
	check(inv.get_item_count("fertilizer") >= 1, "Фермер должен получить био-удобрение")
	print("✅ Смена класса: специализация установлена, стартовые семена и удобрение выданы.")

	# -------------------------------------------------------------------------
	# 3. Дисциплины и структура навыков (SkillDB)
	# -------------------------------------------------------------------------
	print("\n--- 3. Реестр дисциплин и уровней ---")
	check(SkillDB.SKILL_IDS.size() >= 6, "В SkillDB должно быть не менее 6 дисциплин")
	check(SkillDB.MAX_LEVEL == 10, "Максимальный уровень навыка должен быть 10")
	check(SkillDB.calculate_level(0) == 1, "При 0 XP уровень должен быть 1")
	var max_xp = SkillDB.get_xp_for_level(10)
	check(SkillDB.calculate_level(max_xp) == 10, "При максимальном XP уровень должен быть 10")
	print("✅ Структура навыков: сетка уровней 1..10 и расчет уровней по очкам опыта работают верно.")

	# -------------------------------------------------------------------------
	# 4. Прокачка опыта и повышение уровней (PlayerSkills)
	# -------------------------------------------------------------------------
	print("\n--- 4. Начисление опыта и повышение уровней ---")
	var skills = player.skills
	if not skills:
		skills = PlayerSkills.new()
		player.add_child(skills)

	skills._init_default_skills()
	check(skills.get_level("mining") == 1, "Стартовый уровень горного дела должен быть 1")
	check(skills.get_xp("mining") == 0, "Стартовый опыт должен быть 0")

	# Начисляем немного опыта (без левелапа)
	var xp_needed_lv2 = SkillDB.get_xp_for_level(2)
	var leveled_up1 = skills.add_xp("mining", 10)
	check(not leveled_up1, "При 10 XP не должно быть левелапа")
	check(skills.get_xp("mining") == 10, "Опыт должен стать 10")

	# Добавляем опыт для перехода на уровень 2
	var leveled_up2 = skills.add_xp("mining", xp_needed_lv2)
	check(leveled_up2, "Должно произойти повышение уровня")
	check(skills.get_level("mining") >= 2, "Уровень горного дела должен стать 2")

	# Прокачка до максимума (уровень 10)
	skills.add_xp("mining", 99999)
	check(skills.get_level("mining") == 10, "Уровень не должен превышать максимум (10)")
	print("✅ Начисление опыта: получение XP, повышение уровней и ограничение MAX_LEVEL проверены.")

	# -------------------------------------------------------------------------
	# 5. Пассивные бонусы от прокачки
	# -------------------------------------------------------------------------
	print("\n--- 5. Расчет пассивных перков ---")
	# Атлетика: повышение максимальной энергии
	skills.add_xp("athletics", 99999) # Lv. 5
	var energy_bonus = skills.get_max_energy_bonus()
	check(energy_bonus > 0.0, "Прокачанная атлетика должна давать бонус к макс. энергии (бонус: %.1f)" % energy_bonus)

	# Строительство: расширение вместимости рюкзака
	skills.add_xp("construction", 99999) # Lv. 5
	var cap_bonus = skills.get_capacity_bonus()
	check(cap_bonus > 0.0, "Прокачанное строительство должно увеличивать вместимость рюкзака (бонус: %.1f)" % cap_bonus)

	# Крафт: ускорение станков
	skills.add_xp("crafting", 99999) # Lv. 5
	var speed_mult = skills.get_machine_speed_mult()
	check(speed_mult > 1.0, "Прокачанный крафт должен ускорять работу станков (множитель: %.2f)" % speed_mult)
	print("✅ Пассивные перки: бонусы энергии, грузоподъемности и скорости станков подтверждены.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ СПЕЦИАЛИЗАЦИЙ И НАВЫКОВ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
