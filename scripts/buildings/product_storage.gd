extends RepairableBuilding
## Готовый амбар (стадия 2+) имеет отдельное хранилище, не карманы игрока.
const Warehouse = preload("res://scripts/inventory/warehouse_inventory.gd")
const ItemDBScript = preload("res://scripts/inventory/item_db.gd")

const MAX_FERMENTATION_SLOTS: int = 4

signal fermentation_updated()

@onready var storage_inventory: Warehouse = $StorageInventory

## Слоты брожения на складе: бочки для пива, вина и браги
var fermentation_slots: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	_init_fermentation_slots()
	set_process(true)

func _init_fermentation_slots() -> void:
	if fermentation_slots.is_empty():
		for i in range(MAX_FERMENTATION_SLOTS):
			fermentation_slots.append({
				"status": "idle",
				"input_item": "",
				"output_item": "",
				"count": 0,
				"output_count": 0,
				"timer": 0.0,
				"duration": 50.0
			})

func _process(delta: float) -> void:
	if not is_storage_ready():
		return
	var changed: bool = false
	for slot in fermentation_slots:
		if slot.get("status", "") == "fermenting":
			slot["timer"] = float(slot.get("timer", 0.0)) + delta
			if slot["timer"] >= float(slot.get("duration", 50.0)):
				slot["timer"] = float(slot.get("duration", 50.0))
				slot["status"] = "ready"
				changed = true
	if changed:
		fermentation_updated.emit()

func is_storage_ready() -> bool:
	return current_stage >= 2

func start_fermentation(slot_idx: int, item_id: String, count: int, from_inv: Node) -> bool:
	if not is_storage_ready() or slot_idx < 0 or slot_idx >= fermentation_slots.size():
		return false
	var slot: Dictionary = fermentation_slots[slot_idx]
	if slot.get("status", "") != "idle":
		return false
	if not ItemDBScript.is_fermentable(item_id):
		return false
	if from_inv == null or from_inv.get_item_count(item_id) < count or count <= 0:
		return false
	
	var data: Dictionary = ItemDBScript.get_fermentation_output(item_id)
	if data.is_empty():
		return false
	
	if not from_inv.remove_item(item_id, count):
		return false
	
	slot["status"] = "fermenting"
	slot["input_item"] = item_id
	slot["output_item"] = data.get("output", "")
	slot["count"] = count
	slot["output_count"] = int(data.get("count", 2)) * count
	slot["timer"] = 0.0
	slot["duration"] = float(data.get("duration", 50.0))
	fermentation_updated.emit()
	return true

func collect_fermentation(slot_idx: int, to_inv: Node) -> int:
	if slot_idx < 0 or slot_idx >= fermentation_slots.size():
		return 0
	var slot: Dictionary = fermentation_slots[slot_idx]
	if slot.get("status", "") != "ready":
		return 0
	if to_inv == null:
		return 0
	
	var out_id: String = slot.get("output_item", "")
	var out_count: int = int(slot.get("output_count", 0))
	if out_id == "" or out_count <= 0:
		return 0
	
	var can_take: int = to_inv.get_max_addable(out_id, out_count)
	if can_take <= 0:
		return 0
	
	var added: bool = to_inv.add_item(out_id, can_take)
	if not added:
		return 0
	
	var remaining: int = out_count - can_take
	if remaining <= 0:
		slot["status"] = "idle"
		slot["input_item"] = ""
		slot["output_item"] = ""
		slot["count"] = 0
		slot["output_count"] = 0
		slot["timer"] = 0.0
	else:
		slot["output_count"] = remaining
	
	fermentation_updated.emit()
	return can_take

func cancel_fermentation(slot_idx: int, return_inv: Node = null) -> bool:
	if slot_idx < 0 or slot_idx >= fermentation_slots.size():
		return false
	var slot: Dictionary = fermentation_slots[slot_idx]
	if slot.get("status", "") != "fermenting":
		return false
	
	var inp_id: String = slot.get("input_item", "")
	var inp_count: int = int(slot.get("count", 0))
	if return_inv and inp_id != "" and inp_count > 0:
		return_inv.add_item(inp_id, inp_count)
	
	slot["status"] = "idle"
	slot["input_item"] = ""
	slot["output_item"] = ""
	slot["count"] = 0
	slot["output_count"] = 0
	slot["timer"] = 0.0
	fermentation_updated.emit()
	return true

func export_fermentation_state() -> Array:
	return fermentation_slots.duplicate(true)

func restore_fermentation_state(data: Array) -> void:
	_init_fermentation_slots()
	for i in range(mini(data.size(), fermentation_slots.size())):
		if data[i] is Dictionary:
			fermentation_slots[i] = (data[i] as Dictionary).duplicate(true)
	fermentation_updated.emit()

func deposit(from: Inventory, id: String, amount: int) -> int:
	return _transfer(from,storage_inventory,id,amount)
func withdraw(to: Inventory, id: String, amount: int) -> int:
	return _transfer(storage_inventory,to,id,amount)
func _transfer(source: Inventory, dest: Inventory, id: String, amount: int) -> int:
	if not is_storage_ready() or source==null or dest==null or source==dest or amount<=0: return 0
	if not Warehouse.accepts(id): return 0
	var n:=mini(source.get_item_count(id),dest.get_max_addable(id,amount))
	if n<=0 or not source.remove_item(id,n): return 0
	if not dest.add_item(id,n):
		source.add_item(id,n)
		return 0
	return n
func _init_default_stages() -> void:
	super._init_default_stages()
	stages_config[0]['description']='Пробита деревянная кровля, ворота повреждены, припасы завалены обломками.'
	stages_config[2]['perks']='📦 Отдельный инвентарь на 20 ячеек. 🍺 Бродильный цех (4 бочки). Бонус к весу рюкзака +20 кг.'
	stages_config[3]['description']='Укреплённый амбар с освещением и фасадным подъёмником.'
	stages_config[3]['perks']='📦 Отдельный инвентарь на 20 ячеек. 🍺 Бродильный цех (4 бочки). Бонус к весу рюкзака +35 кг.'

