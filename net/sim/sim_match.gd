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
var joy_device := 0 ## mando del jugador 2 (solo partida local)
var local_slot := 0 ## índice de sim que controlan teclado/ratón/táctil y sigue la cámara
var joystick: TouchStick ## joystick táctil del HUD (móvil)
var net: NetMatch ## partida online: la sim la avanza RbSession con rollback
var sprint_latch := false ## botón táctil «Correr» (alternar)
var _prev_run := false
signal match_ended(winner_slot: int, reason: String)
var _ended := false
var last_confirmed_wins := [0, 0]
var on_event: Callable ## func(ev) para sonido/partículas/sacudida del anfitrión
var tick_n := 0
var _lock := [true, true]
var _prev_lock := [false, false]
var _hand_t := [0, 0]
var _hand_prev := [false, false]
const HAND_HOLD := 11 ## ticks (PlayerController.LEFT_HOLD_FOR_SHIELD 0,18 s)

## a = jugador 0 de la sim, b = jugador 1 (en online el anfitrión es siempre el 0).
func setup(a: Fighter, b: Fighter, parent: Node3D, online: NetMatch = null) -> void:
	fighters = [a, b]
	params = SimParams.bake(a, b)
	params_hash = SimParams.params_checksum(params) # se intercambia en el saludo de red (RbSession.params_hash)
	net = online
	if net:
		local_slot = net.me
		net.start_play(params, spawn_of(a, b))
		engine = net.engine
		params_hash = net.session.params_hash # incluye el ajuste online (holgura de parada)
		fx.hold_ticks = net.fx_hold_ticks
		fx.local_slot = local_slot
	else:
		engine = FightEngine.new(params, 1, true)
	engine.fx = fx
	fx.callback = func(ev: Dictionary) -> void:
		if on_event.is_valid():
			on_event.call(ev)
	view = SimView.new(a, b, parent)
	view.smooth = net != null

static func spawn_of(a: Fighter, b: Fighter) -> Array[int]:
	var sp: Array[int] = []
	for f in [a, b]:
		sp.append(SimParams.um(f.global_position.x)); sp.append(SimParams.um(f.global_position.z))
		sp.append(FxMath.dir_of(SimParams.um(f.facing.x), SimParams.um(f.facing.z)))
	return sp

## Reinicia el estado desde las posiciones de aparición de los Fighter.
func reset_round() -> void:
	if net:
		state = net.session.state
		view.apply(state)
		running = true
		return
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
	if net:
		_net_step()
		return
	var a := _sample(0)
	var b := _sample(1)
	engine.step(state, a, b)
	tick_n += 1
	view.apply(state)

func _net_step() -> void:
	net.play_step(_sample(local_slot))
	state = net.session.state
	tick_n += 1
	view.apply(state, net.session.last_resim > 0)
	if _ended:
		return
	if net.phase == NetMatch.Ph.OVER:
		_ended = true
		var w := local_slot if net.status in ["forfeit_win", "peer_left", "disconnected", "load_timeout"] else 1 - local_slot
		net.save_replay()
		match_ended.emit(w, net.status)
		return
	var cs := net.confirmed_state()
	last_confirmed_wins = [cs[FightSim.P_BASE + FightSim.G_WINS0], cs[FightSim.P_BASE + FightSim.G_WINS1]]
	var w2 := engine.match_over(cs)
	if w2 >= 0:
		_ended = true
		net.save_replay()
		match_ended.emit(w2, "ko")

func _sample(i: int) -> int:
	if input_override[i].is_valid():
		return int(input_override[i].call(tick_n))
	return sample_device(i)

## Teclado/ratón para el jugador 1; mando joy_device para el 2. Movimiento relativo a la cámara.
func sample_device(i: int) -> int:
	var mv := Vector2.ZERO
	var atk := false; var hand := false; var roll := false; var sprint := false; var swap := false; var lock := false
	if i == local_slot:
		mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if joystick and joystick.visible:
			mv = (mv + PlayerController.shape_stick(joystick.axis)).limit_length(1.0)
		var run := Input.is_action_pressed("run_toggle")
		if run and not _prev_run:
			sprint_latch = not sprint_latch
		_prev_run = run
		atk = Input.is_action_pressed("attack_sword")
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			atk = true # PC: clic izquierdo con el ratón capturado por la cámara
		hand = Input.is_action_pressed("left_hand")
		roll = Input.is_action_pressed("dash")
		if mv.length() < 0.2 or state.size() > 0 and state[i * FightSim.F_FIELDS + FightSim.EXH] > 0:
			sprint_latch = false
		sprint = Input.is_action_pressed("sprint") or sprint_latch
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
	var v := SimView.pack_input(world_move(i, mv), mv.length() < 0.6 and mv.length() > 0.2, atk, block, parry, roll, sprint, swap, _lock[i])
	if i == local_slot:
		v |= extra_buttons()
	return v

## Fase 4: botones de jefe, magia, eikon y montura (la sim detecta el flanco de pulsación).
const EXTRA_ACTIONS := {"boss": FightSim.IN_BOSS, "boss_next": FightSim.IN_BOSS_NEXT, "spell": FightSim.IN_SPELL,
	"spell_next": FightSim.IN_SPELL_NEXT, "summon": FightSim.IN_EIKON, "special": FightSim.IN_EIKON, "mount": FightSim.IN_MOUNT}
var hud_buttons := 0 ## botones táctiles del HUD (los fija la arena)
static func extra_buttons_from(held: Callable) -> int:
	var v := 0
	for a: String in EXTRA_ACTIONS:
		if InputMap.has_action(a) and held.call(a): v |= int(EXTRA_ACTIONS[a])
	return v
func extra_buttons() -> int:
	return extra_buttons_from(func(a: String) -> bool: return Input.is_action_pressed(a)) | hud_buttons

## Stick (x derecha, y abajo) -> mundo: relativo a la cámara para el jugador 1, al rival para el 2.
func world_move(i: int, mv: Vector2) -> Vector3:
	var f := fighters[i]
	var fwd := Vector3.FORWARD
	if i == local_slot and camera:
		fwd = MeshUtil.flat(-camera.global_transform.basis.z).normalized()
	else:
		var d := MeshUtil.flat(fighters[1 - i].global_position - f.global_position)
		fwd = d.normalized() if d.length() > 0.1 else f.facing
	var right := fwd.cross(Vector3.UP)
	return right * mv.x + fwd * -mv.y
