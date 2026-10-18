class_name ResourceNode
extends "res://scripts/interaction/interactable.gd"

## Интерактивный узел добычи ресурса (Этап 1, разделы 16, 17, 66)

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")
const Seasons = preload("res://scripts/core/seasons.gd")

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
## Добыча за удар (дробная: 0.25 камня/дерева, 2 воды). Целые штуки выдаются
## по мере накопления; остаток < 1 хранится в _yield_pool и сгорает при истощении.
@export var yield_per_hit: float = 2.0
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

@export_group("Winter")
## Открытый водоём замерзает зимой (Seasons.water_freezes). Колодец — нет.
@export var freezes_in_winter: bool = false

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
## Накопленная дробная добыча (< 1): целые штуки выдаются по мере накопления.
## В сейв не пишется и при истощении/возрождении сгорает.
var _yield_pool: float = 0.0
## Накопленный урон по жиле (для дробного снижения силы удара затупленным инструментом)
var _damage_pool: float = 0.0
## Всего добыто с узла за его жизнь (для итога «Жила выработана»).
var _harvest_total: int = 0
## Саженец посажен на пень и растёт.
var is_growing: bool = false
## Сколько игровых часов саженец уже растёт.
var growth_progress_hours: float = 0.0
var _original_scale: Vector3 = Vector3.ONE
var _day_cycle: Node = null
## Предыдущее состояние промерзания — чтобы обновлять лёд один раз на смену.
var _was_frozen: bool = false

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
	
	_update_frozen_visual()
	set_process(is_depleted or is_growing or freezes_in_winter)

func _process(delta: float) -> void:
	# Открытая вода следит за сезоном: промерзание и оттепель меняют вид и подсказку.
	if freezes_in_winter:
		var frozen_now: bool = is_frozen()
		if frozen_now != _was_frozen:
			_was_frozen = frozen_now
			_update_frozen_visual()
		if not is_depleted and not is_growing:
			return
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
	AudioManager.play("plant")
	var skills: Object = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("add_xp"):
		skills.add_xp("woodcutting", 10)
	if player and player.has_method("notify"):
		player.notify("🌱 Саженец посажен! %s вырастет через %d игр. ч." % [resource_display_name, int(ceil(growth_hours))])
	return true

func _update_growth_visual() -> void:
	if not visual_node or not is_growing:
		return
	var k: float = lerpf(SAPLING_START_SCALE, 0.9, get_growth_ratio())
	visual_node.scale = _original_scale * k

## Открытый водоём зимой замёрз: добывать из него нельзя (колодец работает круглый год).
func is_frozen() -> bool:
	return freezes_in_winter and Seasons.water_freezes()

func get_frozen_prompt() -> String:
	return "❄️ %s: вода замёрзла — дождитесь оттепели или копайте колодец" % object_name

func _update_frozen_visual() -> void:
	if not visual_node:
		return
	var surface: Node = visual_node.get_node_or_null("WaterSurface")
	if not (surface is MeshInstance3D):
		return
	var mesh: MeshInstance3D = surface
	var mat: StandardMaterial3D = null
	if mesh.material_override is StandardMaterial3D:
		mat = mesh.material_override
	elif mesh.mesh is PrimitiveMesh:
		var prim: PrimitiveMesh = mesh.mesh
		var surf_mat: Material = prim.material
		if surf_mat is StandardMaterial3D:
			# Материал лежит на общем ресурсе сцены — копируем, чтобы лёд не утёк на все водоёмы.
			var prim_copy: PrimitiveMesh = prim.duplicate()
			mat = (surf_mat as StandardMaterial3D).duplicate()
			prim_copy.material = mat
			mesh.mesh = prim_copy
	if mat == null:
		return
	if is_frozen():
		mat.albedo_color = Color(0.82, 0.90, 0.98, 0.95)
		mat.roughness = 0.55
	else:
		mat.albedo_color = Color(0.18, 0.58, 0.82, 0.88)
		mat.roughness = 0.15

