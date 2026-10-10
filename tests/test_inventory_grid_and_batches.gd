extends SceneTree

## Регрессия: смена инструмента колесом, клеточный рюкзак, выброс и подбор предметов,
## партии станков (заказ N единиц продукции), сохранение партий и кучек, окна UI.

const WorldScene = preload("res://scenes/world/world.tscn")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const GameplayUIController = preload("res://scripts/ui/gameplay_ui_controller.gd")

const SAVE_PATH: String = "user://test_inventory_batches.json"

var _done: bool = false
var _failed: bool = false
var world: Node
var player: Node
var inv: Node
var crusher: Node

func _init() -> void:
	print(">>> Загрузка мира для теста инвентаря и партий...")
	world = WorldScene.instantiate()
	root.add_child(world)
	# Мир не должен сам тикать (погода, таймеры станков) — циклы завершаем вручную.
	world.process_mode = Node.PROCESS_MODE_DISABLED

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true

func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _check(cond: bool, reason: String) -> bool:
	if not cond:
		_fail(reason)
	return cond

func _run() -> void:
	player = world.find_child("Player", true, false)
	if not _check(player != null and "inventory" in player and player.inventory != null, "в мире нет игрока с инвентарём"):
		return
	inv = player.inventory
	crusher = world.find_child("StoneCrusher", true, false)
	if not _check(crusher is ProductionMachine and crusher.machine_type == "crusher", "в мире нет дробилки StoneCrusher"):
		return

	for step in [
		test_icons, test_tool_cycle, test_slot_stacks, test_drop_merge_pickup,
		test_cycles_for_amount, test_batch_stone_dust, test_cancel_without_refund,
		test_machine_inventory_storage,
		test_save_validation, test_save_load_batch_and_drops, test_ui_smoke
	]:
		step.call()
		if _failed:
			return
	print("🎉 ВСЕ ПРОВЕРКИ ИНВЕНТАРЯ И ПАРТИЙ ПРОЙДЕНЫ")
	quit(0)

func _reset_inventory() -> void:
	var hud: Node = world.find_child("HUD", true, false) if world else null
	if hud and hud.has_method("close_machine_window"):
		hud.close_machine_window()
	inv.clear()
	var t: Array[String] = ["axe", "pickaxe", "shovel", "bucket", "backpack"]
	inv.tools = t
	inv.recalculate_capacity()
	inv.equip_tool("axe")

func _live_piles() -> Array:
	var result: Array = []
	for n in world.get_tree().get_nodes_in_group(DroppedItemScript.GROUP):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			result.append(n)
	return result

# --- Иконки ---

func test_icons() -> void:
	print("\n--- 1. У каждого предмета есть иконка ---")
	var ids: Array = inv.items.keys()
	ids.append_array(["axe", "pickaxe", "shovel", "bucket", "backpack"])
	for id in ids:
		if not _check(ItemIcons.get_texture(id) != null, "нет иконки для «%s»" % id):
			return
	print("✅ Иконки есть у %d предметов" % ids.size())

# --- Колесо мыши ---

func test_tool_cycle() -> void:
	print("\n--- 2. Смена инструмента по кругу (рюкзак пропускается) ---")
	_reset_inventory()
	if not _check(inv.cycle_tool(1) == "pickaxe", "колесо вниз: ожидалась кирка, в руках %s" % inv.equipped_tool):
		return
	inv.equip_tool("axe")
	if not _check(inv.cycle_tool(-1) == "bucket", "колесо вверх с топора должно дать ведро (без рюкзака), в руках %s" % inv.equipped_tool):
		return
	if not _check(inv.cycle_tool(1) == "axe", "с ведра по кругу должен быть топор"):
		return
	print("✅ Топор → кирка, топор ← ведро, ведро → топор")

# --- Клетки рюкзака ---

