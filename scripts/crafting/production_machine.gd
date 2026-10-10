class_name ProductionMachine
extends "res://scripts/interaction/interactable.gd"

## Интерактивная производственная машина (Дробилка / Верстак / Плавильня / Фильтр).
## Соответствует разделам 18, 19, 20, 21, 29, 30, 68 дизайн-документа.
##
## Два режима запуска:
## * start_recipe — один цикл, продукция сразу кладётся в рюкзак (старое поведение,
##   на него опираются тесты и сохранения прежних версий);
## * start_batch — партия из N циклов (окно станка, machine_panel.gd): сырьё на всю
##   партию списывается из рюкзака при старте, циклы идут подряд, продукция копится
##   в станке (pending_outputs) и забирается по E или кнопкой «Забрать».
##   cancel_batch останавливает партию без возврата сырья.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

## Максимум циклов в одной партии.
const MAX_BATCH_CYCLES: int = 99
## Бонус специализации «Учёный» (Этап 12).
const SCIENTIST_ENERGY_MULT: float = 0.5
const SCIENTIST_SPEED_MULT: float = 1.4

signal machine_opened(machine: Node)
signal process_started(recipe_id: String, duration: float)
signal process_progress(progress: float)
signal process_completed(recipe_id: String, outputs: Dictionary)
signal batch_finished(recipe_id: String, cycles: int)
signal batch_cancelled(recipe_id: String)
signal outputs_changed()

@export var machine_type: String = "crusher"
@export var machine_display_name: String = "Дробилка камня"
@export var visual_node: Node3D
## Сила дрожания корпуса в работе (0 — не дрожит; у дробилки движутся сами детали).
@export_range(0.0, 2.0) var shake_strength: float = 1.0

var is_machine_running: bool = false
var is_machine: bool = true
var active_recipe: Dictionary = {}
var process_timer: float = 0.0
## Длительность одного цикла (с учётом бонусов).
var process_duration: float = 1.0
## Сколько циклов производства завершено (используется целью «Base Restored»).
var completed_runs: int = 0
## Готовая продукция, ожидающая в станке: { item_id: количество }.
var pending_outputs: Dictionary = {}
## Текущая партия: всего циклов / завершено циклов.
var batch_cycles_total: int = 0
var batch_cycles_done: int = 0
## true — продукция партии копится в станке; false — одиночный запуск (сразу в рюкзак).
var batch_to_buffer: bool = false
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
			) * shake_strength
			visual_node.position = _original_pos + shake_offset
		
		if process_timer >= process_duration:
			_complete_process()

func get_prompt() -> String:
	if is_machine_running:
		var pct: int = int((process_timer / max(0.1, process_duration)) * 100.0)
		var r_name: String = active_recipe.get("name", "Переработка")
		if batch_cycles_total > 1:
			return "[E] %s (В работе: %s, цикл %d/%d, %d%%)" % [object_name, r_name, batch_cycles_done + 1, batch_cycles_total, pct]
		return "[E] %s (В работе: %s %d%%)" % [object_name, r_name, pct]
	if not pending_outputs.is_empty():
		return "[E] Забрать продукцию: %s" % object_name
	return "[E] Открыть %s" % object_name

func _on_interacted(player: Node) -> void:
	_last_user = player
	_deliver_pending(player)
	machine_opened.emit(self)

# ---------------------------------------------------------------------------
# Расчёт партии
# ---------------------------------------------------------------------------

## Сколько единиц основной продукции даёт один цикл рецепта.
static func get_output_per_cycle(recipe: Dictionary) -> int:
	var outputs: Dictionary = recipe.get("outputs", {})
	for item_id in outputs.keys():
		return maxi(1, int(outputs[item_id]))
	return 1

## Основной продукт рецепта (первый выход).
static func get_main_output(recipe: Dictionary) -> String:
	var outputs: Dictionary = recipe.get("outputs", {})
	for item_id in outputs.keys():
		return str(item_id)
	return ""

