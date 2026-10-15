"""Standalone art asset matching ozero.jpg; no gameplay/world integration.
python tools/create_lake_model.py OUT_DIR [--render]
Requires bpy 5.1.2, numpy and Pillow. Units: metres; ground origin at water level.
Exports embedded GLB with a seamless 8-second morph animation, editable .blend,
and separately textured glTF for the Godot importer.
"""
import bpy, math, random, sys, os, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from mathutils import Vector
OUT=os.path.abspath(sys.argv[1]);os.makedirs(OUT,exist_ok=True)
random.seed(8214);rng=np.random.default_rng(8214)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau

def noise(n,s):
 a=rng.random((n,n))*255
 return np.asarray(Image.fromarray(a.astype('uint8')).resize((s,s),Image.Resampling.BICUBIC),dtype=float)/255

def image(name,a):
 p=os.path.join(OUT,name+'.png');Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(p)
 return bpy.data.images.load(p)

def mat(name,color,rough=.85,tex=None):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough
 if tex:
  n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=tex;m.node_tree.links.new(n.outputs['Color'],b.inputs['Base Color'])
 return m

def inner(a):return 3.35*(1+.068*math.sin(a*3+.4)+.039*math.sin(a*5-.9)+.017*math.sin(a*9))
def outer(a):return 4.92/(abs(math.cos(a))**4+abs(math.sin(a))**4)**.25*(1+.013*math.sin(a*7)+.009*math.sin(a*11))
def point(a,r,z):return (r*math.cos(a),.91*r*math.sin(a),z)
def bank_z(a,t):
 front=(max(0,-math.sin(a)))**8
 return -.09+(1-front*.42)*.62*(1-math.exp(-t*6))+.075*math.sin(a*4+.5)*min(1,t*4)+.035*math.sin(a*8+t*8)*min(1,t*5)-.07*t**5
# Painted atlas: broad organic moss/earth transitions, fine mineral variation and short grass strokes.
S=2048;yy,xx=np.mgrid[0:S,0:S];X=(xx/S-.5)*11.4;Y=(yy/S-.5)*11.4/.91
A=np.arctan2(Y,X);R=np.sqrt(X*X+Y*Y);ri=3.35*(1+.068*np.sin(A*3+.4)+.039*np.sin(A*5-.9)+.017*np.sin(A*9))
front=np.maximum(0,-np.sin(A))**8
n=noise(14,S)*.48+noise(42,S)*.22+noise(150,S)*.13+noise(650,S)*.05
f=np.clip((R-ri-(.16+front*.42)+(n-.43)*.4)/(.58-front*.18),0,1);f=f*f*(3-2*f)
soil=np.array([.31,.292,.219])[None,None,:]*(.77+n[...,None]*.45)
grass=np.array([.365,.442,.185])[None,None,:]*(.76+n[...,None]*.58)
tex=soil*(1-f[...,None])+grass*f[...,None]
# Slight deeper sediment tint toward centre, avoiding a bright yellow/artificial shoreline.
d=np.clip((ri-R)/1.5,0,1)[...,None];tex=tex*(1-d*.35)+np.array([.16,.215,.17])[None,None,:]*d*.35
im=Image.fromarray(np.uint8(np.clip(tex,0,1)*255));dr=ImageDraw.Draw(im)
for _ in range(23500):
 px=random.randrange(S);py=random.randrange(S)
 if f[py,px]>.72:
  l=random.randrange(2,7);c=(random.randrange(96,134),random.randrange(115,151),random.randrange(48,75));dr.line((px,py,px+random.randrange(-2,3),py-l),fill=c,width=1)
