extends CanvasLayer

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const UI = preload("res://scripts/ui/ui_style.gd")
const SkillDB = preload("res://scripts/skills/skill_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")

## Желаемые размеры окон HUD в логических пикселях (база растяжения 1600×900,
## см. project.godot). Если окно игры меньше, окно ужимается, а списки
## прокручиваются (_layout_windows).
const WINDOW_SIZES: Dictionary = {
	"InventoryWindow": Vector2(620, 520),
	"MachineWindow": Vector2(640, 560),
	"SalesWindow": Vector2(680, 500),
	"RepairWindow": Vector2(680, 560),
	"ContractWindow": Vector2(760, 700),
	"ClassSelectWindow": Vector2(780, 660),
	"SkillsWindow": Vector2(800, 680),
	"PauseWindow": Vector2(640, 700),
	"VictoryWindow": Vector2(760, 560),
}
const WINDOW_SCREEN_MARGIN: float = 24.0
const HOTBAR_SLOT_SIZE: Vector2 = Vector2(118, 46)
## Тост уведомлений должен рисоваться поверх окон рюкзака, станка и заказов.
const NOTIFICATION_Z_INDEX: int = 200

@onready var prompt_container: PanelContainer = $PromptContainer
@onready var prompt_label: Label = $PromptContainer/MarginContainer/PromptLabel
@onready var notification_container: PanelContainer = $NotificationContainer
@onready var notification_label: Label = $NotificationContainer/MarginContainer/NotificationLabel
@onready var notification_timer: Timer = $NotificationTimer

@onready var class_button: Button = get_node_or_null("TopLeftUI/Panel/Margin/VBox/ClassButton")
@onready var class_window: PanelContainer = get_node_or_null("ClassSelectWindow")
@onready var class_close_button: Button = get_node_or_null("ClassSelectWindow/Margin/VBox/HeaderHBox/CloseButton")
@onready var classes_list: VBoxContainer = get_node_or_null("ClassSelectWindow/Margin/VBox/ScrollContainer/ClassesList")

@onready var skills_button: Button = get_node_or_null("TopLeftUI/Panel/Margin/VBox/SkillsButton")
@onready var skills_window: PanelContainer = get_node_or_null("SkillsWindow")
@onready var skills_close_button: Button = get_node_or_null("SkillsWindow/Margin/VBox/HeaderHBox/CloseButton")
@onready var skills_overall_level_label: Label = get_node_or_null("SkillsWindow/Margin/VBox/OverallHBox/OverallLevelLabel")
@onready var skills_overall_title_label: Label = get_node_or_null("SkillsWindow/Margin/VBox/OverallHBox/OverallTitleLabel")
@onready var skills_list: VBoxContainer = get_node_or_null("SkillsWindow/Margin/VBox/ScrollContainer/SkillsList")

# Меню паузы и звука
@onready var pause_button: Button = get_node_or_null("TopRightUI/Panel/Margin/VBox/PauseButton")
@onready var pause_window: PanelContainer = get_node_or_null("PauseWindow")
@onready var base_progress_label: Label = get_node_or_null("PauseWindow/Margin/VBox/BaseProgressLabel")
@onready var ch2_progress_label: Label = get_node_or_null("PauseWindow/Margin/VBox/Ch2ProgressLabel")
@onready var pause_tasks_list: VBoxContainer = get_node_or_null("PauseWindow/Margin/VBox/TasksScroll/TasksList")
@onready var sfx_slider: HSlider = get_node_or_null("PauseWindow/Margin/VBox/SfxHBox/SfxSlider")
@onready var amb_slider: HSlider = get_node_or_null("PauseWindow/Margin/VBox/AmbHBox/AmbSlider")
@onready var pause_resume_button: Button = get_node_or_null("PauseWindow/Margin/VBox/ResumeButton")
@onready var pause_save_button: Button = get_node_or_null("PauseWindow/Margin/VBox/SaveLoadHBox/SaveButton")
@onready var pause_load_button: Button = get_node_or_null("PauseWindow/Margin/VBox/SaveLoadHBox/LoadButton")
@onready var pause_quit_button: Button = get_node_or_null("PauseWindow/Margin/VBox/QuitButton")

# Окно завершения первой главы (Base Restored)
@onready var victory_window: PanelContainer = get_node_or_null("VictoryWindow")
@onready var victory_stats_label: Label = get_node_or_null("VictoryWindow/Margin/VBox/StatsLabel")
@onready var victory_continue_button: Button = get_node_or_null("VictoryWindow/Margin/VBox/ContinueButton")

var _victory_shown: bool = false

@onready var health_bar: ProgressBar = $TopLeftUI/Panel/Margin/VBox/HealthBar
@onready var health_label: Label = $TopLeftUI/Panel/Margin/VBox/HealthBar/Label
@onready var energy_bar: ProgressBar = $TopLeftUI/Panel/Margin/VBox/EnergyBar
@onready var energy_label: Label = $TopLeftUI/Panel/Margin/VBox/EnergyBar/Label
@onready var thirst_bar: ProgressBar = $TopLeftUI/Panel/Margin/VBox/ThirstBar
@onready var thirst_label: Label = $TopLeftUI/Panel/Margin/VBox/ThirstBar/Label
@onready var hunger_bar: ProgressBar = $TopLeftUI/Panel/Margin/VBox/HungerBar
@onready var hunger_label: Label = $TopLeftUI/Panel/Margin/VBox/HungerBar/Label
@onready var wetness_bar: ProgressBar = $TopLeftUI/Panel/Margin/VBox/WetnessBar
@onready var wetness_label: Label = $TopLeftUI/Panel/Margin/VBox/WetnessBar/Label

@onready var time_label: Label = $TopRightUI/Panel/Margin/VBox/TimeLabel
@onready var weather_label: Label = $TopRightUI/Panel/Margin/VBox/WeatherLabel
@onready var season_label: Label = $TopRightUI/Panel/Margin/VBox/SeasonLabel
@onready var money_label: Label = $TopRightUI/Panel/Margin/VBox/MoneyLabel
@onready var power_label: Label = $TopRightUI/Panel/Margin/VBox/PowerLabel

# Быстрый счетчик ресурсов
@onready var wood_label: Label = $ResourceBarUI/Panel/Margin/HBox/WoodCount
@onready var stone_label: Label = $ResourceBarUI/Panel/Margin/HBox/StoneCount
@onready var clay_label: Label = $ResourceBarUI/Panel/Margin/HBox/ClayCount
@onready var sand_label: Label = $ResourceBarUI/Panel/Margin/HBox/SandCount
@onready var water_label: Label = $ResourceBarUI/Panel/Margin/HBox/WaterCount

# Хотбар
@onready var slot_buttons: Array[Button] = [
	$HotbarUI/Panel/Margin/HBox/Slot1,
	$HotbarUI/Panel/Margin/HBox/Slot2,
	$HotbarUI/Panel/Margin/HBox/Slot3,
	$HotbarUI/Panel/Margin/HBox/Slot4,
	$HotbarUI/Panel/Margin/HBox/Slot5
]

# Окно рюкзака
@onready var inventory_window: PanelContainer = $InventoryWindow
@onready var items_list: VBoxContainer = $InventoryWindow/Margin/VBox/ScrollContainer/ItemsList
@onready var inv_footer_label: Label = $InventoryWindow/Margin/VBox/FooterLabel
@onready var inv_close_button: Button = $InventoryWindow/Margin/VBox/HeaderHBox/CloseButton

# Окно производственной машины
@onready var machine_window: PanelContainer = $MachineWindow
@onready var machine_title_label: Label = $MachineWindow/Margin/VBox/HeaderHBox/TitleLabel
@onready var machine_close_button: Button = $MachineWindow/Margin/VBox/HeaderHBox/CloseButton
@onready var machine_status_label: Label = $MachineWindow/Margin/VBox/ProgressBox/StatusLabel
@onready var machine_progress_bar: ProgressBar = $MachineWindow/Margin/VBox/ProgressBox/ProgressBar
@onready var machine_recipe_list: VBoxContainer = $MachineWindow/Margin/VBox/ScrollContainer/RecipeList

# Окно станции отправки (продажи)
@onready var sales_window: PanelContainer = $SalesWindow
@onready var sales_close_button: Button = $SalesWindow/Margin/VBox/HeaderHBox/CloseButton
@onready var sales_goods_list: VBoxContainer = $SalesWindow/Margin/VBox/ScrollContainer/GoodsList
@onready var quick_sell_button: Button = $SalesWindow/Margin/VBox/QuickSellButton

# Окно восстановления зданий
@onready var repair_window: PanelContainer = $RepairWindow
@onready var repair_title_label: Label = $RepairWindow/Margin/VBox/HeaderHBox/TitleLabel
@onready var repair_close_button: Button = $RepairWindow/Margin/VBox/HeaderHBox/CloseButton
@onready var repair_status_label: Label = $RepairWindow/Margin/VBox/StageStatusLabel
@onready var repair_progress_bar: ProgressBar = $RepairWindow/Margin/VBox/StageProgressBar
@onready var repair_perks_label: Label = $RepairWindow/Margin/VBox/PerksLabel
@onready var repair_next_title_label: Label = $RepairWindow/Margin/VBox/NextStageTitleLabel
@onready var repair_requirements_list: VBoxContainer = $RepairWindow/Margin/VBox/RequirementsScroll/RequirementsList
@onready var repair_upgrade_button: Button = $RepairWindow/Margin/VBox/UpgradeButton
@onready var repair_sleep_button: Button = $RepairWindow/Margin/VBox/SleepButton

# Окно контрактов и NPC
@onready var contract_window: PanelContainer = $ContractWindow
@onready var contract_title_label: Label = $ContractWindow/Margin/VBox/HeaderHBox/TitleLabel
@onready var contract_close_button: Button = $ContractWindow/Margin/VBox/HeaderHBox/CloseButton
@onready var contract_dialogue_label: Label = $ContractWindow/Margin/VBox/DialogueBox/DialogueMargin/DialogueLabel
@onready var contracts_list: VBoxContainer = $ContractWindow/Margin/VBox/ScrollContainer/ContractsList

var _bound_player: Node = null
var _current_active_machine: Node = null
var _current_active_station: Node = null
var repair_storage_button: Button
var _current_active_building: Node = null
var _current_active_npc: Node = null
var _cached_weather_mgr: Node = null
var _cached_day_cycle: Node = null
var _cached_season_mgr: Node = null
var _cached_wind_sys: Node = null
var _cached_world: Node = null

