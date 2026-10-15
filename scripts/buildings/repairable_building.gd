class_name RepairableBuilding
extends "res://scripts/interaction/interactable.gd"

## Интерактивное восстанавливаемое здание (Дом / Склад / Мастерская)
## Соответствует разделам 25, 26, 27, 70 дизайн-документа

const ItemDB = preload("res://scripts/inventory/item_db.gd")

## Суммарный бонус к допустимому весу рюкзака по стадиям (индекс = стадия).
const STORAGE_WEIGHT_BONUS: Array[float] = [0.0, 10.0, 20.0, 35.0]
const HOUSE_WEIGHT_BONUS: Array[float] = [0.0, 0.0, 0.0, 15.0]

signal building_opened(building: Node)
signal stage_upgraded(building: Node, new_stage: int)

@export var building_id: String = "house"
@export var building_title: String = "Жилой дом"
@export var current_stage: int = 0
@export var max_stage: int = 3

@export var visuals_root: Node3D

## Конфигурация уровней (если пуста, загружаются значения по умолчанию)
var stages_config: Array[Dictionary] = []

## Накопленные внутри здания материалы следующей стадии: { item_id: количество }.
## Компоненты переносятся из рюкзака порциями — достройку ведут за несколько
## подходов, при прерывании ничего не теряется.
var delivered: Dictionary = {}
## Накопленные внутри здания кредиты следующей стадии.
var delivered_credits: int = 0

func _ready() -> void:
	super._ready()
	object_name = building_title
	prompt_action = "Восстановление"
	
	if stages_config.is_empty():
		_init_default_stages()
	# max_stage не может превышать число описанных стадий.
	max_stage = mini(max_stage, stages_config.size() - 1)
	
	if not visuals_root:
		visuals_root = get_node_or_null("Visuals")
	
	_update_visuals()
	_update_prompt_text()

func _init_default_stages() -> void:
	match building_id:
		"house":
			stages_config = [
				{
					"stage": 0,
					"name": "Разрушенный дом",
					"description": "Крыша пробита ураганом, стены покосились. Полная разруха.",
					"perks": "Объект непригоден для жилья и отдыха.",
					"cost_credits": 0,
					"cost_materials": {}
				},
				{
					"stage": 1,
					"name": "Расчищенный каркас",
					"description": "Завалы строительного мусора убраны, балки укреплены, натянут плотный тент.",
					"perks": "Базовая защита от осадков и ветра. 🛏️ Доступен базовый сон под тентом.",
					"cost_credits": 20,
					"cost_materials": {
						"wood": 8,
						"stone": 6
					}
				},
				{
					"stage": 2,
					"name": "Восстановленный дом",
					"description": "Возведены крепкие стены и надежная кровля. Установлена походная кровать.",
					"perks": "🛏️ Доступен полноценный сон и восстановление энергии (100%).",
					"cost_credits": 60,
					"cost_materials": {
						"wood": 10,
						"poor_brick": 8,
						"mortar": 4
					}
				},
				{
					"stage": 3,
					"name": "Капитальная резиденция",
					"description": "Утепленный фасад, кирпичная печь с дымоходом, остекление и стеллажи.",
					"perks": "🛏️ Комфортный сон + 📦 Вместительный домашний склад (+15 кг к лимиту веса).",
					"cost_credits": 120,
					"cost_materials": {
						"fired_brick": 10,
						"mortar": 6,
						"glass": 2,
						"fuel_briquette": 4
					}
				}
			]
		"storage":
			stages_config = [
				{
					"stage": 0,
					"name": "Разрушенный склад",
					"description": "Стеллажи сломаны, навес рухнул. Хранение грузов невозможно.",
					"perks": "Склад не функционирует.",
					"cost_credits": 0,
					"cost_materials": {}
				},
				{
					"stage": 1,
					"name": "Расчищенный навес",
					"description": "Установлены базовые деревянные поддоны и сухие паллеты.",
					"perks": "📦 Дополнительное хранение (+10 кг к грузоподъемности).",
					"cost_credits": 15,
					"cost_materials": {
						"wood": 6,
						"stone": 4
					}
				},
				{
					"stage": 2,
					"name": "Крытый амбар",
					"description": "Глухие деревянные стены и водонепроницаемый настил.",
					"perks": "📦 Капитальное сухое хранилище (+20 кг к грузоподъемности).",
					"cost_credits": 45,
					"cost_materials": {
						"wood": 10,
						"poor_brick": 6,
						"mortar": 2
					}
				},
				{
					"stage": 3,
					"name": "Логистический комплекс",
					"description": "Капитальный каменный фундамент, стеллажи, сортировочная зона и ручной подъёмник на шестернях.",
					"perks": "📦 Максимальная логистика (+35 кг к грузоподъемности).",
					"cost_credits": 100,
					"cost_materials": {
						"fired_brick": 6,
						"iron_plate": 2,
						"gear": 2,
						"stone_dust": 6
					}
				}
			]
		_:
			# Универсальный шаблон
			stages_config = [
				{
					"stage": 0,
					"name": "Разрушено",
					"description": "Требуется капитальный ремонт.",
					"perks": "Не работает.",
					"cost_credits": 0,
					"cost_materials": {}
				},
				{
					"stage": 1,
					"name": "Частично восстановлено",
					"description": "Первичный каркас.",
					"perks": "Базовый функционал.",
					"cost_credits": 25,
					"cost_materials": {"wood": 5, "stone": 5}
				},
				{
					"stage": 2,
					"name": "Полностью восстановлено",
					"description": "Объект в рабочем состоянии.",
					"perks": "Полный функционал.",
					"cost_credits": 60,
					"cost_materials": {"wood": 10, "poor_brick": 5}
				}
			]

