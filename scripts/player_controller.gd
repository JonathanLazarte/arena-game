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
var _atk_hold: float = -1.0
var _heavy_fired: bool = false
## Ronda 15: correr a pie alternado (V / Bloq Mayús / botón táctil «Correr»). Mantener Mayús también corre.
var run_toggled: bool = false
## Ronda 16: objetivo fijado y cambio de objetivo (Z / rueda del ratón / botón «Objetivo»).
var target: Node3D = null
var _wheel: int = 0

## Objetivos válidos: rival, eikon enemigo (compañero o montura sin jinete) y futuros enemigos
## (cualquier nodo del grupo "damageable" de otro equipo que siga vivo). Rival primero.
func targets() -> Array[Node3D]:
	var out: Array[Node3D] = MeshUtil.enemies_of(me.get_tree(), me.team)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var fa := a is Fighter
		var fb := b is Fighter
		if fa != fb:
			return fa
		return me.global_position.distance_squared_to(a.global_position) < me.global_position.distance_squared_to(b.global_position))
	return out

## Ronda 21: el botón «Objetivo» solo tiene sentido con 2+ objetivos válidos.
func can_cycle_target() -> bool:
	return me != null and targets().size() > 1

func cycle_target() -> Node3D:
	_update_target(true)
	return target

func _update_target(cycle: bool) -> void:
	var list := targets()
	if list.is_empty():
		target = null
		return
	var idx := list.find(target)
	if idx < 0:
		var opp := me.opponent
		target = opp if (opp != null and opp in list) else list[0]
		idx = list.find(target)
	if cycle:
		target = list[(idx + 1) % list.size()]

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel = 1

func _pressed_edge(action: String) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = _prev.get(action, false)
	_prev[action] = now
	return now and not was

func _physics_process(delta: float) -> void:
	if me == null:
		return
	if _pressed_edge("lock_on"):
		lock_on = not lock_on
	var cyc := _pressed_edge("target_next") or _wheel != 0
	_wheel = 0
	_update_target(cyc)
	me.face_target = target if lock_on else null
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
	if _pressed_edge("run_toggle") and not me.mounted:
		run_toggled = not run_toggled
	if me.exhausted > 0.0 or me.mounted:
		run_toggled = false
	me.want_sprint = enabled and (Input.is_action_pressed("sprint") or run_toggled)
	var atk_down := Input.is_action_pressed("attack_sword")
	var atk_edge := _pressed_edge("attack_sword")
	var swp := _pressed_edge("swap_weapon")
	var pr := _pressed_edge("parry")
	var sm := _pressed_edge("summon")
	var ds := _pressed_edge("dash")
	var mt := _pressed_edge("mount")
	var jp := _pressed_edge("jump")
	var sp := _pressed_edge("special")
	var cs := _pressed_edge("spell")
	var cn := _pressed_edge("spell_next")
	if not enabled:
		return
	if swp: me.swap_loadout()
	# Ataque: pulsar = ligero (al soltar), mantener 0,4 s = fuerte. En modo arco dispara.
	if me.loadout == Fighter.Loadout.BOW:
		if atk_edge: me.shoot()
		_atk_hold = -1.0
	elif atk_down:
		if _atk_hold < 0.0:
			_atk_hold = 0.0
			_heavy_fired = false
		else:
			_atk_hold += delta
		if _atk_hold >= Fighter.HEAVY_HOLD and not _heavy_fired:
			_heavy_fired = true
			me.attack_heavy()
	elif _atk_hold >= 0.0:
		if not _heavy_fired:
			me.attack_light()
		_atk_hold = -1.0
	if pr and not me.mounted: me.parry() # ronda 21: sin parry montado
	if cn: me.cycle_spell()
	if cs: me.cast_spell()
	if sm: me.summon()
	if ds: me.dash()
	if mt: me.toggle_mount()
	if jp: me.jump()
	if sp and not me.mounted: me.special() # ronda 22: sin Habilidad/Arte montado
