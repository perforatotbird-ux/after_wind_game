"""Decisive facing test: where does the pickaxe tip go at mine contact?"""
import bpy
from mathutils import Vector

arm = bpy.data.objects['FarmerRig']
arm.animation_data.action = bpy.data.actions.get('mine')
bpy.context.scene.frame_set(10)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
tool = bpy.data.objects['Equipped_Pickaxe']
ev = tool.evaluated_get(dg)
mesh = ev.to_mesh()
ws = [tool.matrix_world @ v.co for v in mesh.vertices]
ev.to_mesh_clear()
cx = sum(ws, Vector()) / len(ws)
hips = arm.matrix_world @ arm.data.bones['Hips'].head_local
print('TIP_CENTER:', tuple(round(v, 2) for v in cx))
print('HIPS:', tuple(round(v, 2) for v in hips))
print('DIR:', tuple(round(v, 2) for v in (cx - hips)))
