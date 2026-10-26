extends SceneTree

## Тест загрузки и корректности иконок предметов ItemIcons и ItemDB.
## Проверяет:
## 1. Все предметы из ItemDB возвращают не-null Texture2D.
## 2. Подключение набора res://assets/icons/* (tools, materials, food, seeds, harvest, tech, alcohol, resources, crafting).
## 3. Переключение use_generated_icons (true / false) со сбросом кэша.
## Запуск: godot --headless --script res://tests/test_item_icons_load.gd

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const ItemIcons = preload("res://scripts/ui/item_icons.gd")

func _init() -> void:
	print("--- НАЧАЛО ТЕСТА: test_item_icons_load ---")
	_run()

func _fail(msg: String) -> void:
	print("❌ ТЕСТ ПРОВАЛЕН: " + msg)
	quit(1)

func _run() -> void:
	# 1. Проверяем режим сгенерированных иконок
	ItemIcons.set_use_generated_icons(true)
	if not ItemIcons.use_generated_icons:
		_fail("ItemIcons.use_generated_icons должен быть true")

	# Проверяем структуру папок GENERATED_FOLDERS
	for folder in ItemIcons.GENERATED_FOLDERS:
		if not folder.begins_with("res://assets/icons/"):
			_fail("Некорректная папка в GENERATED_FOLDERS: " + folder)
		if not DirAccess.dir_exists_absolute(folder):
			_fail("Папка не существует на диске: " + folder)

	# 2. Проверяем загрузку текстуры для каждого предмета из ItemDB
	var total_items: int = ItemDB.ITEMS.size()
	var file_icons_count: int = 0
	var procedural_icons_count: int = 0

	for item_id in ItemDB.ITEMS.keys():
		var tex: Texture2D = ItemIcons.get_texture(item_id)
		if tex == null:
			_fail("get_texture('%s') вернул null" % item_id)
		if tex.get_width() <= 0 or tex.get_height() <= 0:
			_fail("Текстура для '%s' имеет некорректный размер %dx%d" % [item_id, tex.get_width(), tex.get_height()])

		# Проверяем, является ли текстура файловой (256x256) или процедурной
		if tex.get_width() == 256 and tex.get_height() == 256:
			file_icons_count += 1
		else:
			procedural_icons_count += 1

	print("Проверено предметов: %d. Файловых 3D-иконок (256x256): %d, Процедурных: %d" % [
		total_items, file_icons_count, procedural_icons_count
	])

	# Почти все предметы (минимум 115 из 119) должны быть файловыми 256x256
	if file_icons_count < 115:
		_fail("Слишком мало файловых иконок: %d (ожидалось >= 115)" % file_icons_count)

	# 3. Проверяем конкретные категории и ключевые предметы
	var sample_keys = [
		"axe", "pickaxe", "shovel", "bucket", "whetstone", "backpack",
		"iron_axe", "iron_pickaxe", "iron_shovel", "reinforced_bucket",
		"wood", "stone", "iron_ore", "clay", "sand", "water",
		"stone_dust", "sawdust", "coal_powder", "mortar", "poor_brick",
		"fuel_briquette", "fired_brick", "glass", "glass_bottle", "clay_pot",
		"glassware_set", "steel_plate", "precision_gear", "steel_ingot",
		"iron_ingot", "fertilizer", "wooden_handle", "bolt", "fabric", "leather_strap",
		"bread", "baked_potato", "clean_water", "carrot", "apple", "beer", "moonshine",
		"seeds_carrot", "apple_sapling", "gear", "copper_wire", "battery_cell"
	]
	for k in sample_keys:
		var tex = ItemIcons.get_texture(k)
		if tex.get_width() != 256 or tex.get_height() != 256:
			_fail("Предмет '%s' должен использовать 3D-иконку 256x256, получено %dx%d" % [
				k, tex.get_width(), tex.get_height()
			])

	# 4. Проверяем переключение на оригинальные/процедурные иконки
	ItemIcons.set_use_generated_icons(false)
	if ItemIcons.use_generated_icons:
		_fail("ItemIcons.use_generated_icons должен быть false после переключения")

	for k in ["wood", "stone", "carrot"]:
		var tex_orig = ItemIcons.get_texture(k)
		if tex_orig == null or tex_orig.get_width() <= 0:
			_fail("Откат на оригинальную иконку для '%s' вернул некорректную текстуру" % k)

	# Возвращаем режим 3D-иконок обратно
	ItemIcons.set_use_generated_icons(true)
	ItemIcons.clear_cache()
	var tex_restored = ItemIcons.get_texture("wood")
	if tex_restored.get_width() != 256:
		_fail("После возврата use_generated_icons=true текстура 'wood' должна быть 256x256")

	print("✅ ВСЕ ПРОВЕРКИ ИКОНОК УСПЕШНО ПРОЙДЕНЫ!")
	quit(0)