var style_slot_active: StyleBoxFlat = null
var style_slot_normal: StyleBoxFlat = null

func _get_weather_mgr() -> Node:
	if not is_instance_valid(_cached_weather_mgr) and get_tree() and get_tree().root:
		_cached_weather_mgr = get_tree().root.find_child("WeatherManager", true, false)
	return _cached_weather_mgr

func _get_day_cycle() -> Node:
	if not is_instance_valid(_cached_day_cycle) and get_tree() and get_tree().root:
		_cached_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	return _cached_day_cycle

func _get_season_manager() -> Node:
	if not is_instance_valid(_cached_season_mgr) and get_tree() and get_tree().root:
		_cached_season_mgr = get_tree().root.find_child("SeasonManager", true, false)
	return _cached_season_mgr

## Система ветра (сила ветра для ветряка) — по группе, чтобы HUD не зависел от пути узла.
func _get_wind_system() -> Node:
	if get_tree():
		var ws = get_tree().get_first_node_in_group("wind_system")
		if is_instance_valid(ws):
			_cached_wind_sys = ws
	if not is_instance_valid(_cached_wind_sys) and get_tree():
		_cached_wind_sys = get_tree().get_first_node_in_group("wind_system")
	return _cached_wind_sys

func _get_world() -> Node:
	if not is_instance_valid(_cached_world):
		_cached_world = get_tree().current_scene if get_tree().current_scene else (get_tree().root.find_child("World", true, false) if get_tree() and get_tree().root else null)
	return _cached_world

func _ready() -> void:
	prompt_container.visible = false
	notification_container.visible = false
	if inventory_window:
		inventory_window.visible = false
	if machine_window:
		machine_window.visible = false
	if sales_window:
		sales_window.visible = false
	if repair_window:
		repair_window.visible = false
	if contract_window:
		contract_window.visible = false
	
	if notification_timer:
		notification_timer.timeout.connect(_on_notification_timeout)
	
	# Хотбар
	for i in range(slot_buttons.size()):
		var btn: Button = slot_buttons[i]
		if btn:
			btn.pressed.connect(_on_slot_button_pressed.bind(i))
	_setup_hotbar_slots()
	
	if inv_close_button:
		inv_close_button.pressed.connect(toggle_inventory)
	if machine_close_button:
		machine_close_button.pressed.connect(close_machine_window)
	if sales_close_button:
		sales_close_button.pressed.connect(close_sales_window)
	if quick_sell_button:
		quick_sell_button.pressed.connect(_on_quick_sell_pressed)
	if repair_close_button:
		repair_close_button.pressed.connect(close_repair_window)
	if repair_upgrade_button:
		repair_upgrade_button.pressed.connect(_on_upgrade_building_pressed)
	if repair_sleep_button:
		repair_sleep_button.pressed.connect(_on_building_sleep_pressed)
	if repair_upgrade_button:
		repair_storage_button = Button.new()
		repair_storage_button.name = "StorageInventoryButton"
		repair_storage_button.text = "📦 Открыть склад (20 ячеек)"
		repair_storage_button.visible = false
		repair_upgrade_button.get_parent().add_child(repair_storage_button)
		repair_storage_button.pressed.connect(func():
			var controller = get_node_or_null("GameplayUIController")
			if not controller:
				var world = _get_world()
				if world:
					controller = world.get_node_or_null("GameplayUIController")
			if controller and is_instance_valid(_current_active_building):
				controller.open_storage_panel(_current_active_building)
		)
	if contract_close_button:
		contract_close_button.pressed.connect(close_contract_window)
	if class_close_button:
		class_close_button.pressed.connect(close_class_window)
	if class_button:
		class_button.pressed.connect(toggle_class_window)
	if skills_window:
		skills_window.visible = false
	if skills_close_button:
		skills_close_button.pressed.connect(close_skills_window)
	if skills_button:
		skills_button.pressed.connect(toggle_skills_window)
	
	if pause_button:
		pause_button.pressed.connect(toggle_pause_menu)
	if pause_resume_button:
		pause_resume_button.pressed.connect(close_pause_menu)
	if pause_save_button:
		pause_save_button.pressed.connect(_on_pause_save_pressed)
	if pause_load_button:
		pause_load_button.pressed.connect(_on_pause_load_pressed)
	if pause_quit_button:
		pause_quit_button.pressed.connect(func(): get_tree().quit())
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	if amb_slider:
		amb_slider.value_changed.connect(_on_amb_slider_changed)
	if victory_continue_button:
		victory_continue_button.pressed.connect(close_victory_window)
	
	_init_styles()
	_apply_hud_layout()
	_layout_windows()
	get_viewport().size_changed.connect(_layout_windows)

# --- Раскладка и читаемость интерфейса ---

## Размеры постоянных панелей HUD: крупнее шрифты, хотбар по ширине подписей.
func _apply_hud_layout() -> void:
	var top_left := get_node_or_null("TopLeftUI") as Control
	if top_left:
		top_left.offset_right = top_left.offset_left + 300.0
		top_left.offset_bottom = top_left.offset_top + 224.0
	for bar in [health_bar, energy_bar, hunger_bar, thirst_bar, wetness_bar]:
		if bar:
			bar.custom_minimum_size.y = 20.0
	for lbl in [health_label, energy_label, hunger_label, thirst_label, wetness_label]:
		if lbl:
			lbl.add_theme_font_size_override("font_size", 13)
	if class_button:
		class_button.add_theme_font_size_override("font_size", 13)
		class_button.custom_minimum_size.y = 24.0
	if skills_button:
		skills_button.add_theme_font_size_override("font_size", 13)
		skills_button.custom_minimum_size.y = 24.0
	var top_right := get_node_or_null("TopRightUI") as Control
	if top_right:
		top_right.offset_left = top_right.offset_right - 300.0
		top_right.offset_bottom = top_right.offset_top + 176.0
	for pair in [[time_label, 15], [weather_label, 15], [season_label, 12], [money_label, 16], [power_label, 14]]:
		if pair[0]:
			(pair[0] as Label).add_theme_font_size_override("font_size", pair[1])
	var save_lbl := get_node_or_null("TopRightUI/Panel/Margin/VBox/SaveLoadLabel") as Label
	if save_lbl:
		save_lbl.add_theme_font_size_override("font_size", 12)
	if pause_button:
		pause_button.add_theme_font_size_override("font_size", 13)
		pause_button.custom_minimum_size.y = 24.0
	var res_bar := get_node_or_null("ResourceBarUI") as Control
	if res_bar:
		res_bar.offset_left = -360.0
		res_bar.offset_right = 360.0
		res_bar.offset_bottom = res_bar.offset_top + 44.0
	for lbl in [wood_label, stone_label, clay_label, sand_label, water_label]:
		if lbl:
			lbl.add_theme_font_size_override("font_size", 15)
	var hotbar := get_node_or_null("HotbarUI") as Control
	if hotbar:
		var n: int = slot_buttons.size()
		var w: float = n * HOTBAR_SLOT_SIZE.x + maxi(0, n - 1) * 8.0 + 16.0
		hotbar.offset_left = -w * 0.5
		hotbar.offset_right = w * 0.5
		hotbar.offset_top = -(HOTBAR_SLOT_SIZE.y + 12.0) - 15.0
	for btn in slot_buttons:
		if btn:
			btn.custom_minimum_size = HOTBAR_SLOT_SIZE
			btn.add_theme_font_size_override("font_size", 15)
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_setup_hotbar_sharpness_bars()
	if prompt_container:
		prompt_container.offset_left = -320.0
		prompt_container.offset_right = 320.0
		prompt_container.offset_top = -(HOTBAR_SLOT_SIZE.y + 12.0) - 15.0 - 62.0
		prompt_container.offset_bottom = prompt_container.offset_top + 46.0
		prompt_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if prompt_label:
		prompt_label.add_theme_font_size_override("font_size", 15)
		prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if notification_container:
		notification_container.offset_left = -360.0
		notification_container.offset_right = 360.0
	if notification_label:
		notification_label.add_theme_font_size_override("font_size", 15)
		notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for path in ["PauseWindow/Margin/VBox/SfxHBox/SfxText", "PauseWindow/Margin/VBox/AmbHBox/AmbText"]:
		var l := get_node_or_null(path) as Label
		if l:
			l.custom_minimum_size.x = 240.0
	for slider in [sfx_slider, amb_slider]:
		if slider:
			slider.custom_minimum_size = Vector2(200, 24)
	for win in _all_windows():
		UI.polish_text(win)

func _all_windows() -> Array:
	var out: Array = []
	for win_name in WINDOW_SIZES.keys():
		var win := get_node_or_null(NodePath(win_name)) as Control
		if win:
			out.append(win)
	return out

## Центрирует окна и ужимает их до размеров экрана (логические пиксели).
func _layout_windows() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for win_name in WINDOW_SIZES.keys():
		var win := get_node_or_null(NodePath(win_name)) as Control
		if not win:
			continue
		var want: Vector2 = WINDOW_SIZES[win_name]
		var w: float = minf(want.x, maxf(320.0, vp.x - WINDOW_SCREEN_MARGIN * 2.0))
		var h: float = minf(want.y, maxf(240.0, vp.y - WINDOW_SCREEN_MARGIN * 2.0))
		win.set_anchors_preset(Control.PRESET_CENTER)
		win.offset_left = -w * 0.5
		win.offset_right = w * 0.5
		win.offset_top = -h * 0.5
		win.offset_bottom = h * 0.5
		win.grow_horizontal = Control.GROW_DIRECTION_BOTH
		win.grow_vertical = Control.GROW_DIRECTION_BOTH
		# Списки внутри окна забирают свободную высоту, остальное — по содержимому.
		for scroll in win.find_children("*", "ScrollContainer", true, false):
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

## Вызывается после перестройки содержимого окна.
func _polish(win: Control) -> void:
	if win:
		UI.polish_text(win)

