class_name IsometricCamera
extends Camera3D

@export var target_node: Node3D
@export var follow_offset: Vector3 = Vector3(0.0, 11.0, 10.0)
@export var follow_speed: float = 6.0

func _ready() -> void:
	if target_node:
		global_position = target_node.global_position + follow_offset
		look_at(target_node.global_position + Vector3(0, 0.8, 0), Vector3.UP)

func _process(delta: float) -> void:
	if not target_node:
		return
		
	var target_pos: Vector3 = target_node.global_position + follow_offset
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	look_at(target_node.global_position + Vector3(0, 0.8, 0), Vector3.UP)
