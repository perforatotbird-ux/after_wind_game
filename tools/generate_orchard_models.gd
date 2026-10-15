extends SceneTree
## Яблоня и абрикос по yabloko.jpg / abrikos.jpg. Собственные меши и материалы.
## godot --headless --path . -s tools/generate_orchard_models.gd -- EXPORT_DIRECTORY
var out:String
var species:String
var export_dir:String
var rng:=RandomNumberGenerator.new()
var bark_st:SurfaceTool
var leaf_st:SurfaceTool
var mats:Dictionary={}
var canopy_specs:Array=[]
func _init() -> void:
 var args:=OS.get_cmdline_user_args()
 export_dir=args[0] if not args.is_empty() else ProjectSettings.globalize_path('res://outputs/orchard-export/')
 DirAccess.make_dir_recursive_absolute(export_dir)
 PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
 for kind in ['apple','apricot']:
  species=kind;out='res://assets/models/'+species+'/'
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
  rng.seed=57091 if species=='apple' else 91477
  _configure();_materials()
  var tree:=Node3D.new();tree.name=species.capitalize()+'Tree'
  _wood(tree)
  for i in canopy_specs.size():_crown(tree,i)
  _fruits(tree)
  _save_scene(tree,species+'_with_fruit');_export_glb(tree,species+'_with_fruit')
  var fruits:=tree.get_node('Fruits');tree.remove_child(fruits);fruits.free()
  _save_scene(tree,species+'_without_fruit');_export_glb(tree,species+'_without_fruit')
  tree.free()
 print('ORCHARD MODELS OK');quit()
func _configure() -> void:
 if species=='apple':
  canopy_specs=[
   [Vector3(.03,3.35,0),Vector3(.84,.69,.76)],
   [Vector3(-.89,2.90,-.13),Vector3(.82,.69,.72)],
   [Vector3(.89,2.91,-.14),Vector3(.83,.67,.74)],
   [Vector3(-1.33,2.15,.12),Vector3(.61,.53,.58)],
   [Vector3(1.31,2.20,.27),Vector3(.62,.55,.59)],
   [Vector3(-.02,2.78,.62),Vector3(.78,.57,.62)],
   [Vector3(.07,2.87,-.63),Vector3(.79,.58,.64)]
  ]
 else:
  canopy_specs=[
   [Vector3(-.12,2.96,.0),Vector3(.78,.58,.70)],
   [Vector3(-.96,2.44,-.17),Vector3(.77,.53,.65)],
   [Vector3(.91,2.66,-.12),Vector3(.82,.55,.69)],
   [Vector3(-1.13,2.08,.23),Vector3(.54,.40,.52)],
   [Vector3(1.20,2.27,.28),Vector3(.58,.43,.53)],
   [Vector3(.01,2.48,.52),Vector3(.74,.49,.61)],
   [Vector3(.12,2.61,-.53),Vector3(.65,.48,.58)]
  ]
func _materials() -> void:
 mats={}
 var bark:=Image.create(256,512,false,Image.FORMAT_RGB8)
 var bark_col:=Color(.53,.32,.16) if species=='apple' else Color(.39,.28,.17)
 for y in 512:
  for x in 256:
   var u:=float(x)/256;var v:=float(y)/512
   var flow:=u+.014*sin(v*11+u*12)+.009*sin(v*27+u*21)
   var grain:=.043*sin(flow*TAU*24)+.018*sin(flow*TAU*60)+.07*sin(u*TAU*4+sin(v*7)*.42)
   if species=='apricot':grain+=.035*sin(flow*TAU*43+v*3)
   bark.set_pixel(x,y,bark_col*(.96+grain))
 var leaf:=Image.create(256,256,false,Image.FORMAT_RGB8)
 for y in 256:
  for x in 256:
   var u:=float(x)/255;var v:=float(y)/255
   var main_vein:=exp(-pow((u-.5)/.010,2))*.11
   var side_vein:=pow(maxf(0,sin((v-absf(u-.5)*.48)*TAU*6)),24)*.055
   var surface:=.94+.024*sin(u*38+sin(v*19))+.019*sin(v*41+u*13)+main_vein+side_vein
   leaf.set_pixel(x,y,Color(surface,surface,surface))
 for pair in [[bark,'bark'],[leaf,'leaf']]:
  var im:Image=pair[0];im.generate_mipmaps()
  var tex:=PortableCompressedTexture2D.new();tex.create_from_image(im,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,false,.9)
  ResourceSaver.save(tex,out+species+'_'+pair[1]+'_texture.tres')
 for key in ['bark','leaves','fruit','stems']:
  var m:=StandardMaterial3D.new();m.resource_name=species.capitalize()+key.capitalize();m.vertex_color_use_as_albedo=true;m.roughness=.90
  if key=='bark':m.albedo_texture=load(out+species+'_bark_texture.tres')
  if key=='leaves':
   m.albedo_texture=load(out+species+'_leaf_texture.tres');m.cull_mode=BaseMaterial3D.CULL_DISABLED;m.roughness=.88
  if key=='fruit':m.roughness=.40 if species=='apple' else .64;m.metallic_specular=.5 if species=='apple' else .28
  m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
  ResourceSaver.save(m,out+species+'_'+key+'_material.tres');mats[key]=load(out+species+'_'+key+'_material.tres')
