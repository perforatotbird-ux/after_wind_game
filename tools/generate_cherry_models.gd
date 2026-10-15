extends SceneTree
## Две вишни по референсу: единая архитектура, плоды отдельным мешем.
## Godot --headless --path . -s tools/generate_cherry_models.gd
const OUT := "res://assets/models/cherry/"
var build_dir:String
var rng := RandomNumberGenerator.new()
var bark_st: SurfaceTool
var leaf_st: SurfaceTool
var mats := {}
var canopy_specs := [
 [Vector3(-0.12,3.60,-0.04),Vector3(0.63,0.57,0.61)],
 [Vector3(-0.82,3.02,-0.12),Vector3(0.78,0.62,0.68)],
 [Vector3(0.73,3.07,-0.17),Vector3(0.82,0.64,0.71)],
 [Vector3(-0.12,2.88,0.58),Vector3(0.78,0.58,0.64)],
 [Vector3(-1.32,2.34,0.22),Vector3(0.54,0.44,0.50)],
 [Vector3(1.22,2.43,0.31),Vector3(0.56,0.46,0.51)],
 [Vector3(0.11,2.96,-0.69),Vector3(0.63,0.57,0.58)]
]
func _init() -> void:
 rng.seed=42071
 PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 var args:=OS.get_cmdline_user_args()
 build_dir=args[0] if not args.is_empty() else ProjectSettings.globalize_path('res://outputs/cherry-export/')
 DirAccess.make_dir_recursive_absolute(build_dir)
 _materials()
 var tree:=Node3D.new();tree.name='CherryTree'
 _wood(tree)
 for i in canopy_specs.size(): _crown(tree,i)
 _fruit(tree)
 _save_scene(tree,'cherry_with_fruit')
 _export_glb(tree,build_dir.path_join('cherry_with_fruit.glb'))
 var fruits:=tree.get_node('Fruits');tree.remove_child(fruits);fruits.free()
 _save_scene(tree,'cherry_without_fruit')
 _export_glb(tree,build_dir.path_join('cherry_without_fruit.glb'))
 tree.free()
 print('CHERRY MODELS OK')
 quit()
func _materials() -> void:
 var im:=Image.create(256,512,false,Image.FORMAT_RGB8)
 for y in 512:
  for x in 256:
   var u:=float(x)/256;var v:=float(y)/512
   var flow:=u+0.012*sin(v*13+u*11)+0.006*sin(v*32+u*17)
   var grain:=0.045*sin(flow*TAU*24)+0.017*sin(flow*TAU*67)+0.009*sin(flow*TAU*110+v*8)
   var broad:=0.06*sin(u*TAU*4+sin(v*8)*0.5)
   im.set_pixel(x,y,Color(0.60,0.365,0.19)*(0.94+grain+broad))
 im.generate_mipmaps()
 var tex:=PortableCompressedTexture2D.new();tex.create_from_image(im,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,false,0.9)
 ResourceSaver.save(tex,OUT+'cherry_bark_texture.tres')
 for key in ['bark','leaves','fruit','stems']:
  var m:=StandardMaterial3D.new();m.resource_name='Cherry'+key.capitalize();m.vertex_color_use_as_albedo=true
  m.roughness=0.88
  if key=='bark':m.albedo_texture=load(OUT+'cherry_bark_texture.tres')
  if key=='leaves':m.cull_mode=BaseMaterial3D.CULL_DISABLED;m.roughness=0.86
  if key=='fruit':m.roughness=0.27;m.metallic_specular=0.65
  ResourceSaver.save(m,OUT+'cherry_'+key+'_material.tres');mats[key]=load(OUT+'cherry_'+key+'_material.tres')
