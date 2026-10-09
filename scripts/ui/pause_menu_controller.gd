extends Node

## Расширение меню паузы HUD: слоты сохранения вместо одного файла, окно
## настроек, «В главное меню» и подтверждения. Создаётся world.gd только при
## полноценном запуске игры; в headless-тестах меню паузы работает как раньше.
## hud.gd не меняется: контроллер переподключает сигналы существующих кнопок.

const UI = preload("res://scripts/ui/ui_style.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")
const SavesPanel = preload("res://scripts/ui/saves_panel.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")

const VBOX_PATH: String = "PauseWindow/Margin/VBox"

var hud: CanvasLayer = null
var world: Node = null

func setup(p_hud: CanvasLayer, p_world: Node) -> void:
	hud = p_hud
	world = p_world

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wire.call_deferred()

func _btn(rel_path: String) -> Button:
	return hud.get_node_or_null(VBOX_PATH + "/" + rel_path) as Button

func _slider(rel_path: String) -> HSlider:
	return hud.get_node_or_null(VBOX_PATH + "/" + rel_path) as HSlider

func _wire() -> void:
	if not is_instance_valid(hud):
		return
	_rewire(_btn("SaveLoadHBox/SaveButton"), _on_save_pressed)
	_rewire(_btn("SaveLoadHBox/LoadButton"), _on_load_pressed)
	var quit_btn := _btn("QuitButton")
	_rewire(quit_btn, _on_quit_pressed)
	if quit_btn and quit_btn.get_parent():
		_insert_before(quit_btn, "⚙ Настройки", _on_settings_pressed)
		_insert_before(quit_btn, "🏠 В главное меню", _on_main_menu_pressed)
	# Быстрые ползунки звука в паузе теперь тоже сохраняют настройки.
	var sfx := _slider("SfxHBox/SfxSlider")
	if sfx:
		sfx.value_changed.connect(_on_hud_slider_changed.bind("sfx_volume"))
	var amb := _slider("AmbHBox/AmbSlider")
	if amb:
		amb.value_changed.connect(_on_hud_slider_changed.bind("ambient_volume"))
	_sync_hud_sliders()

func _rewire(btn: Button, callback: Callable) -> void:
	if btn == null:
		return
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(callback)

func _insert_before(anchor: Button, text: String, callback: Callable) -> void:
	var parent := anchor.get_parent()
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = anchor.custom_minimum_size
	btn.size_flags_horizontal = anchor.size_flags_horizontal
	btn.add_theme_font_size_override("font_size", anchor.get_theme_font_size("font_size"))
	btn.pressed.connect(callback)
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())

func _sync_hud_sliders() -> void:
	var sfx := _slider("SfxHBox/SfxSlider")
	if sfx:
		sfx.set_value_no_signal(float(GameSettings.get_value("sfx_volume")))
	var amb := _slider("AmbHBox/AmbSlider")
	if amb:
		amb.set_value_no_signal(float(GameSettings.get_value("ambient_volume")))

func _on_hud_slider_changed(value: float, key: String) -> void:
	GameSettings.set_value(key, value, get_tree())

# --- Действия меню паузы ---

func _on_save_pressed() -> void:
	AudioManager.play("ui_click")
	var panel = SavesPanel.new()
	panel.setup("save", world)
	panel.saved.connect(_on_slot_saved)
	hud.add_child(panel)

func _on_slot_saved(slot_id: String, ok: bool) -> void:
	if not ok:
		_notify("⚠️ Не удалось сохранить игру в %s" % SaveSlots.get_slot_title(slot_id))

func _on_load_pressed() -> void:
	AudioManager.play("ui_click")
	var panel = SavesPanel.new()
	panel.setup("load", world)
	panel.slot_chosen.connect(_on_load_slot_chosen)
	hud.add_child(panel)

func _on_load_slot_chosen(slot_id: String) -> void:
	_confirm("Загрузить сохранение?",
		"Несохранённый прогресс текущей игры будет потерян.",
		"▶ Загрузить", false, _load_slot.bind(slot_id))

func _load_slot(slot_id: String) -> void:
	GameSession.request_load(get_tree(), slot_id)
	GameSession.restart_scene(get_tree())

func _on_settings_pressed() -> void:
	AudioManager.play("ui_click")
	var panel = SettingsPanel.new()
	panel.closed.connect(_sync_hud_sliders)
	hud.add_child(panel)

func _on_main_menu_pressed() -> void:
	AudioManager.play("ui_click")
	_confirm("Выйти в главное меню?",
		"Несохранённый прогресс будет потерян. Сохранитесь в слот, если не хотите потерять последние минуты.",
		"🏠 В меню", true, _go_to_main_menu)

func _go_to_main_menu() -> void:
	GameSession.request_main_menu(get_tree())
	GameSession.restart_scene(get_tree())

func _on_quit_pressed() -> void:
	AudioManager.play("ui_click")
	_confirm("Выйти из игры?",
		"Несохранённый прогресс будет потерян.",
		"⏻ Выйти", true, _quit_game)

func _quit_game() -> void:
	get_tree().quit()

func _confirm(title: String, message: String, ok_text: String, danger: bool, on_ok: Callable) -> void:
	var dialog = ConfirmDialog.new()
	dialog.setup(title, message, ok_text, danger)
	dialog.confirmed.connect(on_ok)
	hud.add_child(dialog)

func _notify(text: String) -> void:
	if hud.has_method("show_notification"):
		hud.show_notification(text)
