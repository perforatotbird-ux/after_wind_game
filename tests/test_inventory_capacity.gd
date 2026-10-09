extends SceneTree

## Тест вместимости рюкзака: слоты, стаки, перегруз, бонус склада, формат сохранения v2.
## Запуск: godot --headless --script res://tests/test_inventory_capacity.gd

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")

const TEST_SAVE: String = "user://test_capacity_save.json"
const TEST_LEGACY: String = "user://test_capacity_legacy.json"
const TEST_FUTURE: String = "user://test_capacity_future.json"

var world: Node
var _done: bool = false
var _frames: int = 0

func _init() -> void:
	world = WorldScene.instantiate()
	root.add_child(world)

func _process(_delta: float) -> bool:
	if _done:
		return false
	_frames += 1
	if _frames < 3:
		return false
	_done = true
	_run()
	return false

func _fail(msg: String) -> void:
	print("❌ ТЕСТ ПРОВАЛЕН: " + msg)
	_cleanup()
	quit(1)

func _cleanup() -> void:
	for path in [TEST_SAVE, TEST_LEGACY, TEST_FUTURE, TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _write(path: String, data: Dictionary) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _run() -> void:
	var player = world.find_child("Player", true, false)
	if player == null:
		_fail("Player не найден")
		return
	var inv = player.get("inventory")
	if inv == null:
		_fail("Inventory не найден")
		return

	# 1. Слоты
	inv.clear()
	inv.recalculate_capacity()
	if inv.max_slots <= 0:
		_fail("max_slots должен быть > 0")
		return
	var base_walk: float = player.walk_speed
	var base_sprint: float = player.sprint_speed

	# 2. Стаки
	var stone_stack: int = inv.get_max_stack("stone")
	if stone_stack > 1 and inv.get_slots_for("stone", stone_stack + 1) != 2:
		_fail("стек камня + 1 должен занимать 2 слота")
		return

	# 3. Инструменты не занимают слоты
	if ItemDB.get_item("iron_axe").get("category", "") in ["tool", "equipment"]:
		if inv.item_uses_slots("iron_axe"):
			_fail("инструмент не должен занимать слот рюкзака")
			return

	# 4. Отказ при нехватке слотов
	var saved_slots: int = inv.max_slots
	inv.clear()
	inv.max_slots = 1
	if not inv.add_item("stone", stone_stack):
		_fail("полный стек камня должен влезать в 1 слот")
		return
	if inv.add_item("wood", 1):
		_fail("дерево не должно добавляться при занятом единственном слоте")
		return
	inv.clear()
	inv.max_slots = saved_slots

	# 5. Перегруз
	inv.max_slots = 999
	var stone_w: float = float(ItemDB.get_item("stone").get("weight", 1.0))
	if stone_w <= 0.0:
		stone_w = 1.0
	var n_over: int = int(ceil(inv.max_weight * 1.1 / stone_w)) + 1
	inv.items["stone"] = n_over
	inv._update_load_state()
	if inv.get_load_state() != Inventory.LoadState.OVERLOADED:
		_fail("ожидался OVERLOADED при ×1.1, ratio=%.2f" % inv.get_load_ratio())
		return
	if player.walk_speed >= base_walk:
		_fail("при перегрузе скорость ходьбы должна снижаться")
		return
	var n_crit: int = int(ceil(inv.max_weight * 1.3 / stone_w)) + 1
	inv.items["stone"] = n_crit
	inv._update_load_state()
	if inv.get_load_state() != Inventory.LoadState.CRITICAL:
		_fail("ожидался CRITICAL при ×1.3")
		return
	if player.walk_speed != 0.0 or player.sprint_speed != 0.0:
		_fail("при критическом перегрузе персонаж должен быть обездвижен")
		return
	inv.clear()
	if inv.get_load_state() != Inventory.LoadState.NORMAL:
		_fail("после clear() нагрузка должна быть NORMAL")
		return
	if not is_equal_approx(player.walk_speed, base_walk) or not is_equal_approx(player.sprint_speed, base_sprint):
		_fail("скорость не восстановилась после снятия перегруза")
		return
	inv.max_slots = saved_slots

	# 6. Бонус склада
	var storage = world.find_child("RepairableStorage", true, false)
	if storage and storage.has_method("apply_capacity_bonus"):
		var before_total: float = inv.get_weight_bonus_total()
		var before_storage: float = float(storage.get_weight_bonus())
		storage.current_stage = 2
		storage.apply_capacity_bonus(player)
		if not is_equal_approx(float(storage.get_weight_bonus()), 20.0):
			_fail("бонус склада 2-й стадии должен быть 20 кг")
			return
		if not is_equal_approx(inv.get_weight_bonus_total() - before_total, 20.0 - before_storage):
			_fail("бонус склада не применился к max_weight")
			return

	# 7. Сохранение v2
	if not SaveManager.save_game(world, TEST_SAVE):
		_fail("save_game вернул false")
		return
	var f = FileAccess.open(TEST_SAVE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		_fail("сохранение не является JSON-объектом")
		return
	if int(parsed.get("meta", {}).get("format_version", 0)) != 2:
		_fail("meta.format_version должен быть 2")
		return
	if not parsed.get("resources") is Array:
		_fail("секция resources должна быть массивом")
		return

	# 8. Старое сохранение v1 загружается
	_write(TEST_LEGACY, {"meta": {"version": "1.0.0"}, "player": {"energy": 67}})
	if not SaveManager.load_game(world, TEST_LEGACY):
		_fail("сохранение v1 должно загружаться")
		return

	# 9. Сохранение из будущей версии отклоняется
	_write(TEST_FUTURE, {"meta": {"format_version": 3}})
	if SaveManager.load_game(world, TEST_FUTURE):
		_fail("сохранение формата 3 должно отклоняться")
		return

	_cleanup()
	print("✅ test_inventory_capacity: все проверки пройдены")
	quit(0)