func _update_prompt_text() -> void:
	if current_stage >= max_stage:
		prompt_action = "Осмотреть"
	else:
		prompt_action = "Восстановление"

func get_prompt() -> String:
	var stage_data: Dictionary = get_current_stage_data()
	var s_name: String = stage_data.get("name", building_title)
	if current_stage >= max_stage:
		return "[E] %s [%s — Восстановлено]" % [building_title, s_name]
	return "[E] %s [%s (%d/%d)]" % [building_title, s_name, current_stage, max_stage]

func _on_interacted(_player: Node) -> void:
	building_opened.emit(self)

func get_stage_data(stage_idx: int) -> Dictionary:
	if stage_idx >= 0 and stage_idx < stages_config.size():
		return stages_config[stage_idx]
	return {}

func get_current_stage_data() -> Dictionary:
	return get_stage_data(current_stage)

func get_next_stage_data() -> Dictionary:
	if current_stage < max_stage:
		return get_stage_data(current_stage + 1)
	return {}

func can_upgrade(player: Node) -> Dictionary:
	var result: Dictionary = {
		"can_upgrade": false,
		"reason": "",
		"missing_credits": 0,
		"missing_materials": {}
	}
	
	if current_stage >= max_stage:
		result["reason"] = "Здание уже полностью восстановлено!"
		return result
	
	var next_stage: Dictionary = get_next_stage_data()
	if next_stage.is_empty():
		result["reason"] = "Данные следующего этапа не найдены."
		return result
	
	var inv = player.get("inventory") if player else null
	if not inv:
		result["reason"] = "Инвентарь игрока недоступен."
		return result
	
	var cost_cr: int = next_stage.get("cost_credits", 0)
	var current_cr: int = inv.get("credits") if "credits" in inv else 0
	if current_cr < cost_cr:
		result["missing_credits"] = cost_cr - current_cr
	
	var mats: Dictionary = next_stage.get("cost_materials", {})
	var missing_mats: Dictionary = {}
	for mat_id in mats.keys():
		var needed: int = mats[mat_id]
		var avail: int = inv.get_item_count(mat_id)
		if avail < needed:
			missing_mats[mat_id] = needed - avail
	
	result["missing_materials"] = missing_mats
	
	if result["missing_credits"] == 0 and missing_mats.is_empty():
		result["can_upgrade"] = true
	else:
		result["reason"] = "Недостаточно ресурсов или кредитов."
	
	return result

