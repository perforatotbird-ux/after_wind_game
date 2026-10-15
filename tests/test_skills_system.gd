extends SceneTree

## Тест системы прокачки навыков персонажа («Learn by doing»).
## Проверяет SkillDB, PlayerSkills, начисление XP, левелапы, перки, сериализацию, интеграцию с игроком и HUD.

const SkillDB = preload("res://scripts/skills/skill_db.gd")
const PlayerSkills = preload("res://scripts/skills/player_skills.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const HudScene = preload("res://scenes/ui/hud.tscn")

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_skill_db_structure_and_formulas()
	_test_player_skills_xp_and_leveling()
	_test_player_skills_perks_query()
	_test_player_skills_serialization()
	_test_athletics_progression()
	_test_player_scene_integration()
	_test_hud_skills_ui()

	if errors.is_empty():
		print("PASS: test_skills_system — вся система навыков (11 веток, перки, интеграция, HUD) работает корректно!")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)

func _test_skill_db_structure_and_formulas() -> void:
	check(SkillDB.SKILL_IDS.size() == 11, "SkillDB должен содержать ровно 11 навыков, найдено %d" % SkillDB.SKILL_IDS.size())
	
	for sid in SkillDB.SKILL_IDS:
		var s_data: Dictionary = SkillDB.get_skill_data(sid)
		check(not s_data.is_empty(), "Метаданные для навыка '%s' отсутствуют в SkillDB" % sid)
		check(s_data.has("name") and not s_data["name"].is_empty(), "Навык '%s' не имеет имени" % sid)
		check(s_data.has("icon") and not s_data["icon"].is_empty(), "Навык '%s' не имеет иконки" % sid)
		check(s_data.has("description"), "Навык '%s' не имеет описания" % sid)
		check(s_data.has("actions"), "Навык '%s' не имеет списка действий" % sid)

	# Проверка порогов опыта
	check(SkillDB.XP_THRESHOLDS.size() == 10, "Должно быть 10 порогов опыта")
	check(SkillDB.get_xp_for_level(1) == 0, "Уровень 1 должен требовать 0 XP")
	check(SkillDB.get_xp_for_level(2) == 400, "Уровень 2 должен требовать 400 XP")
	check(SkillDB.get_xp_for_level(10) == 13000, "Уровень 10 должен требовать 13000 XP")
	
	check(SkillDB.calculate_level(0) == 1, "0 XP должно давать 1 уровень")
	check(SkillDB.calculate_level(399) == 1, "399 XP должно давать 1 уровень")
	check(SkillDB.calculate_level(400) == 2, "400 XP должно давать 2 уровень")
	check(SkillDB.calculate_level(999) == 2, "999 XP должно давать 2 уровень")
	check(SkillDB.calculate_level(1000) == 3, "1000 XP должно давать 3 уровень")
	check(SkillDB.calculate_level(13000) == 10, "13000 XP должно давать 10 уровень")
	check(SkillDB.calculate_level(99999) == 10, "Опыт выше максимума должен ограничиваться 10 уровнем")

	# Проверка расчёта бонусов
	check(is_equal_approx(SkillDB.get_energy_discount("woodcutting", 1), 0.0), "Скидка энергии на Lv.1 должна быть 0")
	check(is_equal_approx(SkillDB.get_energy_discount("woodcutting", 2), 0.03), "Скидка энергии на Lv.2 должна быть 3%")
	check(is_equal_approx(SkillDB.get_energy_discount("woodcutting", 10), 0.27), "Скидка энергии на Lv.10 должна быть 27%")

	check(is_equal_approx(SkillDB.get_bonus_yield_chance("woodcutting", 1), 0.0), "Шанс доп. сбора на Lv.1 должен быть 0")
	check(is_equal_approx(SkillDB.get_bonus_yield_chance("woodcutting", 10), 0.45), "Шанс доп. сбора на Lv.10 должен быть 45%")

	check(is_equal_approx(SkillDB.get_machine_speed_mult(1), 1.0), "Множитель скорости станков на Lv.1 должен быть 1.0")
	check(is_equal_approx(SkillDB.get_machine_speed_mult(10), 1.225), "Множитель скорости станков на Lv.10 должен быть 1.225")

	check(is_equal_approx(SkillDB.get_capacity_bonus(1), 0.0), "Бонус к весу рюкзака на Lv.1 должен быть 0 кг")
	check(is_equal_approx(SkillDB.get_capacity_bonus(10), 9.0), "Бонус к весу рюкзака на Lv.10 должен быть 9 кг")

	check(is_equal_approx(SkillDB.get_max_energy_bonus(1), 0.0), "Бонус к энергии на Lv.1 должен быть 0")
	check(is_equal_approx(SkillDB.get_max_energy_bonus(10), 27.0), "Бонус к энергии на Lv.10 должен быть 27")