func _new_surface() -> SurfaceTool:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);return st
func _save_mesh(parent:Node3D,st:SurfaceTool,name_:String,mat:Material) -> void:
 st.index();var mesh:=st.commit()
 if name_=='Trunk':
  var arrays:=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for i in vertices.size():vertices[i].y=maxf(0.0,vertices[i].y)
  arrays[Mesh.ARRAY_VERTEX]=vertices;mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.surface_set_material(0,mat)
 var path:=out+species+'_'+name_.to_snake_case()+'_mesh.tres';ResourceSaver.save(mesh,path)
 var mi:=MeshInstance3D.new();mi.name=name_;mi.mesh=load(path);parent.add_child(mi)
 print(species,' ',name_,' tris=',mesh.surface_get_array_index_len(0)/3)
func _wood(tree:Node3D) -> void:
 bark_st=_new_surface()
 var points:Array
 if species=='apple':points=_bezier3(Vector3(.02,0,0),Vector3(-.17,.72,.03),Vector3(.12,1.28,-.08),Vector3(.04,2.18,0),14)
 else:points=_bezier3(Vector3(.04,0,0),Vector3(-.45,.66,.11),Vector3(.41,1.42,-.13),Vector3(-.03,2.13,0),16)
 _tube(points,_radii(points.size(),.23,.10,.72),14,Color(.88,.86,.82),Color(1.05,1.03,.99),{'amp':.42,'lobes':5.0,'decay':.26,'phase':.5},false)
 for i in 5:
  var a:=float(i)*TAU/5+.2;var d:=Vector3(cos(a),0,sin(a))
  var root_:=_bezier(Vector3(.02,.19,0),Vector3(.02,.04,0)+d*.22,Vector3(.02,.018,0)+d*rng.randf_range(.29,.40),5)
  _tube(root_,_radii(root_.size(),.095,.008),7,Color(.84,.84,.79),Color(.8,.81,.78))
 for i in canopy_specs.size():
  var c:Vector3=canopy_specs[i][0]
  var start:Vector3=points[6+(i%4)]
  var middle:=start.lerp(c,.48);middle.y-=.14
  var branch:=_bezier(start,middle,c+Vector3(0,-.13,0),9)
  _tube(branch,_radii(branch.size(),.10 if i<3 else .08,.018),9,Color(.94,.94,.91),Color(1,1,1))
  for j in [-1,1]:
   var to:=c+Vector3(j*.34,.13,.18*j)
   var fork:=_bezier(branch[5],c+Vector3(j*.24,-.23,.08*j),to,6)
   _tube(fork,_radii(fork.size(),.047,.009),7,Color(.97,.97,.92),Color(.93,.95,.91))
  # Fine rising shoots visible below the looser canopy.
  for j in 3:
   var at:Vector3=branch[4+j];var twig:=_bezier(at,at+Vector3(.14*(j-1),.17,.08),at+Vector3(.24*(j-1),.39,.16),4)
   _tube(twig,_radii(twig.size(),.021,.005),5,Color(1,1,1),Color(.91,.93,.88))
 _save_mesh(tree,bark_st,'Trunk',mats.bark)
