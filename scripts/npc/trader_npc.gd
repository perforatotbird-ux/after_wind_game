class_name TraderNPC
extends "res://scripts/interaction/interactable.gd"

## NPC-караванщик и снабженец (Этап 7, разделы 22, 23, 86)
## Выдает выгодные контракты на поставку восстановленных материалов

signal dialogue_opened(npc: Node)

@export var npc_name: String = "Степан (Снабженец)"
@export var greeting_text: String = "Приветствую, выживший! Буря натворила бед, но смотрю, твоя база оживает. У меня есть срочные заказы от соседних поселений — заплатят щедро!"
@export var visual_node: Node3D

var _orig_y: float = 0.0
var _anim_time: float = 0.0
var starter_seeds_given: bool = false

func _ready() -> void:
	super._ready()
	object_name = npc_name
	prompt_action = "Поговорить / Заказы"
	
	if not visual_node:
		visual_node = get_node_or_null("Visual")
	if visual_node:
		_orig_y = visual_node.position.y

func _process(delta: float) -> void:
	if visual_node:
		_anim_time += delta * 2.5
		# Мягкое дыхание / покачивание персонажа
		visual_node.position.y = _orig_y + sin(_anim_time) * 0.03

func get_prompt() -> String:
	return "[E] Поговорить: %s" % object_name

func _on_interacted(player: Node) -> void:
	dialogue_opened.emit(self)
	var inv = player.get("inventory") if player else null
	if inv and not starter_seeds_given:
		starter_seeds_given = true
		inv.add_item("seeds_carrot", 3)
		inv.add_item("seeds_potato", 2)
		inv.add_item("seeds_wheat", 3)
		if player.has_method("notify"):
			player.notify("👨‍🌾 Степан: «Держи семена моркови, картошки и пшеницы! Вскопай грядку лопатой и наладь урожай.»")
			return
	
	if player.has_method("notify"):
		player.notify("👨‍🌾 Степан готов обсудить заказы и поставки материалов.")
