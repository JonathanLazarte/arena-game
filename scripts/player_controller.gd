class_name PlayerController
extends Node
## Lee teclado + controles táctiles y los traduce a órdenes del luchador.
## Lock-on (fijar objetivo) activado por defecto: Tab/Q o botón "Fijar".

var me: Fighter
var camera: Camera3D
var joystick: TouchStick
var enabled: bool = true
var lock_on: bool = true
var _prev: Dictionary = {}

func _pressed_edge(action: String) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = _prev.get(action, false)
	_prev[action] = now
	return now and not was

func _physics_process(_delta: float) -> void:
	if me == null:
		return
	if _pressed_edge("lock_on"):
		lock_on = not lock_on
	var opp := me.opponent
	me.face_target = opp if (lock_on and opp != null and opp.alive) else null
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if joystick:
		v += joystick.axis
	v = v.limit_length(1.0)
	var fwd := Vector3.FORWARD
	if me.face_target:
		# Movimiento relativo al rival (strafe)
		var d := MeshUtil.flat(me.face_target.global_position - me.global_position)
		fwd = d.normalized() if d.length() > 0.1 else me.facing
	elif camera:
		fwd = MeshUtil.flat(-camera.global_transform.basis.z).normalized()
	var right := fwd.cross(Vector3.UP)
	me.move_input = (right * v.x + fwd * -v.y) if enabled else Vector3.ZERO
	me.want_block = enabled and Input.is_action_pressed("block")
	me.want_sprint = enabled and Input.is_action_pressed("sprint")
	var sw := _pressed_edge("attack_sword")
	var bw := _pressed_edge("shoot_bow")
	var sm := _pressed_edge("summon")
	var ds := _pressed_edge("dash")
	var mt := _pressed_edge("mount")
	if not enabled:
		return
	if sw: me.sword()
	if bw: me.shoot()
	if sm: me.summon()
	if ds: me.dash()
	if mt: me.toggle_mount()
