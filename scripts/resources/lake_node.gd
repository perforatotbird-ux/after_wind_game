class_name LakeNode
extends ResourceNode

## Специализированный узел природного озера.
## В отличие от точечных ресурсов (деревья, камни), озеро является крупным ландшафтным объектом:
## 1. Не сжимается и не трясётся при заборе воды ведром (отсутствие мигания и скачков геометрии).
## 2. Не исчезает из мира при исчерпании доступной воды — блокируется только интерактивность на время восстановления.

func _play_hit_effect() -> void:
	# Озеро — стационарный ландшафтный водоём.
	# Анимацию набора воды ведром проигрывает игрок (play_scoop_animation); геометрия озера не масштабируется.
	pass

func _set_depleted(depleted: bool) -> void:
	is_depleted = depleted
	_yield_pool = 0.0
	if not depleted:
		_harvest_total = 0
	
	# При истощении забор воды блокируется до восстановления
	is_interactable = not depleted
	set_process(depleted)
	
	if depleted:
		respawn_timer = respawn_time
		# Озеро гарантированно остаётся видимым и в оригинальном масштабе
		if visual_node:
			visual_node.visible = true
			visual_node.scale = _original_scale
		if depleted_visual_node:
			depleted_visual_node.visible = false
		node_depleted.emit()
	else:
		current_hits = max_hits
		if visual_node:
			visual_node.visible = true
			visual_node.scale = _original_scale
		if depleted_visual_node:
			depleted_visual_node.visible = false
		node_respawned.emit()
