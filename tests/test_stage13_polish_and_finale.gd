extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 13...")
	var world_node = WorldScene.instantiate()
	root.add_child(world_node)

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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 13: GAME FEEL, АУДИО, ПАУЗА И BASE RESTORED")
	print("=================================================================")
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var hud = world.get_node_or_null("HUD")
	if not hud:
		_fail("HUD не найден")
		return
	
	var inv = player.get("inventory")
	if not inv:
		_fail("Инвентарь игрока не найден")
		return

	# -------------------------------------------------------------
	# 1. Проверка процедурного AudioManager
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Процедурный AudioManager и генерация звуков ---")
	var audio_mgr = world.find_child("AudioManager", true, false)
	if not audio_mgr:
		_fail("AudioManager не найден среди дочерних узлов World")
		return
	
	if not AudioManager.instance:
		_fail("Статический экземпляр AudioManager.instance равен null")
		return
	
	var expected_sounds: Array[String] = [
		"hit_wood", "hit_stone", "till_soil", "harvest",
		"machine_start", "coins", "water_splash", "ui_click",
		"victory_fanfare", "wind_ambient", "rain_ambient"
	]
	
	for s_name in expected_sounds:
		if not audio_mgr._sounds.has(s_name):
			_fail("Звуковой эффект '%s' отсутствует в реестре AudioManager" % s_name)
			return
		var stream: AudioStreamWAV = audio_mgr._sounds[s_name]
		if not stream or stream.data.is_empty():
			_fail("Аудиопоток '%s' пуст или не сгенерирован" % s_name)
			return
		print("  • Звук '%s': %d байт PCM, mix_rate: %d Гц" % [s_name, stream.data.size(), stream.mix_rate])
	
	# Проверка вызова воспроизведения и регулировки громкости
	AudioManager.play("hit_wood", 1.05)
	AudioManager.play("coins", 1.0)
	AudioManager.play("ui_click")
	
	audio_mgr.set_sfx_vol(0.5)
	if abs(audio_mgr.sfx_volume - 0.5) > 0.01:
		_fail("Регулировка sfx_volume не сработала")
		return
	
	audio_mgr.set_ambient_vol(0.7)
	if abs(audio