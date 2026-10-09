extends CanvasLayer

## Стартовое меню: живой мир на фоне (камера медленно облетает базу),
## «Продолжить», «Новая игра», «Загрузить», «Настройки», «Выход».
## Любой запуск игры перезагружает сцену мира через GameSession, чтобы партия
## начиналась с чистого состояния (мир под меню тем временем живёт: погода, сутки).
## Создаётся world.gd; поле world нужно задать до add_child.

const UI = preload("res://scripts/ui/ui_style.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const SavesPanel = preload("res://scripts/ui/saves_panel.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

const ORBIT_RADIUS: float = 24.0
const ORBIT_HEIGHT: float = 12.0
## Радиан в секунду: полный оборот примерно за 2 минуты.
const ORBIT_SPEED: float = 0.05
const LOOK_OFFSET: Vector3 = Vector3(0.0, 1.5, 0.0)

var world: Node3D = null
var _camera: Camera3D = null
var _orbit_center: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.7
var _continue_button: Button = null
var _continue_hint: Label = null

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	refresh_continue()
	_setup_camera.call_deferred()

func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.queue_free()

# --- Камера ---

func _setup_camera() -> void:
	if not is_instance_valid(world):
		return
	var player := world.get_node_or_null("Player") as Node3D
	if player:
		_orbit_center = player.global_position
	_camera = Camera3D.new()
	_camera.name = "MainMenuCamera"
	_camera.fov = 55.0
	world.add_child(_camera)
	_camera.make_current()
	_update_camera()

func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	_orbit_angle = fmod(_orbit_angle + ORBIT_SPEED * delta, TAU)
	_update_camera()

func _update_camera() -> void:
	var offset := Vector3(sin(_orbit_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(_orbit_angle) * ORBIT_RADIUS)
	_camera.global_position = _orbit_center + offset
	_camera.look_at(_orbit_center + LOOK_OFFSET, Vector3.UP)

# --- Интерфейс ---

func _build_ui() -> void:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Затемнение левой части — читаемость меню поверх живого мира.
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.06, 0.08, 0.45)
	shade.set_anchor(SIDE_RIGHT, 0.42)
	shade.set_anchor(SIDE_BOTTOM, 1.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var holder := CenterContainer.new()
	holder.set_anchor(SIDE_RIGHT, 0.42)
	holder.set_anchor(SIDE_BOTTOM, 1.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	var panel := UI.make_panel(Color(0.12, 0.15, 0.18, 0.9), UI.COLOR_BORDER, 1)
	panel.custom_minimum_size = Vector2(380, 0)
	holder.add_child(panel)
	var m := UI.make_margin(26)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var title := UI.make_label("AFTER THE STORM", 34, UI.COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var subtitle := UI.make_label("🌬 После бури", 15, UI.COLOR_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 18)
	v.add_child(sep)

	_continue_button = _add_menu_button(v, "▶  Продолжить", _on_continue_pressed, true)
	_continue_hint = UI.make_label("", 11, UI.COLOR_DIM)
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_continue_hint)
	_add_menu_button(v, "✦  Новая игра", _on_new_game_pressed)
	_add_menu_button(v, "📂  Загрузить", _on_load_pressed)
	_add_menu_button(v, "⚙  Настройки", _on_settings_pressed)
	_add_menu_button(v, "⏻  Выход", _on_quit_pressed)

	var tip := UI.make_label("WASD — ходьба · ПКМ + мышь — камера · E — действие · Esc — пауза", 11, UI.COLOR_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)

func _add_menu_button(parent: Control, text: String, callback: Callable, primary: bool = false) -> Button:
	var b := UI.make_button(text, Vector2(0, 44), primary, false, 17)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func refresh_continue() -> void:
	if _continue_button == null:
		return
	var slot: String = SaveSlots.get_latest_slot()
	_continue_button.disabled = slot == ""
	if slot == "":
		_continue_hint.text = "Сохранений пока нет"
	else:
		var info: Dictionary = SaveSlots.get_slot_info(slot)
		_continue_hint.text = "%s · %s" % [info.get("title", ""), SaveSlots.format_slot_details(info)]
		if is_inside_tree():
			_continue_button.grab_focus.call_deferred()

# --- Действия ---

func _on_continue_pressed() -> void:
	var slot: String = SaveSlots.get_latest_slot()
	if slot != "":
		_start_load(slot)

func _start_load(slot_id: String) -> void:
	AudioManager.play("ui_click")
	GameSession.request_load(get_tree(), slot_id)
	GameSession.restart_scene(get_tree())

func _on_new_game_pressed() -> void:
	AudioManager.play("ui_click")
	GameSession.request_new_game(get_tree())
	GameSession.restart_scene(get_tree())

func _on_load_pressed() -> void:
	AudioManager.play("ui_click")
	var panel = SavesPanel.new()
	panel.setup("load", world)
	panel.slot_chosen.connect(_start_load)
	panel.closed.connect(refresh_continue)
	add_child(panel)

func _on_settings_pressed() -> void:
	AudioManager.play("ui_click")
	add_child(SettingsPanel.new())

func _on_quit_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().quit()