func _test_player_skills_xp_and_leveling() -> void:
	var ps: PlayerSkills = PlayerSkills.new()
	root.add_child(ps)

	for sid in SkillDB.SKILL_IDS:
		check(ps.get_level(sid) == 1, "Начальный уровень навыка '%s' должен быть 1" % sid)
		check(ps.get_xp(sid) == 0, "Начальный XP навыка '%s' должен быть 0" % sid)

	var fired: Dictionary = {
		"xp": false,
		"level_up": false,
		"updated": false
	}

	ps.skill_xp_gained.connect(func(_id, _amt, _cur, _nxt): fired["xp"] = true)
	ps.skill_leveled_up.connect(func(_id, _lvl, _desc): fired["level_up"] = true)
	ps.skills_updated.connect(func(): fired["updated"] = true)

	# Начисление 200 XP: без левелапа (нужно 400 на Lv.2)
	var leveled: bool = ps.add_xp("woodcutting", 200)
	check(not leveled, "200 XP не должны вызывать левелап")
	check(fired["xp"], "Сигнал skill_xp_gained должен быть вызван")
	check(fired["updated"], "Сигнал skills_updated должен быть вызван")
	check(not fired["level_up"], "Сигнал skill_leveled_up не должен быть вызван")
	check(ps.get_xp("woodcutting") == 200, "XP лесозаготовки должен быть 200")
	check(ps.get_level("woodcutting") == 1, "Уровень лесозаготовки должен оставаться 1")

	# Начисление ещё 250 XP: суммарно 450 XP -> Lv. 2
	fired["xp"] = false
	fired["updated"] = false
	fired["level_up"] = false

	leveled = ps.add_xp("woodcutting", 250)
	check(leveled, "Суммарно 450 XP должны вызвать повышение уровня до 2")
	check(fired["level_up"], "Сигнал skill_leveled_up должен сработать")
	check(ps.get_level("woodcutting") == 2, "Уровень лесозаготовки должен стать 2")
	check(ps.get_xp("woodcutting") == 450, "XP лесозаготовки должен быть 450")

	# Проверка капа 10 уровня (13000 XP)
	ps.add_xp("mining", 20000)
	check(ps.get_level("mining") == 10, "Майнинг должен достичь максимального 10 уровня")
	check(ps.get_xp("mining") == 13000, "Опыт майнинга должен быть ограничен 13000")
	var extra_add: bool = ps.add_xp("mining", 100)
	check(not extra_add, "Добавление опыта на максимальном уровне должно возвращать false")

	ps.queue_free()

func _test_player_skills_perks_query() -> void:
	var ps: PlayerSkills = PlayerSkills.new()
	root.add_child(ps)

	ps.add_xp("woodcutting", 400) # Lv. 2
	check(is_equal_approx(ps.get_energy_discount("woodcutting"), 0.03), "Скидка энергии на Lv.2 должна быть 3%")
	check(is_equal_approx(ps.get_energy_discount("mining"), 0.0), "Скидка энергии на Lv.1 майнинга должна быть 0%")

	ps.add_xp("crafting", 1800) # Lv. 4
	check(is_equal_approx(ps.get_machine_speed_mult(), 1.075), "Скорость станков на Lv.4 ремесла должна быть 1.075")
	check(is_equal_approx(ps.get_wear_discount(), 0.075), "Скидка износа станков на Lv.4 ремесла должна быть 0.075")

	ps.add_xp("construction", 1000) # Lv. 3
	check(is_equal_approx(ps.get_capacity_bonus(), 2.0), "Бонус к весу на Lv.3 строительства должен быть +2 кг")

	ps.add_xp("athletics", 400) # Lv. 2
	check(is_equal_approx(ps.get_max_energy_bonus(), 3.0), "Бонус к макс. энергии на Lv.2 атлетики должен быть +3")
	check(is_equal_approx(ps.get_sprint_energy_discount(), 0.025), "Скидка спринта на Lv.2 атлетики должна быть 2.5%")

	ps.queue_free()

