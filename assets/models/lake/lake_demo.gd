extends Node3D
## Preview-only controller. No gameplay dependencies. Run lake_demo.tscn with F6.
var camera:Camera3D
func _ready()->void:
 camera=$Camera3D
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:
  var m:ShaderMaterial=load("res://assets/models/lake/lake_water_material.tres")
  var speed:float=m.get_shader_parameter("wind_strength")
  m.set_shader_parameter("wind_strength",1.0 if speed==0.0 else 0.0)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera.size=maxf(9.0,camera.size-.5)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera.size=minf(20.0,camera.size+.5)
