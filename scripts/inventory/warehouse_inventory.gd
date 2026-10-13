extends Inventory
## Постоянное отдельное хранилище продукции; 20 стеков, без перегруза персонажа.
const CAPACITY := 20
func _ready() -> void:
	items.clear(); tools.clear(); equipped_tool=''
	max_slots=CAPACITY; base_max_weight=1000000.0
	set_physics_process(false)
func recalculate_capacity() -> void:
	max_slots=CAPACITY
func item_uses_slots(_id: String) -> bool:
	return true
static func accepts(id: String) -> bool:
	var data: Dictionary=ItemDB.get_item(id)
	return not data.is_empty() and data.get('category','') not in ['tool','equipment']
func get_max_addable(id: String, amount: int) -> int:
	return super.get_max_addable(id,amount) if accepts(id) else 0
func add_item(id: String, amount: int) -> bool:
	return super.add_item(id,amount) if accepts(id) else false
func export_state() -> Dictionary:
	get_slot_cells() # reconcile stable cell positions before saving
	var positive: Dictionary={}
	for id in items:
		if int(items[id])>0: positive[id]=int(items[id])
	return {'items':positive,'slot_layout':slot_layout.duplicate()}
func restore_state(data: Dictionary) -> void:
	# Caller validates the whole save before mutating any world object.
	items=data.get('items',{}).duplicate(true)
	max_slots=CAPACITY
	set_slot_layout(data.get('slot_layout',[]))
	_weight_dirty=true
	inventory_updated.emit()
static func is_valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get('items',{}) is Dictionary or not data.get('slot_layout',[]) is Array: return false
	var used:=0
	for id in data.get('items',{}):
		var n: Variant=data['items'][id]
		if not id is String or not accepts(id): return false
		if typeof(n) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(n)) or n<0 or n!=floor(float(n)): return false
		var item: Dictionary=ItemDB.get_item(id)
		var stack: int=maxi(1,int(item.get('max_stack',99 if item.get('stackable',true) else 1)))
		if n>CAPACITY*stack: return false
		used+=ceili(float(n)/stack)
		if used>CAPACITY: return false
	var layout: Array=data.get('slot_layout',[])
	if layout.size()>CAPACITY: return false
	for id in layout:
		if not id is String or (id!='' and not accepts(id)): return false
	return true