func _unhandled_input(event: InputEvent) -> void:
	# Во время отдыха/сна (переход с часами) интерфейс не реагирует на ESC.
	if _bound_player and _bound_player.get("is_resting"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if victory_window and victory_window.visible:
				close_victory_window()
				get_viewport().set_input_as_handled()
			elif pause_window and pause_window.visible:
				close_pause_menu()
				get_viewport().set_input_as_handled()
			elif class_window and class_window.visible:
				close_class_window()
				get_viewport().set_input_as_handled()
			elif skills_window and skills_window.visible:
				close_skills_window()
				get_viewport().set_input_as_handled()
			elif contract_window and contract_window.visible:
				close_contract_window()
				get_viewport().set_input_as_handled()
			elif repair_window and repair_window.visible:
				close_repair_window()
				get_viewport().set_input_as_handled()
			elif machine_window and machine_window.visible:
				close_machine_window()
				get_viewport().set_input_as_handled()
			elif sales_window and sales_window.visible:
				close_sales_window()
				get_viewport().set_input_as_handled()
			elif inventory_window and inventory_window.visible:
				toggle_inventory()
				get_viewport().set_input_as_handled()
			else:
				toggle_pause_menu()
				get_viewport().set_input_as_handled()

func is_gameplay_input_blocked() -> bool:
	# Режимы размещения (делянка) и прочие перехватчики мыши.
	if is_inside_tree() and get_tree().get_first_node_in_group("ui_input_blockers") != null:
		return true
	for window in [inventory_window, machine_window, sales_window, repair_window, contract_window, class_window, skills_window, pause_window, victory_window]:
		if is_instance_valid(window) and window.visible:
			return true
	return false

func _process(_delta: float) -> void:
	if machine_window and machine_window.visible and _current_active_machine:
		_update_machine_progress_ui()

func _init_styles() -> void:
	if not style_slot_active:
		var s_act: StyleBoxFlat = StyleBoxFlat.new()
		s_act.bg_color = Color(0.2, 0.3, 0.45, 0.95)
		s_act.border_color = Color(1.0, 0.85, 0.25, 1.0)
		s_act.set_border_width_all(2)
		s_act.set_corner_radius_all(6)
		style_slot_active = s_act
	
	if not style_slot_normal:
		var s_norm: StyleBoxFlat = StyleBoxFlat.new()
		s_norm.bg_color = Color(0.12, 0.15, 0.18, 0.85)
		s_norm.border_color = Color(0.3, 0.35, 0.4, 0.6)
		s_norm.set_border_width_all(1)
		s_norm.set_corner_radius_all(6)
		style_slot_normal = s_norm

func bind_player(player: Node) -> void:
	if not player:
		return
	_bound_player = player
	
	if player.has_signal("focused_interactable_changed"):
		player.focused_interactable_changed.connect(_on_focused_interactable_changed)
	if player.has_signal("notification_received"):
		player.notification_received.connect(show_notification)
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if "health" in player and "max_health" in player:
		_on_health_changed(player.health, player.max_health)
	if player.has_signal("energy_changed"):
		player.energy_changed.connect(_on_energy_changed)
	if "energy" in player and "max_energy" in player:
		_on_energy_changed(player.energy, player.max_energy)
	if player.has_signal("inventory_toggle_requested"):
		player.inventory_toggle_requested.connect(toggle_inventory)
	if player.has_signal("thirst_changed"):
		player.thirst_changed.connect(_on_thirst_changed)
	if "thirst" in player and "max_thirst" in player:
		_on_thirst_changed(player.thirst, player.max_thirst)
	if player.has_signal("hunger_changed"):
		player.hunger_changed.connect(_on_hunger_changed)
	if "hunger" in player and "max_hunger" in player:
		_on_hunger_changed(player.hunger, player.max_hunger)
	if player.has_signal("wetness_changed"):
		player.wetness_changed.connect(_on_wetness_changed)
	if "wetness" in player and "max_wetness" in player:
		_on_wetness_changed(player.wetness, player.max_wetness)
	
	if player.has_signal("class_select_toggle_requested"):
		player.class_select_toggle_requested.connect(toggle_class_window)
	if player.has_signal("character_class_changed"):
		player.character_class_changed.connect(_on_character_class_changed)
	if "character_class" in player:
		_on_character_class_changed(player.character_class, CharacterClassDB.get_class_display_name(player.character_class))
	
	if player.has_signal("skills_toggle_requested"):
		player.skills_toggle_requested.connect(toggle_skills_window)
	if "skills" in player and player.skills:
		var p_skills = player.skills
		if p_skills.has_signal("skills_updated"):
			p_skills.skills_updated.connect(_update_skills_button)
		if p_skills.has_signal("skill_leveled_up"):
			p_skills.skill_leveled_up.connect(_on_skill_leveled_up)
		_update_skills_button()
	
	if "inventory" in player and player.inventory:
		var inv = player.inventory
		inv.inventory_updated.connect(_on_inventory_updated)
		inv.tool_changed.connect(_on_tool_changed)
		if inv.has_signal("credits_changed"):
			inv.credits_changed.connect(set_credits)
		if inv.has_signal("tool_sharpness_changed"):
			inv.tool_sharpness_changed.connect(_on_tool_sharpness_changed)
		_setup_hotbar_sharpness_bars()
		_highlight_slot(0)
		_update_resource_counters()
		update_hotbar_sharpness()
		set_credits(inv.credits if "credits" in inv else 0)

const DEFAULT_SLOT_TOOLS: Array[String] = ["axe", "pickaxe", "shovel", "bucket", "backpack"]

func _setup_hotbar_slots() -> void:
	var inv = _bound_player.inventory if (_bound_player and "inventory" in _bound_player) else null
	for i in range(slot_buttons.size()):
		var btn: Button = slot_buttons[i]
		if not btn:
			continue
		var tool_id: String = DEFAULT_SLOT_TOOLS[i] if i < DEFAULT_SLOT_TOOLS.size() else ""
		if inv and i < inv.tools.size():
			tool_id = inv.tools[i]
		
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		
		var tex: Texture2D = ItemIcons.get_texture(tool_id) if not tool_id.is_empty() else null
		btn.icon = tex
		
		var t_data: Dictionary = ItemDB.get_item(tool_id) if not tool_id.is_empty() else {}
		var raw_name: String = t_data.get("name", tool_id)
		var short_name: String = raw_name
		if tool_id == "axe": short_name = "Топор"
		elif tool_id == "iron_axe": short_name = "Жел. топор"
		elif tool_id == "pickaxe": short_name = "Кирка"
		elif tool_id == "iron_pickaxe": short_name = "Жел. кирка"
		elif tool_id == "shovel": short_name = "Мотыга"
		elif tool_id == "iron_shovel": short_name = "Жел. мотыга"
		elif tool_id == "bucket": short_name = "Ведро"
		elif tool_id == "reinforced_bucket": short_name = "Усил. ведро"
		elif tool_id == "backpack": short_name = "Рюкзак"
		elif tool_id == "large_backpack": short_name = "Больш. рюкзак"
		
		btn.text = " %d: %s" % [i + 1, short_name]
		
		if i == 3:
			btn.tooltip_text = "%d: %s %s\n%s" % [
				i + 1,
				t_data.get("icon", "💧"),
				raw_name,
				t_data.get("description", "Используется для переноски чистой воды.")
			]
		elif i == 4:
			var slots_info: String = "Слоты: %d" % inv.max_slots if inv else "12 слотов"
			btn.tooltip_text = "%d: %s %s\n%s\nКлик — открыть/закрыть рюкзак" % [
				i + 1,
				t_data.get("icon", "🎒"),
				raw_name,
				slots_info
			]

func _setup_hotbar_sharpness_bars() -> void:
	for i in [0, 1, 2]:
		if i >= slot_buttons.size():
			continue
		var btn: Button = slot_buttons[i]
		if not btn:
			continue
		var old = btn.get_node_or_null("SharpnessBar")
		if old:
			continue
		var bar := ProgressBar.new()
		bar.name = "SharpnessBar"
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_left = 6
		bar.offset_right = -6
		bar.offset_bottom = -3
		bar.offset_top = -7
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.08, 0.1, 0.12, 0.9)
		bg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg)
		btn.add_child(bar)

func update_hotbar_sharpness() -> void:
	_setup_hotbar_slots()
	if not _bound_player or not ("inventory" in _bound_player):
		return
	var inv = _bound_player.inventory
	if not inv or not inv.has_method("get_tool_sharpness"):
		return
	var slot_tools: Array[String] = ["axe", "pickaxe", "shovel"]
	for i in range(slot_tools.size()):
		if i >= slot_buttons.size():
			continue
		var btn: Button = slot_buttons[i]
		if not btn:
			continue
		var t_type: String = slot_tools[i]
		var tool_id: String = t_type
		if i < inv.tools.size():
			tool_id = inv.tools[i]
		var s: float = inv.get_tool_sharpness(tool_id)
		var eff: Dictionary = inv.get_sharpness_efficiency(tool_id)
		var t_data: Dictionary = ItemDB.get_item(tool_id)
		var t_name: String = t_data.get("name", tool_id)
		var t_icon: String = t_data.get("icon", "")
		
		var tip: String = "%d: %s %s\nЗаточка: %d%% [%s]" % [i + 1, t_icon, t_name, int(round(s)), eff.get("status_name", "")]
		if eff.get("is_dull", false):
			tip += "\n⚠️ Лезвие затуплено! Урон: %d%%, расход сил: +%d%%" % [
				int(round(eff.get("power_mult", 1.0) * 100.0)),
				int(round((eff.get("energy_cost_mult", 1.0) - 1.0) * 100.0))
			]
		elif eff.get("crit_bonus", 0.0) > 0.0:
			tip += "\n✨ Бритвенная острота: +10% шанс двойной добычи, -10% расход сил!"
		btn.tooltip_text = tip
		
		var bar: ProgressBar = btn.get_node_or_null("SharpnessBar") as ProgressBar
		if bar:
			bar.value = s
			var col: Color = Color(0.2, 0.85, 0.3)
			if s < 10.0:
				col = Color(0.95, 0.2, 0.2)
			elif s < 35.0:
				col = Color(0.95, 0.55, 0.15)
			elif s < 75.0:
				col = Color(0.85, 0.85, 0.2)
			var fill := StyleBoxFlat.new()
			fill.bg_color = col
			fill.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("fill", fill)

func _on_tool_sharpness_changed(_tool_id: String, _curr: float) -> void:
	update_hotbar_sharpness()

func _on_slot_button_pressed(index: int) -> void:
	if index == 4:
		toggle_inventory()
	elif _bound_player and _bound_player.has_method("equip_slot"):
		_bound_player.equip_slot(index)