## Прогресс следующей стадии с учётом накопленного внутри здания:
## {"ready": bool, "credits": [внесено, нужно], "materials": {id: [внесено, нужно]}}.
func get_delivery_progress() -> Dictionary:
	var out: Dictionary = {"ready": false, "credits": [0, 0], "materials": {}}
	if current_stage >= max_stage:
		return out
	var next_stage: Dictionary = get_next_stage_data()
	var need_cr: int = int(next_stage.get("cost_credits", 0))
	out["credits"] = [delivered_credits, need_cr]
	var mats: Dictionary = next_stage.get("cost_materials", {})
	var done: bool = delivered_credits >= need_cr
	for mat_id in mats.keys():
		var need: int = int(mats[mat_id])
		var have: int = int(delivered.get(mat_id, 0))
		out["materials"][mat_id] = [have, need]
		if have < need:
			done = false
	out["ready"] = done
	return out

## Переносит в здание всё, что есть в рюкзаке (не больше нужного), и, когда
## комплект собран, применяет стадию. Возвращает true, если стадия применена
## этим вызовом.
func contribute(player: Node) -> bool:
	if current_stage >= max_stage:
		if player and player.has_method("notify"):
			player.notify("✅ %s уже полностью восстановлено." % building_title)
		return false
	var next_stage: Dictionary = get_next_stage_data()
	if next_stage.is_empty():
		return false
	var inv = player.get("inventory") if player else null
	if inv == null:
		if player and player.has_method("notify"):
			player.notify("❌ Инвентарь игрока недоступен.")
		return false

	var cost_cr: int = int(next_stage.get("cost_credits", 0))
	var player_cr: int = int(inv.get("credits")) if "credits" in inv else 0
	var cr_take: int = clampi(cost_cr - delivered_credits, 0, maxi(0, player_cr))
	if cr_take > 0:
		inv.spend_credits(cr_take)
		delivered_credits += cr_take

	var mats: Dictionary = next_stage.get("cost_materials", {})
	var brought: Array[String] = []
	for mat_id in mats.keys():
		var need: int = int(mats[mat_id]) - int(delivered.get(mat_id, 0))
		if need <= 0:
			continue
		var take: int = mini(need, inv.get_item_count(mat_id))
		if take > 0 and inv.remove_item(mat_id, take):
			delivered[mat_id] = int(delivered.get(mat_id, 0)) + take
			brought.append("%s ×%d" % [ItemDB.get_item_name(mat_id), take])

	var progress: Dictionary = get_delivery_progress()
	if not bool(progress.get("ready", false)):
		if player and player.has_method("notify"):
			var msg: String = "📦 Внесено в «%s»:" % building_title
			if not brought.is_empty():
				msg += " " + ", ".join(brought)
			var still: PackedStringArray = []
			if int(progress["credits"][0]) < int(progress["credits"][1]):
				still.append("💰 кредиты %d/%d" % [int(progress["credits"][0]), int(progress["credits"][1])])
			for mat_id in progress["materials"].keys():
				var pair: Array = progress["materials"][mat_id]
				if int(pair[0]) < int(pair[1]):
					still.append("%s %s %d/%d" % [ItemDB.get_item_icon(mat_id), ItemDB.get_item_name(mat_id), int(pair[0]), int(pair[1])])
			if not still.is_empty():
				msg += ". Осталось: " + ", ".join(still)
			player.notify(msg)
		return false

	# Комплект собран — применяем стадию (внесено ровно по нужному количеству).
	delivered.clear()
	delivered_credits = 0
	current_stage += 1
	_apply_stage_perks(player, next_stage)
	_update_visuals()
	_update_prompt_text()
	_play_upgrade_effect()

	stage_upgraded.emit(self, current_stage)

	if player and player.has_method("notify"):
		var stage_name: String = next_stage.get("name", "Уровень %d" % current_stage)
		player.notify("🎉 %s восстановлен до стадии: %s!" % [building_title, stage_name])

	return true

