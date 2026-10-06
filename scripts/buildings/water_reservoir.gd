class_name WaterReservoir
extends "res://scripts/interaction/interactable.gd"

## Водный резервуар / Цистерна чистой воды (Разделы 9, 13, 17 дизайн-документа)
## Накапливает воду, позволяет утолять жажду прямо во дворе базы

const ItemDB = preload("res://scripts/inventory/item_db.gd")

signal water_level_changed(current: int, max_val: int)

@export var max_capacity: int = 20
@export var current_water: int = 6
@export var passive_replenish_time: float = 45.0

var _timer: float = 0.0

func _ready() -> void:
	super._ready()
	object_name = "Резервуар чистой воды"
	prompt_action = "Пить / Набрать"

func _process(delta: float) -> void:
	if current_water < max_capacity:
		_timer += delta
		if _timer >= passive_replenish_time:
			_timer = 0.0
			current_water = min(max_capacity, current_water + 1)
			water_level_changed.emit(current_water, max_capacity)

func get_prompt() -> String:
	return "[E] Пить из резервуара (%d/%d л)" % [current_water, max_capacity]

func _on_interacted(player: Node) -> void:
	if current_water <= 0:
		if player.has_method("notify"):
			player.notify("ℹ️ Резервуар пуст. Профильтруйте воду и пополните запас!")
		return
	
	if "thirst" in player and "max_thirst" in player:
		if player.thirst >= player.max_thirst:
			# Если игрок не хочет пить, проверяем может ли он набрать воду в инвентарь при наличии ведра
			var inv = player.get("inventory") if "inventory" in player else null
			if inv and inv.has_method("add_item"):
				current_water -= 1
				inv.add_item("clean_water", 1)
				water_level_changed.emit(current_water, max_capacity)
				if player.has_method("notify"):
					player.notify("💧 Вы набрали 1 л чистой воды в рюкзак (Остаток: %d/%d л)." % [current_water, max_capacity])
				return
			
			if player.has_method("notify"):
				player.notify("💧 Вы не хотите пить (Жажда 100%).")
			return
		
		# Утоление жажды
		current_water -= 1
		water_level_changed.emit(current_water, max_capacity)
		if player.has_method("drink_water"):
			player.drink_water(45.0, true, 5.0)
