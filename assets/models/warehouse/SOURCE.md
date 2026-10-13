# Product warehouse — ruined and restored

Own procedural geometry, designed from the user's `склад_wreck.jpg` and `склад.jpg` references. Raster references are not embedded in runtime resources. Stylized interpretation: stone footing, vertical siding, heavy timber frame, open iron-bound gates, breached/intact wooden roof with corrugated patches, interior shelves/crates/barrels, front rope hoist, lanterns and stage-1 canvas.

Shared original painted wood/stone and normal textures are the project's house materials in assets/models/house. Meshes are split by architectural function, vertex-compressed text ArrayMesh; each resource <1 MiB. Moving meshes keep their own pivots. Approx. 44k triangles per model.

Build with bpy 5.x, numpy and Pillow:
```
python tools/create_warehouse_models.py /tmp/warehouse_build
godot --headless --path . -s tools/import_warehouse_models.gd -- /tmp/warehouse_build
```
Godot 4.7.2 runtime requires only committed resources. Stage 2+ unlocks an independent empty 20-cell inventory (the visible crates are decoration). Stage 3 animates the front hoist; restored lanterns illuminate at night. Existing repair prices and player-weight bonuses retained. Persistent items and cell order live in buildings.storage_inventory in v2 saves.

Details: docs/DOCUMENTATION.md, «Модель склада». Tests: test_storage_model.gd and test_storage_inventory.gd. Old assets/models/storage and their old generators remain as unused legacy assets.
