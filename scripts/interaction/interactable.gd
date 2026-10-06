class_name Interactable
extends Area3D

## Базовый класс для интерактивных объектов в игре
signal interacted(player: Node)

@export var object_name: String = "Объект"
@export var prompt_action: String = "Взаимодействовать"
@export var is_interactable: bool = true

func _ready() -> void:
	# Коллизионный слой 4 для взаимодействия (Interactables)
	collision_layer = 8
	collision_mask = 0

func get_prompt() -> String:
	return "[E] %s (%s)" % [prompt_action, object_name]

func interact(player: Node) -> void:
	if not is_interactable:
		return
	interacted.emit(player)
	_on_interacted(player)

func _on_interacted(_player: Node) -> void:
	# Переопределяется в дочерних классах
	pass
