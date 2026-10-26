extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const SleepDialogScene = preload("res://scripts/ui/sleep_dialog.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования PrimitiveBed и проверки рецептов брикетов...")
	var world_node = WorldScene.instantiate()
	root.add_child(world_node)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _run_tests() -> void:
	print("====================================================")
	print("🧪 ЗАПУСК ТЕСТОВ: ПРИМИТИВНАЯ ЛЕЖАНКА И РЕЦЕПТЫ БРИКЕТОВ")
	print("====================================================")

	# 1. Проверка удаления дублирующегося рецепта угольных брикетов
	if RecipeDB.RECIPES.has("craft_coal_briquette"):
		_fail("Дублирующийся рецепт craft_coal_briquette не должен присутствовать в RecipeDB")
		return

	if not RecipeDB.RECIPES.has("press_coal_briquette"):
		_fail("Канонический рецепт press_coal_briquette должен присутствовать в RecipeDB")
		return

	var coal_briquette_recipe = RecipeDB.get_recipe("press_coal_briquette")
	if coal_briquette_recipe["inputs"].get("coal", 0) != 2:
		_fail("Рецепт press_coal_briquette должен требовать 2 угля")
		return
	if coal_briquette_recipe["outputs"].get("fuel_briquette", 0) != 3:
		_fail("Рецепт press_coal_briquette должен производить 3 топливных брикета")
		return

	if not RecipeDB.RECIPES.has("craft_briquette"):
		_fail("Рецепт древесных брикетов craft_briquette должен присутствовать в RecipeDB")
		return

	print("  • База рецептов проверена: дубликат удален, канонический рецепт сохранен")

	# 2. Проверка размещения и доступности PrimitiveBed в мире
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return

	var bed = world.get_node_or_null("Props/PrimitiveBed")
	if not bed:
		_fail("Узел Props/PrimitiveBed не найден в сцене World")
		return

	if not (bed is PrimitiveBed):
		_fail("Props/PrimitiveBed не является экземпляром PrimitiveBed")
		return

	if not bed.can_sleep():
		_fail("Примитивная лежанка должна быть доступна сразу со старта (can_sleep() == true)")
		return

	if not bed.is_in_group("interactables"):
		_fail("Лежанка должна быть в группе interactables")
		return

	if not bed.is_in_group("rest_spots"):
		_fail("Лежанка должна быть в группе rest_spots")
		return

	# Проверка расположения возле костра
	var campfire = world.get_node_or_null("Props/Campfire")
	if not campfire:
		_fail("Костёр Props/Campfire не найден в сцене")
		return

	var dist_to_campfire = bed.global_position.distance_to(campfire.global_position)
	print("  • Расстояние между лежанкой и костром: %.2f м" % dist_to_campfire)
	if dist_to_campfire < 1.0 or dist_to_campfire > 4.0:
		_fail("Лежанка должна располагаться возле костра (1.0 - 4.0 м), получено: %.2f м" % dist_to_campfire)
		return

	print("  • Лежанка успешно размещена возле костра и доступна сразу")

	# 3. Тестирование сна / отдыха
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Игрок Player не найден в сцене")
		return

	player.energy = 25.0
	player.health = 40.0
	player.hours_without_sleep = 16.0

	# Вызов сна на 6 часов (полноценный сон)
	bed.sleep(player, 6.0)

	if player.energy < 90.0:
		_fail("После 6 часов сна энергия игрока должна восстановиться (>=90%%), текущая: %.1f" % player.energy)
		return

	if player.hours_without_sleep != 0.0:
		_fail("После сна бессонница должна быть сброшена в 0.0, текущая: %.1f" % player.hours_without_sleep)
		return

	print("  • Механика сна и снятия усталости через лежанку подтверждена")

	# 4. Проверка диалога сна (SleepDialog)
	var sleep_dialog = SleepDialogScene.new()
	sleep_dialog.setup(bed, player, "😴 Примитивная лежанка")
	world.add_child(sleep_dialog)

	if sleep_dialog.custom_title != "😴 Примитивная лежанка":
		_fail("SleepDialog должен принимать кастомный заголовок лежанки")
		return

	sleep_dialog.queue_free()
	print("  • Диалог сна SleepDialog корректно настраивается и адаптируется к лежанке")

	print("\n====================================================")
	print("🎉 ВСЕ ТЕСТЫ PRIMITIVE BED УСПЕШНО ПРОЙДЕНЫ!")
	print("====================================================")
	quit(0)
