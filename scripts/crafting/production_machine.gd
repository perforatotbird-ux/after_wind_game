class_name ProductionMachine
extends "res://scripts/interaction/interactable.gd"

## Интерактивная производственная машина (Дробилка / Верстак / Плавильня / Фильтр).
## Соответствует разделам 18, 19, 20, 21, 29, 30, 68 дизайн-документа.
##
## Два режима запуска:
## * start_recipe — один цикл, продукция складывается в инвентарь станка (pending_outputs);
## * start_batch — партия из N циклов (окно станка, machine_panel.gd): сырьё на всю
##   партию списывается из рюкзака при старте, циклы идут подряд, продукция копится
##   в станке (pending_outputs) и забирается в окне станка.
##   cancel_batch останавливает партию без возврата сырья.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const MachineWearScript = preload("res://scripts/crafting/machine_wear.gd")
const MachineLevelScript = preload("res://scripts/crafting/machine_level.gd")
const PowerGridScript = preload("res://scripts/energy/power_grid.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")

## Максимум циклов в одной партии.
const MAX_BATCH_CYCLES: int = 99
## Бонус специализации «Учёный» (Этап 12).
const SCIENTIST_ENERGY_MULT: float = 0.5
const SCIENTIST_SPEED_MULT: float = 1.4
## На сколько процентов состояния восстанавливает обычный ремонт (болты + рукоять).
const REPAIR_RESTORE: float = 50.0
## Качественный ремонт (болты + стальная пластина, с улучшенного верстака):
## восстанавливает больше состояния за более редкие детали.
const QUALITY_REPAIR_RESTORE: float = 70.0
const QUALITY_REPAIR_COST: Dictionary = {"bolt": 2, "steel_plate": 1}
## Число независимых слотов топлива у печи.
const FUEL_SLOTS: int = 4
## Вместимость одного топливного слота.
const FUEL_SLOT_STACK: int = 9
## Виды топлива и время горения одной единицы, сек реального времени.
## Дерево — слабое аварийное топливо (1 шт = 10 с); уголь и брикеты — основные.
const FUEL_BURN_TIME: Dictionary = {"coal": 240.0, "wood": 10.0, "fuel_briquette": 360.0}
const FUEL_ITEMS: Array[String] = ["coal", "wood", "fuel_briquette"]
## Стоимость улучшения станка: { тип станка: { уровень: { item_id: количество } } }.
## Все детали делаются станками: Lv.2 — из компонентов Lv.1, Lv.3 — из стали
## и точных шестерён (их делает только улучшенный верстак).
const UPGRADE_COSTS: Dictionary = {
	"crusher": {
		2: {"stone": 6, "iron_plate": 4, "gear": 2, "bolt": 4},
		3: {"steel_plate": 4, "precision_gear": 2, "iron_plate": 4, "bolt": 6},
	},
	"workbench": {
		2: {"wooden_handle": 2, "iron_plate": 4, "gear": 2, "bolt": 4},
		3: {"steel_plate": 4, "precision_gear": 3, "bolt": 6},
	},
	"furnace": {
		2: {"fired_brick": 6, "iron_plate": 6, "gear": 2, "bolt": 4},
		3: {"fired_brick": 6, "steel_plate": 6, "precision_gear": 2, "bolt": 6},
	},
	"water_filter": {
		2: {"sand": 4, "iron_plate": 2, "gear": 1, "bolt": 2},
		3: {"steel_plate": 2, "precision_gear": 1, "bolt": 4},
	},
	"kitchen_stove": {
		2: {"fired_brick": 4, "iron_plate": 3, "gear": 2},
	},
}

## Станки Главы 2, которым нужно топливо и которые не берут энергию из сети.
const HEAT_MACHINES: Array[String] = ["campfire", "kitchen_stove"]

signal machine_opened(machine: Node)
signal process_started(recipe_id: String, duration: float)
signal process_progress(progress: float)
signal process_completed(recipe_id: String, outputs: Dictionary)
signal batch_finished(recipe_id: String, cycles: int)
signal batch_cancelled(recipe_id: String)
signal outputs_changed()
signal machine_upgraded(new_level: int)
signal machine_rebuilt()

@export var machine_type: String = "crusher"
@export var machine_display_name: String = "Дробилка камня"
@export var visual_node: Node3D
## Сила дрожания корпуса в работе (0 — не дрожит; у дробилки движутся сами детали).
@export_range(0.0, 2.0) var shake_strength: float = 1.0
## Потребление энергосети в работе, кВт (мощность учитывается сетью только пока
## станок реально работает — см. get_power_demand; настраивается в сцене станка).
@export var power_draw: float = 1.0
## Износ включён (MachineWear): изнашивается за циклы, ремонт — repair_machine().
@export var wear_enabled: bool = true
## Износ за один завершённый цикл (при wear_enabled).
@export var wear_per_cycle: float = 0.5
## Ресурсы одного ремонта: { item_id: количество }.
@export var repair_cost: Dictionary = {"bolt": 2, "wooden_handle": 1}
## У печи — отдельный блок из 4 слотов топлива; без топлива цикл приостанавливается.
@export var has_fuel_slots: bool = false
## Число топливных слотов (у печи — 4, у костра — 1, у кухни — 2).
@export var fuel_slot_count: int = FUEL_SLOTS
## Переопределение времени горения: { item_id: секунды }. Пусто — FUEL_BURN_TIME.
@export var fuel_burn_times: Dictionary = {}
## Прибавка к выходу каждой позиции рецепта за уровень выше первого
## (дробилка 1, фильтр 2; у верстака и печи выход растёт только рецептами).
@export var yield_bonus_per_level: int = 0

