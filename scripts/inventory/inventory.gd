class_name Inventory
extends Node

## Компонент инвентаря игрока (Разделы 14, 15, 66, 67).
##
## Модель вместимости (подробно — docs/DOCUMENTATION.md, «Инвентарь и грузоподъёмность»):
## * Рюкзак задаёт число слотов (max_slots) и допустимый вес (max_weight).
## * Стек занимает ceil(количество / max_stack) слотов; нестакаемые предметы
##   (max_stack = 1 или stackable = false) занимают слот на штуку. Инструменты и
##   снаряжение висят на поясе и слотов рюкзака не занимают.
## * Нехватка слотов — жёсткий лимит: предмет не подбирается (сигнал item_rejected).
## * Вес — мягкий лимит: выше max_weight — перегруз (замедление, нет спринта,
##   повышенный расход энергии при движении); от max_weight * OVERLOAD_CRITICAL_RATIO —
##   критический перегруз (персонаж обездвижен).
## * Восстановленные склад и дом дают бонус к допустимому весу (set_weight_bonus).
## * Окно рюкзака показывает каждый стек отдельной клеткой (get_slot_stacks);
##   предметы можно выбросить на землю (drop_item + DroppedItem).

const ItemDB = preload("res://scripts/inventory/item_db.gd")

enum LoadState { NORMAL, OVERLOADED, CRITICAL }

## Порог критического перегруза относительно допустимого веса.
const OVERLOAD_CRITICAL_RATIO: float = 1.25
## Множитель скорости ходьбы при перегрузе.
const OVERLOAD_SPEED_MULT: float = 0.6
## Дополнительный расход энергии (ед./сек) при движении с перегрузом.
const OVERLOAD_MOVE_ENERGY_PER_SEC: float = 2.5
## Размер стека по умолчанию, если в ItemDB не задан max_stack.
const DEFAULT_MAX_STACK: int = 99
## Допустимый вес рюкзаков, если в ItemDB не задан ключ max_weight.
const BACKPACK_WEIGHT_LIMITS: Dictionary = {
	"backpack": 50.0,
	"large_backpack": 75.0
}
const DEFAULT_SLOTS: int = 12
const DEFAULT_MAX_WEIGHT: float = 50.0

signal inventory_updated()
signal item_added(item_id: String, amount: int, new_total: int)
signal item_rejected(item_id: String, amount: int, reason: String)
signal tool_changed(tool_id: String, tool_name: String)
signal credits_changed(total: int)
signal load_state_changed(state: int)

@export var max_slots: int = DEFAULT_SLOTS
## Допустимый вес самого рюкзака (без бонусов зданий).
@export var base_max_weight: float = DEFAULT_MAX_WEIGHT

## Бонусы к допустимому весу: { источник: кг }, например { "building:storage": 20.0 }.
var weight_bonuses: Dictionary = {}

## Итоговый допустимый вес = рюкзак + бонусы. Присваивание меняет базу рюкзака,
## сохраняя бонусы (обратная совместимость со старым кодом и тестами).
var max_weight: float:
	get:
		return base_max_weight + get_weight_bonus_total()
	set(value):
		base_max_weight = maxf(0.0, value - get_weight_bonus_total())

## Финансы
var credits: int = 0

## Доступные инструменты (хотбар слоты 1-5)
var tools: Array[String] = ["axe", "pickaxe", "shovel", "bucket", "backpack"]
var equipped_tool: String = "axe"

## Словарь хранения предметов { item_id: int }
var items: Dictionary = {
	"wood": 0,
	"stone": 0,
	"clay": 0,
	"sand": 0,
	"water": 0,
	"stone_dust": 0,
	"sawdust": 0,
	"poor_brick": 0,
	"fuel_briquette": 0,
	"fired_brick": 0,
	"glass": 0,
	"metal_scrap": 0,
	"iron_ingot": 0,
	"clean_water": 0,
	"bottled_water": 0,
	"seeds_carrot": 0,
	"seeds_potato": 0,
	"seeds_wheat": 0,
	"carrot": 0,
	"potato": 0,
	"wheat": 0,
	"bread": 0,
	"fertilizer": 0,
	"copper_wire": 0,
	"iron_plate": 0,
	"gear": 0,
	"battery_cell": 0,
	"street_lamp_item": 0,
	# --- Компоненты и инструменты Lv.2 (Этап 11) ---
	"wooden_handle": 0,
	"bolt": 0,
	"fabric": 0,
	"leather_strap": 0,
	"iron_axe": 0,
	"iron_pickaxe": 0,
	"iron_shovel": 0,
	"reinforced_bucket": 0,
	"large_backpack": 0
}

