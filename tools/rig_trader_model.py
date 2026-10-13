"""Странствующий торговец: статичный GLB -> облегчённый skinned GLB.
Запуск: python tools/rig_trader_model.py SOURCE.glb OUT_DIR (требуется bpy).
Сохраняет UV/материал, сваривает швы, ~26k треугольников, рост 1.8 м.
17 костей; idle, greet, talk, walk (на месте). Рюкзак закреплён на груди,
шапка/борода на голове; полы плаща на тазе. Исходник не изменяется.
Затем tools/import_trader_model.gd сохраняет текстовые игровые ресурсы.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Quaternion
SRC, OUT = sys.argv[1:3]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(SRC))
o = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = o
o.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Input is Y-up even after Blender import; convert to Z-up, face -Y.
o.rotation_euler = (math.pi / 2, 0, math.pi)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
lo = min(v.co.z for v in o.data.vertices)
height = max(v.co.z for v in o.data.vertices) - lo
scale = 1.8 / height
for v in o.data.vertices:
    v.co.z -= lo
    v.co *= scale
bm = bmesh.new(); bm.from_mesh(o.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00002)
bm.to_mesh(o.data); bm.free()
o.data.calc_loop_triangles(); original = len(o.data.loop_triangles)
mod = o.modifiers.new('GameLOD', 'DECIMATE'); mod.ratio = min(1, 26000 / original)
bpy.ops.object.modifier_apply(modifier=mod.name)
o.data.calc_loop_triangles(); print('Triangles', original, '->', len(o.data.loop_triangles), flush=True)
for p in o.data.polygons: p.use_smooth = True
o.name = 'TraderBody'
# Landmarks in source-height fractions (Z); front is -Y.
s = scale
J = {
 'Pelvis': ((0,0,.44), (0,0,.53), None),
 'Spine': ((0,0,.53), (0,0,.65), 'Pelvis'),
 'Chest': ((0,0,.65), (0,0,.78), 'Spine'),
 'Neck': ((0,0,.78), (0,0,.88), 'Chest'),
 'Head': ((0,0,.88), (0,0,1.06), 'Neck'),
}
for side, sign in [('R',1), ('L',-1)]:
 J.update({
  'UpperArm.'+side: ((sign*.16,0,.77),(sign*.235,0,.59),'Chest'),
  'Forearm.'+side: ((sign*.235,0,.59),(sign*.25,-.025,.46),'UpperArm.'+side),
  'Hand.'+side: ((sign*.25,-.025,.46),(sign*.25,-.025,.39),'Forearm.'+side),
  'Thigh.'+side: ((sign*.085,0,.43),(sign*.105,0,.21),'Pelvis'),
  'Calf.'+side: ((sign*.105,0,.21),(sign*.12,0,.07),'Thigh.'+side),
  'Foot.'+side: ((sign*.12,0,.07),(sign*.12,-.10,.025),'Calf.'+side),
 })
arm_data = bpy.data.armatures.new('TraderSkeleton')
arm = bpy.data.objects.new('TraderRig', arm_data); bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for name,(a,b,parent) in J.items():
 bone=arm_data.edit_bones.new(name); bone.head=Vector(a)*s;bone.tail=Vector(b)*s
 if parent: bone.parent=arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
groups={n:o.vertex_groups.new(name=n) for n in J}
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def blend(a,b,t):return {a:1-t,b:t}
for v in o.data.vertices:
 x,y,z=v.co/s; ax=abs(x); side='R' if x>0 else 'L'
 # Rigid accessories behind shoulders and on the belt do not follow arms.
 if z>.86: w={'Head':1}
 elif z>.78: w=blend('Chest','Head',smooth(.79,.87,z))
 elif ax>.175 and y<.10 and .36<z<.78:
  if z>.61: w=blend('UpperArm.'+side,'Chest',smooth(.71,.78,z))
  elif z>.51: w=blend('Forearm.'+side,'UpperArm.'+side,smooth(.54,.62,z))
  else: w=blend('Hand.'+side,'Forearm.'+side,smooth(.44,.51,z))
 elif z>.49 or (y>.09 and z>.38):
  if z>.64:w={'Chest':1}
  else:w=blend('Pelvis','Chest',smooth(.49,.65,z))
 elif z>.23:
  # Pants follow thighs; the outer coat follows pelvis, blended across the hem.
  pinned=max(smooth(.115,.175,ax),smooth(.37,.46,z))
  w=blend('Thigh.'+side,'Pelvis',pinned)
 elif z>.17:w=blend('Calf.'+side,'Thigh.'+side,smooth(.17,.23,z))
 else:w=blend('Foot.'+side,'Calf.'+side,smooth(.065,.16,z))
 for name,weight in w.items():
  if weight>0:groups[name].add([v.index],weight,'REPLACE')
mod=o.modifiers.new('TraderSkeleton','ARMATURE');mod.object=arm
o.parent=arm
# One action per animation, quaternion tracks, mild gestures for heavy equipment.
arm.animation_data_create()
def rotation(pb,axis,angle):
 local=pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
 return Quaternion(local,angle)
def pose(name,t):
 motion={}
 def rot(b,ax,angle):motion[b]=(ax,angle)
 if name=='idle':
  phase=2*math.pi*t/4
  rot('Spine',(1,0,0),.015*math.sin(phase));rot('Chest',(1,0,0),.018*math.sin(phase))
  rot('Head',(0,0,1),.06*math.sin(phase))
  for side,sign in [('R',1),('L',-1)]:rot('Forearm.'+side,(1,0,0),.025*math.sin(phase+sign*.6))
 elif name=='greet':
  envelope=math.sin(math.pi*t/2.4)**2
  rot('UpperArm.R',(0,1,0),-.26*envelope)
  rot('Forearm.R',(1,0,0),-1.0*envelope)
  rot('Hand.R',(0,1,0),.18*math.sin(t*math.pi*5)*envelope)
  rot('Head',(1,0,0),.08*envelope)
 elif name=='talk':
  envelope=math.sin(math.pi*t/3.2)**2
  rot('Head',(1,0,0),.07*math.sin(t*math.pi*2)*envelope)
  rot('Forearm.L',(1,0,0),-.34*envelope)
  rot('Hand.L',(0,1,0),-.12*math.sin(t*math.pi)*envelope)
  rot('Chest',(0,0,1),.025*math.sin(t*math.pi)*envelope)
 elif name=='walk':
  phase=t*2*math.pi/1.2
  for side,sign in [('R',1),('L',-1)]:
   a=phase+(0 if sign==1 else math.pi)
   rot('Thigh.'+side,(1,0,0),.28*math.sin(a))
   rot('Calf.'+side,(1,0,0),.22*max(0,-math.sin(a)))
   rot('UpperArm.'+side,(1,0,0),-.12*math.sin(a))
  rot('Chest',(0,1,0),.025*math.sin(phase))
 for pb in arm.pose.bones:
  pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion((1,0,0,0))
  if pb.name in motion:
   ax,angle=motion[pb.name];pb.rotation_quaternion=rotation(pb,ax,angle)
  pb.keyframe_insert('rotation_quaternion',frame=round(t*30))
for name,length in [('idle',4.0),('greet',2.4),('talk',3.2),('walk',1.2)]:
 act=bpy.data.actions.new(name);arm.animation_data.action=act
 for i in range(round(length*30)+1):pose(name,i/30)
 track=arm.animation_data.nla_tracks.new();track.name=name
 strip=track.strips.new(name,0,act);strip.action_frame_end=round(length*30)
arm.animation_data.action=None
for track in arm.animation_data.nla_tracks: track.mute=True
for pb in arm.pose.bones:pb.rotation_quaternion=Quaternion((1,0,0,0))
bpy.context.scene.render.fps=30
# Resize embedded images, export as GLTF_SEPARATE to feed Godot conversion.
for im in bpy.data.images:
 if im.type=='IMAGE' and im.size[0]>0:
  im.scale(2048 if 'normal' not in im.name and 'metallic' not in im.name else 1024,
           2048 if 'normal' not in im.name and 'metallic' not in im.name else 1024)
for track in arm.animation_data.nla_tracks:track.mute=False
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'trader_rigged.gltf'),export_format='GLTF_SEPARATE',
 export_animations=True,export_animation_mode='NLA_TRACKS',export_skins=True,export_yup=True,
 export_force_sampling=True,export_apply=False)
print('RIG EXPORT OK',flush=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'trader_rigged.blend'))
