"""Inspect UAL rig + render contact sheets for candidate clips."""
import bpy
import os
from mathutils import Vector

GLB = ("C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/"
       "Godot/AnimationLibrary_Godot_Standard.glb")
OUT = "K:/After Wind/outputs/ual_preview"
os.makedirs(OUT, exist_ok=True)

bpy.ops.import_scene.gltf(filepath=GLB)
# В GLB затесался дефолтный мусор сцены (Cube, Icosphere, Camera, Light) — сносим.
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
print("ARMATURES:", [(a.name, len(a.data.bones)) for a in arms])
arm = arms[0]
print("BONES:", [b.name for b in arm.data.bones])
# Рост и ракурс
bps = arm.data.bones
heads = [arm.matrix_world @ b.head_local for b in bps]
print(f"height: {max(v.z for v in heads):.2f}")
print(f"hips/feet: {[(b.name, tuple(round(v,2) for v in (arm.matrix_world @ b.head_local))) for b in bps if 'hips' in b.name or 'foot' in b.name]}")

# Камера и свет для контакт-листов
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 640
scene.render.resolution_y = 400
scene.render.film_transparent = False
try:
    scene.world.color = (0.05, 0.05, 0.06)
except Exception:
    pass
cam_data = bpy.data.cameras.new("UALCam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.4
cam = bpy.data.objects.new("UALCam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = Vector((0, -4.5, 1.5))
cam.rotation_euler = (Vector((0, 0, 0.9)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam
sun = bpy.data.lights.new("UALSun", type='SUN')
sun.energy = 3.0
sun_obj = bpy.data.objects.new("UALSun", sun)
bpy.context.collection.objects.link(sun_obj)
sun_obj.rotation_euler = (0.7, 0.1, -0.6)
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, -0.005))
plane = bpy.context.object
mat = bpy.data.materials.new('UALGround')
mat.diffuse_color = (0.07, 0.08, 0.1, 1)
plane.data.materials.append(mat)

CANDIDATES = {
    "Fixing_Kneeling": [1, 31, 62, 93, 124],
    "PickUp_Table": [1, 7, 13, 20],
    "Interact": [1, 12, 24, 36, 48],
}
arm.animation_data.action = None
for clip, frames in CANDIDATES.items():
    action = bpy.data.actions.get(clip)
    if action is None:
        print(f"MISSING {clip}")
        continue
    arm.animation_data.action = action
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT, f"{clip}_{f:03d}.png")
        bpy.ops.render.render(write_still=True)
    print(f"sheet {clip} done")
print("UAL_INSPECT_DONE")