var _load_state: int = LoadState.NORMAL
var _base_walk_speed: float = -1.0
var _base_sprint_speed: float = -1.0

func clear() -> void:
	for k in items.keys():
		items[k] = 0
	_update_load_state()
	inventory_updated.emit()

func _ready() -> void:
	# Начальный инструмент по умолчанию
	call_deferred("_notify_tool_changed")

func _physics_process(delta: float) -> void:
	# Предметы могут меняться напрямую (загрузка, тесты) — состояние сверяем каждый тик.
	_update_load_state()
	if _load_state != LoadState.OVERLOADED:
		return
	var owner_body = get_parent()
	if owner_body is CharacterBody3D and owner_body.has_method("consume_energy"):
		var horizontal: Vector3 = owner_body.velocity
		horizontal.y = 0.0
		if horizontal.length_squared() > 0.04:
			owner_body.consume_energy(OVERLOAD_MOVE_ENERGY_PER_SEC * delta)

func _notify_tool_changed() -> void:
	var tool_data: Dictionary = ItemDB.get_item(equipped_tool)
	var t_name: String = tool_data.get("name", equipped_tool)
	tool_changed.emit(equipped_tool, t_name)

func equip_tool(tool_id: String) -> void:
	if equipped_tool == tool_id:
		return
	if tools.has(tool_id):
		equipped_tool = tool_id
		var tool_data: Dictionary = ItemDB.get_item(equipped_tool)
		var t_name: String = tool_data.get("name", equipped_tool)
		tool_changed.emit(equipped_tool, t_name)

func equip_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < tools.size():
		equip_tool(tools[slot_index])

## Инструменты пояса, между которыми листает колесо мыши. Рюкзак пропускается:
## его не берут в руки, слот 5 открывает окно инвентаря.
func get_cyclable_tools() -> Array[String]:
	var result: Array[String] = []
	for t in tools:
		if t == "backpack" or ItemDB.get_item(t).get("tool_type", "") == "backpack":
			continue
		result.append(t)
	return result

## Колесо мыши: следующий (direction > 0) или предыдущий (direction < 0)
## инструмент по кругу. Возвращает id инструмента в руках после переключения.
func cycle_tool(direction: int) -> String:
	var cyclable: Array[String] = get_cyclable_tools()
	if cyclable.is_empty() or direction == 0:
		return equipped_tool
	var idx: int = cyclable.find(equipped_tool)
	var next_idx: int = 0
	if idx == -1:
		next_idx = 0 if direction > 0 else cyclable.size() - 1
	else:
		next_idx = posmod(idx + signi(direction), cyclable.size())
	equip_tool(cyclable[next_idx])
	return equipped_tool

func is_tool_equipped(tool_id_or_type: String) -> bool:
	if equipped_tool == tool_id_or_type:
		return true
	var tool_data: Dictionary = ItemDB.get_item(equipped_tool)
	return tool_data.get("tool_type", "") == tool_id_or_type

func get_equipped_tool() -> String:
	return equipped_tool

func get_tool_level(tool_type: String = "") -> int:
	if tool_type.is_empty():
		var data: Dictionary = ItemDB.get_item(equipped_tool)
		return data.get("level", 1)
	
	# Сначала проверяем текущий экипированный инструмент
	var eq_data: Dictionary = ItemDB.get_item(equipped_tool)
	if eq_data.get("tool_type", "") == tool_type:
		return eq_data.get("level", 1)
	
	# Ищем наивысший уровень среди инструментов в поясе
	var max_lvl: int = 1
	for t in tools:
		var d: Dictionary = ItemDB.get_item(t)
		if d.get("tool_type", "") == tool_type:
			max_lvl = maxi(max_lvl, d.get("level", 1))
	return max_lvl

func upgrade_tool(tool_id: String) -> bool:
	var item_data: Dictionary = ItemDB.get_item(tool_id)
	if item_data.is_empty():
		return false
	
	var t_type: String = item_data.get("tool_type", "")
	if t_type.is_empty():
		return false
	
	if t_type == "backpack":
		var b_idx: int = tools.find("backpack")
		if b_idx != -1:
			tools[b_idx] = tool_id
		elif not tools.has(tool_id):
			tools.append(tool_id)
		if equipped_tool == "backpack":
			equipped_tool = tool_id
		recalculate_capacity()
		inventory_updated.emit()
		_notify_tool_changed()
		return true
	
	# Замена в списке инструментов
	var found_idx: int = -1
	for i in range(tools.size()):
		var cur_tool: String = tools[i]
		if cur_tool == t_type or ItemDB.get_item(cur_tool).get("tool_type", "") == t_type:
			found_idx = i
			break
	
	if found_idx != -1:
		tools[found_idx] = tool_id
	else:
		tools.append(tool_id)
	
	# Если сейчас в руках старый инструмент того же типа, автоматически переключаем
	var cur_data: Dictionary = ItemDB.get_item(equipped_tool)
	if equipped_tool == t_type or cur_data.get("tool_type", "") == t_type:
		equipped_tool = tool_id
		_notify_tool_changed()
	
	inventory_updated.emit()
	return true

