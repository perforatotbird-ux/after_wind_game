extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print(">>> Инициализация теста Realistic Stardew Valley Protagonist...")
	var player_instance = PlayerScene.instantiate()
	root.add_child(player_instance)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	
	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _run_tests() -> void:
	print("=================================================================")
	print("🌾 ЗАПУСК ТЕСТОВ: REALISTIC STARDEW VALLEY PROTAGONIST MODEL")
	print("=================================================================")
	
	var player = root.get_node_or_null("Player")
	if not player:
		_fail("Узел Player не найден в корне дерева")
		return
	
	# 1. Проверка структуры модели персонажа в Player.tscn
	print("\n--- Проверка 1: Структура модели в Player.tscn ---")
	var visuals = player.get_node_or_null("Visuals")
	if not visuals:
		_fail("Узел Visuals не найден в Player")
		return
	
	var char_model = visuals.get_node_or_null("CharacterModel")
	if not char_model:
		_fail("Узел CharacterModel не найден в Player/Visuals")
		return
	print("  • CharacterModel успешно найден в Visuals.")
	
	var skeleton = char_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton:
		_fail("Skeleton3D не найден внутри CharacterModel")
		return
	print("  • Арматура Skeleton3D найдена. Число костей: %d" % skeleton.get_bone_count())
	if skeleton.get_bone_count() < 20:
		_fail("Недостаточно костей в Skeleton3D (ожидалось >= 20)")
		return
	
	var hat_mesh = char_model.find_child("Sun_Hat", true, false) as MeshInstance3D
	if not hat_mesh:
		_fail("Sun_Hat меш не найден в CharacterModel")
		return
	print("  • Sun_Hat (шляпа от солнца с лентой и завязками) успешно обнаружена.")
	
	var equipped_pickaxe = char_model.find_child("Equipped_Pickaxe", true, false) as MeshInstance3D
	if not equipped_pickaxe:
		_fail("Equipped_Pickaxe не найдена внутри CharacterModel")
		return
	print("  • Equipped_Pickaxe прикреплена к руке персонажа.")
	
	var char_mesh = char_model.find_child("Farmer_Character", true, false) as MeshInstance3D
	if not char_mesh:
		_fail("Farmer_Character меш не найден в CharacterModel")
		return
	print("  • Farmer_Character (анатомическое тело, фланель, жилет, штаны с наколенниками, сапоги) обнаружен.")
	
	# 2. Проверка AnimationPlayer и запеченных анимаций
	print("\n--- Проверка 2: AnimationPlayer и анимации реалистичного героя ---")
	var anim_player = player.anim_player
	if not anim_player:
		_fail("anim_player не инициализирован в Player.gd")
		return
	
	var expected_anims = ["idle", "walk", "run", "mine"]
	for a in expected_anims:
		if not anim_player.has_animation(a):
			_fail("Анимация '%s' отсутствует в AnimationPlayer" % a)
			return
		var anim = anim_player.get_animation(a)
		print("  • Анимация '%s' найдена (длина: %.2f сек, треков: %d)" % [a, anim.length, anim.get_track_count()])
	
	# Проверка переключения анимаций через player.gd
	player.play_animation("walk")
	if player.current_anim != "walk":
		_fail("Не удалось включить анимацию 'walk'")
		return
	print("  • Переключение на 'walk' успешно.")
	
	player.play_mining_animation()
	if player.current_anim != "mine" or not player.is_mining:
		_fail("Не удалось активировать взмах инструментом (mining animation)")
		return
	print("  • Анимация удара 'mine' успешно запущена.")
	
	# 3. Проверка динамического отображения инструмента и шляпы:
	# виден инструмент экипированного слота, а не всегда кирка
	print("\n--- Проверка 3: Динамическое управление видимостью экипировки ---")
	player.inventory.equip_tool("pickaxe")
	player.set_equipped_tool_visible(false)
	if equipped_pickaxe.visible:
		_fail("Инструмент должен быть скрыт при вызове set_equipped_tool_visible(false)")
		return
	print("  • Инструмент корректно скрывается, когда убран.")
	
	player.set_equipped_tool_visible(true)
	if not equipped_pickaxe.visible:
		_fail("Инструмент должен быть видим при вызове set_equipped_tool_visible(true)")
		return
	print("  • Инструмент корректно отображается в руках героя.")

	player.inventory.equip_tool("shovel")
	player.set_equipped_tool_visible(true)
	var equipped_shovel: Node3D = player.equipped_tool_nodes.get("shovel")
	if equipped_shovel == null:
		_fail("Узел Equipped_Shovel не создан в ToolSocket (player.equipped_tool_nodes)")
		return
	if not equipped_shovel.visible:
		_fail("Лопата должна быть видима, когда экипирована лопата")
		return
	if equipped_pickaxe.visible:
		_fail("Кирка должна быть скрыта, когда экипирована лопата (раньше везде была кирка)")
		return
	print("  • Лопата корректно отображается в руках, кирка скрыта.")
	
	player.set_hat_visible(false)
	if hat_mesh.visible:
		_fail("Шляпа должна быть скрыта при вызове set_hat_visible(false)")
		return
	print("  • Шляпа корректно скрывается при программном вызове.")
	
	player.set_hat_visible(true)
	if not hat_mesh.visible:
		_fail("Шляпа должна быть видима при вызове set_hat_visible(true)")
		return
	print("  • Шляпа корректно отображается на голове героя.")
	
	# 4. Проверка спрайтов и иконок UI
	print("\n--- Проверка 4: 2D Спрайты, портреты и иконки ---")
	var farmer_class = CharacterClassDB.get_class_data("farmer")
	if farmer_class.is_empty():
		_fail("Класс farmer не найден в CharacterClassDB")
		return
	print("  • Класс 'farmer' в БД: %s, портрет: %s, спрайт: %s" % [farmer_class.name, farmer_class.portrait, farmer_class.sprite])
	
	if not FileAccess.file_exists(farmer_class.portrait):
		_fail("Файл портрета не найден: " + farmer_class.portrait)
		return
	print("  • Студийный портрет фермера (farmer_portrait.png) подтвержден.")
	
	if not FileAccess.file_exists(farmer_class.sprite):
		_fail("Файл изометрического спрайта не найден: " + farmer_class.sprite)
		return
	print("  • Изометрический спрайт фермера (farmer_isometric.png) подтвержден.")
	
	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ REALISTIC STARDEW VALLEY PROTAGONIST ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)
