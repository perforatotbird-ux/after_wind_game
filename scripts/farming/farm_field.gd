extends "res://scripts/interaction/interactable.gd"

## Делянка — фермерский участок произвольного размера (от 1 до MAX_CELLS клеток),
## который игрок ставит мышкой из рюкзака (FarmFieldPlacer).
##
## Жизненный цикл:
## 1. BLUEPRINT — размечена колышками и шнуром; игрок приносит материалы (E),
##    стоимость считается по размеру (cost_for). X дважды — отменить и забрать материалы.
## 2. BUILDING — стройка идёт BUILD_HOURS игровых часов (1 игровой день): по мере
##    прогресса появляются бортик и грядки.
## 3. READY — каждая клетка независима: свои семена, влага, плодородие, уход.
##    E — умное действие над клеткой (или зоной 3×3, клавиша G): убрать увядшее →
##    собрать урожай → посадить выбранные семена (R — сменить) → полить → удобрить.
## Правила роста — scripts/farming/crop_db.gd.

const CropDB = preload("res://scripts/farming/crop_db.gd")
const Meshes = preload("res://scripts/farming/farm_field_meshes.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")

const GROUP: String = "farm_fields"
const MAX_CELLS: int = 128
const BUILD_HOURS: float = 24.0
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0
## Полив одной порцией воды: одна клетка или каждая клетка зоны 3×3.
const WATER_SINGLE: float = 70.0
const WATER_ZONE: float = 40.0
## Порог «пора поливать» над нижней границей нормы культуры.
const WATER_HINT_MARGIN: float = 15.0
## Влага новой делянки (земля полита при постройке).
const START_MOISTURE: float = 35.0
## Сколько клеток удобряет одна порция удобрения.
const CELLS_PER_FERTILIZER: int = 3
const REACH: float = 1.9

enum State { BLUEPRINT, BUILDING, READY }

signal state_changed(new_state: int)
signal cell_changed(cell: Vector2i)

var size: Vector2i = Vector2i(2, 2)
var state: int = State.BLUEPRINT
var delivered: Dictionary = {}
var build_progress: float = 0.0
## Клетки построчно: index = z * size.x + x.
var cells: Array = []
## Размер зоны действия: 1 (клетка) или 3 (3×3).
var zone_size: int = 1
var target_cell: Vector2i = Vector2i(-1, -1)

var _day_cycle: Node = null
var _cached_player: Node = null
var _prompt_dirty: bool = false
var _visual_keys: PackedStringArray = []
var _soil_keys: PackedInt32Array = []
var _built_shown: int = -1
var _cancel_armed_msec: int = -1
var _rng := RandomNumberGenerator.new()

var _shape: CollisionShape3D
var _mulch: MeshInstance3D
var _border: MeshInstance3D
var _survey: MeshInstance3D
var _area_fill: MeshInstance3D
var _pile: MeshInstance3D
var _sign: MeshInstance3D
var _label: Label3D
var _soil_mmi: MultiMeshInstance3D
var _crop_mmis: Dictionary = {}
var _highlight: MeshInstance3D

## Стоимость делянки w×h: бортик — древесина по периметру, дренаж — камень,
## мульча и компост в грядки — опилки.
static func cost_for(w: int, h: int) -> Dictionary:
	var n: int = maxi(1, w) * maxi(1, h)
	var perimeter: int = 2 * (maxi(1, w) + maxi(1, h))
	return {
		"wood": 4 + ceili(perimeter * 0.5),
		"stone": ceili(n / 4.0),
		"sawdust": ceili(n / 4.0),
	}

## Создаёт делянку в parent с углом в origin (мировые XZ, y игнорируется).
static func spawn(parent: Node, origin: Vector3, w: int, h: int) -> Node:
	var f = load("res://scripts/farming/farm_field.gd").new()
	f.size = Vector2i(clampi(w, 1, MAX_CELLS), clampi(h, 1, MAX_CELLS))
	f.name = "FarmField_%d_%d" % [int(round(origin.x)), int(round(origin.z))]
	parent.add_child(f)
	if f.is_inside_tree():
		f.global_position = Vector3(origin.x, 0.0, origin.z)
	else:
		f.position = Vector3(origin.x, 0.0, origin.z)
	return f

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	object_name = "Делянка"
	prompt_action = "Работать"
	_rng.randomize()
	if cells.size() != size.x * size.y:
		_reset_cells()
	_build_nodes()
	_refresh_all_visuals()
	_clear_decor.call_deferred()

func get_cell_count() -> int:
	return size.x * size.y

## Прямоугольник делянки на плоскости XZ мира.
func get_rect() -> Rect2:
	return Rect2(global_position.x, global_position.z, size.x, size.y)

func get_cost() -> Dictionary:
	return cost_for(size.x, size.y)

func _reset_cells() -> void:
	cells.clear()
	for i in get_cell_count():
		cells.append(_new_cell())

static func _new_cell() -> Dictionary:
	return {"crop": "", "growth": 0.0, "moisture": START_MOISTURE, "fertility": CropDB.START_FERTILITY,
		"fertilized": false, "withered": false, "drought": 0.0, "care": 0.0, "total": 0.0, "last_crop": ""}

