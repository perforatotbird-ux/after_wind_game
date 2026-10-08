"""Which way do UAL hands move during PickUp reach?"""
import bpy
from mathutils import Vector

bpy.ops.import_scene.gltf(
    filepath='C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
rig.animation_data.action = bpy.data.actions.get('PickUp_Table')
for f in (1, 13):
    bpy.context.scene.frame_set(f)
    bpy.context.view_layer.update()
    for b in ('DEF-hand.R', 'DEF-hips'):
        w = rig.matrix_world @ rig.pose.bones[b].matrix
        print(f"f{f} {b}: {tuple(round(v, 3) for v in w.translation)}")
