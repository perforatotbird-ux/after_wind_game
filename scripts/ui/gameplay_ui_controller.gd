extends Node

## Игровые окна поверх HUD: клеточный рюкзак (TAB / I / слот 5) и окно станка
## с заказом партии, а также смена инструмента колесом мыши (Ctrl + колесо — зум
## камеры, см. isometric_camera.gd). Перехватывает сигналы, которые раньше открывали
## старые окна HUD (toggle_inventory / open_machine_window). Пока окно открыто,
## управление персонажем выключено. Создаётся в world.gd (_init_session).

const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const MachinePanel = preload("res://scripts/ui/machine_panel.gd")

const SLOT5_PATH: String = "HotbarUI/Panel/Margin/HBox/Slot5"

var hud: Node
var world: Node
var player: Node

var _panel: Control
var _player_prev_mode: int = Node.PROCESS_MODE_INHERIT

func setup(p_hud: Node, p_world: Node, p_player: Node) -> void:
	hud = p_hud
	world = p_world
	player = p_player

func _ready() -> void:
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
	_open(p)
	return p

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