@export_group("Глава 2: восстановление / постройка")
## Станок в мире начинает разрушенным (или не построенным) и не работает,
## пока его не восстановить за rebuild_cost + rebuild_credits.
## Стартовый баланс Главы 2: работают только верстак и костёр.
@export var requires_rebuild: bool = false
## Что показывает неготовый станок (завалы камней, кирпичная кладка, чертеж на кольях).
@export var ruined_visual: Node3D
## Словарь для подсказок и окна станка: { title, description, perks }.
@export var rebuild_info: Dictionary = {}
## Материалы восстановления/постройки: { item_id: количество }.
@export var rebuild_cost: Dictionary = {}
## Кредиты за восстановление/постройку.
@export var rebuild_credits: int = 0

var is_machine_running: bool = false
var is_machine: bool = true
## Станок восстановлен/построен. Стартовое значение — requires_rebuild.
var rebuilt: bool = true
## Накопленные внутри станка компоненты текущей работы (восстановление,
## ремонт, качественный ремонт, улучшение): { kind: { item_id: количество } }.
## Детали переносятся из рюкзака порциями — работу можно вести за несколько
## подходов, ничего не теряется между ними.
var job_stash: Dictionary = {"rebuild": {}, "repair": {}, "repair_q": {}, "upgrade": {}}
## Накопленные кредиты по видам работ (нужны только восстановлению).
var job_credits: Dictionary = {"rebuild": 0, "repair": 0, "repair_q": 0, "upgrade": 0}
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
## Питание от энергосети (PowerGrid.set_powered). false — цикл на паузе.
var power_ok: bool = true
## Состояние оборудования (износ/ремонт) — общий компонент MachineWear.
var wear: MachineWearScript
## Уровень станка (Lv.1 базовая → Lv.2 улучшенная → Lv.3 передовая).
var level_state: MachineLevelScript
## 4 независимых слота топлива: { "item_id": String, "count": int }.
var fuel_slots: Array = []
## Сколько секунд горения осталось у активной единицы топлива.
var fuel_burn_left: float = 0.0
## Слот, из которого взята горящая единица топлива (-1 — ничего не горит).
var active_fuel_slot: int = -1

var _last_emitted_progress: float = -1.0

func _ready() -> void:
	super._ready()
	object_name = machine_display_name
	prompt_action = "Открыть"
	# Перемотка времени (отдых, сон) должна двигать и производство.
	add_to_group("production_machines")
	# Станок без потребления (костёр) не встаёт в сеть — иначе он «просит»
	# энергию, которой у ручного станка быть не может.
	if power_draw > 0.0:
		add_to_group("power_consumers")
	wear = MachineWearScript.new()
	wear.wear_per_cycle = wear_per_cycle
	level_state = MachineLevelScript.new()
	wear.max_condition = level_state.get_max_condition()
	wear.condition = wear.max_condition
	if not wear_enabled:
		wear.condition = wear.max_condition
	if has_fuel_slots:
		for i in maxi(1, fuel_slot_count):
			fuel_slots.append({"item_id": "", "count": 0})
	
	if not visual_node:
		visual_node = get_node_or_null("Visual")
	if visual_node:
		_original_pos = visual_node.position
	rebuilt = not requires_rebuild
	_update_rebuild_visuals()
	set_process(is_machine_running)

# ---------------------------------------------------------------------------
# Восстановление / постройка (Глава 2)
# ---------------------------------------------------------------------------

## Станок готов к работе (или ещё нет).
func is_operational() -> bool:
	return rebuilt

## Продвигает работу станка на hours игровых часов (перемотка времени во время
## отдыха/сна): циклы идут, топливо сгорает, продукция копится в станке.
## Остановленный станок не запускается сам собой.
func advance_hours(hours: float) -> void:
	if hours <= 0.0 or not is_machine_running:
		return
	var seconds_left: float = hours * _get_seconds_per_game_hour()
	var step: float = 0.5
	while seconds_left > 0.0 and is_machine_running and not is_queued_for_deletion():
		var dt: float = minf(step, seconds_left)
		seconds_left -= dt
		if not power_ok:
			continue
		if has_fuel_slots and fuel_burn_left <= 0.0 and not _light_next_fuel():
			# Топливо кончилось: цикл на паузе, сырьё и прогресс не теряются.
			break
		if has_fuel_slots:
			fuel_burn_left = maxf(0.0, fuel_burn_left - dt / level_state.get_fuel_efficiency())
		process_timer += dt
		if process_timer >= process_duration:
			_complete_process()