im.save(os.path.join(OUT,'lake_ground.png'));groundim=bpy.data.images.load(os.path.join(OUT,'lake_ground.png'))
S=512;yy,xx=np.mgrid[0:S,0:S];n=noise(14,S)*.14+noise(95,S)*.035
strata=.035*np.sin(yy/S*TAU*6+noise(8,S)*2)+.012*np.sin(yy/S*TAU*23)
sideim=image('lake_earth_strata',np.array([.31,.246,.16])[None,None,:]+(n+strata)[...,None]*np.array([.65,.5,.33]))
stoneim=image('lake_pebble',np.array([.40,.403,.335])[None,None,:]+(noise(22,S)-.5)[...,None]*.15+(noise(160,S)-.5)[...,None]*.04)
# Leaf texture with a fine central vein and diagonal branching veins, tinted by vertex colours.
S=256;yy,xx=np.mgrid[0:S,0:S];u=xx/S;v=yy/S
leaf=np.ones((S,S,3))*.92;vein=np.exp(-((u-.5)/.009)**2)*.10
branch=np.exp(-((np.abs(u-.5)*.85+(v*6)%1-.45)/.035)**2)*.035
leaf-=vein[...,None]+branch[...,None];leaf+=((noise(30,S)-.5)*.035)[...,None]
leafim=image('lake_leaf_veins',leaf)
GROUND=mat('LakeGround', (1,1,1),.97,groundim);SIDE=mat('LakeEarth',(1,1,1),.96,sideim);STONE=mat('LakePebbles',(1,1,1),.82,stoneim)
LEAF=mat('LakeLeaves',(1,1,1),.86,leafim);GRASS=mat('LakeGrasses',(1,1,1),.93);STEM=mat('LakeTwigs',(.19,.155,.08));REED=mat('LakeCattail',(.245,.135,.052),.99)
for m in [LEAF,GRASS,STONE]:
 b=m.node_tree.nodes['Principled BSDF'];col=m.node_tree.nodes.new('ShaderNodeVertexColor');col.layer_name='Tint'
 if m==LEAF:
  mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
  tx=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE');m.node_tree.links.new(tx.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(col.outputs['Color'],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
 elif m==STONE:
  mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
  tx=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE');m.node_tree.links.new(tx.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(col.outputs['Color'],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
 else:m.node_tree.links.new(col.outputs['Color'],b.inputs['Base Color'])
 m.use_backface_culling=False

def mesh(name,V,F,material,UV=None,C=None,smooth=True):
 me=bpy.data.meshes.new(name);me.from_pydata(V,[],F);me.update();ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(material)
 uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  p.use_smooth=smooth
  for li in p.loop_indices:
   vi=me.loops[li].vertex_index;co=V[vi]
   uv.data[li].uv=UV[vi] if UV is not None else (co[0]/11.4+.5,co[1]/11.4+.5)
 if C is not None:
  ca=me.color_attributes.new(name='Tint',type='FLOAT_COLOR',domain='POINT')
  for i,c in enumerate(C):ca.data[i].color=(*c[:3],1)
 return ob
# Sculpted bank with a low muddy entry on the near edge and lush raised sides.
N=192;K=25;V=[];F=[]
for j in range(K+1):
 t=j/K
 for i in range(N):
  a=i/N*TAU;r=inner(a)*.948+(outer(a)-inner(a)*.948)*t
  z=bank_z(a,t)+.018*math.sin(a*29+t*12)*math.sin(t*math.pi)
  V.append(point(a,r,z))
for j in range(K):
 for i in range(N):
  ni=(i+1)%N;a=j*N+i;b=j*N+ni;c=(j+1)*N+ni;d=(j+1)*N+i;F.extend([(a,d,c),(a,c,b)])
bank=mesh('SculptedBank',V,F,GROUND)
# Basin floor: shallow shelves show through the clear water, deeper green centre.
V=[(0,0,-.65)];F=[]
for j in range(1,19):
 t=j/18
 for i in range(N):
  a=i/N*TAU;V.append(point(a,inner(a)*t,-.63+.55*t**3+.016*math.sin(a*5)*t))
for i in range(N):F.append((0,1+i,1+(i+1)%N))
for j in range(17):
 for i in range(N):
  ni=(i+1)%N;a=1+j*N+i;b=1+j*N+ni;c=1+(j+1)*N+ni;d=1+(j+1)*N+i;F.extend([(a,d,c),(a,c,b)])
basin=mesh('LakeBasin',V,F,GROUND)
# Visible thickness: irregular horizontal sediment strata, no floating slab gaps.
V=[];UV=[];F=[]
for j in range(8):
 t=j/7
 for i in range(N+1):
  a=i/N*TAU;r=outer(a)*(1-.045*t+.012*math.sin(a*13+t*9)*math.sin(math.pi*t));z=bank_z(a,1)*(1-t)-.86*t+.021*math.sin(a*17+t*12)*math.sin(math.pi*t)
  V.append(point(a,r,z));UV.append((i/N*5,t))
for j in range(7):
 for i in range(N):
  a=j*(N+1)+i;F.append((a,a+1,a+N+2,a+N+1))
