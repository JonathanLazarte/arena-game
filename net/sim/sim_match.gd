class_name SimMatch
extends Node
## Partida local a dos jugadores sobre FightSim (modo sim de la arena, Arena.sim_mode).
## Cada tick físico: muestrea las dos entradas, empaqueta con SimView.pack_input, avanza la sim,
## vuelca el estado en los Fighter (SimView) y dispara efectos deduplicados (SimFx).
## Es el mismo bucle que usará RbSession en red, sin la capa de transporte.
var params: Array
var params_hash: int
var engine: FightEngine
var state: PackedInt64Array
var view: SimView
var fx := SimFx.new()
var fighters: Array[Fighter] = []
var camera: Camera3D
var running := false
## Sustituye la entrada de un jugador: func(tick: int) -> int (pruebas, bots, red). Vacío = dispositivo.
var input_override: Array[Callable] = [Callable(), Callable()]
var joy_device := 0 ## mando del jugador 2
var on_event: Callable ## func(ev) para sonido/partículas/sacudida del anfitrión
var tick_n := 0
var _lock := [true, true]
var _prev_lock := [false, false]
var _hand_t := [0, 0]
var _hand_prev := [false, false]
const HAND_HOLD := 11 ## ticks (PlayerController.LEFT_HOLD_FOR_SHIELD 0,18 s)

func setup(a: Fighter, b: Fighter, parent: Node3D) -> void:
	fighters = [a, b]
	params = SimParams.bake(a, b)
	params_hash = SimParams.params_checksum(params) # se intercambia en el saludo de red (RbSession.params_hash)
	engine = FightEngine.new(params, 1, true)
	engine.fx = fx
	fx.callback = func(ev: Dictionary) -> void:
		if on_event.is_valid():
			on_event.call(ev)
	view = SimView.new(a, b, parent)

## Reinicia el estado desde las posiciones de aparición de los Fighter.
func reset_round() -> void:
	state = engine.initial()
	for i in 2:
		var f := fighters[i]
		var o := i * FightSim.F_FIELDS
		state[o + FightSim.X] = SimParams.um(f.global_position.x)
		state[o + FightSim.Z] = SimParams.um(f.global_position.z)
		state[o + FightSim.FACE] = FxMath.dir_of(SimParams.um(f.facing.x), SimParams.um(f.facing.z))
	view.apply(state)
	running = true

func _physics_process(_d: float) -> void:
	if running:
		step_once()

func step_once() -> void:
	var a := _sample(0)
	var b := _sample(1)
	engine.step(state, a, b)
	tick_n += 1
	view.apply(state)

func _sample(i: int) -> int:
	if input_override[i].is_valid():
		return int(input_override[i].call(tick_n))
	return sample_device(i)

## Teclado/ratón para el jugador 1; mando joy_device para el 2. Movimiento relativo a la cámara.
func sample_device(i: int) -> int:
	var mv := Vector2.ZERO
	var atk := false; var hand := false; var roll := false; var sprint := false; var swap := false; var lock := false
	if i == 0:
		mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		atk = Input.is_action_pressed("attack_sword")
		hand = Input.is_action_pressed("left_hand")
		roll = Input.is_action_pressed("dash")
		sprint = Input.is_action_pressed("sprint")
		swap = Input.is_action_pressed("swap_weapon")
		lock = Input.is_action_pressed("lock_on")
	else:
		mv = Vector2(Input.get_joy_axis(joy_device, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy_device, JOY_AXIS_LEFT_Y))
		if mv.length() < 0.2: mv = Vector2.ZERO
		atk = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_X)
		hand = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_LEFT_SHOULDER)
		roll = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_B)
		sprint = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_LEFT_STICK)
		swap = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_Y)
		lock = Input.is_joy_button_pressed(joy_device, JOY_BUTTON_RIGHT_STICK)
	if lock and not _prev_lock[i]:
		_lock[i] = not _lock[i]
	_prev_lock[i] = lock
	# mano izquierda: mantener = escudo, toque = parada (como PlayerController)
	var block := false; var parry := false
	if hand:
		_hand_t[i] = _hand_t[i] + 1 if _hand_prev[i] else 0
		block = _hand_t[i] >= HAND_HOLD
	elif _hand_prev[i]:
		parry = _hand_t[i] < HAND_HOLD
	_hand_prev[i] = hand
	return SimView.pack_input(world_move(i, mv), mv.length() < 0.6 and mv.length() > 0.2, atk, block, parry, roll, sprint, swap, _lock[i])

## Stick (x derecha, y abajo) -> mundo: relativo a la cámara para el jugador 1, al rival para el 2.
func world_move(i: int, mv: Vector2) -> Vector3:
	var f := fighters[i]
	var fwd := Vector3.FORWARD
	if i == 0 and camera:
		fwd = MeshUtil.flat(-camera.global_transform.basis.z).normalized()
	else:
		var d := MeshUtil.flat(fighters[1 - i].global_position - f.global_position)
		fwd = d.normalized() if d.length() > 0.1 else f.facing
	var right := fwd.cross(Vector3.UP)
	return right * mv.x + fwd * -mv.y