func _on_tool_changed(tool_id: String, _tool_name: String) -> void:
	var slot_map: Dictionary = {
		"axe": 0,
		"iron_axe": 0,
		"pickaxe": 1,
		"iron_pickaxe": 1,
		"shovel": 2,
		"iron_shovel": 2,
		"bucket": 3,
		"reinforced_bucket": 3,
		"backpack": 4,
		"large_backpack": 4
	}
	var idx: int = slot_map.get(tool_id, 0)
	_highlight_slot(idx)
	update_hotbar_sharpness()

func _highlight_slot(active_index: int) -> void:
	for i in range(slot_buttons.size()):
		var btn: Button = slot_buttons[i]
		if not btn:
			continue
		if i == active_index:
			btn.add_theme_stylebox_override("normal", style_slot_active)
			btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		else:
			btn.add_theme_stylebox_override("normal", style_slot_normal)
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

func _on_health_changed(curr: float, max_v: float) -> void:
	if health_bar:
		health_bar.value = (curr / max_v) * 100.0
	if health_label:
		var pct: int = int((curr / max_v) * 100.0)
		if pct <= 25:
			health_label.text = "❤️ Здоровье %d%% (Опасно!)" % pct
			health_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
		elif pct <= 50:
			health_label.text = "❤️ Здоровье %d%% (Ранение)" % pct
			health_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
		else:
			health_label.text = "❤️ Здоровье %d%%" % pct
			health_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))

func _on_energy_changed(curr: float, max_v: float) -> void:
	if energy_bar:
		energy_bar.value = (curr / max_v) * 100.0
	if energy_label:
		var pct: int = int((curr / max_v) * 100.0)
		var is_deprived: bool = false
		if _bound_player and _bound_player.has_method("is_sleep_deprived"):
			is_deprived = _bound_player.is_sleep_deprived()
		
		if is_deprived:
			energy_label.text = "⚡ Энергия %d%% (Бессонница!)" % pct
			energy_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.95))
		elif pct <= 0:
			energy_label.text = "⚡ Энергия %d%% (Истощение!)" % pct
			energy_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif pct < 20:
			energy_label.text = "⚡ Энергия %d%% (Усталость!)" % pct
			energy_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		elif pct < 50:
			energy_label.text = "⚡ Энергия %d%%" % pct
			energy_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		else:
			energy_label.text = "⚡ Энергия %d%%" % pct
			energy_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

func _on_thirst_changed(curr: float, max_v: float) -> void:
	if thirst_bar:
		thirst_bar.value = (curr / max_v) * 100.0
	if thirst_label:
		var pct: int = int((curr / max_v) * 100.0)
		if pct <= 15:
			thirst_label.text = "💧 Жажда %d%% (Обезвоживание!)" % pct
			thirst_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif pct <= 40:
			thirst_label.text = "💧 Жажда %d%% (Жажда!)" % pct
			thirst_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		else:
			thirst_label.text = "💧 Жажда %d%%" % pct
			thirst_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))

func _on_hunger_changed(curr: float, max_v: float) -> void:
	if hunger_bar:
		hunger_bar.value = (curr / max_v) * 100.0
	if hunger_label:
		var pct: int = int((curr / max_v) * 100.0)
		if pct <= 15:
			hunger_label.text = "🍞 Сытость %d%% (Голод!)" % pct
			hunger_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif pct <= 40:
			hunger_label.text = "🍞 Сытость %d%%" % pct
			hunger_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		else:
			hunger_label.text = "🍞 Сытость %d%%" % pct
			hunger_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.8))

func _on_wetness_changed(curr: float, max_v: float) -> void:
	if wetness_bar:
		wetness_bar.value = (curr / max_v) * 100.0
	if wetness_label:
		var pct: int = int((curr / max_v) * 100.0)
		if pct <= 0:
			wetness_label.text = "💧 Сухой (0%)"
			wetness_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		elif pct < 40:
			wetness_label.text = "💧 Влажный %d%%" % pct
			wetness_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		elif pct < 80:
			wetness_label.text = "💧 Промок %d%% (Холод!)" % pct
			wetness_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
		else:
			wetness_label.text = "❄️ Насквозь промок %d%%" % pct
			wetness_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

func update_time_display(day: int, hour: int, minute: int, formatted: String, phase: String) -> void:
	if time_label:
		time_label.text = formatted
	if weather_label:
		var weather_mgr: Node = _get_weather_mgr()
		var w_name: String = "Ясно"
		var icon: String = "☀️"
		var temp_offset: int = 0
		if weather_mgr and weather_mgr.has_method("get_weather_name"):
			w_name = weather_mgr.get_weather_name()
			icon = weather_mgr.get_weather_icon()
			temp_offset = weather_mgr.get_temperature_offset()
		
		var base_temp: int = 22
		match phase:
			"Утро": base_temp = 16
			"День": base_temp = 23
			"Вечер": base_temp = 18
			"Ночь": base_temp = 11
		
		var final_temp: int = maxi(-25, base_temp + temp_offset + _get_season_temperature_offset())
		weather_label.text = "%s %s (%+d°C)" % [icon, w_name, final_temp]

func update_weather_display(_new_type: int = 0, w_name: String = "", icon: String = "") -> void:
	if weather_label:
		var day_cycle: Node = _get_day_cycle()
		var phase: String = day_cycle.get_current_phase() if (day_cycle and day_cycle.has_method("get_current_phase")) else "День"
		var base_temp: int = 22
		match phase:
			"Утро": base_temp = 16
			"День": base_temp = 23
			"Вечер": base_temp = 18
			"Ночь": base_temp = 11
		
		var weather_mgr: Node = _get_weather_mgr()
		var temp_offset: int = weather_mgr.get_temperature_offset() if (weather_mgr and weather_mgr.has_method("get_temperature_offset")) else 0
		var final_temp: int = maxi(-25, base_temp + temp_offset + _get_season_temperature_offset())
		weather_label.text = "%s %s (%+d°C)" % [icon, w_name, final_temp]

## Сезонный сдвиг температуры (лето теплее, зима холоднее). 0 без системы сезонов.
func _get_season_temperature_offset() -> int:
	var sm: Node = _get_season_manager()
	if sm and sm.has_method("get_temperature_offset"):
		return int(sm.get_temperature_offset())
	return Seasons.get_temperature_offset()

## Строка календаря: «🌱 Весна» + активное погодное событие.
func update_season_display() -> void:
	if not season_label:
		season_label = get_node_or_null("TopRightUI/Panel/Margin/VBox/SeasonLabel")
	if not season_label:
		return
	if not Seasons.is_enabled():
		season_label.text = ""
		season_label.visible = false
		return
	season_label.visible = true
	var caption: String = Seasons.get_calendar_caption()
	var sm: Node = _get_season_manager()
	if sm and sm.has_method("get_active_event_caption"):
		var event_caption: String = str(sm.get_active_event_caption())
		if event_caption != "":
			caption = "%s · %s" % [caption, event_caption]
	season_label.text = caption

func update_power_display(stored: float, capacity: float, generation: float, consumption: float, has_power: bool, source_mode: int = -1) -> void:
	if not power_label:
		power_label = get_node_or_null("TopRightUI/Panel/Margin/VBox/PowerLabel")
	if not power_label:
		return

	var net: float = generation - consumption
	var pct: int = int((stored / capacity) * 100.0) if capacity > 0 else 0
	var sign_str: String = "+" if net >= 0 else ""
	# Выбранный источник питания (Сеть / Ветряк / Батарея), если он известен.
	var mode_str: String = ""
	match source_mode:
		1: mode_str = " · Ветряк"
		2: mode_str = " · Батарея"
		_: mode_str = ""

	if not has_power:
		var reason: String
		if source_mode == 2:
			reason = ": батарея разряжена (заряд %d%%)" % pct
		elif consumption > generation:
			reason = ": тратится %.1f кВт > генерация %.1f кВт" % [consumption, generation]
		else:
			reason = ": нет доступной мощности"
		power_label.text = "⚡ Сеть%s: Обесточена (0%%)%s" % [mode_str, reason]
		power_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	elif net >= 0:
		power_label.text = "⚡ Сеть%s: %d%% (%s%.1f кВт)" % [mode_str, pct, sign_str, net]
		power_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.6))
	else:
		power_label.text = "⚡ Сеть%s: %d%% (%.1f кВт)" % [mode_str, pct, net]
		power_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))

	# Сила ветра рядом с состоянием сети: от неё напрямую зависит выработка ветряка,
	# а по ней игрок решает, переключать ли питание на батарею.
	var wind_sys: Node = _get_wind_system()
	if wind_sys and wind_sys.has_method("get_wind_speed"):
		power_label.text += " · 💨 %.1f м/с (%s)" % [wind_sys.get_wind_speed(), wind_sys.get_wind_name().to_lower()]

func _on_inventory_updated() -> void:
	_update_resource_counters()
	update_hotbar_sharpness()
	if inventory_window and inventory_window.visible:
		_refresh_inventory_window()
	if machine_window and machine_window.visible and _current_active_machine:
		_populate_machine_recipes(_current_active_machine)
	if sales_window and sales_window.visible:
		_refresh_sales_window()
	if repair_window and repair_window.visible and _current_active_building:
		_refresh_repair_window()
	if contract_window and contract_window.visible:
		_refresh_contract_window()

func _update_resource_counters() -> void:
	if not _bound_player or not ("inventory" in _bound_player):
		return
	var inv = _bound_player.inventory
	if not inv:
		return
	
	if wood_label:
		wood_label.text = "🌲 Дерево: %d" % inv.get_item_count("wood")
	if stone_label:
		stone_label.text = "⛰ Камень: %d" % inv.get_item_count("stone")
	if clay_label:
		clay_label.text = "🧱 Глина: %d" % inv.get_item_count("clay")
	if sand_label:
		sand_label.text = "⏳ Песок: %d" % inv.get_item_count("sand")
	if water_label:
		var raw_w: int = inv.get_item_count("water")
		var clean_w: int = inv.get_item_count("clean_water")
		var bot_w: int = inv.get_item_count("bottled_water")
		if clean_w > 0 or bot_w > 0:
			water_label.text = "💧 Вода: %d (Чист:%d Бут:%d)" % [raw_w, clean_w, bot_w]
		else:
			water_label.text = "💧 Вода: %d" % raw_w

# --- Окно Рюкзака ---
func toggle_inventory() -> void:
	if not inventory_window:
		return
	inventory_window.visible = not inventory_window.visible
	if inventory_window.visible:
		if machine_window: machine_window.visible = false
		if sales_window: sales_window.visible = false
		if repair_window: repair_window.visible = false
		_refresh_inventory_window()

