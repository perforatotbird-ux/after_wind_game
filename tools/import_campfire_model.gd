extends SceneTree
## godot --headless --path . -s tools/import_campfire_model.gd -- <build_dir>
const OUT := "res://assets/models/campfire/"
var materials := {}
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): push_error("Укажите папку сборки костра"); quit(1); return
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var doc := GLTFDocument.new();var state := GLTFState.new()
	if doc.append_from_file(args[0].path_join("campfire_model.gltf"),state) != OK:
		push_error("Не прочитан костёр");quit(1);return
	var scene := doc.generate_scene(state);scene.name="CampfireGeometry"
	for mi in scene.find_children("*","MeshInstance3D",true,false):
		var mesh := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var key := src.resource_name.to_snake_case()
			if not materials.has(key):
				var mat := src.duplicate() as StandardMaterial3D
				if src.albedo_texture:
					mat.albedo_texture=_texture(src.albedo_texture.get_image(),key+"_texture",false)
				mat.roughness=0.95
				mat.vertex_color_use_as_albedo = key == "campfire_stone"
				mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				ResourceSaver.save(mat,OUT+key+"_material.tres")
				materials[key]=load(OUT+key+"_material.tres")
			var st := SurfaceTool.new();st.create_from(mi.mesh,s);st.generate_tangents()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			mesh.surface_set_material(s,materials[key])
		var path:=OUT+"campfire_"+mi.name.to_snake_case()+"_mesh.tres"
		ResourceSaver.save(mesh,path);mi.mesh=load(path)
		print(mi.name," surfaces ",mesh.get_surface_count())
	var cracks:=Image.load_from_file(args[0].path_join("campfire_cracks.png"))
	_texture(cracks,"campfire_cracks",false)
	var smoke:=Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var v:=Vector2((x-63.5)/63.5,(y-63.5)/63.5)
			var wobble:=0.8+0.2*sin(v.x*8+v.y*5)*cos(v.y*7-v.x*4)
			var alpha:=pow(maxf(0.0,1.0-v.length_squared()),2)*wobble
			smoke.set_pixel(x,y,Color(1,1,1,alpha))
	_texture(smoke,"campfire_smoke",true)
	_set_owner(scene,scene)
	var packed:=PackedScene.new();packed.pack(scene)
	ResourceSaver.save(packed,OUT+"campfire_geometry.tscn")
	scene.free();print("CAMPFIRE IMPORT OK");quit()
func _texture(image:Image,name_:String,alpha:bool)->Texture2D:
	image.convert(Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8)
	image.generate_mipmaps()
	var tex:=PortableCompressedTexture2D.new()
	tex.create_from_image(image,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,false,0.88)
	ResourceSaver.save(tex,OUT+name_+".tres")
	return load(OUT+name_+".tres")
func _set_owner(node:Node,root_node:Node)->void:
	for child in node.get_children():child.owner=root_node;_set_owner(child,root_node)