# ---------------------------------------------------------------------------
# Вместимость рюкзака
# ---------------------------------------------------------------------------

## Пересчитывает слоты и базовый вес по лучшему рюкзаку на поясе.
func recalculate_capacity() -> void:
	var best_slots: int = DEFAULT_SLOTS
	var best_weight: float = DEFAULT_MAX_WEIGHT
	var best_level: int = 0
	for t in tools:
		var d: Dictionary = ItemDB.get_item(t)
		if d.get("tool_type", "") != "backpack":
			continue
		var lvl: int = int(d.get("level", 1))
		if lvl < best_level:
			continue
		best_level = lvl
		best_slots = int(d.get("slots", DEFAULT_SLOTS))
		best_weight = float(d.get("max_weight", BACKPACK_WEIGHT_LIMITS.get(t, DEFAULT_MAX_WEIGHT)))
	max_slots = best_slots
	base_max_weight = best_weight
	_update_load_state()

## Устанавливает (или снимает при kg <= 0) бонус к допустимому весу от источника.
func set_weight_bonus(source: String, kg: float) -> void:
	if kg <= 0.0:
		weight_bonuses.erase(source)
	else:
		weight_bonuses[source] = kg
	_update_load_state()
	inventory_updated.emit()

func get_weight_bonus_total() -> float:
	var total: float = 0.0
	for k in weight_bonuses:
		total += float(weight_bonuses[k])
	return total

## Занимает ли предмет слоты рюкзака (инструменты и снаряжение — на поясе).
func item_uses_slots(item_id: String) -> bool:
	var cat: String = ItemDB.get_item(item_id).get("category", "")
	return cat not in ["tool", "equipment"]

func get_max_stack(item_id: String) -> int:
	var data: Dictionary = ItemDB.get_item(item_id)
	if data.has("max_stack"):
		return maxi(1, int(data["max_stack"]))
	if data.get("stackable", true) == false:
		return 1
	return DEFAULT_MAX_STACK

func get_slots_for(item_id: String, count: int) -> int:
	if count <= 0 or not item_uses_slots(item_id):
		return 0
	return ceili(float(count) / float(get_max_stack(item_id)))

func get_used_slots() -> int:
	var used: int = 0
	for item_id in items.keys():
		used += get_slots_for(item_id, int(items[item_id]))
	return used

func get_free_slots() -> int:
	return maxi(0, max_slots - get_used_slots())

## Хватит ли слотов, чтобы положить amount предметов item_id.
func can_add_item(item_id: String, amount: int) -> bool:
	if amount <= 0 or ItemDB.get_item(item_id).is_empty():
		return false
	var current: int = int(items.get(item_id, 0))
	var extra_slots: int = get_slots_for(item_id, current + amount) - get_slots_for(item_id, current)
	return extra_slots <= 0 or extra_slots <= get_free_slots()

## Сколько штук item_id (не больше amount) поместится в рюкзак: остаток
## неполных стеков + свободные слоты. Для частичного подбора и выдачи продукции.
func get_max_addable(item_id: String, amount: int) -> int:
	if amount <= 0 or ItemDB.get_item(item_id).is_empty():
		return 0
	if not item_uses_slots(item_id):
		return amount
	var current: int = int(items.get(item_id, 0))
	var stack: int = get_max_stack(item_id)
	var capacity: int = (get_slots_for(item_id, current) + get_free_slots()) * stack - current
	return clampi(capacity, 0, amount)

## Раскладка рюкзака по клеткам окна инвентаря: каждый стек — отдельная клетка
## { "item_id": String, "count": int }. Порядок стабилен (порядок ключей items),
## полные стеки идут первыми. Инструменты пояса в раскладку не входят.
func get_slot_stacks() -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for item_id in items.keys():
		var count: int = int(items[item_id])
		if count <= 0 or not item_uses_slots(item_id):
			continue
		var stack: int = get_max_stack(item_id)
		while count > 0:
			var n: int = mini(count, stack)
			cells.append({"item_id": item_id, "count": n})
			count -= n
	return cells

