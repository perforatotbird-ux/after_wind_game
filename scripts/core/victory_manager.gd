class_name VictoryManager
extends RefCounted

## Менеджер финальной цели Первого этапа «Base Restored» (Разделы 85, 91, 92 дизайн-документа)
## Проверяет выполнение всех ключевых условий восстановления базы и хозяйства.

const ContractDB = preload("res://scripts/economy/contract_db.gd")

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
	
	# 1. Восстановление жилого дома (Стадия 2)
	var house = world.find_child("RepairableHouse", true, false)
	var house_done: bool = (house != null and "current_stage" in house and house.current_stage >= 2)
	tasks.append({
		"id": "house",
		"title": "Восстановить дом до стадии 2/2 (кровать и укрытие)",
		"icon": "🏠",
		"done": house_done
	})
	
	# 2. Восстановление склада (Стадия 2)
	var storage = world.find_child("RepairableStorage", true, false)
	var storage_done: bool = (storage != null and "current_stage" in storage and storage.current_stage >= 2)
	tasks.append({
		"id": "storage",
		"title": "Восстановить склад до стадии 2/2 (хранилище базы)",
		"icon": "📦",
		"done": storage_done
	})
	
	# 3. Восстановление производственного узла (Дробилка)
	var crusher = world.find_child("StoneCrusher", true, false)
	if not crusher:
		crusher = world.find_child("Crusher", true, false)
	var crusher_done: bool = (crusher != null and is_instance_valid(crusher))
	tasks.append({
		"id": "crusher",
		"title": "Запустить дробилку для измельчения камня и глины",
		"icon": "⚙️",
		"done": crusher_done
	})
	
	# 4. Восстановление верстака
	var bench = world.find_child("Workbench", true, false)
	var bench_done: bool = (bench != null and is_instance_valid(bench))
	tasks.append({
		"id": "workbench",
		"title": "Оборудовать верстак для крафта оснастки и инструментов",
		"icon": "🔨",
		"done": bench_done
	})
	
	# 5. Восстановление плавильной печи
	var smelter = world.find_child("Smelter", true, false)
	var smelter_done: bool = (smelter != null and is_instance_valid(smelter))
	tasks.append({
		"id": "smelter",
		"title": "Ввести в строй высокотемпературную печь-плавильню",
		"icon": "🔥",
		"done": smelter_done
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
	
	# 8. Создание инструмента мастера Lv.2 или большого рюкзака
	var player = world.find_child("Player", true, false)
	var inv = player.get("inventory") if player else null
	var upgrades_done: bool = false
	if inv:
		if inv.has_method("get_tool_level"):
			if inv.get_tool_level("axe") >= 2 or inv.get_tool_level("pickaxe") >= 2 or inv.get_tool_level("shovel") >= 2 or inv.get_tool_level("bucket") >= 2 or inv.get_tool_level("backpack") >= 2:
				upgrades_done = true
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
