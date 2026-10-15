extends SceneTree
## Standalone lake art only. Does NOT change any game scene, scripts or configuration.
## godot --headless --path . -s tools/import_lake_model.gd -- BUILD_DIRECTORY
const OUT := "res://assets/models/lake/"
var materials := {}
func _initialize() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.is_empty():push_error("Specify lake build directory");quit(1);return
 PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
 var doc:=GLTFDocument.new();var state:=GLTFState.new()
 if doc.append_from_file(args[0].path_join("lake_model.gltf"),state)!=OK:push_error("Lake glTF missing");quit(1);return
 var scene:=doc.generate_scene(state);scene.name="LakeModel"
 var meshes:=scene.find_children("*","MeshInstance3D",true,false)
 var total:=0
 for mi in meshes:
  # Split big botanical meshes by triangles: every text resource is portable <1 MB.
  var source:ArrayMesh=mi.mesh
  var original_name:String=mi.name
  var group:=Node3D.new();group.name=mi.name;mi.get_parent().add_child(group)
  var part:=0
  for surf in source.get_surface_count():
   var mat_:=_material(source.surface_get_material(surf),mi.name=="WaterSurface")
   var arr:Array=source.surface_get_arrays(surf)
   var indices:PackedInt32Array=arr[Mesh.ARRAY_INDEX]
   if indices.is_empty():
    indices.resize(arr[Mesh.ARRAY_VERTEX].size())
    for k in indices.size():indices[k]=k
   for first in range(0,indices.size(),12000):
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat_)
    for k in range(first,mini(first+12000,indices.size())):
     var ix:=indices[k]
     if arr[Mesh.ARRAY_NORMAL]!=null:st.set_normal(arr[Mesh.ARRAY_NORMAL][ix])
     if arr[Mesh.ARRAY_TEX_UV]!=null:st.set_uv(arr[Mesh.ARRAY_TEX_UV][ix])
     if arr[Mesh.ARRAY_COLOR]!=null:st.set_color(arr[Mesh.ARRAY_COLOR][ix])
     st.add_vertex(arr[Mesh.ARRAY_VERTEX][ix])
    st.index();st.generate_tangents()
    var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES);mesh.surface_set_material(0,mat_)
    var path:=OUT+mi.name.to_snake_case()+"_%02d_mesh.tres"%part
    ResourceSaver.save(mesh,path)
    var instance:=MeshInstance3D.new();instance.name="Part%02d"%part;instance.mesh=load(path)
    if mi.name=="WaterSurface":instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;instance.extra_cull_margin=.10
    group.add_child(instance);total+=mesh.surface_get_array_index_len(0)/3;part+=1
  print(mi.name," ",part," parts")
  mi.get_parent().remove_child(mi);mi.free();group.name=original_name
 owner_recursive(scene,scene)
 var packed:=PackedScene.new();packed.pack(scene);ResourceSaver.save(packed,OUT+"lake_model.tscn")
 scene.free();print("LAKE IMPORT OK ",total," triangles");quit()
func _material(src:Material,is_water:bool)->Material:
 if is_water:
  if not materials.has("water"):
   var m:=ShaderMaterial.new();m.shader=load(OUT+"lake_water.gdshader");ResourceSaver.save(m,OUT+"lake_water_material.tres");materials["water"]=load(OUT+"lake_water_material.tres")
  return materials["water"]
 var key:=src.resource_name.to_snake_case()
 if materials.has(key):return materials[key]
 var m:=src.duplicate() as StandardMaterial3D
 for prop in ["albedo_texture","normal_texture","roughness_texture"]:
  var tex:Texture2D=m.get(prop)
  if tex:
   var img:=tex.get_image();img.convert(Image.FORMAT_RGBA8);img.generate_mipmaps()
   var portable:=PortableCompressedTexture2D.new();portable.create_from_image(img,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,prop=="normal_texture",.9)
   var path:String=OUT+key+"_"+prop+".tres";ResourceSaver.save(portable,path);m.set(prop,load(path))
 m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 m.cull_mode=BaseMaterial3D.CULL_DISABLED
 m.vertex_color_use_as_albedo=key in ["lake_leaves","lake_grasses","lake_pebbles"]
 ResourceSaver.save(m,OUT+key+"_material.tres");materials[key]=load(OUT+key+"_material.tres");return materials[key]
func owner_recursive(node:Node,root_:Node)->void:
 for child in node.get_children():child.owner=root_;owner_recursive(child,root_)
