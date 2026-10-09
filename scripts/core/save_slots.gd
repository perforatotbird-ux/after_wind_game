extends RefCounted

## Слоты сохранений поверх SaveManager: 3 ручных слота (user://saves/slot_N.json)
## и автосохранение. Автосохранение — это прежний файл user://savegame.json, поэтому
## F5/F9, сон в доме и старые сохранения продолжают работать без миграции.
## Формат файлов не меняется (см. docs/DOCUMENTATION.md, «Сохранения»).

const SAVE_DIR: String = "user://saves"
const AUTOSAVE_ID: String = "autosave"
const MANUAL_SLOT_COUNT: int = 3

## Пути можно подменить в тестах, чтобы не трогать сохранения игрока.
static var save_dir: String = SAVE_DIR
static var autosave_path: String = "user://savegame.json"

static func get_manual_slot_ids() -> Array[String]:
	var ids: Array[String] = []
	for i in range(1, MANUAL_SLOT_COUNT + 1):
		ids.append("slot_%d" % i)
	return ids

static func get_all_slot_ids() -> Array[String]:
	var ids: Array[String] = [AUTOSAVE_ID]
	ids.append_array(get_manual_slot_ids())
	return ids

## Пустая строка — неизвестный слот (защита от произвольных путей).
static func get_slot_path(slot_id: String) -> String:
	if slot_id == AUTOSAVE_ID:
		return autosave_path
	if slot_id in get_manual_slot_ids():
		return save_dir.path_join(slot_id + ".json")
	return ""

static func get_slot_title(slot_id: String) -> String:
	if slot_id == AUTOSAVE_ID:
		return "🔄 Автосохранение"
	return "💾 Слот %s" % slot_id.trim_prefix("slot_")

static func has_slot(slot_id: String) -> bool:
	var path := get_slot_path(slot_id)
	return path != "" and FileAccess.file_exists(path)

static func save_to_slot(world: Node, slot_id: String) -> bool:
	var path := get_slot_path(slot_id)
	if path == "":
		return false
	var base_dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	return SaveManager.save_game(world, path)

static func load_from_slot(world: Node, slot_id: String) -> bool:
	if not has_slot(slot_id):
		return false
	return SaveManager.load_game(world, get_slot_path(slot_id))

static func delete_slot(slot_id: String) -> bool:
	var path := get_slot_path(slot_id)
	if path == "":
		return false
	return SaveManager.delete_save(path)

## Сырые данные слота или {} (нет файла / битый JSON). Ошибки в лог не пишет.
static func read_slot_data(slot_id: String) -> Dictionary:
	if not has_slot(slot_id):
		return {}
	var file := FileAccess.open(get_slot_path(slot_id), FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}

## Краткая информация для карточки слота (без изменения мира).
## valid = false, если файл повреждён или создан более новой версией игры.
static func get_slot_info(slot_id: String) -> Dictionary:
	var info: Dictionary = {
		"id": slot_id,
		"title": get_slot_title(slot_id),
		"exists": has_slot(slot_id),
		"valid": false,
		"day": 1,
		"hour": 8.0,
		"credits": 0,
		"timestamp": "",
		"modified": 0,
	}
	if not info["exists"]:
		return info
	info["modified"] = FileAccess.get_modified_time(get_slot_path(slot_id))
	var data := read_slot_data(slot_id)
	if data.is_empty() or not SaveManager._validate_save_data(data):
		return info
	if SaveManager.get_format_version(data) > SaveManager.SAVE_FORMAT_VERSION:
		return info
	info["valid"] = true
	var meta: Dictionary = data.get("meta", {})
	if meta.get("timestamp", "") is String:
		info["timestamp"] = String(meta.get("timestamp", "")).replace("T", " ").substr(0, 16)
	var dn: Dictionary = data.get("day_night", {})
	info["day"] = int(dn.get("current_day", 1))
	info["hour"] = float(dn.get("current_hour", dn.get("time_of_day", 8.0)))
	var inv: Dictionary = data.get("inventory", {})
	info["credits"] = int(inv.get("credits", 0))
	return info

static func format_slot_details(info: Dictionary) -> String:
	if not info.get("exists", false):
		return "Пусто"
	if not info.get("valid", false):
		return "⚠️ Файл повреждён или создан более новой версией игры"
	var hour: float = float(info.get("hour", 8.0))
	var h: int = int(hour)
	var m: int = int((hour - h) * 60.0)
	var parts: Array[String] = [
		"📅 День %d, %02d:%02d" % [int(info.get("day", 1)), h, m],
		"💰 %d кр." % int(info.get("credits", 0)),
	]
	var ts: String = str(info.get("timestamp", ""))
	if ts != "":
		parts.append("🕒 " + ts)
	return "  |  ".join(parts)

## Самый свежий корректный слот (для «Продолжить») или "".
static func get_latest_slot() -> String:
	var best: String = ""
	var best_time: int = -1
	for slot_id in get_all_slot_ids():
		var info := get_slot_info(slot_id)
		if info["valid"] and int(info["modified"]) > best_time:
			best_time = int(info["modified"])
			best = slot_id
	return best