F.append(tuple(reversed([7*(N+1)+i for i in range(N)])))
side=mesh('EarthStrata',V,F,SIDE,UV,smooth=True)
# Merge thousands of little botanicals into a few material-based meshes.
class Batch:
 def __init__(self,name,material):self.name=name;self.mat=material;self.V=[];self.F=[];self.C=[];self.U=[]
 def add(self,V,F,C,UV=None):
  off=len(self.V);self.V.extend(V);self.F.extend(tuple(off+i for i in f) for f in F);self.C.extend([C]*len(V) if len(C)==3 and isinstance(C[0],float) else C);self.U.extend(UV if UV is not None else [(v[0]*2,v[1]*2) for v in V])
 def finish(self,smooth=True):return mesh(self.name,self.V,self.F,self.mat,self.U,self.C,smooth)
leaves=Batch('ShrubLeaves',LEAF);grasses=Batch('GrassTufts',GRASS);twigs=Batch('ShrubBranches',STEM);reeds=Batch('ReedLeaves',GRASS);heads=Batch('CattailHeads',REED);pebbles=Batch('ShorePebbles',STONE)

def rod(batch,a,b,r,col=(1.,1.,1.),segments=7):
 a=Vector(a);b=Vector(b);q=Vector((0,0,1)).rotation_difference((b-a).normalized());V=[]
 for p in [a,b]:
  for i in range(segments):V.append(tuple(p+q@Vector((r*math.cos(i/segments*TAU),r*math.sin(i/segments*TAU),0))))
 F=[(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)];F.extend([tuple(reversed(range(segments))),tuple(range(segments,segments*2))]);batch.add(V,F,col)

def blade(batch,base,ang,length,width,lean,col):
 base=Vector(base);side=Vector((math.cos(ang),math.sin(ang),0));forward=Vector((-math.sin(ang),math.cos(ang),0));V=[];UV=[]
 for j in range(6):
  t=j/5;center=base+forward*(lean*t*t)+Vector((0,0,length*(t-.15*t*t)));w=width*math.sin(math.pi*(t*.96+.025))
  for k in [-1,0,1]:V.append(tuple(center+side*w*k+Vector((0,0,.013*math.sin(math.pi*t)*(1-abs(k))))));UV.append(((k+1)/2,t))
 F=[]
 for j in range(5):
  for k in range(2):a=j*3+k;F.extend([(a,a+3,a+4),(a,a+4,a+1)])
 batch.add(V,F,col,UV)

def leaflet(base,dir_,L,W,col):
 base=Vector(base);d=Vector(dir_).normalized();side=d.cross(Vector((0,0,1))).normalized()
 if side.length<.1:side=Vector((1,0,0))
 V=[];UV=[]
 for j in range(5):
  t=j/4;center=base+d*(L*t)+Vector((0,0,.035*math.sin(t*math.pi)));w=W*math.sin(math.pi*t)**.8
  for k in [-1,0,1]:V.append(tuple(center+side*w*k-Vector((0,0,.015*abs(k)*math.sin(t*math.pi)))));UV.append(((k+1)/2,t))
 F=[]
 for j in range(4):
  for k in range(2):a=j*3+k;F.extend([(a,a+3,a+4),(a,a+4,a+1)])
 leaves.add(V,F,col,UV)

def ground_at(x,y):
 a=math.atan2(y/.91,x);r=math.hypot(x,y/.91);t=(r-inner(a)*.948)/(outer(a)-inner(a)*.948);return bank_z(a,max(0,min(1,t)))
# Asymmetrically grouped shrubs: breathing room and an unobstructed foreground shoreline.
for ang,dist,size in [(.35,.78,1.),(1.58,.85,1.05),(2.75,.83,.87),(3.3,.83,.67),(5.28,.86,.86)]:
 r=inner(ang)+(outer(ang)-inner(ang))*dist;x,y,_=point(ang,r,0);z=ground_at(x,y)
 for lobe in range(4):
  aa=random.random()*TAU;cx=x+math.cos(aa)*size*.31;cy=y+math.sin(aa)*size*.31;cz=z+size*random.uniform(.36,.65)
  rod(twigs,(x,y,z),(cx,cy,cz),.035*size)
  for _ in range(165):
   a=random.random()*TAU;zz=random.uniform(-.8,1);h=math.sqrt(1-zz*zz);rr=random.uniform(.55,1)
   p=(cx+math.cos(a)*h*rr*.42*size,cy+math.sin(a)*h*rr*.42*size,cz+zz*rr*.38*size)
   d=(math.cos(a)*.6+random.uniform(-.6,.6),math.sin(a)*.6+random.uniform(-.6,.6),random.uniform(-.25,.6))
   col=(random.uniform(.16,.31),random.uniform(.28,.46),random.uniform(.065,.13));leaflet(p,d,random.uniform(.12,.23)*size,random.uniform(.045,.075)*size,col)