func _crown(tree:Node3D,index_:int) -> void:
 leaf_st=_new_surface()
 var c:Vector3=canopy_specs[index_][0];var r:Vector3=canopy_specs[index_][1]
 # Small interior foliage, not a solid green sphere; branches show through gaps.
 var count:=int(320*r.x*r.z)+55
 var golden:=PI*(3-sqrt(5.0))
 for i in count:
  var y:=1.0-1.98*(i+.5)/count;var a:=i*golden+rng.randf_range(-.17,.17)
  var rr:=sqrt(maxf(0,1-y*y));var n:=Vector3(cos(a)*rr,y,sin(a)*rr)
  var at:=c+n*r*rng.randf_range(.77,1.02)
  _leaf(at,n,rng.randf_range(.24,.33) if species=='apple' else rng.randf_range(.26,.35))
 # Interior leaves prevent hollow-looking clumps while retaining real openings.
 for i in 30:
  var d:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
  _leaf(c+d*r*.54,d,rng.randf_range(.26,.37))
 _save_mesh(tree,leaf_st,'Canopy%d'%index_,mats.leaves)
func _leaf(at:Vector3,n:Vector3,size:float) -> void:
 var t:=Vector3.DOWN-n*Vector3.DOWN.dot(n)
 if t.length()<.08:t=Vector3(cos(rng.randf()*TAU),0,sin(rng.randf()*TAU))
 t=t.normalized().rotated(n,rng.randf_range(-1.35,1.35))
 t=(t*.93+n*.20).normalized()
 if rng.randf()<.22:t=-t # Leaf sprays project up/out, not only tiled downward.
 var b:=n.cross(t).normalized()
 var shade:=clampf(n.y*.31+.65,0,1)
 var dark:=Color(.095,.235,.075) if species=='apple' else Color(.15,.245,.064)
 var light:=Color(.29,.42,.13) if species=='apple' else Color(.34,.445,.16)
 var color:=dark.lerp(light,shade)*rng.randf_range(.84,1.12)
 var mid:=at+t*size*.09+n*size*.065
 var contour:Array=[]
 for j in 12:
  var angle:float=TAU*j/12
  var length:float=.50*cos(angle)+.055*pow(maxf(0,cos(angle)),8)
  var width:float=(.30 if species=='apple' else .405)*sin(angle)*(1-.12*cos(angle))
  contour.append(Vector2(length,width))
 for k in contour.size():
  var a:Vector2=contour[k];var d:Vector2=contour[(k+1)%contour.size()]
  var p1:=at+t*a.x*size+b*a.y*size;var p2:=at+t*d.x*size+b*d.y*size
  var normal:Vector3=(n*.9+Vector3.UP*.12).normalized()
  _tri(leaf_st,[mid,p1,p2],[normal,normal,normal],[color*1.05,color*.94,color*.94],[Vector2(.5,.56),Vector2(a.y+.5,(a.x+.5)/1.07),Vector2(d.y+.5,(d.x+.5)/1.07)])