func _refresh_inventory_window() -> void:
	if not _bound_player or not ("inventory" in _bound_player):
		return
	var inv = _bound_player.inventory
	if not inv or not items_list:
		return
	
	for child in items_list.get_children():
		child.queue_free()
	
	var has_items: bool = false
	for item_id in inv.items.keys():
		var count: int = inv.items[item_id]
		if count > 0:
			has_items = true
			var data: Dictionary = ItemDB.get_item(item_id)
			var item_name: String = data.get("name", item_id)
			var icon: String = data.get("icon", "📦")
			var weight: float = data.get("weight", 1.0) * count
			
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			
			var tex_rect: TextureRect = TextureRect.new()
			tex_rect.custom_minimum_size = Vector2(24, 24)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			tex_rect.texture = ItemIcons.get_texture(item_id)
			row.add_child(tex_rect)
			
			var lbl_name: Label = Label.new()
			lbl_name.text = item_name
			lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl_name.add_theme_font_size_override("font_size", 14)
			row.add_child(lbl_name)
			
			var lbl_count: Label = Label.new()
			lbl_count.text = "x%d" % count
			lbl_count.custom_minimum_size = Vector2(50, 0)
			lbl_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lbl_count.add_theme_font_size_override("font_size", 14)
			lbl_count.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			row.add_child(lbl_count)
			
			var lbl_w: Label = Label.new()
			lbl_w.text = "(%.1f кг)" % weight
			lbl_w.custom_minimum_size = Vector2(70, 0)
			lbl_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lbl_w.add_theme_font_size_override("font_size", 12)
			lbl_w.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
			row.add_child(lbl_w)
			
			if ItemDB.is_drinkable(item_id):
				var btn_drink: Button = Button.new()
				btn_drink.text = "💧 Пить"
				btn_drink.custom_minimum_size = Vector2(65, 26)
				btn_drink.add_theme_font_size_override("font_size", 11)
				btn_drink.pressed.connect(_on_inventory_drink_pressed.bind(item_id))
				row.add_child(btn_drink)
			
			if ItemDB.is_edible(item_id):
				var btn_eat: Button = Button.new()
				btn_eat.text = "🍎 Есть"
				btn_eat.custom_minimum_size = Vector2(65, 26)
				btn_eat.add_theme_font_size_override("font_size", 11)
				btn_eat.pressed.connect(_on_inventory_eat_pressed.bind(item_id))
				row.add_child(btn_eat)
			
			items_list.add_child(row)
	
	if not has_items:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Рюкзак пуст. Исследуйте мир и добывайте ресурсы!"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items_list.add_child(empty_lbl)
	
	if inv_footer_label:
		inv_footer_label.text = "Вес: %.1f / %.1f кг  |  Занято слотов: %d / %d  (TAB / 5 для закрытия)" % [
			inv.get_total_weight(),
			inv.max_weight,
			inv.get_used_slots(),
			inv.max_slots
		]

func _on_inventory_drink_pressed(item_id: String) -> void:
	if _bound_player and _bound_player.has_method("drink_from_inventory"):
		_bound_player.drink_from_inventory(item_id)
		_refresh_inventory_window()

func _on_inventory_eat_pressed(item_id: String) -> void:
	if _bound_player and _bound_player.has_method("eat_food"):
		_bound_player.eat_food(item_id)
		_refresh_inventory_window()

# --- Окно Производственной Машины (Дробилка / Верстак) ---
func open_machine_window(machine: Node) -> void:
	_current_active_machine = machine
	if not machine_window:
		return
	
	if inventory_window: inventory_window.visible = false
	if sales_window: sales_window.visible = false
	if repair_window: repair_window.visible = false
	
	var m_name: String = machine.get("object_name") if "object_name" in machine else "Машина"
	var m_type: String = machine.get("machine_type") if "machine_type" in machine else ""
	var icon: String = "🔨"
	if m_type == "crusher":
		icon = "⚙️"
	elif m_type == "furnace":
		icon = "🔥"
	machine_title_label.text = "%s %s" % [icon, m_name]
	
	machine_window.visible = true
	_populate_machine_recipes(machine)
	_update_machine_progress_ui()

func close_machine_window() -> void:
	if machine_window:
		machine_window.visible = false
	_current_active_machine = null

func _update_machine_progress_ui() -> void:
	if not _current_active_machine:
		return
	var is_proc: bool = _current_active_machine.get("is_machine_running") if "is_machine_running" in _current_active_machine else false
	if is_proc:
		var prog: float = _current_active_machine.get_progress() if _current_active_machine.has_method("get_progress") else 0.0
		machine_progress_bar.value = prog * 100.0
		var r_name: String = _current_active_machine.active_recipe.get("name", "Производство")
		var left_sec: float = max(0.0, _current_active_machine.process_duration - _current_active_machine.process_timer)
		machine_status_label.text = "⚙️ В процессе: %s (осталось %.1f сек)" % [r_name, left_sec]
	else:
		machine_progress_bar.value = 0.0
		machine_status_label.text = "Готово к запуску. Выберите рецепт ниже:"

func _populate_machine_recipes(machine: Node) -> void:
	if not machine_recipe_list:
		return
	for child in machine_recipe_list.get_children():
		child.queue_free()
	
	var m_type: String = machine.get("machine_type") if "machine_type" in machine else ""
	var recipes: Array[Dictionary] = RecipeDB.get_recipes_for_machine(m_type)
	var inv = _bound_player.get("inventory") if _bound_player else null
	var is_busy: bool = machine.get("is_machine_running") if "is_machine_running" in machine else false
	
	for recipe in recipes:
		var r_id: String = recipe.get("id", "")
		var r_name: String = recipe.get("name", "")
		var duration: float = recipe.get("duration", 6.0)
		var inputs: Dictionary = recipe.get("inputs", {})
		var outputs: Dictionary = recipe.get("outputs", {})
		var can_craft_this: bool = RecipeDB.can_craft(recipe, inv) and not is_busy
		
		var panel: PanelContainer = PanelContainer.new()
		var p_style: StyleBoxFlat = StyleBoxFlat.new()
		p_style.bg_color = Color(0.14, 0.17, 0.22, 0.9)
		p_style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", p_style)
		
		var m_box: MarginContainer = MarginContainer.new()
		m_box.add_theme_constant_override("margin_left", 10)
		m_box.add_theme_constant_override("margin_top", 8)
		m_box.add_theme_constant_override("margin_right", 10)
		m_box.add_theme_constant_override("margin_bottom", 8)
		panel.add_child(m_box)
		
		var h_box: HBoxContainer = HBoxContainer.new()
		h_box.alignment = BoxContainer.ALIGNMENT_BEGIN
		m_box.add_child(h_box)
		
		var v_info: VBoxContainer = VBoxContainer.new()
		v_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h_box.add_child(v_info)
		
		var l_title: Label = Label.new()
		l_title.text = r_name
		l_title.add_theme_font_size_override("font_size", 14)
		l_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		v_info.add_child(l_title)
		
		# Описание ресурсов
		var in_parts: Array[String] = []
		for item_id in inputs.keys():
			var needed: int = inputs[item_id]
			var avail: int = inv.get_item_count(item_id) if inv else 0
			var item_icon: String = ItemDB.get_item_icon(item_id)
			var item_name: String = ItemDB.get_item_name(item_id)
			in_parts.append("%s %s: %d/%d" % [item_icon, item_name, avail, needed])
		
		var out_parts: Array[String] = []
		for item_id in outputs.keys():
			var out_count: int = outputs[item_id]
			var item_icon: String = ItemDB.get_item_icon(item_id)
			var item_name: String = ItemDB.get_item_name(item_id)
			out_parts.append("+%d %s %s" % [out_count, item_icon, item_name])
		if out_parts.is_empty() and r_id.begins_with("sharpen_"):
			out_parts.append("✨ Заточка до 100%")
		
		var l_details: Label = Label.new()
		l_details.text = "Сырьё: %s  |  Выход: %s (⏱ %.0f сек)" % [
			", ".join(in_parts),
			", ".join(out_parts),
			duration
		]
		l_details.add_theme_font_size_override("font_size", 11)
		l_details.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		v_info.add_child(l_details)
		
		# Кнопка запуска
		var btn_craft: Button = Button.new()
		btn_craft.text = "▶ Запуск"
		btn_craft.custom_minimum_size = Vector2(85, 34)
		btn_craft.disabled = not can_craft_this
		btn_craft.pressed.connect(_on_craft_button_pressed.bind(machine, r_id))
		h_box.add_child(btn_craft)
		
		machine_recipe_list.add_child(panel)

func _on_craft_button_pressed(machine: Node, recipe_id: String) -> void:
	if machine and machine.has_method("start_recipe"):
		var ok: bool = machine.start_recipe(recipe_id, _bound_player)
		if ok:
			_populate_machine_recipes(machine)

# --- Окно Станции Отправки (Продажа) ---
func open_sales_window(station: Node) -> void:
	_current_active_station = station
	if not sales_window:
		return
	if inventory_window: inventory_window.visible = false
	if machine_window: machine_window.visible = false
	if repair_window: repair_window.visible = false
	
	sales_window.visible = true
	_refresh_sales_window()

func close_sales_window() -> void:
	if sales_window:
		sales_window.visible = false
	_current_active_station = null

func _refresh_sales_window() -> void:
	if not sales_goods_list or not _bound_player:
		return
	for child in sales_goods_list.get_children():
		child.queue_free()
	
	var inv = _bound_player.get("inventory") if _bound_player else null
	if not inv:
		return
	
	var any_sellable: bool = false
	for item_id in inv.items.keys():
		var count: int = inv.items[item_id]
		var price: int = ItemDB.get_sell_price(item_id)
		if count > 0 and price > 0:
			any_sellable = true
			var item_name: String = ItemDB.get_item_name(item_id)
			var item_icon: String = ItemDB.get_item_icon(item_id)
			
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			
			var l_title: Label = Label.new()
			l_title.text = "%s %s" % [item_icon, item_name]
			l_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l_title.add_theme_font_size_override("font_size", 14)
			row.add_child(l_title)
			
			var l_info: Label = Label.new()
			l_info.text = "x%d  (цена: %d кр.)" % [count, price]
			l_info.custom_minimum_size = Vector2(170, 0)
			l_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l_info.add_theme_font_size_override("font_size", 13)
			l_info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			row.add_child(l_info)
			
			var btn_sell_1: Button = Button.new()
			btn_sell_1.text = "+1 шт"
			btn_sell_1.custom_minimum_size = Vector2(80, 34)
			btn_sell_1.pressed.connect(_on_sell_goods_pressed.bind(item_id, 1))
			row.add_child(btn_sell_1)
			
			var btn_sell_all: Button = Button.new()
			btn_sell_all.text = "Все (x%d)" % count
			btn_sell_all.custom_minimum_size = Vector2(110, 34)
			btn_sell_all.pressed.connect(_on_sell_goods_pressed.bind(item_id, count))
			row.add_child(btn_sell_all)
			
			sales_goods_list.add_child(row)
	
	if not any_sellable:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "В рюкзаке нет товаров для продажи.\nПроизведите кирпичи или брикеты на верстаке!"
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sales_goods_list.add_child(empty_lbl)
	_polish(sales_window)

