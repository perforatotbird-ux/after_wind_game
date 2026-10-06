extends CanvasLayer

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")

@onready var prompt_container: PanelContainer = $PromptContainer
@onready var prompt_label: Label = $PromptContainer/MarginContainer/PromptLabel
@onready var notification_container: PanelContainer = $NotificationContainer
@onready var notification_label: Label = $NotificationContainer/MarginContainer/NotificationLabel
@onready var notification_timer: Timer = $NotificationTimer

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
@onready var money_label: Label = $TopRightUI/Panel/Margin/VBox/MoneyLabel

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
var _current_active_building: Node = null
var _current_active_npc: Node = null

var style_slot_active: StyleBoxFlat = null
var style_slot_normal: StyleBoxFlat = null

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
	if contract_close_button:
		contract_close_button.pressed.connect(close_contract_window)
	
	_init_styles()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if contract_window and contract_window.visible:
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
	if player.has_signal("energy_changed"):
		player.energy_changed.connect(_on_energy_changed)
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
	
	if "inventory" in player and player.inventory:
		var inv = player.inventory
		inv.inventory_updated.connect(_on_inventory_updated)
		inv.tool_changed.connect(_on_tool_changed)
		if inv.has_signal("credits_changed"):
			inv.credits_changed.connect(set_credits)
		_highlight_slot(0)
		_update_resource_counters()
		set_credits(inv.credits if "credits" in inv else 0)

func _on_slot_button_pressed(index: int) -> void:
	if index == 4:
		toggle_inventory()
	elif _bound_player and _bound_player.has_method("equip_slot"):
		_bound_player.equip_slot(index)

func _on_tool_changed(tool_id: String, _tool_name: String) -> void:
	var slot_map: Dictionary = {
		"axe": 0,
		"pickaxe": 1,
		"shovel": 2,
		"bucket": 3,
		"backpack": 4
	}
	var idx: int = slot_map.get(tool_id, 0)
	_highlight_slot(idx)

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

func _on_energy_changed(curr: float, max_v: float) -> void:
	if energy_bar:
		energy_bar.value = (curr / max_v) * 100.0
	if energy_label:
		var pct: int = int((curr / max_v) * 100.0)
		if pct <= 0:
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
		var weather_mgr: Node = get_tree().root.find_child("WeatherManager", true, false)
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
		
		var final_temp: int = max(4, base_temp + temp_offset)
		weather_label.text = "%s %s (+%d°C)" % [icon, w_name, final_temp]

func update_weather_display(_new_type: int = 0, w_name: String = "", icon: String = "") -> void:
	if weather_label:
		var day_cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
		var phase: String = day_cycle.get_current_phase() if (day_cycle and day_cycle.has_method("get_current_phase")) else "День"
		var base_temp: int = 22
		match phase:
			"Утро": base_temp = 16
			"День": base_temp = 23
			"Вечер": base_temp = 18
			"Ночь": base_temp = 11
		
		var weather_mgr: Node = get_tree().root.find_child("WeatherManager", true, false)
		var temp_offset: int = weather_mgr.get_temperature_offset() if (weather_mgr and weather_mgr.has_method("get_temperature_offset")) else 0
		var final_temp: int = max(4, base_temp + temp_offset)
		weather_label.text = "%s %s (+%d°C)" % [icon, w_name, final_temp]

