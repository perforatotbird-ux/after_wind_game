extends Control

## Диалог сна в доме: ползунок длительности (1–12 ч), быстрые кнопки,
## расчёт времени пробуждения. Персонаж исчезает из мира на время сна
## (см. player.start_rest), переход показывает часы со стрелками.
##   var d = SleepDialog.new()
##   d.setup(building, player)
##   d.confirmed.connect(func(hours): ...)
##   parent.add_child(d)

signal confirmed(hours: float)
signal cancelled

const UI = preload("res://scripts/ui/ui_style.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

## Границы выбора длительности сна, игровых часах.
const MIN_HOURS: float = 1.0
const MAX_HOURS: float = 12.0
const STEP_HOURS: float = 1.0
## Полный сон — от этого порога энергия и здоровье утром на 100%.
const FULL_SLEEP_HOURS: float = 6.0

var _building: Node
var _player: Node
var _slider: HSlider
var _spin: SpinBox
var _info: Label
var _syncing: bool = false
var selected_hours: float = FULL_SLEEP_HOURS
var _quick_buttons: Array[Button] = []
var _quick_values: Array[float] = [1.0, 4.0, 6.0, 8.0, 12.0]

func setup(building: Node, player: Node) -> void:
	_building = building
	_player = player

func get_hours() -> float:
	return selected_hours

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var margin := UI.make_margin(20)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := UI.make_label("😴 Сон в доме", 20, UI.COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hint := UI.make_label("Сколько спать? Выберите готовое время или задайте ползунком. Короткий сон освежит силы, долгий — полностью восстановит здоровье и энергию.", 13, UI.COLOR_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_slider = HSlider.new()
	_slider.min_value = MIN_HOURS
	_slider.max_value = MAX_HOURS
	_slider.step = STEP_HOURS
	_slider.custom_minimum_size = Vector2(420, 26)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slider_changed)
	vbox.add_child(_slider)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)
	_quick_buttons.clear()
	for quick in _quick_values:
		var btn := UI.make_button("%d ч" % int(quick), Vector2(56, 32))
		btn.pressed.connect(_set_hours.bind(quick))
		row.add_child(btn)
		_quick_buttons.append(btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_spin = SpinBox.new()
	_spin.min_value = MIN_HOURS
	_spin.max_value = MAX_HOURS
	_spin.step = STEP_HOURS
	_spin.rounded = true
	_spin.custom_minimum_size = Vector2(95, 32)
	_spin.value_changed.connect(_on_spin_changed)
	row.add_child(_spin)

	_info = UI.make_label("", 14)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)
	var cancel_btn := UI.make_button("Отмена", Vector2(120, 36))
	cancel_btn.pressed.connect(_on_cancel)
	buttons.add_child(cancel_btn)
	var ok_btn := UI.make_button("🛏️ Спать", Vector2(160, 36), true)
	ok_btn.pressed.connect(_on_ok)
	buttons.add_child(ok_btn)
	ok_btn.grab_focus.call_deferred()

	_set_hours(FULL_SLEEP_HOURS)

## Игровое время пробуждения: «День N, HH:MM».
func _wake_text(hours: float) -> String:
	var dc: Node = null
	var tree := get_tree()
	if tree:
		dc = tree.get_first_node_in_group("day_night_cycle")
	if dc == null or not ("current_hour" in dc):
		return "через %d игровых ч." % int(hours)
	var day: int = int(dc.current_day)
	var hour: float = float(dc.current_hour) + hours
	while hour >= 24.0:
		hour -= 24.0
		day += 1
	return "Проснётесь: День %d, %02d:%02d" % [day, int(hour), int((hour - float(int(hour))) * 60.0)]

func _set_hours(h: float) -> void:
	var n: float = clampf(snappedf(h, STEP_HOURS), MIN_HOURS, MAX_HOURS)
	selected_hours = n
	_syncing = true
	if _slider and not is_equal_approx(_slider.value, n):
		_slider.value = n
	if _spin and not is_equal_approx(_spin.value, n):
		_spin.value = n
	_syncing = false
	
	# Подсветка активной быстрой кнопки
	for i in range(_quick_buttons.size()):
		var b: Button = _quick_buttons[i]
		var val: float = _quick_values[i]
		var is_selected: bool = is_equal_approx(val, n)
		if is_selected:
			b.add_theme_stylebox_override("normal", UI.make_stylebox(Color(0.24, 0.28, 0.36), UI.COLOR_ACCENT, 2, 4))
			b.add_theme_color_override("font_color", UI.COLOR_ACCENT)
		else:
			b.add_theme_stylebox_override("normal", UI.make_stylebox(UI.COLOR_CARD, UI.COLOR_BORDER, 1, 4))
			b.add_theme_color_override("font_color", UI.COLOR_TEXT)
	
	var text: String = "Длительность: %d ч  ·  %s" % [int(n), _wake_text(n)]
	if n < FULL_SLEEP_HOURS:
		text += "\n⚠️ Короткий сон восстановит силы частично (+%d%% энергии)." % int(round((n / FULL_SLEEP_HOURS) * 100.0))
	else:
		text += "\n✨ Полноценный сон: 100% энергии и полное здоровье."
	if _info:
		_info.text = text

func _on_slider_changed(v: float) -> void:
	if not _syncing:
		_set_hours(v)

func _on_spin_changed(v: float) -> void:
	if not _syncing:
		_set_hours(v)

## Диалог перехватывает ESC/Enter раньше HUD: он добавлен как ребёнок HUD,
## и _unhandled_input у HUD отработал бы первым и закрыл окно дома,
## оставив диалог сна «осиротевшим» (сон не срабатывал бы).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_ok()
			get_viewport().set_input_as_handled()

func _on_ok() -> void:
	AudioManager.play("ui_click")
	confirmed.emit(get_hours())
	queue_free()

func _on_cancel() -> void:
	AudioManager.play("ui_click")
	cancelled.emit()
	queue_free()
