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
					"perks": "Базовая защита от осадков и ветра.",
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

func upgrade(player: Node) -> bool:
	var check: Dictionary = can_upgrade(player)
	if not check.get("can_upgrade", false):
		if player and player.has_method("notify"):
			player.notify("❌ Невозможно улучшить: " + check.get("reason", ""))
		return false
	
	var next_stage: Dictionary = get_next_stage_data()
	var inv = player.get("inventory")
	
	# Списание кредитов
	var cost_cr: int = next_stage.get("cost_credits", 0)
	if cost_cr > 0:
		inv.spend_credits(cost_cr)
	
	# Списание материалов
	var mats: Dictionary = next_stage.get("cost_materials", {})
	for mat_id in mats.keys():
		var count: int = mats[mat_id]
		inv.remove_item(mat_id, count)
	
	# Повышение стадии
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

func _play_upgrade_effect() -> void:
	if not visuals_root:
		return
	var tw: Tween = create_tween()
	var orig_scale: Vector3 = visuals_root.scale
	tw.tween_property(visuals_root, "scale", orig_scale * 1.08, 0.12)
	tw.tween_property(visuals_root, "scale", orig_scale, 0.18)

func can_sleep() -> bool:
	return building_id == "house" and current_stage >= 2

func sleep(player: Node) -> void:
	if not can_sleep():
		if player and player.has_method("notify"):
			player.notify("⚠️ Дом еще недостаточно отремонтирован для сна!")
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
