extends SceneTree
## Клеточный рюкзак как в индустрии: у стека постоянная клетка, перетаскивание
## меняет клетки местами, новые предметы ложатся в первую свободную, сортировка,
## раскладка сохраняется; сетка окна рюкзака компилируется и показывает добычу.
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
var errors: Array[String] = []
var world: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _cell_ids(inv) -> Array:
	return inv.get_slot_cells().map(func(c): return str(c.get("item_id", "")))

func _initialize() -> void:
	var inv = InventoryScript.new()
	root.add_child(inv)
	# 1. Добыча сразу видна в клетке
	inv.add_item("stone", 22)
	var cells: Array = inv.get_slot_cells()
	check(cells.size() == inv.max_slots, "Клеток %d, а слотов %d" % [cells.size(), inv.max_slots])
	check(cells[0].get("item_id", "") == "stone" and cells[0].get("count", 0) == 22, "Камень не в первой клетке: %s" % [cells[0]])
	inv.add_item("wood", 5)
	check(_cell_ids(inv).slice(0, 2) == ["stone", "wood"], "Новый предмет не лёг в первую свободную клетку")
	# 2. Перетаскивание: перенос в пустую клетку и обмен
	check(inv.move_slot(0, 7), "move_slot в пустую клетку не сработал")
	check(_cell_ids(inv)[7] == "stone" and _cell_ids(inv)[0] == "", "Камень не переехал в клетку 8")
	inv.add_item("clay", 2)
	check(_cell_ids(inv)[0] == "clay", "Новый предмет не занял освободившуюся клетку 1")
	inv.move_slot(7, 1)  # камень <-> дерево
	check(_cell_ids(inv)[1] == "stone" and _cell_ids(inv)[7] == "wood", "Обмен клеток не сработал")
	# 3. Позиция держится при изменении количества и пропадает при нуле
	inv.add_item("stone", 3)
	check(_cell_ids(inv)[1] == "stone" and inv.get_slot_cells()[1].count == 25, "Стек камня сдвинулся при добыче")
	inv.remove_item("clay", 2)
	check(_cell_ids(inv)[0] == "", "Пустой стек не освободил клетку")
	# 4. Несколько стеков одного предмета (max_stack)
	var stack: int = inv.get_max_stack("stone")
	inv.add_item("stone", stack)
	var stone_cells: Array = inv.get_slot_cells().filter(func(c): return c.get("item_id", "") == "stone")
	check(stone_cells.size() == 2 and stone_cells[0].count == stack, "Переполненный стек не разделился на 2 клетки")
	# 5. Сортировка
	inv.sort_slots()
	var ids: Array = _cell_ids(inv).filter(func(x): return x != "")
	var first_stone: int = ids.find("stone")
	check(ids.size() == 3 and first_stone != -1 and first_stone + 1 < ids.size() and ids[first_stone + 1] == "stone", "Сортировка не сложила одинаковые стеки рядом: %s" % [ids])
	check(_cell_ids(inv)[0] != "", "После сортировки первая клетка пуста")
	inv.queue_free()
	# 6. Окно рюкзака: сетка компилируется и показывает добычу
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var player = world.get_node("Player")
	var inv = player.inventory
	inv.add_item("stone", 22)
	inv.add_item("water", 2)
	var panel = InventoryPanel.new()
	panel.setup(player)
	world.get_node("HUD").add_child(panel)
	var grid = panel._grid
	check(grid != null and grid.get_script() == ItemGrid, "В окне рюкзака нет сетки ItemGrid")
	if grid:
		check(grid.get_visible_cell_count() == inv.max_slots, "Сетка показывает %d клеток вместо %d" % [grid.get_visible_cell_count(), inv.max_slots])
		var shown: Array = []
		for i in grid.get_visible_cell_count():
			var st: Dictionary = grid.get_cell_stack(i)
			if not st.is_empty():
				shown.append(st.item_id)
		check(shown.has("stone") and shown.has("water"), "Камень/вода не видны в клетках: %s" % [shown])
		# drag-and-drop через сам виджет
		var idx: int = inv.slot_layout.find("stone")
		var data = grid._get_cell_drag_data(Vector2.ZERO, idx)
		check(data is Dictionary and grid._can_drop_on_cell(Vector2.ZERO, data, 10), "Клетку нельзя перетащить")
		grid._drop_on_cell(Vector2.ZERO, data, 10)
		check(inv.slot_layout[10] == "stone", "Перетаскивание в сетке не переложило камень")
		# 7. Раскладка сохраняется
		SaveManager.save_game(world, "user://slots_test.json")
		inv.sort_slots()
		SaveManager.load_game(world, "user://slots_test.json")
		check(inv.slot_layout.size() > 10 and inv.slot_layout[10] == "stone", "Раскладка не восстановилась из сохранения")
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://slots_test.json"))
	panel.queue_free()
	if errors.is_empty():
		print("ТЕСТ ПРОЙДЕН: клеточный рюкзак — клетки, перетаскивание, сортировка, сохранение")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("ТЕСТ ПРОВАЛЕН")
		quit(1)
	return true