func get_cell(c: Vector2i) -> Dictionary:
	if not is_cell_valid(c):
		return {}
	return cells[c.y * size.x + c.x]

func is_cell_valid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func cell_center_global(c: Vector2i) -> Vector3:
	return global_position + Vector3(c.x + 0.5, Meshes.BED_HEIGHT, c.y + 0.5)

func is_ripe(c: Vector2i) -> bool:
	var d: Dictionary = get_cell(c)
	return not d.is_empty() and d["crop"] != "" and not d["withered"] and float(d["growth"]) >= float(CropDB.get_crop(d["crop"])["growth_hours"])

## Прогресс культуры клетки 0..1.
func get_progress(c: Vector2i) -> float:
	var d: Dictionary = get_cell(c)
	if d.is_empty() or d["crop"] == "":
		return 0.0
	return clampf(float(d["growth"]) / float(CropDB.get_crop(d["crop"])["growth_hours"]), 0.0, 1.0)

func get_quality(c: Vector2i) -> int:
	var d: Dictionary = get_cell(c)
	if d.is_empty() or float(d["total"]) <= 0.0:
		return 0
	return CropDB.quality_for(float(d["care"]) / float(d["total"]))

# --- Время ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance_hours(delta * _get_hours_per_second(), false)

## Продвигает стройку и рост на hours игровых часов (крупные шаги дробятся).
func advance_hours(hours: float, refresh: bool = true) -> void:
	if hours <= 0.0:
		return
	var left: float = hours
	while left > 0.0:
		var step: float = minf(left, 0.5)
		left -= step
		_tick(step)
	if refresh:
		_refresh_all_visuals()
	else:
		_refresh_if_changed()

func _tick(h: float) -> void:
	match state:
		State.BUILDING:
			build_progress += h
			if build_progress >= BUILD_HOURS:
				_finish_building()
		State.READY:
			var farmer: bool = _is_farmer()
			for i in cells.size():
				_tick_cell(cells[i], h, farmer)

func _tick_cell(d: Dictionary, h: float, farmer: bool) -> void:
	var crop: String = d["crop"]
	if crop == "" or d["withered"] or float(d["growth"]) >= float(CropDB.get_crop(crop).get("growth_hours", 1.0)):
		d["moisture"] = maxf(0.0, float(d["moisture"]) - CropDB.EMPTY_EVAPORATION * h)
		if crop == "":
			d["fertility"] = minf(100.0, float(d["fertility"]) + CropDB.FALLOW_RECOVERY * h)
		return
	var info: Dictionary = CropDB.get_crop(crop)
	var m: float = float(d["moisture"])
	var mf: float = CropDB.moisture_factor(crop, m)
	d["total"] = float(d["total"]) + h
	if mf >= 1.0:
		d["care"] = float(d["care"]) + h
	if m <= 0.0:
		d["drought"] = float(d["drought"]) + h
		if float(d["drought"]) >= float(info["wither_hours"]):
			d["withered"] = true
			return
	else:
		d["drought"] = 0.0
	var speed: float = mf * CropDB.soil_factor(float(d["fertility"]))
	if d["fertilized"]:
		speed *= CropDB.FERTILIZED_SPEED
	if farmer:
		speed *= CropDB.FARMER_SPEED
	if not Seasons.is_in_season(info["seasons"]):
		speed = 0.0
	d["growth"] = minf(float(info["growth_hours"]), float(d["growth"]) + h * speed)
	d["moisture"] = maxf(0.0, m - float(info["water_use"]) * h)

func _finish_building() -> void:
	build_progress = BUILD_HOURS
	state = State.READY
	_reset_cells()
	_prompt_dirty = true
	state_changed.emit(state)
	_refresh_all_visuals()
	var p := _get_player()
	if p and p.has_method("notify"):
		p.notify("🌾 Делянка %d×%d построена! Сажайте семена (E), R — выбор семян, G — зона 3×3." % [size.x, size.y])

## Дождь: hydration % влаги каждой клетке (вызывает WeatherManager).
func apply_rain(hydration: float) -> void:
	if state != State.READY or hydration <= 0.0:
		return
	for d in cells:
		d["moisture"] = minf(100.0, float(d["moisture"]) + hydration)
		if float(d["moisture"]) > 0.0:
			d["drought"] = 0.0

func _is_farmer() -> bool:
	var p := _get_player()
	return p != null and p.get("character_class") == "farmer"

func _get_player() -> Node:
	if is_instance_valid(_cached_player):
		return _cached_player
	if not is_inside_tree():
		return null
	_cached_player = get_tree().root.find_child("Player", true, false)
	return _cached_player

func _get_hours_per_second() -> float:
	if not is_instance_valid(_day_cycle):
		_day_cycle = null
		if is_inside_tree():
			_day_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		return float(_day_cycle.get_hours_per_second())
	return FALLBACK_HOURS_PER_SECOND

# --- Прицел --------------------------------------------------------------------------