## Сколько реальных секунд длится один игровой час (из DayNightCycle).
func _get_seconds_per_game_hour() -> float:
	var tree := get_tree()
	if tree:
		var dc: Node = tree.get_first_node_in_group("day_night_cycle")
		if dc and dc.has_method("get_seconds_per_game_hour"):
			return maxf(1.0, float(dc.get_seconds_per_game_hour()))
	return 60.0

## Текст состояния: «Работает» / «Разрушена» / «Не построена».
func get_rebuild_state_name() -> String:
	if rebuilt:
		return "Готова к работе"
	return str(rebuild_info.get("title", "Разрушена"))

## Всё, что нужно для восстановления: { credits, materials }.
func get_rebuild_requirements() -> Dictionary:
	return {"credits": maxi(0, rebuild_credits), "materials": rebuild_cost.duplicate()}

## Хватает ли ресурсов на восстановление.
func can_rebuild(player: Node) -> Dictionary:
	var result: Dictionary = {"can_rebuild": false, "reason": "", "missing_credits": 0, "missing_materials": {}}
	if rebuilt:
		result["reason"] = "Станок уже готов к работе."
		return result
	var inv = player.get("inventory") if player and "inventory" in player else null
	if inv == null:
		result["reason"] = "Инвентарь игрока недоступен."
		return result
	if maxi(0, rebuild_credits) > 0 and int(inv.get("credits")) < rebuild_credits:
		result["missing_credits"] = rebuild_credits - int(inv.get("credits"))
	var missing: Dictionary = {}
	for item_id in rebuild_cost.keys():
		var needed: int = int(rebuild_cost[item_id])
		var avail: int = int(inv.get_item_count(str(item_id)))
		if avail < needed:
			missing[str(item_id)] = needed - avail
	result["missing_materials"] = missing
	if result["missing_credits"] == 0 and missing.is_empty():
		result["can_rebuild"] = true
	else:
		result["reason"] = "Не хватает ресурсов или кредитов."
	return result

## Что нужно для работы kind ("rebuild" / "repair" / "repair_q" / "upgrade"):
## {"materials": {...}, "credits": int}.
func get_job_requirements(kind: String) -> Dictionary:
	match kind:
		"rebuild":
			return {"materials": rebuild_cost.duplicate(), "credits": maxi(0, rebuild_credits)}
		"repair":
			return {"materials": repair_cost.duplicate(), "credits": 0}
		"repair_q":
			return {"materials": QUALITY_REPAIR_COST.duplicate(), "credits": 0}
		"upgrade":
			var costs: Dictionary = UPGRADE_COSTS.get(machine_type, {})
			var next: Dictionary = costs.get(level_state.level + 1, {}) if level_state else {}
			return {"materials": next.duplicate(), "credits": 0}
	return {"materials": {}, "credits": 0}

## Прогресс работы kind с учётом накопленного в станке:
## {"ready": bool, "materials": {id: [внесено, нужно]}, "credits": [внесено, нужно],
##   "delivered": int, "need": int} — последние два для компактной кнопки.
func get_job_progress(kind: String) -> Dictionary:
	var req: Dictionary = get_job_requirements(kind)
	var stash: Dictionary = job_stash.get(kind, {})
	var mats: Dictionary = req.get("materials", {})
	var out: Dictionary = {
		"ready": false, "materials": {}, "credits": [0, 0], "delivered": 0, "need": 0
	}
	var done: bool = true
	var need_cr: int = int(req.get("credits", 0))
	var have_cr: int = int(job_credits.get(kind, 0))
	out["credits"] = [have_cr, need_cr]
	out["delivered"] += mini(have_cr, need_cr)
	out["need"] += need_cr
	if have_cr < need_cr:
		done = false
	for item_id in mats.keys():
		var need: int = int(mats[item_id])
		var have: int = int(stash.get(item_id, 0))
		out["materials"][item_id] = [have, need]
		out["delivered"] += mini(have, need)
		out["need"] += need
		if have < need:
			done = false
	out["ready"] = done
	return out

## Доступна ли работа kind прямо сейчас (без переноса ресурсов).
func is_job_available(kind: String) -> bool:
	match kind:
		"rebuild":
			return not rebuilt
		"repair", "repair_q":
			return wear != null and wear.get_ratio() < 1.0
		"upgrade":
			return can_upgrade()
	return false

