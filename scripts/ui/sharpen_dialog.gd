extends Control

## Модальное меню «Заточить» для инструмента из рюкзака (двойной клик по ячейке).
## Показывает состояние лезвия, наличие точильного камня и заряд бруска;
## кнопка «Заточить» запускает задачу заточки выбранного инструмента.
##   var d = SharpenDialog.new()
##   d.setup("iron_axe")
##   d.confirmed.connect(func(tool_id): ...)
##   parent.add_child(d)

signal confirmed(tool_id: String)
signal cancelled

const UI = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

var _tool_id: String = ""
var _inventory: Node = null

var _status_lbl: Label
var _whet_lbl: Label
var _ok_btn: Button


func setup(tool_id: String, inventory: Node) -> void:
	_tool_id = tool_id
	_inventory = inventory


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(UI.make_label("🔨 Заточить", 18, UI.COLOR_TITLE))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vbox.add_child(head)
	var icon := TextureRect.new()
	icon.texture = ItemIcons.get_texture(_tool_id)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	head.add_child(icon)
	var names := VBoxContainer.new()
	head.add_child(names)
	names.add_child(UI.make_label("%s %s" % [ItemDB.get_item_icon(_tool_id), ItemDB.get_item_name(_tool_id)], 15))
	_status_lbl = UI.make_label("", 13, UI.COLOR_MUTED)
	names.add_child(_status_lbl)

	_whet_lbl = UI.make_label("", 13)
	_whet_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_whet_lbl)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)
	var cancel_btn := UI.make_button("Отмена", Vector2(120, 36))
	cancel_btn.pressed.connect(_on_cancel)
	buttons.add_child(cancel_btn)
	_ok_btn = UI.make_button("🔨 Заточить", Vector2(160, 36), true)
	_ok_btn.pressed.connect(_on_ok)
	buttons.add_child(_ok_btn)

	_refresh_status()
	_ok_btn.grab_focus.call_deferred()


func _refresh_status() -> void:
	var s: float = 100.0
	var eff: Dictionary = {}
	if _inventory:
		s = _inventory.get_tool_sharpness(_tool_id)
		eff = _inventory.get_sharpness_efficiency(_tool_id)
	_status_lbl.text = "Заточка: %d%% [%s]" % [int(round(s)), str(eff.get("status_name", ""))]
	if _inventory and _inventory.get_item_count("whetstone") > 0:
		var uses: int = _inventory.get_whetstone_uses() if _inventory.has_method("get_whetstone_uses") else 5
		_whet_lbl.text = "🪨 Точильный камень: %d шт. на поясе, зарядов %d/5.\nЗаточка даёт +40%% за 25 сек (быстрее с навыком ремесла)." % [int(_inventory.get_item_count("whetstone")), uses]
	else:
		_whet_lbl.text = "⚠️ Точильного камня нет в рюкзаке! Скрафтите его из 2 камня + 1 песок (кнопка в шапке рюкзака)."
		_whet_lbl.add_theme_color_override("font_color", UI.COLOR_DANGER)
		_ok_btn.disabled = true
		if _inventory and s >= 100.0:
			_whet_lbl.text = "✨ Инструмент уже идеально наточен."


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
	confirmed.emit(_tool_id)
	queue_free()


func _on_cancel() -> void:
	AudioManager.play("ui_click")
	cancelled.emit()
	queue_free()
