class_name ContractBoard
extends "res://scripts/interaction/interactable.gd"

## Доска заказов и строительных контрактов (Разделы 22, 23, 86)
## Позволяет просматривать и сдавать заказы от округи

signal board_opened(board: Node)

func _ready() -> void:
	super._ready()
	object_name = "Доска заказов и контрактов"
	prompt_action = "Смотреть заказы"

func get_prompt() -> String:
	return "[E] Доска заказов"

func _on_interacted(_player: Node) -> void:
	board_opened.emit(self)