## Переносит в станок всё, что есть в рюкзаке (не больше нужного), и, когда
## комплект собран, выполняет работу. Возвращает true, если работа выполнена
## этим вызовом.
func contribute_to_job(player: Node, kind: String) -> bool:
	if not is_instance_valid(player):
		return false
	if not is_job_available(kind):
		_notify_job_unavailable(player, kind)
		return false
	var req: Dictionary = get_job_requirements(kind)
	var inv = player.get("inventory") if "inventory" in player else null
	if inv == null:
		if player.has_method("notify"):
			player.notify("❌ Инвентарь игрока недоступен.")
		return false

	if not job_stash.has(kind):
		job_stash[kind] = {}
	var stash: Dictionary = job_stash[kind]
	var need_cr: int = int(req.get("credits", 0))
	var player_cr: int = int(inv.get("credits")) if "credits" in inv else 0
	var cr_take: int = clampi(need_cr - int(job_credits.get(kind, 0)), 0, maxi(0, player_cr))
	if cr_take > 0:
		inv.spend_credits(cr_take)
		job_credits[kind] = int(job_credits.get(kind, 0)) + cr_take

	var brought: Array[String] = []
	var mats: Dictionary = req.get("materials", {})
	for item_id in mats.keys():
		var need: int = int(mats[item_id]) - int(stash.get(item_id, 0))
		if need <= 0:
			continue
		var take: int = mini(need, inv.get_item_count(str(item_id)))
		if take > 0 and inv.remove_item(str(item_id), take):
			stash[item_id] = int(stash.get(item_id, 0)) + take
			brought.append("%s ×%d" % [ItemDB.get_item_name(str(item_id)), take])

	var progress: Dictionary = get_job_progress(kind)
	if not bool(progress.get("ready", false)):
		if player.has_method("notify"):
			var msg: String = "📦 Внесено в «%s»:" % object_name
			if not brought.is_empty():
				msg += " " + ", ".join(brought)
			var still: PackedStringArray = []
			var cr_pair: Array = progress["credits"]
			if int(cr_pair[0]) < int(cr_pair[1]):
				still.append("💰 кредиты %d/%d" % [int(cr_pair[0]), int(cr_pair[1])])
			for item_id in progress["materials"].keys():
				var pair: Array = progress["materials"][item_id]
				if int(pair[0]) < int(pair[1]):
					still.append("%s %s %d/%d" % [ItemDB.get_item_icon(str(item_id)), ItemDB.get_item_name(str(item_id)), int(pair[0]), int(pair[1])])
			if not still.is_empty():
				msg += ". Осталось: " + ", ".join(still)
			player.notify(msg)
		return false

	# Комплект собран — выполняем работу (внесено ровно по нужному количеству).
	_apply_job(kind)
	job_stash[kind] = {}
	job_credits[kind] = 0
	return true

func _notify_job_unavailable(player: Node, kind: String) -> void:
	if not player.has_method("notify"):
		return
	match kind:
		"rebuild":
			player.notify("✅ «%s» уже готов к работе." % object_name)
		"repair", "repair_q":
			player.notify("✅ «%s» полностью исправна — ремонт не нужен." % object_name)
		"upgrade":
			player.notify("⬆ «%s» уже максимального уровня (Lv.%d)." % [object_name, level_state.level])

func _apply_job(kind: String) -> void:
	match kind:
		"rebuild":
			set_rebuilt(true)
			AudioManager.play("build")
			var title: String = str(rebuild_info.get("title", "готов к работе"))
			if _last_user and is_instance_valid(_last_user) and _last_user.has_method("notify"):
				_last_user.notify("🎉 %s восстановлен: %s" % [object_name, title])
			machine_rebuilt.emit()
		"repair", "repair_q":
			var restore: float = QUALITY_REPAIR_RESTORE if kind == "repair_q" else REPAIR_RESTORE
			wear.repair(wear.max_condition * restore / 100.0)
			AudioManager.play("build")
			if _last_user and is_instance_valid(_last_user) and _last_user.has_method("notify"):
				_last_user.notify("🔧 «%s» отремонтирована (%s): %s" % [
					object_name, "качественно" if kind == "repair_q" else "обычно", wear.get_status_text()])
		"upgrade":
			var ratio: float = wear.get_ratio() if wear else 1.0
			var next_level: int = level_state.level + 1
			level_state.set_level(next_level)
			if wear:
				wear.max_condition = level_state.get_max_condition()
				wear.set_condition(ratio * wear.max_condition)
			AudioManager.play("build")
			if _last_user and is_instance_valid(_last_user) and _last_user.has_method("notify"):
				_last_user.notify("⬆ «%s» улучшена до Lv.%d (%s): циклы ×%.2f, ресурс %d, питание ×%.1f." % [
					object_name, next_level, level_state.get_level_name(), level_state.get_speed_mult(),
					int(level_state.get_max_condition()), level_state.get_power_mult()])
			machine_upgraded.emit(next_level)
	
	var skills: Object = _last_user.get("skills") if _last_user and is_instance_valid(_last_user) and "skills" in _last_user else null
	if skills and skills.has_method("add_xp"):
		if kind == "rebuild":
			skills.add_xp("construction", 40)
		elif kind in ["repair", "repair_q"]:
			skills.add_xp("crafting", 15)
		elif kind == "upgrade":
			skills.add_xp("construction", 50)

## Восстанавливает (или строит) станок: компоненты переносятся внутрь станка
## порциями, станок встаёт в ready, когда комплект собран.
func rebuild(player: Node) -> bool:
	if rebuilt:
		if player and player.has_method("notify"):
			player.notify("✅ «%s» уже готов к работе." % object_name)
		return false
	return contribute_to_job(player, "rebuild")

## Ставит станок в готовое состояние (или возвращает в разрушенное).
func set_rebuilt(value: bool) -> void:
	rebuilt = value
	if rebuilt:
		# Восстановление засчитывается в вехи Главы 2 «Первый дым».
		CookingProgress.register_rebuild(machine_type)
	else:
		# Неготовый станок не может быть занятым или повреждённым.
		cancel_batch()
		pending_outputs.clear()
		job_stash["rebuild"] = {}
		job_credits["rebuild"] = 0
		if wear:
			wear.set_condition(wear.max_condition)
	_update_rebuild_visuals()