func upgrade(player: Node) -> bool:
	return contribute(player)

func _apply_stage_perks(player: Node, _stage_data: Dictionary) -> void:
	apply_capacity_bonus(player)

## Суммарный бонус к допустимому весу рюкзака на текущей стадии.
func get_weight_bonus() -> float:
	var idx: int = clampi(current_stage, 0, 3)
	match building_id:
		"storage":
			return STORAGE_WEIGHT_BONUS[idx]
		"house":
			return HOUSE_WEIGHT_BONUS[idx]
	return 0.0

## Идемпотентно выставляет бонус грузоподъёмности игроку (вызывается при улучшении
## и после загрузки сохранения).
func apply_capacity_bonus(player: Node) -> void:
	var inv = player.get("inventory") if player else null
	if inv and inv.has_method("set_weight_bonus"):
		inv.set_weight_bonus("building:" + building_id, get_weight_bonus())

func _update_visuals() -> void:
	if not visuals_root:
		return
	
	for i in range(max_stage + 1):
		var node_name: String = "Stage%d" % i
		var stage_node = visuals_root.get_node_or_null(node_name)
		if stage_node:
			stage_node.visible = (i == current_stage)
	# Коллизии, которые есть только на одной стадии (StaticBody3D/Stage<N>…), — включены только на ней.
	var body := get_node_or_null("StaticBody3D")
	if body:
		for shape in body.get_children():
			if shape is CollisionShape3D and String(shape.name).begins_with("Stage"):
				shape.set_deferred("disabled", not String(shape.name).begins_with("Stage%d" % current_stage))

func _play_upgrade_effect() -> void:
	if not visuals_root:
		return
	var tw: Tween = create_tween()
	var orig_scale: Vector3 = visuals_root.scale
	tw.tween_property(visuals_root, "scale", orig_scale * 1.08, 0.12)
	tw.tween_property(visuals_root, "scale", orig_scale, 0.18)

func can_sleep() -> bool:
	return building_id == "house" and current_stage >= 1

func sleep(player: Node, hours: float = -1.0) -> void:
	if not can_sleep():
		if player and player.has_method("notify"):
			player.notify("⚠️ Дом еще недостаточно отремонтирован для сна!")
		return

	# hours <= 0 — сон до 6:00 утра следующего дня (поведение по умолчанию);
	# иначе — выбранная ползунком длительность в диалоге сна.
	if hours <= 0.0:
		hours = 8.0
		var dc: Node = get_tree().root.find_child("DayNightCycle", true, false)
		if dc and "current_hour" in dc:
			# Часов до 6:00 утра следующего дня (например, 23:00 -> 7 ч, 07:00 -> 23 ч).
			hours = (24.0 - float(dc.current_hour)) + 6.0
	# Сон через переход отдыха (часы, ускорение времени, рост и производство
	# догоняют перемотку). В headless-режиме и без UI start_rest применяет
	# результат мгновенно.
	if player and player.has_method("start_rest"):
		player.start_rest(maxf(0.5, hours), true)
		return

	var day_cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
	var new_day: int = -1
	if day_cycle and day_cycle.has_method("skip_to_morning"):
		day_cycle.skip_to_morning(6.0)
		new_day = day_cycle.current_day

	if player:
		if player.has_method("rest_in_bed"):
			player.rest_in_bed(new_day)
		elif "energy" in player and "max_energy" in player:
			player.energy = player.max_energy
			if player.has_signal("energy_changed"):
				player.energy_changed.emit(player.energy, player.max_energy)
			if player.has_method("notify"):
				player.notify("💤 Вы отлично выспались в отремонтированном доме! Энергия 100%.")

	# Автосохранение при сне в доме (Этап 12)
	var world = get_tree().root.find_child("World", true, false)
	if world:
		const SaveManagerClass = preload("res://scripts/core/save_manager.gd")
		SaveManagerClass.save_game(world)
