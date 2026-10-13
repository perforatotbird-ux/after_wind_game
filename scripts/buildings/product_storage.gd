extends RepairableBuilding
## Готовый амбар (стадия 2+) имеет отдельное хранилище, не карманы игрока.
const Warehouse = preload("res://scripts/inventory/warehouse_inventory.gd")
@onready var storage_inventory: Warehouse = $StorageInventory
func is_storage_ready() -> bool:
	return current_stage>=2
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
	stages_config[2]['perks']='📦 Отдельный инвентарь на 20 ячеек. Бонус к весу рюкзака +20 кг.'
	stages_config[3]['description']='Укреплённый амбар с освещением и фасадным подъёмником.'
	stages_config[3]['perks']='📦 Отдельный инвентарь на 20 ячеек. Бонус к весу рюкзака +35 кг.'
