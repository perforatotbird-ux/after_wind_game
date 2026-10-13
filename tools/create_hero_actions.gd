extends SceneTree
## Дополнительный клип мотыги: опорные ноги из idle, умеренный наклон корпуса.
func _initialize():call_deferred('run')
func run():
 var player=load('res://scenes/player/player.tscn').instantiate();root.add_child(player)
 player.set_process(false);player.set_physics_process(false)
 var ap:AnimationPlayer=player.anim_player;var sk:Skeleton3D=player.visual_root.find_child('Skeleton3D',true,false)
 var idle:Animation=ap.get_animation('idle')
 var anim:=Animation.new();anim.length=1.2;anim.set_meta('play_speed',1.2);anim.set_meta('contact_time',.66)
 var tracks:={}
 for i in range(sk.get_bone_count()):
  var path:=NodePath('HeroArmature/Skeleton3D:'+sk.get_bone_name(i))
  var p:=anim.add_track(Animation.TYPE_POSITION_3D);anim.track_set_path(p,path)
  var r:=anim.add_track(Animation.TYPE_ROTATION_3D);anim.track_set_path(r,path)
  var sc:=anim.add_track(Animation.TYPE_SCALE_3D);anim.track_set_path(sc,path)
  tracks[i]=[p,r,sc]
 for frame in range(37):
  var t:=frame/30.0;ap.play('idle',0);ap.seek(t,true);ap.advance(0)
  var phase:=t/1.2
  var bend:float=smoothstep(.25,.55,phase)*(1.-smoothstep(.65,1.,phase))
  for b in ['Spine1','Spine2']:
   var idx:=sk.find_bone(b);var q:=sk.get_bone_pose_rotation(idx)
   sk.set_bone_pose_rotation(idx,q*Quaternion(Vector3.RIGHT,deg_to_rad(10)*bend))
  for i in tracks:
   anim.track_insert_key(tracks[i][0],t,sk.get_bone_pose_position(i))
   anim.track_insert_key(tracks[i][1],t,sk.get_bone_pose_rotation(i))
   anim.track_insert_key(tracks[i][2],t,sk.get_bone_pose_scale(i))
 var library:=AnimationLibrary.new();library.add_animation('hoe_dig',anim)
 print('saved hoe animation ',ResourceSaver.save(library,'res://assets/animations/hero_actions.tres'))
 player.free();quit()
