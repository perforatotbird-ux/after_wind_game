"""Inspect library assets: bounds, orientation, materials, textures."""
import bpy
import os
from mathutils import Vector

FILES = {
    "axe": "C:/Users/inval/AppData/Local/Temp/opencode/fantasy/Exports/glTF/Axe_Bronze.gltf",
    "bucket": "C:/Users/inval/AppData/Local/Temp/opencode/fantasy/Exports/glTF/Bucket_Metal.gltf",
    "pickaxe": "C:/Users/inval/AppData/Local/Temp/opencode/fantasy/Exports/glTF/Pickaxe_Bronze.gltf",
    "shovel": "C:/Users/inval/AppData/Local/Temp/opencode/kenney/Models/GLB format/shovel.glb",
}


def reset():
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for col in [bpy.data.meshes, bpy.data.materials, bpy.data.images]:
        for b in list(col):
            try:
                col.remove(b, do_unlink=True)
            except Exception:
                pass


for tid, path in FILES.items():
    reset()
    if path.endswith('.gltf'):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    print(f"=== {tid} ({os.path.basename(path)}) ===")
    print(f"  objects: {[(o.name, o.type) for o in bpy.data.objects]}")
    allv = []
    for o in meshes:
        ws = o.matrix_world
        allv += [ws @ Vector(c) for c in o.bound_box]
    if allv:
        xs = [v.x for v in allv]
        ys = [v.y for v in allv]
        zs = [v.z for v in allv]
        print(f"  world bounds x:[{min(xs):.3f},{max(xs):.3f}] y:[{min(ys):.3f},{max(ys):.3f}] z:[{min(zs):.3f},{max(zs):.3f}]")
        print(f"  size: {max(xs)-min(xs):.3f} x {max(ys)-min(ys):.3f} x {max(zs)-min(zs):.3f}")
    for o in meshes:
        print(f"  mesh {o.name}: verts={len(o.data.vertices)} mats={[m.name if m else None for m in o.data.materials]} loc={tuple(round(v,3) for v in o.location)} rot={tuple(round(v,3) for v in o.rotation_euler)} scale={tuple(round(v,3) for v in o.scale)}")
    for m in bpy.data.materials:
        if m.use_nodes:
            imgs = [n.image.name if (n.type == 'TEX_IMAGE' and n.image) else None for n in m.node_tree.nodes]
            imgs = [i for i in imgs if i]
            print(f"  material {m.name}: images={imgs}")
print("INSPECT_DONE")