func _on_sell_goods_pressed(item_id: String, amount: int) -> void:
	if _current_active_station and _current_active_station.has_method("sell_goods"):
		_current_active_station.sell_goods({item_id: amount}, _bound_player)
		_refresh_sales_window()

func _on_quick_sell_pressed() -> void:
	if not _current_active_station or not _bound_player:
		return
	var inv = _bound_player.get("inventory") if _bound_player else null
	if not inv:
		return
	
	var to_sell: Dictionary = {}
	for product_id in ["poor_brick", "mortar", "fuel_briquette", "fired_brick", "glass", "iron_ingot", "clean_water", "bottled_water",
			"coal_powder", "glass_bottle", "clay_pot", "glassware_set",
			"carrot", "potato", "wheat", "bread",
			"sunflower_seeds", "onion", "cabbage", "tomato", "pepper", "bean", "herbs", "corn", "pumpkin",
			"apple", "pear", "cherry", "apricot", "dried_apricot", "apricot_compote", "apricot_pie",
			"red_berry", "blue_berry", "blackberry", "sea_buckthorn"]:
		var c: int = inv.get_item_count(product_id)
		if c > 0:
			to_sell[product_id] = c
	
	if to_sell.is_empty():
		show_notification("ℹ️ В рюкзаке нет готовой продукции (материалы, вода, выращенные овощи, хлеб) для отправки.")
		return
	
	_current_active_station.sell_goods(to_sell, _bound_player)
	_refresh_sales_window()

# --- Окно Восстановления Зданий ---
func open_repair_window(building: Node) -> void:
	_current_active_building = building
	if not repair_window:
		return
	if inventory_window: inventory_window.visible = false
	if machine_window: machine_window.visible = false
	if sales_window: sales_window.visible = false
	
	repair_window.visible = true
	_refresh_repair_window()

func close_repair_window() -> void:
	if repair_window:
		repair_window.visible = false
	_current_active_building = null

func _refresh_repair_window() -> void:
	if not _current_active_building or not repair_window:
		return
	
	var b_title: String = _current_active_building.get("building_title") if "building_title" in _current_active_building else "Здание"
	repair_title_label.text = "🏗️ " + b_title
	
	var curr_stage: int = _current_active_building.get("current_stage") if "current_stage" in _current_active_building else 0
	var max_st: int = _current_active_building.get("max_stage") if "max_stage" in _current_active_building else 3
	var cur_data: Dictionary = _current_active_building.get_current_stage_data() if _current_active_building.has_method("get_current_stage_data") else {}
	var stage_name: String = cur_data.get("name", "Уровень %d" % curr_stage)
	
	repair_status_label.text = "Текущее состояние: %s (Уровень %d/%d)" % [stage_name, curr_stage, max_st]
	repair_progress_bar.max_value = max_st
	repair_progress_bar.value = curr_stage
	
	var perks_text: String = cur_data.get("perks", "Нет эффектов")
	repair_perks_label.text = "Текущие возможности: " + perks_text
	
	# Кнопка сна (если это дом и уровень >= 2)
	var can_sleep_now: bool = _current_active_building.has_method("can_sleep") and _current_active_building.can_sleep()
	repair_sleep_button.visible = can_sleep_now
	
	if repair_storage_button:
		repair_storage_button.visible = _current_active_building.has_method("is_storage_ready") and _current_active_building.is_storage_ready()
	# Очистка списка требований
	for ch in repair_requirements_list.get_children():
		ch.queue_free()
	
	if curr_stage >= max_st:
		repair_next_title_label.text = "🎉 Здание полностью отремонтировано и модернизировано!"
		repair_next_title_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		repair_upgrade_button.visible = false
		return
	
	repair_upgrade_button.visible = true
	var next_data: Dictionary = _current_active_building.get_next_stage_data() if _current_active_building.has_method("get_next_stage_data") else {}
	var next_name: String = next_data.get("name", "Уровень %d" % (curr_stage + 1))
	var next_desc: String = next_data.get("description", "")
	var next_perk: String = next_data.get("perks", "")
	
	repair_next_title_label.text = "Следующий этап: %s (Уровень %d)\n%s\nЭффект: %s" % [next_name, curr_stage + 1, next_desc, next_perk]
	repair_next_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	
	var inv = _bound_player.get("inventory") if _bound_player else null
	var cost_cr: int = next_data.get("cost_credits", 0)
	var mats: Dictionary = next_data.get("cost_materials", {})
	var in_building_cr: int = int(_current_active_building.get("delivered_credits")) if "delivered_credits" in _current_active_building else 0
	
	# Кредиты в требованиях
	if cost_cr > 0:
		var remaining_cr: int = maxi(0, cost_cr - in_building_cr)
		var player_cr: int = inv.get("credits") if (inv and "credits" in inv) else 0
		var row_cr: HBoxContainer = HBoxContainer.new()
		var l_cr: Label = Label.new()
		if remaining_cr == 0:
			l_cr.text = "✓ 💰 Кредиты: Собрано (%d / %d)" % [in_building_cr, cost_cr]
			l_cr.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		else:
			l_cr.text = "💰 Кредиты: Требуется %d (внесено %d / %d) [В кошельке: %d]" % [remaining_cr, in_building_cr, cost_cr, player_cr]
			if player_cr >= remaining_cr:
				l_cr.add_theme_color_override("font_color", Color(0.5, 0.95, 0.85))
			elif player_cr > 0:
				l_cr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				l_cr.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		l_cr.add_theme_font_size_override("font_size", 13)
		row_cr.add_child(l_cr)
		repair_requirements_list.add_child(row_cr)
	
	# Материалы в требованиях (динамический остаток «Требуется»)
	for mat_id in mats.keys():
		var needed: int = mats[mat_id]
		var in_building: int = int(_current_active_building.delivered.get(mat_id, 0)) if "delivered" in _current_active_building else 0
		var remaining: int = maxi(0, needed - in_building)
		var avail: int = inv.get_item_count(mat_id) if inv else 0
		var mat_name: String = ItemDB.get_item_name(mat_id)
		var mat_icon: String = ItemDB.get_item_icon(mat_id)
		
		var row_mat: HBoxContainer = HBoxContainer.new()
		var l_mat: Label = Label.new()
		if remaining == 0:
			l_mat.text = "✓ %s %s: Собрано (%d / %d)" % [mat_icon, mat_name, in_building, needed]
			l_mat.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		else:
			l_mat.text = "%s %s: Требуется %d (внесено %d / %d) [В рюкзаке: %d]" % [mat_icon, mat_name, remaining, in_building, needed, avail]
			if avail >= remaining:
				l_mat.add_theme_color_override("font_color", Color(0.5, 0.95, 0.85))
			elif avail > 0:
				l_mat.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				l_mat.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		l_mat.add_theme_font_size_override("font_size", 13)
		row_mat.add_child(l_mat)
		repair_requirements_list.add_child(row_mat)
	
	# Внести материалы: переносит в здание всё, что есть в рюкзаке; когда
	# комплект собран — стадия применяется автоматически.
	repair_upgrade_button.disabled = false
	repair_upgrade_button.text = "🔨 Внести материалы (Уровень %d)" % (curr_stage + 1)
	repair_upgrade_button.tooltip_text = "Переносит в здание всё, что есть в рюкзаке. Когда весь комплект собран — стадия восстановления применяется."
	_polish(repair_window)

func _on_upgrade_building_pressed() -> void:
	if not _current_active_building or not _bound_player:
		return
	if _current_active_building.has_method("upgrade"):
		var ok: bool = _current_active_building.upgrade(_bound_player)
		if ok:
			_refresh_repair_window()

func _on_building_sleep_pressed() -> void:
	if not _current_active_building or not _bound_player:
		return
	# Диалог с ползунком: сколько спать. Персонаж исчезает из мира на время сна.
	var dialog: Control = preload("res://scripts/ui/sleep_dialog.gd").new()
	dialog.setup(_current_active_building, _bound_player)
	dialog.confirmed.connect(_on_sleep_confirmed)
	add_child(dialog)

func _on_sleep_confirmed(hours: float) -> void:
	var building: Node = _current_active_building
	if building == null or not _bound_player:
		return
	if building.has_method("sleep"):
		close_repair_window()
		building.sleep(_bound_player, hours)

# --- Взаимодействия и уведомления ---
func _on_focused_interactable_changed(interactable: Node) -> void:
	if interactable and interactable.has_method("get_prompt"):
		prompt_label.text = interactable.get_prompt()
		prompt_container.visible = true
	else:
		prompt_container.visible = false

func show_notification(text: String, duration: float = 3.5) -> void:
	if not notification_label:
		notification_label = get_node_or_null("NotificationContainer/MarginContainer/NotificationLabel")
	if not notification_container:
		notification_container = get_node_or_null("NotificationContainer")
	if not notification_timer:
		notification_timer = get_node_or_null("NotificationTimer")

	if notification_label:
		notification_label.text = text
	if notification_container:
		# Панели рюкзака/станка/заказов добавляются в HUD последними и рисуются
		# поверх тоста (уровни пассивных навыков растут как раз при работе с ними).
		notification_container.z_index = NOTIFICATION_Z_INDEX
		notification_container.visible = true
	if notification_timer:
		notification_timer.start(duration)

func _on_notification_timeout() -> void:
	notification_container.visible = false

## Вспышка молнии на весь экран (гроза): белый флэш на 0.18 с. Вызывает
## SeasonManager при каждой молнии — гроза видна, даже если ударила в поле.
func flash_lightning() -> void:
	var flash := ColorRect.new()
	flash.name = "LightningFlash"
	flash.color = Color(0.95, 0.97, 1.0, 0.55)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)

