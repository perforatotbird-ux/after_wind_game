extends RefCounted

## Заглушка системы сезонов (подключать: const Seasons = preload("res://scripts/core/seasons.gd")). Полноценной смены времён года в игре пока нет:
## current_season пустой — это значит «сезоны выключены», и всё, что зависит от
## сезона (например, отрастание ягод), работает круглый год.
## Будущая система сезонов должна просто выставлять current_season
## ("spring", "summer", "autumn", "winter") — кусты сразу начнут его учитывать.

const SPRING: String = "spring"
const SUMMER: String = "summer"
const AUTUMN: String = "autumn"
const WINTER: String = "winter"
const ALL: Array[String] = [SPRING, SUMMER, AUTUMN, WINTER]
const NAMES: Dictionary = {SPRING: "весна", SUMMER: "лето", AUTUMN: "осень", WINTER: "зима"}

## Текущий сезон; "" — система сезонов ещё не подключена.
static var current_season: String = ""

static func is_enabled() -> bool:
	return current_season != ""

static func get_current_season() -> String:
	return current_season

## true, если сейчас один из сезонов списка (без системы сезонов — всегда true).
static func is_in_season(seasons: Array) -> bool:
	if not is_enabled():
		return true
	return seasons.has(current_season)

static func describe(seasons: Array) -> String:
	var parts: PackedStringArray = []
	for s in seasons:
		parts.append(NAMES.get(s, str(s)))
	return ", ".join(parts)