func _test_player_skills_serialization() -> void:
	var ps1: PlayerSkills = PlayerSkills.new()
	root.add_child(ps1)
	ps1.add_xp("woodcutting", 500)
	ps1.add_xp("farming", 1200)
	ps1.add_xp("athletics", 50)

	var saved_data: Dictionary = ps1.serialize()
	check(saved_data.has("skills") and saved_data.has("version"), "Сериализованные данные должны иметь 'skills' и 'version'")
	check(saved_data["skills"].has("woodcutting"), "Сериализованные данные должны содержать woodcutting")
	check(saved_data["skills"]["woodcutting"]["level"] == 2, "Сохраненный уровень woodcutting должен быть 2")
	check(saved_data["skills"]["woodcutting"]["xp"] == 500, "Сохраненный XP woodcutting должен быть 500")

	var ps2: PlayerSkills = PlayerSkills.new()
	root.add_child(ps2)
	ps2.deserialize(saved_data)

	check(ps2.get_level("woodcutting") == 2, "Восстановленный уровень woodcutting должен быть 2")
	check(ps2.get_xp("woodcutting") == 500, "Восстановленный XP woodcutting должен быть 500")
	check(ps2.get_level("farming") == 3, "Восстановленный уровень farming должен быть 3")
	check(ps2.get_xp("farming") == 1200, "Восстановленный XP farming должен быть 1200")
	check(ps2.get_level("mining") == 1, "Не тронутый навык mining должен быть 1 уровня")

	# Проверка совместимости со старыми сохранениями (пустой словарь)
	var ps3: PlayerSkills = PlayerSkills.new()
	root.add_child(ps3)
	ps3.deserialize({})
	for sid in SkillDB.SKILL_IDS:
		check(ps3.get_level(sid) == 1, "Десериализация пустого словаря должна корректно инициализировать '%s' Lv.1" % sid)

	ps1.queue_free()
	ps2.queue_free()
	ps3.queue_free()

func _test_athletics_progression() -> void:
	var ps: PlayerSkills = PlayerSkills.new()
	root.add_child(ps)

	check(ps.get_xp("athletics") == 0, "Начальный опыт атлетики = 0")
	ps.award_athletics_jump()
	check(ps.get_xp("athletics") == 1, "Прыжок должен давать 1 XP атлетики")

	ps.award_athletics_sprint()
	check(ps.get_xp("athletics") == 3, "Интервал спринта должен давать 2 XP атлетики (всего 3)")

	ps.queue_free()

func _test_player_scene_integration() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)

	check(player.get_node_or_null("Skills") != null, "Узел Skills должен присутствовать в PlayerScene")
	check(player.skills != null, "Поле player.skills должно быть инициализировано")
	check(player.skills is PlayerSkills, "player.skills должен быть экземпляром PlayerSkills")

	# Проверка базовой энергии и бонуса от атлетики
	var base_max_energy: float = player.get_effective_max_energy()
	check(is_equal_approx(base_max_energy, 100.0), "Базовая максимальная энергия игрока должна быть 100.0, получено %.1f" % base_max_energy)

	player.skills.add_xp("athletics", 400) # Lv. 2 -> +3 энергии
	var boosted_max_energy: float = player.get_effective_max_energy()
	check(is_equal_approx(boosted_max_energy, 103.0), "Максимальная энергия игрока на Lv.2 атлетики должна быть 103.0, получено %.1f" % boosted_max_energy)

	# Проверка масштабирования питательности еды от кулинарии
	player.skills.add_xp("cooking", 1000) # Lv. 3 -> +6% к питательности
	player.hunger = 50.0
	player.energy = 50.0
	player.inventory.add_item("cabbage", 1) # cabbage: hunger_recovery = 32.0, energy_bonus = 10.0
	player.eat_food("cabbage")
	# 50.0 + 32.0 * 1.06 = 83.92
	check(is_equal_approx(player.hunger, 83.92), "Сытость должна восстановиться на 33.92 с учетом кулинарии Lv.3 (получено %.2f)" % player.hunger)

	player.queue_free()

func _test_hud_skills_ui() -> void:
	var hud = HudScene.instantiate()
	root.add_child(hud)

	check(hud.skills_button != null, "skills_button должен существовать в HUD")
	check(hud.skills_window != null, "skills_window должен существовать в HUD")
	check(not hud.skills_window.visible, "skills_window должно быть скрыто по умолчанию")

	# Подвязка игрока
	var player = PlayerScene.instantiate()
	root.add_child(player)
	hud.bind_player(player)

	# Открытие окна навыков
	hud.toggle_skills_window()
	check(hud.skills_window.visible, "skills_window должно стать видимым после toggle_skills_window()")
	check(hud.skills_list != null, "skills_list должен присутствовать в HUD")
	check(hud.skills_list.get_child_count() == 11, "В списке навыков должно сгенерироваться ровно 11 карточек, получено %d" % hud.skills_list.get_child_count())

	# Проверка блокировки ввода
	check(hud.is_gameplay_input_blocked(), "Когда окно навыков открыто, геймплейный ввод должен блокироваться")

	# Закрытие окна навыков
	hud.close_skills_window()
	check(not hud.skills_window.visible, "skills_window должно быть скрыто после close_skills_window()")

	player.queue_free()
	hud.queue_free()