## Тестовый и отладочный ход: минует стоимость и сразу включает станок.
func force_rebuilt() -> void:
	job_stash["rebuild"] = {}
	job_credits["rebuild"] = 0
	set_rebuilt(true)

func _update_rebuild_visuals() -> void:
	if ruined_visual:
		ruined_visual.visible = not rebuilt
	if visual_node:
		visual_node.visible = rebuilt
	if is_inside_tree():
		set_process(is_machine_running)

func _process(delta: float) -> void:
	if not is_machine_running:
		set_process(false)
		return
	if not power_ok:
		# Нет питания: таймер цикла стоит, партия ждёт. Сырьё уже списано — не теряется.
		return
	if has_fuel_slots:
		if fuel_burn_left <= 0.0 and not _light_next_fuel():
			# Топливо кончилось: цикл приостановлен, сырьё и прогресс партии не теряются.
			return
		# КПД топлива растёт с уровнем станка (Lv.2 ×1.3): горение тратится медленнее.
		fuel_burn_left = maxf(0.0, fuel_burn_left - delta / level_state.get_fuel_efficiency())
	process_timer += delta
	var progress: float = clamp(process_timer / maxf(0.01, process_duration), 0.0, 1.0)
	if absf(progress - _last_emitted_progress) >= 0.01 or progress >= 1.0:
		_last_emitted_progress = progress
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
	var lvl: String = " (Lv.%d)" % level_state.level if level_state.level > 1 else ""
	if not rebuilt:
		return "[E] %s [%s]" % [object_name, get_rebuild_state_name()]
	if is_machine_running:
		if not power_ok:
			return "[E] %s (Нет питания — цикл приостановлен)" % object_name
		if has_fuel_slots and fuel_burn_left <= 0.0 and get_fuel_time_total() <= 0.0:
			return "[E] %s (Нет топлива — цикл приостановлен)" % object_name
		var pct: int = int((process_timer / max(0.1, process_duration)) * 100.0)
		var r_name: String = active_recipe.get("name", "Переработка")
		if batch_cycles_total > 1:
			return "[E] %s%s (В работе: %s, цикл %d/%d, %d%%)" % [object_name, lvl, r_name, batch_cycles_done + 1, batch_cycles_total, pct]
		return "[E] %s%s (В работе: %s %d%%)" % [object_name, lvl, r_name, pct]
	if not pending_outputs.is_empty():
		var total_items: int = 0
		for cnt in pending_outputs.values():
			total_items += int(cnt)
		return "[E] Открыть %s%s (продукция: %d шт.)" % [object_name, lvl, total_items]
	return "[E] Открыть %s%s" % [object_name, lvl]

func _on_interacted(player: Node) -> void:
	_last_user = player
	machine_opened.emit(self)

# ---------------------------------------------------------------------------
# Энергосеть (PowerGrid опрашивает группу power_consumers)
# ---------------------------------------------------------------------------

## Мощность, которую станок берёт из сети прямо сейчас, кВт. Работающий станок
## потребляет даже без питания (его цикл стоит и он «просит» энергию) — иначе
## сеть мигала бы на границе баланса. Исключение — режим сети «Батарея»: там
## пауза снимает нагрузку, чтобы батарея могла зарядиться и вернуть питание.
## Улучшенный станок мощнее (Lv.2 ×1.3, Lv.3 ×1.6), но и работает быстрее.
func get_power_demand() -> float:
	if not is_machine_running or power_draw <= 0.0:
		return 0.0
	if not power_ok:
		var grid: Node = _get_power_grid()
		if grid and int(grid.get("source_mode")) == PowerGridScript.SourceMode.BATTERY:
			return 0.0
	return power_draw * level_state.get_power_mult()

var _grid_ref: Node = null

func _get_power_grid() -> Node:
	if not is_instance_valid(_grid_ref) and get_tree():
		_grid_ref = get_tree().get_first_node_in_group("power_grid")
	return _grid_ref

## PowerGrid сообщает о доступности питания. Без питания цикл приостанавливается:
## партия и сырьё не теряются, при восстановлении питания производство продолжается.
func set_powered(has_power: bool) -> void:
	if power_ok == has_power:
		return
	power_ok = has_power
	if not is_machine_running or not (_last_user and is_instance_valid(_last_user)):
		return
	if not has_power:
		_last_user.notify("⚡ В «%s» нет питания — производство приостановлено." % object_name)
	else:
		_last_user.notify("⚡ Питание восстановлено: «%s» продолжает работу." % object_name)

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
	var skills: Object = player.get("skills") if player and "skills" in player else null
	if skills:
		if skills.has_method("get_machine_speed_mult"):
			duration /= skills.get_machine_speed_mult()
		var sk_id: String = "hydrology" if machine_type == "water_filter" else "crafting"
		if skills.has_method("get_energy_discount"):
			energy_cost *= skills.get_energy_discount(sk_id)
	return {"duration": duration, "energy": energy_cost}