func _fruits(tree:Node3D) -> void:
 var holder:=Node3D.new();holder.name='Fruits';tree.add_child(holder)
 var st:=_new_surface();bark_st=_new_surface()
 for i in 42:
  var k:=i%canopy_specs.size();var c:Vector3=canopy_specs[k][0];var r:Vector3=canopy_specs[k][1]
  var turn:float=floor(float(i)/7);var a:float=TAU*turn/4.0+float(k)*.31
  var n:=Vector3(cos(a),-.57,sin(a)).normalized();var at:=c+n*r*1.10
  if i>=28:
   var side:float=-.35 if i<35 else .37
   n=Vector3(side,.20,1).normalized();at=c+n*r*1.12
  var radius:=rng.randf_range(.105,.132) if species=='apple' else rng.randf_range(.086,.108)
  var pos:=at+Vector3(0,-.18,0)
  _fruit_mesh(st,pos,radius,rng.randf())
  var stem:=_bezier(at,at+Vector3(.025,-.045,.015),pos+Vector3(0,radius*.90,0),3)
  _tube(stem,[.011,.009,.008,.006],6,Color(.28,.25,.12),Color(.24,.21,.095))
  # Tiny dark calyx at the apple's recessed underside.
  if species=='apple':
   var p:=pos-Vector3(0,radius*.80,0)
   for j in 5:
    var ang:=TAU*j/5;var tip:=p+Vector3(cos(ang)*radius*.18,-.003,sin(ang)*radius*.18)
    _tri(st,[p+Vector3(-.007,0,0),tip,p+Vector3(.007,0,0)],[Vector3.DOWN,Vector3.DOWN,Vector3.DOWN],[Color(.19,.14,.045),Color(.27,.18,.047),Color(.19,.14,.045)],[Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
 _save_mesh(holder,st,'Apples' if species=='apple' else 'Apricots',mats.fruit)
 _save_mesh(holder,bark_st,'Stems',mats.stems)
func _fruit_mesh(st:SurfaceTool,c:Vector3,r:float,ripeness:float) -> void:
 var segs:=12;var rings:=10
 for y in rings:
  for x in segs:
   var ps:Array=[];var ns:Array=[];var cs:Array=[];var uv:Array=[]
   for step in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
    var a:float=TAU*(x+step.x)/segs;var th:float=PI*(y+step.y)/rings
    var normal:=Vector3(sin(th)*cos(a),cos(th),sin(th)*sin(a))
    var point:=normal*r;var color:Color
    if species=='apple':
     var lobe:float=1+.045*cos(a*5)*pow(sin(th),2)
     point.x*=lobe;point.z*=lobe
     point.y=r*(.91*cos(th)-.16*exp(-pow(th/.35,2))+.12*exp(-pow((PI-th)/.35,2)))
     color=Color(.34,.44,.075).lerp(Color(.74,.43,.060),clampf(ripeness*1.6,0,1))
     var blush:float=clampf(normal.dot(Vector3(.30,.05,.93))*.65+.45,0,1)*clampf((ripeness-.25)*1.8,0,1)
     color=color.lerp(Color(.67,.045,.027),blush)
     color*=.95+.035*sin(a*37+th*8)
    else:
     var seam:float=exp(-pow(sin(a-PI/2)/.12,2))*pow(sin(th),2)
     point.x*=1-.06*seam;point.z*=1-.06*seam;point.y*=1.13
     color=Color(.72,.40,.055).lerp(Color(.80,.30,.028),ripeness*.55)
     var cheek:float=maxf(0,normal.dot(Vector3(.72,.05,.5)))*ripeness*.25
     color=color.lerp(Color(.70,.17,.021),cheek)*(1-.08*seam)
    ps.append(c+point);ns.append(normal);cs.append(color);uv.append(Vector2(float(x+step.x)/segs,float(y+step.y)/rings))
   _tri(st,[ps[0],ps[1],ps[2]],[ns[0],ns[1],ns[2]],[cs[0],cs[1],cs[2]],[uv[0],uv[1],uv[2]])
   _tri(st,[ps[0],ps[2],ps[3]],[ns[0],ns[2],ns[3]],[cs[0],cs[2],cs[3]],[uv[0],uv[2],uv[3]])
func _save_scene(tree:Node3D,name_:String) -> void:
 _owners(tree,tree);var packed:=PackedScene.new();packed.pack(tree);ResourceSaver.save(packed,out+name_+'.tscn')
func _owners(n:Node,r:Node) -> void:
 for c in n.get_children():c.owner=r;_owners(c,r)
func _export_glb(tree:Node3D,name_:String) -> void:
 var doc:=GLTFDocument.new();var state:=GLTFState.new()
 var result:=doc.append_from_scene(tree,state)
 if result==OK:result=doc.write_to_filesystem(state,export_dir.path_join(name_+'.glb'))
 if result!=OK:push_error('GLB export failed '+str(result));quit(1)

## Треугольник с правильным (по часовой) обходом относительно средней нормали.
func _tri(st: SurfaceTool, p: Array, n: Array, c: Array, uv: Array = []) -> void:
 var order := [0, 1, 2]
 var avg: Vector3 = (n[0] + n[1] + n[2])
 if ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).dot(avg) > 0.0:
  order = [0, 2, 1]
 for i in order:
  st.set_color(c[i])
  st.set_normal((n[i] as Vector3).normalized())
  if not uv.is_empty():
   st.set_uv(uv[i])
  st.add_vertex(p[i])

func _bezier(a: Vector3, b: Vector3, c: Vector3, n: int) -> Array:
 var out: Array = []
 for i in n + 1:
  var t := float(i) / n
  out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
 return out

func _bezier3(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: int) -> Array:
 var out: Array = []
 for i in n + 1:
  var t := float(i) / n
  var ab := a.lerp(b, t); var bc := b.lerp(c, t); var cd := c.lerp(d, t)
  out.append(ab.lerp(bc, t).lerp(bc.lerp(cd, t), t))
 return out

## Трубка вдоль полилинии: радиусы по точкам, параллельный перенос рамки.
## flare: {"amp", "lobes", "decay", "phase"} — корневые наплывы у основания.
func _tube(pts: Array, rad: Array, sides: int, col0: Color, col1: Color, flare: Dictionary = {}, cap := true) -> void:
 var n := pts.size()
 var T: Array = []
 for i in n:
  var a: Vector3 = pts[maxi(i - 1, 0)]
  var b: Vector3 = pts[mini(i + 1, n - 1)]
  T.append((b - a).normalized())
 var N0: Vector3 = (T[0] as Vector3).cross(Vector3.RIGHT if absf((T[0] as Vector3).x) < 0.9 else Vector3.FORWARD).normalized()
 var frames: Array = []
 var Nc := N0
 for i in n:
  var t: Vector3 = T[i]
  Nc = (Nc - t * Nc.dot(t)).normalized()
  frames.append([Nc, t.cross(Nc).normalized()])
 var u_rep := maxf(1.0, roundf(TAU * float(rad[0]) / 0.45))
 var rings: Array = []
 var s_len := 0.0
 for i in n:
  if i > 0:
   s_len += (pts[i] - pts[i - 1] as Vector3).length()
  var ring: Array = []
  var h: float = (pts[i] as Vector3).y
  for j in sides + 1:
   var ang := TAU * j / sides
   var dir: Vector3 = frames[i][0] * cos(ang) + frames[i][1] * sin(ang)
   var r: float = rad[i]
   if not flare.is_empty():
    var lob := pow(maxf(0.0, cos(flare["lobes"] * ang + flare["phase"])), 2.0)
    r *= 1.0 + flare["amp"] * exp(-h / flare["decay"]) * (0.3 + 0.7 * lob)
   var col := col0.lerp(col1, float(i) / maxf(1.0, n - 1))
   ring.append([pts[i] + dir * r, dir, Vector2(u_rep * j / sides, s_len / 0.9), col])
  rings.append(ring)
 for i in n - 1:
  for j in sides:
   var a: Array = rings[i][j]; var b: Array = rings[i + 1][j]
   var c: Array = rings[i + 1][j + 1]; var d: Array = rings[i][j + 1]
   _tri(bark_st, [a[0], b[0], c[0]], [a[1], b[1], c[1]], [a[3], b[3], c[3]], [a[2], b[2], c[2]])
   _tri(bark_st, [a[0], c[0], d[0]], [a[1], c[1], d[1]], [a[3], c[3], d[3]], [a[2], c[2], d[2]])
 if cap:
  var tip: Vector3 = pts[n - 1] + (T[n - 1] as Vector3) * float(rad[n - 1]) * 1.2
  var last: Array = rings[n - 1]
  for j in sides:
   _tri(bark_st, [last[j][0], last[j + 1][0], tip], [last[j][1], last[j + 1][1], T[n - 1]],
    [last[j][3], last[j + 1][3], last[j][3]], [last[j][2], last[j + 1][2], last[j][2]])

func _radii(n: int, r0: float, r1: float, pw := 1.0) -> Array:
 var out: Array = []
 for i in n:
  out.append(lerpf(r0, r1, pow(float(i) / (n - 1), pw)))
 return out

