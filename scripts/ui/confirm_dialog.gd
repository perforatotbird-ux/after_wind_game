extends Control

## Модальное окно подтверждения в стиле HUD (перезапись/удаление слота, выход).
## ESC или «Отмена» — отказ. Использование:
##   var d = ConfirmDialog.new(); d.setup("Заголовок", "Текст", "Да", true)
##   d.confirmed.connect(callback); parent.add_child(d)

signal confirmed
signal cancelled

const UI = preload("res://scripts/ui/ui_style.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

var _title: String = "Подтверждение"
var _message: String = ""
var _ok_text: String = "Подтвердить"
var _danger: bool = false

func setup(title: String, message: String, ok_text: String = "Подтвердить", danger: bool = false) -> void:
	_title = title
	_message = message
	_ok_text = ok_text
	_danger = danger

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_DANGER if _danger else UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(UI.make_label(_title, 18, UI.COLOR_TITLE))
	var msg := UI.make_label(_message, 13, UI.COLOR_MUTED)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(msg)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)
	var cancel_btn := UI.make_button("Отмена", Vector2(120, 36))
	cancel_btn.pressed.connect(_on_cancel)
	buttons.add_child(cancel_btn)
	var ok_btn := UI.make_button(_ok_text, Vector2(160, 36), not _danger, _danger)
	ok_btn.pressed.connect(_on_ok)
	buttons.add_child(ok_btn)
	# Для опасных действий фокус по умолчанию — на «Отмена».
	if _danger:
		cancel_btn.grab_focus.call_deferred()
	else:
		ok_btn.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_cancel()
		get_viewport().set_input_as_handled()

func _on_ok() -> void:
	AudioManager.play("ui_click")
	confirmed.emit()
	queue_free()

func _on_cancel() -> void:
	AudioManager.play("ui_click")
	cancelled.emit()
	queue_free()