# Fine curved grasses; mature tufts interspersed with smaller sprouts, not an even lawn.
for k in range(115):
 a=random.random()*TAU;t=random.uniform(.51,.95);r=inner(a)+(outer(a)-inner(a))*t;x,y,_=point(a,r,0);z=ground_at(x,y);sz=random.uniform(.65,1.25) if k<37 else random.uniform(.25,.55)
 for i in range(random.randrange(12,24)):
  aa=random.random()*TAU;p=(x+random.uniform(-.12,.12)*sz,y+random.uniform(-.12,.12)*sz,z-.012)
  blade(grasses,p,aa,random.uniform(.18,.48)*sz,random.uniform(.01,.023)*sz,random.uniform(.1,.24)*sz,(random.uniform(.27,.40),random.uniform(.35,.49),random.uniform(.105,.18)))
# Broadleaf ground rosettes around the outer rim.
for k in range(34):
 a=random.random()*TAU;t=random.uniform(.58,.95);r=inner(a)+(outer(a)-inner(a))*t;x,y,_=point(a,r,0);z=ground_at(x,y)
 for i in range(7):
  aa=i/7*TAU+random.uniform(-.2,.2);leaflet((x,y,z+.018),(math.cos(aa),math.sin(aa),random.uniform(.12,.4)),random.uniform(.16,.28),.052,(.24,.39,.15))
# Cattail islands close to the water, matching the reference's four small clusters.
for ang in [.28,1.91,3.55,5.35]:
 r=inner(ang)*.943;x,y,_=point(ang,r,0)
 for j in range(10):
  aa=random.random()*TAU;blade(reeds,(x+random.uniform(-.14,.14),y+random.uniform(-.14,.14),-.04),aa,random.uniform(.45,.85),random.uniform(.022,.04),random.uniform(.15,.30),(.27+random.random()*.12,.40+random.random()*.1,.11+random.random()*.09))
 for j in range(3):
  bx=x+random.uniform(-.13,.13);by=y+random.uniform(-.13,.13);h=random.uniform(.68,1.13);lean=random.uniform(-.1,.1)
  rod(reeds,(bx,by,-.065),(bx+lean,by+.05,h),.012,(.34,.40,.17))
  # Rounded seed-head mesh, subtly tapered tip.
  V=[];F=[];levels=9;seg=9
  for q in range(levels):
   t=q/(levels-1);rad=.034*math.sin(math.pi*(.04+.92*t))**.35
   for i in range(seg):V.append((bx+lean+math.cos(i/seg*TAU)*rad,by+.05+math.sin(i/seg*TAU)*rad,h-.20+t*.23))
  for q in range(levels-1):
   for i in range(seg):a=q*seg+i;b=q*seg+(i+1)%seg;F.append((a,b,b+seg,a+seg))
  heads.add(V,F,(1.,1.,1.))
# Pebbles: individually deformed ellipsoids with softened facets, concentrated in wet mud.
for k in range(132):
 a=random.random()*TAU;t=random.uniform(.94,1.20);r=inner(a)*t;x,y,_=point(a,r,0)
 if t<1:z=-.63+.55*t**3
 else:z=ground_at(x,y)
 s=random.uniform(.026,.087)*(1.8 if k<14 else 1);V=[];F=[]
 for j in range(7):
  ph=math.pi*j/6
  for i in range(9):
   th=i/9*TAU;rr=1+random.uniform(-.10,.10);V.append((x+math.sin(ph)*math.cos(th)*s*rr,y+math.sin(ph)*math.sin(th)*s*.75*rr,z+math.cos(ph)*s*.58+s*.25))
 for j in range(6):
  for i in range(9):a=j*9+i;b=j*9+(i+1)%9;F.append((a,b,b+9,a+9))
 pebbles.add(V,[tuple(reversed(f)) for f in F],(random.uniform(.85,1.22),random.uniform(.84,1.18),random.uniform(.78,1.10)))
