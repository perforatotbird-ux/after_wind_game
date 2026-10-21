extends "res://scripts/interaction/interactable.gd"

## Лесной гриб (Глава 2 «Первый дым», мастер-план 2.2) — первый ингредиент кухни,
## доступный без фермы. Растёт в тени у деревьев и камней, появляется в
## `grow_seasons` (лето, осень) и отрастает за regrow_hours игровых часов.
##
## Модель двух состояний: FullModel (гриб на месте) и EmptyModel (только моховая
## кочка — гриб срезан). Как у ягодных кустов, но сбора «без сбора»: гриб срезают
## целиком, урожай всегда 1.

const Seasons = preload("res://scripts/core/seasons.gd")
const CookingProgress = preload("res://scripts/crafting/cooking_progress.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")
const GROUP: String = "mushrooms"
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0

@export var mushroom_item_id: String = "mushroom"
@export var mushroom_amount: int = 1
## Сезоны роста (пусто — круглый год).
@export var grow_seasons: Array[String] = ["summer", "autumn"]
## Сколько игровых часов отрастает срезанный гриб.
@export var regrow_hours: float = 18.0
@export var full_model: Node3D
@export var empty_model: Node3D

var has_mushroom: bool = true
## Сколько часов роста накоплено после срезания.
var regrow_progress: float = 0.0
var _day_cycle: Node = null

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	prompt_action = "Срезать грибы"
	object_name = "Лесной гриб"
	_update_model()

func _process(delta: float) -> void:
	if not has_mushroom:
		advance_regrow(delta * _get_hours_per_second())

## Рост на hours игровых часов (вне сезона время не идёт).
func advance_regrow(hours: float) -> void:
	if has_mushroom or hours <= 0.0 or not Seasons.is_in_season(grow_seasons):
		return
	regrow_progress += hours
	if regrow_progress >= regrow_hours:
		set_has_mushroom(true)

func set_has_mushroom(value: bool) -> void:
	has_mushroom = value
	regrow_progress = 0.0
	_update_model()

func _update_model() -> void:
	if full_model:
		full_model.visible = has_mushroom
	if empty_model:
		empty_model.visible = not has_mushroom

func get_prompt() -> String:
	if has_mushroom:
		return "[E] %s (%s ×%d)" % [prompt_action, ItemDB.get_item(mushroom_item_id).get("name", mushroom_item_id), mushroom_amount]
	if not Seasons.is_in_season(grow_seasons):
		return "%s: грибы растут только в сезон (%s)" % [object_name, Seasons.describe(grow_seasons)]
	return "%s: грибы отрастут через ~%d ч" % [object_name, ceili(maxf(0.0, regrow_hours - regrow_progress))]

func _on_interacted(player: Node) -> void:
	if not has_mushroom:
		_notify(player, "🌿 " + get_prompt())
		return
	var count: int = mushroom_amount
	var skills: Object = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("roll_bonus_yield") and skills.roll_bonus_yield("foraging"):
		count += 1
	var inv = player.get("inventory") if player else null
	if inv == null:
		_notify(player, "🎒 Не хватает места в рюкзаке для грибов!")
		return
	# Не поместившиеся грибы падают кучкой у грибницы, а не пропадают.
	var fit: int = int(inv.get_max_addable(mushroom_item_id, count)) if inv.has_method("get_max_addable") else 0
	if fit <= 0:
		_notify(player, "🎒 Не хватает места в рюкзаке для грибов!")
		return
	if fit < count:
		DroppedItemScript.give_or_drop(player, mushroom_item_id, count - fit,
			global_position + Vector3(0.0, 0.4, 0.0), get_parent())
	if not inv.add_item(mushroom_item_id, fit):
		_notify(player, "🎒 Не хватает места в рюкзаке для грибов!")
		return
	count = fit
	set_has_mushroom(false)
	CookingProgress.register_mushrooms(count)
	AudioManager.play("berry_pick")
	if skills and skills.has_method("add_xp"):
		skills.add_xp("foraging", 8)
	var item: Dictionary = ItemDB.get_item(mushroom_item_id)
	_notify(player, "%s Собрано: %s ×%d" % [item.get("icon", "🍄"), item.get("name", mushroom_item_id), count])

func _notify(player: Node, text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)

func get_save_state() -> Dictionary:
	return {"has_mushroom": has_mushroom, "regrow_progress": regrow_progress}

func apply_save_state(state: Dictionary) -> void:
	set_has_mushroom(bool(state.get("has_mushroom", true)))
	if not has_mushroom:
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