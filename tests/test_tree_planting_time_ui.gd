extends SceneTree
## Деревья не отрастают сами — их сажают саженцами на пень; время: 1 игровой час = 1 мин
## (настраивается); окна HUD помещаются в экран, а текст не вылезает за края окон.

const SaveManager = preload("res://scripts/core/save_manager.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const MachinePanel = preload("res://scripts/ui/machine_panel.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const SAVE_PATH := "user://test_tree_planting.json"
const SETTINGS_PATH := "user://test_tree_planting_settings.cfg"

var errors: Array[String] = []
var world: Node
var player: Node
var hud: Node
var tree_node: Node
var frames := 0
var stage := 0
var _machine_panel: Control = null

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	GameSettings.settings_path = SETTINGS_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	GameSettings.load_settings()
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	match stage:
		0:
			_test_trees()
			_test_time()
			_test_settings()
			_open_windows_for_layout()
			stage = 1
			frames = 0
		1:
			if frames >= 4:
				_check_windows_fit()
				stage = 2
				frames = 0
		2:
			if frames >= 3:
				return _finish()
	return false

func _test_trees() -> void:
	player = world.get_node("Player")
	var forest: Array = world.get_node("Resources/Forest").get_children()
	for t in forest:
		if t.is_in_group("trees"):
			check(t.requires_planting, "%s: дерево должно требовать посадки" % t.name)
	tree_node = forest[0]
	var inv = player.inventory
	inv.remove_item("sapling", inv.get_item_count("sapling"))
	inv.equip_tool("axe")
	var guard := 0
	while not tree_node.is_depleted and guard < 20:
		tree_node._on_interacted(player)
		guard += 1
	check(tree_node.is_depleted, "Дерево не срублено")
	check(inv.get_item_count("sapling") == tree_node.sapling_yield, "При рубке не выпал саженец (есть %d)" % inv.get_item_count("sapling"))
	check(tree_node.is_interactable, "Пень должен оставаться интерактивным для посадки")
	check(not player._is_mining_resource(tree_node), "Посадка на пень не должна требовать замаха топором")
	# Само не отрастает даже через много времени.
	for i in 40:
		tree_node._process(60.0)
	check(tree_node.is_depleted and not tree_node.is_growing, "Срубленное дерево отросло само")
	check("Посадить" in tree_node.get_prompt(), "Подсказка пня не предлагает посадку: %s" % tree_node.get_prompt())
	# Без саженца посадить нельзя.
	inv.remove_item("sapling", inv.get_item_count("sapling"))
	tree_node._on_interacted(player)
	check(not tree_node.is_growing, "Посадка удалась без саженца")
	# С саженцем — растёт по игровым часам.
	inv.add_item("sapling", 2)
	tree_node._on_interacted(player)
	check(tree_node.is_growing, "Саженец не посажен")
	check(inv.get_item_count("sapling") == 1, "Саженец не списан при посадке")
	tree_node._on_interacted(player)
	check(inv.get_item_count("sapling") == 1, "Второй саженец списан на растущее дерево")
	var half: float = tree_node.growth_hours * 0.5
	tree_node.advance_growth(half)
	check(tree_node.is_depleted and is_equal_approx(tree_node.get_growth_ratio(), 0.5), "Рост на полпути работает неверно")
	var vis: Node3D = tree_node.visual_node
	check(vis.visible and vis.scale.y < tree_node._original_scale.y and vis.scale.y > 0.0, "Саженец не виден или не уменьшен")
	check("растёт" in tree_node.get_prompt(), "Подсказка не показывает рост")
	# Сохранение и загрузка растущего саженца.
	check(SaveManager.save_game(world, SAVE_PATH), "Сохранение не удалось")
	tree_node.advance_growth(tree_node.growth_hours)
	check(not tree_node.is_depleted, "Дерево не выросло за growth_hours")
	check(SaveManager.load_game(world, SAVE_PATH), "Загрузка не удалась")
	check(tree_node.is_depleted and tree_node.is_growing and is_equal_approx(tree_node.growth_progress_hours, half), "Состояние саженца не восстановлено из сохранения")
	SaveManager.delete_save(SAVE_PATH)
	# Рост идёт по игровому времени DayNightCycle: 1 час = 60 с по умолчанию.
	var remaining_hours: float = tree_node.growth_hours - tree_node.growth_progress_hours
	for i in int(ceil(remaining_hours)) + 1:
		tree_node._process(60.0)
	check(not tree_node.is_depleted and tree_node.current_hits == tree_node.max_hits, "Дерево не выросло по игровому времени")
	check(vis.scale.is_equal_approx(tree_node._original_scale), "Масштаб выросшего дерева не восстановлен")
	# Камни по-прежнему восстанавливаются сами.
	var rock = world.find_children("*", "Area3D", true, false).filter(func(n): return "required_tool" in n and n.required_tool == "pickaxe" and n.has_method("respawn"))
	if not rock.is_empty():
		check(not rock[0].requires_planting, "Камень не должен требовать посадки")
	check(ItemDB.get_item("sapling").get("name", "") == "Саженец", "Нет предмета «Саженец»")

func _test_time() -> void:
	var cycle = world.get_node("DayNightCycle")
	check(cycle.is_in_group("day_night_cycle"), "DayNightCycle не в группе")
	check(is_equal_approx(cycle.day_duration_seconds, 1440.0), "Сутки по умолчанию должны длиться 24 мин, а не %s с" % cycle.day_duration_seconds)
	check(is_equal_approx(cycle.get_seconds_per_game_hour(), 60.0), "1 игровой час должен длиться 60 с")
	cycle.set_time(1, 8.0)
	for i in 60:
		cycle._process(1.0)
	check(absf(cycle.current_hour - 9.0) < 0.001, "За 60 с прошёл не 1 час: %.3f" % cycle.current_hour)

func _test_settings() -> void:
	var cycle = world.get_node("DayNightCycle")
	check(is_equal_approx(GameSettings.get_seconds_per_game_hour(), 60.0), "По умолчанию в настройках должен быть 1 час = 60 с")
	GameSettings.set_value("seconds_per_game_hour", 120.0, self)
	check(is_equal_approx(cycle.day_duration_seconds, 2880.0), "Настройка длительности часа не применилась к суткам")
	GameSettings.set_value("seconds_per_game_hour", 99999.0, self)
	check(GameSettings.get_seconds_per_game_hour() <= GameSettings.GAME_HOUR_MAX, "Длительность часа не ограничена")
	GameSettings.load_settings()
	check(GameSettings.get_seconds_per_game_hour() <= GameSettings.GAME_HOUR_MAX, "Настройка не сохранилась в файл")
	var labels: Array[String] = GameSettings.get_game_hour_labels()
	check(labels.size() == GameSettings.GAME_HOUR_PRESETS.size(), "Нет подписей пресетов")
	check(labels[GameSettings.GAME_HOUR_PRESETS.find(60.0)].contains("по умолчанию"), "Пресет 1 мин не помечен по умолчанию")
	var panel = SettingsPanel.new()
	root.add_child(panel)
	check(panel._game_hour != null and panel._game_hour.item_count == GameSettings.GAME_HOUR_PRESETS.size(), "В окне настроек нет выбора длительности часа")
	panel._on_game_hour_selected(GameSettings.GAME_HOUR_PRESETS.find(30.0))
	check(is_equal_approx(cycle.day_duration_seconds, 720.0), "Выбор пресета в окне настроек не применился")
	check(panel._ui_scale != null, "В окне настроек нет масштаба интерфейса")
	panel.queue_free()
	GameSettings.reset_to_defaults(self)
	check(is_equal_approx(cycle.day_duration_seconds, 1440.0), "Сброс настроек не вернул 1 час = 60 с")
	check(is_equal_approx(root.content_scale_factor, 1.0), "Сброс не вернул масштаб интерфейса")

func _open_windows_for_layout() -> void:
	hud = world.get_node("HUD")
	ContractDB.completed_contracts.clear()
	hud.open_contract_window(world.find_child("TraderNPC", true, false))
	hud.victory_window.visible = true
	var machine = null
	for n in world.find_children("*", "Area3D", true, false):
		if n.has_method("start_batch"):
			if machine == null or "Верстак" in str(n.get("object_name")):
				machine = n
	check(machine != null, "Не найден станок")
	if machine:
		_machine_panel = MachinePanel.new()
		_machine_panel.setup(machine, player)
		hud.add_child(_machine_panel)

func _check_rect_inside(ctrl: Control, outer: Rect2, what: String) -> void:
	var r: Rect2 = ctrl.get_global_rect()
	check(r.position.x >= outer.position.x - 1.0 and r.end.x <= outer.end.x + 1.0,
		"%s: «%s» вылезает за окно по ширине (%.0f..%.0f при окне %.0f..%.0f)" % [what, str(ctrl.get("text")).left(40), r.position.x, r.end.x, outer.position.x, outer.end.x])

func _check_texts(win: Control, what: String) -> void:
	var outer: Rect2 = win.get_global_rect()
	for n in win.find_children("*", "", true, false):
		if (n is Label or n is Button) and n.is_visible_in_tree():
			var scroll_parent: Node = n.get_parent()
			while scroll_parent and not (scroll_parent is ScrollContainer) and scroll_parent != win:
				scroll_parent = scroll_parent.get_parent()
			var bounds: Rect2 = outer
			if scroll_parent is ScrollContainer:
				bounds = (scroll_parent as Control).get_global_rect()
			_check_rect_inside(n, bounds, what)
			if n is Label:
				check(n.get_theme_font_size("font_size") >= 13, "%s: слишком мелкий шрифт у «%s»" % [what, str(n.text).left(30)])

func _check_windows_fit() -> void:
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var screen := Rect2(Vector2.ZERO, vp)
	for win_name in hud.WINDOW_SIZES.keys():
		var win := hud.get_node(NodePath(win_name)) as Control
		if not win.visible:
			continue
		var r: Rect2 = win.get_global_rect()
		check(screen.encloses(r), "Окно %s не помещается в экран %s: %s" % [win_name, vp, r])
	_check_texts(hud.contract_window, "Заказы")
	_check_texts(hud.victory_window, "Финал")
	hud.victory_window.visible = false
	if _machine_panel:
		var panel_rect: Rect2 = _machine_panel.get_child(1).get_child(0).get_global_rect()
		check(screen.encloses(panel_rect), "Окно станка не помещается в экран: %s" % panel_rect)
		for n in _machine_panel.find_children("*", "Button", true, false):
			if n.is_visible_in_tree():
				_check_rect_inside(n, panel_rect, "Станок")
	hud.close_contract_window()
	hud.toggle_pause_menu()
	await_layout_then_check_pause()

func await_layout_then_check_pause() -> void:
	paused = true

func _finish() -> bool:
	_check_texts(hud.pause_window, "Пауза")
	hud.close_pause_menu()
	GameSettings.reset_to_defaults(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	if errors.is_empty():
		print("ТЕСТ ПРОЙДЕН: деревья сажаются саженцами, 1 игровой час = 1 мин (настраивается), окна HUD помещаются и текст не вылезает")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)
	return true
