"""Костёр по campfire_multi.jpg: каменное кольцо, поленья шалашом, щепа и угли.
python tools/create_campfire_model.py OUT_DIR [--render]
Требуется bpy 5.1.2; результат GLTF + текстуры, импорт tools/import_campfire_model.gd.
Огонь/дым/искры и обугливание добавляются игровым CampfireVisual, не запекаются в геометрию.
"""
import bpy,math,random,os,sys
import numpy as np
from PIL import Image,ImageFilter
from mathutils import Vector
OUT=os.path.abspath(sys.argv[1]);os.makedirs(OUT,exist_ok=True);random.seed(64)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng=np.random.default_rng(64)
def noise(n,w,h):
 a=rng.random((n,n))*255
 return np.asarray(Image.fromarray(a.astype('uint8')).resize((w,h),Image.Resampling.BICUBIC),dtype=float)/255

def texture(name,a):
 p=os.path.join(OUT,name+'.png');Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(p)
 im=bpy.data.images.load(p);return im
W=512;H=1024;y,x=np.mgrid[0:H,0:W];u=x/W;v=y/H
warp=u+.003*np.sin(v*13)+.002*np.sin(v*39+u*9)
grain=np.sin(warp*166+noise(8,W,H)*2)*.045+np.sin(warp*370+v*7)*.018
broad=noise(12,W,H)*.14+noise(65,W,H)*.025
base=np.array([.57,.38,.205]);wood=base[None,None,:]*(.82+broad[...,None]+grain[...,None])
# Broad painted bark ribbons and highlights, rather than photographic random speckles.
wood+=np.clip(np.sin(warp*85+1)*.05,0,.05)[...,None]*np.array([1,.85,.5])
wood_im=texture('campfire_wood',wood)
S=256;yy,xx=np.mgrid[0:S,0:S];dx=(xx/S-.5)*2;dy=(yy/S-.5)*2
rad=np.sqrt(dx*dx+dy*dy);ang=np.arctan2(dy,dx)
rings=.16*np.sin((rad+.018*np.sin(ang*5))*48)
cap=np.array([.72,.53,.31])[None,None,:]*(.95+rings[...,None])
cap*=1-.13*np.clip((rad-.8)/.2,0,1)[...,None]
cap_im=texture('campfire_endgrain',cap)
S=512;n=noise(8,S,S)*.12+noise(27,S,S)*.055+noise(120,S,S)*.015
stone_im=texture('campfire_stone',np.array([.29,.275,.24])[None,None,:]+n[...,None])
yy,xx=np.mgrid[0:S,0:S];r=np.sqrt(((xx/S-.5)*2)**2+((yy/S-.5)*2)**2)
a=noise(12,S,S)*.10+noise(80,S,S)*.05
soil=np.array([.27,.205,.14])[None,None,:]+a[...,None]
ash=np.array([.145,.135,.12])[None,None,:]+a[...,None]*.40
f=np.clip((r-.25)/.60,0,1)[...,None]
soil=ash*(1-f)+soil*f;soil_im=texture('campfire_soil',soil)
# A sparse crack mask for incandescent charcoal and dark charred timber.
yy,xx=np.mgrid[0:S,0:S];coords=np.stack((xx/S,yy/S),axis=-1);best=np.ones((S,S))*9;second=best.copy()
for pt in rng.random((65,2)):
 dist=np.sqrt(((coords-pt)**2).sum(axis=-1))
 second=np.minimum(second,np.maximum(best,dist));best=np.minimum(best,dist)
crack=np.clip(1-(second-best)/.006,0,1)
texture('campfire_cracks',np.repeat(crack[...,None],3,axis=-1))

def material(name,image,color=(1,1,1)):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF']
 b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=.94
 if image:
  node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
  m.node_tree.links.new(node.outputs['Color'],b.inputs['Base Color'])
 return m
wood_m=material('CampfireWood',wood_im);cap_m=material('CampfireEndgrain',cap_im)
stone_m=material('CampfireStone',stone_im);soil_m=material('CampfireSoil',soil_im)
coal_m=material('CampfireCharcoal',None,(.045,.038,.032))
parts={k:[] for k in ['StoneRing','Logs','Kindling','GroundBed','Charcoal']}