## Клетка перед персонажем (или ближайшая в досягаемости). false — делать нечего.
func update_aim(player: Node3D) -> bool:
	_cached_player = player
	var c: Vector2i = _pick_cell(player)
	if state != State.READY:
		var near: bool = _distance_to_rect(player.global_position) <= REACH
		if c != target_cell:
			target_cell = c
		_update_highlight()
		return near
	if c != target_cell:
		target_cell = c
		_prompt_dirty = true
	_update_highlight()
	return is_cell_valid(target_cell)

func _pick_cell(player: Node3D) -> Vector2i:
	var facing := Vector3.FORWARD
	var vr = player.get("visual_root")
	if vr is Node3D:
		facing = -(vr as Node3D).global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.001 else Vector3.FORWARD
	var aim: Vector3 = player.global_position + facing * 0.75 - global_position
	var c := Vector2i(floori(aim.x), floori(aim.z))
	if is_cell_valid(c):
		return c
	var cc := Vector2i(clampi(c.x, 0, size.x - 1), clampi(c.y, 0, size.y - 1))
	var center: Vector3 = cell_center_global(cc)
	var flat := Vector2(player.global_position.x - center.x, player.global_position.z - center.z)
	return cc if flat.length() <= REACH else Vector2i(-1, -1)

func _distance_to_rect(p: Vector3) -> float:
	var r := get_rect()
	var dx: float = maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz: float = maxf(maxf(r.position.y - p.z, 0.0), p.z - r.end.y)
	return Vector2(dx, dz).length()

func get_interaction_point() -> Vector3:
	if is_cell_valid(target_cell):
		return cell_center_global(target_cell)
	var p := _get_player()
	if p:
		var r := get_rect()
		return Vector3(clampf(p.global_position.x, r.position.x, r.end.x), 0.0, clampf(p.global_position.z, r.position.y, r.end.y))
	return global_position

func consume_prompt_dirty() -> bool:
	var was: bool = _prompt_dirty
	_prompt_dirty = false
	return was

## Ручной выбор клетки (тесты).
func set_target_cell(c: Vector2i) -> void:
	target_cell = c if is_cell_valid(c) else Vector2i(-1, -1)
	_prompt_dirty = true
	_update_highlight()

