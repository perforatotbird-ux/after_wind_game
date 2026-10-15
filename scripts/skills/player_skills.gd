class_name PlayerSkills
extends Node

## Компонент прокачки навыков персонажа («Learn by doing»).
## Управляет опытом, уровнями и пассивными перками для всех 11 механик.

const SkillDB = preload("res://scripts/skills/skill_db.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")

signal skill_xp_gained(skill_id: String, amount: int, current_xp: int, next_level_xp: int)
signal skill_leveled_up(skill_id: String, new_level: int, perk_description: String)
signal skills_updated()

## Словарь состояния навыков: { skill_id: { "level": int, "xp": int } }
var skills_data: Dictionary = {}

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	_init_default_skills()

func _ready() -> void:
	if skills_data.is_empty():
		_init_default_skills()

func _init_default_skills() -> void:
	for sid in SkillDB.SKILL_IDS:
		if not skills_data.has(sid):
			skills_data[sid] = {
				"level": 1,
				"xp": 0
			}

## Начисление очков опыта в конкретный навык
func add_xp(skill_id: String, amount: int) -> bool:
	if not skills_data.has(skill_id) or amount <= 0:
		return false
	
	var entry: Dictionary = skills_data[skill_id]
	var old_level: int = int(entry.get("level", 1))
	
	if old_level >= SkillDB.MAX_LEVEL:
		entry["xp"] = SkillDB.get_xp_for_level(SkillDB.MAX_LEVEL)
		return false
	
	entry["xp"] = int(entry.get("xp", 0)) + amount
	var new_level: int = SkillDB.calculate_level(int(entry["xp"]))
	entry["level"] = new_level
	if new_level >= SkillDB.MAX_LEVEL:
		entry["xp"] = SkillDB.get_xp_for_level(SkillDB.MAX_LEVEL)
	
	var leveled_up: bool = (new_level > old_level)
	var next_xp: int = SkillDB.get_xp_for_level(mini(new_level + 1, SkillDB.MAX_LEVEL))
	
	skill_xp_gained.emit(skill_id, amount, int(entry["xp"]), next_xp)
	
	if leveled_up:
		var perk_desc: String = SkillDB.get_perks_summary(skill_id, new_level)
		skill_leveled_up.emit(skill_id, new_level, perk_desc)
		
		# Звуковой отклик и всплывающее уведомление
		AudioManager.play("ui_click")
		var p = get_parent()
		if p and is_instance_valid(p) and p.has_method("notify"):
			var s_meta: Dictionary = SkillDB.get_skill_data(skill_id)
			var s_name: String = s_meta.get("name", skill_id)
			var s_icon: String = s_meta.get("icon", "⭐")
			var first_perk_line: String = perk_desc.split("\n")[0] if not perk_desc.is_empty() else ""
			p.notify("🎉 Навык повышен! [%s %s: Уровень %d] %s" % [s_icon, s_name, new_level, first_perk_line])
		
		# Если повысилась атлетика — сразу обновить лимиты энергии на персонаже
		if skill_id == "athletics" and p and "max_energy" in p and p.has_signal("energy_changed"):
			var cur_en: float = float(p.energy) if "energy" in p else 100.0
			var eff_max: float = p.max_energy + get_max_energy_bonus()
			p.energy_changed.emit(cur_en, eff_max)
		
		# Если повысилось строительство — обновить лимит веса рюкзака
		if skill_id == "construction" and p and "inventory" in p and p.inventory:
			if p.inventory.has_method("recalculate_capacity"):
				p.inventory.recalculate_capacity()
	
	skills_updated.emit()
	return leveled_up

# --- Геттеры данных ---

func get_level(skill_id: String) -> int:
	return int(skills_data.get(skill_id, {}).get("level", 1))

func get_xp(skill_id: String) -> int:
	return int(skills_data.get(skill_id, {}).get("xp", 0))

func get_progress(skill_id: String) -> float:
	var lvl: int = get_level(skill_id)
	var xp: int = get_xp(skill_id)
	return SkillDB.get_level_progress(xp, lvl)

func get_overall_level() -> int:
	return SkillDB.get_overall_level(skills_data)

func get_overall_title() -> String:
	return SkillDB.get_overall_title(get_overall_level())

# --- Расчёт перков и вероятностей ---

func get_energy_discount(skill_id: String) -> float:
	return SkillDB.get_energy_discount(skill_id, get_level(skill_id))

## Проверка шанса на дополнительную единицу ресурса
func roll_bonus_yield(skill_id: String) -> bool:
	var chance: float = SkillDB.get_bonus_yield_chance(skill_id, get_level(skill_id))
	if chance <= 0.0:
		return false
	return _rng.randf() < chance

## Проверка шанса сберечь семечко при посадке
func roll_seed_save() -> bool:
	var chance: float = SkillDB.get_seed_save_chance(get_level("farming"))
	if chance <= 0.0:
		return false
	return _rng.randf() < chance

func get_harvest_quality_bonus() -> float:
	return SkillDB.get_harvest_quality_bonus(get_level("farming"))

func get_machine_speed_mult() -> float:
	return SkillDB.get_machine_speed_mult(get_level("crafting"))

func get_wear_discount() -> float:
	return SkillDB.get_wear_discount(get_level("crafting"))

func get_cooking_nutrition_mult() -> float:
	return SkillDB.get_cooking_nutrition_mult(get_level("cooking"))

func get_capacity_bonus() -> float:
	return SkillDB.get_capacity_bonus(get_level("construction"))

func get_max_energy_bonus() -> float:
	return SkillDB.get_max_energy_bonus(get_level("athletics"))

func get_trade_bonus_mult() -> float:
	return SkillDB.get_trade_bonus_mult(get_level("trading"))

func get_trade_discount_mult() -> float:
	return SkillDB.get_trade_discount_mult(get_level("trading"))

func get_sprint_energy_discount() -> float:
	return get_energy_discount("athletics")

func award_athletics_jump() -> void:
	add_xp("athletics", 1)

func award_athletics_sprint(_dist: float = 0.0) -> void:
	add_xp("athletics", 2)

# --- Сериализация и Сохранение ---

func serialize() -> Dictionary:
	var skills_dict: Dictionary = {}
	for sid in SkillDB.SKILL_IDS:
		var entry = skills_data.get(sid, {"level": 1, "xp": 0})
		skills_dict[sid] = {
			"level": int(entry.get("level", 1)),
			"xp": int(entry.get("xp", 0))
		}
	return {
		"version": 1,
		"skills": skills_dict
	}

func deserialize(data: Dictionary) -> void:
	_init_default_skills()
	if data == null or data.is_empty():
		return
	var src: Dictionary = data.get("skills", data)
	for sid in SkillDB.SKILL_IDS:
		if src.has(sid) and src[sid] is Dictionary:
			var raw = src[sid]
			var xp_val = int(raw.get("xp", 0))
			var lvl_val = int(raw.get("level", SkillDB.calculate_level(xp_val)))
			skills_data[sid] = {
				"level": clampi(lvl_val, 1, SkillDB.MAX_LEVEL),
				"xp": maxi(0, xp_val)
			}
	skills_updated.emit()
