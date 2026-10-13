"""Two timber cottages from House.jpg / House_wreck.jpg. Own geometry and textures.
python tools/create_house_models.py BUILD_DIR
Blender: Z up, facade -Y. Godot: facade +Z. No reference raster in the game.
"""
import bpy, math, os, sys, random
import numpy as np
from PIL import Image
from mathutils import Vector
OUT=os.path.abspath(sys.argv[1]);os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng=np.random.default_rng(137)
def noise(n,s=1024):
 return np.asarray(Image.fromarray(np.uint8(rng.random((n,n))*255)).resize((s,s),Image.Resampling.BICUBIC),dtype=float)/255
s=1024;y,x=np.mgrid[0:s,0:s];u=x/s;v=y/s
flow=u+.009*np.sin(v*13+u*14)+.006*np.sin(v*28+u*25)
grain=.06*np.sin(flow*210)+.024*np.sin(flow*510+v*8)
# Painted elongated knots and annual grain, not noisy bark.
for cx,cy in [( .24,.32),(.76,.73),(.52,.9)]:
 d=np.sqrt(((u-cx)*3)**2+((v-cy)*.7)**2)
 grain+=np.exp(-d*18)*np.sin(d*180)*.1
tex=np.array([.55,.43,.30])[None,None,:]*(.92+grain[...,None]+noise(18)[...,None]*.12)
stone=np.array([.46,.445,.39])[None,None,:]*(.77+noise(9)[...,None]*.34+noise(55)[...,None]*.08)
def image(name,arr):
 p=os.path.join(OUT,name+'.png');Image.fromarray(np.uint8(np.clip(arr,0,1)*255)).save(p);return bpy.data.images.load(p)
wood_im=image('house_wood',tex);stone_im=image('house_stone',stone)
for name,arr in [('wood',tex),('stone',stone)]:
 h=arr.mean(axis=2);dy,dx=np.gradient(h);n=np.dstack((-dx*6,-dy*6,np.ones_like(h)));n/=np.linalg.norm(n,axis=2)[...,None];image('house_'+name+'_normal',n*.5+.5)
