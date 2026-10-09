extends Control

## Окно слотов сохранения в стиле HUD. Режимы: "load" (загрузка) и "save" (запись).
## Запись и удаление выполняет само (перезапись и удаление — с подтверждением);
## о выборе слота для загрузки сообщает сигналом slot_chosen — владелец решает,
## как перезапустить мир. Автосохранение в режиме записи не показывается.

signal slot_chosen(slot_id: String)
signal saved(slot_id: String, ok: bool)
signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")

var mode: String = "load"
var world: Node = null
var _list: VBoxContainer = null

func setup(p_mode: String, p_world: Node = null) -> void:
	mode = p_mode
	world = p_world

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.make_overlay())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.make_panel(UI.COLOR_BG, UI.COLOR_ACCENT, 2)
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)
	var margin := UI.make_margin(18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := UI.make_label("💾 Сохранить игру" if mode == "save" else "📂 Загрузить игру", 20, UI.COLOR_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := UI.make_button("✕", Vector2(36, 32))
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_list)

	var hint_text := "Автосохранение пишется каждые 5 минут, при сне и по F5."
	var hint := UI.make_label(hint_text, 13, UI.COLOR_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	refresh()

func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for slot_id in SaveSlots.get_all_slot_ids():
		if mode == "save" and slot_id == SaveSlots.AUTOSAVE_ID:
			continue
		_list.add_child(_make_row(SaveSlots.get_slot_info(slot_id)))

func _make_row(info: Dictionary) -> Control:
	var exists: bool = info.get("exists", false)
	var valid: bool = info.get("valid", false)
	var broken: bool = exists and not valid
	var card := UI.make_panel(UI.COLOR_CARD if exists else UI.COLOR_CARD_EMPTY, UI.COLOR_DANGER if broken else UI.COLOR_BORDER, 1)
	var m := UI.make_margin(10)
	card.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	m.add_child(h)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info_box)
	info_box.add_child(UI.make_label(str(info.get("title", "")), 15, UI.COLOR_TITLE if exists else UI.COLOR_TEXT))
	var details := UI.make_label(SaveSlots.format_slot_details(info), 13, UI.COLOR_DANGER if broken else UI.COLOR_MUTED)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(details)

	var slot_id: String = str(info.get("id", ""))
	var action: Button
	if mode == "save":
		action = UI.make_button("💾 Перезаписать" if exists else "💾 Сохранить", Vector2(160, 36), true)
		action.pressed.connect(_on_save_pressed.bind(slot_id, exists))
	else:
		action = UI.make_button("▶ Загрузить", Vector2(160, 36), true)
		action.disabled = not valid
		action.pressed.connect(_on_load_pressed.bind(slot_id))
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(action)
	if exists:
		var del := UI.make_button("🗑", Vector2(40, 36), false, true)
		del.tooltip_text = "Удалить сохранение"
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.pressed.connect(_on_delete_pressed.bind(slot_id))
		h.add_child(del)
	return card

func _on_save_pressed(slot_id: String, exists: bool) -> void:
	AudioManager.play("ui_click")
	if exists:
		_confirm("Перезаписать сохранение?",
			"%s будет заменён текущим прогрессом." % SaveSlots.get_slot_title(slot_id),
			"💾 Перезаписать", false, _do_save.bind(slot_id))
	else:
		_do_save(slot_id)

func _do_save(slot_id: String) -> void:
	var ok: bool = SaveSlots.save_to_slot(world, slot_id)
	refresh()
	saved.emit(slot_id, ok)

func _on_load_pressed(slot_id: String) -> void:
	AudioManager.play("ui_click")
	slot_chosen.emit(slot_id)

func _on_delete_pressed(slot_id: String) -> void:
	AudioManager.play("ui_click")
	_confirm("Удалить сохранение?",
		"%s будет удалён без возможности восстановления." % SaveSlots.get_slot_title(slot_id),
		"🗑 Удалить", true, _do_delete.bind(slot_id))

func _do_delete(slot_id: String) -> void:
	SaveSlots.delete_slot(slot_id)
	refresh()

func _confirm(title: String, message: String, ok_text: String, danger: bool, on_ok: Callable) -> void:
	var dialog = ConfirmDialog.new()
	dialog.setup(title, message, ok_text, danger)
	dialog.confirmed.connect(on_ok)
	add_child(dialog)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	AudioManager.play("ui_click")
	closed.emit()
	queue_free()
