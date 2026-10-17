extends SceneTree
## Тестирование исправления 4 багов:
## 1. Ночное освещение (00:13 темно, солнце 0.0, луна умеренная, амбиент приглушён).
## 2. Длительность сна (1 час не восстанавливает 100% энергии, не объявляет рассвет без смены дня; расчет до 6:00).
## 3. Крафт оселка из рюкзака (2 камня + 1 песок -> 1 оселок).
## 4. Форматирование рецептов в станках без формулы 1x1=2.

const WorldScene = preload("res://scenes/world/world.tscn")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const MachinePanel = preload("res://scripts/ui/machine_panel.gd")
const SleepDialog = preload("res://scripts/ui/sleep_dialog.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("========================================")
	print("🧪 ТЕСТ ИСПРАВЛЕНИЯ 4 БАГОВ")
	print("========================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var dc = world.get_node_or_null("DayNightCycle")
	check(dc != null, "DayNightCycle не найден")
	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var env_mgr = world.get_node_or_null("LightingEnvManager")

	# --- 1. Ночное освещение в 00:13 ---
	print("\n--- 1. Проверка ночного освещения в 00:13 ---")
	if dc:
		dc.current_hour = 0.217 # 00:13
		dc._process(0.016)
		check(dc.is_night(), "В 00:13 должна быть ночь (is_night == true)")
		var sun = dc.sun_light
		check(sun != null, "SunLight не найден")
		if sun:
			check(sun.light_energy <= 0.001, "Ночью солнце должно быть выключено (energy: %.3f)" % sun.light_energy)
		var moon = dc.get("_moon_light")
		if moon:
			check(moon.light_energy <= 0.15, "Ночью свет луны должен быть мягким (energy: %.3f)" % moon.light_energy)
		if env_mgr and env_mgr.world_environment and env_mgr.world_environment.environment:
			var env = env_mgr.world_environment.environment
			check(env.ambient_light_energy <= 0.20, "Ночной амбиент должен быть темным (energy: %.3f)" % env.ambient_light_energy)
		print("✅ Ночное освещение: солнце 0.0, луна умеренная, амбиент тёмный.")

	# --- 2. Длительность сна и частичное восстановление ---
	print("\n--- 2. Проверка сна и выбора времени ---")
	if player and dc:
		dc.current_day = 1
		dc.current_hour = 14.0 # Середина дня
		player.energy = 20.0
		player.health = 80.0
		var notifs: Array[String] = []
		var notif_cb = func(txt: String): notifs.append(txt)
		player.notification_received.connect(notif_cb)

		# Сон 1 час
		player.start_rest(1.0, true)
		check(player.energy < 50.0, "Сон на 1 час не должен восстанавливать энергию до максимума (энергия: %.1f)" % player.energy)
		check(player.energy > 20.0, "Сон на 1 час должен немного восстановить энергию (энергия: %.1f)" % player.energy)
		var has_new_day_notif: bool = false
		for n in notifs:
			if "Наступил День" in n:
				has_new_day_notif = true
		check(not has_new_day_notif, "Сон на 1 час в середине дня не должен объявлять новый день!")

		# Полноценный сон 8 часов
		player.energy = 20.0
		player.start_rest(8.0, true)
		check(player.energy >= 99.9, "Полноценный сон 8 часов должен восстанавливать 100%% энергии (энергия: %.1f)" % player.energy)
		player.notification_received.disconnect(notif_cb)
		print("✅ Сон: 1 час восстанавливает силы частично без ложного рассвета, 8 часов — на 100%.")

	# --- 3. Крафт оселка в рюкзаке ---
	print("\n--- 3. Проверка крафта оселка в рюкзаке ---")
	if player and player.inventory:
		var inv = player.inventory
		inv.clear()
		inv.add_item("stone", 5)
		inv.add_item("sand", 3)

		var inv_ui = InventoryPanel.new()
		inv_ui.setup(player)
		root.add_child(inv_ui)
		check(is_instance_valid(inv_ui._whetstone_header_btn), "Кнопка крафта оселка в шапке рюкзака не найдена")

		# Крафтим оселок (теперь это задача на 6 секунд с прогресс-баром)
		inv_ui._craft_whetstone_in_backpack()
		check(inv_ui._task_kind == "craft_whetstone", "Крафт оселка должен запускать 6-секундную задачу")
		inv_ui._process(6.1)
		check(inv.get_item_count("whetstone") == 1, "Оселок не добавился в инвентарь (кол-во: %d)" % inv.get_item_count("whetstone"))
		check(inv.get_item_count("stone") == 3, "Камень не списался корректно (осталось: %d, ожидалось 3)" % inv.get_item_count("stone"))
		check(inv.get_item_count("sand") == 2, "Песок не списался корректно (осталось: %d, ожидалось 2)" % inv.get_item_count("sand"))
		check(inv_ui._selected == "whetstone", "После крафта оселок должен автоматически выбираться в рюкзаке")

		# Пробуем крафтить при недостатке ресурсов
		inv.remove_item("stone", 3)
		inv_ui._craft_whetstone_in_backpack()
		check(inv.get_item_count("whetstone") == 1, "Оселок скрафтился без нужного количества камней!")

		inv_ui.queue_free()
		print("✅ Крафт оселка в рюкзаке: работает списание 2 камней + 1 песка, проверка ресурсов и автовыбор.")

	# --- 4. Отображение рецептов без формулы ---
	print("\n--- 4. Проверка отображения рецептов станков ---")
	var crusher = world.find_child("StoneCrusher", true, false)
	if crusher and player:
		var mp = MachinePanel.new()
		mp.setup(crusher, player)
		root.add_child(mp)
		var test_recipe = {
			"id": "test_recipe",
			"name": "Тестовый рецепт",
			"inputs": {"stone": 2},
			"outputs": {"stone_dust": 1},
			"duration": 5.0,
			"energy_cost": 1.0
		}
		mp._selected_recipe = test_recipe
		mp._refresh_order()

		var found_formula: bool = false
		var found_clean_needed: bool = false
		for child in mp._inputs_box.get_children():
			var lbl: Label = null
			if child is Label:
				lbl = child
			elif child is HBoxContainer:
				for sub in child.get_children():
					if sub is Label:
						lbl = sub
						break
			if lbl:
				var t: String = lbl.text
				if "×" in t and "=" in t:
					found_formula = true
				if "нужно 2" in t:
					found_clean_needed = true
		check(not found_formula, "В панели станка не должно быть формулы 'need × cycles = total'!")
		check(found_clean_needed, "В панели станка должна быть строчка 'нужно 2 (есть X)'!")
		mp.queue_free()
		print("✅ Отображение рецептов: чистый понятный вид 'нужно N (есть M)' без математической формулы.")

	# Завершение теста
	world.queue_free()
	if errors.is_empty():
		print("\n========================================")
		print("🎉 ВСЕ 4 БАГА УСПЕШНО ИСПРАВЛЕНЫ И ПРОТЕСТИРОВАНЫ!")
		print("========================================")
		quit(0)
	else:
		print("\n========================================")
		print("❌ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("========================================")
		quit(1)
