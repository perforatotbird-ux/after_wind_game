class_name ResourceNode
extends "res://scripts/interaction/interactable.gd"

## Интерактивный узел добычи ресурса (Этап 1, разделы 16, 17, 66)

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

signal resource_gathered(resource_id: String, amount: int)
signal node_depleted()
signal node_respawned()

@export_group("Resource Settings")
@export var resource_id: String = "wood"
@export var resource_display_name: String = "Древесина"
@export var required_tool: String = "axe"
@export var action_verb: String = "Рубить"
@export var max_hits: int = 3
@export var current_hits: int = 3
@export var yield_per_hit: int = 2
@export var bonus_depleted_yield: int = 1
@export var energy_cost: float = 3.0
@export var respawn_time: float = 40.0

@export_group("Planting")
## Деревья не восстанавливаются сами: на пень нужно посадить саженец.
## По умолчанию включено для узлов из группы "trees" (см. _ready).
@export var requires_planting: bool = false
## Сколько саженцев выпадает при полной вырубке дерева.
@export var sapling_yield: int = 1
## Время роста саженца до взрослого дерева в игровых часах.
@export var growth_hours: float = 8.0

@export_group("Visuals")
@export var visual_node: Node3D
@export var depleted_visual_node: Node3D

const SAPLING_ID: String = "sapling"
## Масштаб модели только что посаженного саженца.
const SAPLING_START_SCALE: float = 0.18
## Запасная скорость времени, если в сцене нет DayNightCycle (1 игровой час = 60 с).
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0

var is_depleted: bool = false
var respawn_timer: float = 0.0
## Саженец посажен на пень и растёт.
var is_growing: bool = false
## Сколько игровых часов саженец уже растёт.
var growth_progress_hours: float = 0.0
var _original_scale: Vector3 = Vector3.ONE
var _day_cycle: Node = null

func _ready() -> void:
	super._ready()
	current_hits = max_hits
	if is_in_group("trees"):
		requires_planting = true
	object_name = resource_display_name
	prompt_action = action_verb
	
	if not visual_node:
		visual_node = get_node_or_null("Visual")
	if visual_node:
		_original_scale = visual_node.scale
	
	if not depleted_visual_node:
		depleted_visual_node = get_node_or_null("DepletedVisual")
	if depleted_visual_node:
		depleted_visual_node.visible = false
	
	set_process(is_depleted or is_growing)

func _process(delta: float) -> void:
	if not is_depleted and not is_growing:
		set_process(false)
		return
	if requires_planting:
		if is_growing:
			advance_growth(delta * _get_hours_per_second())
		return
	if respawn_time > 0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn()

## Скорость игрового времени из DayNightCycle (часов за секунду реального времени).
func _get_hours_per_second() -> float:
	if not is_instance_valid(_day_cycle):
		_day_cycle = null
		var tree := get_tree()
		if tree:
			_day_cycle = tree.get_first_node_in_group("day_night_cycle")
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		return float(_day_cycle.get_hours_per_second())
	return FALLBACK_HOURS_PER_SECOND

## Рост саженца на hours игровых часов; при достижении growth_hours дерево снова можно рубить.
func advance_growth(hours: float) -> void:
	if not is_growing:
		return
	growth_progress_hours = minf(growth_hours, growth_progress_hours + maxf(0.0, hours))
	_update_growth_visual()
	if growth_progress_hours >= growth_hours:
		is_growing = false
		growth_progress_hours = 0.0
		respawn()

func get_growth_ratio() -> float:
	if not is_growing:
		return 1.0 if not is_depleted else 0.0
	return clampf(growth_progress_hours / maxf(0.01, growth_hours), 0.0, 1.0)

## Сажает саженец на пень. Возвращает true, если посадка удалась.
func plant_sapling(player: Node) -> bool:
	if not requires_planting or not is_depleted or is_growing:
		return false
	var inv = player.get("inventory") if player and "inventory" in player else null
	if inv == null or not inv.has_method("remove_item") or not inv.remove_item(SAPLING_ID, 1):
		if player and player.has_method("notify"):
			player.notify("🌱 Нужен саженец: он выпадает при рубке деревьев.")
		return false
	is_growing = true
	growth_progress_hours = 0.0
	set_process(true)
	if depleted_visual_node:
		depleted_visual_node.visible = false
	if visual_node:
		visual_node.visible = true
	_update_growth_visual()
	AudioManager.play("hit_wood", 1.3)
	if player and player.has_method("notify"):
		player.notify("🌱 Саженец посажен! %s вырастет через %d игр. ч." % [resource_display_name, int(ceil(growth_hours))])
	return true

func _update_growth_visual() -> void:
	if not visual_node or not is_growing:
		return
	var k: float = lerpf(SAPLING_START_SCALE, 0.9, get_growth_ratio())
	visual_node.scale = _original_scale * k

func get_prompt() -> String:
	if is_depleted and requires_planting:
		if is_growing:
			return "🌱 Саженец растёт: %d%% (ещё ~%d игр. ч.)" % [int(get_growth_ratio() * 100.0), int(ceil(growth_hours - growth_progress_hours))]
		return "[E] Посадить саженец (пень: %s)" % resource_display_name
	if is_depleted:
		return "Ресурс истощён (восстанавливается...)"
	
	var tool_data: Dictionary = ItemDB.get_item(required_tool)
	var tool_name: String = tool_data.get("name", required_tool)
	var tool_icon: String = tool_data.get("icon", "🔨")
	
	return "[E] %s %s (%s %s) [%d/%d]" % [
		action_verb,
		object_name,
		tool_icon,
		tool_name,
		current_hits,
		max_hits
	]

