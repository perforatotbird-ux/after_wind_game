# Timber cottage — ruined and restored

Created for this project from the user's visual references `House_wreck.jpg` and `House.jpg`.
Own procedural geometry, wood grain and stone textures. Reference rasters are not embedded in the game; this is a stylized interpretation, not an imported scan.

Features: timber siding/posts, individual shingles, real roof and wall breaches in the ruined version, stone footing/steps/chimney, wooden door and window frames, debris, stage-1 canvas tarp. Restored final stage adds warm windows and chimney smoke using the project's existing soft smoke texture.

Rebuild:
```
python tools/create_house_models.py /tmp/house_build
godot --headless --path . -s tools/import_house_models.gd -- /tmp/house_build
```
Dependencies for rebuilding: bpy 5.x, numpy, Pillow; Godot 4.7.2. Runtime only needs the committed Godot resources. Each file <1 MiB, vertex-compressed ArrayMesh, shared materials and portable compressed textures. Two architectural models are mapped onto four existing gameplay stages, without changing repair costs, sleep, house storage bonus or save format.

Coordinate system: facade +Z in Godot, ground at Y=0. Building stays at (-6.2,0,-5.5). Regression: tests/test_house_models.gd. Detailed documentation: docs/DOCUMENTATION.md, «Модель дома».
