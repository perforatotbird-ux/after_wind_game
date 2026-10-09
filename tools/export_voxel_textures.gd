extends SceneTree
## Превью текстур жил: тайлы VoxelTextures, увеличенные ×6, в одну строку.
## Запуск: godot --headless --path . -s tools/export_voxel_textures.gd [-- путь.png]
const VoxelTextures = preload("res://scripts/world/voxel_textures.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://voxel_textures_preview.png"
	var scale: int = 6
	var t: int = VoxelTextures.TILE * scale
	var gap: int = 8
	var img := Image.create_empty(VoxelTextures.TILE_COUNT * (t + gap) + gap, t + gap * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.12, 0.13))
	for i in VoxelTextures.TILE_COUNT:
		var tile: Image = VoxelTextures.get_tile_image(i)
		tile.resize(t, t, Image.INTERPOLATE_NEAREST)
		img.blit_rect(tile, Rect2i(0, 0, t, t), Vector2i(gap + i * (t + gap), gap))
	img.save_png(out)
	print("Сохранено: ", ProjectSettings.globalize_path(out))
	quit()
