class_name TouchStick
extends Node2D
## Joystick virtual multitáctil. axis: Vector2 en [-1,1] (y negativo = adelante).

var radius: float = 90.0
var axis: Vector2 = Vector2.ZERO
var _touch: int = -1
var _knob: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := _to_local_canvas(st.position)
		if st.pressed and _touch == -1 and local.length() < radius * 1.6:
			_touch = st.index
			_update(local)
		elif not st.pressed and st.index == _touch:
			_touch = -1
			_update(Vector2.ZERO)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch:
			_update(_to_local_canvas(sd.position))

func _to_local_canvas(screen_pos: Vector2) -> Vector2:
	var xf := get_viewport().get_final_transform().affine_inverse()
	return (xf * screen_pos) - global_position

func _update(local: Vector2) -> void:
	_knob = local.limit_length(radius)
	axis = _knob / radius
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.15))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	draw_circle(_knob, radius * 0.4, Color(1, 1, 1, 0.45))
