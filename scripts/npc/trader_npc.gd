class_name TraderNPC
extends "res://scripts/interaction/interactable.gd"

## NPC-караванщик и снабженец (Этап 7, разделы 22, 23, 86)
## Выдает выгодные контракты на поставку восстановленных материалов

signal dialogue_opened(npc: Node)

const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

@export var npc_name: String = "Степан (Снабженец)"
@export var greeting_text: String = "Приветствую, выживший! Буря натворила бед, но смотрю, твоя база оживает. У меня есть срочные заказы от соседних поселений — заплатят щедро!"
@export var visual_node: Node3D

var animation_player: AnimationPlayer
var _dialogue_active: bool = false
var _target_player: Node3D
var _rest_yaw: float = 0.0
var is_trader: bool = true
var is_npc: bool = true
var starter_seeds_given: bool = false

func _ready() -> void:
	super._ready()
	object_name = npc_name
	prompt_action = "Поговорить / Заказы"
	
	if not visual_node:
		visual_node = get_node_or_null("Visual")
	if visual_node:
		_rest_yaw = visual_node.rotation.y
		animation_player = visual_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
		animation_player.play("idle")

func _process(delta: float) -> void:
	# Feet stay on the ground; only the visual turns toward the interlocutor.
	if not visual_node:
		return
	var yaw := _rest_yaw
	if _dialogue_active and is_instance_valid(_target_player):
		var direction := global_transform.basis.inverse() * (_target_player.global_position - global_position)
		if Vector2(direction.x, direction.z).length_squared() > 0.01:
			yaw = atan2(direction.x, direction.z)
	visual_node.rotation.y = lerp_angle(visual_node.rotation.y, yaw, minf(delta * 5.0, 1.0))

func begin_dialogue(player: Node = null) -> void:
	_target_player = player as Node3D
	if _dialogue_active:
		return
	_dialogue_active = true
	_play_animation("greet")

func end_dialogue() -> void:
	_dialogue_active = false
	_target_player = null
	_play_animation("idle")

func _play_animation(anim: StringName) -> void:
	if animation_player and animation_player.has_animation(anim):
		animation_player.play(anim, 0.2)

func _on_animation_finished(anim: StringName) -> void:
	if anim in [&"greet", &"talk"]:
		_play_animation("talk" if _dialogue_active else "idle")

func get_prompt() -> String:
	return "[E] Поговорить: %s" % object_name

func _on_interacted(player: Node) -> void:
	begin_dialogue(player)
	dialogue_opened.emit(self)
	var inv = player.get("inventory") if player else null
	if inv and not starter_seeds_given:
		starter_seeds_given = true
		# Семена не теряются: при полном рюкзаке падают кучкой у Степана.
		var drop_at: Vector3 = global_position + Vector3(0.0, 0.4, 1.0) if player is Node3D else Vector3.ZERO
		DroppedItemScript.give_or_drop(player, "seeds_carrot", 3, drop_at, get_parent())
		DroppedItemScript.give_or_drop(player, "seeds_potato", 2, drop_at, get_parent())
		DroppedItemScript.give_or_drop(player, "seeds_wheat", 3, drop_at, get_parent())
		if player.has_method("notify"):
			player.notify("👨‍🌾 Степан: «Держи семена моркови, картошки и пшеницы! Вскопай грядку лопатой и наладь урожай.»")
			return
	
	if player.has_method("notify"):
		player.notify("👨‍🌾 Степан готов обсудить заказы и поставки материалов.")
