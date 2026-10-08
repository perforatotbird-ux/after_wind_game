"""Decisive facing probe: bend direction in Fixing_Kneeling."""
import bpy
from mathutils import Vector

bpy.ops.import_scene.gltf(
    filepath='C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for t in rig.animation_data.nla_tracks:
    t.mute = True
rig.animation_data.action = bpy.data.actions.get('Fixing_Kneeling')
for f in (1, 30, 60, 90, 124):
    bpy.context.scene.frame_set(f)
    bpy.context.view_layer.update()
    hp = rig.matrix_world @ rig.pose.bones['DEF-hips'].matrix
    hd = rig.matrix_world @ rig.pose.bones['DEF-head'].matrix
    print(f"f{f}: hips={tuple(round(v,2) for v in hp.translation)} head={tuple(round(v,2) for v in hd.translation)}")