func _on_inventory_updated() -> void:
	_update_resource_counters()
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
			
			var lbl_name: Label = Label.new()
			lbl_name.text = "%s %s" % [icon, item_name]
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
			
			var l_title: Label = Label.new()
			l_title.text = "%s %s" % [item_icon, item_name]
			l_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l_title.add_theme_font_size_override("font_size", 14)
			row.add_child(l_title)
			
			var l_info: Label = Label.new()
			l_info.text = "x%d  (цена: %d кр.)" % [count, price]
			l_info.custom_minimum_size = Vector2(120, 0)
			l_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l_info.add_theme_font_size_override("font_size", 13)
			l_info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			row.add_child(l_info)
			
			var btn_sell_1: Button = Button.new()
			btn_sell_1.text = "+1 шт"
			btn_sell_1.custom_minimum_size = Vector2(55, 28)
			btn_sell_1.pressed.connect(_on_sell_goods_pressed.bind(item_id, 1))
			row.add_child(btn_sell_1)
			
			var btn_sell_all: Button = Button.new()
			btn_sell_all.text = "Все (x%d)" % count
			btn_sell_all.custom_minimum_size = Vector2(75, 28)
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
	for product_id in ["poor_brick", "fuel_briquette", "fired_brick", "glass", "iron_ingot", "clean_water", "bottled_water", "carrot", "potato", "wheat", "bread"]:
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
	
	# Кредиты в требованиях
	if cost_cr > 0:
		var row_cr: HBoxContainer = HBoxContainer.new()
		var l_cr: Label = Label.new()
		var player_cr: int = inv.get("credits") if (inv and "credits" in inv) else 0
		var cr_ok: bool = player_cr >= cost_cr
		l_cr.text = "💰 Кредиты: %d / %d" % [player_cr, cost_cr]
		l_cr.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if cr_ok else Color(1.0, 0.4, 0.4))
		l_cr.add_theme_font_size_override("font_size", 13)
		row_cr.add_child(l_cr)
		repair_requirements_list.add_child(row_cr)
	
	# Материалы в требованиях
	for mat_id in mats.keys():
		var needed: int = mats[mat_id]
		var avail: int = inv.get_item_count(mat_id) if inv else 0
		var mat_name: String = ItemDB.get_item_name(mat_id)
		var mat_icon: String = ItemDB.get_item_icon(mat_id)
		var ok: bool = avail >= needed
		
		var row_mat: HBoxContainer = HBoxContainer.new()
		var l_mat: Label = Label.new()
		l_mat.text = "%s %s: %d / %d" % [mat_icon, mat_name, avail, needed]
		l_mat.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if ok else Color(1.0, 0.4, 0.4))
		l_mat.add_theme_font_size_override("font_size", 13)
		row_mat.add_child(l_mat)
		repair_requirements_list.add_child(row_mat)
	
	var check: Dictionary = _current_active_building.can_upgrade(_bound_player) if _current_active_building.has_method("can_upgrade") else {}
	var can_up: bool = check.get("can_upgrade", false)
	repair_upgrade_button.disabled = not can_up
	repair_upgrade_button.text = "🔨 Восстановить (Уровень %d)" % (curr_stage + 1)

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
	if _current_active_building.has_method("sleep"):
		_current_active_building.sleep(_bound_player)

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
		notification_container.visible = true
	if notification_timer:
		notification_timer.start(duration)

func _on_notification_timeout() -> void:
	notification_container.visible = false

func set_credits(amount: int) -> void:
	if money_label:
		money_label.text = "💰 Кредиты: %d" % amount

# --- Окно Контрактов и NPC ---
func open_contract_window(source_node: Node = null) -> void:
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
	if contract_window:
		contract_window.visible = false
	_current_active_npc = null

func _refresh_contract_window() -> void:
	if not contract_window or not contracts_list:
		return
	
	if _current_active_npc and "greeting_text" in _current_active_npc:
		var n_name: String = _current_active_npc.npc_name if "npc_name" in _current_active_npc else "Степан (Снабженец)"
		contract_title_label.text = "👨‍🌾 " + n_name
		contract_dialogue_label.text = _current_active_npc.greeting_text
	else:
		contract_title_label.text = "📜 Доска заказов и контрактов"
		contract_dialogue_label.text = "Срочные поставки стройматериалов и снабжения для окрестных жителей. Оплата производится сразу при сдаче партии!"
	
	for child in contracts_list.get_children():
		contracts_list.remove_child(child)
		child.queue_free()
	
	var inv = _bound_player.get("inventory") if _bound_player else null
	var all_contracts = ContractDB.get_all_contracts()
	
	for contract in all_contracts:
		var c_id: String = contract.get("id", "")
		var is_done: bool = ContractDB.is_completed(c_id)
		var can_do: bool = ContractDB.can_fulfill(contract, inv)
		
		var card: PanelContainer = PanelContainer.new()
		var card_style: StyleBoxFlat = StyleBoxFlat.new()
		card_style.bg_color = Color(0.14, 0.17, 0.22, 0.95) if not is_done else Color(0.11, 0.13, 0.15, 0.7)
		card_style.border_color = Color(0.3, 0.75, 0.45, 1.0) if can_do else (Color(0.28, 0.45, 0.65, 0.8) if not is_done else Color(0.3, 0.35, 0.4, 0.5))
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
		lbl_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45) if not is_done else Color(0.65, 0.7, 0.75))
		h_title.add_child(lbl_title)
		
		var lbl_reward: Label = Label.new()
		lbl_reward.text = "💰 +%d кр." % contract.get("reward_credits", 0)
		lbl_reward.add_theme_font_size_override("font_size", 13)
		lbl_reward.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if not is_done else Color(0.6, 0.7, 0.6))
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
		var h_reqs: HBoxContainer = HBoxContainer.new()
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
		if is_done:
			btn.text = "Заказ выполнен ✅"
			btn.disabled = true
		elif can_do:
			btn.text = "Сдать партию материалов (💰 +%d кр.)" % contract.get("reward_credits", 0)
			btn.pressed.connect(_on_fulfill_contract_pressed.bind(c_id))
		else:
			btn.text = "Недостаточно товаров в рюкзаке"
			btn.disabled = true
		vbox.add_child(btn)
		
		contracts_list.add_child(card)

func _on_fulfill_contract_pressed(contract_id: String) -> void:
	if not _bound_player:
		return
	var ok: bool = ContractDB.fulfill_contract(contract_id, _bound_player)
	if ok:
		_refresh_contract_window()
