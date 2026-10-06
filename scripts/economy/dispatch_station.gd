class_name DispatchStation
extends "res://scripts/interaction/interactable.gd"

## Станция отправки продукции (Разделы 22, 23, 24 дизайн-документа)

const ItemDB = preload("res://scripts/inventory/item_db.gd")

signal station_opened(station: Node)
signal items_sold(total_credits: int)

@export var station_name: String = "Станция отправки"

func _ready() -> void:
	super._ready()
	object_name = station_name
	prompt_action = "Открыть терминал"

func _on_interacted(_player: Node) -> void:
	station_opened.emit(self)

func sell_goods(items_to_sell: Dictionary, player: Node) -> int:
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv:
		return 0
	
	var total_earned: int = 0
	for item_id in items_to_sell.keys():
		var amount: int = items_to_sell[item_id]
		var available: int = inv.get_item_count(item_id)
		var actual_amount: int = min(amount, available)
		if actual_amount > 0:
			var price: int = ItemDB.get_sell_price(item_id)
			var revenue: int = price * actual_amount
			inv.remove_item(item_id, actual_amount)
			total_earned += revenue
	
	if total_earned > 0:
		inv.add_credits(total_earned)
		items_sold.emit(total_earned)
		if player.has_method("notify"):
			player.notify("💰 Груз успешно отправлен! Получено +%d кредитов." % total_earned)
	
	return total_earned
