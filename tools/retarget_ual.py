"""Retarget Quaternius UAL v1 mocap (CC0, Godot Asset Store) onto the farmer rig.
- dig   <- Fixing_Kneeling frames 30..90 (bend -> kneel work -> early rise)
- scoop <- PickUp_Table frames 1..20 (reach -> lift)
World-space copy with rest-pose compensation; feet may slide slightly.
Run: Blender --background stardew_farmer.blend --python retarget_ual.py
Env SAVE=1: write .blend + export .glb (else preview renders only).
"""
import bpy
import math
import os
from mathutils import Vector, Matrix, Quaternion

UAL_GLB = ("C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/"
           "Godot/AnimationLibrary_Godot_Standard.glb")
ROOT = "K:/After Wind"
OUT = ROOT + "/outputs/ual_retarget"
os.makedirs(OUT, exist_ok=True)
SAVE = os.environ.get("SAVE") == "1"
UAL_FPS = 30
DST_FPS = 60

# UAL «R»-сторона физически на -X, у фермера «R» — на +X, обе смотрят -Y.
# Превью показало: зеркальный своп ломает сильнее, чем чинит.
# Возвращаем прямое соответствие + доворот источника π (стороны совпадают
# пространственно, жесты не зеркалятся).
MAP = {
    'DEF-hips': 'Hips',
    'DEF-spine.001': 'Spine',
    'DEF-spine.003': 'Chest',
    'DEF-neck': 'Neck',
    'DEF-head': 'Head',
    'DEF-shoulder.L': 'Clavicle.L',
    'DEF-upper_arm.L': 'UpperArm.L',
    'DEF-forearm.L': 'Forearm.L',
    'DEF-hand.L': 'Hand.L',
    'DEF-thigh.L': 'Thigh.L',
    'DEF-shin.L': 'Shin.L',
    'DEF-foot.L': 'Foot.L',
    'DEF-shoulder.R': 'Clavicle.R',
    'DEF-upper_arm.R': 'UpperArm.R',
    'DEF-forearm.R': 'Forearm.R',
    'DEF-hand.R': 'Hand.R',
    'DEF-thigh.R': 'Thigh.R',
    'DEF-shin.R': 'Shin.R',
    'DEF-foot.R': 'Foot.R',
}

SEGMENTS = {
    # dst_name: (src_action, src_first, src_last, src_step)
    'dig': ('Fixing_Kneeling', 30, 90, 2),
    'scoop': ('PickUp_Table', 1, 20, 1),
}


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = 'QUATERNION'


def rest_world(arm, bone_name):
    return arm.matrix_world @ arm.data.bones[bone_name].matrix_local


def posed_world(arm, bone_name):
    return arm.matrix_world @ arm.pose.bones[bone_name].matrix


def src_world_quat(src, bone_name):
    return (src.matrix_world @ src.pose.bones[bone_name].matrix).to_quaternion()


def src_world_pos(src, bone_name):
    return src.matrix_world @ src.pose.bones[bone_name].matrix.translation.copy()


def src_rest_world_pos(src, bone_name):
    return src.matrix_world @ src.data.bones[bone_name].head_local.copy()


HIP_SCALE = [1.0]


