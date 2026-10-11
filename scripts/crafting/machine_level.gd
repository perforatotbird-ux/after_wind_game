class_name MachineLevel
extends RefCounted

## Уровень станка (Lv.1 базовая → Lv.2 улучшенная → Lv.3 передовая) — общий
## переиспользуемый компонент, как MachineWear для износа. Множители применяются
## в ProductionMachine поверх рецепта, износа и класса персонажа:
## финальная скорость = рецепт × уровень × износ × класс.
## Спецбонусы машин (выход продукции у дробилки/фильтра, КПД топлива у печи)
## считаются от этих же множителей. Стоимость улучшений — UPGRADE_COSTS у станка.

## Максимальный уровень станка (Lv.3 — без новых рецептов, только характеристики;
## «темы» Lv.3 — автоподача, рекуперация — приходят с Главой 2).
const MAX_LEVEL: int = 3

## Множители по уровням: скорость цикла, износ за цикл, ресурс станка,
## потребление сети, сила персонажа за цикл, КПД топлива (время горения).
const LEVEL_STATS: Dictionary = {
	1: {"speed": 1.0, "wear": 1.0, "max_condition": 100.0, "power": 1.0, "energy": 1.0, "fuel": 1.0},
	2: {"speed": 0.75, "wear": 0.6, "max_condition": 120.0, "power": 1.3, "energy": 0.8, "fuel": 1.3},
	3: {"speed": 0.6, "wear": 0.4, "max_condition": 150.0, "power": 1.6, "energy": 0.65, "fuel": 1.6},
}

var level: int = 1

func set_level(value: int) -> void:
	level = clampi(value, 1, MAX_LEVEL)

func get_stats() -> Dictionary:
	return LEVEL_STATS.get(clampi(level, 1, MAX_LEVEL), LEVEL_STATS[1])

## Множитель длительности цикла (меньше — быстрее).
func get_speed_mult() -> float:
	return float(get_stats()["speed"])

## Множитель износа за цикл (меньше — долговечнее).
func get_wear_mult() -> float:
	return float(get_stats()["wear"])

## Ресурс станка (max_condition) на этом уровне.
func get_max_condition() -> float:
	return float(get_stats()["max_condition"])

## Множитель потребления энергосети.
func get_power_mult() -> float:
	return float(get_stats()["power"])

## Множитель силы персонажа за цикл.
func get_energy_mult() -> float:
	return float(get_stats()["energy"])

## КПД топлива: время горения одной единицы фактически × efficiency.
func get_fuel_efficiency() -> float:
	return float(get_stats()["fuel"])

func can_upgrade() -> bool:
	return level < MAX_LEVEL

func get_level_name() -> String:
	match level:
		2: return "Улучшенная"
		3: return "Передовая"
		_: return "Базовая"
