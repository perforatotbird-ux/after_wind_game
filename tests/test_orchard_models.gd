extends SceneTree
## Яблоня и абрикос: четыре версии, общие меши, материалы и игровой сбор яблок.
const FruitTree=preload('res://scripts/resources/fruit_tree.gd')
const Seasons=preload('res://scripts/core/seasons.gd')
class MockPlayer extends Node:
 var inventory:Inventory
 func notify(_message:String) -> void:pass
var errors:Array[String]=[]
func check(ok:bool,msg:String) -> void:
 if not ok:errors.append(msg);printerr('FAIL: '+msg)
func _initialize():call_deferred('checks')
func checks():
 for species in ['apple','apricot']:
  var path:String='res://assets/models/'+species+'/'
  var fruit:Node3D=load(path+species+'_with_fruit.tscn').instantiate()
  var bare:Node3D=load(path+species+'_without_fruit.tscn').instantiate()
  root.add_child(fruit);root.add_child(bare)
  var name_:String='Apples' if species=='apple' else 'Apricots'
  check(fruit.has_node('Fruits/'+name_) and fruit.has_node('Fruits/Stems'),'Separate '+species+' fruit and stems')
  check(not bare.has_node('Fruits'),'Bare '+species+' contains no fruit geometry')
  var tris:=0;var first:=true;var bounds:=AABB()
  for mi in fruit.find_children('*','MeshInstance3D',true,false):
   check(mi.mesh is ArrayMesh,'Real mesh '+mi.name)
   for i in mi.mesh.get_surface_count():
    tris+=mi.mesh.surface_get_array_index_len(i)/3
    var a:Array=mi.mesh.surface_get_arrays(i)
    check(a[Mesh.ARRAY_COLOR]!=null and a[Mesh.ARRAY_NORMAL]!=null and a[Mesh.ARRAY_TEX_UV]!=null,'Normals color UV '+mi.name)
    check(mi.mesh.surface_get_material(i) is StandardMaterial3D,'PBR material '+mi.name)
   var b:AABB=mi.transform*mi.get_aabb();bounds=b if first else bounds.merge(b);first=false
  check(tris>22000 and tris<50000,'Triangle budget '+species)
  check(bounds.position.y>=-.001,'Grounded roots '+species)
  check(bounds.size.y>3.3 and bounds.size.y<4.4,'Tree height '+species)
  check(bounds.size.x>3.3 and bounds.size.x<4.4,'Wide crown '+species)
  for n in ['Trunk','Canopy0','Canopy1','Canopy2','Canopy3','Canopy4','Canopy5','Canopy6']:
   check(fruit.get_node(n).mesh==bare.get_node(n).mesh,'Shared bare/fruity '+n)
  check(fruit.get_node('Trunk').mesh.surface_get_material(0).albedo_texture!=null,'Bark texture '+species)
  check(fruit.get_node('Canopy0').mesh.surface_get_material(0).albedo_texture!=null,'Leaf vein texture '+species)
  for f in DirAccess.get_files_at(path):
   if f.ends_with('.tres'):check(FileAccess.get_file_as_bytes(path+f).size()<1024*1024,'Portable resource '+f)
  var a:Array=fruit.get_node('Fruits/'+name_).mesh.surface_get_arrays(0);var colors:PackedColorArray=a[Mesh.ARRAY_COLOR]
  if species=='apple':
   var red:=false;var yellow:=false;var green:=false
   for c in colors:
    red=red or c.r>c.g*2.5;yellow=yellow or (c.r>c.g and c.g>c.b*3);green=green or c.g>c.r
   check(red and yellow and green,'Red/yellow/green apple blush')
  else:
   check(fruit.get_node('Fruits/'+name_).mesh.surface_get_material(0).roughness>.5,'Apricot soft non-gloss finish')
  fruit.queue_free();bare.queue_free()
 var tree:Node=load('res://scenes/resources/tree_apple.tscn').instantiate();root.add_child(tree);tree.set_process(false)
 check(tree.object_name=='Яблоня' and tree._canopy_mesh==null and tree._fruits_node.has_node('Apples'),'Apple uses new model')
 check(tree.max_hits==8,'Current audited chopping balance preserved')
 var player:=MockPlayer.new();player.inventory=Inventory.new();player.add_child(player.inventory);root.add_child(player)
 var trunk:Mesh=tree._trunk_mesh.mesh
 var amount:int=tree.harvest(player)
 check(amount>=4 and amount<=8 and player.inventory.get_item_count('apple')==amount,'Apple harvest yield unchanged')
 check(not tree._fruits_node.visible and tree._trunk_mesh.mesh==trunk,'Harvest hides fruit without changing crown')
 Seasons.current_season='summer';tree.advance_hours(24);check(not tree.has_fruit,'Apple does not regrow in summer')
 Seasons.current_season='autumn';tree.advance_hours(24);check(tree.has_fruit and tree._fruits_node.visible,'Autumn regrowth shows apples')
 tree.stage=0;tree.has_fruit=false;tree._update_visuals()
 check(tree._visuals_root.scale==Vector3(.3,.3,.3) and not tree._fruits_node.visible,'Sapling has no fruit')
 tree.advance_hours(24);check(tree.stage==1 and not tree._fruits_node.visible,'Young apple has no fruit')
 tree.advance_hours(48);check(tree.stage==2 and tree._fruits_node.visible,'Mature apple fruits after original three days')
 tree.apply_save_state({'type':'apple_tree','stage':2,'has_fruit':false,'hits':8})
 check(not tree._fruits_node.visible and tree._fruits_node.has_node('Apples'),'Legacy saved empty apple uses new model')
 tree.apply_save_state({'type':'pear_tree','stage':2,'has_fruit':true})
 check(tree._canopy_mesh is MeshInstance3D and tree._fruits_node.visible,'Pear unchanged')
 tree.apply_save_state({'type':'cherry_tree','stage':2,'has_fruit':true})
 check(tree._fruits_node.has_node('Cherries'),'Cherry unchanged')
 check(not FruitTree.CONFIGS.has('apricot_tree'),'Apricot models do not invent gameplay economy')
 Seasons.current_season='';tree.queue_free();player.queue_free()
 if errors.is_empty():print('PASS: test_orchard_models')
 quit(0 if errors.is_empty() else 1)
