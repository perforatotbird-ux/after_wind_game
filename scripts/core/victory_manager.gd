class_name VictoryManager
extends RefCounted

## Менеджер финальной цели Первого этапа «Base Restored» (Разделы 85, 91, 92 дизайн-документа).
## Проверяет выполнение всех ключевых условий восстановления базы и хозяйства.
## Машины (дробилка, верстак, плавильня) засчитываются только после первого
## завершённого цикла производства — наличия в сцене недостаточно.

const ContractDB = preload("res://scripts/economy/contract_db.gd")

static func _machine_has_output(machine: Node) -> bool:
	return machine != null and is_instance_valid(machine) and "completed_runs" in machine and int(machine.completed_runs) > 0

static func evaluate_base_restored(world: Node) -> Dictionary:
	var tasks: Array[Dictionary] = []
	
	if not world or not is_instance_valid(world):
		return {
			"is_victory": false,
			"progress_pct": 0,
			"completed_count": 0,
			"total_count": 0,
			"tasks": tasks
		}
	
	# 1. Восстановление жилого дома (стадия 2 из 3)
	var house = world.find_child("RepairableHouse", true, false)
	var house_done: bool = (house != null and "current_stage" in house and house.current_stage >= 2)
	tasks.append({
		"id": "house",
		"title": "Восстановить дом до стадии 2 из 3 (кровать и укрытие)",
		"icon": "🏠",
		"done": house_done
	})
	
	# 2. Восстановление склада (стадия 2 из 3)
	var storage = world.find_child("RepairableStorage", true, false)
	var storage_done: bool = (storage != null and "current_stage" in storage and storage.current_stage >= 2)
	tasks.append({
		"id": "storage",
		"title": "Восстановить склад до стадии 2 из 3 (хранилище базы)",
		"icon": "📦",
		"done": storage_done
	})
	
	# 3. Дробилка: получить первую продукцию
	var crusher = world.find_child("StoneCrusher", true, false)
	if not crusher:
		crusher = world.find_child("Crusher", true, false)
	tasks.append({
		"id": "crusher",
		"title": "Запустить дробилку и получить первую продукцию",
		"icon": "⚙️",
		"done": _machine_has_output(crusher)
	})
	
	# 4. Верстак: первый изготовленный предмет
	var bench = world.find_child("Workbench", true, false)
	tasks.append({
		"id": "workbench",
		"title": "Изготовить первый предмет на верстаке",
		"icon": "🔨",
		"done": _machine_has_output(bench)
	})
	
	# 5. Плавильня: первая плавка
	var smelter = world.find_child("Smelter", true, false)
	tasks.append({
		"id": "smelter",
		"title": "Провести первую плавку в печи-плавильне",
		"icon": "🔥",
		"done": _machine_has_output(smelter)
	})
	
	# 6. Восстановление фермерского хозяйства
	var plots = world.find_children("", "FarmlandPlot", true, false)
	if plots.is_empty():
		for c in world.find_children("*", "", true, false):
			if c.is_in_group("farmland_plots"):
				plots.append(c)
	var farm_done: bool = false
	for p in plots:
		if is_instance_valid(p) and "soil_state" in p and p.soil_state >= 1:
			farm_done = true
			break
	tasks.append({
		"id": "farm",
		"title": "Вскопать пахотную грядку и подготовить землю фермы",
		"icon": "🌾",
		"done": farm_done
	})
	
	# 7. Сдача заказов общине (минимум 2 контракта)
	var completed_contracts: int = ContractDB.get_completed_count()
	var contracts_done: bool = (completed_contracts >= 2)
	tasks.append({
		"id": "contracts",
		"title": "Выполнить контракты снабжения общины (%d/2 сдано)" % mini(completed_contracts, 2),
		"icon": "📜",
		"done": contracts_done
	})
	
	# 8. Инструмент мастера Lv.2 или большой рюкзак
	var player = world.find_child("Player", true, false)
	var inv = player.get("inventory") if player else null
	var upgrades_done: bool = false
	if inv:
		if inv.has_method("get_tool_level"):
			for t_type in ["axe", "pickaxe", "shovel", "bucket", "backpack"]:
				if inv.get_tool_level(t_type) >= 2:
					upgrades_done = true
					break
		elif "max_slots" in inv and inv.max_slots > 12:
			upgrades_done = true
	tasks.append({
		"id": "upgrades",
		"title": "Создать и экипировать инструмент мастера Lv.2",
		"icon": "✨",
		"done": upgrades_done
	})
	
	var completed_count: int = 0
	for t in tasks:
		if t["done"]:
			completed_count += 1
	
	var total_count: int = tasks.size()
	var pct: int = int((float(completed_count) / float(total_count)) * 100.0) if total_count > 0 else 0
	var is_victory: bool = (completed_count == total_count)
	
	return {
		"is_victory": is_victory,
		"progress_pct": pct,
		"completed_count": completed_count,
		"total_count": total_count,
		"tasks": tasks
	}