func _on_interacted(player: Node) -> void:
	if is_depleted and requires_planting:
		if is_growing:
			if player.has_method("notify"):
				player.notify("🌱 Саженец ещё растёт: %d%%" % int(get_growth_ratio() * 100.0))
		else:
			plant_sapling(player)
		return
	if is_depleted:
		if player.has_method("notify"):
			player.notify("⏳ Месторождение истощено и восстанавливается...")
		return
	
	var inv = player.get("inventory") if "inventory" in player else null
	
	var tool_data: Dictionary = ItemDB.get_item(required_tool)
	var tool_name: String = tool_data.get("name", required_tool)
	var tool_icon: String = tool_data.get("icon", "🔨")
	
	# Проверка инструмента
	if inv:
		if not inv.is_tool_equipped(required_tool):
			var equipped_name: String = ItemDB.get_item_name(inv.get_equipped_tool())
			var msg: String = "⚠️ Требуется %s %s! В руках: %s. Нажмите клавишу слота." % [
				tool_icon, tool_name, equipped_name
			]
			if player.has_method("notify"):
				player.notify(msg)
			return
	
	# Проверка уровня инструмента (Этап 11)
	var tool_level: int = 1
	if inv and inv.has_method("get_tool_level"):
		tool_level = inv.get_tool_level(required_tool)
	
	var final_energy_cost: float = energy_cost
	var hit_power: int = 1
	var bonus_yield: int = 0
	if tool_level >= 2:
		final_energy_cost = energy_cost * 0.65
		hit_power = 2
		bonus_yield = 1
	
	# Бонус специализации Шахтёр (Этап 12)
	var is_mining_node: bool = (required_tool == "pickaxe" or resource_id in ["stone", "metal_scrap"])
	if player and "character_class" in player and player.character_class == "miner" and is_mining_node:
		bonus_yield += 1
		final_energy_cost *= 0.80
	
	# Трата энергии
	if player.has_method("consume_energy"):
		player.consume_energy(final_energy_cost)
	
	# Звук удара (Game Feel)
	if required_tool == "axe" or resource_id == "wood":
		AudioManager.play("hit_wood", randf_range(0.95, 1.05))
	else:
		AudioManager.play("hit_stone", randf_range(0.95, 1.05))
	
	# Визуальный отклик (shake tween)
	_play_hit_effect()
	
	# Добыча
	current_hits -= hit_power
	var gained: int = yield_per_hit + bonus_yield
	var item_icon: String = ItemDB.get_item_icon(resource_id)
	
	if current_hits <= 0:
		# Истощение
		gained += bonus_depleted_yield
		if inv:
			inv.add_item(resource_id, gained)
		
		resource_gathered.emit(resource_id, gained)
		_set_depleted(true)
		
		var msg_depleted: String = "✅ %s %s +%d! Жила полностью выработана." % [
			item_icon, resource_display_name, gained
		]
		if requires_planting:
			var saplings: int = maxi(0, sapling_yield)
			if inv and saplings > 0:
				inv.add_item(SAPLING_ID, saplings)
			msg_depleted = "✅ %s %s +%d, 🌱 саженец +%d. Дерево не отрастёт само — посадите саженец на пень." % [
				item_icon, resource_display_name, gained, saplings
			]
		if player.has_method("notify"):
			player.notify(msg_depleted)
	else:
		if inv:
			inv.add_item(resource_id, gained)
		
		resource_gathered.emit(resource_id, gained)
		
		var msg_hit: String = "%s %s +%d (Прочность: %d/%d)" % [
			item_icon, resource_display_name, gained, current_hits, max_hits
		]
		if player.has_method("notify"):
			player.notify(msg_hit)
		# Набор воды ведром из пруда: персонаж выставляет ведро, капли, полное ведро.
		if required_tool == "bucket" and player.has_method("play_scoop_animation"):
			player.play_scoop_animation(global_position)

func _play_hit_effect() -> void:
	if not visual_node:
		return
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual_node, "scale", _original_scale * Vector3(1.15, 0.85, 1.15), 0.08)
	tw.tween_property(visual_node, "scale", _original_scale, 0.12)

func _set_depleted(depleted: bool) -> void:
	is_depleted = depleted
	# Пень дерева остаётся интерактивным: на него сажают саженец.
	is_interactable = (not depleted) or requires_planting
	if not depleted:
		is_growing = false
		growth_progress_hours = 0.0
		set_process(false)
	else:
		set_process(true)
	# Твёрдое тело (валун) исчезает вместе с моделью: по щебню можно пройти.
	var solid := get_node_or_null("SolidBody/SolidShape") as CollisionShape3D
	if solid:
		solid.set_deferred("disabled", depleted)
	
	if depleted:
		respawn_timer = respawn_time
		if visual_node:
			# Плавное сжатие
			var tw: Tween = create_tween()
			tw.tween_property(visual_node, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
			tw.finished.connect(func(): if is_depleted and not is_growing and visual_node: visual_node.visible = false)
		if depleted_visual_node:
			depleted_visual_node.visible = true
			depleted_visual_node.scale = Vector3(0.1, 0.1, 0.1)
			var tw2: Tween = create_tween()
			tw2.tween_property(depleted_visual_node, "scale", Vector3.ONE, 0.25)
		node_depleted.emit()
	else:
		current_hits = max_hits
		if visual_node:
			visual_node.visible = true
			visual_node.scale = _original_scale
		if depleted_visual_node:
			depleted_visual_node.visible = false
		node_respawned.emit()

func respawn() -> void:
	_set_depleted(false)
