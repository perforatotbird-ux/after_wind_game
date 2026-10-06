extends "res://scripts/interaction/interactable.gd"

@export_multiline var interaction_message: String = "Вы осмотрели объект."

func _on_interacted(player: Node) -> void:
	var msg: String = "[%s]: %s" % [object_name, interaction_message]
	if player.has_method("notify"):
		player.notify(msg)
	print(msg)
