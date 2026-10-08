"""Numeric check of Head/Hand chains after retarget bake."""
import bpy
from mathutils import Vector

bpy.ops.wm.open_mainfile(filepath='K:/After Wind/assets/models/character/stardew_farmer.blend')
farm = bpy.data.objects['FarmerRig']
bpy.ops.import_scene.gltf(
    filepath='C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
src = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name != 'FarmerRig')

# Тот же алайнмент, что в ретаргете.
farm_hips_z = (farm.matrix_world @ farm.data.bones['Hips'].head_local).z
src_hips_z = (src.matrix_world @ src.data.bones['DEF-hips'].head_local).z
s = farm_hips_z / src_hips_z
bpy.ops.object.select_all(action='DESELECT')
src.select_set(True)
bpy.context.view_layer.objects.active = src
src.rotation_euler = (0, 0, __import__('math').pi)
src.scale = (s, s, s)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
for t in src.animation_data.nla_tracks:
    t.mute = True
src.animation_data.action = bpy.data.actions.get('Fixing_Kneeling')

MAP = {'DEF-neck': 'Neck', 'DEF-head': 'Head',
       'DEF-forearm.R': 'Forearm.R', 'DEF-hand.R': 'Hand.R',
       'DEF-upper_arm.R': 'UpperArm.R', 'DEF-hips': 'Hips'}
bpy.context.scene.frame_set(61)
bpy.context.view_layer.update()
for s_name, t_name in MAP.items():
    Mw_s = src.matrix_world @ src.pose.bones[s_name].matrix
    R_s = src.matrix_world @ src.data.bones[s_name].matrix_local
    R_t = farm.matrix_world @ farm.data.bones[t_name].matrix_local
    M_t = Mw_s @ R_s.inverted() @ R_t
    print(f"{s_name}->{t_name}:")
    print(f"  srcRestQ={tuple(round(v,3) for v in R_s.to_quaternion())} farmRestQ={tuple(round(v,3) for v in R_t.to_quaternion())}")
    print(f"  srcPoseQ={tuple(round(v,3) for v in Mw_s.to_quaternion())}")
    print(f"  resultQ={tuple(round(v,3) for v in M_t.to_quaternion())} resultLoc={tuple(round(v,3) for v in M_t.translation)}")
