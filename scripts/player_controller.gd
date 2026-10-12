class_name PlayerController
extends Node
## Lee teclado + controles táctiles y los traduce a órdenes del luchador.

var me: Fighter
var camera: Camera3D
var joystick: TouchStick
var enabled: bool = true
var _prev: Dictionary = {}

func _pressed_edge(action: String) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = _prev.get(action, false)
	_prev[action] = now
	return now and not was

func _physics_process(_delta: float) -> void:
	if me == null:
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if joystick:
		v += joystick.axis
	v = v.limit_length(1.0)
	var fwd := Vector3.FORWARD
	if camera:
		fwd = MeshUtil.flat(-camera.global_transform.basis.z).normalized()
	var right := fwd.cross(Vector3.UP)
	me.move_input = (right * v.x + fwd * -v.y) if enabled else Vector3.ZERO
	me.want_block = enabled and Input.is_action_pressed("block")
	var sw := _pressed_edge("attack_sword")
	var bw := _pressed_edge("shoot_bow")
	var sm := _pressed_edge("summon")
	var ds := _pressed_edge("dash")
	if not enabled:
		return
	if sw: me.sword()
	if bw: me.shoot()
	if sm: me.summon()
	if ds: me.dash()
