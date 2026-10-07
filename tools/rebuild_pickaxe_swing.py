"""Rebuild only the farming hero's rig weights and mining action, preserving art.
Run with Blender --background stardew_farmer.blend --python this_file -- --render.
The same build_mining_action() is used by the character generator.
"""
import bpy
import math
import json
import sys
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT = Path(__file__).resolve().parents[1]
FPS = 60
DURATION = 0.42
CONTACT = 0.15


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = 'QUATERNION'


def reweight_character(obj, arm):
    # This character is assembled from disconnected primitives. Assign by
    # anatomical component, not individual vertex height: the old heuristic
    # split trousers/torso/gloves across unrelated arms and legs.
    adjacency = [[] for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    unseen = set(range(len(adjacency)))
    while unseen:
        stack = [unseen.pop()]
        component = []
        while stack:
            i = stack.pop()
            component.append(i)
            for j in adjacency[i]:
                if j in unseen:
                    unseen.remove(j)
                    stack.append(j)
        center = sum((obj.data.vertices[i].co for i in component), Vector()) / len(component)
        x, y, z = center
        side = 'R' if x >= 0 else 'L'
        if z > 1.53:
            name = 'Head'
        elif z > 1.45:
            name = 'Neck'
        elif abs(x) > 0.27 and z > 0.65:
            name = ('UpperArm.' if z > 1.08 else 'Forearm.' if z > 0.84 else 'Hand.') + side
        elif z > 1.17:
            name = 'Chest'
        elif z > 0.96:
            name = 'Spine'
        elif z > 0.73:
            name = 'Hips'
        elif z > 0.41:
            name = 'Thigh.' + side
        elif z > 0.13:
            name = 'Shin.' + side
        else:
            name = 'Foot.' + side
        groups[name].add(component, 1.0, 'REPLACE')


def aim_bone(arm, name, head, tail):
    bone = arm.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    direction = (tail - head).normalized()
    rotate = (rest @ Vector((0, 1, 0))).rotation_difference(direction)
    bone.matrix = Matrix.Translation(head) @ (rotate.to_matrix() @ rest).to_4x4()
    bpy.context.view_layer.update()


def solve_arm(arm, side, grip, tool_rotation):
    # Analytic two-bone IK, baked to FK for portable glTF (no live constraints).
    hand_name = 'Hand.' + side
    hand = arm.pose.bones[hand_name]
    hand_rest = hand.bone.matrix_local
    grip_rest = Vector((0.35 if side == 'R' else -0.35, -0.02, 0.76))
    wrist = grip - tool_rotation @ (grip_rest - hand_rest.translation)
    upper = arm.pose.bones['UpperArm.' + side]
    lower = arm.pose.bones['Forearm.' + side]
    shoulder = upper.head.copy()
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


def build_mining_action(arm):
    data = arm.animation_data_create()
    data.action = None
    data.use_nla = False
    for track in list(data.nla_tracks):
        if track.name == 'mine':
            data.nla_tracks.remove(track)
    old = bpy.data.actions.get('mine')
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new('mine')
    action.use_fake_user = True
    data.action = action
    bpy.context.scene.render.fps = FPS
    # t, grip xyz, shaft pitch, torso pitch. No hips or leg movement.
    # Immediate readable pose, 83ms lift, contact at 150ms, short recovery.
    poses = [
        (0.000, (0.10, -0.28, 1.29), -1.55, 0.015),
        (0.050, (0.10, -0.23, 1.53), -2.42, 0.020),
        (0.083333, (0.10, -0.23, 1.62), -2.65, 0.025),
        (0.116667, (0.10, -0.40, 1.33), -1.40, 0.060),
        (0.150, (0.10, -0.43, 1.13), -0.55, 0.095),
        (0.183333, (0.10, -0.43, 1.12), -0.52, 0.095),
        (0.250, (0.10, -0.36, 1.22), -0.80, 0.055),
        (0.333333, (0.10, -0.28, 1.28), -1.35, 0.020),
        (0.416667, (0.10, -0.28, 1.29), -1.55, 0.015),
    ]
    previous_quaternions = {}
    for t, position, pitch, torso in poses:
        frame = 1 + round(t * FPS)
        reset_pose(arm)
        # Feet stay invariant because the pelvis and lower limbs stay neutral;
        # upper-body weight is conveyed by spine/chest, not by dragging legs.
        for name, amount in [('Spine', torso * 0.4), ('Chest', torso * 0.6)]:
            bone = arm.pose.bones[name]
            bone.rotation_quaternion = Quaternion((1, 0, 0), amount)
        bpy.context.view_layer.update()
        rotation = Matrix.Rotation(pitch, 3, 'X')
        grip = Vector(position)
        solve_arm(arm, 'R', grip, rotation)
        # The supporting left palm is on the same shaft, toward the pommel.
        solve_arm(arm, 'L', grip + rotation @ Vector((0, 0, 0.10)), rotation)
        for bone in arm.pose.bones:
            # q and -q are equivalent poses but interpolate through a flip in
            # Blender's component F-curves. Keep the same quaternion hemisphere.
            q = bone.rotation_quaternion.copy()
            if bone.name in previous_quaternions and q.dot(previous_quaternions[bone.name]) < 0:
                q.negate()
                bone.rotation_quaternion = q
            previous_quaternions[bone.name] = q.copy()
            bone.keyframe_insert('location', frame=frame)
            bone.keyframe_insert('rotation_quaternion', frame=frame)
            bone.keyframe_insert('scale', frame=frame)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    action['contact_seconds'] = CONTACT
    action['purpose'] = 'Responsive two-hand pickaxe; planted feet; no root motion'
    return action


def patch_and_export():
    arm = bpy.data.objects['FarmerRig']
    reweight_character(bpy.data.objects['Farmer_Character'], arm)
    # Prevent motion from previous actions leaking into unkeyed bones.
    # Preserve original idle/walk/run timing despite raising export FPS.
    old_fps = bpy.context.scene.render.fps
    arm.animation_data.use_nla = False
    arm.animation_data.action = None
    for name in ['idle', 'walk', 'run']:
        action = bpy.data.actions[name]
        if action.get('quaternion_baked', False):
            continue
        reset_pose(arm)
        for bone in arm.pose.bones:
            bone.rotation_mode = 'XYZ'
        arm.animation_data.action = action
        start, end = action.frame_range
        frames = round((end-start) * FPS / old_fps)
        samples = []
        for index in range(frames+1):
            scene = bpy.context.scene
            scene.frame_set(int(start + index * old_fps / FPS), subframe=(start + index * old_fps / FPS) % 1)
            bpy.context.view_layer.update()
            samples.append({bone.name: bone.matrix_basis.copy() for bone in arm.pose.bones})
        arm.animation_data.action = None
        for track in list(arm.animation_data.nla_tracks):
            if any(strip.action == action for strip in track.strips):
                arm.animation_data.nla_tracks.remove(track)
        bpy.data.actions.remove(action)
        baked = bpy.data.actions.new(name)
        baked.use_fake_user = True
        baked['quaternion_baked'] = True
        arm.animation_data.action = baked
        reset_pose(arm)
        previous = {}
        for index, sample in enumerate(samples):
            for bone in arm.pose.bones:
                bone.matrix_basis = sample[bone.name]
                q = bone.rotation_quaternion.copy()
                if bone.name in previous and q.dot(previous[bone.name]) < 0:
                    q.negate()
                    bone.rotation_quaternion = q
                previous[bone.name] = q.copy()
                for prop in ['location', 'rotation_quaternion', 'scale']:
                    bone.keyframe_insert(prop, frame=index+1)
    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)
    action = build_mining_action(arm)
    arm.animation_data.action = action
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 26
    bpy.context.scene.frame_set(1)
    # Baseline feet measured on evaluated skinned vertices, not just bones.
    char = bpy.data.objects['Farmer_Character']
    foot_indices = [v.index for v in char.data.vertices if v.co.z < 0.13]
    initial = None
    drift = 0.0
    samples = []
    tip_rest = Vector((0.36, -0.36, 0.24))
    rest_inverse = arm.data.bones['Hand.R'].matrix_local.inverted()
    for frame in range(1, 27):
        bpy.context.scene.frame_set(frame)
        evaluated = char.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        feet = [mesh.vertices[i].co.copy() for i in foot_indices]
        if initial is None:
            initial = feet
        drift = max(drift, max((a-b).length for a, b in zip(feet, initial)))
        evaluated.to_mesh_clear()
        tip = arm.pose.bones['Hand.R'].matrix @ rest_inverse @ tip_rest
        samples.append({'t': (frame-1)/FPS, 'tip': list(tip)})
    out = ROOT / 'outputs' / 'pickaxe_swing'
    (out / 'rig_metrics.json').write_text(json.dumps({'duration': 25/FPS, 'contact': CONTACT, 'max_foot_vertex_drift_m': drift, 'samples': samples}, indent=2))
    if drift > 0.002:
        raise RuntimeError(f'Feet drift: {drift}')
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'assets/models/character/stardew_farmer.blend'))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm, char, bpy.data.objects['Sun_Hat'], bpy.data.objects['Equipped_Pickaxe']]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=str(ROOT / 'assets/models/character/stardew_farmer.glb'),
        export_format='GLB', use_selection=True, export_apply=False,
        export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False,
        export_skins=True, export_morph=False, export_lights=False, export_cameras=False)
    print('SWING_METRICS', json.dumps({'foot_drift_m': drift, 'duration': 25/FPS, 'contact': CONTACT}))
    if '--render' in sys.argv:
        render_preview(arm, out)


def render_preview(arm, out):
    scene = bpy.context.scene
    arm.animation_data.use_nla = False
    arm.animation_data.action = bpy.data.actions['mine']
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 560
    scene.render.resolution_y = 560
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.world.color = (0.045, 0.045, 0.055)
    scene.view_settings.view_transform = 'AgX'
    camera = bpy.data.objects['IsoCamera']
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.65
    camera.location = (2.7, -4.2, 2.4)
    camera.rotation_euler = (Vector((0, -0.12, 1.05)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.005))
    plane = bpy.context.object
    mat = bpy.data.materials.new('PreviewGround')
    mat.diffuse_color = (0.065, 0.075, 0.09, 1)
    plane.data.materials.append(mat)
    for frame in range(1, 27):
        scene.frame_set(frame)
        scene.render.filepath = str(out / f'swing_{frame:02d}.png')
        bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    patch_and_export()
