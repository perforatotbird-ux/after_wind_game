extends "res://scripts/interaction/interactable.gd"

## Ягодный куст: по [E] собирается berry_yield ягод, после чего куст показывает
## модель без ягод. Ягоды отрастают за regrow_hours игровых часов, но время идёт
## только в сезоны grow_seasons (см. Seasons — пока система сезонов выключена,
## куст отрастает круглый год). Здоровье ягоды не лечат — только сытость, жажду и силы.

const Seasons = preload("res://scripts/core/seasons.gd")
const GROUP: String = "berry_bushes"
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0

## Вид куста ("red" / "blue") — для сохранений, тестов и спавнера.
@export var bush_type: String = "red"
@export var berry_item_id: String = "red_berry"
@export var berry_yield: int = 3
@export var grow_seasons: Array[String] = ["spring", "summer"]
## Сколько игровых часов (в подходящий сезон) отрастают ягоды.
@export var regrow_hours: float = 36.0
@export var full_model: Node3D
@export var empty_model: Node3D

var has_berries: bool = true
## Сколько часов роста уже накоплено после сбора.
var regrow_progress: float = 0.0
var _day_cycle: Node = null

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	prompt_action = "Собрать ягоды"
	_update_model()

func _process(delta: float) -> void:
	if not has_berries:
		advance_regrow(delta * _get_hours_per_second())

## Рост ягод на hours игровых часов (вне сезона время не идёт).
func advance_regrow(hours: float) -> void:
	if has_berries or hours <= 0.0 or not Seasons.is_in_season(grow_seasons):
		return
	regrow_progress += hours
	if regrow_progress >= regrow_hours:
		set_has_berries(true)

func set_has_berries(value: bool) -> void:
	has_berries = value
	regrow_progress = 0.0
	_update_model()

func _update_model() -> void:
	if full_model:
		full_model.visible = has_berries
	if empty_model:
		empty_model.visible = not has_berries

func get_prompt() -> String:
	if has_berries:
		return "[E] %s (%s ×%d)" % [prompt_action, ItemDB.get_item(berry_item_id).get("name", berry_item_id), berry_yield]
	if not Seasons.is_in_season(grow_seasons):
		return "%s: ягоды растут только в сезон (%s)" % [object_name, Seasons.describe(grow_seasons)]
	return "%s: ягоды отрастут через ~%d ч" % [object_name, ceili(maxf(0.0, regrow_hours - regrow_progress))]

func _on_interacted(player: Node) -> void:
	if not has_berries:
		_notify(player, "🌿 " + get_prompt())
		return
	var inv = player.get("inventory") if player else null
	if inv == null or not inv.add_item(berry_item_id, berry_yield):
		_notify(player, "🎒 Не хватает места в рюкзаке для ягод!")
		return
	set_has_berries(false)
	var item: Dictionary = ItemDB.get_item(berry_item_id)
	_notify(player, "%s Собрано: %s ×%d" % [item.get("icon", "🫐"), item.get("name", berry_item_id), berry_yield])

func _notify(player: Node, text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)

func get_save_state() -> Dictionary:
	return {"has_berries": has_berries, "regrow_progress": regrow_progress}

func apply_save_state(state: Dictionary) -> void:
	set_has_berries(bool(state.get("has_berries", true)))
	if not has_berries:
		regrow_progress = clampf(float(state.get("regrow_progress", 0.0)), 0.0, regrow_hours)

func _get_hours_per_second() -> float:
	if not is_instance_valid(_day_cycle):
		_day_cycle = null
		var tree := get_tree()
		if tree:
			_day_cycle = tree.get_first_node_in_group("day_night_cycle")
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		return float(_day_cycle.get_hours_per_second())
	return FALLBACK_HOURS_PER_SECOND
