class_name Inventory
extends Node

## Компонент инвентаря игрока (Разделы 14, 15, 66, 67)

const ItemDB = preload("res://scripts/inventory/item_db.gd")

signal inventory_updated()
signal item_added(item_id: String, amount: int, new_total: int)
signal tool_changed(tool_id: String, tool_name: String)
signal credits_changed(total: int)

@export var max_slots: int = 12
@export var max_weight: float = 50.0

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

func clear() -> void:
	for k in items.keys():
		items[k] = 0
	inventory_updated.emit()

func _ready() -> void:
	# Начальный инструмент по умолчанию
	call_deferred("_notify_tool_changed")

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
		max_slots = item_data.get("slots", 20)
		max_weight = 75.0
		var b_idx: int = tools.find("backpack")
		if b_idx != -1:
			tools[b_idx] = tool_id
		elif not tools.has(tool_id):
			tools.append(tool_id)
		if equipped_tool == "backpack":
			equipped_tool = tool_id
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

func add_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	
	var item_data: Dictionary = ItemDB.get_item(item_id)
	if item_data.is_empty():
		push_warning("Попытка добавить неизвестный предмет: " + item_id)
		return false
	
	var current: int = items.get(item_id, 0)
	var new_amount: int = current + amount
	items[item_id] = new_amount
	
	# Если получен инструмент или снаряжение — автоматически активируем оснастку/улучшение
	var cat: String = item_data.get("category", "")
	if cat in ["tool", "equipment"]:
		upgrade_tool(item_id)
	
	item_added.emit(item_id, amount, new_amount)
	inventory_updated.emit()
	return true

func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0 or not items.has(item_id):
		return false
	
	var current: int = items.get(item_id, 0)
	if current < amount:
		return false
	
	items[item_id] = current - amount
	inventory_updated.emit()
	return true

func get_item_count(item_id: String) -> int:
	return items.get(item_id, 0)

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items.keys():
		var count: int = items[item_id]
		if count > 0:
			var data: Dictionary = ItemDB.get_item(item_id)
			var w: float = data.get("weight", 1.0)
			total += w * count
	return total

func get_used_slots() -> int:
	var count: int = 0
	for item_id in items.keys():
		if items[item_id] > 0:
			count += 1
	return count

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
