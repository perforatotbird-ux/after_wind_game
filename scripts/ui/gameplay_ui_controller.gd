extends Node

## Игровые окна поверх HUD: клеточный рюкзак (TAB / I / слот 5) и окно станка
## с заказом партии, а также смена инструмента колесом мыши (Ctrl + колесо — зум
## камеры, см. isometric_camera.gd). Перехватывает сигналы, которые раньше открывали
## старые окна HUD (toggle_inventory / open_machine_window). Пока окно открыто,
## управление персонажем выключено. Создаётся в world.gd (_init_session).

const StoragePanel = preload("res://scripts/ui/storage_panel.gd")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const MachinePanel = preload("res://scripts/ui/machine_panel.gd")
const FarmFieldPlacer = preload("res://scripts/farming/farm_field_placer.gd")
const FruitTreePlacer = preload("res://scripts/farming/fruit_tree_placer.gd")
const FarmlandPlotScene = preload("res://scenes/farming/farmland_plot.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

## Классическая грядка (farmland_plot: mounded → tilled): материалы и размер пятна.
const FARMLAND_PLOT_COST: Dictionary = {"wood": 4, "stone": 2}
const FARMLAND_PLOT_SIZE: Vector2 = Vector2(2.6, 1.6)

const SLOT5_PATH: String = "HotbarUI/Panel/Margin/HBox/Slot5"

var hud: Node
var world: Node
var player: Node

var _panel: Control
var _player_prev_mode: int = Node.PROCESS_MODE_INHERIT
## Как часто перепроверяем подключения интерактивных объектов: станки и
## постройки могут появиться в мире уже после старта (сохранение, постройка).
const REWIRE_INTERVAL: float = 5.0
var _rewire_timer: float = 0.0

func setup(p_hud: Node, p_world: Node, p_player: Node) -> void:
	hud = p_hud
	world = p_world
	player = p_player

func _ready() -> void:
	_rewire()

func _process(delta: float) -> void:
	_rewire_timer += delta
	if _rewire_timer >= REWIRE_INTERVAL:
		_rewire_timer = 0.0
		_rewire()

func _rewire() -> void:
	if player and player.has_signal("inventory_toggle_requested"):
		_disconnect_from(player.inventory_toggle_requested, hud)
		if not player.inventory_toggle_requested.is_connected(toggle_inventory_panel):
			player.inventory_toggle_requested.connect(toggle_inventory_panel)
	if hud:
		var slot5 = hud.get_node_or_null(SLOT5_PATH)
		if slot5 is BaseButton:
			for c in slot5.pressed.get_connections():
				slot5.pressed.disconnect(c["callable"])
			slot5.pressed.connect(toggle_inventory_panel)
	if world:
		for node in world.find_children("*", "Area3D", true, false):
			if node.has_signal("building_opened"):
				_disconnect_from(node.building_opened, hud)
				if not node.building_opened.is_connected(open_building_panel):
					node.building_opened.connect(open_building_panel)
			if node.has_signal("machine_opened"):
				_disconnect_from(node.machine_opened, hud)
				if not node.machine_opened.is_connected(open_machine_panel):
					node.machine_opened.connect(open_machine_panel)

## Отключает от сигнала все обработчики объекта target (старые окна HUD).
static func _disconnect_from(sig: Signal, target: Object) -> void:
	if target == null:
		return
	for c in sig.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_object() == target:
			sig.disconnect(cb)

func is_panel_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and not _panel.is_queued_for_deletion()

func get_open_panel() -> Control:
	return _panel if is_panel_open() else null

func toggle_inventory_panel() -> void:
	if is_panel_open():
		close_panel()
	else:
		open_inventory_panel()

func open_inventory_panel() -> Control:
	var p = InventoryPanel.new()
	p.setup(player)
	p.build_requested.connect(start_placement)
	_open(p)
	return p

func open_building_panel(building: Node) -> void:
	if building.has_method("is_storage_ready") and building.is_storage_ready():
		open_storage_panel(building)
	elif hud:
		hud.open_repair_window(building)

func open_storage_panel(building: Node) -> Control:
	if not building.has_method("is_storage_ready") or not building.is_storage_ready(): return null
	if hud and hud.has_method("close_repair_window"): hud.close_repair_window()
	var p = StoragePanel.new()
	p.setup(player, building)
	p.repair_requested.connect(func():
		close_panel()
		if hud: hud.open_repair_window(building)
	)
	_open(p)
	return p

var _placer: Node = null

## Режим размещения постройки мышкой (делянка или фруктовое дерево). Рюкзак закрывается.
func start_placement(kind: String = "farm_field") -> Node:
	if world == null:
		return null
	close_panel()
	if is_instance_valid(_placer):
		_placer.queue_free()
	if kind == "farm_field":
		_placer = FarmFieldPlacer.new()
		_placer.name = "FarmFieldPlacer"
		_placer.setup(world, player)
		world.add_child(_placer)
		return _placer
	elif kind == "farmland_plot":
		_place_farmland_plot()
		return null
	elif kind.begins_with("fruit_tree"):
		var sapling_id: String = "apple_sapling"
		if kind.begins_with("fruit_tree:"):
			sapling_id = kind.substr("fruit_tree:".length())
		_placer = FruitTreePlacer.new()
		_placer.name = "FruitTreePlacer"
		_placer.setup(world, player, sapling_id)
		world.add_child(_placer)
		return _placer
	return null

## Классическая грядка из моделей farm_plot_mounded/tilled: ставится перед
## игроком за дерево и камень. Проверка места — та же, что у делянок.
func _place_farmland_plot() -> void:
	if world == null or player == null:
		return
	var inv = player.get("inventory") if "inventory" in player else null
	if inv == null:
		return
	for rid in FARMLAND_PLOT_COST.keys():
		var need: int = int(FARMLAND_PLOT_COST[rid])
		var have: int = int(inv.get_item_count(str(rid))) if inv.has_method("get_item_count") else 0
		if have < need:
			AudioManager.play("ui_error")
			if player.has_method("notify"):
				player.notify("❌ Для грядки нужно: %s (не хватает %s)" % [_farmland_cost_text(), ItemDB.get_item_name(str(rid))])
			return
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3(1, 0, 0)
	fwd = fwd.normalized()
	var center := Vector2(player.global_position.x, player.global_position.z) + Vector2(fwd.x, fwd.z) * 2.5
	var rect := Rect2(center - FARMLAND_PLOT_SIZE * 0.5, FARMLAND_PLOT_SIZE)
	var err: String = FarmFieldPlacer.check_rect(world, rect)
	if err != "":
		AudioManager.play("ui_error")
		if player.has_method("notify"):
			player.notify("❌ Грядку не поставить: %s" % err)
		return
	for rid in FARMLAND_PLOT_COST.keys():
		inv.remove_item(str(rid), int(FARMLAND_PLOT_COST[rid]))
	var plot = FarmlandPlotScene.instantiate()
	plot.name = _next_farmland_name()
	var parent = world.get_node_or_null("Props")
	if parent == null:
		parent = world
	parent.add_child(plot)
	plot.global_position = Vector3(center.x, player.global_position.y, center.y)
	AudioManager.play("ui_click")
	if player.has_method("notify"):
		player.notify("🌱 Грядка готова! Вскопайте её мотыгой [E].")

func _farmland_cost_text() -> String:
	var parts: PackedStringArray = []
	for rid in FARMLAND_PLOT_COST.keys():
		parts.append("%d %s" % [int(FARMLAND_PLOT_COST[rid]), ItemDB.get_item_name(str(rid))])
	return ", ".join(parts)

func _next_farmland_name() -> String:
	var n: int = 3
	while world.find_child("FarmlandPlot%d" % n, true, false) != null:
		n += 1
	return "FarmlandPlot%d" % n

func is_placing() -> bool:
	return is_instance_valid(_placer) and not _placer.is_queued_for_deletion()

func open_machine_panel(machine: Node) -> Control:
	var p = MachinePanel.new()
	p.setup(machine, player)
	_open(p)
	return p

func close_panel() -> void:
	if is_panel_open():
		_panel.close()

func _open(panel: Control) -> void:
	if is_panel_open():
		_panel.closed.disconnect(_on_panel_closed)
		_panel.queue_free()
	elif player:
		_player_prev_mode = player.process_mode
		player.process_mode = Node.PROCESS_MODE_DISABLED
	_panel = panel
	panel.closed.connect(_on_panel_closed)
	var host: Node = hud if hud else self
	host.add_child(panel)

func _on_panel_closed() -> void:
	_panel = null
	if player and is_instance_valid(player):
		player.process_mode = _player_prev_mode

## Колесо мыши без Ctrl — следующий / предыдущий инструмент пояса.
func _unhandled_input(event: InputEvent) -> void:
	handle_wheel(event)

func handle_wheel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not event.pressed:
		return false
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	if event.ctrl_pressed or event.meta_pressed:
		return false
	if is_panel_open() or (is_inside_tree() and get_tree().paused):
		return false
	if hud and hud.has_method("is_gameplay_input_blocked") and hud.is_gameplay_input_blocked():
		return false
	if player == null or not ("inventory" in player) or player.inventory == null:
		return false
	player.inventory.cycle_tool(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	return true