def mesh(name,verts,faces,uvs,mats,idx=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
 for m in mats:me.materials.append(m)
 uv=me.uv_layers.new(name='UVMap')
 for i,p in enumerate(me.polygons):
  if idx:p.material_index=idx[i]
  for li,co in zip(p.loop_indices,uvs[i]):uv.data[li].uv=co
 return ob

def log(name,a,b,radius,kind=False):
 a=Vector(a);b=Vector(b);direction=(b-a).normalized();rotation=Vector((0,0,1)).rotation_difference(direction).to_matrix()
 segments=10 if not kind else 7;steps=9 if not kind else 4
 verts=[];faces=[];uvs=[];indices=[];phase=random.uniform(0,6.28)
 for j in range(steps+1):
  t=j/steps
  for i in range(segments+1):
   angle=2*math.pi*i/segments
   r=radius*(1-.14*t+.045*math.sin(angle*3+phase)+.026*math.sin(t*12+angle*4))
   # Shallow longitudinal bark flutes are modeled, so they catch the fire light.
   vec=Vector((r*math.cos(angle)+.012*math.sin(t*4+phase),r*math.sin(angle),t*(b-a).length))
   verts.append(tuple(a+rotation@vec))
 for j in range(steps):
  for i in range(segments):
   n=j*(segments+1)+i
   faces.append((n,n+1,n+segments+2,n+segments+1));indices.append(0)
   uvs.append([(i/segments,j/steps),( (i+1)/segments,j/steps),((i+1)/segments,(j+1)/steps),(i/segments,(j+1)/steps)])
 # Flat endgrain discs reveal real concentric wood rings on both ends.
 for j,reverse in [(0,True),(steps,False)]:
  center=len(verts);verts.append(tuple(a if j==0 else b))
  for i in range(segments):
   f=(center,j*(segments+1)+i,j*(segments+1)+i+1)
   uv=[(.5,.5),(.5+.48*math.cos(2*math.pi*i/segments),.5+.48*math.sin(2*math.pi*i/segments)),(.5+.48*math.cos(2*math.pi*(i+1)/segments),.5+.48*math.sin(2*math.pi*(i+1)/segments))]
   if reverse:f=tuple(reversed(f));uv.reverse()
   faces.append(f);uvs.append(uv);indices.append(1)
 ob=mesh(name,verts,faces,uvs,[wood_m,cap_m],indices)
 for p in ob.data.polygons:p.use_smooth=p.material_index==0
 parts['Kindling' if kind else 'Logs'].append(ob)

for k in range(6):
 a=k*2*math.pi/6+.16;rr=.36+random.uniform(-.025,.025)
 start=(rr*math.cos(a),rr*math.sin(a),.12+random.uniform(0,.025))
 top=(.145*math.cos(a+1.15),.145*math.sin(a+1.15),.79+random.uniform(-.10,.10))
 log('UprightLog%02d'%k,start,top,random.uniform(.075,.092))
for k in range(3):
 angle=k*math.pi/3+.45;d=Vector((math.cos(angle),math.sin(angle),0));center=Vector((0,0,.13+k*.055))
 log('CrossLog%02d'%k,center-d*.35,center+d*.35,.065)
for k in range(18):
 angle=random.uniform(0,6.28);d=Vector((math.cos(angle),math.sin(angle),0));center=Vector((random.uniform(-.18,.18),random.uniform(-.18,.18),.09+random.uniform(0,.065)))
 log('Kindling%02d'%k,center-d*random.uniform(.1,.24),center+d*random.uniform(.1,.24),random.uniform(.009,.021),True)

# Irregular boulders, broad planar facets with softened edges, not identical spheres.
def rock(name,loc,scale,mat,group,subdiv=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv,radius=1,location=loc)
 ob=bpy.context.object;ob.name=name
 for v in ob.data.vertices:
  v.co*=random.uniform(.91,1.10)
  v.co.z=max(v.co.z,-.64)
 ob.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 ob.data.materials.append(mat)
 if group=='StoneRing':
  mod=ob.modifiers.new('SoftStoneEdges','BEVEL');mod.width=.026;mod.segments=2
  bpy.ops.object.modifier_apply(modifier=mod.name)
 # Spherical UVs suffice for softly mottled stone/charcoal.
 uv=ob.data.uv_layers.new(name='UVMap')
 for p in ob.data.polygons:
  for li in p.loop_indices:
   co=ob.data.vertices[ob.data.loops[li].vertex_index].co
   uv.data[li].uv=(math.atan2(co.y,co.x)/(2*math.pi)+.5,co.z/(scale[2]*2)+.5)
 ob.rotation_euler[2]=random.uniform(0,6.28)
 if group=='StoneRing':
  layer=ob.data.color_attributes.new(name='StoneTint',type='FLOAT_COLOR',domain='POINT')
  shade=random.uniform(.76,1.03)
  for vertex in ob.data.vertices:
   tone=shade*(.94+.06*vertex.co.z/max(scale[2],.01))
   layer.data[vertex.index].color=(tone,tone*.98,tone*.94,1)
 parts[group].append(ob);return ob
for k in range(14):
 angle=k*2*math.pi/14;rr=.76+random.uniform(-.025,.025)
 rock('RingStone%02d'%k,(rr*math.cos(angle),rr*math.sin(angle),.15),
  (random.uniform(.17,.225),random.uniform(.15,.19),random.uniform(.15,.19)),stone_m,'StoneRing',1)
for k in range(38):
 angle=random.uniform(0,6.28);rr=random.uniform(.33,.66)
 rock('Pebble%02d'%k,(rr*math.cos(angle),rr*math.sin(angle),.05),(.025,.025,.022),stone_m,'StoneRing')
for k in range(28):
 angle=random.uniform(0,6.28);rr=random.uniform(.08,.34)
 rock('Coal%02d'%k,(rr*math.cos(angle),rr*math.sin(angle),.075),(.06,.047,.045),coal_m,'Charcoal',2)
# A hand-shaped soil/ash disk with an irregular rim.
verts=[(0,0,.045)];N=64
for ring,r in enumerate([.30,.63,.87]):
 for i in range(N):
  a=i*2*math.pi/N;rr=r*(1+random.uniform(-.025,.025));z=.038 if ring<2 else .015
  verts.append((rr*math.cos(a),rr*math.sin(a),z))
faces=[]
for i in range(N):faces.append((0,1+i,1+(i+1)%N))
for ring in range(2):
 for i in range(N):
  n=1+ring*N+i;next_=1+ring*N+(i+1)%N
  faces.append((n,n+N,next_+N,next_))
uvs=[[(verts[i][0]/1.8+.5,verts[i][1]/1.8+.5) for i in f] for f in faces]
parts['GroundBed'].append(mesh('GroundBed',verts,faces,uvs,[soil_m]))
# Join per category: 5 mesh nodes and a few surfaces, instead of 100+ draw calls.
objects=[]
for name,obs in parts.items():
 bpy.ops.object.select_all(action='DESELECT')
 for ob in obs:ob.select_set(True)
 bpy.context.view_layer.objects.active=obs[0]
 if len(obs)>1:bpy.ops.object.join()
 ob=bpy.context.object;ob.name=name;ob.data.calc_loop_triangles();objects.append(ob)
 print(name,len(ob.data.loop_triangles),'triangles',flush=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'campfire.blend'))
bpy.ops.object.select_all(action='DESELECT')
for ob in objects:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'campfire_model.gltf'),export_format='GLTF_SEPARATE',use_selection=True,export_animations=False,export_vertex_color='ACTIVE')
if '--render' in sys.argv:
 sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=20
 sc.render.resolution_x=750;sc.render.resolution_y=650;sc.render.resolution_percentage=100
 sc.world=bpy.data.worlds.new('World');sc.world.color=(.22,.22,.22)
 bpy.ops.object.camera_add(location=(2.7,-4.2,2.65));cam=bpy.context.object
 cam.rotation_euler=(Vector((0,0,.38))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.5;sc.camera=cam
 for loc,power in [((2,-3,5),550),((-3,-1,3),450),((0,3,5),500)]:
  bpy.ops.object.light_add(type='AREA',location=loc);l=bpy.context.object;l.data.energy=power;l.data.size=4;l.rotation_euler=(Vector((0,0,.3))-l.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object
 floor.data.materials.append(material('Floor',None,(.10,.11,.12)))
 sc.render.filepath=os.path.join(OUT,'model_preview.png');bpy.ops.render.render(write_still=True)
