"""Swap embedded pickaxe meshes (mine, stylized) with Quaternius Pickaxe_Bronze.
- farmer blend: remove skinned Equipped_Pickaxe, add Q pickaxe BONE-parented to
  ToolSocket.R (miner pattern) named Equipped_Pickaxe. Actions untouched.
- miner blend: same swap (already bone-parented pattern).
Run headless per blend:
  Blender --background <blend> --python swap_pickaxe_mesh.py
Saves the .blend in place. Export is done by the existing pipeline scripts.
"""
import bpy
import os
from mathutils import Vector

Q_PICKAXE = "K:/After Wind/assets/models/tools/pickaxe_inhand.glb"


def swap(arm_name, char_name=None):
    arm = bpy.data.objects.get(arm_name)
    if arm is None:
        raise RuntimeError(f"armature {arm_name} not found")
    old = bpy.data.objects.get('Equipped_Pickaxe')
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
        print(f"removed old Equipped_Pickaxe from {arm_name}")
    # Импорт нормализованной кирки (grip в origin, рукоять +Z, голова вдоль Y).
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=Q_PICKAXE)
    new_objs = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new_objs if o.type == 'MESH']
    # Джойним на случай нескольких кусков, имя как у оригинала.
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    tool = bpy.context.active_object
    tool.name = 'Equipped_Pickaxe'
    # Кость-родитель как у майнера: поза следует за рукой без весов.
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    arm.data.bones.active = arm.data.bones['ToolSocket.R']
    tool.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='BONE', keep_transform=False)
    tool.parent_bone = 'ToolSocket.R'
    tool.rotation_mode = 'XYZ'
    tool.location = Vector((0, 0, 0))
    tool.rotation_euler = (0, 0, 0)
    print(f"attached Quaternius pickaxe to {arm_name}/ToolSocket.R: "
          f"verts={len(tool.data.vertices)} mats={[m.name if m else None for m in tool.data.materials]}")
    bpy.ops.wm.save_as_mainfile()


if __name__ == '__main__':
    if 'FarmerRig' in bpy.data.objects:
        swap('FarmerRig', 'Farmer_Character')
    elif 'MinerRig' in bpy.data.objects:
        swap('MinerRig', 'Miner_Character')
        # Экспорт майнера теми же параметрами, что в create_miner_and_pickaxe.py.
        bpy.ops.export_scene.gltf(
            filepath="K:/After Wind/assets/models/character/miner.glb",
            export_format='GLB', use_selection=False,
            export_materials='EXPORT', export_apply=False,
            export_animations=True, export_anim_single_armature=True,
            export_nla_strips=True)
        print("exported miner.glb")
    else:
        raise RuntimeError('no known rig in this blend')
    print("SWAP_DONE")