## Число циклов для заказа amount единиц продукции. 0 — значение не кратно выходу цикла.
static func cycles_for_amount(recipe: Dictionary, amount: int) -> int:
	var per_cycle: int = get_output_per_cycle(recipe)
	if amount <= 0 or amount % per_cycle != 0:
		return 0
	return amount / per_cycle

## Сколько циклов можно оплатить сырьём из инвентаря (не больше MAX_BATCH_CYCLES).
static func get_max_cycles(recipe: Dictionary, inv: Node) -> int:
	if recipe.is_empty() or inv == null:
		return 0
	var best: int = MAX_BATCH_CYCLES
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		var need: int = int(inputs[item_id])
		if need <= 0:
			continue
		best = mini(best, int(inv.get_item_count(item_id)) / need)
	return maxi(0, best)

## Длительность одного цикла и энергозатраты на цикл с учётом специализации игрока.
func get_cycle_params(recipe: Dictionary, player: Node) -> Dictionary:
	var energy_cost: float = float(recipe.get("energy_cost", 2.0))
	var duration: float = float(recipe.get("duration", 6.0))
	if player and "character_class" in player and player.character_class == "scientist":
		energy_cost *= SCIENTIST_ENERGY_MULT
		duration /= SCIENTIST_SPEED_MULT
	return {"duration": duration, "energy": energy_cost}

# ---------------------------------------------------------------------------
# Запуск
# ---------------------------------------------------------------------------

## Одиночный цикл: продукция сразу в рюкзак (совместимость со старым кодом).
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
	
	var params: Dictionary = get_cycle_params(recipe, player)
	if player.has_method("consume_energy"):
		player.consume_energy(params["energy"])
	
	batch_cycles_total = 1
	batch_cycles_done = 0
	batch_to_buffer = false
	_begin_cycle(recipe, params["duration"], player)
	
	if player.has_method("notify"):
		player.notify("⚙️ Запущено: %s (время: %.0f сек)" % [recipe.get("name"), process_duration])
	return true

## Партия из cycles циклов: сырьё на всю партию списывается сразу, энергия — тоже
## (за все циклы), продукция копится в станке.
func start_batch(recipe_id: String, cycles: int, player: Node) -> bool:
	if is_machine_running or not is_instance_valid(player):
		return false
	if cycles < 1 or cycles > MAX_BATCH_CYCLES:
		return false
	var recipe: Dictionary = RecipeDB.get_recipe(recipe_id)
	if recipe.is_empty() or recipe.get("machine", "") != machine_type:
		return false
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return false
	if get_max_cycles(recipe, inv) < cycles:
		if player.has_method("notify"):
			player.notify("❌ Недостаточно сырья на %d цикл(ов) «%s»!" % [cycles, recipe.get("name", recipe_id)])
		return false
	
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		inv.remove_item(item_id, int(inputs[item_id]) * cycles)
	
	var params: Dictionary = get_cycle_params(recipe, player)
	if player.has_method("consume_energy"):
		player.consume_energy(float(params["energy"]) * cycles)
	
	batch_cycles_total = cycles
	batch_cycles_done = 0
	batch_to_buffer = true
	_begin_cycle(recipe, params["duration"], player)
	
	if player.has_method("notify"):
		var main_out: String = get_main_output(recipe)
		player.notify("⚙️ Запущена партия: %s %s ×%d (≈ %.0f сек)" % [
			ItemDB.get_item_icon(main_out), ItemDB.get_item_name(main_out),
			cycles * get_output_per_cycle(recipe), process_duration * cycles
		])
	return true

func _begin_cycle(recipe: Dictionary, duration: float, player: Node) -> void:
	active_recipe = recipe
	process_timer = 0.0
	process_duration = maxf(0.05, duration)
	is_machine_running = true
	_last_user = player
	process_started.emit(recipe.get("id", ""), process_duration)
	AudioManager.play("machine_start")

