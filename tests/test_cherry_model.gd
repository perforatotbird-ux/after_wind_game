extends SceneTree
## Модель вишни: две версии, форма, листья, плоды, рост и старые сохранения.
const FruitTree = preload('res://scripts/resources/fruit_tree.gd')
const Seasons = preload('res://scripts/core/seasons.gd')
const Save = preload('res://scripts/core/save_manager.gd')
const SAVE_PATH := 'user://test_cherry_model.json'
class MockPlayer extends Node:
 var inventory:Inventory
 func notify(_message:String) -> void:pass
var errors:Array[String]=[]
func check(ok:bool,msg:String) -> void:
 if not ok:errors.append(msg);printerr('FAIL: '+msg)
func _initialize() -> void:
 call_deferred('checks')
func tri_count(mesh:Mesh) -> int:
 var n:=0
 for i in mesh.get_surface_count():n+=mesh.surface_get_array_index_len(i)/3
 return n
func checks() -> void:
 var fruitful:Node3D=load('res://assets/models/cherry/cherry_with_fruit.tscn').instantiate()
 var bare:Node3D=load('res://assets/models/cherry/cherry_without_fruit.tscn').instantiate()
 root.add_child(fruitful);root.add_child(bare)
 check(fruitful.has_node('Fruits/Cherries') and fruitful.has_node('Fruits/Stems'),'Cherries and paired stems are separate geometry')
 check(not bare.has_node('Fruits'),'Bare variant has no fruit or stems')
 var total:=0;var bounds:=AABB();var first:=true
 for mi in fruitful.find_children('*','MeshInstance3D',true,false):
  check(mi.mesh is ArrayMesh,'Real geometry '+mi.name)
  total+=tri_count(mi.mesh)
  var b:AABB=mi.transform*mi.get_aabb();bounds=b if first else bounds.merge(b);first=false
  for i in mi.mesh.get_surface_count():
   var a:Array=mi.mesh.surface_get_arrays(i)
   check(a[Mesh.ARRAY_NORMAL]!=null and a[Mesh.ARRAY_COLOR]!=null and a[Mesh.ARRAY_TEX_UV]!=null,'Normals colors UV '+mi.name)
   check(mi.mesh.surface_get_material(i) is StandardMaterial3D,'Material '+mi.name)
 check(total>15000 and total<30000,'Triangle budget 15–30k')
 check(bounds.position.y>=-.001,'Tree sits on ground')
 check(bounds.size.y>3.8 and bounds.size.y<4.4,'Tree height matches fruit trees')
 check(bounds.size.x>3.4 and bounds.size.x<4.2,'Wide multi-lobed canopy')
 for n in ['Trunk','Canopy0','Canopy1','Canopy2','Canopy3','Canopy4','Canopy5','Canopy6']:
  check(fruitful.get_node(n).mesh==bare.get_node(n).mesh,'Shared trunk and foliage '+n)
 var mat=fruitful.get_node('Trunk').mesh.surface_get_material(0)
 check(mat.albedo_texture!=null,'Textured bark')
 check(fruitful.get_node('Fruits/Cherries').mesh.surface_get_material(0).roughness<.4,'Glossy cherries')
 for f in DirAccess.get_files_at('res://assets/models/cherry'):
  if f.ends_with('.tres'):check(FileAccess.get_file_as_bytes('res://assets/models/cherry/'+f).size()<1024*1024,'Portable text resource '+f)
 var tree:Node=load('res://scenes/resources/tree_cherry.tscn').instantiate();root.add_child(tree);tree.set_process(false)
 check(tree.tree_type=='cherry_tree' and tree.object_name=='Вишня','Ready-to-use gameplay cherry scene')
 var player:=MockPlayer.new();player.inventory=Inventory.new();player.add_child(player.inventory);root.add_child(player)
 var cherries:Node3D=tree._fruits_node
 check(cherries.visible and tree._canopy_mesh==null,'Cherry uses new model, not placeholder sphere')
 var trunk_mesh:Mesh=tree._trunk_mesh.mesh
 var amount:int=tree.harvest(player)
 check(amount>=6 and amount<=12 and player.inventory.get_item_count('cherry')==amount,'Existing harvest yield retained')
 check(not cherries.visible and not tree.has_fruit,'Harvest hides berries and stems')
 check(tree._trunk_mesh.mesh==trunk_mesh,'Harvest does not rebuild trunk or leaves')
 Seasons.current_season='winter';tree.advance_hours(24)
 check(not tree.has_fruit and not cherries.visible,'No winter regrowth')
 Seasons.current_season='summer';tree.advance_hours(24)
 check(tree.has_fruit and cherries.visible,'Summer regrowth restores fruit geometry')
 tree.stage=FruitTree.Stage.SAPLING;tree.has_fruit=false;tree._update_visuals()
 check(not cherries.visible and tree._visuals_root.scale==Vector3(.3,.3,.3),'Sapling is scaled down without fruit')
 tree.advance_hours(24)
 check(tree.stage==FruitTree.Stage.YOUNG and not cherries.visible,'Young stage keeps no fruit')
 tree.advance_hours(48)
 check(tree.stage==FruitTree.Stage.MATURE and cherries.visible,'Mature stage fruits after original 3 days')
 var data:Dictionary=tree.get_save_state();data.has_fruit=false
 tree.apply_save_state(data)
 check(not tree._fruits_node.visible and tree._visuals_root.get_child_count()==1,'Saved empty cherry rebuilt correctly')
 tree.apply_save_state({'type':'apple_tree','stage':2,'has_fruit':true})
 check(tree._canopy_mesh==null and tree._fruits_node.visible and tree._fruits_node.has_node('Apples'),'Apple model selected when loading another type')
 tree.apply_save_state({'type':'cherry_tree','stage':2,'has_fruit':true})
 check(tree._canopy_mesh==null and tree._fruits_node.visible,'Loading legacy cherry uses new mesh')
 Seasons.current_season=''
 fruitful.queue_free();bare.queue_free();tree.queue_free();player.queue_free()
 # Integration: actual SaveManager creates fruit trees from optional legacy state.
 var world:Node3D=load('res://scenes/world/world.tscn').instantiate();root.add_child(world)
 for i in 3:await process_frame
 world.process_mode=Node.PROCESS_MODE_DISABLED
 var file:=FileAccess.open(SAVE_PATH,FileAccess.WRITE)
 file.store_string(JSON.stringify({'meta':{'version':'1.0.0'},'fruit_trees':[{'type':'cherry_tree','pos':[11,0,7],'stage':2,'has_fruit':false,'growth':0,'regrow':3,'hits':3}]}));file.close()
 check(Save.load_game(world,SAVE_PATH),'Legacy save with empty cherry loads')
 var loaded:Node
 for t in get_nodes_in_group('fruit_trees'):
  if t.is_inside_tree() and not t.is_queued_for_deletion() and t.tree_type=='cherry_tree':loaded=t
 check(loaded!=null and loaded._canopy_mesh==null and not loaded._fruits_node.visible,'SaveManager reconstructs empty new cherry')
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
 if errors.is_empty():print('PASS: test_cherry_model')
 quit(0 if errors.is_empty() else 1)
