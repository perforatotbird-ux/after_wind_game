class_name ProductionMachine
extends "res://scripts/interaction/interactable.gd"

## Интерактивная производственная машина (Дробилка / Верстак / Плавильня)
## Соответствует разделам 18, 19, 20, 21, 29, 30, 68 дизайн-документа

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

signal machine_opened(machine: Node)
signal process_started(recipe_id: String, duration: float)
signal process_progress(progress: float)
signal process_completed(recipe_id: String, outputs: Dictionary)

@export var machine_type: String = "crusher"
@export var machine_display_name: String = "Дробилка камня"
@export var visual_node: Node3D

var is_machine_running: bool = false
var is_machine: bool = true
var active_recipe: Dictionary = {}
var process_timer: float = 0.0
var process_duration: float = 1.0
## Сколько циклов производства завершено (используется целью «Base Restored»).
var completed_runs: int = 0
## Продукция, не поместившаяся в рюкзак: { item_id: количество }. Выдаётся при следующем открытии.
var pending_outputs: Dictionary = {}
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
		var progress: float = clamp(process_timer / maxf(0.01, process_duration), 0.0, 1.0)
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
	if not pending_outputs.is_empty():
		return "[E] Забрать продукцию: %s" % object_name
	return "[E] Открыть %s" % object_name

func _on_interacted(player: Node) -> void:
	_last_user = player
	_deliver_pending(player)
	machine_opened.emit(self)

func start_recipe(recipe_id: String, player: Node) -> bool:
	if is_machine_running or not is_instance_valid(player):
		return false
	
	var recipe: Dictionary = RecipeDB.get_recipe(recipe_id)
	if recipe.is_empty() or recipe.get("machine", "") != machine_type:
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
	AudioManager.play("machine_start")
	
	if player.has_method("notify"):
		player.notify("⚙️ Запущено: %s (время: %.0f сек)" % [recipe.get("name"), process_duration])
	
	return true

func _complete_process() -> void:
	is_machine_running = false
	process_timer = 0.0
	completed_runs += 1
	if visual_node:
		visual_node.position = _original_pos
	
	var outputs: Dictionary = active_recipe.get("outputs", {})
	var user_valid: bool = _last_user != null and is_instance_valid(_last_user)
	var inv = null
	if user_valid and "inventory" in _last_user:
		inv = _last_user.get("inventory")
	
	# Начисление готовой продукции игроку; не поместившееся ждёт в машине.
	var stored_any: bool = false
	for item_id in outputs.keys():
		var amount: int = int(outputs[item_id])
		if inv and inv.add_item(item_id, amount):
			if _last_user.has_method("notify"):
				_last_user.notify("✅ Готово! %s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), amount])
		else:
			pending_outputs[item_id] = int(pending_outputs.get(item_id, 0)) + amount
			stored_any = true
	if stored_any and user_valid and _last_user.has_method("notify"):
		_last_user.notify("📦 Рюкзак полон — продукция ждёт в машине «%s»." % object_name)
	
	AudioManager.play("harvest", 1.25)
	process_completed.emit(active_recipe.get("id", ""), outputs)
	active_recipe = {}

## Выдаёт игроку продукцию, ранее не поместившуюся в рюкзак.
func _deliver_pending(player: Node) -> void:
	if pending_outputs.is_empty() or not is_instance_valid(player):
		return
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return
	for item_id in pending_outputs.keys():
		var amount: int = int(pending_outputs[item_id])
		if amount <= 0 or inv.add_item(item_id, amount):
			pending_outputs.erase(item_id)
			if amount > 0 and player.has_method("notify"):
				player.notify("📦 Забрано из машины: %s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), amount])
	if not pending_outputs.is_empty() and player.has_method("notify"):
		player.notify("⚠️ Не хватает слотов в рюкзаке — часть продукции осталась в машине.")

func get_progress() -> float:
	if not is_machine_running:
		return 0.0
	return clamp(process_timer / max(0.1, process_duration), 0.0, 1.0)