# ---------------------------------------------------------------------------
# Запуск
# ---------------------------------------------------------------------------

## Одиночный цикл: продукция копится в станке (pending_outputs).
func start_recipe(recipe_id: String, player: Node) -> bool:
	if is_machine_running or not is_instance_valid(player):
		return false
	
	var recipe: Dictionary = RecipeDB.get_recipe(recipe_id)
	if recipe.is_empty() or recipe.get("machine", "") != machine_type:
		return false

	if not rebuilt:
		if player.has_method("notify"):
			player.notify("⛔ «%s» %s — сначала приведите станок в порядок." % [object_name, get_rebuild_state_name().to_lower()])
		return false
	if wear and wear.is_broken():
		if player.has_method("notify"):
			player.notify("⛔ «%s» неисправна и требует ремонта." % object_name)
		return false
	if int(recipe.get("min_level", 1)) > level_state.level:
		if player.has_method("notify"):
			player.notify("⬆ Рецепт «%s» требует станок Lv.%d — улучшите станок." % [recipe.get("name", recipe_id), int(recipe["min_level"])])
		return false

	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return false

	# Проверка наличия сырья
	if not RecipeDB.can_craft(recipe, inv):
		if player.has_method("notify"):
			player.notify("❌ Недостаточно сырья для запуска производства!")
		return false

	var params: Dictionary = get_cycle_params(recipe, player)
	# Топливо проверяется ДО списания сырья: при отказе ничего не теряется.
	if not _require_fuel(params["duration"] * (wear.get_speed_mult() if wear else 1.0), player, 1):
		return false

	# Списание ресурсов
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		var needed: int = inputs[item_id]
		inv.remove_item(item_id, needed)

	if player.has_method("consume_energy"):
		player.consume_energy(params["energy"] * level_state.get_energy_mult())

	batch_cycles_total = 1
	batch_cycles_done = 0
	batch_to_buffer = true
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
	if not rebuilt:
		if player.has_method("notify"):
			player.notify("⛔ «%s» %s — сначала приведите станок в порядок." % [object_name, get_rebuild_state_name().to_lower()])
		return false
	if wear and wear.is_broken():
		if player.has_method("notify"):
			player.notify("⛔ «%s» неисправна и требует ремонта." % object_name)
		return false
	if int(recipe.get("min_level", 1)) > level_state.level:
		if player.has_method("notify"):
			player.notify("⬆ Рецепт «%s» требует станок Lv.%d — улучшите станок." % [recipe.get("name", recipe_id), int(recipe["min_level"])])
		return false
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return false
	if get_max_cycles(recipe, inv) < cycles:
		if player.has_method("notify"):
			player.notify("❌ Недостаточно сырья на %d цикл(ов) «%s»!" % [cycles, recipe.get("name", recipe_id)])
		return false

	var params: Dictionary = get_cycle_params(recipe, player)
	# Топливо проверяется ДО списания сырья: при отказе ничего не теряется.
	if not _require_fuel(params["duration"] * (wear.get_speed_mult() if wear else 1.0) * cycles, player, cycles):
		return false

	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id in inputs.keys():
		inv.remove_item(item_id, int(inputs[item_id]) * cycles)

	if player.has_method("consume_energy"):
		player.consume_energy(float(params["energy"]) * level_state.get_energy_mult() * cycles)

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
	# Скорость цикла: рецепт × уровень станка × износ (MachineWear).
	process_duration = maxf(0.05, duration) \
		* level_state.get_speed_mult() \
		* (wear.get_speed_mult() if wear else 1.0)
	_last_emitted_progress = -1.0
	# Печь разжигает топливо сразу при старте цикла.
	if has_fuel_slots and fuel_burn_left <= 0.0:
		_light_next_fuel()
	is_machine_running = true
	set_process(true)
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
	set_process(false)
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

# ---------------------------------------------------------------------------
# Крючок подсистем (Глава 2: кулинария и вехи)
# ---------------------------------------------------------------------------

## Вызывается после каждого завершённого цикла с выходами одного цикла.
## Переопределяется станками готовки, чтобы засчитывать приготовленные блюда.
func _on_outputs_produced(_outputs: Dictionary) -> void:
	pass

