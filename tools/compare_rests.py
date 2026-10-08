"""Compare rest orientations UAL vs farmer to detect side swap."""
import bpy
from mathutils import Vector

bpy.ops.wm.open_mainfile(filepath='K:/After Wind/assets/models/character/stardew_farmer.blend')
farm = bpy.data.objects['FarmerRig']
bpy.ops.import_scene.gltf(
    filepath='C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
ual = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name != 'FarmerRig')
print("UAL ARM:", ual.name, [b.name for b in ual.data.bones][:6])

print("UAL rest (world):")
for b in ('DEF-upper_arm.R', 'DEF-upper_arm.L', 'DEF-hand.R', 'DEF-hand.L', 'DEF-hips'):
    M = ual.matrix_world @ ual.data.bones[b].matrix_local
    print(f"  {b}: loc={tuple(round(v,2) for v in M.translation)} det={round(M.determinant(),3)}")
print("FARMER rest (world):")
for b in ('UpperArm.R', 'UpperArm.L', 'Hand.R', 'Hand.L', 'Hips'):
    M = farm.matrix_world @ farm.data.bones[b].matrix_local
    print(f"  {b}: loc={tuple(round(v,2) for v in M.translation)} det={round(M.determinant(),3)}")
