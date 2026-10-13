extends SceneTree
## Реальная физика прыжка, состояния анимации, постоянная кирка и двуручный хват.
var player
var failed:=false
class ModalStub extends Node:
 func is_gameplay_input_blocked():return true
func _initialize():call_deferred('run')
func check(ok:bool,message:String):
 if not ok:failed=true;push_error(message)
func jump_event():
 var event:=InputEventAction.new();event.action='jump';event.pressed=true;player._unhandled_input(event)
func run():
 var floor_:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(40,1,40);shape.shape=box;floor_.add_child(shape);floor_.position.y=-.5;root.add_child(floor_)
 player=load('res://scenes/player/player.tscn').instantiate();root.add_child(player)
 for i in 12:await physics_frame
 check(player.is_on_floor(),'Player must start on ground')
 check(InputMap.has_action('jump'),'Missing jump input action')
 check(InputMap.action_get_events('jump')[0].physical_keycode==KEY_SPACE,'Jump must use physical Space')
 var start_y:float=player.position.y
 jump_event();Input.action_press('move_forward')
 var apex:=0.0;var clips:={};var prevented_double:=false
 for i in 90:
  await physics_frame
  apex=maxf(apex,player.position.y-start_y);clips[player.current_anim]=true
  if i==12:
   var before:float=player.velocity.y;jump_event();await physics_frame
   prevented_double=player.velocity.y<=before+.01
 check(apex>.8 and apex<1.3,'Unexpected jump height: '+str(apex))
 check(prevented_double,'Airborne input caused a second jump')
 check(player.is_on_floor() and not player.is_jumping,'Jump did not land')
 check(absf(player.position.z)>1.0,'Cannot move horizontally during jump')
 for clip in ['jump_start','jump_loop','jump_land']:check(clips.has(clip),'Missing played animation '+clip)
 Input.action_release('move_forward')
 for i in 20:await physics_frame
 check(player.current_anim=='idle','Landing did not return to locomotion')
 var hud:=ModalStub.new();root.add_child(hud);player._hud=hud;jump_event()
 for i in 4:await physics_frame
 check(not player.is_jumping and player.is_on_floor(),'Modal allowed jump')
 player._hud=null;hud.queue_free()
 player.play_dig_animation();jump_event();await physics_frame
 check(not player.is_jumping,'Can jump during tool action')
 player._finish_dig()
 player.inventory.equip_tool('pickaxe');player._refresh_tool_visibility()
 var pick:MeshInstance3D=player.equipped_pickaxe_mesh
 check(pick.visible,'Pickaxe hidden in idle')
 check(pick.mesh.resource_path=='res://assets/models/tools/pickaxe_equipped_mesh.tres','Old embedded axe still used as pickaxe')
 for tool in ['axe','shovel','bucket']:
  player.inventory.equip_tool(tool);check(not pick.visible,'Embedded tool visible together with '+tool)
 player.inventory.equip_tool('shovel')
 check(player.equipped_tool_nodes.shovel.name=='Equipped_Shovel','Legacy shovel key broken')
 check(player.equipped_tool_nodes.shovel.find_child('ForgedBlade',true,false)!=null,'Hoe missing forged blade')
 for path in ['res://scenes/tools/shovel_inhand.tscn','res://scenes/tools/shovel_model.tscn']:
  var legacy=load(path).instantiate();check(legacy.find_child('ForgedBlade',true,false)!=null,'Legacy scene has no hoe geometry: '+path);legacy.free()
 player.set_process(false);player.set_physics_process(false)
 var max_error:=0.0
 for mode in ['idle','dig','walk','jog','run','jump_start','jump_loop','jump_land']:
  player.is_digging=mode=='dig';player._dig_duration=1.;player._dig_elapsed=0.
  var anim:String=player._resolve_anim(mode);player.anim_player.play(anim,0);player.anim_player.speed_scale=0.
  var mode_error:=0.0
  for i in range(31):
   var fraction:float=i/30.
   player._dig_elapsed=fraction
   player.anim_player.seek(fraction*player.anim_player.get_animation(anim).length,true);player.anim_player.advance(0.)
   await process_frame
   max_error=maxf(max_error,player.hoe_grip.grip_error);mode_error=maxf(mode_error,player.hoe_grip.grip_error)
  print('GRIP ',mode,' ',mode_error)
 check(max_error<.025,'Two-hand grip detached by '+str(max_error)+' m')
 check(player.anim_player.has_animation('tools/hoe_dig'),'Missing dedicated hoe clip')
 check(load('res://scripts/inventory/item_db.gd').get_item('shovel').name=='Мотыга','Item still named shovel')
 var icon:Texture2D=load('res://assets/tools/hoe_icon.tres')
 check(icon.get_image()!=null and icon.get_image().get_width()==48,'Hoe icon has no persisted image data')
 print('JUMP: apex=',apex,' clips=',clips.keys(),'; HOE: max wrist error=',max_error,'m')
 quit(1 if failed else 0)