## Клетки зоны действия вокруг клетки c.
func zone_cells(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_cell_valid(c):
		return out
	var r: int = 1 if zone_size == 3 else 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := Vector2i(c.x + dx, c.y + dz)
			if is_cell_valid(n):
				out.append(n)
	return out

func toggle_zone(player: Node = null) -> void:
	zone_size = 3 if zone_size == 1 else 1
	_prompt_dirty = true
	_update_highlight()
	_notify(player, "🔲 Зона работы на делянке: %d×%d" % [zone_size, zone_size])

# --- Семена ------------------------------------------------------------------------

## Семена для посадки: выбранные игроком (если есть в рюкзаке), иначе первые имеющиеся.
func get_active_seed(player: Node) -> String:
	var inv = player.get("inventory") if player else null
	if inv == null:
		return ""
	var sel: String = str(player.get("selected_seed")) if player.get("selected_seed") != null else ""
	if sel != "" and inv.get_item_count(sel) > 0:
		return sel
	for s in CropDB.all_seeds():
		if inv.get_item_count(s) > 0:
			return s
	return ""

## R — следующие семена из имеющихся в рюкзаке.
func cycle_seed(player: Node) -> String:
	var inv = player.get("inventory") if player else null
	if inv == null:
		return ""
	var have: Array[String] = []
	for s in CropDB.all_seeds():
		if inv.get_item_count(s) > 0:
			have.append(s)
	if have.is_empty():
		_notify(player, "🌱 В рюкзаке нет семян. Семена продаёт торговец, они же возвращаются с урожаем.")
		return ""
	var cur: String = get_active_seed(player)
	var next: String = have[(have.find(cur) + 1) % have.size()]
	if "selected_seed" in player:
		player.selected_seed = next
	_prompt_dirty = true
	var crop: String = CropDB.crop_for_seed(next)
	_notify(player, "🌱 Семена для посадки: %s ×%d — %s" % [ItemDB.get_item_name(next), inv.get_item_count(next), CropDB.describe(crop)])
	return next

# --- Подсказки -------------------------------------------------------------------

func get_prompt() -> String:
	match state:
		State.BLUEPRINT:
			return "[E] Принести материалы для делянки %d×%d: %s  ·  [X] отменить" % [size.x, size.y, _cost_progress_text()]
		State.BUILDING:
			return "Делянка %d×%d строится: %d%% (ещё ~%d ч)  ·  [X] отменить" % [size.x, size.y, int(build_progress / BUILD_HOURS * 100.0), ceili(BUILD_HOURS - build_progress)]
	if not is_cell_valid(target_cell):
		return "Делянка: подойдите к грядке"
	var d: Dictionary = get_cell(target_cell)
	var zone_txt: String = "G — зона %d×%d" % [zone_size, zone_size]
	var soil_txt: String = "влага %d%% · почва %d%%" % [int(d["moisture"]), int(d["fertility"])]
	var crop: String = d["crop"]
	if crop == "":
		var p := _get_player()
		var seed_id: String = get_active_seed(p) if p else ""
		if seed_id == "":
			return "Пустая грядка (%s) — нет семян  ·  [E] полить  ·  %s" % [soil_txt, zone_txt]
		var inv = p.get("inventory")
		return "[E] Посадить: %s (×%d)  ·  %s  ·  R — семена · %s" % [CropDB.get_crop_name(CropDB.crop_for_seed(seed_id)), inv.get_item_count(seed_id), soil_txt, zone_txt]
	var info: Dictionary = CropDB.get_crop(crop)
	var name_txt: String = CropDB.get_crop_name(crop)
	if d["withered"]:
		return "[E] Убрать увядшую культуру: %s (засуха)  ·  %s" % [name_txt, zone_txt]
	var q: int = get_quality(target_cell)
	if is_ripe(target_cell):
		return "[E] Собрать урожай: %s %s(%s)  ·  %s" % [name_txt, CropDB.QUALITY_STARS[q] + " " if q > 0 else "", CropDB.QUALITY_NAMES[q], zone_txt]
	var need: String = ""
	var m: float = float(d["moisture"])
	if m <= 0.0:
		need = " · ⚠ засуха %d/%d ч" % [int(d["drought"]), int(info["wither_hours"])]
	elif m < float(info["moist_min"]):
		need = " · сухо"
	elif m > float(info["moist_max"]):
		need = " · переувлажнение"
	var fert: String = " · удобрено" if d["fertilized"] else ""
	return "%s: %d%% · влага %d%% (норма %d–%d)%s · почва %d%%%s  ·  [E] полить/удобрить · %s" % [name_txt, int(get_progress(target_cell) * 100.0), int(m), int(info["moist_min"]), int(info["moist_max"]), need, int(d["fertility"]), fert, zone_txt]

func _cost_progress_text() -> String:
	var parts: PackedStringArray = []
	var cost := get_cost()
	for id in cost:
		parts.append("%s %d/%d" % [ItemDB.get_item_name(id), int(delivered.get(id, 0)), int(cost[id])])
	return ", ".join(parts)

# --- Действия ---------------------------------------------------------------------

func _on_interacted(player: Node) -> void:
	match state:
		State.BLUEPRINT:
			deliver_materials(player)
		State.BUILDING:
			_notify(player, "🏗 " + get_prompt())
		State.READY:
			work_cell(player, target_cell)

## Отдаёт из рюкзака недостающие материалы. Когда всё принесено — начинается стройка.
func deliver_materials(player: Node) -> bool:
	if state != State.BLUEPRINT:
		return false
	var inv = player.get("inventory") if player else null
	if inv == null:
		return false
	var cost := get_cost()
	var given: PackedStringArray = []
	for id in cost:
		var need: int = int(cost[id]) - int(delivered.get(id, 0))
		var take: int = mini(need, inv.get_item_count(id))
		if take > 0 and inv.remove_item(id, take):
			delivered[id] = int(delivered.get(id, 0)) + take
			given.append("%s ×%d" % [ItemDB.get_item_name(id), take])
	_prompt_dirty = true
	if _all_delivered():
		state = State.BUILDING
		build_progress = 0.0
		state_changed.emit(state)
		AudioManager.play("build")
		_refresh_all_visuals()
		_notify(player, "🏗 Материалы на месте! Стройка делянки займёт 1 игровой день (%d ч)." % int(BUILD_HOURS))
		return true
	if given.is_empty():
		_notify(player, "📦 Для делянки не хватает: %s" % _missing_text())
	else:
		_notify(player, "📦 Принесено: %s. Ещё нужно: %s" % [", ".join(given), _missing_text()])
	return not given.is_empty()

func _all_delivered() -> bool:
	var cost := get_cost()
	for id in cost:
		if int(delivered.get(id, 0)) < int(cost[id]):
			return false
	return true

func _missing_text() -> String:
	var parts: PackedStringArray = []
	var cost := get_cost()
	for id in cost:
		var left: int = int(cost[id]) - int(delivered.get(id, 0))
		if left > 0:
			parts.append("%s ×%d" % [ItemDB.get_item_name(id), left])
	return ", ".join(parts)

## X: отмена неготовой делянки (нужно нажать дважды за 3 с). Материалы возвращаются.
func request_cancel(player: Node) -> bool:
	if state == State.READY:
		_notify(player, "ℹ️ Готовую делянку нельзя снести.")
		return false
	var now: int = Time.get_ticks_msec()
	if _cancel_armed_msec < 0 or now - _cancel_armed_msec > 3000:
		_cancel_armed_msec = now
		_notify(player, "⚠️ Нажмите X ещё раз, чтобы отменить делянку и забрать материалы.")
		return false
	cancel_construction(player)
	return true

func cancel_construction(player: Node) -> void:
	var inv = player.get("inventory") if player else null
	for id in delivered:
		var n: int = int(delivered[id])
		if n <= 0:
			continue
		if inv == null or not inv.add_item(id, n):
			var drop_script = load("res://scripts/inventory/dropped_item.gd")
			drop_script.spawn(get_parent(), id, n, global_position + Vector3(-0.8, 0.2, -0.8))
	delivered.clear()
	_notify(player, "🗑 Делянка отменена, материалы возвращены.")
	queue_free()

## Умное действие над клеткой (и зоной): убрать увядшее, собрать, посадить, полить, удобрить.
func work_cell(player: Node, c: Vector2i) -> String:
	if state != State.READY or not is_cell_valid(c):
		return ""
	var d: Dictionary = get_cell(c)
	var inv = player.get("inventory") if player else null
	if d["withered"]:
		clear_withered(c, player)
		return "clear"
	if is_ripe(c):
		harvest(c, player)
		return "harvest"
	if d["crop"] == "":
		var seed_id: String = get_active_seed(player)
		if seed_id != "":
			plant(c, seed_id, player)
			return "plant"
		if inv and _has_water(inv) and float(d["moisture"]) < 80.0:
			water(c, player)
			return "water"
		_notify(player, "🌱 Нет семян для посадки. Купите у торговца или соберите с урожая.")
		return ""
	var info: Dictionary = CropDB.get_crop(d["crop"])
	if inv and _has_water(inv) and float(d["moisture"]) < float(info["moist_min"]) + WATER_HINT_MARGIN:
		water(c, player)
		return "water"
	if inv and inv.get_item_count("fertilizer") > 0 and not d["fertilized"]:
		fertilize(c, player)
		return "fertilize"
	_notify(player, "🌱 %s растёт: %d%%. Влага %d%% (норма %d–%d%%), почва %d%%." % [info["name"], int(get_progress(c) * 100.0), int(d["moisture"]), int(info["moist_min"]), int(info["moist_max"]), int(d["fertility"])])
	return "info"

func _has_water(inv: Node) -> bool:
	return inv.get_item_count("water") > 0 or inv.get_item_count("clean_water") > 0

## Посадка seed_id во все пустые клетки зоны (по семени на клетку).
func plant(c: Vector2i, seed_id: String, player: Node = null) -> int:
	var crop: String = CropDB.crop_for_seed(seed_id)
	if crop == "":
		return 0
	var inv = player.get("inventory") if player else null
	var planted: int = 0
	for n in zone_cells(c):
		var d: Dictionary = get_cell(n)
		if d["crop"] != "":
			continue
		if inv:
			if inv.get_item_count(seed_id) <= 0:
				break
			inv.remove_item(seed_id, 1)
		d["crop"] = crop
		d["growth"] = 0.0
		d["withered"] = false
		d["fertilized"] = false
		d["drought"] = 0.0
		d["care"] = 0.0
		d["total"] = 0.0
		planted += 1
		cell_changed.emit(n)
	if planted > 0:
		AudioManager.play("plant")
		_prompt_dirty = true
		_refresh_all_visuals()
		var rot: String = ""
		var last: String = get_cell(c)["last_crop"]
		if last != "" and last != crop:
			rot = " Севооборот после «%s» — бонус к урожаю!" % CropDB.get_crop_name(last)
		elif last == crop:
			rot = " Та же культура подряд сильнее истощит почву."
		_notify(player, "🌱 Посажено: %s ×%d.%s" % [CropDB.get_crop_name(crop), planted, rot])
	return planted

## Полив зоны одной порцией воды (чистая вода расходуется первой).
func water(c: Vector2i, player: Node = null) -> bool:
	var inv = player.get("inventory") if player else null
	if inv:
		if inv.get_item_count("clean_water") > 0:
			inv.remove_item("clean_water", 1)
		elif inv.get_item_count("water") > 0:
			inv.remove_item("water", 1)
		else:
			_notify(player, "💧 Нет воды для полива! Наберите в резервуаре.")
			return false
	var zone := zone_cells(c)
	var amount: float = WATER_SINGLE if zone.size() == 1 else WATER_ZONE
	for n in zone:
		var d: Dictionary = get_cell(n)
		d["moisture"] = minf(100.0, float(d["moisture"]) + amount)
		d["drought"] = 0.0
	AudioManager.play("water_splash")
	_prompt_dirty = true
	_refresh_all_visuals()
	_notify(player, "💧 Полито клеток: %d (+%d%% влаги)." % [zone.size(), int(amount)])
	return true

## Удобрение клеток зоны с культурой: порция на CELLS_PER_FERTILIZER клетки.
func fertilize(c: Vector2i, player: Node = null) -> int:
	var inv = player.get("inventory") if player else null
	var targets: Array[Vector2i] = []
	for n in zone_cells(c):
		var d: Dictionary = get_cell(n)
		if d["crop"] != "" and not d["fertilized"] and not d["withered"]:
			targets.append(n)
	if targets.is_empty():
		return 0
	var portions: int = ceili(float(targets.size()) / CELLS_PER_FERTILIZER)
	if inv:
		portions = mini(portions, inv.get_item_count("fertilizer"))
		if portions <= 0:
			return 0
		inv.remove_item("fertilizer", portions)
	var done: int = mini(targets.size(), portions * CELLS_PER_FERTILIZER)
	for i in done:
		var d: Dictionary = get_cell(targets[i])
		d["fertilized"] = true
		d["fertility"] = minf(100.0, float(d["fertility"]) + CropDB.FERTILIZER_BONUS)
	_prompt_dirty = true
	_refresh_all_visuals()
	_notify(player, "✨ Удобрено клеток: %d (рост ×%.1f, +1 к урожаю, почва +%d%%)." % [done, CropDB.FERTILIZED_SPEED, int(CropDB.FERTILIZER_BONUS)])
	return done

func clear_withered(c: Vector2i, player: Node = null) -> int:
	var n_cleared: int = 0
	for n in zone_cells(c):
		var d: Dictionary = get_cell(n)
		if d["withered"]:
			d["crop"] = ""
			d["growth"] = 0.0
			d["withered"] = false
			d["fertilized"] = false
			d["drought"] = 0.0
			n_cleared += 1
	_prompt_dirty = true
	_refresh_all_visuals()
	_notify(player, "🥀 Убрано увядших растений: %d. Поливайте вовремя — засуха губит урожай." % n_cleared)
	return n_cleared

## Урожай клетки: базовый (случайно в диапазоне культуры) + качество + удобрение
## + севооборот − бедная почва. Возвращает {crop: [урожай, семена]}.
static func calc_yield(d: Dictionary, quality: int, rng: RandomNumberGenerator) -> Array:
	var info: Dictionary = CropDB.get_crop(d["crop"])
	var y: int = rng.randi_range(int(info["yield"][0]), int(info["yield"][1])) + quality
	if d["fertilized"]:
		y += 1
	if d["last_crop"] != "" and d["last_crop"] != d["crop"]:
		y += 1
	if float(d["fertility"]) < CropDB.POOR_SOIL:
		y -= 1
	var s: int = rng.randi_range(int(info["seeds_back"][0]), int(info["seeds_back"][1]))
	return [maxi(1, y), s]

func harvest(c: Vector2i, player: Node = null) -> Dictionary:
	var inv = player.get("inventory") if player else null
	var totals: Dictionary = {}
	var best_q: int = 0
	for n in zone_cells(c):
		if not is_ripe(n):
			continue
		var d: Dictionary = get_cell(n)
		var crop: String = d["crop"]
		var q: int = get_quality(n)
		var ys: Array = calc_yield(d, q, _rng)
		var seed_id: String = CropDB.get_crop(crop)["seed"]
		if inv:
			if not inv.can_add_item(crop, ys[0]) or not inv.can_add_item(seed_id, ys[1]):
				_notify(player, "🎒 Рюкзак полон — урожай остался на грядке.")
				break
			inv.add_item(crop, ys[0])
			inv.add_item(seed_id, ys[1])
		var t: Array = totals.get(crop, [0, 0])
		totals[crop] = [t[0] + ys[0], t[1] + ys[1]]
		best_q = maxi(best_q, q)
		var drain: float = float(CropDB.get_crop(crop)["soil_drain"])
		if d["last_crop"] == crop:
			drain *= 1.5
		elif d["last_crop"] != "":
			drain *= 0.5
		d["fertility"] = maxf(0.0, float(d["fertility"]) - drain)
		d["last_crop"] = crop
		d["crop"] = ""
		d["growth"] = 0.0
		d["fertilized"] = false
		d["care"] = 0.0
		d["total"] = 0.0
		cell_changed.emit(n)
	if not totals.is_empty():
		AudioManager.play("harvest")
		_prompt_dirty = true
		_refresh_all_visuals()
		var parts: PackedStringArray = []
		for crop in totals:
			parts.append("%s ×%d (семена ×%d)" % [CropDB.get_crop_name(crop), totals[crop][0], totals[crop][1]])
		_notify(player, "🧺 Урожай: %s%s" % [", ".join(parts), "  ★ отличный уход!" if best_q == 2 else ""])
	return totals

func _notify(player: Node, text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)

# --- Сохранение ------------------------------------------------------------------

func get_save_state() -> Dictionary:
	var cs: Array = []
	for d in cells:
		cs.append([d["crop"], snappedf(float(d["growth"]), 0.01), snappedf(float(d["moisture"]), 0.1), snappedf(float(d["fertility"]), 0.1),
			d["fertilized"], d["withered"], snappedf(float(d["drought"]), 0.01), snappedf(float(d["care"]), 0.01), snappedf(float(d["total"]), 0.01), d["last_crop"]])
	return {"x": global_position.x, "z": global_position.z, "w": size.x, "h": size.y, "state": state,
		"delivered": delivered.duplicate(), "build": build_progress, "cells": cs}

func apply_save_state(st: Dictionary) -> void:
	state = clampi(int(st.get("state", State.BLUEPRINT)), State.BLUEPRINT, State.READY)
	build_progress = clampf(float(st.get("build", 0.0)), 0.0, BUILD_HOURS)
	delivered.clear()
	var dv: Dictionary = st.get("delivered", {})
	for id in dv:
		delivered[str(id)] = maxi(0, int(dv[id]))
	_reset_cells()
	var cs: Array = st.get("cells", [])
	for i in mini(cs.size(), cells.size()):
		var a: Array = cs[i]
		if a.size() < 10:
			continue
		var crop: String = str(a[0]) if CropDB.has_crop(str(a[0])) else ""
		cells[i] = {"crop": crop, "growth": maxf(0.0, float(a[1])), "moisture": clampf(float(a[2]), 0.0, 100.0),
			"fertility": clampf(float(a[3]), 0.0, 100.0), "fertilized": bool(a[4]), "withered": bool(a[5]) and crop != "",
			"drought": maxf(0.0, float(a[6])), "care": maxf(0.0, float(a[7])), "total": maxf(0.0, float(a[8])),
			"last_crop": str(a[9]) if CropDB.has_crop(str(a[9])) else ""}
	_prompt_dirty = true
	_refresh_all_visuals()

static func is_valid_save_state(st: Variant) -> bool:
	if not st is Dictionary:
		return false
	for k in ["x", "z", "w", "h"]:
		if not (st.get(k) is float or st.get(k) is int):
			return false
	var w: int = int(st["w"])
	var h: int = int(st["h"])
	if w < 1 or h < 1 or w * h > MAX_CELLS:
		return false
	if st.has("cells") and (not st["cells"] is Array or st["cells"].size() > w * h):
		return false
	if st.has("delivered") and not st["delivered"] is Dictionary:
		return false
	return true

# --- Визуал ------------------------------------------------------------------------

func _build_nodes() -> void:
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + 2.0, 2.0, size.y + 2.0)
	_shape.shape = box
	_shape.position = Vector3(size.x * 0.5, 1.0, size.y * 0.5)
	add_child(_shape)
	var mat: Material = Meshes.material()
	_mulch = _mesh_node("Mulch", Meshes.mulch(size.x, size.y), mat)
	_border = _mesh_node("Border", null, mat)
	_survey = _mesh_node("Survey", Meshes.survey(size.x, size.y), Meshes.material(true))
	var fill := PlaneMesh.new()
	fill.size = Vector2(size.x, size.y)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.albedo_color = Color(0.95, 0.85, 0.5, 0.18)
	_area_fill = _mesh_node("AreaFill", fill, fill_mat)
	_area_fill.position = Vector3(size.x * 0.5, 0.03, size.y * 0.5)
	_pile = _mesh_node("MaterialPile", Meshes.material_pile(), mat)
	_pile.position = Vector3(minf(0.9, size.x * 0.5), 0.0, minf(0.6, size.y * 0.5))
	_pile.rotation.y = PI * 0.5
	_sign = _mesh_node("Sign", Meshes.sign_post(), mat)
	_sign.position = Vector3(-0.25, 0.0, -0.25)
	_sign.rotation.y = PI * 0.25
	_label = Label3D.new()
	_label.name = "SignLabel"
	_label.pixel_size = 0.0035
	_label.font_size = 40
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.96, 0.85)
	_label.position = Vector3(0.0, 0.72, 0.06)
	_sign.add_child(_label)
	_soil_mmi = MultiMeshInstance3D.new()
	_soil_mmi.name = "SoilBeds"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Meshes.soil_cell()
	_soil_mmi.multimesh = mm
	_soil_mmi.material_override = mat
	add_child(_soil_mmi)
	_highlight = _mesh_node("Highlight", Meshes.highlight(1), Meshes.material(false, 0.5))
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false

