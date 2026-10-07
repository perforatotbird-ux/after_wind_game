extends SceneTree

func _init() -> void:
	var sc = load("res://scenes/player/character_model.tscn").instantiate()
	var ap = sc.find_child("AnimationPlayer", true, false)
	print("AnimationPlayer found:", ap != null)
	if ap:
		for a_name in ap.get_animation_list():
			var anim = ap.get_animation(a_name)
			print("\n=== Anim: ", a_name, " len: ", anim.length, " tracks: ", anim.get_track_count())
			for t in range(anim.get_track_count()):
				var path = anim.track_get_path(t)
				var k_cnt = anim.track_get_key_count(t)
				var val0 = anim.track_get_key_value(t, 0)
				var val_mid = anim.track_get_key_value(t, int(k_cnt/2))
				print("   Track: ", path, " keys: ", k_cnt, " v0: ", val0, " vMid: ", val_mid)
	quit(0)
