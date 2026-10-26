extends Control

## Переход «Отдых / Сон» (см. docs/DOCUMENTATION.md, «Отдых и сон»):
## затемнение, часы с бегущими стрелками; игровое время продвигается шагами,
## синхронными с анимацией, статы меняются в течение всего отдыха, а не в финале.
## Создаётся player.start_rest(); повторный запуск заблокирован флагом is_resting.

const RestTransitionStyle = preload("res://scripts/ui/ui_style.gd")

## Длительность перехода в реальных секундах и число шагов симуляции.
const DURATION: float = 2.4
const STEPS: int = 12

var player: Node
var day_cycle: Node
var total_hours: float = 8.0
var is_sleep: bool = false

var _elapsed: float = 0.0
var _step_accum: float = 0.0
var _steps_done: int = 0
var _time_label: Label
var _clock: Control
var _finished: bool = false

func setup(p_player: Node, p_day_cycle: Node, hours: float, sleep: bool) -> void:
	player = p_player
	day_cycle = p_day_cycle
	total_hours = maxf(0.5, hours)
	is_sleep = sleep

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := RestTransitionStyle.make_panel(RestTransitionStyle.COLOR_BG, RestTransitionStyle.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var margin := RestTransitionStyle.make_margin(20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var title := RestTransitionStyle.make_label("💤 Сон" if is_sleep else "🛌 Отдых", 22, RestTransitionStyle.COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_clock = Control.new()
	_clock.custom_minimum_size = Vector2(140, 140)
	_clock.draw.connect(_draw_clock)
	box.add_child(_clock)

	_time_label = RestTransitionStyle.make_label("", 16, RestTransitionStyle.COLOR_ACCENT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time_label)

	var hint := RestTransitionStyle.make_label("Пока вы отдыхаете, время бежит: урожай растёт, станки работают…", 14, RestTransitionStyle.COLOR_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(320, 0)
	box.add_child(hint)

	# Начальный шаг, чтобы статы и время тронулись сразу, а не через 0.2 с.
	_step_accum = DURATION / STEPS

func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_step_accum += delta
	var step_time: float = DURATION / float(STEPS)
	while _steps_done < STEPS and _step_accum >= step_time:
		_step_accum -= step_time
		_steps_done += 1
		var hours_step: float = total_hours / float(STEPS)
		if day_cycle and day_cycle.has_method("advance_hours"):
			day_cycle.advance_hours(hours_step)
		if player and player.has_method("_apply_rest_step"):
			player._apply_rest_step(hours_step, total_hours, float(_steps_done) * hours_step, is_sleep)
		if not is_instance_valid(player) or player.get("is_resting") == false:
			_finished = true
			queue_free()
			return
	_clock.queue_redraw()
	if day_cycle and day_cycle.has_method("get_time_string"):
		_time_label.text = "⏳ %d ч · %s" % [int(round(total_hours)), str(day_cycle.get_time_string())]
	if _elapsed >= DURATION:
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if player and is_instance_valid(player) and player.get("is_resting") == true and player.has_method("_finish_rest"):
		player._finish_rest(total_hours, is_sleep)
	queue_free()

## Часы со стрелками: часовая — по игровому времени (12-часовой циферблат),
## минутная — по минутам; за переход стрелки успевают намотать все отдых-часы.
## Внешнее кольцо — прогресс отдыха: простая иллюстрация бега времени.
func _draw_clock() -> void:
	var c: Control = _clock
	var center: Vector2 = c.size * 0.5
	var radius: float = minf(c.size.x, c.size.y) * 0.5 - 12.0
	c.draw_circle(center, radius, Color(0.10, 0.11, 0.14))
	c.draw_arc(center, radius, 0.0, TAU, 48, RestTransitionStyle.COLOR_ACCENT, 2.0, true)
	for i in 12:
		var ang: float = TAU * float(i) / 12.0 - TAU * 0.25
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var major: bool = i % 3 == 0
		c.draw_line(
			center + dir * radius * (0.80 if major else 0.86),
			center + dir * radius * 0.94,
			RestTransitionStyle.COLOR_MUTED if major else RestTransitionStyle.COLOR_DIM,
			2.5 if major else 1.5
		)
	# Прогресс отдыха: дуга заполняется по мере бега времени.
	var progress: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	if progress > 0.0:
		var ring: float = radius + 5.0
		c.draw_arc(center, ring, -TAU * 0.25, -TAU * 0.25 + TAU * progress, 48, RestTransitionStyle.COLOR_OK, 3.0, true)
	var hour: float = 0.0
	if day_cycle and "current_hour" in day_cycle:
		hour = float(day_cycle.current_hour)
	var hour_ang: float = TAU * fmod(hour, 12.0) / 12.0 - TAU * 0.25
	var min_ang: float = TAU * fmod(hour, 1.0) - TAU * 0.25
	c.draw_line(center, center + Vector2(cos(hour_ang), sin(hour_ang)) * radius * 0.5, RestTransitionStyle.COLOR_TITLE, 4.0)
	c.draw_line(center, center + Vector2(cos(min_ang), sin(min_ang)) * radius * 0.75, RestTransitionStyle.COLOR_ACCENT, 2.5)
	c.draw_circle(center, 4.0, RestTransitionStyle.COLOR_TITLE)