def retarget_segment(farm, src, dst_name, src_action_name, first, last, step):
    """Классический rotation-only ретаргет: мировые кватернионы копируются,
    позиции берутся из FK (кроме Hips — у него копируется дельта)."""
    src_action = bpy.data.actions.get(src_action_name)
    if src_action is None:
        raise RuntimeError(f"source action {src_action_name} missing")
    old = bpy.data.actions.get(dst_name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(dst_name)
    action.use_fake_user = True
    if farm.animation_data is None:
        farm.animation_data_create()
    farm.animation_data.use_nla = False
    farm.animation_data.action = action
    if src.animation_data is None:
        raise RuntimeError("source has no animation_data")
    for track in src.animation_data.nla_tracks:
        track.mute = True
    src.animation_data.action = src_action
    # Топологический порядок: родители раньше детей.
    order = ['Hips', 'Spine', 'Chest', 'Neck', 'Head',
             'Clavicle.L', 'UpperArm.L', 'Forearm.L', 'Hand.L',
             'Thigh.L', 'Shin.L', 'Foot.L',
             'Clavicle.R', 'UpperArm.R', 'Forearm.R', 'Hand.R',
             'Thigh.R', 'Shin.R', 'Foot.R']
    rev = {v: k for k, v in MAP.items()}
    previous = {}
    frames = list(range(first, last + 1, step))
    for i, sf in enumerate(frames):
        bpy.context.scene.frame_set(sf)
        bpy.context.view_layer.update()
        df = 1 + (sf - first) / UAL_FPS * DST_FPS
        # Root неподвижен (без root motion): его мировой кватернион = rest.
        # (Сидить identity ломало ВСЁ тело на поворот rest-косты Root!)
        final_q = {'Root': (farm.matrix_world
                            @ farm.data.bones['Root'].matrix_local).to_quaternion()}
        skip = set(x for x in os.environ.get("SKIP", "").split(",") if x)
        for t_name in order:
            if t_name in skip:
                continue
            s_name = rev.get(t_name)
            pb = farm.pose.bones[t_name]
            if s_name is None:
                continue
            q_w = src_world_quat(src, s_name)
            if t_name == 'Hips':
                # Локальный оффсет таза = мировая дельта источника × масштаб роста.
                pb.location = ((src_world_pos(src, s_name)
                                - src_rest_world_pos(src, s_name)) * HIP_SCALE[0])
            q_parent = final_q.get(pb.parent.name)
            if q_parent is None:
                q_parent = (farm.matrix_world @ pb.parent.bone.matrix_local).to_quaternion()
            q_local = q_parent.inverted() @ q_w
            if t_name in previous and q_local.dot(previous[t_name]) < 0:
                q_local.negate()
            pb.rotation_quaternion = q_local
            previous[t_name] = q_local.copy()
            q_parent = final_q.get(pb.parent.name)
            if q_parent is None:
                q_parent = (farm.matrix_world @ pb.parent.bone.matrix_local).to_quaternion()
            final_q[t_name] = q_parent @ q_local
        for pb in farm.pose.bones:
            if pb.name == 'Hips':
                pb.keyframe_insert('location', frame=df)
            if pb.name in final_q:
                pb.keyframe_insert('rotation_quaternion', frame=df)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    print(f"retargeted {dst_name}: src {src_action_name}[{first}-{last}] -> {len(frames)} keys")
    return action


CANONICAL = {'Equipped_Pickaxe', 'Farmer_Character', 'FarmerRig', 'Fill_Light',
               'IsoCamera', 'Key_Light', 'PortraitCamera', 'Rim_Light',
               'Sun_Hat', 'UnderHat_Light', 'PreviewGround'}


def main():
    farm = bpy.data.objects['FarmerRig']
    bpy.context.scene.render.fps = DST_FPS
    # Чистим мусор прошлых превью-запусков (LIB_*-темпы),
    # чтобы он не засорял рендеры и не сохранялся в .blend.
    for o in [o for o in bpy.data.objects if o.name not in CANONICAL
              and o.name != 'Mannequin' and o.type != 'ARMATURE']:
        print("removing leftover temp:", o.name)
        bpy.data.objects.remove(o, do_unlink=True)
    fad = farm.animation_data
    print(f"FARM animdata: use_nla={fad.use_nla if fad else None} "
          f"tracks={[t.name for t in fad.nla_tracks] if fad else []} "
          f"action={fad.action.name if fad and fad.action else None}")
    if fad:
        fad.use_nla = False
    # Импорт UAL-манекена.
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=UAL_GLB)
    new_objs = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new_objs if o.type == 'ARMATURE')
    for o in new_objs:
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    print("UAL rig imported; junk removed")
    # Масштаб под рост фермера (по высоте таза).
    farm_hips_z = (farm.matrix_world @ farm.data.bones['Hips'].head_local).z
    src_hips_z = (src.matrix_world @ src.data.bones['DEF-hips'].head_local).z
    s = farm_hips_z / src_hips_z
    # Доворот источника π вокруг Z + масштаб: стороны совпадают пространственно.
    # (Без запекания — только трансформ объекта, формула учитывает matrix_world.)
    src.rotation_euler = (0, 0, math.pi)
    src.scale = (s, s, s)
    bpy.context.view_layer.update()
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = farm
    bpy.context.view_layer.update()
    print(f"hips: farm={farm_hips_z:.3f} ual={src_hips_z:.3f} scale={s:.3f} sides_swapped")
    HIP_SCALE[0] = s
    reset_pose(farm)

    for dst_name, (src_action, first, last, step) in SEGMENTS.items():
        retarget_segment(farm, src, dst_name, src_action, first, last, step)

    # Числовая сверка rotation-only ретаргета: мировые кватернионы должны совпасть.
    for t in src.animation_data.nla_tracks:
        t.mute = True
    src.animation_data.action = bpy.data.actions.get('Fixing_Kneeling')
    farm.animation_data.action = bpy.data.actions.get('dig')
    bpy.context.scene.frame_set(61)
    bpy.context.view_layer.update()
    for s_name, t_name in (('DEF-upper_arm.R', 'UpperArm.R'),
                           ('DEF-upper_arm.L', 'UpperArm.L'),
                           ('DEF-hips', 'Hips'),
                           ('DEF-head', 'Head'),
                           ('DEF-hand.R', 'Hand.R'),
                           ('DEF-neck', 'Neck')):
        q_s = (src.matrix_world @ src.pose.bones[s_name].matrix).to_quaternion()
        q_f = (farm.matrix_world @ farm.pose.bones[t_name].matrix).to_quaternion()
        a = abs(q_s.rotation_difference(q_f).angle) % (2 * math.pi)
        angle = min(a, 2 * math.pi - a)
        print(f"VERIFY {s_name}->{t_name}: anglediff={angle:.4f} rad")

    # Превью на фермере с инструментами. (Манекен уже удалён при импорте.)
    mannequin = None
    SHOW_SRC = False
    SIDE_BY_SIDE = False
    farmer_vis = True
    for o in ('Farmer_Character', 'Sun_Hat'):
        oo = bpy.data.objects.get(o)
        if oo:
            oo.hide_viewport = oo.hide_render = False
    embedded_pick = bpy.data.objects.get('Equipped_Pickaxe')
    if embedded_pick:
        embedded_pick.hide_viewport = embedded_pick.hide_render = True
        print("HID embedded_pickaxe")
    else:
        print("WARNING: Equipped_Pickaxe NOT FOUND for hiding!")
    print("VISIBLE_MESHES:", [o.name for o in bpy.data.objects
                              if o.type == 'MESH' and not o.hide_viewport])
    tools_dir = ROOT + "/assets/models/tools"
    bpy.ops.import_scene.gltf(filepath=tools_dir + "/shovel_inhand.glb")
    shovel = bpy.context.selected_objects[0]
    bpy.ops.import_scene.gltf(filepath=tools_dir + "/bucket_inhand.glb")
    bucket = bpy.context.selected_objects[0]
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for tool_obj in (shovel, bucket):
        bpy.ops.object.select_all(action='DESELECT')
        farm.data.bones.active = farm.data.bones['ToolSocket.R']
        tool_obj.select_set(True)
        bpy.context.view_layer.objects.active = farm
        bpy.ops.object.parent_set(type='BONE', keep_transform=False)
        tool_obj.parent_bone = 'ToolSocket.R'
        tool_obj.rotation_mode = 'XYZ'
        tool_obj.location = Vector((0, 0, 0))
        tool_obj.rotation_euler = (0, 0, 0)
    print("TOOLS:", [(o.name, o.type, o.parent_bone if o.parent else None,
                      o.hide_viewport, o.hide_render) for o in (shovel, bucket)])

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 560
    scene.render.resolution_y = 560
    scene.render.film_transparent = False
    try:
        scene.world.color = (0.045, 0.045, 0.055)
    except Exception:
        pass
    cam = bpy.data.objects.get('IsoCamera')
    cam.data.type = 'ORTHO'
    scene.camera = cam
    if 'PreviewGround' not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, -0.005))
        bpy.context.object.name = 'PreviewGround'

    def shot(action_name, frame, fname, show, loc, tgt, ortho):
        print("SHOT", fname, "visible:", [o.name for o in bpy.data.objects
                                          if o.type == 'MESH' and not o.hide_render])
        shovel.hide_render = shovel.hide_viewport = ('shovel' not in show)
        bucket.hide_render = bucket.hide_viewport = ('bucket' not in show)
        farm.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(int(round(frame)))
        bpy.context.view_layer.update()
        cam.location = Vector(loc)
        cam.data.ortho_scale = ortho
        cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT, fname)
        bpy.ops.render.render(write_still=True)
        print("rendered", fname)

    # Доворот лопаты внутри dig-клипа: клинок смотрит вверх — доворачиваем
    # сокет постоянным локальным доворотом, чтобы клинок (+Z инструмента)
    # смотрел вниз-вперёд в грунт. Действует только внутри dig (mine не тронут).
    farm.animation_data.action = bpy.data.actions.get('dig')
    scene.frame_set(61)
    bpy.context.view_layer.update()
    sock = farm.pose.bones['ToolSocket.R']
    parent_w = (farm.matrix_world @ sock.parent.matrix).to_3x3()
    d_cur = ((farm.matrix_world @ sock.matrix).to_3x3() @ Vector((0, 0, 1))).normalized()
    d_want = Vector((0, -0.45, -0.89)).normalized()
    r_world = d_cur.rotation_difference(d_want)
    r_local = (parent_w.inverted() @ r_world.to_matrix()).to_quaternion()
    print(f"DIGFIX blade {tuple(round(v,2) for v in d_cur)} r_local={tuple(round(v,3) for v in r_local)}")
    # У сокета в dig-клипе ключей нет (следует за рукой); создаём постоянный
    # локальный доворот двумя ключами (1 и 121) — хватит на весь клип.
    sock.rotation_quaternion = r_local
    for t in (1, 121):
        scene.frame_set(t)
        bpy.context.view_layer.update()
        sock.rotation_quaternion = r_local
        sock.keyframe_insert('rotation_quaternion', frame=t)
    dig_action = bpy.data.actions.get('dig')
    for layer in dig_action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if 'ToolSocket.R' in fc.data_path:
                        for kp in fc.keyframe_points:
                            kp.interpolation = 'LINEAR'
    print("DIGFIX: constant socket offset keyed at 1..121")
    scene.frame_set(61)
    bpy.context.view_layer.update()
    ISO = ((2.7, -4.2, 2.4), (0, -0.12, 1.05), 2.65)
    FRONT = ((0, -4.5, 1.5), (0, 0, 0.9), 2.2)
    BACK = ((0, 4.5, 1.5), (0, 0, 0.9), 2.2)
    CLOSE = ((0.3, -1.8, 1.0), (0.1, -0.2, 0.8), 1.2)
    KNEEL = ((0, -4.2, 1.1), (0, -0.1, 0.55), 2.0)
    KNEEL_SIDE = ((4.2, -0.3, 1.0), (0, -0.2, 0.55), 2.0)
    dig_mid = 1 + (60 - 30) / UAL_FPS * DST_FPS
    scoop_mid = 1 + (10 - 1) / UAL_FPS * DST_FPS
    shot('dig', dig_mid, 'r_dig_mid.png', 'shovel', *ISO)
    shot('dig', dig_mid, 'r_dig_front.png', 'shovel', *FRONT)
    shot('scoop', scoop_mid, 'r_scoop_mid.png', 'bucket', *ISO)
    shot('scoop', scoop_mid, 'r_scoop_front.png', 'bucket', *FRONT)
    shot('dig', dig_mid, 'r_dig_close.png', 'shovel', *CLOSE)
    shot('scoop', scoop_mid, 'r_scoop_close.png', 'bucket', *CLOSE)
    shot('dig', dig_mid, 'r_dig_back.png', 'shovel', *BACK)
    shot('dig', dig_mid, 'r_dig_kneel.png', 'shovel', *KNEEL)
    shot('dig', dig_mid, 'r_dig_kneel_side.png', 'shovel', *KNEEL_SIDE)
    if SHOW_SRC:
        shot('dig', dig_mid, 'src_dig_mid.png', '', *ISO)
        shot('scoop', scoop_mid, 'src_scoop_mid.png', '', *ISO)
    if SIDE_BY_SIDE:
        # Манекен рядом (сдвиг +1.6 по X) в той же NLA-позе для прямого сравнения.
        mannequin.location.x = 1.6
        for t in src.animation_data.nla_tracks:
            t.mute = True
        src.animation_data.action = bpy.data.actions.get('Fixing_Kneeling')
        farm.animation_data.action = bpy.data.actions.get('dig')
        scene.frame_set(61)
        bpy.context.view_layer.update()
        for tool_obj, want in ((shovel, True), (bucket, False)):
            tool_obj.hide_viewport = tool_obj.hide_render = not want
        cam.location = Vector((0.8, -5.5, 1.6))
        cam.data.ortho_scale = 4.2
        cam.rotation_euler = (Vector((0.8, 0, 0.8)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT, 'side_dig_srcpose.png')
        bpy.ops.render.render(write_still=True)
        print("rendered side_dig_srcpose.png")

    if SAVE:
        if embedded_pick:
            embedded_pick.hide_viewport = embedded_pick.hide_render = False
        for o in (shovel, bucket):
            bpy.data.objects.remove(o, do_unlink=True)
        if 'PreviewGround' in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects['PreviewGround'], do_unlink=True)
        # UAL-манекен тоже вычищаем перед сохранением.
        bpy.data.objects.remove(src, do_unlink=True)
        mannequin = bpy.data.objects.get('Mannequin')
        if mannequin:
            bpy.data.objects.remove(mannequin, do_unlink=True)
        reset_pose(farm)
        farm.animation_data.action = bpy.data.actions['idle']
        scene.frame_set(1)
        bpy.ops.wm.save_as_mainfile(
            filepath=ROOT + "/assets/models/character/stardew_farmer.blend")
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [farm, bpy.data.objects['Farmer_Character'],
                    bpy.data.objects['Sun_Hat'], bpy.data.objects['Equipped_Pickaxe']]:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = farm
        bpy.ops.export_scene.gltf(
            filepath=ROOT + "/assets/models/character/stardew_farmer.glb",
            export_format='GLB', use_selection=True, export_apply=False,
            export_animations=True, export_animation_mode='ACTIONS',
            export_force_sampling=True, export_frame_range=False,
            export_skins=True, export_morph=False, export_lights=False, export_cameras=False)
        print("SAVED farmer with retargeted dig/scoop")
    else:
        print("PREVIEW ONLY. Set SAVE=1 to write.")


if __name__ == '__main__':
    main()