func _complete_process() -> void:
	completed_runs += 1
	var user_valid: bool = _last_user != null and is_instance_valid(_last_user)
	var skills: Object = _last_user.get("skills") if user_valid and "skills" in _last_user else null
	if wear_enabled and wear:
		# Улучшенный станок изнашивается медленнее (множитель уровня).
		var w_amount: float = wear_per_cycle * level_state.get_wear_mult()
		if skills and skills.has_method("get_wear_discount"):
			w_amount *= skills.get_wear_discount()
		wear.add_wear(w_amount)
	
	if skills and skills.has_method("add_xp"):
		if machine_type == "water_filter":
			skills.add_xp("hydrology", 10)
		elif machine_type in HEAT_MACHINES:
			skills.add_xp("cooking", 15)
		else:
			skills.add_xp("crafting", 12)
	
	var outputs: Dictionary = active_recipe.get("outputs", {})
	var recipe_id: String = active_recipe.get("id", "")

	# Бонус выхода за уровень (дробилка +1/ур., фильтр +2/ур.): каждая позиция
	# рецепта получает прибавку — цикл делает больше продукции, сырьё то же.
	var bonus: int = yield_bonus_per_level * maxi(0, level_state.level - 1)
	for item_id in outputs.keys():
		pending_outputs[item_id] = int(pending_outputs.get(item_id, 0)) + int(outputs[item_id]) + bonus
	batch_cycles_done += 1
	AudioManager.play("machine_done")
	_on_outputs_produced(outputs)
	process_completed.emit(recipe_id, outputs)
	outputs_changed.emit()
	if batch_cycles_done < batch_cycles_total:
		process_timer = 0.0
		_last_emitted_progress = -1.0
		return
	var cycles: int = batch_cycles_total
	_finish_run()
	if user_valid and _last_user.has_method("notify"):
		var main_out: String = get_main_output(ItemDB.get_item("") if false else {"outputs": outputs})
		_last_user.notify("✅ Готово: %s %s ×%d — заберите в «%s» [E]" % [
			ItemDB.get_item_icon(main_out), ItemDB.get_item_name(main_out),
			int(pending_outputs.get(main_out, 0)), object_name
		])
	batch_finished.emit(recipe_id, cycles)

func _finish_run() -> void:
	is_machine_running = false
	set_process(false)
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

## Забрать конкретный предмет из станка в рюкзак игрока.
## Возвращает количество перенесённых единиц.
func collect_output_item(item_id: String, player: Node, max_amount: int = -1) -> int:
	if not pending_outputs.has(item_id) or not is_instance_valid(player):
		return 0
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return 0
	var available: int = int(pending_outputs.get(item_id, 0))
	if available <= 0:
		pending_outputs.erase(item_id)
		outputs_changed.emit()
		return 0
	var amount: int = available if max_amount <= 0 else mini(available, max_amount)
	var fit: int = amount
	if inv.has_method("get_max_addable"):
		fit = inv.get_max_addable(item_id, amount)
	if fit <= 0 or not inv.add_item(item_id, fit):
		if player.has_method("notify"):
			player.notify("⚠️ В рюкзаке нет места для %s" % ItemDB.get_item_name(item_id))
		return 0
	
	if fit >= available:
		pending_outputs.erase(item_id)
	else:
		pending_outputs[item_id] = available - fit
	if player.has_method("notify"):
		player.notify("📦 Забрано из машины: %s %s +%d" % [ItemDB.get_item_icon(item_id), ItemDB.get_item_name(item_id), fit])
	outputs_changed.emit()
	return fit

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

# ---------------------------------------------------------------------------
# Износ и ремонт
# ---------------------------------------------------------------------------

## Ремонт станка: детали переносятся внутрь станка порциями, ремонт
## выполняется, когда комплект собран. Обычный ремонт — repair_cost (+50 %),
## качественный (quality = true) — QUALITY_REPAIR_COST (+70 %, стальная пластина).
## Возвращает true, если ремонт выполнен этим вызовом.
func repair_machine(player: Node, quality: bool = false) -> bool:
	if wear == null:
		return false
	if wear.get_ratio() >= 1.0:
		if player and player.has_method("notify"):
			player.notify("✅ «%s» полностью исправна — ремонт не нужен." % object_name)
		return false
	return contribute_to_job(player, "repair_q" if quality else "repair")

func _repair_cost_text(cost: Dictionary = {}) -> String:
	var use: Dictionary = cost if not cost.is_empty() else repair_cost
	var parts: PackedStringArray = []
	for item_id in use.keys():
		parts.append("%s %s ×%d" % [ItemDB.get_item_icon(str(item_id)), ItemDB.get_item_name(str(item_id)), int(use[item_id])])
	return ", ".join(parts)

# ---------------------------------------------------------------------------
# Уровни станка (улучшение на месте)
# ---------------------------------------------------------------------------

func get_level() -> int:
	return level_state.level if level_state else 1

## Можно ли улучшить прямо сейчас: есть следующий уровень, стоимость для этого
## типа станка задана и станок не занят производством.
func can_upgrade() -> bool:
	if level_state == null or not level_state.can_upgrade() or is_machine_running:
		return false
	var costs: Dictionary = UPGRADE_COSTS.get(machine_type, {})
	return costs.has(level_state.level + 1)

## Стоимость следующего уровня: { item_id: количество } или {}.
func get_upgrade_cost() -> Dictionary:
	if not can_upgrade():
		return {}
	return UPGRADE_COSTS[machine_type][level_state.level + 1]

## Улучшает станок на месте: детали переносятся внутрь станка порциями,
## уровень растёт, когда комплект собран (ресурс износа — с сохранением доли
## состояния). Возвращает true при успешном улучшении этим вызовом.
func upgrade_machine(player: Node) -> bool:
	if level_state == null:
		return false
	if is_machine_running:
		if player and player.has_method("notify"):
			player.notify("⏳ Дождитесь окончания партии, прежде чем улучшать станок.")
		return false
	if not can_upgrade():
		if player and player.has_method("notify"):
			player.notify("⬆ «%s» уже максимального уровня (Lv.%d)." % [object_name, level_state.level])
		return false
	return contribute_to_job(player, "upgrade")

