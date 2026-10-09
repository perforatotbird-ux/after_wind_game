extends RefCounted

## Состояние сессии между перезагрузками сцены мира.
## Стартовое меню и меню паузы пишут сюда намерение (новая игра / загрузка
## слота / выход в меню) и перезагружают сцену; world.gd читает его один раз в _ready.
## Данные хранятся в метаданных SceneTree — они переживают reload_current_scene().

const META_KEY: StringName = &"after_storm_session"

static func request_new_game(tree: SceneTree) -> void:
	tree.set_meta(META_KEY, {"skip_menu": true, "load_slot": ""})

static func request_load(tree: SceneTree, slot_id: String) -> void:
	tree.set_meta(META_KEY, {"skip_menu": true, "load_slot": slot_id})

static func request_main_menu(tree: SceneTree) -> void:
	if tree.has_meta(META_KEY):
		tree.remove_meta(META_KEY)

## Возвращает и очищает запрос. Пустой словарь — показать стартовое меню.
static func consume(tree: SceneTree) -> Dictionary:
	if not tree.has_meta(META_KEY):
		return {}
	var data = tree.get_meta(META_KEY)
	tree.remove_meta(META_KEY)
	return data if data is Dictionary else {}

static func restart_scene(tree: SceneTree) -> void:
	tree.paused = false
	tree.reload_current_scene()