def mat(name,img=None,color=(1,1,1),metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.85;p.inputs['Metallic'].default_value=metal
 if img:
  t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=img;m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
 return m
mats={
 'wood':mat('HouseWood',wood_im),'roof':mat('HouseRoof',wood_im),
 'trim':mat('HouseTrim',wood_im),'stone':mat('HouseStone',stone_im),
 'interior':mat('HouseInterior',None,(.075,.05,.033)),
 'metal':mat('HouseIron',None,(.16,.17,.16),.7),
 'glass':mat('HouseGlass',None,(.85,.40,.10)),
 'moss':mat('HouseMoss',None,(.19,.23,.095)),
 'tarp':mat('HouseTarp',None,(.24,.32,.30))}
parts={};state='';random.seed(137)
def finish(ob,key,material,tint=1,bevel=0):
 ob.data.materials.append(mats[material]);bpy.context.view_layer.objects.active=ob
 if bevel:
  mod=ob.modifiers.new('WornEdges','BEVEL');mod.width=bevel;mod.segments=1;bpy.ops.object.modifier_apply(modifier=mod.name)
 uv=ob.data.uv_layers.new(name='UVMap');coords=np.array([v.co[:] for v in ob.data.vertices]);span=np.ptp(coords,axis=0);axis=int(np.argmax(span));others=[i for i in range(3) if i!=axis]
 offset=random.random()
 for p in ob.data.polygons:
  minor=max(others,key=lambda i:np.ptp([coords[v][i] for v in p.vertices]))
  for li in p.loop_indices:
   co=coords[ob.data.loops[li].vertex_index];uv.data[li].uv=((co[minor]/max(span[minor],.05)+.5)*.66+offset,co[axis]/max(span[axis],.05)*.86+.5)
 color=ob.data.color_attributes.new(name='Tint',type='FLOAT_COLOR',domain='POINT')
 if material=='roof':base=(.98,1.03,1.06)
 elif material=='trim':base=(.43,.45,.46)
 elif material=='wood':base=(1.0,.95,.88)
 else:base=(1,1,1)
 if state=='ruined' and material in ('wood','roof'):tint*=.77
 for c in color.data:c.color=(*[k*tint for k in base],1)
 parts.setdefault(key,[]).append(ob);return ob

def box(key,name,loc,size,material='wood',bevel=.018,tint=None,rotation=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);ob=bpy.context.object;ob.name=name;ob.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rotation:ob.rotation_euler=rotation
 return finish(ob,key,material,random.uniform(.88,1.10) if tint is None else tint,bevel)
def beam(key,name,a,b,w=.16,d=None,material='wood'):
 a=Vector(a);b=Vector(b);ob=box(key,name,(a+b)/2,(w,d or w,(b-a).length),material,bevel=.025)
 ob.rotation_euler=Vector((0,0,1)).rotation_difference((b-a).normalized()).to_euler();return ob

def prism(key,name,polygon,thick,origin,axis1,axis2,normal,material='wood'):
 origin=Vector(origin);axis1=Vector(axis1);axis2=Vector(axis2);normal=Vector(normal)
 if axis1.cross(axis2).dot(normal)<0:polygon=list(reversed(polygon))
 verts=[tuple(origin+axis1*a+axis2*b+normal*c) for c in [-thick/2,thick/2] for a,b in polygon];n=len(polygon)
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
 return finish(ob,key,material,random.uniform(.86,1.08),0)

def brick(key,name,loc,size):
 ob=box(key,name,loc,size,'stone',bevel=min(size)*.17,tint=random.uniform(.78,1.14))
 for v in ob.data.vertices:v.co+=Vector(tuple(random.uniform(-.009,.009) for _ in range(3)))
 return ob
W=4.9;D=3.8;BASE=.40;EAVE=2.97;PEAK=4.95;RX=2.87;RY=2.35

def cottage(which):
 global state,parts
 state=which;parts={};random.seed(137)
 ruined=which=='ruined'
 # Foundation has real joints and chunky individual dressed stones.
 box('Foundation','MortarBed',(0,0,.19),(5.1,4.05,.35),'interior',0)
 for row in range(2):
  z=.12+row*.19
  for side in [-1,1]:
   for i in range(10):brick('Foundation','FootingFront',( -2.38+i*.53+(.08 if row else 0),side*1.97,z),(.51,.35,.26))
   for i in range(7):brick('Foundation','FootingSide',(side*2.5,-1.57+i*.52,z),(.38,.5,.26))
 for j in range(2):brick('Foundation','DoorStep',(0,-2.15-j*.27,.16-j*.06),(1.22+j*.16,.48,.21))
 # Interior floor is visible through real ruined-roof openings.
 for i in range(16):box('Walls','FloorBoard',(-2.23+i*.30,0,.4),(.285,3.64,.08),'wood',.008,tint=.65)
 # Horizontal siding, with doorway/window cutouts, and jagged missing board sections.
 for side in [-1,1]:
  for row in range(12):
   z=.53+row*.205
   spans=[(-2.38,2.38)]
   openings=[]
   if side==-1 and z<2.2:openings.append((-.52,.52))
   if 1.02<z<2.04:openings.extend([(-1.90,-1.06),(1.06,1.90)])
   for oa,ob in openings:
    spans=[piece for a,b in spans for piece in ([(a,min(b,oa))] if a<oa else [])+([(max(a,ob),b)] if b>ob else []) if piece[1]-piece[0]>.04]
   for a,b in spans:
    damaged=ruined and ((row in [2,4,10] and side==-1) or (row in [3,8] and side==1)) and b-a>.6
    if damaged:
     mid=(a+b)/2;gap=min(.32,(b-a)*.25)
     for l,r in [(a,mid-gap),(mid+gap,b)]:
      if r-l<.05:continue
      poly=[(l,-.087),(r-.09,-.087),(r,.015),(r-.1,.087),(l,.087)]
      prism('Walls','SplinteredSiding',poly,.11,(0,side*1.9,z),(1,0,0),(0,0,1),(0,-1,0))
    else:box('Walls','Siding',((a+b)/2,side*1.9,z),(b-a,.115,.182),'wood',.012)
  # Timber gable, vertical boards following the triangular profile.
  for i in range(22):
   xx=-2.33+i*.22;top=PEAK-abs(xx)/RX*(PEAK-EAVE)-.09;h=top-EAVE
   if h<.10:continue
   if abs(xx)<.45 and EAVE+h>3.65:
    box('Walls','GableUnderWindow',(xx,side*1.9,(EAVE+3.43)/2),(.207,.115,3.43-EAVE),'wood',.01)
    if top>4.15:box('Walls','GableAboveWindow',(xx,side*1.9,(top+4.15)/2),(.207,.115,top-4.15),'wood',.01)
   else:box('Walls','GableBoard',(xx,side*1.9,EAVE+h/2),(.207,.115,h),'wood',.012)
 for side in [-1,1]:
  for row in range(12):
   z=.53+row*.205;spans=[(-1.84,1.84)]
   if 1.02<z<2.04:spans=[(-1.84,-.52),(.52,1.84)]
   for a,b in spans:
    if ruined and row in [3,10] and side==1:
     for l,r in [(a,a+(b-a)*.35),(a+(b-a)*.58,b)]:
      prism('Walls','BrokenSideBoard',[(l,-.08),(r-.09,-.08),(r,.02),(r-.08,.08),(l,.08)],.115,(side*2.45,0,z),(0,1,0),(0,0,1),(1,0,0))
    else:box('Walls','SideBoard',(side*2.45,(a+b)/2,z),(.115,b-a,.182),'wood',.012)
 # Load-bearing posts and trim; coherent architecture in both states.
 for xx in [-2.47,2.47]:
  for yy in [-1.91,1.91]:beam('Timber','CornerPost',(xx,yy,.38),(xx+(.04 if ruined else 0),yy,3.02),.21)
 for yy in [-1.95,1.95]:
  beam('Timber','WallHeader',(-2.54,yy,2.91),(2.54,yy,2.91),.22)
  beam('Roof','GableBargeLeft',(-RX,yy-.18,EAVE-.12),(0,yy-.18,PEAK+.08),.24)
  beam('Roof','GableBargeRight',(0,yy-.18,PEAK+.08),(RX,yy-.18,EAVE-.12),.24)
  beam('Timber','GableBase',(-2.46,yy,3.02),(2.46,yy,3.02),.17)
 beam('Roof','Ridge',(0,-RY-.1,PEAK),(0,RY+.1,PEAK),.26)
 for side in [-1,1]:
  beam('Roof','EaveBeam',(side*RX,-RY,EAVE-.12),(side*RX,RY,EAVE-.12),.23)
  for j in range(9):
   yy=-2.17+j*.55
   if ruined and side==1 and 2<=j<=6:
    beam('Roof','SnappedRafter',(0,yy,PEAK-.09),(side*.68,yy,PEAK-.57),.12)
    beam('Roof','RafterRemnant',(side*2.35,yy,EAVE+.25),(side*RX,yy,EAVE-.07),.12)
   else:beam('Roof','Rafter',(0,yy,PEAK-.09),(side*RX,yy,EAVE-.07),.12)
  slope=Vector((side*RX,0,EAVE-PEAK));normal=Vector((side*(PEAK-EAVE),0,RX)).normalized();direction=slope.normalized();length=slope.length
  for row in range(8):
   t=(row+.5)/8;px=side*RX*t;pz=PEAK+(EAVE-PEAK)*t+.035+(8-row)*.007
   for col in range(13):
    yy=-2.22+col*.37+(0.04 if row%2 else -.03)
    # One large continuous breach, not peppered random omissions.
    if ruined and ((side==1 and ((2<=row<=6 and 3<=col<=9) or (row==7 and 5<=col<=8))) or (side==-1 and row in [1,2,3] and 6<=col<=8)):continue
    tilew=.36+random.uniform(-.02,.012);tileh=length/8+.14
    tip=random.uniform(-.04,.035)
    poly=[(-tilew/2,-tileh/2),(tilew/2,-tileh/2),(tilew/2,tileh/2+tip),(tilew*.13,tileh/2+.012),(-tilew*.07,tileh/2-.018),(-tilew/2,tileh/2+.035)]
    prism('Roof','WoodenShingle',poly,.055,(px,yy,pz),(0,1,0),direction,normal,'roof')
 # Door, rails, iron handle and straps.
 box('Door','DoorDarkGap',(0,-1.96,1.29),(1.02,.09,1.80),'interior',0)
 for i in range(5):box('Door','DoorBoard',(-.37+i*.185,-2.025,1.28),(.176,.065,1.70),'wood',.012)
 for xx in [-.54,.54]:beam('Door','DoorJamb',(xx,-2.07,.43),(xx,-2.07,2.25),.13)
 beam('Door','Lintel',(-.64,-2.07,2.25),(.64,-2.07,2.25),.14)
 for z in [.76,1.85]:box('Door','DoorRail',(0,-2.08,z),(.91,.07,.12),'wood',.015)
 for z in [.77,1.85]:box('Door','Hinge',(-.31,-2.126,z),(.19,.025,.04),'metal',.009)
 bpy.ops.mesh.primitive_torus_add(major_radius=.052,minor_radius=.012,major_segments=12,minor_segments=5,location=(.31,-2.13,1.15),rotation=(math.pi/2,0,0));finish(bpy.context.object,'Door','metal')
 # Window openings and dark charcoal trim, cross mullions, amber glass only in repaired model.
 def window(center,side=False,gable=False):
  w=.66 if gable else .78;h=.63 if gable else .93
  xx,yy,zz=center
  horizontal=(0,1,0) if side else (1,0,0);normal=((1 if xx>0 else -1),0,0) if side else (0,(1 if yy>0 else -1),0)
  origin=Vector(center);right=Vector(horizontal);norm=Vector(normal)
  poly=[(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]
  prism('Windows','WindowInterior',poly,.04,origin,right,(0,0,1),norm,'interior')
  if not ruined:prism('Glass','WarmGlass',poly,.012,origin+norm*.06,right,(0,0,1),norm,'glass')
  for a in [-1,1]:
   beam('Windows','WindowJamb',origin+right*a*(w/2+.055)+Vector((0,0,-h/2)),origin+right*a*(w/2+.055)+Vector((0,0,h/2)),.09,material='trim')
   beam('Windows','WindowRail',origin+Vector((0,0,a*(h/2+.055)))+right*(-w/2-.14),origin+Vector((0,0,a*(h/2+.055)))+right*(w/2+.14),.12,material='trim')
  beam('Windows','WindowMullion',origin+norm*.09+Vector((0,0,-h/2)),origin+norm*.09+Vector((0,0,h/2)),.047)
  beam('Windows','WindowCross',origin+norm*.09-right*w/2,origin+norm*.09+right*w/2,.045)
 for xx in [-1.48,1.48]:
  for yy in [-2.025,2.025]:window((xx,yy,1.53))
 for yy in [-2.02,2.02]:window((0,yy,3.80),gable=True)
 for side in [-1,1]:window((side*2.54,0,1.53),side=True)
 # Exterior chimney: stacked irregular masonry, stepped plinth and open mouth.
 cx=2.52;cy=.62
 box('Chimney','DarkMortarShaft',(cx,cy,2.31),(.69,.64,3.95),'interior',0)
 for row in range(15):
  z=.54+row*.258;span=.85-(row/15)*.11
  for side in [-1,1]:
   for j in range(2):
    brick('Chimney','ChimneyStone',(cx+side*span/2,cy+(j-.5)*.35+(.05 if row%2 else -.02),z),(.23,.345,.27))
    brick('Chimney','ChimneyStone',(cx+(j-.5)*.35,cy+side*span/2,z),(.345,.23,.27))
 for side in [-1,1]:
  brick('Chimney','CapStone',(cx+side*.38,cy,4.51),(.27,1.01,.23))
  brick('Chimney','CapStone',(cx,cy+side*.38,4.51),(.51,.27,.23))
 box('Chimney','FlueDarkInterior',(cx,cy,4.36),(.48,.48,.015),'interior',0)
 for j in range(5):brick('Chimney','HearthPlinth',(cx-.4+j*.2,cy,.3),(.29,1.12,.46))
 # Small moss tufts confined to damp foundation joints.
 for i in range(35):
  side=random.choice([-1,1]);xx=random.uniform(-2.5,2.5);yy=side*2.02
  for k in range(3):beam('Foundation','MossTuft',(xx,yy,.08),(xx+random.uniform(-.035,.035),yy+random.uniform(-.025,.025),random.uniform(.14,.22)),.011,material='moss')
 if ruined:
  for i in range(35):
   side=random.choice([-1,1]);xx=random.uniform(-2.9,2.9);yy=random.uniform(-2.7,2.7)
   if abs(xx)<2.5 and abs(yy)<2.05:yy=-2.2-random.random()*.5
   ob=box('Debris','FallenBoard',(xx,yy,random.uniform(.06,.17)),(random.uniform(.27,.94),random.uniform(.10,.23),.045),'wood',.009);ob.rotation_euler=(random.uniform(-.08,.12),random.uniform(-.1,.1),random.uniform(0,6.28))
  for i in range(11):
   xx=random.choice([-1,1])*random.uniform(2.7,3.0);yy=random.uniform(-2.5,2.4);brick('Debris','Rubble',(xx,yy,.11),(.20,.22,.18))
  for i in range(3):beam('Debris','LeaningBrokenTimber',(2.7,-1.2+i*.2,.13),(2.55,-.9+i*.2,.7),.13)
 # One shared emergency tarp covers the cleared roof at stage 1 only.
 # Explicit ownership/group names make partial rebuilding a real architectural transition.
 for side in [-1,1]:
  for row in range(10):
   for col in range(16):
    # Open notch for unused stone flue, no fabric/chimney intersection.
    xx=side*RX*(row+.5)/10;yy=-2.35+4.7*(col+.5)/16
    if side==1 and xx>2.1 and abs(yy-.62)<.70:continue
    verts=[]
    for r,c in [(row,col),(row+1,col),(row+1,col+1),(row,col+1)]:
     t=r/10;y0=-2.35+4.7*c/16
     sag=.09*math.sin(math.pi*t)*math.sin(math.pi*c/16)
     ripple=.018*math.sin(c*1.5+r*.8)*math.sin(math.pi*t)
     verts.append((side*RX*t,y0,PEAK+(EAVE-PEAK)*t+.10-sag+ripple))
    if side==1:verts.reverse()
    me=bpy.data.meshes.new('CanvasPanel');me.from_pydata(verts,[],[(0,1,2,3)]);me.update()
    ob=bpy.data.objects.new('CanvasPanel',me);bpy.context.collection.objects.link(ob)
    finish(ob,'Tarp','tarp',tint=.92+.05*(col%3))
  for yy in [-2.35,2.35]:
   beam('Tarp','Hem',(0,yy,PEAK+.11),(side*RX,yy,EAVE+.11),.027,material='tarp')
  for yy in [-1.8,0,1.8]:
   beam('Tarp','TieCord',(side*RX,yy,EAVE+.1),(side*2.5,yy,2.2),.014,material='tarp')
 # Join by architectural part: static draw calls and payload sizes remain bounded.
 for name,items in parts.items():
  for o in bpy.context.selected_objects:o.select_set(False)
  for o in items:o.select_set(True)
  bpy.context.view_layer.objects.active=items[0]
  if len(items)>1:bpy.ops.object.join()
  o=items[0];o.name=name;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
  bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 for o in bpy.context.selected_objects:o.select_set(False)
 objects=[bpy.data.objects.get(name) for name in parts]
 for o in objects:o.select_set(True)
 path=os.path.join(OUT,'house_'+which+'.gltf')
 bpy.ops.export_scene.gltf(filepath=path,export_format='GLTF_SEPARATE',use_selection=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_yup=True)
 tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
 print(which,'triangles',tris,'parts',len(objects),flush=True)
 for o in objects:bpy.data.objects.remove(o,do_unlink=True)
for which in ['ruined','restored']:cottage(which)
