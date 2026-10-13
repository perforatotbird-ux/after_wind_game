extends SkeletonModifier3D
## Двуручный хват: оба запястья решаются к двум точкам одного черенка.
## Модификатор работает после AnimationPlayer, поэтому ходьба и наклон корпуса сохраняются.
var player: Node
var _right_socket: Transform3D
var _left_socket: Transform3D
var _initialized := false
var grip_error := 0.0

func _process_modification() -> void:
 var sk:=get_skeleton()
 if not is_instance_valid(player) or sk==null:
  return
 var hoe:Node3D=player.equipped_tool_nodes.get('shovel')
 if not is_instance_valid(hoe) or not hoe.visible:
  return
 if not _initialized:
  var rh:=sk.find_bone('Hand.r');var lh:=sk.find_bone('Hand.l');var socket:=sk.find_bone('ToolSocket.R')
  if rh<0 or lh<0 or socket<0:return
  _right_socket=sk.get_bone_global_rest(rh).affine_inverse()*sk.get_bone_global_rest(socket)
  # Левая кисть развёрнута к правой: кулак вокруг того же черенка.
  _left_socket=_right_socket
  _left_socket.origin=Vector3(-_right_socket.origin.x,_right_socket.origin.y,_right_socket.origin.z)
  _initialized=true
 var origin:=Vector3(-.18,1.08,.28)
 var axis:=Vector3(.72,.66,.08).normalized()
 if player.is_digging or player.is_mining:
  var elapsed:float=player._dig_elapsed if player.is_digging else player._strike_elapsed
  var duration:float=player._dig_duration if player.is_digging else player._strike_duration
  var t:float=clampf(elapsed/maxf(duration,.01),0,1)
  var lift:=smoothstep(0.0,.25,t)*(1.0-smoothstep(.25,.52,t))
  var strike:=smoothstep(.25,.55,t)*(1.0-smoothstep(.65,1.0,t))
  origin=origin.lerp(Vector3(-.12,1.18,.22),lift).lerp(Vector3(0,1.07,.18),strike)
  axis=axis.lerp(Vector3(.15,.98,-.10).normalized(),lift).lerp(Vector3(.08,-.72,.69).normalized(),strike).normalized()
 var y:=axis;var x:=Vector3.BACK.cross(y).normalized();var z:=x.cross(y).normalized()
 # Скелет героя в единицах 1/.36; сокет компенсирует масштаб персонажа.
 var desired:=Transform3D(Basis(x,y,z)*(1.0/.36),origin/.36)
 # Подогнать общий черенок к пересечению областей досягаемости обеих рук,
 # а не вытягивать запястья или оставлять левую ладонь рядом с инструментом.
 for iteration in range(12):
  for side in ['r','l']:
   var grip:=desired
   if side=='l':grip.origin+=axis*(.28/.36)
   var target:=grip*(_right_socket if side=='r' else _left_socket).affine_inverse()
   var a:=sk.get_bone_global_pose(sk.find_bone('Forearm.'+side)).origin
   var b:=sk.get_bone_global_pose(sk.find_bone('Arm.'+side)).origin
   var c:=sk.get_bone_global_pose(sk.find_bone('Hand.'+side)).origin
   var reach:float=(a.distance_to(b)+b.distance_to(c))*.985
   var offset:=target.origin-a
   if offset.length()>reach:desired.origin-=offset.normalized()*(offset.length()-reach)
 var right:=desired*_right_socket.affine_inverse()
 var left_socket:=desired;left_socket.origin+=axis*(.28/.36)
 var left:=left_socket*_left_socket.affine_inverse()
 solve_arm(sk,'r',right,Vector3(-1.5,2.7,.3))
 solve_arm(sk,'l',left,Vector3(1.5,2.7,.3))
 # ToolSocket.R следует ориентации кисти, не отдельному независимому пропу.
 var socket_idx:=sk.find_bone('ToolSocket.R')
 sk.set_bone_global_pose(socket_idx,desired)
 grip_error=maxf(sk.get_bone_global_pose(sk.find_bone('Hand.r')).origin.distance_to(right.origin),sk.get_bone_global_pose(sk.find_bone('Hand.l')).origin.distance_to(left.origin))*.36
 curl_fingers(sk,'r');curl_fingers(sk,'l')

func solve_arm(sk:Skeleton3D,side:String,target:Transform3D,pole:Vector3)->void:
 var upper:=sk.find_bone('Forearm.'+side);var lower:=sk.find_bone('Arm.'+side);var hand:=sk.find_bone('Hand.'+side)
 var a:=sk.get_bone_global_pose(upper).origin
 var b:=sk.get_bone_global_pose(lower).origin
 var c:=sk.get_bone_global_pose(hand).origin
 var l1:=a.distance_to(b);var l2:=b.distance_to(c)
 var d:=clampf(a.distance_to(target.origin),absf(l1-l2)+.001,l1+l2-.001)
 var dir:Vector3=(target.origin-a).normalized()
 var perpendicular:Vector3=(pole-a)-dir*(pole-a).dot(dir);perpendicular=perpendicular.normalized()
 var along:float=(l1*l1-l2*l2+d*d)/(2*d)
 var elbow:=a+dir*along+perpendicular*sqrt(maxf(0,l1*l1-along*along))
 _rotate_bone(sk,upper,b-a,elbow-a)
 b=sk.get_bone_global_pose(lower).origin;c=sk.get_bone_global_pose(hand).origin
 _rotate_bone(sk,lower,c-b,target.origin-b)
 var hp:=sk.get_bone_global_pose(hand);hp.basis=target.basis
 sk.set_bone_global_pose(hand,hp)

func _rotate_bone(sk:Skeleton3D,idx:int,old:Vector3,new_:Vector3)->void:
 if old.length_squared()<.00001 or new_.length_squared()<.00001:return
 var pose:=sk.get_bone_global_pose(idx)
 pose.basis=Basis(Quaternion(old.normalized(),new_.normalized()))*pose.basis
 sk.set_bone_global_pose(idx,pose)

func curl_fingers(sk:Skeleton3D,side:String)->void:
 # Зафиксировать пальцы в исходном кулаке; UAL Farm_Harvest раскрывает ладонь.
 for finger in ['Index','Middle','Ring','Pinky','Thumb']:
  for segment in range(1,4):
   var idx:=sk.find_bone(finger+str(segment)+'.'+side)
   if idx>=0:sk.set_bone_pose_rotation(idx,Quaternion.IDENTITY)
