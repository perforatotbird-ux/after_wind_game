class_name KitchenStove
extends ProductionMachine

## Печь-кухня (Глава 2 «Первый дым») — улучшенный станок готовки. В отличие от
## костра берёт энергию из сети (2.0 кВт) и имеет уровни Lv.1–2: на Lv.2
## открываются соусы. Топлива два слота — сушить и варить можно долго.
##
## Начинает как стройплощадка: пока не построен за rebuild_cost + rebuild_credits,
## не принимает рецепты и показывает каменную кладку вместо печи.

const GROUP: String = "kitchen_stoves"

## Качество блюд по уровню печи (мастер-план 5.4, 7.3): костёр даёт обычное,
## печь-кухня — хорошее, а с Lv.2 отличное.
const QUALITY_BY_LEVEL: Array[String] = [
	CookingProgress.QUALITY_GOOD,
	CookingProgress.QUALITY_GREAT,
]

func _ready() -> void:
	# Конфигурация — до super._ready(): базовый класс создаёт топливные слоты и
	# выставляет rebuilt по requires_rebuild именно в этот момент.
	machine_type = "kitchen_stove"
	machine_display_name = "Печь-кухня"
	prompt_action = "Готовить"
	has_fuel_slots = true
	fuel_slot_count = 2
	requires_rebuild = true
	super._ready()
	add_to_group(GROUP)

## Качество блюда по текущему уровню печи.
func get_dish_quality() -> String:
	var index: int = clampi((get_level() if level_state else 1) - 1, 0, QUALITY_BY_LEVEL.size() - 1)
	return QUALITY_BY_LEVEL[index]

func _on_outputs_produced(outputs: Dictionary) -> void:
	var quality: String = get_dish_quality()
	for item_id in outputs.keys():
		CookingProgress.register_dish(str(item_id), int(outputs[item_id]), quality)