func _new_surface() -> SurfaceTool:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);return st
func _save_mesh(tree:Node3D,st:SurfaceTool,name_:String,mat:Material) -> void:
 st.index();var mesh:=st.commit()
 if name_=='Trunk':
  var arrays:=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for i in vertices.size():vertices[i].y=maxf(0.0,vertices[i].y)
  arrays[Mesh.ARRAY_VERTEX]=vertices;mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.surface_set_material(0,mat)
 var path:=OUT+'cherry_'+name_.to_snake_case()+'_mesh.tres'
 ResourceSaver.save(mesh,path)
 var mi:=MeshInstance3D.new();mi.name=name_;mi.mesh=load(path);tree.add_child(mi)
 print(name_,' tris ',mesh.surface_get_array_index_len(0)/3,' bounds ',mesh.get_aabb())
func _wood(tree:Node3D) -> void:
 bark_st=_new_surface()
 var points:=_bezier3(Vector3(-0.08,0,0),Vector3(-0.66,1.04,0.14),Vector3(0.51,1.93,-0.05),Vector3(-0.1,2.72,0),18)
 _tube(points,_radii(points.size(),0.25,0.095,0.65),14,Color(0.83,0.82,0.77),Color(1.1,1.05,0.96),{'amp':0.65,'lobes':5.0,'decay':0.25,'phase':0.4},false)
 for i in 5:
  var a:=float(i)*TAU/5+0.2
  var d:=Vector3(cos(a),0,sin(a))
  var pts:=_bezier(Vector3(-.08,.22,0),Vector3(-.08,.04,0)+d*.35,Vector3(-.08,.015,0)+d*rng.randf_range(.43,.57),6)
  _tube(pts,_radii(pts.size(),.14,.009),7,Color(.84,.82,.76),Color(.75,.75,.73))
 for i in canopy_specs.size():
  var c:Vector3=canopy_specs[i][0]
  var start:Vector3=points[10 if i>=4 else 13]
  var mid:=start.lerp(c,.46);mid.y-=.14
  var branch:=_bezier(start,mid,c-Vector3(0,.12,0),9)
  _tube(branch,_radii(branch.size(),.10 if i<4 else .074,.024),8,Color(.92,.9,.85),Color(1,1,1))
  for j in [-1,1]:
   var fork:=_bezier(branch[6],c+Vector3(j*.26,-.13,.1*j),c+Vector3(j*.34,.20,.14*j),4)
   _tube(fork,_radii(fork.size(),.035,.007),6,Color(1,1,1),Color(.87,.9,.84))
 _save_mesh(tree,bark_st,'Trunk',mats.bark)
func _crown(tree:Node3D,index_:int) -> void:
 leaf_st=_new_surface()
 var c:Vector3=canopy_specs[index_][0];var r:Vector3=canopy_specs[index_][1]
 # Low-poly dark interior is covered by individual ridged lanceolate leaves.
 _ellipsoid(leaf_st,c,r*.78,16,8,Color(.105,.25,.055),false)
 var count:=int(260*r.x*r.z)+52
 var golden:=PI*(3-sqrt(5.0))
 for i in count:
  var y:=1.0-1.96*(i+.5)/count
  var a:=i*golden+rng.randf_range(-.13,.13)
  var rr:=sqrt(maxf(0,1-y*y))
  var n:=Vector3(cos(a)*rr,y,sin(a)*rr)
  var at:=c+n*r*rng.randf_range(.87,1.02)
  _leaf(at,n,rng.randf_range(.27,.38))
 _save_mesh(tree,leaf_st,'Canopy%d'%index_,mats.leaves)
