"""Присланный исправный GLB -> repaired/ruined версии очистителя для Godot.
python tools/create_water_filter_model.py SOURCE.glb OUT_DIR [--render]
Требуется bpy (проверено 5.1.2). UV/материал сохраняются, ~32k треугольников,
высота 2.15 м. Руины — разломанная колонна и снятая крышка исходной модели,
сорванный верх трубы, обломки обода, тёмная фильтрующая засыпка, ржавые края.
Затем tools/import_water_filter_model.gd сохраняет текстовые ресурсы Godot.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix
SRC, OUT = sys.argv[1:3]; os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(SRC))
o=next(o for o in bpy.context.scene.objects if o.type=='MESH')
bpy.context.view_layer.objects.active=o;o.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
o.rotation_euler=(math.pi/2,0,math.pi)
bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
low=min(v.co.z for v in o.data.vertices); height=max(v.co.z for v in o.data.vertices)-low
factor=2.15/height
for v in o.data.vertices:
 v.co.z-=low;v.co*=factor
# Center the plinth, not the pipe that overhangs it.
base=[v.co for v in o.data.vertices if v.co.z<.16]
cx=(min(v.x for v in base)+max(v.x for v in base))/2
cy=(min(v.y for v in base)+max(v.y for v in base))/2
for v in o.data.vertices:v.co.x-=cx;v.co.y-=cy
bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000025);bm.to_mesh(o.data);bm.free()
o.data.calc_loop_triangles();orig=len(o.data.loop_triangles)
mod=o.modifiers.new('GameLOD','DECIMATE');mod.ratio=32000/orig
bpy.ops.object.modifier_apply(modifier=mod.name)
for p in o.data.polygons:p.use_smooth=True
o.name='FilterRepaired'
mat=o.data.materials[0];mat.name='FilterOriginalPBR'
# Keep original image channels/UV, avoid runtime multi-megabyte PNGs.
for im in bpy.data.images:
 if im.type=='IMAGE' and im.size[0]>0:
  size=2048 if 'normal' not in im.name and 'metallic' not in im.name else 1024
  im.scale(size,size)
def select(objects):
 bpy.ops.object.select_all(action='DESELECT')
 for ob in objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=objects[0]
def export(objects,state):
 select(objects)
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'filter_'+state+'.gltf'),export_format='GLTF_SEPARATE',
  use_selection=True,export_animations=False,export_yup=True,export_vertex_color='ACTIVE')
 for ob in objects:ob.data.calc_loop_triangles()
 print(state,'triangles',sum(len(ob.data.loop_triangles) for ob in objects),flush=True)
export([o],'repaired')
# Add a spatial vertex patina to the damaged variant, without altering the intact material.
damaged=mat.copy();damaged.name='FilterDamagedPBR'
bs=damaged.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.94
# Color attribute multiplied by original albedo. Repaired mesh has no patina.
nodes=damaged.node_tree.nodes;links=damaged.node_tree.links
src=bs.inputs['Base Color'].links[0].from_socket
vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='DamagePatina'
mul=nodes.new('ShaderNodeMixRGB');mul.blend_type='MULTIPLY';mul.inputs[0].default_value=1
links.new(src,mul.inputs[1]);links.new(vc.outputs['Color'],mul.inputs[2]);links.new(mul.outputs[0],bs.inputs['Base Color'])
# Exporter cannot bake arbitrary node multiplication; export vertex color separately,
# Godot enables vertex_color_use_as_albedo on this material during import.
links.new(src,bs.inputs['Base Color'])

def part(name,zmin,zmax):
 ob=bpy.data.objects.new(name,o.data.copy());bpy.context.collection.objects.link(ob)
 bm=bmesh.new();bm.from_mesh(ob.data)
 for z,lower in [(zmin,True),(zmax,False)]:
  if z is None:continue
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-5,
    plane_co=(0,0,z),plane_no=(0,0,1),clear_inner=lower,clear_outer=not lower)
 # Jagged tearing at the severed plane; UVs remain attached to original polygons.
 for v in bm.verts:
  for cut in [zmin,zmax]:
   if cut is not None and abs(v.co.z-cut)<.002:
    a=math.atan2(v.co.y,v.co.x)
    v.co.z+=.022*math.sin(a*13)+.012*math.sin(a*29)
 bm.to_mesh(ob.data);bm.free()
 ob.data.materials.clear();ob.data.materials.append(damaged)
 colors=ob.data.color_attributes.new(name='DamagePatina',type='FLOAT_COLOR',domain='POINT')
 for v in ob.data.vertices:
  x,y,z=v.co
  stain=.5+.5*math.sin(x*15+y*11+z*8)*math.sin(x*23-y*9)
  edge=min([abs(z-cut) for cut in [zmin,zmax] if cut is not None]+[1.])
  rust=max(0,1-edge/.12)*.55
  colors.data[v.index].color=(.63+stain*.14,.58+stain*.12-rust*.2,.49+stain*.1-rust*.24,1)
 return ob
lower=part('FilterBrokenBase',None,1.06)
column=part('FilterCollapsedColumn',1.12,1.84)
lid=part('FilterFallenLid',1.84,None)
# Tilt the fractured upper column sideways from its base, leaving the crack visible.
pivot=Vector((0,0,1.12));R=Matrix.Rotation(math.radians(-28),4,'Y') @ Matrix.Rotation(math.radians(8),4,'Z')
for v in column.data.vertices:v.co=R.to_3x3()@(v.co-pivot)+pivot+Vector((-.18,.06,-.10))
# Cap and elbow pipe are detached and lie on the front corner of the plinth.
coords=[v.co.copy() for v in lid.data.vertices];c=sum(coords,Vector())/len(coords)
R=Matrix.Rotation(math.radians(76),4,'X') @ Matrix.Rotation(math.radians(-20),4,'Z')
for v in lid.data.vertices:v.co=R.to_3x3()@(v.co-c)
lo=min(v.co.z for v in lid.data.vertices)
for v in lid.data.vertices:v.co+=Vector((.50,-.48,.18-lo))
# Original ring between fractured sections is divided into four actual metal shards.
shards=[]
for k in range(4):
 ob=part('FilterRingShard%d'%k,1.06,1.12)
 bm=bmesh.new();bm.from_mesh(ob.data)
 bad=[]
 for f in bm.faces:
  co=f.calc_center_median();sector=int((math.atan2(co.y,co.x)+math.pi)/(math.pi/2))%4
  if sector!=k:bad.append(f)
 bmesh.ops.delete(bm,geom=bad,context='FACES')
 bm.to_mesh(ob.data);bm.free()
 if not ob.data.polygons:bpy.data.objects.remove(ob,do_unlink=True);continue
 c=sum((v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
 R=Matrix.Rotation(math.radians(58+k*13),4,'Y')
 for v in ob.data.vertices:v.co=R.to_3x3()@(v.co-c)
 lo=min(v.co.z for v in ob.data.vertices)
 for v in ob.data.vertices:v.co+=Vector((-.7+k*.42,-.62,.18-lo))
 shards.append(ob)
# Dark interior: failed sand/charcoal bed visible where the upper column has broken off.
def plain(name,color,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.97;bs.inputs['Metallic'].default_value=metal
 return m
fill=plain('FilterFailedMedia',(.16,.115,.075))
rust=plain('FilterRustRim',(.23,.105,.045),.3)
# The original tank is centered slightly behind the plinth center.
bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.38,depth=.075,location=(0,0,1.01))
media=bpy.context.object;media.name='FilterFailedMedia';media.data.materials.append(fill)
# A thin, irregular severed ring gives the cut tank wall visible thickness.
bpy.ops.mesh.primitive_torus_add(major_radius=.40,minor_radius=.022,major_segments=40,minor_segments=6,location=(0,0,1.055))
rim=bpy.context.object;rim.name='FilterTornRim';rim.data.materials.append(rust)
for v in rim.data.vertices:v.co.z+=.018*math.sin(math.atan2(v.co.y,v.co.x)*13)
ruins=[lower,column,lid,*shards,media,rim]
# Ensure derived debris stays on or immediately beside the same foundation.
for ob in ruins:
 for v in ob.data.vertices:
  world=ob.matrix_world@v.co
  if world.z<.005:v.co.z+=.005-world.z
export(ruins,'ruined')
# Keep render sources for visual QA; no .blend is needed by the game.
for ob in ruins:ob.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'filter_build.blend'))
if '--render' in sys.argv:
 sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=16
 sc.render.resolution_x=700;sc.render.resolution_y=700;sc.render.resolution_percentage=100
 sc.world=bpy.data.worlds.new('World');sc.world.color=(.25,.25,.25)
 bpy.ops.object.camera_add(location=(3.2,-5,3.2));cam=bpy.context.object
 cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=3.2;sc.camera=cam
 for loc,power in [((2,-4,5),700),((-3,-1,4),450),((0,4,5),600)]:
  bpy.ops.object.light_add(type='AREA',location=loc);l=bpy.context.object;l.data.energy=power;l.data.size=4;l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object;floor.data.materials.append(plain('Floor',(.07,.085,.09)))
 for state in ['repaired','ruined']:
  o.hide_render=state=='ruined'
  for ob in ruins:ob.hide_render=state=='repaired'
  # Restore patina shader for Blender preview; Godot uses exported vertex colors.
  if state=='ruined':links.new(mul.outputs[0],damaged.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
  sc.render.filepath=os.path.join(OUT,'preview_'+state+'.png');bpy.ops.render.render(write_still=True)
