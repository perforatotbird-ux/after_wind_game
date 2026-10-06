class_name ProductionMachine
extends "res://scripts/interaction/interactable.gd"

## Интерактивная производственная машина (Дробилка / Верстак)
## Соответствует разделам 18, 19, 20, 21, 29, 30, 68 дизайн-документа

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")

signal machine_opened(machine: Node)
signal process_started(recipe_id: String, duration: float)
signal process_progress(progress: float)
signal process_completed(recipe_id: String, outputs: Dictionary)

@export var machine_type: String = "crusher"
@export var machine_display_name: String = "Дробилка камня"
@export var visual_node: Node3D

var is_machine_running: bool = false
var active_recipe: Dictionary = {}
var process_timer: float = 0.0
var process_duration: float = 1.0
var _original_pos: Vector3 = Vector3.ZERO
var _last_user: Node = null

func _ready() -> void:
	super._ready()
	object_name = machine_display_name
	prompt_action = "Открыть"
	
	if not visual_node:
		visual_node = get_node_or_null("Visual")
	if visual_node:
		_original_pos = visual_node.position

func _process(delta: float) -> void:
	if is_machine_running:
		process_timer += delta
		var progress: float = clamp(process_timer / process_duration, 0.0, 1.0)
		process_progress.emit(progress)
		
		# Визуальная вибрация работающей техники
		if visual_node:
			var shake_offset: Vector3 = Vector3(
				randf_range(-0.02, 0.02),
				randf_range(-0.01, 0.02),
				randf_range(-0.02, 0.02)
			)
			visual_node.position = _original_pos + shake_offset
		
		if process_timer >= process_duration:
			_complete_process()

func get_prompt() -> String:
	if is_machine_running:
		var pct: int = int((process_timer / max(0.1, process_duration)) * 100.0)
		var r_name: String = active_recipe.get("name", "Переработка")
		return "[E] %s (В работе: %s %d%%)" % [object_name, r_name, pct]
	return "[E] Открыть %s" % object_name

func _on_interacted(player: Node) -> void:
	_last_user = player
	machine_opened.emit(self)

func start_recipe(recipe_id: String, player: Node) -> bool:
	if is_machine_running:
		return false
	
	var recipe: Dictionary = RecipeDB.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return false
	
	# Проверка наличия сырья
	if not RecipeDB.can_craft(recipe, inv):
		if player.has_method("notify"):
			player.notify("❌ Недостаточно сырья для запуска производства!")
		return false
	
	# Списание ресурсов
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		var needed: int = inputs[item_id]
		inv.remove_item(item_id, needed)
	
	# Списание энергии игрока за запуск оборудования
	var energy_cost: float = recipe.get("energy_cost", 2.0)
	var duration: float = recipe.get("duration", 6.0)
	
	# Бонус специализации Учёный (Этап 12)
	if player and "character_class" in player and player.character_class == "scientist":
		energy_cost *= 0.50
		duration /= 1.40
	
	if player.has_method("consume_energy"):
		player.consume_energy(energy_cost)
	
	# Запуск процесса
	active_recipe = recipe
	process_timer = 0.0
	process_duration = duration
	is_machine_running = true
	_last_user = player
	
	process_started.emit(recipe_id, process_duration)
	
	if player.has_method("notify"):
		player.notify("⚙️ Запущено: %s (время: %.0f сек)" % [recipe.get("name"), process_duration])
	
	return true

func _complete_process() -> void:
	is_machine_running = false
	process_timer = 0.0
	if visual_node:
		visual_node.position = _original_pos
	
	var outputs: Dictionary = active_recipe.get("outputs", {})
	
	# Начисление готовой продукции игроку
	if _last_user and is_instance_valid(_last_user):
		var inv = _last_user.get("inventory") if "inventory" in _last_user else null
		if inv:
			for item_id in outputs.keys():
				var amount: int = outputs[item_id]
				inv.add_item(item_id, amount)
				var item_icon: String = ItemDB.get_item_icon(item_id)
				var item_name: String = ItemDB.get_item_name(item_id)
				if _last_user.has_method("notify"):
					_last_user.notify("✅ Готово! %s %s +%d" % [item_icon, item_name, amount])
	
	process_completed.emit(active_recipe.get("id", ""), outputs)
	active_recipe = {}

func get_progress() -> float:
	if not is_machine_running:
		return 0.0
	return clamp(process_timer / max(0.1, process_duration), 0.0, 1.0)