func get_prompt() -> String:
	if is_frozen():
		return get_frozen_prompt()
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
	if is_frozen():
		if player and player.has_method("notify"):
			player.notify(get_frozen_prompt())
		return
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

	# Острота инструмента (затупление и заточка)
	var sharpness_eff: Dictionary = {"power_mult": 1.0, "energy_cost_mult": 1.0, "is_dull": false, "crit_bonus": 0.0}
	if inv and inv.has_method("get_sharpness_efficiency"):
		sharpness_eff = inv.get_sharpness_efficiency(required_tool)
		final_energy_cost *= float(sharpness_eff.get("energy_cost_mult", 1.0))
		if float(sharpness_eff.get("crit_bonus", 0.0)) > 0.0 and randf() < float(sharpness_eff.get("crit_bonus", 0.0)):
			bonus_yield += 1

	# Списание остроты за удар
	if inv and inv.has_method("consume_tool_sharpness"):
		var dull_cost: float = 0.8 if required_tool == "axe" else (1.0 if required_tool == "pickaxe" else 0.6)
		inv.consume_tool_sharpness(required_tool, dull_cost)
	
	# Прокачка навыков (Learn by doing)
	var skills: Object = player.get("skills") if player and "skills" in player else null
	var target_skill: String = "mining"
	if required_tool == "axe" or resource_id == "wood":
		target_skill = "woodcutting"
	elif required_tool == "bucket" or resource_id in ["dirty_water", "water", "clean_water"]:
		target_skill = "hydrology"
	elif is_mining_node:
		target_skill = "mining"
	
	if skills:
		if skills.has_method("get_energy_discount"):
			final_energy_cost *= maxf(0.1, 1.0 - skills.get_energy_discount(target_skill))
		if skills.has_method("roll_bonus_yield") and skills.roll_bonus_yield(target_skill):
			bonus_yield += 1
		if skills.has_method("add_xp"):
			skills.add_xp(target_skill, 5)
	
	# Трата энергии
	if player.has_method("consume_energy"):
		player.consume_energy(final_energy_cost)
	# Сбор ресурсов расходует сытость и жажду
	if player.has_method("consume_hunger"):
		player.consume_hunger(0.5)
	if player.has_method("consume_thirst"):
		player.consume_thirst(0.5)
	
	# Звук удара (Game Feel) — при критически затупленном лезвии звук глухой
	var pitch: float = 0.65 if (float(sharpness_eff.get("power_mult", 1.0)) <= 0.5) else 1.0
	if required_tool == "axe" or resource_id == "wood":
		AudioManager.play("hit_wood", pitch)
	elif resource_id == "metal_scrap":
		AudioManager.play("hit_metal", pitch)
	else:
		AudioManager.play("hit_stone", pitch)
	
	# Визуальный отклик (shake tween)
	_play_hit_effect()
	
	# Добыча (с учетом эффективности заточки лезвия)
	var raw_power: float = float(hit_power) * float(sharpness_eff.get("power_mult", 1.0))
	_damage_pool += raw_power
	var dealt: int = int(floor(_damage_pool))
	_damage_pool -= float(dealt)
	current_hits -= dealt
	_yield_pool += float(yield_per_hit) + float(bonus_yield)
	var gained: int = int(floor(_yield_pool))
	_yield_pool -= float(gained)
	_harvest_total += gained
	var item_icon: String = ItemDB.get_item_icon(resource_id)
	
	if current_hits <= 0:
		# Истощение
		if skills and skills.has_method("add_xp"):
			skills.add_xp(target_skill, 25)
		gained += bonus_depleted_yield
		if inv:
			# Рюкзак полон — добыча падает кучкой у узла, а не пропадает.
			DroppedItemScript.give_or_drop(player, resource_id, gained, global_position, get_parent())

		resource_gathered.emit(resource_id, gained)
		_set_depleted(true)

		var msg_depleted: String = "✅ %s %s +%d! Жила полностью выработана." % [
			item_icon, resource_display_name, _harvest_total
		]
		if requires_planting:
			var saplings: int = maxi(0, sapling_yield)
			if inv and saplings > 0:
				DroppedItemScript.give_or_drop(player, SAPLING_ID, saplings, global_position, get_parent())
			msg_depleted = "✅ %s %s +%d, 🌱 саженец +%d. Дерево не отрастёт само — посадите саженец на пень." % [
				item_icon, resource_display_name, _harvest_total, saplings
			]
		if player.has_method("notify"):
			player.notify(msg_depleted)
	else:
		if inv:
			# Рюкзак полон — добыча падает кучкой у узла, а не пропадает.
			DroppedItemScript.give_or_drop(player, resource_id, gained, global_position, get_parent())

		resource_gathered.emit(resource_id, gained)
		
		var msg_hit: String
		if gained > 0:
			msg_hit = "%s %s +%d (Прочность: %d/%d)" % [
				item_icon, resource_display_name, gained, current_hits, max_hits
			]
		else:
			msg_hit = "%s %s +0 (до целого %.2f; Прочность: %d/%d)" % [
				item_icon, resource_display_name, _yield_pool, current_hits, max_hits
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
	_spawn_hit_crumbs()

## Взрыв крошки в цвет ресурса при ударе: рубка (щепа), камень (осколки),
## руда/металлолом (искры окалины), вода (брызги). Как у воксельных жил.
func _spawn_hit_crumbs() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var tint: Color = Color(0.55, 0.42, 0.28)
	match resource_id:
		"wood":
			tint = Color(0.5, 0.33, 0.16)
		"stone":
			tint = Color(0.62, 0.62, 0.65)
		"metal_scrap", "iron_ore", "coal":
			tint = Color(0.75, 0.45, 0.2)
		"clay":
			tint = Color(0.7, 0.42, 0.26)
		"sand":
			tint = Color(0.85, 0.75, 0.5)
		"water", "dirty_water", "clean_water":
			tint = Color(0.4, 0.68, 0.95)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.06
	var mat_res := StandardMaterial3D.new()
	mat_res.albedo_color = tint
	bm.material = mat_res
	p.mesh = bm
	add_child(p)
	p.position = Vector3(0, 1.0, 0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _set_depleted(depleted: bool) -> void:
	is_depleted = depleted
	# Недобранная дробная добыча (< 1) при истощении и возрождении сгорает.
	_yield_pool = 0.0
	_damage_pool = 0.0
	if not depleted:
		_harvest_total = 0
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
