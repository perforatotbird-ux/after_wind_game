extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
const PickaxeScene = preload("res://scenes/tools/pickaxe_model.tscn")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print(">>> Инициализация теста Miner & Pickaxe...")
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
	print("⛏️ ЗАПУСК ТЕСТОВ: МОДЕЛЬ ШАХТЕРА, КИРКА, АНИМАЦИИ И СПРАЙТЫ")
	print("=================================================================")
	
	var player = root.get_node_or_null("Player")
	if not player:
		_fail("Узел Player не найден в корне дерева")
		return
	
	# 1. Проверка структуры модели шахтера в сцене игрока
	print("\n--- Проверка 1: Структура модели Шахтера в Player.tscn ---")
	var visuals = player.get_node_or_null("Visuals")
	if not visuals:
		_fail("Узел Visuals не найден в Player")
		return
	
	var miner_model = visuals.get_node_or_null("CharacterModel")
	if not miner_model:
		miner_model = visuals.get_node_or_null("MinerModel")
	if not miner_model:
		_fail("Узел модели персонажа (CharacterModel или MinerModel) не найден в Player/Visuals")
		return
	print("  • Модель персонажа успешно найдена в Visuals.")
	
	var skeleton = miner_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton:
		_fail("Skeleton3D не найден внутри модели")
		return
	print("  • Арматура Skeleton3D найдена. Число костей: %d" % skeleton.get_bone_count())
	if skeleton.get_bone_count() < 15:
		_fail("Недостаточно костей в Skeleton3D (ожидалось >= 15)")
		return
	
	var equipped_pickaxe = miner_model.find_child("Equipped_Pickaxe", true, false) as MeshInstance3D
	if not equipped_pickaxe:
		_fail("Equipped_Pickaxe не найден внутри модели персонажа")
		return
	print("  • Equipped_Pickaxe прикреплена к правой руке персонажа.")
	
	# 2. Проверка AnimationPlayer и запеченных анимаций
	print("\n--- Проверка 2: AnimationPlayer и анимации шахтера ---")
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
		_fail("Не удалось активировать взмах киркой (mining animation)")
		return
	print("  • Анимация удара киркой 'mine' успешно запущена.")
	
	# 3. Проверка динамического отображения кирки в руках
	print("\n--- Проверка 3: Динамическое снаряжение кирки в руках ---")
	player.set_equipped_tool_visible(false)
	if equipped_pickaxe.visible:
		_fail("Кирка должна быть скрыта при вызове set_equipped_tool_visible(false)")
		return
	print("  • Кирка корректно скрывается, когда инструмент убран.")
	
	player.set_equipped_tool_visible(true)
	if not equipped_pickaxe.visible:
		_fail("Кирка должна быть видима при вызове set_equipped_tool_visible(true)")
		return
	print("  • Кирка корректно отображается в руках шахтера.")
	
	# 4. Проверка отдельной модели кирки
	print("\n--- Проверка 4: Автономная модель кирки (scenes/tools/pickaxe_model.tscn) ---")
	var pickaxe_inst = PickaxeScene.instantiate()
	if not pickaxe_inst:
		_fail("Не удалось инстанцировать PickaxeScene")
		return
	print("  • Автономная сцена PickaxeModel успешно инстанцирована.")
	pickaxe_inst.free()
	
	# 5. Проверка спрайтов и иконок UI
	print("\n--- Проверка 5: 2D Спрайты, портреты и иконки ---")
	var miner_class = CharacterClassDB.get_class_data("miner")
	if miner_class.is_empty():
		_fail("Класс miner не найден в CharacterClassDB")
		return
	print("  • Класс 'miner' в БД: %s, портрет: %s, спрайт: %s" % [miner_class.name, miner_class.portrait, miner_class.sprite])
	
	var portrait_file = FileAccess.file_exists(miner_class.portrait)
	if not portrait_file:
		_fail("Файл портрета не найден: " + miner_class.portrait)
		return
	print("  • Портрет шахтера (miner_portrait.png) существует.")
	
	var sprite_file = FileAccess.file_exists(miner_class.sprite)
	if not sprite_file:
		_fail("Файл изометрического спрайта не найден: " + miner_class.sprite)
		return
	print("  • Изометрический спрайт шахтера (miner_isometric.png) существует.")
	
	var pickaxe_item = ItemDB.get_item("pickaxe")
	if pickaxe_item.is_empty():
		_fail("Предмет 'pickaxe' не найден в ItemDB")
		return
	if not FileAccess.file_exists(pickaxe_item.texture):
		_fail("Иконка кирки не найдена: " + pickaxe_item.texture)
		return
	print("  • Иконка кирки в ItemDB (%s) существует и привязана." % pickaxe_item.texture)
	
	var iron_pickaxe_item = ItemDB.get_item("iron_pickaxe")
	if iron_pickaxe_item.is_empty():
		_fail("Предмет 'iron_pickaxe' не найден в ItemDB")
		return
	if not FileAccess.file_exists(iron_pickaxe_item.texture):
		_fail("Иконка железной кирки не найдена: " + iron_pickaxe_item.texture)
		return
	print("  • Иконка улучшенной кирки в ItemDB (%s) существует и привязана." % iron_pickaxe_item.texture)
	
	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ МОДЕЛИ ШАХТЕРА И КИРКИ ПРОЙДЕНЫ НА 100%! (CODE 0)")
	print("=================================================================")
	quit(0)
