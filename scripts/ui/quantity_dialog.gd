extends Control

## Модальное окно выбора количества (выбрасывание предметов): ползунок + поле,
## быстрые кнопки «1 / ½ / Все», вес выбранного количества. ESC / «Отмена» — отказ.
##   var d = QuantityDialog.new()
##   d.setup("Выбросить", "stone", 37)
##   d.confirmed.connect(func(n): ...)
##   parent.add_child(d)

signal confirmed(amount: int)
signal cancelled

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

var _title: String = "Выбросить"
var _item_id: String = ""
var _max: int = 1
var _min: int = 1
var _step: int = 1
var _default: int = -1
var _ok_text: String = "Выбросить"

var _slider: HSlider
var _spin: SpinBox
var _info: Label
var _syncing: bool = false

func setup(title: String, item_id: String, max_amount: int, default_amount: int = -1, ok_text: String = "Выбросить", step: int = 1, min_amount: int = 1) -> void:
	_title = title
	_item_id = item_id
	_step = maxi(1, step)
	_min = maxi(_step, min_amount)
	_max = maxi(_min, max_amount)
	_default = default_amount
	_ok_text = ok_text

func get_amount() -> int:
	return int(_spin.value) if _spin else _min

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())
	
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	
	vbox.add_child(UI.make_label(_title, 18, UI.COLOR_TITLE))
	
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vbox.add_child(head)
	var icon := TextureRect.new()
	icon.texture = ItemIcons.get_texture(_item_id)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var names := VBoxContainer.new()
	head.add_child(names)
	names.add_child(UI.make_label("%s %s" % [ItemDB.get_item_icon(_item_id), ItemDB.get_item_name(_item_id)], 15))
	names.add_child(UI.make_label("Доступно: %d" % _max, 12, UI.COLOR_MUTED))
	
	_slider = HSlider.new()
	_slider.min_value = _min
	_slider.max_value = _max
	_slider.step = _step
	_slider.custom_minimum_size = Vector2(380, 24)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_slider)
	
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var one_btn := UI.make_button(str(_min), Vector2(56, 32))
	one_btn.pressed.connect(func(): _set_amount(_min))
	row.add_child(one_btn)
	var half_btn := UI.make_button("½", Vector2(56, 32))
	half_btn.pressed.connect(func(): _set_amount(int(snappedi(_max / 2, _step))))
	row.add_child(half_btn)
	var all_btn := UI.make_button("Все", Vector2(64, 32))
	all_btn.pressed.connect(func(): _set_amount(_max))
	row.add_child(all_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_spin = SpinBox.new()
	_spin.min_value = _min
	_spin.max_value = _max
	_spin.step = _step
	_spin.rounded = true
	_spin.custom_minimum_size = Vector2(110, 32)
	row.add_child(_spin)
	
	_info = UI.make_label("", 13, UI.COLOR_MUTED)
	vbox.add_child(_info)
	
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)
	var cancel_btn := UI.make_button("Отмена", Vector2(120, 36))
	cancel_btn.pressed.connect(_on_cancel)
	buttons.add_child(cancel_btn)
	var ok_btn := UI.make_button(_ok_text, Vector2(160, 36), true)
	ok_btn.pressed.connect(_on_ok)
	buttons.add_child(ok_btn)
	
	_slider.value_changed.connect(_on_slider_changed)
	_spin.value_changed.connect(_on_spin_changed)
	_set_amount(_default if _default > 0 else _max)
	ok_btn.grab_focus.call_deferred()

func _set_amount(n: int) -> void:
	n = clampi(int(snappedi(n, _step)), _min, _max)
	_syncing = true
	_slider.value = n
	_spin.value = n
	_syncing = false
	_update_info()

func _on_slider_changed(v: float) -> void:
	if _syncing:
		return
	_set_amount(int(v))

func _on_spin_changed(v: float) -> void:
	if _syncing:
		return
	_set_amount(int(v))

func _update_info() -> void:
	if _info == null:
		return
	var w: float = float(ItemDB.get_item(_item_id).get("weight", 1.0))
	_info.text = "Количество: %d  ·  Вес: %.1f кг (%.2f кг/шт.)" % [get_amount(), w * get_amount(), w]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_ok()
			get_viewport().set_input_as_handled()

func _on_ok() -> void:
	AudioManager.play("ui_click")
	confirmed.emit(get_amount())
	queue_free()

func _on_cancel() -> void:
	AudioManager.play("ui_click")
	cancelled.emit()
	queue_free()