for batch in [leaves,grasses,twigs,reeds,heads,pebbles]:batch.finish()
# Clear lake surface with pale jade shallows and a muted blue-green centre.
WATER=mat('LakeWater',(.065,.21,.175),.23)
b=WATER.node_tree.nodes['Principled BSDF'];vc=WATER.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Tint';WATER.node_tree.links.new(vc.outputs['Color'],b.inputs['Base Color']);b.inputs['IOR'].default_value=1.333;b.inputs['Transmission Weight'].default_value=.52;b.inputs['Coat Weight'].default_value=.20;b.inputs['Coat Roughness'].default_value=.25
nt=WATER.node_tree;texn=nt.nodes.new('ShaderNodeTexNoise');texn.inputs['Scale'].default_value=22;texn.inputs['Detail'].default_value=2;texn.inputs['Roughness'].default_value=.46
bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.16;bump.inputs['Distance'].default_value=.026;nt.links.new(texn.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs['Normal'],b.inputs['Normal'])
# Bake a seamless ripple normal map for generic GLB viewers; Godot uses analytic animated normals.
S=512;yy,xx=np.mgrid[0:S,0:S];u=xx/S*TAU;v=yy/S*TAU
h=.008*np.sin(u*13+v*7)+.004*np.sin(u*19-v*11)+.002*np.sin(u*29+v*23)
dy,dx=np.gradient(h);normal=np.stack((-dx*9,-dy*9,np.ones_like(h)),axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True);nim=image('lake_ripple_normal',normal*.5+.5);nim.colorspace_settings.name='Non-Color'
node=nt.nodes.new('ShaderNodeTexImage');node.image=nim;norm=nt.nodes.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.45;nt.links.new(node.outputs['Color'],norm.inputs['Color']);nt.links.new(norm.outputs['Normal'],b.inputs['Normal'])
V=[(0,0,.005)];F=[];UV=[(.5,.5)];COL=[(.08,.215,.182)];EDGE=[1.]
NA=160;NR=44
for j in range(1,NR+1):
 t=j/NR
 for i in range(NA):
  a=i/NA*TAU;p=point(a,inner(a)*.975*t,.005);V.append(p);UV.append((p[0]/6.6+.5,p[1]/6.6+.5));fade=max(0,1-t**4);EDGE.append(fade);c=np.array([.06,.185,.162])*(1-t**3)+np.array([.19,.32,.253])*t**3;COL.append(tuple(c))
for i in range(NA):F.append((0,1+i,1+(i+1)%NA))
for j in range(NR-1):
 for i in range(NA):
  ni=(i+1)%NA;a=1+j*NA+i;b_=1+j*NA+ni;c=1+(j+1)*NA+ni;d=1+(j+1)*NA+i;F.extend([(a,d,c),(a,c,b_)])
water=mesh('WaterSurface',V,F,WATER,UV,COL)
# Vertex colour is also exported so the shader can fade displacement at the shoreline.
water.shape_key_add(name='Basis')
for name_,axis,phase,amp in [('WindSin',(1.9,.8),0,.023),('WindCos',(1.9,.8),math.pi/2,.023),('CrossSin',(-1.2,2.4),0,.011),('CrossCos',(-1.2,2.4),math.pi/2,.011)]:
 key=water.shape_key_add(name=name_);key.slider_min=-1;key.slider_max=1
 for i,(x,y,z) in enumerate(V):key.data[i].co.z=z+amp*EDGE[i]*math.sin(x*axis[0]+y*axis[1]+phase)
 freq=1 if name_.startswith('Wind') else 2
 for frame in range(1,242,4):
  t=(frame-1)/240;key.value=math.cos(TAU*t*freq) if name_.endswith('Sin') else -math.sin(TAU*t*freq);key.keyframe_insert('value',frame=frame)
 key.value=math.cos(TAU*freq) if name_.endswith('Sin') else -math.sin(TAU*freq);key.keyframe_insert('value',frame=241)
water.data.shape_keys.animation_data.action.name='LakeWindLoop_8s'
# Thin discontinuous shoreline lip: muted wet edge rather than cartoon-white foam ring.
FOAM=mat('LakeShoreline',(.39,.44,.35),.78)
V=[];F=[]
for i in range(NA):
 a=i/NA*TAU
 for t in [.975,.982]:V.append(point(a,inner(a)*t,.008))
for i in range(NA):
 if math.sin(i/NA*TAU*7+1)>.05:
  a=i*2;b_=((i+1)%NA)*2;F.append((a,b_,b_+1,a+1))
