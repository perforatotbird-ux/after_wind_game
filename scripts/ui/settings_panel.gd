extends Control

## Окно настроек в стиле HUD: звук (общая громкость, эффекты, окружение),
## экран (полноэкранный режим, разрешение, VSync) и чувствительность камеры.
## Изменения применяются сразу и сохраняются в user://settings.cfg (GameSettings).

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _is_percent: Dictionary = {}
var _fullscreen: CheckButton = null
var _vsync: CheckButton = null
var _resolution: OptionButton = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := UI.make_label("⚙ Настройки", 20, UI.COLOR_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := UI.make_button("✕", Vector2(36, 32))
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	vbox.add_child(UI.make_section_header("🔊 Звук"))
	_add_slider(vbox, "master_volume", "Общая громкость", 0.0, 1.0, 0.05, true)
	_add_slider(vbox, "sfx_volume", "Эффекты", 0.0, 1.0, 0.05, true)
	_add_slider(vbox, "ambient_volume", "Окружение (ветер, дождь)", 0.0, 1.0, 0.05, true)
	vbox.add_child(HSeparator.new())

	vbox.add_child(UI.make_section_header("🖥 Экран"))
	_fullscreen = _add_toggle(vbox, "Полноэкранный режим", "fullscreen")
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	var res_label := UI.make_label("Разрешение окна", 13, UI.COLOR_TEXT)
	res_label.custom_minimum_size = Vector2(230, 0)
	res_row.add_child(res_label)
	_resolution = OptionButton.new()
	_resolution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in GameSettings.get_resolution_labels():
		_resolution.add_item(label)
	_resolution.item_selected.connect(_on_resolution_selected)
	res_row.add_child(_resolution)
	vbox.add_child(res_row)
	_vsync = _add_toggle(vbox, "Вертикальная синхронизация (VSync)", "vsync")
	vbox.add_child(HSeparator.new())

	vbox.add_child(UI.make_section_header("🖱 Камера"))
	_add_slider(vbox, "mouse_sensitivity", "Чувствительность (ПКМ + мышь)",
		GameSettings.MOUSE_SENSITIVITY_MIN, GameSettings.MOUSE_SENSITIVITY_MAX, 0.05, false)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	vbox.add_child(footer)
	var reset_btn := UI.make_button("↺ По умолчанию", Vector2(160, 36))
	reset_btn.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var done_btn := UI.make_button("✔ Готово", Vector2(140, 36), true)
	done_btn.pressed.connect(close)
	footer.add_child(done_btn)

	_sync_from_settings()
	done_btn.grab_focus.call_deferred()

func _add_slider(parent: Control, key: String, text: String, min_v: float, max_v: float, step: float, percent: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UI.make_label(text, 13, UI.COLOR_TEXT)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(200, 24)
	row.add_child(s)
	var v := UI.make_label("", 13, UI.COLOR_TITLE)
	v.custom_minimum_size = Vector2(64, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	_sliders[key] = s
	_value_labels[key] = v
	_is_percent[key] = percent
	s.value_changed.connect(_on_slider_changed.bind(key))
	parent.add_child(row)

func _add_toggle(parent: Control, text: String, key: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.add_theme_color_override("font_color", UI.COLOR_TEXT)
	cb.add_theme_color_override("font_hover_color", UI.COLOR_TITLE)
	cb.add_theme_font_size_override("font_size", 13)
	cb.toggled.connect(_on_toggle.bind(key))
	parent.add_child(cb)
	return cb

func _sync_from_settings() -> void:
	for key in _sliders.keys():
		var val: float = float(GameSettings.get_value(key))
		(_sliders[key] as HSlider).set_value_no_signal(val)
		_update_value_label(key, val)
	var fullscreen: bool = bool(GameSettings.get_value("fullscreen"))
	_fullscreen.set_pressed_no_signal(fullscreen)
	_vsync.set_pressed_no_signal(bool(GameSettings.get_value("vsync")))
	_resolution.select(int(GameSettings.get_value("resolution_index")) + 1)
	_resolution.disabled = fullscreen

func _update_value_label(key: String, value: float) -> void:
	var label: Label = _value_labels[key]
	if _is_percent.get(key, false):
		label.text = "%d%%" % int(round(value * 100.0))
	else:
		label.text = "×%.2f" % value

func _on_slider_changed(value: float, key: String) -> void:
	GameSettings.set_value(key, value, get_tree())
	_update_value_label(key, value)

func _on_toggle(pressed: bool, key: String) -> void:
	AudioManager.play("ui_click")
	GameSettings.set_value(key, pressed, get_tree())
	if key == "fullscreen":
		_resolution.disabled = pressed

func _on_resolution_selected(index: int) -> void:
	AudioManager.play("ui_click")
	# Пункт 0 — «Как в проекте» (resolution_index = -1).
	GameSettings.set_value("resolution_index", index - 1, get_tree())

func _on_reset_pressed() -> void:
	AudioManager.play("ui_click")
	GameSettings.reset_to_defaults(get_tree())
	_sync_from_settings()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	AudioManager.play("ui_click")
	closed.emit()
	queue_free()