func test_slot_stacks() -> void:
	print("\n--- 3. Раскладка по клеткам и лимит слотов ---")
	_reset_inventory()
	var stack: int = inv.get_max_stack("stone")
	if not _check(stack >= 4, "стек камня слишком мал для теста: %d" % stack):
		return
	inv.max_slots = 2
	inv.items["stone"] = stack + 3
	var cells: Array = inv.get_slot_stacks()
	if not _check(cells.size() == 2, "ожидалось 2 клетки, получено %d" % cells.size()):
		return
	if not _check(int(cells[0]["count"]) == stack and int(cells[1]["count"]) == 3, "неверные количества в клетках: %s" % str(cells)):
		return
	if not _check(inv.get_free_slots() == 0, "свободных слотов быть не должно"):
		return
	if not _check(inv.get_max_addable("stone", 1000) == stack - 3, "get_max_addable должен вернуть остаток неполного стека (%d)" % (stack - 3)):
		return
	if not _check(not inv.can_add_item("wood", 1), "новый предмет не должен помещаться без свободного слота"):
		return
	_reset_inventory()
	print("✅ %d камней = клетки [%d][3], доложить можно %d" % [stack + 3, stack, stack - 3])

# --- Выброс и подбор ---

func test_drop_merge_pickup() -> void:
	print("\n--- 4. Выброс, слияние кучек и подбор ---")
	_reset_inventory()
	inv.add_item("stone", 12)
	var pile = DroppedItemScript.drop_from_player(player, "stone", 5)
	if not _check(pile != null and inv.get_item_count("stone") == 7, "выброс 5 камней не сработал"):
		return
	var pile2 = DroppedItemScript.drop_from_player(player, "stone", 5)
	if not _check(pile2 == pile and int(pile.amount) == 10, "вторая кучка рядом должна слиться с первой"):
		return
	if not _check(DroppedItemScript.drop_from_player(player, "stone", 3) == null and inv.get_item_count("stone") == 2, "нельзя выбросить больше, чем есть"):
		return
	if not _check(DroppedItemScript.drop_from_player(player, "axe", 1) == null, "инструмент с пояса выбрасывать нельзя"):
		return
	pile._on_interacted(player)
	if not _check(inv.get_item_count("stone") == 12, "после подбора должно быть 12 камней, есть %d" % inv.get_item_count("stone")):
		return
	if not _check(_live_piles().is_empty(), "подобранная кучка должна исчезнуть"):
		return
	_reset_inventory()
	print("✅ 5+5 камней → одна кучка ×10 → подобрана целиком")

# --- Партии ---

func test_cycles_for_amount() -> void:
	print("\n--- 5. Заказ количества: только кратно выходу цикла ---")
	var recipe: Dictionary = RecipeDB.get_recipe("crush_stone")
	if not _check(not recipe.is_empty(), "нет рецепта crush_stone"):
		return
	if not _check(ProductionMachine.cycles_for_amount(recipe, 10) == 10, "10 каменной пыли = 10 циклов"):
		return
	if not _check(ProductionMachine.cycles_for_amount(recipe, 0) == 0, "0 единиц = 0 циклов"):
		return
	var double_out: Dictionary = {"outputs": {"stone_dust": 2}}
	if not _check(ProductionMachine.cycles_for_amount(double_out, 3) == 0 and ProductionMachine.cycles_for_amount(double_out, 4) == 2, "некратное количество должно отклоняться"):
		return
	_reset_inventory()
	inv.add_item("stone", 9)
	if not _check(ProductionMachine.get_max_cycles(recipe, inv) == 4, "из 9 камней можно сделать 4 цикла"):
		return
	_reset_inventory()
	print("✅ cycles_for_amount и get_max_cycles корректны")

func test_batch_stone_dust() -> void:
	print("\n--- 6. Партия: 10 каменной пыли из 20 камней ---")
	_reset_inventory()
	inv.add_item("stone", 20)
	if not _check(crusher.start_batch("crush_stone", 11, player) == false, "на 11 циклов сырья не хватает — старт должен быть отклонён"):
		return
	if not _check(crusher.start_batch("crush_stone", 10, player), "партия из 10 циклов не запустилась"):
		return
	if not _check(inv.get_item_count("stone") == 0, "сырьё на всю партию должно списаться при старте"):
		return
	if not _check(crusher.is_machine_running and crusher.batch_cycles_total == 10 and crusher.batch_to_buffer, "состояние партии неверно"):
		return
	for i in range(10):
		crusher._complete_process()
	if not _check(not crusher.is_machine_running, "после 10 циклов станок должен остановиться"):
		return
	if not _check(int(crusher.pending_outputs.get("stone_dust", 0)) == 10 and inv.get_item_count("stone_dust") == 0, "продукция партии должна копиться в станке"):
		return
	if not _check(crusher.collect_outputs(player) and inv.get_item_count("stone_dust") == 10, "«Забрать» должно выдать 10 каменной пыли"):
		return
	_reset_inventory()
	print("✅ 20 камней → 10 циклов → 10 каменной пыли в рюкзаке")