func _upgrade_cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_id in cost.keys():
		parts.append("%s %s ×%d" % [ItemDB.get_item_icon(str(item_id)), ItemDB.get_item_name(str(item_id)), int(cost[item_id])])
	return ", ".join(parts)

# ---------------------------------------------------------------------------
# Топливо (печь: 4 независимых слота, у каждого вида своё время горения)
# ---------------------------------------------------------------------------

func get_fuel_burn_time(item_id: String) -> float:
	if not fuel_burn_times.is_empty():
		return float(fuel_burn_times.get(item_id, 0.0))
	return float(FUEL_BURN_TIME.get(item_id, 0.0))

## Полный запас горения: догорающая единица + всё топливо в слотах, сек.
## У станков без топливных слотов — заведомо большое значение.
func get_fuel_time_total() -> float:
	if not has_fuel_slots:
		return 1.0e9
	var total: float = fuel_burn_left
	for slot in fuel_slots:
		if int(slot["count"]) > 0:
			total += get_fuel_burn_time(str(slot["item_id"])) * int(slot["count"])
	return total

## Проверка перед запуском: запаса горения должно хватить на всю партию.
func _require_fuel(needed_seconds: float, player: Node, cycles: int) -> bool:
	if not has_fuel_slots or get_fuel_time_total() >= needed_seconds:
		return true
	if player and player.has_method("notify"):
		player.notify("⛽ Не хватает топлива на %d цикл(ов) (%.0f с горения). В слоты: %s." % [
			cycles, needed_seconds, _fuel_list_text()])
	return false

func _fuel_list_text() -> String:
	var parts: PackedStringArray = []
	for f in FUEL_ITEMS:
		parts.append("%s %s (%d с/шт)" % [ItemDB.get_item_icon(f), ItemDB.get_item_name(f), int(get_fuel_burn_time(f))])
	return ", ".join(parts)

## Кладёт топливо из инвентаря в слоты: сначала в слоты с тем же видом,
## затем в пустые. Возвращает, сколько единиц добавлено.
func add_fuel_from_inventory(inv: Node, item_id: String, amount: int = -1) -> int:
	if not has_fuel_slots or inv == null or not item_id in FUEL_ITEMS:
		return 0
	var available: int = int(inv.get_item_count(item_id))
	if amount >= 0:
		available = mini(available, amount)
	var added: int = 0
	for slot in fuel_slots:
		if added >= available:
			break
		if str(slot["item_id"]) == item_id and int(slot["count"]) < FUEL_SLOT_STACK:
			var n: int = mini(available - added, FUEL_SLOT_STACK - int(slot["count"]))
			slot["count"] = int(slot["count"]) + n
			added += n
	for slot in fuel_slots:
		if added >= available:
			break
		if str(slot["item_id"]) == "" or int(slot["count"]) <= 0:
			var n: int = mini(available - added, FUEL_SLOT_STACK)
			slot["item_id"] = item_id
			slot["count"] = n
			added += n
	if added > 0:
		inv.remove_item(item_id, added)
		# Если печь стояла без топлива — разжигаем сразу.
		if fuel_burn_left <= 0.0:
			_light_next_fuel()
	return added

## Забирает содержимое топливного слота обратно в инвентарь. Возвращает количество.
func take_fuel_from_slot(slot_index: int, inv: Node) -> int:
	if not has_fuel_slots or inv == null or slot_index < 0 or slot_index >= fuel_slots.size():
		return 0
	var slot: Dictionary = fuel_slots[slot_index]
	var count: int = int(slot["count"])
	if count <= 0:
		return 0
	var back: int = count
	if inv.has_method("get_max_addable"):
		back = int(inv.get_max_addable(str(slot["item_id"]), count))
	if back <= 0 or not inv.add_item(str(slot["item_id"]), back):
		return 0
	slot["count"] = int(slot["count"]) - back
	if int(slot["count"]) <= 0:
		slot["item_id"] = ""
		if active_fuel_slot == slot_index:
			# Горевшая единица была из этого слота — ищем следующее топливо.
			active_fuel_slot = -1
			fuel_burn_left = 0.0
			_light_next_fuel()
	return back

## Разжигает следующую единицу топлива (сначала слот, где горело, затем по порядку).
## false — топлива нигде нет.
func _light_next_fuel() -> bool:
	if not has_fuel_slots:
		return true
	var order: Array[int] = []
	if active_fuel_slot >= 0 and active_fuel_slot < fuel_slots.size():
		order.append(active_fuel_slot)
	for i in fuel_slots.size():
		if i != active_fuel_slot:
			order.append(i)
	for i in order:
		var slot: Dictionary = fuel_slots[i]
		if int(slot["count"]) > 0:
			slot["count"] = int(slot["count"]) - 1
			active_fuel_slot = i
			fuel_burn_left = get_fuel_burn_time(str(slot["item_id"]))
			return true
	active_fuel_slot = -1
	fuel_burn_left = 0.0
	return false
