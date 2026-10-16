class_name CameraRig
extends Node
## Ronda 25: cámara orbital.
## PC: arrastrar con el botón derecho (por defecto) o ratón capturado (opción en Ajustes; Esc lo suelta).
## Android: arrastrar en la mitad derecha de la pantalla (fuera de los botones).
## Con objetivo fijado la cámara sigue al objetivo; un tirón horizontal rápido cambia de objetivo.
## Choca con los pilares y el muro (se acerca) y limita la inclinación.

static var sensitivity: float = 1.0
static var invert_y: bool = false
static var capture_mouse: bool = false
const PITCH_MIN := -0.15 ## rad (un poco por debajo del horizonte)
const PITCH_MAX := 1.1 ## rad (~63°, casi cenital)
const PITCH_DEFAULT := 0.5
const DIST := 9.5
const MOUSE_K := 0.005
const TOUCH_K := 0.008
const FLICK_PX := 140.0 ## tirón horizontal (px en 0,25 s) que cambia de objetivo con lock-on
const RECENTER_DELAY := 1.5
const RECENTER_RATE := 1.2

var camera: Camera3D
var player: Fighter
var controller: PlayerController
var hud: Node
var yaw: float = 0.0
var pitch: float = PITCH_DEFAULT
var obstacles: Array = [] ## Vector3(x, radio, z)
var arena_radius: float = 42.0
var active: bool = true ## en combate (captura de ratón)
var _drag: bool = false
var _touch_idx: int = -1
var _idle_t: float = 99.0
var _flick: float = 0.0
var _flick_t: float = 0.0
var _released: bool = false
var menu_open: bool = false ## ronda 30: menú de pausa abierto (ratón libre)
var flicks: int = 0 ## cambios de objetivo con tirón (pruebas)
var _execution_left: float = 0.0
var _execution_duration: float = 0.8
var _execution_attacker: Fighter
var _execution_target: Fighter
var _home_fov: float = 70.0

func play_execution(attacker: Fighter, target: Fighter, duration: float = 0.8) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	if _execution_left <= 0.0 and camera:
		_home_fov = camera.fov
	_execution_attacker = attacker
	_execution_target = target
	_execution_duration = maxf(duration, 0.1)
	_execution_left = _execution_duration

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.pressed and capture_mouse and _released and not menu_open and mb.button_index == MOUSE_BUTTON_LEFT:
			_released = false
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			orbit(mm.relative * MOUSE_K)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed and _touch_idx < 0 and _touch_ok(st.position):
			_touch_idx = st.index
		elif not st.pressed and st.index == _touch_idx:
			_touch_idx = -1
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if sd.index == _touch_idx:
			orbit(sd.relative * TOUCH_K)

## Toque válido para orbitar: mitad derecha y fuera de los botones táctiles visibles.
func _touch_ok(pos: Vector2) -> bool:
	var vw := get_viewport().get_visible_rect().size
	if pos.x < vw.x * 0.5:
		return false
	if hud and "btns" in hud:
		for b: TouchScreenButton in (hud.btns as Dictionary).values():
			if b.visible and b.shape is CircleShape2D and pos.distance_to(b.global_position) < (b.shape as CircleShape2D).radius + 12.0:
				return false
	return true

## rel: radianes aproximados (x = giro, y = inclinación).
func orbit(rel: Vector2) -> void:
	_idle_t = 0.0
	var locked := player != null and is_instance_valid(player.face_target)
	if locked:
		_flick += rel.x / MOUSE_K
		_flick_t = 0.25
		if absf(_flick) > FLICK_PX and controller:
			controller.cycle_target()
			flicks += 1
			_flick = 0.0
	else:
		yaw -= rel.x * sensitivity
	pitch = clampf(pitch + rel.y * sensitivity * (-1.0 if invert_y else 1.0), PITCH_MIN, PITCH_MAX)

func _offset(y: float, p: float, d: float) -> Vector3:
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d

