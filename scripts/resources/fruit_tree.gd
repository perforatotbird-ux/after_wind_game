extends "res://scripts/interaction/interactable.gd"

## Фруктовое дерево (Яблоня, Груша, Вишня) — раздел 8.2 мастер-плана.
## Многолетняя посадка: стадии (саженец -> молодое -> взрослое),
## сезонный сбор плодов [E], отрастание урожая, рубка топором с возвратом саженца.
## Без class_name (как berry_bush.gd): подключать через preload-const.

const ItemDB = preload("res://scripts/inventory/item_db.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

const CherryModel = preload("res://assets/models/cherry/cherry_with_fruit.tscn")
const AppleModel = preload("res://assets/models/apple/apple_with_fruit.tscn")
const ApricotModel = preload("res://assets/models/apricot/apricot_with_fruit.tscn")

const GROUP: String = "fruit_trees"
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0

enum Stage {
	SAPLING = 0, # Саженец
	YOUNG = 1,   # Молодое дерево
	MATURE = 2   # Взрослое плодоносящее
}

const CONFIGS: Dictionary = {
	"apple_tree": {
		"name": "Яблоня",
		"fruit_id": "apple",
		"fruit_name": "яблоки",
		"sapling_id": "apple_sapling",
		"yield_range": [4, 8],
		# Часы роста по стадиям: саженец -> молодое, молодое -> взрослое.
		# Яблоня — 3 игровых дня (24 + 48 ч) до первого урожая.
		"grow_hours": [24.0, 48.0],
		"fruit_color": Color(0.88, 0.18, 0.15),
		"canopy_color": Color(0.28, 0.55, 0.22),
		"seasons": ["autumn"],
	},
	"pear_tree": {
		"name": "Груша",
		"fruit_id": "pear",
		"fruit_name": "груши",
		"sapling_id": "pear_sapling",
		"yield_range": [3, 6],
		# Груша — 4 игровых дня (24 + 72 ч) до первого урожая.
		"grow_hours": [24.0, 72.0],
		"fruit_color": Color(0.82, 0.74, 0.22),
		"canopy_color": Color(0.32, 0.58, 0.24),
		"seasons": ["autumn"],
	},
	"cherry_tree": {
		"name": "Вишня",
		"fruit_id": "cherry",
		"fruit_name": "вишню",
		"sapling_id": "cherry_sapling",
		"yield_range": [6, 12],
		# Вишня — 3 игровых дня (24 + 48 ч) до первого урожая.
		"grow_hours": [24.0, 48.0],
		"fruit_color": Color(0.72, 0.08, 0.14),
		"canopy_color": Color(0.35, 0.62, 0.26),
		"seasons": ["summer"],
	},
	"apricot_tree": {
		"name": "Абрикос",
		"fruit_id": "apricot",
		"fruit_name": "абрикосы",
		"sapling_id": "apricot_sapling",
		"yield_range": [5, 9],
		# Абрикос — 3 игровых дня (24 + 48 ч) до первого урожая.
		"grow_hours": [24.0, 48.0],
		"fruit_color": Color(0.96, 0.60, 0.15),
		"canopy_color": Color(0.30, 0.58, 0.24),
		"seasons": ["summer"],
	}
}

@export var tree_type: String = "apple_tree"
@export var stage: int = Stage.MATURE
@export var has_fruit: bool = true
@export var fruit_regrow_hours: float = 24.0
@export var regrow_progress: float = 0.0
@export var growth_progress: float = 0.0
@export var max_hits: int = 8
@export var current_hits: int = 8
## Накопленная дробная древесина (0.25 за удар, как у лесных деревьев).
var _wood_pool: float = 0.0
## Накопленный урон по дереву (для затупленного инструмента)
var _damage_pool: float = 0.0

var _visuals_root: Node3D = null
var _trunk_mesh: MeshInstance3D = null
var _canopy_mesh: MeshInstance3D = null
var _fruits_node: Node3D = null
var _day_cycle: Node = null
var _static_body: StaticBody3D = null

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	add_to_group("saveable")
	var cfg: Dictionary = _get_config()
	object_name = cfg.get("name", "Фруктовое дерево")
	prompt_action = "Собрать урожай"
	_setup_collision()
	_build_visuals()
	_update_visuals()

func _setup_collision() -> void:
	# Коллизия Area3D для взаимодействия игрока
	var existing_col = get_node_or_null("CollisionShape3D")
	if not existing_col:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.4
		shape.height = 3.5
		col.shape = shape
		col.position.y = 1.75
		add_child(col)

	# Физическое препятствие для ствола
	_static_body = get_node_or_null("TrunkBody") as StaticBody3D
	if not _static_body:
		_static_body = StaticBody3D.new()
		_static_body.name = "TrunkBody"
		_static_body.collision_layer = 1
		_static_body.collision_mask = 0
		var sb_col := CollisionShape3D.new()
		var sb_shape := CylinderShape3D.new()
		sb_shape.radius = 0.35
		sb_shape.height = 2.0
		sb_col.shape = sb_shape
		sb_col.position.y = 1.0
		_static_body.add_child(sb_col)
		add_child(_static_body)

func _get_config() -> Dictionary:
	return CONFIGS.get(tree_type, CONFIGS["apple_tree"])

func _process(delta: float) -> void:
	var hours: float = delta * _get_hours_per_second()
	advance_hours(hours)

func advance_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	var cfg: Dictionary = _get_config()

	# Рост дерева (время идёт круглый год, вне зависимости от сезона).
	if stage < Stage.MATURE:
		var gh: Array = cfg.get("grow_hours", [12.0, 24.0])
		var need: float = float(gh[0]) if stage == Stage.SAPLING else float(gh[1])
		growth_progress += hours
		if growth_progress >= need:
			stage += 1
			growth_progress = 0.0
			if stage == Stage.MATURE:
				has_fruit = true
			_update_visuals()
		return

	# Отрастание плодов у взрослого дерева
	if not has_fruit:
		var seasons: Array = cfg.get("seasons", ["summer", "autumn"])
		if Seasons.is_in_season(seasons):
			regrow_progress += hours
			if regrow_progress >= fruit_regrow_hours:
				has_fruit = true
				regrow_progress = 0.0
				_update_visuals()

func _build_visuals() -> void:
	if _visuals_root:
		remove_child(_visuals_root)
		_visuals_root.queue_free()
	_trunk_mesh = null
	_canopy_mesh = null
	_fruits_node = null

	_visuals_root = Node3D.new()
	_visuals_root.name = "TreeVisuals"
	add_child(_visuals_root)

	# Яблоня, вишня и абрикос по референсам: общий ствол и крона, отдельный узел плодов.
	# Молодые стадии используют ту же модель без плодов; сбор не перестраивает меши.
	if tree_type in ["cherry_tree", "apple_tree", "apricot_tree"]:
		var packed: PackedScene = AppleModel
		if tree_type == "cherry_tree":
			packed = CherryModel
		elif tree_type == "apricot_tree":
			packed = ApricotModel
		var model: Node3D = packed.instantiate()
		_visuals_root.add_child(model)
		_trunk_mesh = model.get_node_or_null("Trunk")
		_fruits_node = model.get_node_or_null("Fruits")
		return

	var cfg: Dictionary = _get_config()
	var wood_col: Color = Color(0.42, 0.28, 0.16)
	var canopy_col: Color = cfg.get("canopy_color", Color(0.3, 0.55, 0.2))
	var fruit_col: Color = cfg.get("fruit_color", Color(0.88, 0.18, 0.15))

	# Ствол
	_trunk_mesh = MeshInstance3D.new()
	_trunk_mesh.name = "Trunk"
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = wood_col
	trunk_mat.roughness = 0.9
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.32
	cyl.height = 2.2
	_trunk_mesh.mesh = cyl
	_trunk_mesh.position.y = 1.1
	_trunk_mesh.material_override = trunk_mat
	_visuals_root.add_child(_trunk_mesh)

	# Крона
	_canopy_mesh = MeshInstance3D.new()
	_canopy_mesh.name = "Canopy"
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = canopy_col
	canopy_mat.roughness = 0.85
	var sph := SphereMesh.new()
	sph.radius = 1.35
	sph.height = 2.4
	_canopy_mesh.mesh = sph
	_canopy_mesh.position.y = 2.6
	_canopy_mesh.material_override = canopy_mat
	_visuals_root.add_child(_canopy_mesh)

	# Плоды
	_fruits_node = Node3D.new()
	_fruits_node.name = "Fruits"
	_fruits_node.position.y = 2.6
	var fruit_mat := StandardMaterial3D.new()
	fruit_mat.albedo_color = fruit_col
	fruit_mat.roughness = 0.5
	var fruit_mesh := SphereMesh.new()
	fruit_mesh.radius = 0.10
	fruit_mesh.height = 0.20

	var offsets: Array[Vector3] = [
		Vector3(0.9, -0.3, 0.8),
		Vector3(-0.85, -0.2, 0.8),
		Vector3(1.1, 0.2, -0.4),
		Vector3(-0.95, 0.1, -0.7),
		Vector3(0.1, -0.4, 1.25),
		Vector3(0.3, 0.6, 0.8),
		Vector3(-0.4, 0.5, -0.85),
		Vector3(0.0, -0.5, -1.2)
	]
	for pos in offsets:
		var fi := MeshInstance3D.new()
		fi.mesh = fruit_mesh
		fi.position = pos
		fi.material_override = fruit_mat
		_fruits_node.add_child(fi)

	_visuals_root.add_child(_fruits_node)

func _update_visuals() -> void:
	if not _visuals_root:
		return

	match stage:
		Stage.SAPLING:
			_visuals_root.scale = Vector3(0.3, 0.3, 0.3)
			if _canopy_mesh:
				_canopy_mesh.scale = Vector3(0.4, 0.4, 0.4)
				_canopy_mesh.position.y = 1.4
			if _fruits_node:
				_fruits_node.visible = false
			if _static_body:
				_static_body.collision_layer = 0
		Stage.YOUNG:
			_visuals_root.scale = Vector3(0.65, 0.65, 0.65)
			if _canopy_mesh:
				_canopy_mesh.scale = Vector3(0.75, 0.75, 0.75)
				_canopy_mesh.position.y = 2.0
			if _fruits_node:
				_fruits_node.visible = false
			if _static_body:
				_static_body.collision_layer = 1
		Stage.MATURE:
			_visuals_root.scale = Vector3.ONE
			if _canopy_mesh:
				_canopy_mesh.scale = Vector3.ONE
				_canopy_mesh.position.y = 2.6
			if _fruits_node:
				_fruits_node.visible = has_fruit
			if _static_body:
				_static_body.collision_layer = 1

func get_prompt() -> String:
	var cfg: Dictionary = _get_config()
	if stage < Stage.MATURE:
		return "[E] Осмотреть (молодое дерево растёт) (%s)" % cfg.get("name", "")
	if has_fruit:
		return "[E] Собрать урожай (%s)" % cfg.get("name", "")
	return "[E] Срубить топором / осмотреть (%s)" % cfg.get("name", "")

func _on_interacted(player: Node) -> void:
	var inv = player.get("inventory") if player and "inventory" in player else null
	var cfg: Dictionary = _get_config()

	# Спелые плоды собираются первыми — даже с топором в руках.
	if stage >= Stage.MATURE and has_fruit:
		harvest(player)
		return

	# Без плодов и с топором — рубка (убрать молодое или срубить пустое).
	if inv and inv.has_method("is_tool_equipped") and inv.is_tool_equipped("axe"):
		chop(player)
		return

	# Дерево пустое и топора нет — статус (рост / ожидание плодов).
	if stage < Stage.MATURE:
		if player and player.has_method("notify"):
			var st_name: String = "Саженец" if stage == Stage.SAPLING else "Молодое дерево"
			player.notify("🌱 %s (%s). Дерево подрастает." % [st_name, cfg.get("name", "")])
		return

	if player and player.has_method("notify"):
		var seasons: Array = cfg.get("seasons", [])
		if not Seasons.is_in_season(seasons):
			player.notify("🍂 %s сейчас не плодоносит (сезон сбора: %s)." % [cfg.get("name", ""), ", ".join(seasons)])
		else:
			var left: int = maxi(1, int(fruit_regrow_hours - regrow_progress))
			player.notify("⏳ Плоды ещё созревают (примерно %d ч)." % left)

func harvest(player: Node) -> int:
	if not has_fruit or stage < Stage.MATURE:
		return 0

	var cfg: Dictionary = _get_config()
	var fruit_id: String = cfg.get("fruit_id", "apple")
	var yr: Array = cfg.get("yield_range", [3, 5])
	var count: int = randi_range(int(yr[0]), int(yr[1]))
	
	var skills: Object = player.get("skills") if player and "skills" in player else null
	if skills and skills.has_method("roll_bonus_yield") and skills.roll_bonus_yield("orchard"):
		count += 1

	var drop_at: Vector3 = global_position + Vector3(0.0, 1.2, 0.0)
	DroppedItemScript.give_or_drop(player, fruit_id, count, drop_at, get_parent())

	AudioManager.play("harvest")
	has_fruit = false
	regrow_progress = 0.0
	_update_visuals()

	if skills and skills.has_method("add_xp"):
		skills.add_xp("orchard", 15)

	if player and player.has_method("notify"):
		player.notify("🧺 Собрано: %s ×%d!" % [ItemDB.get_item_name(fruit_id), count])

	return count

func chop(player: Node) -> bool:
	var inv = player.get("inventory") if player and "inventory" in player else null
	var sharpness_eff: Dictionary = {"power_mult": 1.0, "energy_cost_mult": 1.0, "is_dull": false, "crit_bonus": 0.0}
	if inv and inv.has_method("get_sharpness_efficiency"):
		sharpness_eff = inv.get_sharpness_efficiency("axe")

	var skills: Object = player.get("skills") if player and "skills" in player else null
	var energy_cost: float = 1.5 * float(sharpness_eff.get("energy_cost_mult", 1.0))
	if skills and skills.has_method("get_energy_discount"):
		energy_cost *= maxf(0.1, 1.0 - skills.get_energy_discount("woodcutting"))
	
	if player and player.has_method("consume_energy"):
		player.consume_energy(energy_cost)

	# Списание остроты топора
	if inv and inv.has_method("consume_tool_sharpness"):
		inv.consume_tool_sharpness("axe", 0.8)

	var pitch: float = 0.65 if (float(sharpness_eff.get("power_mult", 1.0)) <= 0.5) else 1.0
	AudioManager.play("hit_wood", pitch)
	_spawn_chop_crumbs()

	var raw_power: float = 1.0 * float(sharpness_eff.get("power_mult", 1.0))
	_damage_pool += raw_power
	var dealt: int = int(floor(_damage_pool))
	_damage_pool -= float(dealt)
	current_hits -= dealt

	if skills and skills.has_method("add_xp"):
		skills.add_xp("woodcutting", 3)

	# Древесина капает дробно (0.25 за удар): целая выдаётся каждую 4-ю.
	var drop_at: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
	var wood_gain: float = 0.25
	if float(sharpness_eff.get("crit_bonus", 0.0)) > 0.0 and randf() < float(sharpness_eff.get("crit_bonus", 0.0)):
		wood_gain += 0.25
	_wood_pool += wood_gain
	var whole: int = int(floor(_wood_pool))
	_wood_pool -= float(whole)
	if whole > 0:
		DroppedItemScript.give_or_drop(player, "wood", whole, drop_at, get_parent())

	if current_hits <= 0:
		if skills and skills.has_method("add_xp"):
			skills.add_xp("woodcutting", 15)
		# Дерево срублено! Возвращаем древесину и саженец
		var cfg: Dictionary = _get_config()
		var sapling_id: String = cfg.get("sapling_id", "apple_sapling")
		DroppedItemScript.give_or_drop(player, "wood", 2, drop_at, get_parent())
		DroppedItemScript.give_or_drop(player, sapling_id, 1, drop_at, get_parent())
		AudioManager.play("hit_wood")
		if player and player.has_method("notify"):
			player.notify("🪓 %s срублена! Получены древесина и %s." % [cfg.get("name", ""), ItemDB.get_item_name(sapling_id)])
		queue_free()
		return true

	if player and player.has_method("notify"):
		player.notify("🪓 Удар по дереву! Осталось ударов: %d" % current_hits)
	return false

## Щепа при ударе топором — как крошка у обычных деревьев и жил.
func _spawn_chop_crumbs() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
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
	mat_res.albedo_color = Color(0.5, 0.33, 0.16)
	bm.material = mat_res
	p.mesh = bm
	add_child(p)
	p.position = Vector3(0, 1.2, 0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func get_save_state() -> Dictionary:
	return {
		"type": tree_type,
		"pos": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"stage": stage,
		"growth": snappedf(growth_progress, 0.1),
		"has_fruit": has_fruit,
		"regrow": snappedf(regrow_progress, 0.1),
		"hits": current_hits
	}

func apply_save_state(data: Dictionary) -> void:
	tree_type = str(data.get("type", tree_type))
	var cfg: Dictionary = _get_config()
	object_name = cfg.get("name", object_name)
	stage = int(data.get("stage", stage))
	# Числа зажимаем, как в berry_bush/resource_node: битый сейв не должен
	# давать мгновенное созревание, вечное ожидание плодов или падение с 1 удара.
	growth_progress = maxf(0.0, float(data.get("growth", 0.0)))
	has_fruit = bool(data.get("has_fruit", true))
	regrow_progress = clampf(float(data.get("regrow", 0.0)), 0.0, fruit_regrow_hours)
	current_hits = clampi(int(data.get("hits", max_hits)), 0, max_hits)
	if data.has("pos"):
		var p: Array = data["pos"]
		if p.size() >= 3:
			global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_build_visuals()
	_update_visuals()

func _get_hours_per_second() -> float:
	if not is_instance_valid(_day_cycle):
		_day_cycle = null
		var tree := get_tree()
		if tree:
			_day_cycle = tree.get_first_node_in_group("day_night_cycle")
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		return float(_day_cycle.get_hours_per_second())
	return FALLBACK_HOURS_PER_SECOND