func set_credits(amount: int) -> void:
	if money_label:
		money_label.text = "💰 Кредиты: %d" % amount

# --- Окно Контрактов и NPC ---
func open_contract_window(source_node: Node = null) -> void:
	if is_instance_valid(_current_active_npc) and _current_active_npc != source_node and _current_active_npc.has_method("end_dialogue"):
		_current_active_npc.end_dialogue()
	_current_active_npc = source_node
	if not contract_window:
		return
	if inventory_window: inventory_window.visible = false
	if machine_window: machine_window.visible = false
	if sales_window: sales_window.visible = false
	if repair_window: repair_window.visible = false
	
	contract_window.visible = true
	_refresh_contract_window()

func close_contract_window() -> void:
	if is_instance_valid(_current_active_npc) and _current_active_npc.has_method("end_dialogue"):
		_current_active_npc.end_dialogue()
	if contract_window:
		contract_window.visible = false
	_current_active_npc = null

func _refresh_contract_window() -> void:
	if not contract_window or not contracts_list:
		return
	
	if _current_active_npc and "greeting_text" in _current_active_npc:
		var n_name: String = _current_active_npc.npc_name if "npc_name" in _current_active_npc else "Степан (Снабженец)"
		contract_title_label.text = "👨‍🌾 " + n_name
		contract_dialogue_label.text = ContractDB.get_story_greeting() if _current_active_npc.get("is_trader") == true else _current_active_npc.greeting_text
	else:
		contract_title_label.text = "📜 Доска заказов и контрактов"
		contract_dialogue_label.text = "Срочные поставки стройматериалов и снабжения для окрестных жителей. Оплата производится сразу при сдаче партии!"
	
	for child in contracts_list.get_children():
		contracts_list.remove_child(child)
		child.queue_free()
	
	var inv = _bound_player.get("inventory") if _bound_player else null
	var all_contracts = ContractDB.get_all_contracts()
	var shown: int = 0

	for contract in all_contracts:
		var c_id: String = contract.get("id", "")
		# Выполненные заказы снимаются с доски: не занимают место и не сбивают с толку.
		if ContractDB.is_completed(c_id):
			continue
		if not ContractDB.is_unlocked(contract):
			contracts_list.add_child(_make_locked_contract_card(contract))
			shown += 1
			continue

		var can_do: bool = ContractDB.can_fulfill(contract, inv)
		var card: PanelContainer = PanelContainer.new()
		var card_style: StyleBoxFlat = StyleBoxFlat.new()
		card_style.bg_color = Color(0.14, 0.17, 0.22, 0.95)
		card_style.border_color = Color(0.3, 0.75, 0.45, 1.0) if can_do else Color(0.28, 0.45, 0.65, 0.8)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)
		
		var m_box: MarginContainer = MarginContainer.new()
		m_box.add_theme_constant_override("margin_left", 12)
		m_box.add_theme_constant_override("margin_top", 10)
		m_box.add_theme_constant_override("margin_right", 12)
		m_box.add_theme_constant_override("margin_bottom", 10)
		card.add_child(m_box)
		
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		m_box.add_child(vbox)
		
		# Заголовок и награда
		var h_title: HBoxContainer = HBoxContainer.new()
		var lbl_title: Label = Label.new()
		lbl_title.text = contract.get("title", "Заказ")
		lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_title.add_theme_font_size_override("font_size", 14)
		lbl_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		h_title.add_child(lbl_title)
		
		var lbl_reward: Label = Label.new()
		var reward_txt: String = "💰 +%d кр." % contract.get("reward_credits", 0)
		var reward_items: Dictionary = contract.get("reward_items", {})
		if not reward_items.is_empty():
			var gift_parts: Array[String] = []
			for gift_id in reward_items.keys():
				gift_parts.append("%s ×%d" % [ItemDB.get_item_name(str(gift_id)), int(reward_items[gift_id])])
			reward_txt += " 🎁 " + ", ".join(gift_parts)
		lbl_reward.text = reward_txt
		lbl_reward.add_theme_font_size_override("font_size", 13)
		lbl_reward.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		h_title.add_child(lbl_reward)
		vbox.add_child(h_title)
		
		# Клиент и описание
		var lbl_desc: Label = Label.new()
		lbl_desc.text = "Заказчик: %s — %s" % [contract.get("client", "Округа"), contract.get("description", "")]
		lbl_desc.add_theme_font_size_override("font_size", 11)
		lbl_desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(lbl_desc)
		
		# Требования к ресурсам
		var reqs: Dictionary = contract.get("requirements", {})
		var h_reqs: HFlowContainer = HFlowContainer.new()
		h_reqs.add_theme_constant_override("h_separation", 14)
		h_reqs.add_theme_constant_override("v_separation", 4)
		for item_id in reqs.keys():
			var needed: int = reqs[item_id]
			var count: int = inv.get_item_count(item_id) if inv else 0
			var icon: String = ItemDB.get_item_icon(item_id)
			var item_name: String = ItemDB.get_item_name(item_id)
			
			var lbl_item: Label = Label.new()
			lbl_item.text = "%s %s: %d/%d" % [icon, item_name, count, needed]
			lbl_item.add_theme_font_size_override("font_size", 11)
			if count >= needed:
				lbl_item.add_theme_color_override("font_color", Color(0.4, 0.95, 0.4))
			else:
				lbl_item.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4))
			h_reqs.add_child(lbl_item)
		vbox.add_child(h_reqs)
		
		# Кнопка сдачи
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(0, 30)
		if can_do:
			var gift_txt: String = " + 🎁" if not contract.get("reward_items", {}).is_empty() else ""
			btn.text = "Сдать партию материалов (💰 +%d кр.%s)" % [contract.get("reward_credits", 0), gift_txt]
			btn.pressed.connect(_on_fulfill_contract_pressed.bind(c_id))
		else:
			btn.text = "Недостаточно товаров в рюкзаке"
			btn.disabled = true
		vbox.add_child(btn)
		
		contracts_list.add_child(card)
		shown += 1

	# Все доступные заказы сданы — на доске только будущие волны.
	if shown == 0:
		var done_lbl: Label = Label.new()
		done_lbl.text = "📭 Все заказы выполнены. Округа готовит новые поставки — загляните позже!"
		done_lbl.add_theme_font_size_override("font_size", 13)
		done_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
		done_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contracts_list.add_child(done_lbl)
	_polish(contract_window)

## Карточка заказа следующей волны: заказчик и условие открытия, без требований.
func _make_locked_contract_card(contract: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 0.8)
	style.border_color = Color(0.3, 0.32, 0.36, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)
	var lbl := Label.new()
	var need: int = int(contract.get("unlock_after", 0))
	lbl.text = "🔒 %s — %s\nОткроется после %d выполненных заказов (сдано %d)." % [
		contract.get("title", "Заказ"), contract.get("client", "Округа"), need, ContractDB.get_completed_count()]
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(lbl)
	return card

func _on_fulfill_contract_pressed(contract_id: String) -> void:
	if not _bound_player:
		return
	var ok: bool = ContractDB.fulfill_contract(contract_id, _bound_player)
	if ok:
		_refresh_contract_window()

# --- Выбор специализации персонажа (Этап 12) ---
func _on_character_class_changed(class_id: String, c_name: String) -> void:
	if class_button:
		var c_icon: String = CharacterClassDB.get_class_icon(class_id)
		class_button.text = "%s Класс: %s [C]" % [c_icon, c_name]

func toggle_class_window() -> void:
	if not class_window:
		return
	class_window.visible = not class_window.visible
	if class_window.visible:
		_populate_class_cards()

func close_class_window() -> void:
	if class_window:
		class_window.visible = false

func _populate_class_cards() -> void:
	if not classes_list:
		return
	for c in classes_list.get_children():
		c.queue_free()
	
	var all_classes = CharacterClassDB.get_all_classes()
	var current_class: String = _bound_player.character_class if (_bound_player and "character_class" in _bound_player) else "miner"
	
	for c_data in all_classes:
		var card: PanelContainer = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		var is_selected: bool = (c_data.id == current_class)
		card_style.bg_color = Color(0.18, 0.22, 0.28, 0.95) if is_selected else Color(0.12, 0.14, 0.18, 0.9)
		card_style.border_color = Color(1.0, 0.85, 0.3) if is_selected else Color(0.35, 0.4, 0.45, 0.5)
		card_style.set_border_width_all(2 if is_selected else 1)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)
		
		var m: MarginContainer = MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_top", 10)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_bottom", 10)
		card.add_child(m)
		
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		m.add_child(vbox)
		
		var title: Label = Label.new()
		title.text = "%s %s — %s" % [c_data.icon, c_data.name, c_data.title]
		title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45) if is_selected else Color(0.9, 0.9, 0.9))
		title.add_theme_font_size_override("font_size", 14)
		vbox.add_child(title)
		
		var desc: Label = Label.new()
		desc.text = c_data.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		desc.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc)
		
		var perks_label: Label = Label.new()
		var perks_text: String = ""
		for p in c_data.perks:
			perks_text += "• " + p + "\n"
		perks_label.text = perks_text.strip_edges()
		perks_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.6))
		perks_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(perks_label)
		
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(0, 28)
		if is_selected:
			btn.text = "✓ Текущая специализация"
			btn.disabled = true
		else:
			btn.text = "Выбрать: %s %s" % [c_data.icon, c_data.name]
			var sel_id = c_data.id
			btn.pressed.connect(func():
				if _bound_player and _bound_player.has_method("set_character_class"):
					_bound_player.set_character_class(sel_id)
					_populate_class_cards()
			)
		vbox.add_child(btn)
		
		classes_list.add_child(card)
	_polish(class_window)

# --- Прокачка навыков персонажа (Learn by Doing) ---
func _update_skills_button() -> void:
	if not skills_button:
		return
	var overall_lvl: int = 11
	if _bound_player and "skills" in _bound_player and _bound_player.skills:
		if _bound_player.skills.has_method("get_overall_level"):
			overall_lvl = _bound_player.skills.get_overall_level()
	skills_button.text = "⭐ [K] Навыки (Ур. %d)" % overall_lvl

