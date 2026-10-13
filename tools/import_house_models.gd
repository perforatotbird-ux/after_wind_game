extends SceneTree
## Godot --headless --path . -s tools/import_house_models.gd -- BUILD_DIR
const OUT := 'res://assets/models/house/'
var materials:={}
var textures:={}
func _initialize()->void:
 var args:=OS.get_cmdline_user_args()
 if args.is_empty():push_error('Укажите папку сборки дома');quit(1);return
 PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 for state_name in ['ruined','restored']:
  var doc:=GLTFDocument.new();var state:=GLTFState.new()
  if doc.append_from_file(args[0].path_join('house_'+state_name+'.gltf'),state)!=OK:push_error('House glTF missing');quit(1);return
  var scene:=doc.generate_scene(state);scene.name='House'+state_name.capitalize()
  scene.set_script(load('res://scripts/buildings/house_visual.gd'));scene.set('house_stage',0 if state_name=='ruined' else 2)
  var total:=0
  for mi in scene.find_children('*','MeshInstance3D',true,false):
   var mesh:=ArrayMesh.new()
   for s in mi.mesh.get_surface_count():
    var src:=mi.mesh.surface_get_material(s) as StandardMaterial3D
    var key:=src.resource_name.to_snake_case()
    if not materials.has(key):
     var mat:=src.duplicate() as StandardMaterial3D;mat.vertex_color_use_as_albedo=true
     if key in ['house_wood','house_roof','house_trim','house_stone']:
      var texture_key:='stone' if key=='house_stone' else 'wood'
      mat.albedo_texture=texture(args[0],'house_'+texture_key)
      mat.normal_enabled=true;mat.normal_texture=texture(args[0],'house_'+texture_key+'_normal',true);mat.normal_scale=.5
     mat.roughness=.86 if key!='house_iron' else .58
     mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
     ResourceSaver.save(mat,OUT+key+'_material.tres');materials[key]=load(OUT+key+'_material.tres')
    var st:=SurfaceTool.new();st.create_from(mi.mesh,s);st.generate_tangents()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
    mesh.surface_set_material(s,materials[key]);total+=mesh.surface_get_array_index_len(s)/3
   var path:String=OUT+'house_'+state_name+'_'+mi.name.to_snake_case()+'_mesh.tres'
   ResourceSaver.save(mesh,path);mi.mesh=load(path)
   if mi.name=='Tarp':mi.visible=false
  owner_recursive(scene,scene);var packed:=PackedScene.new();packed.pack(scene)
  ResourceSaver.save(packed,OUT+'house_'+state_name+'.tscn');scene.free();print(state_name,' imported triangles ',total)
 print('HOUSE IMPORT OK');quit()
func texture(dir_:String,key:String,is_normal:bool=false)->Texture2D:
 if not textures.has(key):
  var image:=Image.load_from_file(dir_.path_join(key+'.png'));image.convert(Image.FORMAT_RGB8);image.generate_mipmaps()
  var tex:=PortableCompressedTexture2D.new();tex.create_from_image(image,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,is_normal,.85)
  ResourceSaver.save(tex,OUT+key+'_texture.tres');textures[key]=load(OUT+key+'_texture.tres')
 return textures[key]
func owner_recursive(n:Node,r:Node)->void:
 for c in n.get_children():c.owner=r;owner_recursive(c,r)
