class_name MachineWear
extends RefCounted

## Состояние износа оборудования — общий переиспользуемый компонент для любой
## техники (дробилка, верстак, печь, фильтр). Держится на ProductionMachine.
##
## * Износ растёт только за фактически завершённые циклы производства
##   (add_wear вызывает ProductionMachine._complete_process), а не за время на сцене.
## * Пока состояние ≤ WORN_RATIO — станок «изношен»: циклы идут медленнее
##   (get_speed_mult).
## * При 0 — «неисправна»: новые запуски блокируются до ремонта (repair).
## Ремонт — repair_machine() у станка: списывает ресурсы только при успехе.

signal condition_changed(condition: float, max_condition: float)

## Ниже этой доли состояния станок считается изношенным.
const WORN_RATIO: float = 0.5
## Множитель длительности цикла у изношенного станка.
const WORN_SPEED_MULT: float = 1.25

var max_condition: float = 100.0
var condition: float = 100.0
## Износ за один завершённый цикл производства (настраивается станком).
var wear_per_cycle: float = 0.5

func add_wear(amount: float) -> void:
	if amount <= 0.0 or condition <= 0.0:
		return
	condition = maxf(0.0, condition - amount)
	condition_changed.emit(condition, max_condition)

## Восстанавливает состояние на amount (не выше максимума). Возвращает,
## сколько реально восстановлено.
func repair(amount: float) -> float:
	if amount <= 0.0 or condition >= max_condition:
		return 0.0
	var before: float = condition
	condition = minf(max_condition, condition + amount)
	condition_changed.emit(condition, max_condition)
	return condition - before

func set_condition(value: float) -> void:
	condition = clampf(value, 0.0, max_condition)
	condition_changed.emit(condition, max_condition)

func get_ratio() -> float:
	return condition / maxf(0.01, max_condition)

func is_broken() -> bool:
	return condition <= 0.0

func is_worn() -> bool:
	return get_ratio() <= WORN_RATIO

## Множитель длительности цикла из-за износа (1.0 — исправна).
func get_speed_mult() -> float:
	return WORN_SPEED_MULT if is_worn() else 1.0

func get_status_text() -> String:
	var pct: int = int(round(get_ratio() * 100.0))
	if is_broken():
		return "⛔ Неисправна — требуется ремонт"
	if is_worn():
		return "🛠 Изношена (%d%%)" % pct
	return "✅ Исправна (%d%%)" % pct