## Заметный баннер повышения навыка: отдельный долгоживущий (6 с), чтобы его
## не затирали сообщения добычи (кирка по руде, сбор урожая). Дублирует и
## усиливает notify из PlayerSkills.add_xp.
func _on_skill_leveled_up(skill_id: String, new_level: int, perk_description: String) -> void:
	var meta: Dictionary = SkillDB.get_skill_data(skill_id)
	var s_name: String = str(meta.get("name", skill_id))
	var s_icon: String = str(meta.get("icon", "⭐"))
	var first_perk: String = perk_description.split("\n")[0] if perk_description != "" else ""
	var text: String = "🎉 Навык повышен! %s %s — уровень %d. %s [K — навыки]" % [s_icon, s_name, new_level, first_perk]
	show_notification(text, 6.0)
	AudioManager.play("ui_click")
	_update_skills_button()

func toggle_skills_window() -> void:
	if not skills_window:
		return
	AudioManager.play("ui_click")
	skills_window.visible = not skills_window.visible
	if skills_window.visible:
		if inventory_window and inventory_window.visible:
			toggle_inventory()
		if class_window and class_window.visible:
			close_class_window()
		_populate_skills_cards()

func close_skills_window() -> void:
	if skills_window and skills_window.visible:
		AudioManager.play("ui_click")
		skills_window.visible = false

func _populate_skills_cards() -> void:
	if not skills_list:
		return
	for c in skills_list.get_children():
		c.queue_free()
	
	var p_skills: Node = null
	if _bound_player and "skills" in _bound_player and _bound_player.skills:
		p_skills = _bound_player.skills
	
	var overall_lvl: int = p_skills.get_overall_level() if (p_skills and p_skills.has_method("get_overall_level")) else 11
	var overall_title: String = p_skills.get_overall_title() if (p_skills and p_skills.has_method("get_overall_title")) else SkillDB.get_overall_title(overall_lvl)
	
	if skills_overall_level_label:
		skills_overall_level_label.text = "⭐ Общий уровень: %d" % overall_lvl
	if skills_overall_title_label:
		skills_overall_title_label.text = "«%s»" % overall_title
	if skills_button:
		skills_button.text = "⭐ [K] Навыки (Ур. %d)" % overall_lvl
	
	for sid in SkillDB.SKILL_IDS:
		var s_meta: Dictionary = SkillDB.get_skill_data(sid)
		var s_name: String = s_meta.get("name", sid)
		var s_icon: String = s_meta.get("icon", "⭐")
		var s_color: Color = s_meta.get("color", Color(0.85, 0.88, 0.92))
		var s_desc: String = s_meta.get("description", "")
		var s_actions: String = s_meta.get("actions", "")
		
		var lvl: int = p_skills.get_level(sid) if (p_skills and p_skills.has_method("get_level")) else 1
		var xp: int = p_skills.get_xp(sid) if (p_skills and p_skills.has_method("get_xp")) else 0
		var is_max: bool = (lvl >= SkillDB.MAX_LEVEL)
		var next_base: int = SkillDB.get_xp_for_level(mini(lvl + 1, SkillDB.MAX_LEVEL))
		var progress: float = (p_skills.get_progress(sid) if (p_skills and p_skills.has_method("get_progress")) else 0.0) * 100.0
		
		var card: PanelContainer = PanelContainer.new()
		var card_style: StyleBoxFlat = StyleBoxFlat.new()
		if is_max:
			card_style.bg_color = Color(0.16, 0.22, 0.18, 0.95)
			card_style.border_color = Color(1.0, 0.85, 0.3, 1.0)
			card_style.set_border_width_all(2)
		else:
			card_style.bg_color = Color(0.12, 0.14, 0.18, 0.9)
			card_style.border_color = Color(0.3, 0.36, 0.44, 0.6)
			card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)
		
		var m: MarginContainer = MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_top", 10)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_bottom", 10)
		card.add_child(m)
		
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		m.add_child(vbox)
		
		# Заголовок карточки: Иконка + Название слева, Уровень справа
		var header_hbox: HBoxContainer = HBoxContainer.new()
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(header_hbox)
		
		var title_label: Label = Label.new()
		title_label.text = "%s %s" % [s_icon, s_name]
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.add_theme_font_size_override("font_size", 14)
		title_label.add_theme_color_override("font_color", s_color)
		header_hbox.add_child(title_label)
		
		var lvl_badge: Label = Label.new()
		lvl_badge.add_theme_font_size_override("font_size", 13)
		if is_max:
			lvl_badge.text = "🏆 МАКС. УР. %d" % lvl
			lvl_badge.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		else:
			lvl_badge.text = "Ур. %d / %d" % [lvl, SkillDB.MAX_LEVEL]
			lvl_badge.add_theme_color_override("font_color", Color(0.5, 0.95, 0.7))
		header_hbox.add_child(lvl_badge)
		
		# Описание навыка
		if not s_desc.is_empty():
			var desc_label: Label = Label.new()
			desc_label.text = s_desc
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_label.add_theme_font_size_override("font_size", 11)
			desc_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
			vbox.add_child(desc_label)
		
		# Полоса опыта
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		bar.value = 100.0 if is_max else progress
		
		var bar_label: Label = Label.new()
		bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar_label.add_theme_font_size_override("font_size", 10)
		if is_max:
			bar_label.text = "МАКСИМАЛЬНЫЙ УРОВЕНЬ (%d XP)" % xp
			bar_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		else:
			bar_label.text = "%d / %d XP (до след. %d XP)" % [xp, next_base, maxi(0, next_base - xp)]
			bar_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		bar.add_child(bar_label)
		vbox.add_child(bar)
		
		# Список активных перков
		var perks_summary: String = SkillDB.get_perks_summary(sid, lvl)
		var perks_label: Label = Label.new()
		perks_label.text = perks_summary
		perks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		perks_label.add_theme_font_size_override("font_size", 11)
		perks_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.65))
		vbox.add_child(perks_label)
		
		# Подсказка как качать
		if not s_actions.is_empty():
			var train_label: Label = Label.new()
			train_label.text = "Практика: %s" % s_actions
			train_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			train_label.add_theme_font_size_override("font_size", 10)
			train_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
			vbox.add_child(train_label)
		
		skills_list.add_child(card)
	
	_polish(skills_window)

# --- Меню паузы и звука (Этап 13) ---
func toggle_pause_menu() -> void:
	if not pause_window:
		return
	AudioManager.play("ui_click")
	pause_window.visible = not pause_window.visible
	get_tree().paused = pause_window.visible
	if pause_window.visible:
		_refresh_pause_menu()

func close_pause_menu() -> void:
	if pause_window and pause_window.visible:
		AudioManager.play("ui_click")
		pause_window.visible = false
		get_tree().paused = false

func _refresh_pause_menu() -> void:
	var world = _get_world()
	if not world:
		return
	var v_data: Dictionary = VictoryManager.evaluate_base_restored(world)
	if base_progress_label:
		base_progress_label.text = "🏆 Восстановление базы: %d/%d вех (%d%%)" % [
			v_data.get("completed_count", 0), v_data.get("total_count", 0), v_data.get("progress_pct", 0)
		]
	var c_data: Dictionary = CookingProgress.evaluate(world)
	if ch2_progress_label:
		ch2_progress_label.text = "🔥 Первый дым: %d/%d вех (%d%%)" % [
			c_data.get("completed_count", 0), c_data.get("total_count", 0), c_data.get("progress_pct", 0)
		]
	
	if pause_tasks_list:
		for c in pause_tasks_list.get_children():
			c.queue_free()
		for t in v_data.get("tasks", []):
			pause_tasks_list.add_child(_make_task_label(t))
		# Вехи Главы 2 идут после Главы 1 под отдельным заголовком.
		var ch2_header: Label = _make_task_label({"title": "Глава 2 «Первый дым»", "icon": "", "done": false})
		ch2_header.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45))
		ch2_header.text = "— Глава 2 «Первый дым» —"
		pause_tasks_list.add_child(ch2_header)
		for t in c_data.get("tasks", []):
			pause_tasks_list.add_child(_make_task_label(t))
	
	if sfx_slider and AudioManager.instance:
		sfx_slider.value = AudioManager.instance.sfx_volume
	if amb_slider and AudioManager.instance:
		amb_slider.value = AudioManager.instance.ambient_volume
	_polish(pause_window)

func _make_task_label(task: Dictionary) -> Label:
	var l: Label = Label.new()
	var done: bool = bool(task.get("done", false))
	var icon: String = str(task.get("icon", ""))
	l.text = "%s %s: %s" % [icon, str(task.get("title", "")), "[ГОТОВО]" if done else "[в процессе]"]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.4, 0.9, 0.55) if done else Color(0.75, 0.8, 0.85))
	return l

func _on_pause_save_pressed() -> void:
	AudioManager.play("ui_click")
	if _bound_player and _bound_player.has_method("quick_save"):
		_bound_player.quick_save()
	show_notification("💾 Игра успешно сохранена [F5]!")

func _on_pause_load_pressed() -> void:
	AudioManager.play("ui_click")
	if _bound_player and _bound_player.has_method("quick_load"):
		_bound_player.quick_load()
	close_pause_menu()
	show_notification("📂 Сохранение успешно загружено [F9]!")

func _on_sfx_slider_changed(val: float) -> void:
	if AudioManager.instance:
		AudioManager.instance.set_sfx_vol(val)
	AudioManager.play("ui_click")

func _on_amb_slider_changed(val: float) -> void:
	if AudioManager.instance:
		AudioManager.instance.set_ambient_vol(val)

# --- Торжественный финал Первой главы «Base Restored» (Этап 13) ---
func check_and_show_victory_if_earned() -> bool:
	if _victory_shown:
		return false
	var world = _get_world()
	if not world:
		return false
	var v_data: Dictionary = VictoryManager.evaluate_base_restored(world)
	if v_data.get("is_victory", false):
		_victory_shown = true
		show_victory_window(v_data)
		return true
	return false

func show_victory_window(v_data: Dictionary) -> void:
	if not victory_window:
		return
	close_pause_menu()
	victory_window.visible = true
	get_tree().paused = true
	AudioManager.play("victory_fanfare")
	
	if victory_stats_label:
		var days: int = 1
		var day_cycle = _get_day_cycle()
		if day_cycle and "current_day" in day_cycle:
			days = day_cycle.current_day
		var creds: int = _bound_player.inventory.credits if (_bound_player and _bound_player.inventory) else 0
		var c_count: int = ContractDB.get_completed_count()
		victory_stats_label.text = "Прожито суток: %d | Накоплено кредитов: %d | Сдано заказов: %d" % [days, creds, c_count]

func close_victory_window() -> void:
	if victory_window:
		AudioManager.play("ui_click")
		victory_window.visible = false
		get_tree().paused = false
