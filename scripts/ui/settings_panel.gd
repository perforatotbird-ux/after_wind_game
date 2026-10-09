extends Control

## Окно настроек в стиле HUD: скорость игрового времени, звук (общая громкость,
## эффекты, окружение), экран и интерфейс (полноэкранный режим, разрешение, VSync,
## масштаб интерфейса) и чувствительность камеры.
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

const LABEL_WIDTH: float = 300.0
const UI_SCALE_PRESETS: Array = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5]

var _game_hour: OptionButton = null
var _ui_scale: OptionButton = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var margin := UI.make_margin(22)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := UI.make_label("⚙ Настройки", 22, UI.COLOR_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := UI.make_button("✕", Vector2(40, 34))
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Содержимое прокручивается, если окно игры маленькое или масштаб интерфейса крупный.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, mini(560, int(get_viewport_rect().size.y) - 200))
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	vbox.add_child(UI.make_section_header("⏱ Игра"))
	_game_hour = _add_option(vbox, "Длительность игрового часа", GameSettings.get_game_hour_labels(), _on_game_hour_selected)
	var hint := UI.make_label("Влияет на смену дня и ночи и на рост деревьев. Станки и грядки работают в реальном времени.", 12, UI.COLOR_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	vbox.add_child(HSeparator.new())

	vbox.add_child(UI.make_section_header("🔊 Звук"))
	_add_slider(vbox, "master_volume", "Общая громкость", 0.0, 1.0, 0.05, true)
	_add_slider(vbox, "sfx_volume", "Эффекты", 0.0, 1.0, 0.05, true)
	_add_slider(vbox, "ambient_volume", "Окружение (ветер, дождь)", 0.0, 1.0, 0.05, true)
	vbox.add_child(HSeparator.new())

	vbox.add_child(UI.make_section_header("🖥 Экран и интерфейс"))
	_fullscreen = _add_toggle(vbox, "Полноэкранный режим", "fullscreen")
	_resolution = _add_option(vbox, "Разрешение окна", GameSettings.get_resolution_labels(), _on_resolution_selected)
	_vsync = _add_toggle(vbox, "Вертикальная синхронизация (VSync)", "vsync")
	var scale_labels: Array[String] = []
	for k in UI_SCALE_PRESETS:
		scale_labels.append("%d%%%s" % [int(round(float(k) * 100.0)), " (по умолчанию)" if is_equal_approx(float(k), 1.0) else ""])
	_ui_scale = _add_option(vbox, "Масштаб интерфейса", scale_labels, _on_ui_scale_selected)
	vbox.add_child(HSeparator.new())

	vbox.add_child(UI.make_section_header("🖱 Камера"))
	_add_slider(vbox, "mouse_sensitivity", "Чувствительность (ПКМ + мышь)",
		GameSettings.MOUSE_SENSITIVITY_MIN, GameSettings.MOUSE_SENSITIVITY_MAX, 0.05, false)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	var reset_btn := UI.make_button("↺ По умолчанию", Vector2(180, 38))
	reset_btn.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var done_btn := UI.make_button("✔ Готово", Vector2(160, 38), true)
	done_btn.pressed.connect(close)
	footer.add_child(done_btn)

	_sync_from_settings()
	done_btn.grab_focus.call_deferred()

func _add_option(parent: Control, text: String, labels: Array[String], callback: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UI.make_label(text, 15, UI.COLOR_TEXT)
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(0, 34)
	ob.add_theme_font_size_override("font_size", 14)
	ob.clip_text = true
	for label in labels:
		ob.add_item(label)
	ob.item_selected.connect(callback)
	row.add_child(ob)
	parent.add_child(row)
	return ob

func _add_slider(parent: Control, key: String, text: String, min_v: float, max_v: float, step: float, percent: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UI.make_label(text, 15, UI.COLOR_TEXT)
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(200, 24)
	row.add_child(s)
	var v := UI.make_label("", 15, UI.COLOR_TITLE)
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
	cb.add_theme_font_size_override("font_size", 15)
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
	_game_hour.select(GameSettings.get_game_hour_preset_index())
	var cur_scale: float = float(GameSettings.get_value("ui_scale"))
	var best: int = 0
	for i in UI_SCALE_PRESETS.size():
		if absf(float(UI_SCALE_PRESETS[i]) - cur_scale) < absf(float(UI_SCALE_PRESETS[best]) - cur_scale):
			best = i
	_ui_scale.select(best)

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

func _on_game_hour_selected(index: int) -> void:
	AudioManager.play("ui_click")
	GameSettings.set_value("seconds_per_game_hour", float(GameSettings.GAME_HOUR_PRESETS[index]), get_tree())

func _on_ui_scale_selected(index: int) -> void:
	AudioManager.play("ui_click")
	GameSettings.set_value("ui_scale", float(UI_SCALE_PRESETS[index]), get_tree())

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
