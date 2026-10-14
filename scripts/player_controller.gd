class_name PlayerController
extends Node
## Lee teclado + controles táctiles y los traduce a órdenes del luchador.
## Lock-on (fijar objetivo) activado por defecto: Tab/Q o botón "Fijar".

var me: Fighter
var camera: Camera3D
var joystick: TouchStick
var enabled: bool = true
## Ronda 30: menú abierto (sin pausar): quieto y en guardia, sin acciones.
var menu_hold: bool = false
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

const STICK_DEADZONE := 0.18
const STICK_CURVE := 1.5 ## >1: más precisión cerca del centro
const INPUT_SMOOTH := 0.08 ## s para completar un cambio de dirección de 90°
var _smooth: Vector2 = Vector2.ZERO

## Zona muerta radial (no por eje) y curva de respuesta: conserva la dirección exacta del stick.
static func shape_stick(raw: Vector2, dz: float = STICK_DEADZONE, curve: float = STICK_CURVE) -> Vector2:
	var l := raw.length()
	if l <= dz:
		return Vector2.ZERO
	var n := clampf((l - dz) / (1.0 - dz), 0.0, 1.0)
	return raw / l * pow(n, curve)

## Interpola la entrada: gira la dirección (90° en INPUT_SMOOTH) y ajusta la magnitud, sin pasar
## por cero salvo en inversiones casi completas (>135°) o al soltar.
static func smooth_input(cur: Vector2, target: Vector2, delta: float) -> Vector2:
	var rate := delta / INPUT_SMOOTH
	var lc := cur.length()
	var lt := target.length()
	if lc < 0.05 or lt < 0.05 or absf(cur.angle_to(target)) > deg_to_rad(135.0):
		return cur.move_toward(target, rate * 1.5)
	var a := cur.angle_to(target)
	var step := PI * 0.5 * rate
	var dir := (cur / lc).rotated(clampf(a, -step, step))
	return dir * move_toward(lc, lt, rate)

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
	if menu_hold:
		me.move_input = Vector3.ZERO
		me.want_block = enabled and not me.mounted
		me.want_sprint = false
		me.want_charge = false
		_smooth = Vector2.ZERO
		_atk_hold = -1.0
		_clear_buffer()
		for k: String in _prev:
			_prev[k] = Input.is_action_pressed(k) # al cerrar no se dispara lo pulsado en el menú
		return
	# Ronda 30: entrada fluida. Stick (mando o táctil): zona muerta RADIAL + curva de respuesta (girar
	# el stick dibuja un círculo perfecto). Teclado: el vector se interpola ~0,08 s girando (W→D pasa
	# por las diagonales) en vez de saltar de golpe.
	var v := shape_stick(Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0))
	if joystick:
		v = (v + shape_stick(joystick.axis)).limit_length(1.0)
	_smooth = smooth_input(_smooth, v, delta)
	v = _smooth
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
	me.want_charge = enabled and atk_down # ronda 24: fuerte cargado (mantener)
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
	var bs := _pressed_edge("boss")
	var bn := _pressed_edge("boss_next")
	_update_buffer_hit()
	if not enabled:
		_clear_buffer()
		return
	if swp: _try("swap")
	# Ataque: pulsar = ligero (al soltar), mantener 0,4 s = fuerte. En modo arco dispara.
	if me.loadout == Fighter.Loadout.BOW:
		me.hold_pose_t = 0.0
		if atk_edge: _try("shoot")
		me.want_shot_hold = atk_down # ronda 31: mantener = disparo cargado
		_atk_hold = -1.0
	elif atk_down:
		if _atk_hold < 0.0:
			_atk_hold = 0.0
			_heavy_fired = false
		else:
			_atk_hold += delta
		me.hold_pose_t = _atk_hold if not _heavy_fired else 0.0
		if _atk_hold >= Fighter.HEAVY_HOLD and not _heavy_fired:
			_heavy_fired = true
			_try("heavy")
	elif _atk_hold >= 0.0:
		me.hold_pose_t = 0.0
		if not _heavy_fired:
			_try("light")
		_atk_hold = -1.0
	if pr: _try("parry")
	if cn: me.cycle_spell()
	if cs: _try("spell")
	if sm: me.summon()
	if ds: _try("dash")
	if mt: _try("mount")
	if jp: _try("jump")
	if sp: _try("special")
	if bn: me.cycle_boss()
	if bs: _try("boss")
	_update_buffer(delta)

# ---------------- Ronda 23: búfer de entrada ----------------
## Una acción pulsada cuando todavía no es posible (en mitad de un golpe, voltereta, cambio de arma,
## aturdimiento...) se guarda y se ejecuta en el primer fotograma en que sea posible, si no pasaron
## más de `buffer_window` segundos. Gana la última pulsación, salvo que la guardada sea esquivar
## (la esquiva tiene prioridad). Un golpe recibido (nuevo aturdimiento) vacía el búfer; lo pulsado
## DURANTE el aturdimiento sí se guarda y sale al recuperarse.
const BUFFER_WINDOW := 0.4 ## por defecto (estilo souls); configurable en Ajustes
static var buffer_window: float = BUFFER_WINDOW
var buffered: String = ""
var buffer_age: float = 0.0
var buffer_fired: Array[String] = [] ## historial (pruebas / depuración)
var _prev_stun: float = 0.0

func _do(a: String, retry: bool) -> bool:
	match a:
		"light": return me.attack_light() or me._buffered # el combo ya lo encadena
		"heavy": return me.attack_heavy()
		"shoot": return me.shoot()
		"swap": return me.swap_loadout()
		"parry": return not me.mounted and me.parry() # sin parry montado
		"spell": return me.cast_spell()
		"special": return not me.mounted and me.special() # sin Habilidad/Arte montado
		"jump": return me.jump()
		"boss": return me.boss_skill()
		"mount": return me.toggle_mount()
		"dash":
			# Al reintentar no convierte la anticipación de un ligero en estocada con dash
			if retry and me.atk_state == Fighter.Atk.WINDUP:
				return false
			return me.dash()
	return false

func _try(a: String) -> void:
	if _do(a, false):
		if buffered == a:
			_clear_buffer()
		return
	if buffered == "dash" and a != "dash":
		return # la esquiva guardada tiene prioridad
	buffered = a
	buffer_age = 0.0

func _update_buffer(delta: float) -> void:
	if buffered == "":
		return
	buffer_age += delta
	if buffer_age > buffer_window:
		_clear_buffer() # caducó
		return
	if buffer_age <= 0.0:
		return
	if _do(buffered, true):
		buffer_fired.append(buffered)
		_clear_buffer()

func _update_buffer_hit() -> void:
	if me.stun > _prev_stun + 0.001:
		_clear_buffer() # lo golpearon: se descarta lo pulsado antes
	_prev_stun = me.stun

func _clear_buffer() -> void:
	buffered = ""
	buffer_age = 0.0
