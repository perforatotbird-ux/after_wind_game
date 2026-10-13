extends SceneTree
## Собственная игровая мотыга. Ось Y вдоль черенка, хват в начале координат.
func _initialize():
 PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
 var root_:=Node3D.new();root_.name='Hoe'
 var wood:=StandardMaterial3D.new();wood.albedo_color=Color('#bda88f');wood.roughness=.88;wood.albedo_texture=load('res://assets/models/campfire/campfire_wood_texture.tres')
 var metal:=StandardMaterial3D.new();metal.albedo_color=Color('#596570');metal.metallic=.72;metal.roughness=.48
 var edge:=StandardMaterial3D.new();edge.albedo_color=Color('#a6b2b9');edge.metallic=.8;edge.roughness=.3
 var leather:=StandardMaterial3D.new();leather.albedo_color=Color('#39291d');leather.roughness=.96
 cylinder(root_,'OakHandle',.028,.025,1.42,Vector3(0,.48,0),wood,14)
 cylinder(root_,'LowerGrip',.030,.030,.23,Vector3(0,-.075,0),leather,14)
 cylinder(root_,'UpperGrip',.031,.030,.16,Vector3(0,.38,0),leather,14)
 for i in range(6):cylinder(root_,'Wrap'+str(i),.032,.032,.009,Vector3(0,-.17+i*.037,0),wood,14)
 cylinder(root_,'HeadFerrule',.044,.039,.16,Vector3(0,1.12,0),metal,12)
 # Кованое слегка вогнутое полотно: расширение к режущей кромке, толщина 12 мм.
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var vs:=[Vector3(-.055,1.17,0),Vector3(.055,1.17,0),Vector3(-.16,1.13,.28),Vector3(.16,1.13,.28),Vector3(-.175,1.09,.35),Vector3(.175,1.09,.35)]
 for side in [-1,1]:
  for tri in [[0,2,1],[1,2,3],[2,4,3],[3,4,5]]:
   var ids:Array=tri.duplicate();if side<0:ids.reverse()
   for idx in ids:st.add_vertex(vs[idx]+Vector3(0,side*.006,0))
 for pair in [[0,1],[1,3],[3,5],[5,4],[4,2],[2,0]]:
  var a:Vector3=vs[pair[0]];var b:Vector3=vs[pair[1]]
  for v in [a+Vector3(0,.006,0),a-Vector3(0,.006,0),b+Vector3(0,.006,0),b+Vector3(0,.006,0),a-Vector3(0,.006,0),b-Vector3(0,.006,0)]:st.add_vertex(v)
 st.generate_normals();var blade:=MeshInstance3D.new();blade.name='ForgedBlade';blade.mesh=st.commit();blade.material_override=metal;root_.add_child(blade)
 var bevel:=MeshInstance3D.new();bevel.name='SharpenedEdge';var box:=BoxMesh.new();box.size=Vector3(.35,.012,.025);bevel.mesh=box;bevel.position=Vector3(0,1.09,.35);bevel.material_override=edge;root_.add_child(bevel)
 own(root_,root_);var packed:=PackedScene.new();packed.pack(root_)
 ResourceSaver.save(packed,'res://scenes/tools/hoe_inhand.tscn')
 # Старые имена сцен оставлены как совместимые оболочки для сейвов/инструментов.
 for path in ['res://scenes/tools/shovel_inhand.tscn','res://scenes/tools/shovel_model.tscn']:
  var wrapper_text := "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://scenes/tools/hoe_inhand.tscn\" id=\"1_hoe\"]\n\n[node name=\"Hoe\" instance=ExtResource(\"1_hoe\")]\n"
  var file := FileAccess.open(path, FileAccess.WRITE);file.store_string(wrapper_text);file.close()
 var imported=load('res://assets/models/tools/pickaxe_inhand.glb').instantiate()
 var mesh:Mesh=imported.find_child('LIB_pickaxe',true,false).mesh
 ResourceSaver.save(mesh,'res://assets/models/tools/pickaxe_equipped_mesh.tres')
 var icon:=PortableCompressedTexture2D.new();icon.create_from_image(load('res://scripts/ui/item_icons.gd').draw_icon('shovel'),PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
 ResourceSaver.save(icon,'res://assets/tools/hoe_icon.tres')
 imported.free();root_.free();quit()
func cylinder(r:Node3D,n:String,top:float,bottom:float,h:float,p:Vector3,m:Material,sides:int):
 var mesh:=CylinderMesh.new();mesh.top_radius=top;mesh.bottom_radius=bottom;mesh.height=h;mesh.radial_segments=sides;mesh.rings=1
 var node:=MeshInstance3D.new();node.name=n;node.mesh=mesh;node.material_override=m;node.position=p;r.add_child(node)
func own(n:Node,r:Node):
 for c in n.get_children():c.owner=r;own(c,r)
