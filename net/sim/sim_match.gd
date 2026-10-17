class_name SimMatch
extends Node
## Partida local a dos jugadores sobre FightSim (fase 8: toda partida offline; rival = SimAI).
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
		net.rematch_started.connect(_on_net_rematch)
	else:
		engine = FightEngine.new(params, 1, true)
	engine.fx = fx
	fx.callback = func(ev: Dictionary) -> void:
		if on_event.is_valid():
			on_event.call(ev)
	view = SimView.new(a, b, parent)
	view.params = params
	view.smooth = net != null
	AdminMode.on_toggled = func(on: bool) -> void: set_admin_mode(on)
	if AdminMode.enabled:
		_apply_admin_rules()

signal rematch_started
## Fase 9: revancha online acordada. Sesión nueva (mismos params, semilla nueva): efectos nuevos
## (las claves de evento empiezan otra vez en el tick 0) y la vista vuelve al estado inicial.
func _on_net_rematch() -> void:
	engine = net.engine
	var cb := fx.callback
	fx = SimFx.new()
	fx.hold_ticks = net.fx_hold_ticks
	fx.local_slot = local_slot
	fx.callback = cb
	engine.fx = fx
	_ended = false
	last_confirmed_wins = [0, 0]
	state = net.session.state
	view.apply(state)
	rematch_started.emit()

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

var _backup_boss_ids: Array = []

func _apply_admin_rules() -> void:
	if state.is_empty() or params.is_empty():
		return
	var po := local_slot * FightSim.F_FIELDS
	var p_params: Dictionary = params[local_slot]
	var p_max_hp := int(p_params.get("hp", 100000))
	var p_max_st := int(p_params.get("st_max", 100000))
	var p_max_mana := int(p_params.get("mana_max", 100000))
	state[po + FightSim.HP] = p_max_hp
	state[po + FightSim.ST] = p_max_st
	state[po + FightSim.MANA] = p_max_mana
	state[po + FightSim.EXH] = 0
	state[po + FightSim.FLASKS] = 5
	state[po + FightSim.METER] = 100000
	state[po + FightSim.ALIVE] = 1
	state[po + FightSim.BOSS_CD] = 0
	for k in 64:
		state[po + FightSim.BCD_BASE + k] = 0

	var opp_slot := 1 - local_slot
	var eo := opp_slot * FightSim.F_FIELDS
	var e_params: Dictionary = params[opp_slot]
	var e_max_hp := int(e_params.get("hp", 100000))
	state[eo + FightSim.ALIVE] = 1
	state[FightSim.P_BASE + FightSim.G_END_T] = 0
	if state[eo + FightSim.HP] <= e_max_hp * 30 / 100 or state[eo + FightSim.HP] <= 1000:
		state[eo + FightSim.HP] = e_max_hp

	if fighters.size() > local_slot:
		var f := fighters[local_slot]
		var total_ids := BossAbilities.all_ids()
		if f.boss_ids.size() < total_ids.size():
			if _backup_boss_ids.is_empty():
				_backup_boss_ids = f.boss_ids.duplicate()
			f.boss_ids = total_ids.duplicate()
			p_params["boss"] = SimAbilities.compile_all(f)
			p_params["boss_n"] = total_ids.size()

func set_admin_mode(enabled: bool) -> void:
	if not enabled and not _backup_boss_ids.is_empty() and fighters.size() > local_slot:
		var f := fighters[local_slot]
		f.boss_ids = _backup_boss_ids.duplicate()
		_backup_boss_ids.clear()
		params[local_slot]["boss"] = SimAbilities.compile_all(f)
		params[local_slot]["boss_n"] = f.boss_ids.size()
		var po := local_slot * FightSim.F_FIELDS
		state[po + FightSim.AB_SEL] = mini(int(state[po + FightSim.AB_SEL]), maxi(f.boss_ids.size() - 1, 0))

func cycle_boss_prev() -> void:
	if state.is_empty() or params.is_empty():
		return
	var po := local_slot * FightSim.F_FIELDS
	var n: int = SimAbilities.boss_avail(state, params, local_slot)
	if n > 1:
		state[po + FightSim.AB_SEL] = (int(state[po + FightSim.AB_SEL]) - 1 + n) % n
		state[po + FightSim.BOSS_CD] = state[po + FightSim.BCD_BASE + state[po + FightSim.AB_SEL]]

