"""Timber product warehouse from склад.jpg / склад_wreck.jpg, own geometry.
python tools/create_warehouse_models.py BUILD_DIR
Reuses the cottage's procedural wood/stone and bevel/UV helpers, not its architecture.
"""
import create_house_models as g
import bpy,math,os,random
from mathutils import Vector
box=g.box;beam=g.beam;prism=g.prism;brick=g.brick
W=4.4;D=3.55;EAVE=2.87;PEAK=4.35;RX=2.62;RY=2.10
pivots={'Gear':(0,-2.16,3.15),'Crank':(.28,-2.17,3.15),'Chain':(0,-2.20,3.16),'Hook':(0,-2.20,1.0)}
def cylinder(part,name,loc,radius,depth,mat='wood',rotation=None):
 bpy.ops.mesh.primitive_cylinder_add(vertices=14,radius=radius,depth=depth,location=loc)
 o=bpy.context.object;o.name=name
 if rotation:o.rotation_euler=rotation
 return g.finish(o,part,mat,random.uniform(.88,1.08),.008)
def ring(part,name,loc,major,minor,mat='metal',rotation=None):
 bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=5,major_radius=major,minor_radius=minor,location=loc)
 o=bpy.context.object;o.name=name
 if rotation:o.rotation_euler=rotation
 return g.finish(o,part,mat,1,0)
def crate(part,loc,size=.5):
 x,y,z=loc
 box(part,'CrateCore',(x,y,z),(size,size,size),'interior',.014)
 for side in [-1,1]:
  for j in range(4):
   box(part,'CratePlank',(x+(j-1.5)*size/4,y+side*size*.5,z),(size/4-.012,.045,size),'wood',.012)
   box(part,'CratePlank',(x+side*size*.5,y+(j-1.5)*size/4,z),(.045,size/4-.012,size),'wood',.012)
  for zz in [z-size*.40,z+size*.40]:
   box(part,'CrateRail',(x,y+side*(size*.5+.027),zz),(size+.025,.045,.06),'wood',.01)
  beam(part,'CrateDiagonal',(x-size*.42,y+side*(size*.5+.06),z-size*.4),(x+size*.42,y+side*(size*.5+.06),z+size*.4),.055,.035)
 for j in range(4):box(part,'CrateLid',(x+(j-1.5)*size/4,y,z+size*.51),(size/4-.006,size,.04),'wood',.012)
def barrel(loc):
 x,y,z=loc
 cylinder('Goods','BarrelDark',(x,y,z),.235,.67,'interior')
 for j in range(14):
  a=j*math.tau/14;o=box('Goods','BarrelStave',(x+.232*math.cos(a),y+.232*math.sin(a),z),(.11,.048,.65),'wood',.02);o.rotation_euler.z=a+math.pi/2
 cylinder('Goods','BarrelLid',(x,y,z+.335),.239,.035)
 for zz in [z-.245,z+.245]:ring('Goods','BarrelHoop',(x,y,zz),.252,.026)
