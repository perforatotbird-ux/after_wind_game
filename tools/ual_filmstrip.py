"""Render Fixing_Kneeling filmstrip to find the work cycle."""
import bpy
import os
from mathutils import Vector

GLB = ("C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/"
       "Godot/AnimationLibrary_Godot_Standard.glb")
OUT = "K:/After Wind/outputs/ual_preview"

bpy.ops.import_scene.gltf(filepath=GLB)
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 320
sc.render.resolution_y = 200
sc.render.film_transparent = False
cam_data = bpy.data.cameras.new('FKCam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.4
cam = bpy.data.objects.new('FKCam', cam_data)
bpy.context.collection.objects.link(cam)
cam.location = Vector((0, -4.5, 1.5))
cam.rotation_euler = (Vector((0, 0, 0.9)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
sun = bpy.data.lights.new('FKSun', type='SUN')
sun.energy = 3.0
sun_obj = bpy.data.objects.new('FKSun', sun)
bpy.context.collection.objects.link(sun_obj)

arm.animation_data.action = bpy.data.actions.get('Fixing_Kneeling')
for f in (1, 13, 25, 37, 49, 61, 73, 85, 97, 109, 121):
    sc.frame_set(f)
    bpy.context.view_layer.update()
    sc.render.filepath = os.path.join(OUT, f"fk_{f:03d}.png")
    bpy.ops.render.render(write_still=True)
print("FK_STRIP_DONE")
