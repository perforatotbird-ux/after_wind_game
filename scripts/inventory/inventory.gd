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
	"street_lamp_item": 0
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

func is_tool_equipped(tool_id: String) -> bool:
	return equipped_tool == tool_id

func get_equipped_tool() -> String:
	return equipped_tool

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
