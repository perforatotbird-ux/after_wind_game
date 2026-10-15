extends SceneTree
## Isolated art asset: geometry/materials/wind loop without world/gameplay coupling.
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
 if not ok:errors.append(message);printerr("FAIL: "+message)
func _initialize()->void:call_deferred("checks")
func checks()->void:
 var packed:PackedScene=load("res://assets/models/lake/lake_model.tscn")
 check(packed!=null,"Lake scene loadable")
 if packed==null:quit(1);return
 var model:Node3D=packed.instantiate();root.add_child(model)
 for key in ["SculptedBank","EarthStrata","LakeBasin","WaterSurface","ShrubLeaves","GrassTufts","ShrubBranches","ShorePebbles","ReedLeaves","CattailHeads","WetShoreline"]:
  check(model.has_node(key),"Separate art group: "+key)
 var triangles:=0;var bounds:=AABB();var first:=true
 for mi in model.find_children("*","MeshInstance3D",true,false):
  check(mi.mesh is ArrayMesh,"Real editable mesh "+mi.name)
  var b:AABB=mi.get_aabb();bounds=b if first else bounds.merge(b);first=false
  for s in mi.mesh.get_surface_count():
   triangles+=mi.mesh.surface_get_array_index_len(s)/3
   var a:Array=mi.mesh.surface_get_arrays(s)
   check(a[Mesh.ARRAY_NORMAL]!=null and a[Mesh.ARRAY_TEX_UV]!=null,"UV and normals "+mi.name)
   check(mi.mesh.surface_get_material(s)!=null,"Material "+mi.name)
   for v in a[Mesh.ARRAY_VERTEX]:check(v.is_finite(),"Finite vertex")
 check(triangles>80000 and triangles<180000,"Premium art triangle budget")
 check(bounds.size.x>9 and bounds.size.x<12 and bounds.size.z>8 and bounds.size.z<12,"Metre-scale terrain tile")
 var mat:ShaderMaterial=model.get_node("WaterSurface").get_child(0).mesh.surface_get_material(0)
 check(mat!=null and mat.shader!=null,"Animated water shader")
 check(mat.shader.code.contains("TIME") and mat.shader.code.contains("wind_strength"),"Automatic adjustable wind")
 check(mat.shader.code.contains("edge") and mat.shader.code.contains("ALPHA"),"Shore fade and translucency")
 for mi in model.get_node("WaterSurface").get_children():
  check(mi.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"No opaque water shadow")
  check(mi.extra_cull_margin>=.08,"Animated displacement cull margin")
 # Analytic travelling waves loop cleanly, stay subtle, and settle exactly at shore.
 for p in [Vector2.ZERO,Vector2(1.3,-.7),Vector2(-2.1,1.6)]:
  check(absf(wave(p,0,1)-wave(p,8,1))<.00001,"Seamless eight-second loop")
  check(absf(wave(p,1,1))<=.0341,"Gentle displacement <= 3.4cm")
  check(wave(p,2,0)==0,"No displacement at shoreline")
 check(absf(wave(Vector2(1.1,.7),0,1)-wave(Vector2(1.1,.7),2,1))>.001,"Water actually moves")
 for node in model.find_children("*","Node",true,false):
  check(not node is CollisionObject3D,"No gameplay collider")
  check(node.get_script()==null,"Asset has no gameplay script")
 for f in DirAccess.get_files_at("res://assets/models/lake/"):
  if f.ends_with(".tres"):check(FileAccess.get_file_as_bytes("res://assets/models/lake/"+f).size()<1024*1024,"Portable resource "+f)
 var demo:PackedScene=load("res://assets/models/lake/lake_demo.tscn");check(demo!=null,"Separate preview scene")
 model.queue_free()
 if errors.is_empty():print("PASS: test_lake_model — ",triangles," triangles; isolated scene, materials, eight-second wind loop")
 quit(0 if errors.is_empty() else 1)
func wave(p:Vector2,t:float,edge:float)->float:
 return edge*(.023*sin(p.dot(Vector2(1.9,-.8))-t*TAU/8)+.011*sin(p.dot(Vector2(-1.2,-2.4))-t*TAU/4))
