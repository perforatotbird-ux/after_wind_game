extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
const FarmerScene = preload("res://scenes/player/character_model.tscn")
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
	
	# 1. Проверка структуры модели фермера (файл character_model.tscn intact,
	# сам игрок по умолчанию использует шахтёра из Miner_Character_Package).
	print("\n--- Проверка 1: Структура модели фермера (character_model.tscn) ---")
	var farmer_model = FarmerScene.instantiate()
	root.add_child(farmer_model)
	var visuals = farmer_model
	var char_model = farmer_model
	
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
	
	# 2. Проверка AnimationPlayer и запеченных анимаций фермера
	print("\n--- Проверка 2: AnimationPlayer и анимации фермера ---")
	var anim_player = farmer_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		_fail("AnimationPlayer не найден в character_model.tscn")
		return
	
	var expected_anims = ["idle", "walk", "run", "mine", "dig", "scoop"]
	for a in expected_anims:
		if not anim_player.has_animation(a):
			_fail("Анимация '%s' отсутствует в character_model.tscn" % a)
			return
		var anim = anim_player.get_animation(a)
		print("  • Анимация '%s' найдена (длина: %.2f сек, треков: %d)" % [a, anim.length, anim.get_track_count()])
	
	# Переключение анимаций живого игрока идёт через алиасы на модель пакета.
	player.play_animation("walk")
	if player.current_anim == "" or not player.anim_player.has_animation(player.current_anim):
		_fail("Не удалось включить анимацию 'walk' на модели игрока")
		return
	print("  • Переключение на 'walk' успешно (клип: %s)." % player.current_anim)
	
	player.play_mining_animation()
	if not player.is_mining or player.current_anim == "":
		_fail("Не удалось активировать взмах инструментом (mining animation)")
		return
	print("  • Анимация удара успешно запущена (клип: %s)." % player.current_anim)
	player.is_mining = false
	
	# 3. Проверка динамического отображения инструмента и шляпы:
	# виден инструмент экипированного слота, а не всегда кирка
	print("\n--- Проверка 3: Динамическое управление видимостью экипировки ---")
	# 3. Проверка динамического отображения инструмента живого игрока
	# (модель шахтёра из пакета; фермерская сцена выше проверена отдельно).
	print("\n--- Проверка 3: Динамическое управление видимостью экипировки ---")
	var player_pickaxe: Node3D = player.equipped_pickaxe_mesh
	if player_pickaxe == null:
		_fail("Узел кирки не найден у игрока (Equipped_Pickaxe/Pickaxe)")
		return
	player.inventory.equip_tool("pickaxe")
	player.set_equipped_tool_visible(false)
	if player_pickaxe.visible:
		_fail("Инструмент должен быть скрыт при вызове set_equipped_tool_visible(false)")
		return
	print("  • Инструмент корректно скрывается, когда убран.")

	player.set_equipped_tool_visible(true)
	if not player_pickaxe.visible:
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
	if player_pickaxe.visible:
		_fail("Кирка должна быть скрыта, когда экипирована лопата (раньше везде была кирка)")
		return
	print("  • Лопата корректно отображается в руках, кирка скрыта.")

	# Шляпа/каска: у фермера — Sun_Hat, у шахтёра пакета — шлем (Character_Helmet).
	# set_hat_visible не должен падать при отсутствии Sun_Hat.
	player.set_hat_visible(false)
	player.set_hat_visible(true)
	var helmet = player.find_child("Character_Helmet", true, false)
	if player.sun_hat_mesh == null and helmet == null:
		_fail("Ни Sun_Hat, ни Character_Helmet не найдены у модели игрока")
		return
	print("  • Головной убор модели игрока на месте.")
	
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