func update(delta: float) -> void:
	if camera == null or player == null:
		return
	_idle_t += delta
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick = 0.0
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		var want := capture_mouse and active and not _released and not menu_open
		var mode := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != mode and (want or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
			Input.mouse_mode = mode
	var pivot := player.global_position + Vector3(0, 2.0, 0)
	var look := pivot
	var dist := DIST
	var tgt: Node3D = player.face_target if is_instance_valid(player.face_target) else null
	if tgt:
		# Lock-on: detrás del jugador, mirando al objetivo (sobre el hombro)
		var d := MeshUtil.flat(tgt.global_position - player.global_position)
		var dl := d.length()
		var dn := d.normalized() if dl > 0.1 else player.facing
		yaw = lerp_angle(yaw, atan2(-dn.x, -dn.z), clampf(delta * 6.0, 0.0, 1.0))
		dist = 8.0 + clampf(dl * 0.15, 0.0, 5.0)
		pivot += dn.cross(Vector3.UP) * 1.6
		look = player.global_position.lerp(tgt.global_position, 0.5) + Vector3(0, 1.5, 0)
	elif _idle_t > RECENTER_DELAY and player.planar_vel.length() > 2.0:
		# Sin tocar la cámara y avanzando: vuelve poco a poco detrás (no al ir hacia la cámara)
		var fwd := MeshUtil.flat(-camera.global_transform.basis.z).normalized()
		if player.facing.dot(fwd) > 0.3:
			yaw = lerp_angle(yaw, atan2(-player.facing.x, -player.facing.z), clampf(delta * RECENTER_RATE, 0.0, 1.0))
	var cinematic_weight := 0.0
	if _execution_left > 0.0 and is_instance_valid(_execution_attacker) and is_instance_valid(_execution_target):
		_execution_left = maxf(_execution_left - delta, 0.0)
		var progress := 1.0 - _execution_left / _execution_duration
		cinematic_weight = smoothstep(0.0, 0.18, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
		var duel_axis := MeshUtil.flat(_execution_target.global_position - _execution_attacker.global_position).normalized()
		if duel_axis.length() > 0.1:
			var side := Vector3(duel_axis.z, 0.0, -duel_axis.x)
			var side_yaw := atan2(side.x, side.z)
			var other_side_yaw := side_yaw + PI
			if absf(wrapf(yaw - other_side_yaw, -PI, PI)) < absf(wrapf(yaw - side_yaw, -PI, PI)):
				side_yaw = other_side_yaw
			yaw = lerp_angle(yaw, side_yaw, cinematic_weight)
		pitch = lerpf(pitch, 0.24, cinematic_weight)
		var center := _execution_attacker.global_position.lerp(_execution_target.global_position, 0.5)
		var focus := center + Vector3(0.0, 1.55, 0.0)
		pivot = pivot.lerp(focus, cinematic_weight)
		look = look.lerp(focus, cinematic_weight)
		dist = lerpf(dist, 6.4, cinematic_weight)
	else:
		_execution_left = 0.0
		_execution_attacker = null
		_execution_target = null
	camera.fov = lerpf(_home_fov, 52.0, cinematic_weight)
	var want_pos := pivot + _offset(yaw, pitch, dist)
	camera.global_position = camera.global_position.lerp(_collide(pivot, want_pos), clampf(delta * 10.0, 0.0, 1.0))
	if camera.global_position.distance_to(look) > 0.5:
		camera.look_at(look, Vector3.UP)

## Acerca la cámara si un pilar o el muro se interponen; nunca por debajo del suelo.
func _collide(from: Vector3, to: Vector3) -> Vector3:
	var steps := 24
	var last := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		var blocked := Vector2(p.x, p.z).length() > arena_radius - 1.5
		if not blocked:
			for o: Vector3 in obstacles:
				if p.y < 9.0 and Vector2(p.x - o.x, p.z - o.z).length() < o.y + 0.5:
					blocked = true
					break
		if blocked:
			return last
		last = p
	last.y = maxf(last.y, 0.5)
	return last

func reset_behind() -> void:
	if player:
		yaw = atan2(-player.facing.x, -player.facing.z)
	pitch = PITCH_DEFAULT
	_idle_t = 99.0

func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
