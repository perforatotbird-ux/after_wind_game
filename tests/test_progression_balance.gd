extends SceneTree
## Баланс Главы 1: рецепты не мгновенные, все промежуточные предметы куда-то идут,
## а путь до «Base Restored» требует ощутимой, но конечной работы (не бесконечный гринд).
## Решатель раскладывает цели на сырьё по выбранным рецептам и считает время станков.
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")
const Building = preload("res://scripts/buildings/repairable_building.gd")

## Каким рецептом игрок делает предмет на основном пути (остальное — сырьё).
const ROUTE: Dictionary = {
	"stone_dust": "crush_stone", "sawdust": "crush_wood", "poor_brick": "craft_brick",
	"mortar": "craft_mortar", "fuel_briquette": "craft_briquette", "iron_ingot": "smelt_iron_ore",
	"iron_plate": "craft_iron_plate", "wooden_handle": "craft_wooden_handle", "bolt": "craft_bolt",
	"iron_shovel": "upgrade_iron_shovel", "fired_brick": "smelt_brick", "glass": "smelt_glass",
	"gear": "craft_gear", "copper_wire": "craft_copper_wire",
}
var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	var inv_node: Node = Inventory.new()
	var inv_keys: Dictionary = inv_node.items.duplicate()
	inv_node.free()
	var consumed: Dictionary = {}
	for r in RecipeDB.RECIPES.values():
		var d: float = float(r["duration"])
		check(d >= 15.0 and d <= 120.0, "%s: время цикла %.0f с вне 15–120 с" % [r["id"], d])
		for part in ["inputs", "outputs"]:
			for id in r[part]:
				check(not ItemDB.get_item(id).is_empty(), "%s: неизвестный предмет %s" % [r["id"], id])
				check(inv_keys.has(id), "%s: предмета %s нет в Inventory.items" % [r["id"], id])
		for id in r["inputs"]:
			consumed[id] = true
	for c in ContractDB.CONTRACTS:
		for id in c["requirements"]:
			consumed[id] = true
		check(int(c.get("unlock_after", -1)) >= 0, "%s: нет unlock_after" % c["id"])
	var house := Building.new()
	house.building_id = "house"
	house._init_default_stages()
	var storage := Building.new()
	storage.building_id = "storage"
	storage._init_default_stages()
	for b in [house, storage]:
		for st in b.stages_config:
			for id in st["cost_materials"]:
				consumed[id] = true
	# Промежуточные предметы должны где-то тратиться (иначе их производство — тупик).
	for id in ["stone_dust", "sawdust", "poor_brick", "mortar", "fuel_briquette", "fired_brick", "glass",
			"iron_ingot", "iron_plate", "gear", "copper_wire", "battery_cell", "street_lamp_item",
			"wooden_handle", "bolt", "fabric", "leather_strap", "clean_water", "coal", "iron_ore"]:
		check(consumed.has(id), "Предмет %s производится, но нигде не нужен" % id)
	# Волны заказов: в первой хватает заказов для победы (нужно 2).
	var wave0: int = 0
	for c in ContractDB.CONTRACTS:
		if int(c["unlock_after"]) == 0:
			wave0 += 1
	check(wave0 >= 2, "В первой волне меньше 2 заказов — победа недостижима")

	# Путь до победы: дом 2, склад 2, 2 заказа первой волны, железная лопата.
	var goal: Dictionary = {}
	var credits: int = 0
	for b in [house, storage]:
		for stage in [1, 2]:
			var st: Dictionary = b.stages_config[stage]
			credits += int(st["cost_credits"])
			_add(goal, st["cost_materials"])
	var reward: int = 0
	for cid in ["contract_fortify", "contract_fuel_reserve"]:
		var c: Dictionary = ContractDB.get_contract(cid)
		_add(goal, c["requirements"])
		reward += int(c["reward_credits"])
	goal["iron_shovel"] = 1
	check(reward >= credits, "Двух первых заказов (%d кр.) не хватает на ремонт (%d кр.)" % [reward, credits])
	var plan: Dictionary = _resolve(goal)
	var raw: Dictionary = plan["raw"]
	var machine_time: Dictionary = plan["time"]
	print("Сырьё до победы: ", raw)
	print("Время станков, с: ", machine_time)
	var total_raw: int = 0
	for id in raw:
		total_raw += int(raw[id])
	var longest: float = 0.0
	var total_time: float = 0.0
	for m in machine_time:
		longest = maxf(longest, machine_time[m])
		total_time += machine_time[m]
	print("Всего сырья: %d ед., станки суммарно %.1f мин, самый загруженный %.1f мин" % [total_raw, total_time / 60.0, longest / 60.0])
	# Ощутимо, но конечно: ~1 игровой день (сутки 24 мин, 1 игровой час = 1 мин) с параллельной работой станков.
	check(total_raw >= 80 and total_raw <= 220, "Сырья до победы %d — вне 80–220" % total_raw)
	check(longest >= 300.0 and longest <= 1500.0, "Самый загруженный станок %.0f с — вне 5–25 мин" % longest)
	check(int(raw.get("stone", 0)) <= 70, "Слишком много камня до победы: %d" % raw.get("stone", 0))
	check(raw.has("iron_ore") and raw.has("coal"), "Путь к инструменту Lv.2 не использует жилы")
	house.free()
	storage.free()
	if errors.is_empty():
		print("PASS: test_progression_balance — баланс Главы 1")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)

func _add(into: Dictionary, what: Dictionary, mult: int = 1) -> void:
	for id in what:
		into[id] = int(into.get(id, 0)) + int(what[id]) * mult

## Раскладывает потребность на циклы рецептов ROUTE; остаток — сырьё.
func _resolve(goal: Dictionary) -> Dictionary:
	var demand: Dictionary = goal.duplicate()
	var produced: Dictionary = {}
	var time: Dictionary = {}
	var changed: bool = true
	while changed:
		changed = false
		for id in demand.keys():
			if not ROUTE.has(id):
				continue
			var short: int = int(demand[id]) - int(produced.get(id, 0))
			if short <= 0:
				continue
			var r: Dictionary = RecipeDB.get_recipe(ROUTE[id])
			var per: int = int(r["outputs"][id])
			var cycles: int = ceili(float(short) / per)
			for out_id in r["outputs"]:
				produced[out_id] = int(produced.get(out_id, 0)) + int(r["outputs"][out_id]) * cycles
			_add(demand, r["inputs"], cycles)
			time[r["machine"]] = float(time.get(r["machine"], 0.0)) + float(r["duration"]) * cycles
			changed = true
	var raw: Dictionary = {}
	for id in demand:
		if not ROUTE.has(id):
			raw[id] = demand[id]
	return {"raw": raw, "time": time}
