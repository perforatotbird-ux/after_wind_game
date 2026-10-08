extends SceneTree

## Тест динамической экипировки: в руке персонажа виден инструмент
## экипированного слота (топор/кирка/лопата/ведро), а не всегда кирка.
## Ведро носят в руке постоянно (у него нет анимации замаха).

const PlayerScene = preload("res://scenes/player/player.tscn")
const AxeScene = preload("res://scenes/tools/axe_model.tscn")
const ShovelScene = preload("res://scenes/tools/shovel_model.tscn")
const BucketScene = preload("res://scenes/tools/bucket_model.tscn")
const AxeInHandScene = preload("res://scenes/tools/axe_inhand.tscn")
const ShovelInHandScene = preload("res://scenes/tools/shovel_inhand.tscn")
const BucketInHandScene = preload("res://scenes/tools/bucket_inhand.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print(">>> Инициализация теста Equipped Tools...")
	var player_instance = PlayerScene.instantiate()
	root.add_child(player_instance)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true

	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("ТЕСТ ПРОВАЛЕН: " + reason)
	print("ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

## Резолвер анимаций: старая модель (dig/scoop) и новая из пакета
## (Track_Pickaxe_Dig_Loop для копания и набора воды).
func _resolve_tool_anim(ap: AnimationPlayer, logical: String) -> String:
	var aliases: Dictionary = {
		"dig": ["dig", "Track_Pickaxe_Dig_Loop", "Track_Pickaxe_Dig", "mine", "Track_Pickaxe_Swing"],
		"scoop": ["scoop", "Track_Pickaxe_Dig_Loop", "Track_Pickaxe_Dig", "Track_Idle", "idle"],
	}
	if ap.has_animation(logical):
		return logical
	for c in aliases.get(logical, []):
		if ap.has_animation(c):
			return c
	return ""

func _assert_only_visible(player: Node, expected_type: String) -> void:
	var nodes: Dictionary = player.equipped_tool_nodes
	for tool_type in ["axe", "pickaxe", "shovel", "bucket"]:
		if not nodes.has(tool_type):
			_fail("Узел инструмента '%s' отсутствует в equipped_tool_nodes" % tool_type)
			return
		var n: Node3D = nodes[tool_type]
		var should_be_visible: bool = (tool_type == expected_type)
		if n.visible != should_be_visible:
			_fail("Инструмент '%s': visible=%s, ожидалось %s (экипирован '%s')" % [tool_type, n.visible, should_be_visible, expected_type])
			return

func _run_tests() -> void:
	print("=================================================================")
	print("ЗАПУСК ТЕСТОВ: ДИНАМИЧЕСКАЯ ЭКИПИРОВКА ИНСТРУМЕНТОВ В РУКЕ")
	print("=================================================================")

	var player = root.get_node_or_null("Player")
	if not player:
		_fail("Узел Player не найден в корне дерева")
		return

	# 1. Сокет и узлы инструментов созданы при _ready
	print("\n--- Проверка 1: ToolSocket и in-hand узлы ---")
	var skeleton := player.get_node_or_null("Visuals").find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("Skeleton3D не найден в Player/Visuals")
		return
	if skeleton.find_bone("ToolSocket.R") == -1 and skeleton.find_bone("Pickaxe_Attachment_R") == -1 and skeleton.find_bone("Hand_R") == -1 and skeleton.find_bone("Hand.R") == -1:
		_fail("Кость ToolSocket.R (или Hand_R/Pickaxe_Attachment_R новой модели) отсутствует в скелете")
		return
	print("  • Кость ToolSocket.R (или сокет новой модели) найдена.")
	if player.tool_socket == null or not is_instance_valid(player.tool_socket):
		_fail("BoneAttachment3D сокет не создан (player.tool_socket)")
		return
	if player.tool_socket.get_parent() != skeleton:
		_fail("Сокет должен быть ребёнком Skeleton3D")
		return
	print("  • Рантайм-сокет ToolSocket_Runtime привязан к Skeleton3D.")
	for t in ["axe", "pickaxe", "shovel", "bucket"]:
		if not player.equipped_tool_nodes.has(t):
			_fail("equipped_tool_nodes не содержит '%s'" % t)
			return
	print("  • Все 4 инструмента зарегистрированы: axe, pickaxe, shovel, bucket.")

	# 2. Топор в руке при экипированном топоре
	print("\n--- Проверка 2: Топор (слот 1) ---")
	player.inventory.equip_tool("axe")
	player.set_equipped_tool_visible(true)
	_assert_only_visible(player, "axe")
	print("  • Виден только топор.")
	player.set_equipped_tool_visible(false)
	_assert_only_visible(player, "")
	print("  • Всё скрыто после set_equipped_tool_visible(false).")

	# 3. Инструмент Lv.2 того же типа показывает ту же модель
	print("\n--- Проверка 3: Железный топор Lv.2 ---")
	player.inventory.upgrade_tool("iron_axe")
	if player.inventory.get_equipped_tool() != "iron_axe":
		_fail("После upgrade_tool экипирован должен быть iron_axe")
		return
	player.set_equipped_tool_visible(true)
	_assert_only_visible(player, "axe")
	print("  • iron_axe показывает модель топора.")

	# 4. Лопата в руке при экипированной лопате
	print("\n--- Проверка 4: Лопата (слот 3) ---")
	player.inventory.equip_tool("shovel")
	player.set_equipped_tool_visible(true)
	_assert_only_visible(player, "shovel")
	print("  • Видна только лопата.")

	# 5. Ведро носят в руке постоянно (persistent, без замаха)
	print("\n--- Проверка 5: Ведро (слот 4, persistent) ---")
	player.inventory.equip_tool("bucket")
	# Без вызова set_equipped_tool_visible — смена слота сама показывает ведро
	_assert_only_visible(player, "bucket")
	print("  • Ведро видно сразу после экипировки, остальные скрыты.")

	# 6. Автономные и in-hand сцены инстанцируются
	print("\n--- Проверка 6: Сцены инструментов ---")
	for entry in [["axe", AxeScene], ["shovel", ShovelScene], ["bucket", BucketScene],
			["axe_inhand", AxeInHandScene], ["shovel_inhand", ShovelInHandScene], ["bucket_inhand", BucketInHandScene]]:
		var inst: Node = (entry[1] as PackedScene).instantiate()
		if inst == null:
			_fail("Не инстанцируется сцена %s" % entry[0])
			return
		print("  • Сцена %s инстанцирована (%s)." % [entry[0], inst.name])
		inst.free()

	# 7. Иконки в ItemDB
	print("\n--- Проверка 7: Иконки топора/лопаты/ведра в ItemDB ---")
	for item_id in ["axe", "shovel", "bucket", "iron_axe", "iron_shovel", "reinforced_bucket"]:
		var d: Dictionary = ItemDB.get_item(item_id)
		if d.is_empty():
			_fail("Предмет '%s' отсутствует в ItemDB" % item_id)
			return
		if not FileAccess.file_exists(d.get("texture", "")):
			_fail("Иконка предмета '%s' не найдена: %s" % [item_id, d.get("texture", "")])
			return
		print("  • '%s' -> %s." % [item_id, d.get("texture")])

	# 8. Анимация копания лопатой
	print("\n--- Проверка 8: Анимация копания dig ---")
	var dig_name: String = _resolve_tool_anim(player.anim_player, "dig")
	if dig_name == "":
		_fail("Анимация копания ('dig' / 'Track_Pickaxe_Dig_Loop') отсутствует в AnimationPlayer")
		return
	print("  • Клип копания '%s' найден (длина: %.2f сек)." % [dig_name, player.anim_player.get_animation(dig_name).length])
	player.inventory.equip_tool("axe")
	if not player.play_dig_animation():
		_fail("play_dig_animation вернул false")
		return
	if not player.is_digging:
		_fail("Флаг is_digging должен быть true во время копания")
		return
	var dig_shovel: Node3D = player.equipped_tool_nodes.get("shovel")
	if dig_shovel == null or not dig_shovel.visible:
		_fail("Во время копания в руке должна быть лопата (даже если экипирован топор)")
		return
	print("  • Копание запущено: is_digging=true, в руке лопата.")
	player._process(5.0)
	if player.is_digging:
		_fail("Копание должно завершиться по истечении длительности")
		return
	print("  • Копание завершилось, флаг снят.")

	# 9. Анимация набора воды: поза, капли, полное ведро
	print("\n--- Проверка 9: Набор воды scoop + капли + полное ведро ---")
	var scoop_name: String = _resolve_tool_anim(player.anim_player, "scoop")
	if scoop_name == "":
		_fail("Анимация набора воды ('scoop' / 'Track_Pickaxe_Dig_Loop') отсутствует в AnimationPlayer")
		return
	if player.bucket_full_mesh == null or not is_instance_valid(player.bucket_full_mesh):
		_fail("Узел Equipped_BucketFull не создан (bucket_full_inhand)")
		return
	print("  • Клип 'scoop' и узел полного ведра на месте.")
	if not player.play_scoop_animation(Vector3(1, 0, 0)):
		_fail("play_scoop_animation вернул false")
		return
	if not player.is_scooping:
		_fail("Флаг is_scooping должен быть true во время набора воды")
		return
	player._process(0.6)
	var droplets = root.find_child("ScoopDroplets", true, false)
	if droplets == null:
		_fail("Капли ScoopDroplets не заспавнились к моменту 0.6с")
		return
	print("  • Капли летят от источника к ведру.")
	player._process(0.5)
	if not player.bucket_filled:
		_fail("К моменту 1.1с ведро должно стать полным (bucket_filled)")
		return
	if not player.bucket_full_mesh.visible:
		_fail("Должна быть видна модель наполненного ведра")
		return
	print("  • Ведро стало полным: модель заменена.")
	player._process(1.0)
	if player.is_scooping:
		_fail("Набор воды должен завершиться по истечении длительности")
		return
	print("  • Анимация набора завершена, полное ведро осталось в руке.")
	player._process(5.0)
	if player.bucket_filled:
		_fail("По истечении таймера ведро должно снова стать пустым")
		return
	print("  • Таймер истёк — ведро снова пустое.")

	print("\n=================================================================")
	print("ВСЕ ТЕСТЫ ДИНАМИЧЕСКОЙ ЭКИПИРОВКИ ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)
