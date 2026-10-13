class_name CookingProgress
extends RefCounted

## Вехи Главы 2 «Первый дым» (мастер-план 2.4) и учёт готовки.
## Статический трекер: считает приготовленные блюда с качеством, собранные
## грибы, восстановленные станки и построенную печь-кухню. Всё, что нужно для
## вех, копилось бы иначе в разных местах (костёр, кусты, станки), а список
## вех должен быть одним и сохраняться одной секцией.
##
## Вехи:
## 1. Приготовить 5 разных блюд на костре;
## 2. Найти и собрать 10 грибов;
## 3. Отремонтировать дробилку;
## 4. Отремонтировать плавильню;
## 5. Построить печь-кухню.

## Качество блюда (мастер-план 5.4). Разные станки дают разное качество одного
## и того же блюда: костёр — обычное, печь-кухня — хорошее и отличное.
const QUALITY_PLAIN: String = "обычное"
const QUALITY_GOOD: String = "хорошее"
const QUALITY_GREAT: String = "отличное"
const QUALITY_MASTER: String = "мастерское"
const QUALITY_ORDER: Array[String] = [QUALITY_PLAIN, QUALITY_GOOD, QUALITY_GREAT, QUALITY_MASTER]

const DISHES_TARGET: int = 5
const MUSHROOMS_TARGET: int = 10
## Станки, которые нужно восстановить в Главе 2 (плюс печь-кухня — отдельно).
const REBUILD_TARGETS: Array[String] = ["crusher", "furnace"]
const KITCHEN_ID: String = "kitchen_stove"

## item_id → { count, quality }
static var dishes: Dictionary = {}
## Сколько всего грибов собрано за игру (для вехи).
static var mushrooms_collected: int = 0
## Какие станки восстановлены: machine_type → true.
static var rebuilt_machines: Dictionary = {}

static func reset() -> void:
	dishes.clear()
	mushrooms_collected = 0
	rebuilt_machines.clear()

# --- Учёт ----------------------------------------------------------------------

## Записывает приготовленное блюдо. Повторная готовка того же блюда не увеличивает
## счётчик «разных блюд», но обновляет количество и качество.
static func register_dish(item_id: String, amount: int = 1, quality: String = QUALITY_PLAIN) -> void:
	if item_id == "":
		return
	var entry: Dictionary = dishes.get(item_id, {"count": 0, "quality": QUALITY_PLAIN})
	entry["count"] = int(entry.get("count", 0)) + maxi(0, amount)
	# Качество блюда не ухудшается, если его снова приготовили на лучшем станке.
	if QUALITY_ORDER.find(quality) > QUALITY_ORDER.find(str(entry.get("quality", QUALITY_PLAIN))):
		entry["quality"] = quality
	dishes[item_id] = entry

static func register_mushrooms(amount: int) -> void:
	mushrooms_collected += maxi(0, amount)

static func register_rebuild(machine_type: String) -> void:
	if machine_type != "":
		rebuilt_machines[machine_type] = true

static func get_dish_count() -> int:
	return dishes.size()

static func get_dish(item_id: String) -> Dictionary:
	return dishes.get(item_id, {})

static func has_dish(item_id: String) -> bool:
	return dishes.has(item_id)

static func is_machine_rebuilt(machine_type: String) -> bool:
	return bool(rebuilt_machines.get(machine_type, false))