## Вес одной штуки предмета, кг.
func get_item_weight(item_id: String) -> float:
	return float(ItemDB.get_item(item_id).get("weight", 1.0))

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items.keys():
		var count: int = items[item_id]
		if count > 0:
			var data: Dictionary = ItemDB.get_item(item_id)
			var w: float = data.get("weight", 1.0)
			total += w * count
	return total

func get_load_ratio() -> float:
	var limit: float = max_weight
	if limit <= 0.0:
		return INF if get_total_weight() > 0.0 else 0.0
	return get_total_weight() / limit

func get_load_state() -> int:
	var ratio: float = get_load_ratio()
	if ratio >= OVERLOAD_CRITICAL_RATIO:
		return LoadState.CRITICAL
	if ratio > 1.0:
		return LoadState.OVERLOADED
	return LoadState.NORMAL

func is_overloaded() -> bool:
	return get_load_state() != LoadState.NORMAL

func _update_load_state() -> void:
	var state: int = get_load_state()
	if state == _load_state:
		return
	_load_state = state
	_apply_load_penalty(state)
	load_state_changed.emit(state)
	var owner_body = get_parent()
	if owner_body and owner_body.has_method("notify"):
		match state:
			LoadState.NORMAL:
				owner_body.notify("🎒 Нагрузка в норме.")
			LoadState.OVERLOADED:
				owner_body.notify("⚠️ Перегруз: %.0f/%.0f кг — вы идёте медленнее и быстрее устаёте." % [get_total_weight(), max_weight])
			LoadState.CRITICAL:
				owner_body.notify("⛔ Критический перегруз: %.0f/%.0f кг — вы не можете двигаться. Выложите часть груза." % [get_total_weight(), max_weight])

## Штраф к скорости применяется к персонажу-владельцу через его walk_speed / sprint_speed.
func _apply_load_penalty(state: int) -> void:
	var owner_body = get_parent()
	if owner_body == null or not ("walk_speed" in owner_body and "sprint_speed" in owner_body):
		return
	if _base_walk_speed < 0.0:
		_base_walk_speed = owner_body.walk_speed
		_base_sprint_speed = owner_body.sprint_speed
	match state:
		LoadState.NORMAL:
			owner_body.walk_speed = _base_walk_speed
			owner_body.sprint_speed = _base_sprint_speed
		LoadState.OVERLOADED:
			# Спринт с перегрузом не даёт прироста скорости.
			owner_body.walk_speed = _base_walk_speed * OVERLOAD_SPEED_MULT
			owner_body.sprint_speed = owner_body.walk_speed
		LoadState.CRITICAL:
			owner_body.walk_speed = 0.0
			owner_body.sprint_speed = 0.0

# ---------------------------------------------------------------------------
# Предметы
# ---------------------------------------------------------------------------

func add_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	
	var item_data: Dictionary = ItemDB.get_item(item_id)
	if item_data.is_empty():
		push_warning("Попытка добавить неизвестный предмет: " + item_id)
		return false
	
	if not can_add_item(item_id, amount):
		item_rejected.emit(item_id, amount, "no_slots")
		return false
	
	var current: int = items.get(item_id, 0)
	var new_amount: int = current + amount
	items[item_id] = new_amount
	
	# Если получен инструмент или снаряжение — автоматически активируем оснастку/улучшение
	var cat: String = item_data.get("category", "")
	if cat in ["tool", "equipment"]:
		upgrade_tool(item_id)
	
	item_added.emit(item_id, amount, new_amount)
	_update_load_state()
	inventory_updated.emit()
	return true

func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0 or not items.has(item_id):
		return false
	
	var current: int = items.get(item_id, 0)
	if current < amount:
		return false
	
	items[item_id] = current - amount
	_update_load_state()
	inventory_updated.emit()
	return true

## Убирает предметы из рюкзака, чтобы выбросить их на землю (см. DroppedItem).
## Инструменты и снаряжение с пояса не выбрасываются.
func drop_item(item_id: String, amount: int) -> bool:
	if ItemDB.get_item(item_id).is_empty() or not item_uses_slots(item_id):
		return false
	return remove_item(item_id, amount)

func get_item_count(item_id: String) -> int:
	return items.get(item_id, 0)

func add_credits(amount: int) -> void:
	if amount > 0:
		credits += amount
		credits_changed.emit(credits)

func spend_credits(amount: int) -> bool:
	if amount <= 0:
		return true
	if credits >= amount:
		credits -= amount
		credits_changed.emit(credits)
		return true
	return false
