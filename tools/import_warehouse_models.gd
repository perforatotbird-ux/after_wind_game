extends SceneTree
## Godot --headless --path . -s tools/import_warehouse_models.gd -- BUILD_DIR
const OUT := 'res://assets/models/warehouse/'
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():push_error('Укажите папку сборки');quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for which in ['ruined','restored']:
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_file(args[0].path_join('warehouse_'+which+'.gltf'),state)!=OK:push_error('Warehouse glTF missing');quit(1);return
		var scene:=doc.generate_scene(state);scene.name='Warehouse'+which.capitalize()
		scene.set_script(load('res://scripts/buildings/warehouse_visual.gd'));scene.set('storage_stage',0 if which=='ruined' else 2)
		var total:=0
		for mi in scene.find_children('*','MeshInstance3D',true,false):
			var mesh:=ArrayMesh.new()
			for s in mi.mesh.get_surface_count():
				var mat:=mi.mesh.surface_get_material(s) as StandardMaterial3D
				# Shared original painted wood / stone are already portable runtime resources.
				var key:=mat.resource_name.to_snake_case()
				var shared:Material=load('res://assets/models/house/'+key+'_material.tres')
				if shared==null:push_error('Missing shared material '+key);quit(1);return
				var st:=SurfaceTool.new();st.create_from(mi.mesh,s);st.generate_tangents()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
				mesh.surface_set_material(s,shared);total+=mesh.surface_get_array_index_len(s)/3
			var path: String=OUT+'warehouse_'+which+'_'+mi.name.to_snake_case()+'_mesh.tres'
			ResourceSaver.save(mesh,path);mi.mesh=load(path)
			if mi.name=='Tarp':mi.visible=false
		owner_recursive(scene,scene)
		var packed:=PackedScene.new();packed.pack(scene);ResourceSaver.save(packed,OUT+'warehouse_'+which+'.tscn')
		scene.free();print(which,' triangles ',total)
	quit()
func owner_recursive(node: Node, root_: Node) -> void:
	for child in node.get_children():child.owner=root_;owner_recursive(child,root_)
