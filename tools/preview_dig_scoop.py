"""Dig & scoop actions for the farmer + in-hand pose preview.
Run: Blender --background stardew_farmer.blend --python preview_dig_scoop.py
Env: SAVE=1 -> also save .blend and export .glb (only when previews accepted).
Renders go to outputs/dig_scoop_preview/.
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion

FPS = 60
SAVE = os.environ.get("SAVE") == "1"
OUT = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")),
                   "outputs", "dig_scoop_preview")
os.makedirs(OUT, exist_ok=True)


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = 'QUATERNION'


def aim_bone(arm, name, head, tail):
    bone = arm.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    direction = (tail - head).normalized()
    rotate = (rest @ Vector((0, 1, 0))).rotation_difference(direction)
    bone.matrix = Matrix.Translation(head) @ (rotate.to_matrix() @ rest).to_4x4()
    bpy.context.view_layer.update()


def posed_head(arm, bone_name):
    # Позиция головы кости с учётом позы родителей (курок торса/таза).
    pb = arm.pose.bones[bone_name]
    parent = pb.parent
    if parent is None:
        return pb.head.copy()
    return (parent.matrix @ parent.bone.matrix_local.inverted()
            @ pb.bone.head_local)


def solve_arm(arm, side, grip, tool_rotation):
    hand_name = 'Hand.' + side
    hand = arm.pose.bones[hand_name]
    hand_rest = hand.bone.matrix_local
    grip_rest = Vector((0.35 if side == 'R' else -0.35, -0.02, 0.76))
    wrist = grip - tool_rotation @ (grip_rest - hand_rest.translation)
    upper = arm.pose.bones['UpperArm.' + side]
    lower = arm.pose.bones['Forearm.' + side]
    shoulder = posed_head(arm, upper.name)
    l1, l2 = upper.bone.length, lower.bone.length
    delta = wrist - shoulder
    distance = delta.length
    if distance > l1 + l2 - 0.001:
        raise RuntimeError(f'{side} grip out of reach: {distance:.3f} > {l1+l2:.3f}')
    direction = delta.normalized()
    pole = Vector((1 if side == 'R' else -1, 0.15, -0.25))
    perpendicular = (pole - direction * pole.dot(direction)).normalized()
    along = (l1*l1 - l2*l2 + distance*distance) / (2*distance)
    elbow = shoulder + direction*along + perpendicular*math.sqrt(max(0, l1*l1-along*along))
    aim_bone(arm, upper.name, shoulder, elbow)
    aim_bone(arm, lower.name, elbow, wrist)
    hand.matrix = Matrix.Translation(wrist) @ (tool_rotation @ hand_rest.to_3x3()).to_4x4()
    bpy.context.view_layer.update()


def key_all(arm, action, frame, previous):
    for bone in arm.pose.bones:
        q = bone.rotation_quaternion.copy()
        if bone.name in previous and q.dot(previous[bone.name]) < 0:
            q.negate()
            bone.rotation_quaternion = q
        previous[bone.name] = q.copy()
        bone.keyframe_insert('location', frame=frame)
        bone.keyframe_insert('rotation_quaternion', frame=frame)
        bone.keyframe_insert('scale', frame=frame)


def linearize(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'


def build_action(arm, name, poses, use_fake=True):
    data = arm.animation_data_create() if not arm.animation_data else arm.animation_data
    data.action = None
    data.use_nla = False
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    if use_fake:
        action.use_fake_user = True
    data.action = action
    previous = {}
    for pose in poses:
        t, position, pitch, torso, dip = pose[:5]
        left_grip = pose[5] if len(pose) > 5 else None
        frame = 1 + round(t * FPS)
        reset_pose(arm)
        arm.pose.bones['Hips'].location = Vector((0, 0, dip))
        for bname, amount in [('Spine', torso * 0.4), ('Chest', torso * 0.6)]:
            arm.pose.bones[bname].rotation_quaternion = Quaternion((1, 0, 0), amount)
        bpy.context.view_layer.update()
        rotation = Matrix.Rotation(pitch, 3, 'X')
        grip = Vector(position)
        solve_arm(arm, 'R', grip, rotation)
        if left_grip is None:
            solve_arm(arm, 'L', grip + rotation @ Vector((0, 0, 0.10)), rotation)
        else:
            solve_arm(arm, 'L', Vector(left_grip), rotation)
        key_all(arm, action, frame, previous)
    linearize(action)
    return action


DIG_POSES = [
    # t, grip xyz (R), shaft pitch, torso bend, hips dip (=0: ноги прямые, ступни invariant)
    (0.00, (0.10, -0.28, 1.29), -1.55, 0.015, 0.00),
    (0.25, (0.12, -0.38, 1.10), -1.00, 0.220, 0.00),
    (0.45, (0.12, -0.42, 1.00), -0.45, 0.320, 0.00),
    (0.70, (0.12, -0.38, 1.12), -1.10, 0.240, 0.00),
    (1.10, (0.10, -0.28, 1.29), -1.55, 0.015, 0.00),
]

SCOOP_POSES = [
    # t, grip R, pitch, torso, dip, grip L (левая рука опущена — ведро несут одной рукой)
    (0.00, (0.10, -0.28, 1.29), -1.55, 0.015, 0.00, None),
    (0.35, (0.18, -0.38, 1.02), -1.20, 0.100, 0.00, (-0.25, -0.10, 0.95)),
    (0.55, (0.20, -0.40, 0.98), -1.05, 0.160, 0.00, (-0.25, -0.10, 0.93)),
    (0.80, (0.18, -0.38, 1.02), -1.20, 0.120, 0.00, (-0.25, -0.10, 0.95)),
    (1.20, (0.10, -0.28, 1.29), -1.55, 0.015, 0.00, None),
]


def setup_camera_ground():
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 560
    scene.render.resolution_y = 560
    scene.render.film_transparent = False
    try:
        scene.world.color = (0.045, 0.045, 0.055)
    except Exception:
        pass
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        pass
    camera = bpy.data.objects.get('IsoCamera')
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.65
    scene.camera = camera
    if 'PreviewGround' not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.005))
        plane = bpy.context.object
        plane.name = 'PreviewGround'
        mat = bpy.data.materials.new('PreviewGround')
        mat.diffuse_color = (0.065, 0.075, 0.09, 1)
        plane.data.materials.append(mat)


def parent_tool_to_socket(arm, tool_obj):
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    arm.data.bones.active = arm.data.bones['ToolSocket.R']
    tool_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='BONE', keep_transform=False)
    tool_obj.parent_bone = 'ToolSocket.R'
    tool_obj.location = Vector((0, 0, 0))
    tool_obj.rotation_euler = (0, 0, 0)


def main():
    arm = bpy.data.objects['FarmerRig']
    bpy.context.scene.render.fps = FPS
    reset_pose(arm)

    dig = build_action(arm, 'dig', DIG_POSES)
    scoop = build_action(arm, 'scoop', SCOOP_POSES)
    print(f"built dig ({dig.frame_range[0]:.0f}-{dig.frame_range[1]:.0f}) scoop ({scoop.frame_range[0]:.0f}-{scoop.frame_range[1]:.0f})")

    # Временный реквизит для превью (не сохраняется без SAVE).
    tools_dir = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")),
                             "assets", "models", "tools")
    bpy.ops.import_scene.gltf(filepath=os.path.join(tools_dir, "shovel_inhand.glb"))
    shovel = bpy.context.selected_objects[0]
    bpy.ops.import_scene.gltf(filepath=os.path.join(tools_dir, "bucket_inhand.glb"))
    bucket = bpy.context.selected_objects[0]
    bpy.ops.import_scene.gltf(filepath=os.path.join(tools_dir, "axe_inhand.glb"))
    axe = bpy.context.selected_objects[0]
    bpy.ops.import_scene.gltf(filepath=os.path.join(tools_dir, "pickaxe_inhand.glb"))
    pickaxe = bpy.context.selected_objects[0]
    for t in (shovel, bucket, axe, pickaxe):
        parent_tool_to_socket(arm, t)

    # Довороты уже запечены в inhand-GLB нормализацией — здесь identity.
    # (лопата (0,pi,0), ведро tilt; топор/кирка без доворотов)
    print("DIAG shovel euler:", tuple(round(v, 3) for v in shovel.rotation_euler))
    # ведро: минимальный доворот виса наружу от ноги (вычисляем из матрицы сокета).
    reset_pose(arm)
    bpy.context.view_layer.update()
    sock = arm.pose.bones['ToolSocket.R']
    M = arm.matrix_world @ sock.matrix
    hang_local = Vector((0, 0, -1))
    desired_world = Vector((0.55, -0.15, -0.82)).normalized()
    desired_local = (M.to_3x3().inverted() @ desired_world).normalized()
    print(f"socket hang world: {(M.to_3x3() @ hang_local).normalized().to_tuple(3)}")
    print("DIAG bucket euler:", tuple(round(v, 3) for v in bucket.rotation_euler))
    bpy.context.view_layer.update()

    setup_camera_ground()
    scene = bpy.context.scene

    camera = bpy.data.objects.get('IsoCamera')

    def frame_cam(loc, target, ortho=2.2):
        camera.location = Vector(loc)
        camera.data.ortho_scale = ortho
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()

    def render(action_name, frame, fname, show, cam=((2.7, -4.2, 2.4), (0, -0.12, 1.05), 2.65)):
        shovel.hide_render = shovel.hide_viewport = ('shovel' not in show)
        bucket.hide_render = bucket.hide_viewport = ('bucket' not in show)
        axe.hide_render = axe.hide_viewport = ('axe' not in show)
        pickaxe.hide_render = pickaxe.hide_viewport = ('pickaxe' not in show)
        arm.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        frame_cam(*cam)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT, fname)
        bpy.ops.render.render(write_still=True)
        print("rendered", fname)

    FRONT = ((0, -4.5, 1.5), (0, 0, 0.9), 2.2)
    SIDE = ((4.5, 0, 1.4), (0, 0, 0.9), 2.2)
    CLOSE_FRONT = ((0.1, -2.2, 1.1), (0.1, -0.3, 0.9), 1.1)
    CLOSE_SIDE = ((2.2, -0.3, 1.0), (0.0, -0.3, 0.9), 1.1)
    # Кадры: покой+лопата, контакт копания, покой+ведро, момент зачерпывания.
    render('idle', 1, 'rest_shovel.png', 'shovel')
    render('idle', 1, 'rest_shovel_front.png', 'shovel', FRONT)
    render('idle', 1, 'rest_shovel_side.png', 'shovel', SIDE)
    render('dig', 1 + round(0.45 * FPS), 'dig_contact.png', 'shovel')
    render('dig', 1 + round(0.45 * FPS), 'dig_contact_front.png', 'shovel', FRONT)
    render('dig', 1 + round(0.45 * FPS), 'dig_contact_close_front.png', 'shovel', CLOSE_FRONT)
    render('dig', 1 + round(0.45 * FPS), 'dig_contact_close_side.png', 'shovel', CLOSE_SIDE)
    # Диагностика: куда смотрят оси инструмента в кадре контакта.
    arm.animation_data.action = bpy.data.actions['dig']
    scene.frame_set(1 + round(0.45 * FPS))
    bpy.context.view_layer.update()
    sock = arm.pose.bones['ToolSocket.R']
    Mw = (arm.matrix_world @ sock.matrix).to_3x3()
    sh = shovel.matrix_world.to_3x3()
    print(f"DIAG socket+Z world: {(Mw @ Vector((0,0,1))).to_tuple(3)}")
    print(f"DIAG shovel tool -Z(blade) world: {(sh @ Vector((0,0,-1))).to_tuple(3)}")
    print(f"DIAG shovel tool +Y(scoop) world: {(sh @ Vector((0,1,0))).to_tuple(3)}")
    render('idle', 1, 'rest_bucket.png', 'bucket')
    render('idle', 1, 'rest_bucket_front.png', 'bucket', FRONT)
    render('scoop', 1 + round(0.55 * FPS), 'scoop_dip.png', 'bucket')
    render('idle', 1, 'rest_axe_front.png', 'axe', FRONT)
    render('idle', 1, 'rest_pickaxe_front.png', 'pickaxe', FRONT)

    if SAVE:
        for o in (shovel, bucket):
            bpy.data.objects.remove(o, do_unlink=True)
        if 'PreviewGround' in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects['PreviewGround'], do_unlink=True)
        reset_pose(arm)
        arm.animation_data.action = bpy.data.actions['idle']
        scene.frame_set(1)
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        bpy.ops.wm.save_as_mainfile(
            filepath=os.path.join(root, "assets", "models", "character", "stardew_farmer.blend"))
        char = bpy.data.objects['Farmer_Character']
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [arm, char, bpy.data.objects['Sun_Hat'], bpy.data.objects['Equipped_Pickaxe']]:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(root, "assets", "models", "character", "stardew_farmer.glb"),
            export_format='GLB', use_selection=True, export_apply=False,
            export_animations=True, export_animation_mode='ACTIONS',
            export_force_sampling=True, export_frame_range=False,
            export_skins=True, export_morph=False, export_lights=False, export_cameras=False)
        print("SAVED blend + exported glb with dig/scoop")
    else:
        print("PREVIEW ONLY (no save). Set SAVE=1 to write files.")


if __name__ == '__main__':
    main()