func _leaf(at:Vector3,n:Vector3,size:float) -> void:
 var down:=Vector3.DOWN-n*Vector3.DOWN.dot(n)
 if down.length()<.1:down=Vector3(cos(rng.randf()*TAU),0,sin(rng.randf()*TAU))
 var t:Vector3=(down.normalized()*.93+n*.27).normalized()
 var b:Vector3=n.cross(t).normalized()
 var shade:=clampf(n.y*.40+.58,0,1)
 var color:=Color(.09,.225,.05).lerp(Color(.23,.41,.075),shade)*rng.randf_range(.86,1.08)
 var mid:=at+t*size*.22+n*size*.075
 var outline:=[Vector2(-.5,0),Vector2(-.24,.29),Vector2(.11,.32),Vector2(.5,0),Vector2(.11,-.32),Vector2(-.24,-.29)]
 for k in outline.size():
  var a:Vector2=outline[k];var d:Vector2=outline[(k+1)%outline.size()]
  var p1:=at+t*(a.x+.15)*size+b*a.y*size
  var p2:=at+t*(d.x+.15)*size+b*d.y*size
  var normal:Vector3=(n*.9+Vector3.UP*.18).normalized()
  _tri(leaf_st,[mid,p1,p2],[normal,normal,normal],[color*1.09,color*.83,color*.89],[Vector2(.5,.5),Vector2(a.y+.5,a.x+.5),Vector2(d.y+.5,d.x+.5)])
func _ellipsoid(st:SurfaceTool,c:Vector3,r:Vector3,segs:int,rings:int,color:Color,gloss:bool) -> void:
 for y in rings:
  for x in segs:
   var ps:=[];var ns:=[];var cs:=[];var uv:=[]
   for step in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
    var a:float=TAU*(x+step.x)/segs;var th:float=PI*(y+step.y)/rings
    var n:=Vector3(sin(th)*cos(a),cos(th),sin(th)*sin(a))
    ps.append(c+n*r);ns.append(n)
    cs.append(color*(1.0 if gloss else .8+.2*clampf(n.y+.2,0,1)))
    uv.append(Vector2(float(x+step.x)/segs,float(y+step.y)/rings))
   _tri(st,[ps[0],ps[1],ps[2]],[ns[0],ns[1],ns[2]],[cs[0],cs[1],cs[2]],[uv[0],uv[1],uv[2]])
   _tri(st,[ps[0],ps[2],ps[3]],[ns[0],ns[2],ns[3]],[cs[0],cs[2],cs[3]],[uv[0],uv[2],uv[3]])
func _fruit(tree:Node3D) -> void:
 var root_:Node3D=Node3D.new();root_.name='Fruits';tree.add_child(root_)
 var st:=_new_surface();bark_st=_new_surface()
 for i in 35:
  var k:=i%canopy_specs.size();var c:Vector3=canopy_specs[k][0];var r:Vector3=canopy_specs[k][1]
  var a:float=TAU*floor(float(i)/7)/4.0+float(k)*.45
  var dir:=Vector3(cos(a),-.66,sin(a)).normalized()
  var attachment:=c+dir*r*1.11
  if i>=28:
   dir=Vector3(.10,.24,1).normalized();attachment=c+dir*r*1.22
  for j in [-1,1]:
   var fruit:=attachment+Vector3(j*.052,-.18-rng.randf()*.03,.035*j)
   var radius:=rng.randf_range(.055,.067)
   _ellipsoid(st,fruit,Vector3(radius,radius*.94,radius),12,8,Color(.67,.012,.031).lerp(Color(.83,.027,.042),rng.randf()),true)
   _tube(_bezier(attachment,attachment+Vector3(.02*j,-.08,.02),fruit+Vector3(0,radius*.85,0),3),[.008,.007,.006,.005],5,Color(.26,.28,.055),Color(.22,.24,.042))
 _save_mesh(root_,st,'Cherries',mats.fruit)
 _save_mesh(root_,bark_st,'Stems',mats.stems)
func _save_scene(tree:Node3D,name_:String) -> void:
 _owners(tree,tree);var packed:=PackedScene.new();packed.pack(tree);ResourceSaver.save(packed,OUT+name_+'.tscn')
func _owners(n:Node,r:Node) -> void:
 for c in n.get_children():c.owner=r;_owners(c,r)
func _export_glb(tree:Node3D,path:String) -> void:
 var doc:=GLTFDocument.new();var state:=GLTFState.new()
 var result:=doc.append_from_scene(tree,state)
 if result==OK:result=doc.write_to_filesystem(state,path)
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

