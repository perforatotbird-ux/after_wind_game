extends Control

## Переход «Обморок / Поражение» (см. docs/DOCUMENTATION.md, «Обморок и поражение»):
## затемнение, анимированный splash, затем либо утренний отскок к дому
## (stage дома ≥ 2 — «Восстановленный дом»), либо окно поражения с кнопками
## «Продолжить» / «Меню». В headless-режиме (тесты) overlay пропускается:
## применяется результат мгновенно.
##
## Создаётся из player._on_collapse / player._on_sleep_collapse.

const RestTransitionStyle = preload("res://scripts/ui/ui_style.gd")
const GameSession = preload("res://scripts/core/game_session.gd")

## Длительность splash‑части в реальных секундах.
const SPLASH_DURATION: float = 1.6
## Сколько восстанавливать энергии/здоровья после обморока утром.
const POST_COLLAPSE_ENERGY: float = 30.0
const POST_COLLAPSE_HEALTH_MIN: float = 20.0
const POST_COLLAPSE_HEALTH_LOSS: float = 25.0

var player: Node
var day_cycle: Node
## Стадия дома (0..3). При ≥ 2 — утренний отскок к дому вместо game over.
var house_stage: int = 0
var _headless: bool = false

var _elapsed: float = 0.0
var _phase: int = 0  # 0 = splash, 1 = done
var _finished: bool = false


func setup(p_player: Node, p_day_cycle: Node, p_house_stage: int) -> void:
	player = p_player
	day_cycle = p_day_cycle
	house_stage = maxi(0, p_house_stage)
	_headless = DisplayServer.get_name() == "headless"


func _ready() -> void:
	if _headless:
		_finish(false)
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Control.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_theme_stylebox_override("panel", RestTransitionStyle.make_stylebox(Color(0.0, 0.0, 0.0, 0.85), Color(0, 0, 0, 0)))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := RestTransitionStyle.make_panel(RestTransitionStyle.COLOR_CARD, RestTransitionStyle.COLOR_DANGER, 2)
	box.custom_minimum_size = Vector2(340, 0)
	center.add_child(box)
	var margin := RestTransitionStyle.make_margin(24)
	box.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(v)

	var icon := RestTransitionStyle.make_label("💀", 40, RestTransitionStyle.COLOR_DANGER)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)

	var title := RestTransitionStyle.make_label("Обморок", 20, RestTransitionStyle.COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var msg := RestTransitionStyle.make_label(
		"Язык покинул тело. Вы чувствуете, как сознание медленно..." if player == null or player.has_method("is_sleep_deprived")
		else "💀 Вы потеряли сознание...",
		14, RestTransitionStyle.COLOR_TEXT
	)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(msg)

	RestTransitionStyle.polish_text(self)
	if day_cycle and day_cycle.has_method("get_time_string"):
		var lbl := RestTransitionStyle.make_label(str(day_cycle.get_time_string()), 13, RestTransitionStyle.COLOR_MUTED)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lbl)



func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	if _elapsed >= SPLASH_DURATION:
		_finish(_phase == 0 and house_stage >= 2)


## Применяет последствия обморока: восстанавливает статы, ставит на утро
## (если есть дом и skip_to_morning) либо открывает окно поражения.
func _finish(morning: bool) -> void:
	if _finished:
		return
	_finished = true

	if player and player.has_method("notify"):
		player.notify("💀 Обморок: здоровье снижено, но выжив.")

	if morning:
		_apply_morning_recovery()
	else:
		_show_game_over()


## Утренний отскок: время → 08:00, статы восстанавливаются частично.
func _apply_morning_recovery() -> void:
	if day_cycle and day_cycle.has_method("skip_to_morning"):
		day_cycle.skip_to_morning(8.0)
	if player:
		player.hours_without_sleep = 0.0
		if "energy" in player:
			player.energy = POST_COLLAPSE_ENERGY
			if player.has_signal("energy_changed"):
				player.energy_changed.emit(player.energy, player.max_energy)
		if "health" in player:
			player.health = max(POST_COLLAPSE_HEALTH_MIN, player.health - POST_COLLAPSE_HEALTH_LOSS)
			if player.has_signal("health_changed"):
				player.health_changed.emit(player.health, player.max_health)
		if player.has_method("notify"):
			player.notify("🌅 Вы очнулись у дома воспалённом... но живы. Наступил новый день.")
	queue_free()


## Окно поражения: Game Over с выбором загрузить последний сейв или выйти в меню.
func _show_game_over() -> void:
	var overlay := RestTransitionStyle.make_panel(RestTransitionStyle.COLOR_BG, RestTransitionStyle.COLOR_DANGER, 2)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Затемнение поверх: Game Over затемняет, а splash — уже исчез.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var box := RestTransitionStyle.make_panel(RestTransitionStyle.COLOR_CARD, RestTransitionStyle.COLOR_DANGER, 2)
	box.custom_minimum_size = Vector2(380, 0)
	center.add_child(box)
	var margin := RestTransitionStyle.make_margin(24)
	box.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(v)

	var title := RestTransitionStyle.make_label("🎮 Game Over", 26, RestTransitionStyle.COLOR_DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := RestTransitionStyle.make_label(
		"Персонаж упал неузнаваемым. Дом ещё не восстановлен — спаситься придётся с последнего сохранения.",
		14, RestTransitionStyle.COLOR_TEXT
	)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 12)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_box)

	var load_btn := RestTransitionStyle.make_button("⏎ Продолжить", Vector2(150, 0), true)
	var menu_btn := RestTransitionStyle.make_button("🏠 В меню", Vector2(150, 0), false, true)
	btn_box.add_child(load_btn)
	btn_box.add_child(menu_btn)

	add_child(overlay)

	load_btn.pressed.connect(func():
		get_tree().paused = false
		queue_free()
		if player and player.has_method("quick_load"):
			player.quick_load()
	)
	menu_btn.pressed.connect(func():
		get_tree().paused = false
		queue_free()
		# Возврат в стартовое меню: world.gd после перезагрузки покажет меню.
		GameSession.request_main_menu(get_tree())
		get_tree().reload_current_scene()
	)

	RestTransitionStyle.polish_text(overlay)