func select_boss_ability(idx: int) -> void:
	if state.is_empty() or params.is_empty():
		return
	var po := local_slot * FightSim.F_FIELDS
	var n: int = SimAbilities.boss_avail(state, params, local_slot)
	if n > 0:
		state[po + FightSim.AB_SEL] = clampi(idx, 0, n - 1)
		state[po + FightSim.BOSS_CD] = state[po + FightSim.BCD_BASE + state[po + FightSim.AB_SEL]]

func step_once() -> void:
	if net:
		_net_step()
		return
	var a := _sample(0)
	var b := _sample(1)
	engine.step(state, a, b)
	if AdminMode.enabled:
		_apply_admin_rules()
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

## Fase 9: pulsación garantizada de un botón (▶, toques breves): el bit sale exactamente en un
## tick muestreado y al siguiente no, así la sim ve un único flanco aunque el toque dure menos que
## un tick o el botón de la interfaz no tenga acción mantenida. Varias pulsaciones se encolan con un
## tick libre entre ellas.
var _pulses: Array[int] = []
var _pulse_gap := 0
func pulse(bit: int) -> void:
	if _pulses.size() < 8:
		_pulses.append(bit)

func _take_pulse() -> int:
	if _pulse_gap != 0:
		_pulse_gap = 0
		return 0
	if _pulses.is_empty():
		return 0
	_pulse_gap = 1
	return _pulses.pop_front()

## Toques de teclado/táctiles más cortos que un tick: se convierten en pulso (si no, se perderían).
const PULSE_ACTIONS := ["boss_next", "spell_next", "boss", "spell", "flask", "boss_variation"]
func _input(ev: InputEvent) -> void:
	if not running or ev.is_echo():
		return
	for a: String in PULSE_ACTIONS:
		if InputMap.has_action(a) and ev.is_action_pressed(a):
			_tap_seen[a] = Engine.get_physics_frames()
var _tap_seen := {}

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
		v |= aim_input(i)
		var held := v
		# toque que empezó y acabó entre dos ticks: sin bit mantenido, pulso de un tick
		for a: String in _tap_seen:
			var bit: int = EXTRA_ACTIONS.get(a, 0)
			if bit != 0 and (held & bit) == 0 and not Input.is_action_pressed(a) and not _pulses.has(bit):
				_pulses.append(bit)
		_tap_seen.clear()
		v |= _take_pulse()
	return v

## Fase 9: apuntado del arco con el ratón (PC). Con el arco en la mano y sin controles táctiles,
## el rumbo hacia el punto del suelo bajo el cursor (o el frente de la cámara si el ratón está
## capturado) viaja en la entrada (FightSim.aim_bits) y la sim lo usa: igual offline y online.
static var mouse_aim := true
## Pruebas: fuerza un punto de mira en el mundo (sin ratón real).
var aim_world_override: Variant = null

func aim_input(i: int) -> int:
	if not mouse_aim or i != local_slot or state.size() == 0 or fighters.size() < 2:
		return 0
	if state[i * FightSim.F_FIELDS + FightSim.LOADOUT] != FightSim.Load.BOW:
		return 0
	var f := fighters[i]
	var target: Vector3
	if aim_world_override != null:
		target = aim_world_override
	else:
		if (joystick and joystick.visible) or camera == null or not camera.is_inside_tree():
			return 0
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			target = f.global_position + MeshUtil.flat(-camera.global_transform.basis.z) * 10.0
		else:
			var vp := camera.get_viewport()
			var mp := vp.get_mouse_position()
			if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mp):
				return 0
			var from := camera.project_ray_origin(mp)
			var dir := camera.project_ray_normal(mp)
			if absf(dir.y) < 0.001:
				return 0
			var t := (1.0 - from.y) / dir.y # plano a la altura del pecho
			if t <= 0.0:
				return 0
			target = from + dir * t
	var d := MeshUtil.flat(target - f.global_position)
	if d.length() < 0.6:
		return 0
	return FightSim.aim_bits(FxMath.dir_of(SimParams.um(d.x), SimParams.um(d.z)))

## Fase 4: botones de jefe, magia, eikon y montura (la sim detecta el flanco de pulsación).
const EXTRA_ACTIONS := {"boss": FightSim.IN_BOSS, "boss_next": FightSim.IN_BOSS_NEXT, "spell": FightSim.IN_SPELL,
	"spell_next": FightSim.IN_SPELL_NEXT, "summon": FightSim.IN_EIKON, "special": FightSim.IN_ART, "mount": FightSim.IN_MOUNT,
	"boss_variation": FightSim.IN_BOSS_VAR, "jump": FightSim.IN_JUMP, "flask": FightSim.IN_FLASK}
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
