class_name PlayerController
extends Node
## Fase 8: la entrada la muestrea SimMatch (bits de la sim). Aquí quedan las ayudas del HUD/cámara:
## objetivo fijado y su ciclo, forma del stick táctil, menú abierto y estado de «Correr».
## Lock-on (fijar objetivo) activado por defecto: Tab o botón "Fijar".

var me: Fighter
var camera: Camera3D
var joystick: TouchStick
var enabled: bool = true
## Ronda 30: menú abierto (sin pausar): quieto y en guardia, sin acciones.
var menu_hold: bool = false
var lock_on: bool = true
const LEFT_HOLD_FOR_SHIELD := 0.18
## Ventana del búfer de acciones (Ajustes → Controles); offline se hornea en P[0]["buffer"] de la sim.
const BUFFER_WINDOW := 0.4
static var buffer_window: float = BUFFER_WINDOW
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
const INPUT_SMOOTH := 0.03 ## s para completar un cambio de dirección de 90° (fase 7: antes 0,08)
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

func _process(_d: float) -> void:
	if _wheel != 0:
		_wheel = 0
		cycle_target()