## Останавливает текущую партию. Сырьё не возвращается, уже готовая продукция
## остаётся в станке.
func cancel_batch() -> bool:
	if not is_machine_running:
		return false
	var recipe_id: String = active_recipe.get("id", "")
	is_machine_running = false
	active_recipe = {}
	process_timer = 0.0
	batch_cycles_total = 0
	batch_cycles_done = 0
	batch_to_buffer = false
	if visual_node:
		visual_node.position = _original_pos
	if _last_user and is_instance_valid(_last_user) and _last_user.has_method("notify"):
		_last_user.notify("⏹ Производство в «%s» остановлено. Сырьё не возвращается." % object_name)
	batch_cancelled.emit(recipe_id)
	return true

func _complete_process() -> void:
	completed_runs += 1
	var outputs: Dictionary = active_recipe.get("outputs", {})
	var recipe_id: String = active_recipe.get("id", "")
	var user_valid: bool = _last_user != null and is_instance_valid(_last_user)
	
	if batch_to_buffer:
		for item_id in outputs.keys():
			pending_outputs[item_id] = int(pending_outputs.get(item_id, 0)) + int(outputs[item_id])
		batch_cycles_done += 1
		AudioManager.play("harvest", 1.25)
		process_completed.emit(recipe_id, outputs)
		outputs_changed.emit()
		if batch_cycles_done < batch_cycles_total:
			process_timer = 0.0
			return
		var cycles: int = batch_cycles_total
		_finish_run()
		if user_valid and _last_user.has_method("notify"):
			var main_out: String = get_main_output(ItemDB.get_item("") if false else {"outputs": outputs})
			_last_user.notify("✅ Партия готова: %s %s ×%d — заберите в «%s» [E]" % [
				ItemDB.get_item_icon(main_out), ItemDB.get_item_name(main_out),
				int(pending_outputs.get(main_out, 0)), object_name
			])
		batch_finished.emit(recipe_id, cycles)
		return
	
	# Одиночный запуск: продукция игроку; не поместившееся ждёт в машине.
	var inv = null
	if user_valid and "inventory" in _last_user:
		inv = _last_user.get("inventory")
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
	process_completed.emit(recipe_id, outputs)
	_finish_run()
	if stored_any:
		outputs_changed.emit()

func _finish_run() -> void:
	is_machine_running = false
	process_timer = 0.0
	active_recipe = {}
	batch_cycles_total = 0
	batch_cycles_done = 0
	batch_to_buffer = false
	if visual_node:
		visual_node.position = _original_pos

# ---------------------------------------------------------------------------
# Выдача продукции
# ---------------------------------------------------------------------------

## Забрать готовую продукцию из станка. Возвращает true, если станок опустел.
func collect_outputs(player: Node) -> bool:
	_deliver_pending(player)
	return pending_outputs.is_empty()

## Выдаёт игроку накопленную продукцию; если места мало — выдаёт сколько влезет.
func _deliver_pending(player: Node) -> void:
	if pending_outputs.is_empty() or not is_instance_valid(player):
		return
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return
	var changed: bool = false
	for item_id in pending_outputs.keys():
		var amount: int = int(pending_outputs[item_id])
		if amount <= 0:
			pending_outputs.erase(item_id)
			continue
		var fit: int = amount
		if inv.has_method("get_max_addable"):
			fit = inv.get_max_addable(item_id, amount)
		if fit <= 0 or not inv.add_item(item_id, fit):
			continue
		changed = true
		if fit >= amount:
			pending_outputs.erase(item_id)
		else:
			pending_outputs[item_id] = amount - fit
		if player.has_method("notify"):
			player.notify("📦 Забрано из машины: %s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), fit])
	if not pending_outputs.is_empty() and player.has_method("notify"):
		player.notify("⚠️ Не хватает места в рюкзаке — часть продукции осталась в машине.")
	if changed:
		outputs_changed.emit()

func get_progress() -> float:
	if not is_machine_running:
		return 0.0
	return clamp(process_timer / max(0.1, process_duration), 0.0, 1.0)

## Сколько секунд осталось до конца всей партии.
func get_batch_remaining_time() -> float:
	if not is_machine_running:
		return 0.0
	var left_cycles: int = maxi(0, batch_cycles_total - batch_cycles_done - 1)
	return maxf(0.0, process_duration - process_timer) + left_cycles * process_duration