def warehouse(which):
 ruined=which=='ruined';g.state=which;g.parts={};random.seed(739)
 # Raised stone course, interior deck and threshold.
 box('Foundation','Underfloor',(0,0,.10),(4.56,3.75,.16),'interior',.015)
 for row in range(2):
  for side in [-1,1]:
   for i in range(10):brick('Foundation','Footing',(-2.10+i*.465,side*1.80,.13+row*.20),(.46,.29,.25))
   for i in range(7):brick('Foundation','Footing',(side*2.23,-1.46+i*.47,.13+row*.20),(.29,.46,.25))
 for j in range(20):box('Foundation','FloorBoard',(-2.09+j*.22,0,.43),(.211,3.40,.055),'wood',.007)
 brick('Foundation','EntryStep',(0,-1.97,.18),(2.0,.59,.23))
 # Massive vertical siding; entrance remains physically open, interior visible.
 for side in [-1,1]:
  for j in range(20):
   x=-2.09+j*.22
   if side==-1 and abs(x)<.94:continue
   damaged=ruined and side==-1 and j in [2,3,16]
   if damaged:
    box('Shell','SplitBoard',(x,side*D/2,1.05),(.205,.12,1.1),'wood',.014)
    box('Shell','SplitBoard',(x,side*D/2,2.65),(.205,.12,.38),'wood',.014)
   else:box('Shell','Siding',(x,side*D/2,1.65),(.206,.12,2.35),'wood',.015)
  for j in range(20):
   x=-2.09+j*.22;h=PEAK-abs(x)/RX*(PEAK-EAVE)-EAVE
   box('Shell','GablePlank',(x,side*D/2,EAVE+h/2),(.207,.13,h),'wood',.014)
 for side in [-1,1]:
  for j in range(16):
   y=-1.66+j*.221
   if -.46<y<.46:
    for z,h in [(.96,1.0),(2.51,.65)]:box('Shell','UnderWindow',(side*2.2,y,z),(.12,.207,h),'wood',.013)
   elif ruined and side==1 and j in [12,13]:
    box('Shell','BrokenWall',(side*2.2,y,.90),(.12,.207,.9),'wood',.014)
    box('Shell','BrokenWall',(side*2.2,y,2.62),(.12,.207,.38),'wood',.014)
   else:box('Shell','SidePlank',(side*2.2,y,1.65),(.12,.207,2.35),'wood',.014)
  box('Hardware','WindowDark',(side*2.245,0,1.72),(.025,.82,.72),'interior',0)
  for yy in [-.45,.45]:beam('Hardware','WindowFrame',(side*2.28,yy,1.29),(side*2.28,yy,2.15),.07,material='trim')
  for zz in [1.29,2.15]:beam('Hardware','WindowFrame',(side*2.28,-.49,zz),(side*2.28,.49,zz),.08,material='trim')
  for yy in [-.2,.0,.2]:beam('Hardware','WindowBar',(side*2.31,yy,1.31),(side*2.31,yy,2.13),.035,material='metal')
 # Posts, horizontal rails and diagonal bracing with iron shoes and bolts.
 for xx in [-2.18,2.18]:
  for yy in [-1.75,0,1.75]:
   beam('Frame','Post',(xx,yy,.39),(xx,yy,2.92),.22)
   box('Hardware','IronShoe',(xx,yy,.54),(.245,.26,.26),'metal',.025)
 for yy in [-1.82,1.82]:
  for zz in [.62,2.78]:beam('Frame','FacadeHeader',(-2.28,yy,zz),(2.28,yy,zz),.20)
  for xx in [-1.00,1.00]:beam('Frame','EntryJamb',(xx,yy,.42),(xx,yy,2.56),.20)
  for side in [-1,1]:
   beam('Frame','Brace',(side*2.16,yy,2.22),(side*1.55,yy,2.76),.11)
 for side in [-1,1]:
  for zz in [.85,1.45,2.43]:beam('Frame','SideRail',(side*2.26,-1.7,zz),(side*2.26,1.7,zz),.14)
  for y in [-1.68,0,1.68]:
   for z in [.85,1.45,2.43,2.8]:
    box('Hardware','JointPlate',(side*2.36,y,z),(.035,.26,.20),'metal',.014)
    for dy in [-.08,.08]:cylinder('Hardware','Rivet',(side*2.385,y+dy,z),.031,.028,'metal',(0,math.pi/2,0))
 for y in [-1.84,1.84]:
  for x in [-2.14,-1.0,0,1.0,2.14]:
   box('Hardware','FacadePlate',(x,y-.08,2.78),(.28,.035,.18),'metal',.013)
   for dx in [-.09,.09]:cylinder('Hardware','FacadeBolt',(x+dx,y-.105,2.78),.025,.023,'metal',(math.pi/2,0,0))
 for yy in [-1.77,1.77]:
  beam('Frame','KingPost',(0,yy,2.78),(0,yy,PEAK),.13)
  for side in [-1,1]:beam('Frame','GableSupport',(side*2.2,yy,EAVE+.20),(0,yy,PEAK),.12)
 beam('Frame','Ridge',(0,-2.15,PEAK+.05),(0,2.15,PEAK+.05),.21)
 for yy in [-2.05,2.05]:
  for side in [-1,1]:beam('Roof','Bargeboard',(side*RX,yy,EAVE-.05),(0,yy,PEAK+.06),.23)
 for side in [-1,1]:
  beam('Roof','Eave',(side*RX,-2.13,EAVE),(side*RX,2.13,EAVE),.18)
  for j in range(8):
   yy=-1.76+j*.50
   if ruined and side==1 and j in [2,3,4,5]:
    beam('Roof','SnappedRafter',(side*RX,yy,EAVE),(side*1.8,yy,3.3),.12)
   else:beam('Roof','Rafter',(0,yy,PEAK-.09),(side*RX,yy,EAVE-.10),.12)
 # Board shingles with asymmetrical chips and corrugated metal repairs.
 for side in [-1,1]:
  slope=Vector((side*RX,0,EAVE-PEAK));normal=Vector((side*(PEAK-EAVE),0,RX)).normalized();axis=slope.normalized()
  for row in range(6):
   for col in range(14):
    if ruined and ((side==1 and 1<=row<=5 and 3<=col<=9) or (side==-1 and 2<=row<=3 and 7<=col<=9)):continue
    t=(row+.50)/6;yy=-RY+(col+.5)*RY*2/14
    poly=[(-.145,-.31),(.146,-.31),(.145,.30),(.06,.28),(.035,.32),(-.07,.28),(-.145,.31)]
    origin=(side*RX*t,yy,PEAK+(EAVE-PEAK)*t+.065+(5-row)*.006)
    prism('Roof','Shingle',poly,.04,origin,(0,1,0),axis,normal,'roof')
  for t,yy in [( .28,1.27),(.74,-.86)]:
   for stripe in range(9):
    y0=yy+(stripe-4)*.067
    origin=Vector((side*RX*t,y0,PEAK+(EAVE-PEAK)*t+.145))+normal*(.023 if stripe%2 else 0)
    prism('Roof','CorrugatedPatch',[(-.035,-.37),(.035,-.37),(.035,.37),(-.035,.37)],.018,origin,(0,1,0),axis,normal,'metal')
  beam('Roof','RoofBatten',(side*.50,-1.96,PEAK+(EAVE-PEAK)*.50/RX+.15),(side*.50,1.96,PEAK+(EAVE-PEAK)*.50/RX+.15),.09)
 # Two open gate leaves, with individual planks, iron rim and handle.
 for side in [-1,1]:
  hinge=Vector((side*1.03,-1.91,0));angle=side*math.radians(51 if not ruined else 67)
  # Leaves open toward the courtyard; all door components share transform.
  before=list(g.parts.get('Doors',[]))
  for j in range(5):
   broken=ruined and j==2
   box('Doors','GateBoard',(side*(-.09-j*.175),0,1.20 if broken else 1.43),(.165,.075,1.40 if broken else 1.98),'wood',.012)
  for zz in [.50,1.18,2.37]:box('Doors','IronGateStrap',(-side*.44,-.058,zz),(.93,.045,.075),'metal',.014)
  for xx in [-side*.03,-side*.89]:box('Doors','GateRim',(xx,-.04,1.43),(.075,.07,2.06),'metal',.012)
  for zz in [.60,2.20]:
   for xx in [-side*.1,-side*.76]:cylinder('Doors','GateBolt',(xx,-.09,zz),.03,.022,'metal',(math.pi/2,0,0))
  ring('Doors','GateHandle',(-side*.77,-.10,1.4),.074,.012,'metal',(math.pi/2,0,0))
  from mathutils import Matrix
  R=Matrix.Rotation(angle,4,'Z')
  for o in g.parts['Doors'][len(before):]:o.matrix_world=Matrix.Translation(hinge)@R@o.matrix_world
 # Interior shelves, pallets, crates and barrels; real depth through open entrance.
 for x in [-1.63,1.63]:
  for y in [.1,1.26]:beam('Goods','RackUpright',(x,y,.45),(x,y,2.2),.085)
  for z in [.52,1.24,1.98]:box('Goods','Shelf',(x,.69,z),(.75,1.48,.075),'wood',.012)
 for x,y,z,sz in [(-1.62,.12,.82,.45),(-1.62,.92,.82,.50),(-1.6,.70,1.52,.44),(1.62,.20,.83,.50),(1.63,1.04,1.52,.48),(.55,1.14,.71,.49),(.58,1.14,1.19,.43),(-.12,.90,.69,.43)]:crate('Goods',(x,y,z),sz)
 for p in [(-.8,.24,.80),(.90,.48,.80),(.27,1.14,.80)]:barrel(p)
 # Front hoist, anchored above the doorway; pivots retained for animation.
 beam('Frame','HoistBeam',(0,-1.82,3.29),(0,-2.28,3.29),.19)
 beam('Frame','HoistBrace',(0,-1.80,2.97),(0,-2.16,3.26),.10)
 cylinder('Gear','Pulley',(0,-2.16,3.15),.13,.08,'metal',(math.pi/2,0,0))
 ring('Gear','PulleyLip',(0,-2.215,3.15),.126,.023,'metal',(math.pi/2,0,0))
 cylinder('Crank','Axle',(.28,-2.17,3.15),.045,.06,'metal',(math.pi/2,0,0))
 beam('Crank','CrankArm',(.28,-2.20,3.15),(.39,-2.20,3.15),.027,material='metal')
 beam('Chain','Rope',(0,-2.20,3.16),(0,-2.20,1.0),.025,material='wood')
 ring('Hook','HookLoop',(0,-2.20,1.03),.08,.017,'metal',(math.pi/2,0,0))
 if not ruined:crate('Hook',(0,-2.20,.77),.42)
 # Lantern frames, small roofs, luminous panes and brackets.
 for side in [-1,1]:
  x=side*2.13;y=-2.04;z=2.03
  beam('Hardware','LampBracket',(x,-1.8,2.38),(x,-2.22,2.38),.05,material='metal')
  ring('Lanterns','Hanger',(x,y,z+.26),.053,.009,'metal',(math.pi/2,0,0))
  box('Lanterns','LampBase',(x,y,z-.15),(.22,.22,.05),'metal',.018)
  box('Lanterns','LampRoof',(x,y,z+.17),(.26,.26,.07),'metal',.02)
  for dx in [-.095,.095]:
   for dy in [-.095,.095]:beam('Lanterns','LampRib',(x+dx,y+dy,z-.13),(x+dx,y+dy,z+.15),.02,material='metal')
  if not ruined:box('Glow','LampGlass',(x,y,z),(.17,.17,.24),'glass',.004)
 if ruined:
  for j in range(28):
   x=random.uniform(-2.65,2.65);y=random.uniform(-2.90,-2.0)
   o=box('Debris','BrokenBoard',(x,y,random.uniform(.045,.16)),(random.uniform(.23,.90),.14,.05),'wood',.005);o.rotation_euler.z=random.uniform(0,6.28)
  for j in range(10):brick('Debris','Rubble',(random.uniform(-2.5,2.5),random.uniform(-2.6,-2.05),.11),(.19,.22,.16))
  beam('Debris','FallenRafter',(2.38,-1.20,.10),(2.0,-1.10,1.10),.15)
 # Cleared-frame canvas: subdued green cloth on both slopes, seams and ties.
 for side in [-1,1]:
  slope=Vector((side*RX,0,EAVE-PEAK));normal=Vector((side*(PEAK-EAVE),0,RX)).normalized()
  for col in range(12):
   yy=-RY+(col+.5)*RY*2/12
   prism('Tarp','CanvasPanel',[(-.18,-slope.length/2),(.18,-slope.length/2),(.18,slope.length/2),(-.18,slope.length/2)],.018,(side*RX/2,yy,(EAVE+PEAK)/2+.1),(0,1,0),slope.normalized(),normal,'tarp')
  for yy in [-1.9,1.9]:beam('Tarp','Tie',(side*RX,yy,EAVE+.1),(side*2.2,yy,2.2),.017,material='tarp')
 # Join only per architectural part; moving parts keep local pivots.
 for name,items in g.parts.items():
  bpy.ops.object.select_all(action='DESELECT')
  for o in items:o.select_set(True)
  bpy.context.view_layer.objects.active=items[0]
  if len(items)>1:bpy.ops.object.join()
  o=items[0];o.name=name;bpy.context.scene.cursor.location=pivots.get(name,(0,0,0));bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
  bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 bpy.ops.object.select_all(action='DESELECT');objects=[bpy.data.objects[n] for n in g.parts]
 for o in objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=os.path.join(g.OUT,'warehouse_'+which+'.gltf'),export_format='GLTF_SEPARATE',use_selection=True,export_vertex_color='ACTIVE',export_yup=True)
 print(which,'triangles',sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'parts',len(objects),flush=True)
 for o in objects:bpy.data.objects.remove(o,do_unlink=True)
for state in ['ruined','restored']:warehouse(state)