func _mesh_node(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi

func _update_highlight() -> void:
	if _highlight == null:
		return
	var show: bool = state == State.READY and is_cell_valid(target_cell)
	_highlight.visible = show
	if show:
		_highlight.mesh = Meshes.highlight(zone_size)
		_highlight.position = Vector3(target_cell.x + 0.5, 0.0, target_cell.y + 0.5)

## Сколько клеток уже видно (стройка открывает их по мере прогресса).
func _shown_cell_count() -> int:
	match state:
		State.BLUEPRINT:
			return 0
		State.BUILDING:
			return clampi(int(floor(build_progress / BUILD_HOURS * get_cell_count())), 0, get_cell_count())
	return get_cell_count()

func _refresh_if_changed() -> void:
	if state == State.BUILDING:
		var segs: int = Meshes.border_segments(size.x, size.y).size()
		var key: int = _shown_cell_count() * 1000 + int(build_progress / BUILD_HOURS * segs)
		if key != _built_shown:
			_refresh_all_visuals()
		return
	if state != State.READY:
		return
	if _visual_keys.size() != cells.size():
		_refresh_all_visuals()
		return
	for i in cells.size():
		if _cell_key(i) != _visual_keys[i] or _soil_key(i) != _soil_keys[i]:
			_refresh_all_visuals()
			return

func _stage_of(i: int) -> int:
	var d: Dictionary = cells[i]
	var p: float = clampf(float(d["growth"]) / float(CropDB.get_crop(d["crop"])["growth_hours"]), 0.0, 1.0)
	if p >= 1.0:
		return 3
	if p < 0.1:
		return 0
	if p < 0.35:
		return 1
	return 2

func _cell_key(i: int) -> String:
	var d: Dictionary = cells[i]
	if d["crop"] == "":
		return ""
	var p: float = float(d["growth"]) / float(CropDB.get_crop(d["crop"])["growth_hours"])
	return "%s|%d|%s|%d" % [d["crop"], _stage_of(i), d["withered"], int(p * 20.0)]

func _soil_key(i: int) -> int:
	return int(float(cells[i]["moisture"]) / 10.0) + (100 if cells[i]["fertilized"] else 0)

func _refresh_all_visuals() -> void:
	if _soil_mmi == null:
		return
	_prompt_dirty = true
	var blueprint: bool = state == State.BLUEPRINT
	var building: bool = state == State.BUILDING
	_survey.visible = blueprint or building
	_area_fill.visible = blueprint
	_pile.visible = blueprint or building
	_mulch.visible = not blueprint
	var segs: int = Meshes.border_segments(size.x, size.y).size()
	var seg_count: int = 0 if blueprint else (segs if state == State.READY else int(build_progress / BUILD_HOURS * segs))
	_border.mesh = Meshes.border(size.x, size.y, seg_count) if seg_count > 0 else null
	var shown: int = _shown_cell_count()
	_built_shown = shown * 1000 + seg_count
	match state:
		State.BLUEPRINT:
			_label.text = "Делянка %d×%d\nнужны материалы" % [size.x, size.y]
		State.BUILDING:
			_label.text = "Делянка %d×%d\nстройка %d%%" % [size.x, size.y, int(build_progress / BUILD_HOURS * 100.0)]
		_:
			_label.text = "Делянка %d×%d" % [size.x, size.y]
	# Грядки: цвет по влаге (сухая — светлая, мокрая — тёмная), удобренная — чуть теплее.
	var mm := _soil_mmi.multimesh
	mm.instance_count = shown
	_visual_keys.resize(cells.size())
	_soil_keys.resize(cells.size())
	var lists: Dictionary = {}
	for i in shown:
		var c := Vector2i(i % size.x, i / size.x)
		var d: Dictionary = cells[i]
		var wet: float = clampf(float(d["moisture"]) / 80.0, 0.0, 1.0) if state == State.READY else 0.3
		var col := Color(1.0, 1.0, 1.0).lerp(Color(0.55, 0.5, 0.48), wet)
		if d["fertilized"]:
			col = col * Color(1.0, 0.92, 0.85)
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 * ((c.x * 7 + c.y * 3) % 2) * 0.0), Vector3(c.x + 0.5, 0.0, c.y + 0.5))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, col)
		_soil_keys[i] = _soil_key(i)
		_visual_keys[i] = _cell_key(i) if state == State.READY else ""
		if state != State.READY or d["crop"] == "":
			continue
		var stage: int = _stage_of(i)
		var key: String = "%s|%d|%s" % [d["crop"], stage, d["withered"]]
		var p: float = clampf(float(d["growth"]) / float(CropDB.get_crop(d["crop"])["growth_hours"]), 0.0, 1.0)
		var bounds: Array = [[0.0, 0.1], [0.1, 0.35], [0.35, 1.0], [1.0, 1.0]][stage]
		var t: float = 1.0 if bounds[1] <= bounds[0] else clampf((p - bounds[0]) / (bounds[1] - bounds[0]), 0.0, 1.0)
		var s: float = lerpf(0.7, 1.0, t) if stage == 2 else 1.0
		var flip: float = PI if (c.x + c.y) % 2 == 1 else 0.0
		var cxf := Transform3D(Basis(Vector3.UP, flip).scaled(Vector3(s, s, s)), Vector3(c.x + 0.5, 0.0, c.y + 0.5))
		if not lists.has(key):
			lists[key] = []
		lists[key].append(cxf)
	for key in _crop_mmis.keys():
		if not lists.has(key):
			_crop_mmis[key].queue_free()
			_crop_mmis.erase(key)
	for key in lists:
		var mmi: MultiMeshInstance3D = _crop_mmis.get(key)
		if mmi == null:
			var parts: PackedStringArray = key.split("|")
			mmi = MultiMeshInstance3D.new()
			mmi.name = "Crop_" + key.replace("|", "_")
			var cm := MultiMesh.new()
			cm.transform_format = MultiMesh.TRANSFORM_3D
			cm.mesh = Meshes.crop(parts[0], int(parts[1]), parts[2] == "true")
			mmi.multimesh = cm
			mmi.material_override = Meshes.material(true)
			add_child(mmi)
			_crop_mmis[key] = mmi
		var xs: Array = lists[key]
		mmi.multimesh.instance_count = xs.size()
		for j in xs.size():
			mmi.multimesh.set_instance_transform(j, xs[j])
	_update_highlight()

## Убирает траву, цветы, мусор и декоративные кусты под делянкой.
func _clear_decor() -> void:
	if not is_inside_tree():
		return
	var decor = get_tree().get_first_node_in_group(MeadowDecor.GROUP)
	if decor and decor.has_method("clear_area"):
		decor.clear_area(get_rect().grow(0.25))

## Список клеток с культурами (для тестов и отладки).
func count_crops() -> Dictionary:
	var out: Dictionary = {}
	for d in cells:
		if d["crop"] != "":
			out[d["crop"]] = int(out.get(d["crop"], 0)) + 1
	return out