mesh('WetShoreline',V,[tuple(reversed(f)) for f in F],FOAM)
# Select only the asset, leaving camera/lights/studio floor out of delivered meshes.
asset=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in asset:o.select_set(True)
sc=bpy.context.scene;sc.render.fps=30;sc.frame_start=1;sc.frame_end=241;sc.frame_set(1)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'lake_model.glb'),export_format='GLB',use_selection=True,export_animations=True,export_morph=True,export_frame_range=True,export_force_sampling=True,export_yup=True,export_cameras=False,export_lights=False)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'lake_model.gltf'),export_format='GLTF_SEPARATE',use_selection=True,export_animations=False,export_morph=False,export_yup=True,export_cameras=False,export_lights=False)
# Keep the true botanical tint in standard COLOR_0 for every glTF viewer.
import struct
def fix_colors(j):
 for m in j.get('meshes',[]):
  for p in m['primitives']:
   a=p['attributes']
   if 'COLOR_1' in a:a['COLOR_0']=a.pop('COLOR_1')
pth=os.path.join(OUT,'lake_model.gltf');j=json.load(open(pth));fix_colors(j)
with open(pth,'w') as f:json.dump(j,f)
pth=os.path.join(OUT,'lake_model.glb');raw=open(pth,'rb').read();ln=struct.unpack_from('<I',raw,12)[0];j=json.loads(raw[20:20+ln]);fix_colors(j)
tail=bytearray(raw[20+ln:]);done=set()
for animation in j.get('animations',[]):
 for sampler in animation['samplers']:
  ix=sampler['input']
  if ix in done:continue
  done.add(ix);accessor=j['accessors'][ix];view=j['bufferViews'][accessor['bufferView']];off=8+view.get('byteOffset',0)+accessor.get('byteOffset',0)
  times=np.frombuffer(tail,dtype='<f4',count=accessor['count'],offset=off);times-=times[0];accessor['min']=[float(times.min())];accessor['max']=[float(times.max())]
raw=raw[:20+ln]+tail
jb=json.dumps(j,separators=(',',':')).encode();jb+=b' '*((-len(jb))%4);tail=raw[20+ln:]
with open(pth,'wb') as f:f.write(struct.pack('<III',0x46546C67,2,20+len(jb)+len(tail))+struct.pack('<II',len(jb),0x4E4F534A)+jb+tail)
tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in asset);print('LAKE TRIANGLES',tris)
with open(os.path.join(OUT,'model_stats.json'),'w') as f:json.dump({'triangles':tris,'meshes':[(o.name,len(o.data.vertices),len(o.data.polygons)) for o in asset]},f,indent=2)
# Premium neutral studio with soft directional shadows; no props that are not part of the asset.
sc.render.engine='CYCLES';sc.render.threads_mode='FIXED';sc.render.threads=4;sc.cycles.samples=32;sc.cycles.use_denoising=True
sc.render.resolution_x=1600;sc.render.resolution_y=1100;sc.render.resolution_percentage=100
sc.world=bpy.data.worlds.new('LakeStudioWorld');sc.world.color=(.42,.42,.42);sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.56,.60,.57,1);sc.world.node_tree.nodes['Background'].inputs[1].default_value=.45
sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast'
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.90));floor=bpy.context.object;floor.name='PreviewFloor';floor.data.materials.append(mat('PreviewClay',(.48,.49,.455),.94))
for name_,loc,power,size in [('Key',(-5,-7,12),1700,7),('Fill',(7,-1,8),950,7),('Rim',(-2,7,9),1300,5)]:
 bpy.ops.object.light_add(type='AREA',location=loc);ob=bpy.context.object;ob.name='Studio'+name_;ob.data.energy=power;ob.data.shape='DISK';ob.data.size=size;ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(11,-15,13));cam=bpy.context.object;cam.name='PreviewCamera';cam.rotation_euler=(Vector((0,0,.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=14.7;sc.camera=cam
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'lake_model.blend'))
if '--render' in sys.argv:
 for name_,pos,scale in [('lake_hero',(11,-15,13),14.7),('lake_reverse',(-13,11,12),14.7),('lake_detail',(7,-10,8),8.0)]:
  cam.location=pos;target=Vector((0,-.8,.0)) if name_=='lake_detail' else Vector((0,0,0));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=os.path.join(OUT,name_+'.png');bpy.ops.render.render(write_still=True)
print('LAKE BUILD COMPLETE')
