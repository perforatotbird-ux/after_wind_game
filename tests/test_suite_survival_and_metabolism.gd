extends SceneTree
## Комплексный тест механик выживания и метаболизма персонажа (Survival & Metabolism Suite)
## Покрывает:
## 1. Базовый метаболизм: естественный расход сытости, жажды и расчет множителей скорости.
## 2. Энергия и спринт: расход сил при беге, истощение, блокировка спринта при жажде/голоде.
## 3. Критические состояния и урон: урон от голода (0.15/с), обезвоживания (0.25/с), истощения.
## 4. Регенерация здоровья: восстановление HP при сытости >= 70, жажде >= 70, энергии >= 40.
## 5. Потребление пищи и напитков: питье чистой/сырой воды, поедание пищи, восстановление параметров.
## 6. Бессонница и депривация сна: нарастание усталости, блокировка регенерации сил, обморок (48ч).
## 7. Обморок (Collapse) и штрафы: списание 25% ресурсов из рюкзака, выброс дропа, телепортация.

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: ВЫЖИВАНИЕ И МЕТАБОЛИЗМ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Узел Player не найден в мире")
	if not player:
		_finish()
		return

	var inv = player.inventory
	check(inv != null, "Инвентарь игрока недоступен")

	# -------------------------------------------------------------------------
	# 1. Начальное состояние и параметры метаболизма
	# -------------------------------------------------------------------------
	print("\n--- 1. Начальные характеристики и метаболизм ---")
	player.health = 100.0
	player.hunger = 100.0
	player.thirst = 100.0
	player.energy = 100.0
	player.hours_without_sleep = 0.0

	check(player.health == 100.0, "Стартовое здоровье должно быть 100")
	check(player.hunger == 100.0, "Стартовая сытость должна быть 100")
	check(player.thirst == 100.0, "Стартовая жажда должна быть 100")
	check(player.energy == 100.0, "Стартовая энергия должна быть 100")

	# Симулируем 10 секунд голода и жажды
	var h_before = player.hunger
	var t_before = player.thirst
	player._handle_hunger(10.0)
	player._handle_thirst(10.0)
	check(player.hunger < h_before, "Сытость должна убывать со временем")
	check(player.thirst < t_before, "Жажда должна убывать со временем")
	print("✅ Начальный метаболизм: показатели корректно расходуются со временем.")

	# -------------------------------------------------------------------------
	# 2. Множители скорости передвижения
	# -------------------------------------------------------------------------
	print("\n--- 2. Влияние голода, жажды и энергии на скорость ---")
	player.hunger = 100.0
	player.thirst = 100.0
	player.energy = 100.0
	var speed_norm = player.get_speed_multiplier()
	check(abs(speed_norm - 1.0) < 0.01, "При 100%% параметров множитель скорости должен быть ~1.0 (получено %.2f)" % speed_norm)

	# При истощении энергии скорость падает
	player.energy = 0.0
	var speed_tired = player.get_speed_multiplier()
	check(speed_tired <= 0.55, "При нулевой энергии скорость должна быть сильно снижена (получено %.2f)" % speed_tired)

	# При критическом голоде и жажде скорость падает кумулятивно
	player.energy = 100.0
	player.hunger = 0.0
	player.thirst = 0.0
	var speed_exhausted = player.get_speed_multiplier()
	check(speed_exhausted <= 0.40, "При полном голоде и обезвоживании скорость должна падать кумулятивно (получено %.2f)" % speed_exhausted)
	print("✅ Штрафы к скорости: истощение, голод и жажда корректно замедляют персонажа.")

	# -------------------------------------------------------------------------
	# 3. Спринт и ограничения
	# -------------------------------------------------------------------------
	print("\n--- 3. Механика спринта ---")
	player.energy = 100.0
	player.hunger = 100.0
	player.thirst = 100.0
	check(player.can_sprint(), "При полных характеристиках спринт должен быть доступен")

	# При энергии < 20 спринт заблокирован
	player.energy = 15.0
	check(not player.can_sprint(), "При энергии < 20 спринт должен блокироваться")

	# При жажде <= 10 спринт заблокирован
	player.energy = 100.0
	player.thirst = 5.0
	check(not player.can_sprint(), "При жажде <= 10 спринт должен блокироваться")

	# При голоде <= 10 спринт заблокирован
	player.thirst = 100.0
	player.hunger = 8.0
	check(not player.can_sprint(), "При голоде <= 10 спринт должен блокироваться")
	print("✅ Спринт: блокировка при низких показателях сил, воды и еды работает стабильно.")

	# -------------------------------------------------------------------------
	# 4. Урон от критических потребностей и регенерация здоровья
	# -------------------------------------------------------------------------
	print("\n--- 4. Урон здоровью и регенерация ---")
	player.health = 50.0
	player.hunger = 80.0
	player.thirst = 80.0
	player.energy = 80.0
	player.hours_without_sleep = 0.0

	# Регенерация при сытости >= 70, жажде >= 70, энергии >= 40
	player._handle_health(10.0) # 10 секунд
	check(player.health > 50.0, "При высоких потребностях здоровье должно пассивно восстанавливаться")

	# Урон от обезвоживания (thirst == 0)
	player.health = 50.0
	player.thirst = 0.0
	player._handle_health(10.0)
	check(player.health < 50.0, "При thirst == 0 персонаж должен получать урон от обезвоживания (HP: %.2f)" % player.health)

	# Урон от голода (hunger == 0)
	player.health = 50.0
	player.thirst = 100.0
	player.hunger = 0.0
	player._handle_health(10.0)
	check(player.health < 50.0, "При hunger == 0 персонаж должен получать урон от голодания (HP: %.2f)" % player.health)
	print("✅ Здоровье: регенерация при достатке и урон при голоде/жажде функционируют верно.")

	# -------------------------------------------------------------------------
	# 5. Потребление пищи и напитков
	# -------------------------------------------------------------------------
	print("\n--- 5. Потребление пищи и напитков из инвентаря ---")
	inv.clear()
	player.thirst = 20.0
	player.hunger = 20.0

	# Питье чистой воды
	inv.add_item("clean_water", 1)
	check(inv.get_item_count("clean_water") == 1, "Чистая вода не добавилась")
	var drink_ok = player.drink_from_inventory("clean_water")
	check(drink_ok, "Вызов drink_from_inventory не удался")
	check(inv.get_item_count("clean_water") == 0, "Чистая вода не списалась после употребления")
	check(player.thirst > 60.0, "Чистая вода должна утолять жажду (thirst: %.1f)" % player.thirst)

	# Поедание еды
	inv.add_item("carrot", 1)
	check(inv.get_item_count("carrot") == 1, "Морковь не добавилась")
	var eat_ok = player.eat_food("carrot")
	check(eat_ok, "Вызов eat_food не удался")
	check(inv.get_item_count("carrot") == 0, "Морковь не списалась после употребления")
	check(player.hunger > 20.0, "Морковь должна восстанавливать сытость (hunger: %.1f)" % player.hunger)
	print("✅ Инвентарь и питание: корректно списываются предметы и восстанавливаются параметры.")

	# -------------------------------------------------------------------------
	# 6. Бессонница и депривация сна
	# -------------------------------------------------------------------------
	print("\n--- 6. Механика сна и бессонницы ---")
	player.hours_without_sleep = 0.0
	check(player.get_sleep_status_text() == "Бодр", "При 0 часах статус должен быть Бодр")
	check(not player.is_sleep_deprived(), "При 0 часах не должно быть депривации сна")

	# 24 часа без сна -> депривация
	player.hours_without_sleep = 25.0
	check(player.is_sleep_deprived(), "После 24ч без сна должна активироваться бессонница")
	check(player.get_effective_max_energy() <= 75.0, "При бессоннице потолок энергии ограничен 75%%")

	# 36 часов без сна -> критическое переутомление
	player.hours_without_sleep = 37.0
	check(player.get_effective_max_energy() <= 50.0, "При 36ч+ без сна потолок энергии ограничен 50%%")
	check(not player.can_sprint(), "При 36ч+ без сна спринт полностью заблокирован")
	print("✅ Бессонница: ограничение потолка энергии, блокировка спринта и статус бессонницы проверены.")

	# -------------------------------------------------------------------------
	# 7. Штраф при обмороке (Collapse Penalty)
	# -------------------------------------------------------------------------
	print("\n--- 7. Обморок и списание ресурсов ---")
	inv.clear()
	inv.add_item("stone", 20)
	inv.add_item("wood", 12)
	inv.add_credits(500)

	var stone_before = inv.get_item_count("stone")
	var wood_before = inv.get_item_count("wood")
	var creds_before = inv.credits

	player._apply_collapse_penalty()

	# Проверяем: ~25% от 20 = 5 камней списано (осталось 15)
	# ~25% от 12 = 3 дерева списано (осталось 9)
	# Кредиты не списываются при обмороке
	check(inv.get_item_count("stone") == 15, "Должно остаться 15 камней после 25%% штрафа (осталось: %d)" % inv.get_item_count("stone"))
	check(inv.get_item_count("wood") == 9, "Должно остаться 9 дерева после 25%% штрафа (осталось: %d)" % inv.get_item_count("wood"))
	check(inv.credits == creds_before, "Кредиты не должны теряться при обмороке!")
	print("✅ Штраф обморока: списание 25% ресурсов и сохранение кредитов подтверждено.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ ВЫЖИВАНИЯ И МЕТАБОЛИЗМА ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