func test_cancel_without_refund() -> void:
	print("\n--- 7. Отмена партии без возврата сырья ---")
	_reset_inventory()
	inv.add_item("stone", 6)
	if not _check(crusher.start_batch("crush_stone", 3, player), "партия из 3 циклов не запустилась"):
		return
	crusher._complete_process()
	if not _check(crusher.cancel_batch(), "отмена должна сработать"):
		return
	if not _check(not crusher.is_machine_running and inv.get_item_count("stone") == 0, "после отмены сырьё не возвращается"):
		return
	if not _check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1, "уже готовая продукция остаётся в станке"):
		return
	crusher.collect_outputs(player)
	_reset_inventory()
	print("✅ Отмена: сырьё не вернулось, готовая пыль сохранена")

func test_machine_inventory_storage() -> void:
	print("\n--- 7b. Продукция в инвентаре станка и отсутствие автосбора при [E] ---")
	_reset_inventory()
	inv.add_item("stone", 2)
	crusher.pending_outputs = {}
	if not _check(crusher.start_recipe("crush_stone", player), "одиночный запуск crush_stone должен сработать"):
		return
	crusher._complete_process()
	if not _check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1, "готовая продукция должна оказаться в инвентаре станка"):
		return
	if not _check(inv.get_item_count("stone_dust") == 0, "продукция НЕ должна попадать в рюкзак игрока автоматически"):
		return
	
	# Проверка взаимодействия [E]: не должно автоматически вычищать инвентарь станка в рюкзак
	var opened_emitted: Array = [false]
	var cb := func(_m): opened_emitted[0] = true
	crusher.machine_opened.connect(cb, CONNECT_ONE_SHOT)
	crusher._on_interacted(player)
	if not _check(opened_emitted[0], "взаимодействие должно слать machine_opened"):
		return
	if not _check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1 and inv.get_item_count("stone_dust") == 0, "при взаимодействии [E] продукция остаётся в станке"):
		return
	
	# Точечный забор предмета (клик по ячейке в окне)
	var taken: int = crusher.collect_output_item("stone_dust", player)
	if not _check(taken == 1 and crusher.pending_outputs.is_empty() and inv.get_item_count("stone_dust") == 1, "collect_output_item должен перенести предмет в рюкзак"):
		return
	_reset_inventory()
	print("✅ Готовая продукция надёжно хранится в станке и забирается игроком по требованию")

# --- Сохранения ---

func test_save_validation() -> void:
	print("\n--- 8. Валидация новых полей сохранения ---")
	var ok_drop: Dictionary = {"dropped_items": [{"item_id": "stone", "amount": 3.0, "x": 1.0, "y": 0.0, "z": -2.0}]}
	if not _check(SaveManagerScript._validate_save_data(ok_drop), "корректная кучка должна проходить валидацию"):
		return
	var bad_cases: Array = [
		{"dropped_items": {}},
		{"dropped_items": [{"item_id": "no_such_item", "amount": 1, "x": 0, "y": 0, "z": 0}]},
		{"dropped_items": [{"item_id": "stone", "amount": 0, "x": 0, "y": 0, "z": 0}]},
		{"dropped_items": [{"item_id": "stone", "amount": 1, "x": 0, "y": 0}]},
		{"machines": [{"path": "StoneCrusher", "recipe_id": "", "timer": 0.0, "duration": 1.0, "batch_total": 500}]},
		{"machines": [{"path": "StoneCrusher", "recipe_id": "", "timer": 0.0, "duration": 1.0, "batch_done": -1}]},
		{"machines": [{"path": "StoneCrusher", "recipe_id": "", "timer": 0.0, "duration": 1.0, "batch_to_buffer": "yes"}]},
	]
	for data in bad_cases:
		if not _check(not SaveManagerScript._validate_save_data(data), "некорректные данные прошли валидацию: %s" % str(data)):
			return
	print("✅ Корректные данные принимаются, %d некорректных отклонено" % bad_cases.size())