## Строки приготовленного: [{ id, name, icon, count, quality }].
static func get_dish_list() -> Array[Dictionary]:
	var ItemDB = load("res://scripts/inventory/item_db.gd")
	var out: Array[Dictionary] = []
	for item_id in dishes.keys():
		var entry: Dictionary = dishes[item_id]
		out.append({
			"id": str(item_id),
			"name": ItemDB.get_item_name(str(item_id)),
			"icon": ItemDB.get_item_icon(str(item_id)),
			"count": int(entry.get("count", 0)),
			"quality": str(entry.get("quality", QUALITY_PLAIN))
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out

# --- Вехи ----------------------------------------------------------------------

## Текущее состояние вех Главы 2.
static func evaluate(_world: Node = null) -> Dictionary:
	var tasks: Array[Dictionary] = []
	tasks.append({
		"id": "dishes",
		"title": "Приготовить %d разных блюд на костре (%d/%d)" % [DISHES_TARGET, mini(get_dish_count(), DISHES_TARGET), DISHES_TARGET],
		"icon": "🍲",
		"done": get_dish_count() >= DISHES_TARGET
	})
	tasks.append({
		"id": "mushrooms",
		"title": "Найти и собрать %d грибов (%d/%d)" % [MUSHROOMS_TARGET, mini(mushrooms_collected, MUSHROOMS_TARGET), MUSHROOMS_TARGET],
		"icon": "🍄",
		"done": mushrooms_collected >= MUSHROOMS_TARGET
	})
	tasks.append({
		"id": "crusher",
		"title": "Восстановить дробилку",
		"icon": "⚙️",
		"done": is_machine_rebuilt("crusher")
	})
	tasks.append({
		"id": "furnace",
		"title": "Восстановить плавильню",
		"icon": "🔥",
		"done": is_machine_rebuilt("furnace")
	})
	tasks.append({
		"id": "kitchen",
		"title": "Построить печь-кухню",
		"icon": "🍳",
		"done": is_machine_rebuilt(KITCHEN_ID)
	})

	var completed: int = 0
	for t in tasks:
		if t["done"]:
			completed += 1
	var total: int = tasks.size()
	return {
		"is_complete": completed == total,
		"progress_pct": int(float(completed) / float(total) * 100.0) if total > 0 else 0,
		"completed_count": completed,
		"total_count": total,
		"tasks": tasks
	}

# --- Сохранения ----------------------------------------------------------------

static func get_save_state() -> Dictionary:
	return {
		"dishes": dishes.duplicate(true),
		"mushrooms_collected": mushrooms_collected,
		"rebuilt_machines": rebuilt_machines.duplicate(true)
	}

static func apply_save_state(state: Dictionary) -> void:
	reset()
	var saved_dishes: Dictionary = state.get("dishes", {})
	for item_id in saved_dishes.keys():
		var entry: Dictionary = saved_dishes[item_id]
		if entry is Dictionary:
			dishes[str(item_id)] = {
				"count": maxi(0, int(entry.get("count", 0))),
				"quality": _safe_quality(str(entry.get("quality", QUALITY_PLAIN)))
			}
	mushrooms_collected = maxi(0, int(state.get("mushrooms_collected", 0)))
	var saved_rebuilt: Dictionary = state.get("rebuilt_machines", {})
	for machine_type in saved_rebuilt.keys():
		if bool(saved_rebuilt[machine_type]):
			rebuilt_machines[str(machine_type)] = true

static func _safe_quality(quality: String) -> String:
	return quality if QUALITY_ORDER.has(quality) else QUALITY_PLAIN

static func is_valid_save_state(state: Dictionary) -> bool:
	if not state is Dictionary:
		return false
	var saved_dishes: Dictionary = state.get("dishes", {})
	if saved_dishes.size() > 256:
		return false
	for item_id in saved_dishes.keys():
		if not item_id is String:
			return false
		var entry = saved_dishes[item_id]
		if not entry is Dictionary:
			return false
		if not (entry.get("count") is int or entry.get("count") is float):
			return false
		if float(entry.get("count", 0)) < 0.0:
			return false
		if entry.has("quality") and not QUALITY_ORDER.has(str(entry["quality"])):
			return false
	if state.has("mushrooms_collected"):
		var value = state["mushrooms_collected"]
		if not (value is int or value is float) or float(value) < 0.0:
			return false
	var saved_rebuilt: Dictionary = state.get("rebuilt_machines", {})
	if saved_rebuilt.size() > 64:
		return false
	for machine_type in saved_rebuilt.keys():
		if not machine_type is String:
			return false
	return true