func test_save_load_batch_and_drops() -> void:
	print("\n--- 9. Сохранение и загрузка партии и выброшенных предметов ---")
	_reset_inventory()
	inv.add_item("stone", 10)
	if not _check(crusher.start_batch("crush_stone", 3, player), "партия для сохранения не запустилась"):
		return
	crusher._complete_process()
	var pile = DroppedItemScript.drop_from_player(player, "stone", 4)
	if not _check(pile != null, "выброс перед сохранением не сработал"):
		return
	var pile_pos: Vector3 = pile.global_position
	if not _check(SaveManagerScript.save_game(world, SAVE_PATH), "сохранение не записано"):
		return

	# Ломаем состояние: отменяем партию, забираем пыль и убираем кучку.
	crusher.cancel_batch()
	crusher.pending_outputs = {}
	pile.consume()

	if not _check(SaveManagerScript.load_game(world, SAVE_PATH), "загрузка не удалась"):
		return
	if not _check(crusher.is_machine_running and crusher.batch_cycles_total == 3 and crusher.batch_cycles_done == 1 and crusher.batch_to_buffer, "партия не восстановилась: running=%s total=%d done=%d" % [str(crusher.is_machine_running), crusher.batch_cycles_total, crusher.batch_cycles_done]):
		return
	if not _check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1, "накопленная пыль не восстановилась"):
		return
	var piles: Array = _live_piles()
	if not _check(piles.size() == 1 and piles[0].item_id == "stone" and int(piles[0].amount) == 4, "кучка не восстановилась (найдено %d)" % piles.size()):
		return
	if not _check(piles[0].global_position.distance_to(pile_pos) < 0.01, "кучка восстановлена не на своём месте"):
		return
	# Доводим партию после загрузки: ещё 2 цикла → итого 3 пыли.
	crusher._complete_process()
	crusher._complete_process()
	if not _check(not crusher.is_machine_running and int(crusher.pending_outputs.get("stone_dust", 0)) == 3, "восстановленная партия должна дойти до 3 циклов"):
		return
	crusher.collect_outputs(player)
	for p in _live_piles():
		p.consume()
	_reset_inventory()
	DirAccess.remove_absolute(SAVE_PATH)
	print("✅ Партия 1/3 и кучка ×4 пережили сохранение и загрузку")

# --- UI ---

func test_ui_smoke() -> void:
	print("\n--- 10. Окна рюкзака и станка, колесо мыши ---")
	_reset_inventory()
	inv.add_item("stone", 5)
	inv.add_item("wood", 3)

	var grid = ItemGrid.new()
	root.add_child(grid)
	grid.set_stacks(inv.get_slot_stacks(), inv.max_slots)
	if not _check(grid.get_child_count() >= inv.max_slots, "сетка должна показать %d клеток" % inv.max_slots):
		return
	grid.queue_free()

	var hud: Node = world.find_child("HUD", true, false)
	var ui = GameplayUIController.new()
	ui.name = "GameplayUIController"
	ui.setup(hud, world, player)
	root.add_child(ui)

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	if not _check(ui.handle_wheel(wheel) and inv.equipped_tool == "pickaxe", "колесо вниз должно взять кирку (в руках %s)" % inv.equipped_tool):
		return
	var ctrl_wheel := InputEventMouseButton.new()
	ctrl_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	ctrl_wheel.pressed = true
	ctrl_wheel.ctrl_pressed = true
	if not _check(not ui.handle_wheel(ctrl_wheel) and inv.equipped_tool == "pickaxe", "Ctrl + колесо — зум камеры, инструмент меняться не должен"):
		return

	var inv_panel = ui.open_inventory_panel()
	if not _check(inv_panel != null and ui.is_panel_open(), "окно рюкзака не открылось"):
		return
	if not _check(player.process_mode == Node.PROCESS_MODE_DISABLED, "пока открыто окно, персонаж не должен управляться"):
		return
	if not _check(not ui.handle_wheel(wheel), "при открытом окне колесо не меняет инструмент"):
		return
	ui.close_panel()
	if not _check(not ui.is_panel_open(), "окно рюкзака не закрылось"):
		return

	var m_panel = ui.open_machine_panel(crusher)
	if not _check(m_panel != null and ui.is_panel_open(), "окно станка не открылось"):
		return
	ui.close_panel()
	if not _check(not ui.is_panel_open(), "окно станка не закрылось"):
		return
	ui.queue_free()
	_reset_inventory()
	print("✅ Сетка, окна рюкзака и станка открываются и закрываются; колесо/Ctrl+колесо разделены")
