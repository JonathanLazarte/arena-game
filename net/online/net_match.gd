class_name NetMatch
extends RefCounted
## Partida online sobre un NetLink: saludo (versión, RTT, retardo de entrada adaptativo),
## RbSession con FightEngine, sincronía de tiempo por ventaja de fotogramas, intercambio de
## checksums con informe de desincronía, registro de entradas (repetición) y desconexión/abandono.
const PROTO := NetLink.GAME_PROTO
const TICK_MS := 1000.0 / 60.0
const PINGS := 12
const TIMEOUT_MS := 4000
const CK_SEND := 12 ## checksums confirmados recientes por paquete
const MAX_DELAY := 4
const MIN_DELAY := 1
## Tras PREVIEW de fx, el intervalo entre saltos de sincronía (ticks) y el umbral de ventaja.
const SYNC_ADV := 1.5
const SYNC_COOLDOWN := 12

static var current: NetMatch ## partida en curso para la arena (la crea el panel online)

enum Ph { HELLO, PING, START, LOAD, PLAY, OVER }
## Carga de la arena: cada par avisa «rdy» al tener escena y sim listas; la sesión arranca solo
## cuando ambos lo están. Mientras, el límite de desconexión es LOAD_TIMEOUT_MS (no 4 s).
const LOAD_TIMEOUT_MS := 30000
const READY_EVERY_MS := 200
var peer_ready := false
var _ready_at := 0
var _load_started := 0
## false mientras la escena local aún calienta sombreadores/recursos: se envían latidos «ka», no «rdy».
var local_ready := true
## Fase 5, reconexión: tras TIMEOUT_MS sin paquetes la sim se congela y se intenta volver
## (relay: «B» con ficha) durante GRACE_MS; al volver el anfitrión envía una instantánea del
## estado confirmado (época nueva) y ambos repiten el saludo «rdy». Pasado el plazo: abandono.
var grace_ms := 25000 ## algo más que el del relay (20 s), que decide primero con «F»
const SNAP_CHUNK := 900
var reconnecting := false
var reconnects := 0
var epoch := 0
var _reco_since := 0
var _rs_at := 0
var _snap_out: Array = []
var _snap_at := 0
var _snap_in: Dictionary = {}
## Resincronizaciones de la partida [[tick, estado]] (la repetición continúa desde ellas).
var resyncs: Array = []
var load_ms := 0 ## lo que tardó en arrancar (pruebas / overlay)
var phase: Ph = Ph.HELLO
var link: NetLink
var me := 0
var input_delay := 2
var seed_v := 1
var session: RbSession
var engine: FightEngine
var status := "" ## "", "desync", "disconnected", "peer_left", "forfeit_win", "forfeit_loss", "params_mismatch", "version"
var rtt_ms := 0.0
var rtt_samples: Array[float] = []
var peer_frame := -1
var peer_ack := -1
var adv_avg := 0.0
var sync_skips := 0
var _skip_cool := 0
var peer_ck: Dictionary = {}
var checked_to := -1
var desync_frame := -1
var desync_report := ""
var log_dir := "user://net"
var _ping_at := 0
var _pings_sent := 0
var _hello_at := 0
var _peer_hello := false
var _start_sent_at := 0
var _peer_started := false
var _last_send_ms := 0
## Equipo del lobby (NetLoadout.from_game_state); se envía en el saludo. Vacío = equipo estándar.
var local_loadout: Dictionary = {}
var peer_loadout: Dictionary = {}
## Retardo adaptativo durante la partida (histéresis): subir tras UP_TICKS seguidos pidiendo más,
## bajar tras DOWN_TICKS pidiendo menos con 15 ms de margen; como mucho un cambio cada COOLDOWN.
var adaptive_delay := true
const UP_TICKS := 90
const DOWN_TICKS := 300
const DELAY_COOLDOWN := 180
const DOWN_MARGIN_MS := 15.0
var delay_changes := 0
var start_delay := 2
var _want_up := 0
var _want_down := 0
var _delay_cool := 0
## Holgura de parada online (ticks) aplicada a los params al empezar (ver SimParams.online_tuning).
var parry_lenience := 0
var fx_hold_ticks := 2

func _init(l: NetLink) -> void:
	link = l
	me = l.slot

## Retardo de entrada para un RTT: la mitad del viaje en ticks, acotado.
static func delay_for_rtt(rtt: float) -> int:
	return clampi(int(round(rtt * 0.5 / TICK_MS)) - 1, MIN_DELAY, MAX_DELAY) # el rollback cubre el resto

# ---------------- saludo ----------------
## Llamar cada tick hasta que devuelva true (entonces llamar start_play).
func prelude_step() -> bool:
	link.poll()
	var t := NetLink.now_ms()
	for m: Dictionary in _drain():
		match String(m.get("t", "")):
			"hi":
				if int(m.get("v", 0)) != PROTO:
					status = "version"
				_peer_hello = true
				var lo: Variant = m.get("lo", {})
				peer_loadout = lo if lo is Dictionary else {}
			"ping": link.send_msg({"t": "pong", "s": m.get("s", 0)})
			"pong":
				rtt_samples.append(float(t - int(m.get("s", 0))))
			"start":
				if me == 1:
					input_delay = int(m["delay"]); seed_v = int(m["seed"])
					_peer_started = true
					link.send_msg({"t": "go"})
			"go":
				if me == 0: _peer_started = true
	if status != "": return false
	if link.peer_left or t - link.last_recv_ms > TIMEOUT_MS * 2:
		status = "disconnected"; return false
	if not _peer_hello and t >= _hello_at:
		_hello_at = t + 200
		link.send_msg({"t": "hi", "v": PROTO, "lo": local_loadout})
	if _peer_hello and _pings_sent < PINGS and t >= _ping_at:
		_ping_at = t + 40
		_pings_sent += 1
		link.send_msg({"t": "ping", "s": t})
	if _peer_hello and phase == Ph.HELLO:
		link.send_msg({"t": "hi", "v": PROTO, "lo": local_loadout}) # que el rival también nos vea
		phase = Ph.PING
	if me == 0 and phase == Ph.PING and (rtt_samples.size() >= PINGS - 2 or (_pings_sent >= PINGS and t - _ping_at > 600)):
		rtt_ms = _median(rtt_samples) if not rtt_samples.is_empty() else 100.0
		input_delay = delay_for_rtt(rtt_ms)
		seed_v = 1 + randi() % 100000
		phase = Ph.START
	if me == 0 and phase == Ph.START and not _peer_started and t >= _start_sent_at:
		_start_sent_at = t + 150
		link.send_msg({"t": "start", "delay": input_delay, "seed": seed_v})
	if me == 1 and _peer_started and not rtt_samples.is_empty():
		rtt_ms = _median(rtt_samples)
	return _peer_started and link.pending_out() == 0 # el «go» del invitado debe haber salido

func _median(a: Array[float]) -> float:
	var b := a.duplicate(); b.sort()
	return b[b.size() / 2]

## Equipos por hueco de sim: [anfitrión, invitado].
func loadouts_by_slot() -> Array[Dictionary]:
	return [local_loadout, peer_loadout] if me == 0 else [peer_loadout, local_loadout]

func start_play(params: Array, spawn: Array[int] = []) -> void:
	start_delay = input_delay
	parry_lenience = SimParams.lenience_for_delay(input_delay)
	params = SimParams.online_tuning(params, parry_lenience)
	engine = FightEngine.new(params, seed_v, true)
	engine.rounds = true
	engine.spawn = spawn
	session = RbSession.new(me, input_delay, 8, engine)
	session.params_hash = SimParams.params_checksum(params)
	phase = Ph.LOAD
	_load_started = NetLink.now_ms()
	link.last_recv_ms = _load_started # nuestra propia carga no cuenta como silencio del rival
	_ready_at = 0

## Mientras la escena del otro par carga: avisar «rdy», contestar pings, aceptar ya sus entradas.
func _load_step(t: int) -> void:
	for m: Dictionary in _drain():
		_handle(m, t)
	if status != "":
		phase = Ph.OVER
		return
	if link.peer_left:
		status = "peer_left"; phase = Ph.OVER; return
	if me == 0 and not _snap_out.is_empty() and not peer_ready and t >= _snap_at:
		_send_snap(t)
	if t - link.last_recv_ms > LOAD_TIMEOUT_MS:
		status = "load_timeout"; phase = Ph.OVER; return
	if t >= _ready_at:
		_ready_at = t + READY_EVERY_MS
		link.send_msg({"t": "rdy" if local_ready else "ka", "ep": epoch}, true) # también sirve de latido
	if peer_ready and local_ready:
		phase = Ph.PLAY
		load_ms = t - _load_started
		link.last_recv_ms = maxi(link.last_recv_ms, t)
		for i in 2: link.send_msg({"t": "rdy", "ep": epoch}, true)
		_snap_out = []

## ¿Esperando a que cargue el rival? (la arena muestra «Cargando rival…»)
func waiting_peer() -> bool:
	return phase == Ph.LOAD

# ---------------- partida ----------------
## Un tick físico. Devuelve true si la sim avanzó.
func play_step(local_input: int) -> bool:
	if phase == Ph.LOAD:
		link.poll()
		_load_step(NetLink.now_ms())
		_rematch_tick(NetLink.now_ms())
		return false
	if phase != Ph.PLAY:
		return false
	link.poll()
	var t := NetLink.now_ms()
	for m: Dictionary in _drain():
		_handle(m, t)
	_after_msgs(t)
	_rematch_tick(t)
	if phase != Ph.PLAY or reconnecting:
		return false # congelado mientras se reconecta
	return _play_tick(local_input, t)

func _host_resync() -> void:
	epoch += 1
	var f := confirmed_frame() + 1
	var st := confirmed_state()
	var raw := var_to_bytes(st).compress(FileAccess.COMPRESSION_DEFLATE)
	var n := int(ceil(raw.size() / float(SNAP_CHUNK)))
	_snap_out = []
	for i in n:
		_snap_out.append({"t": "snap", "ep": epoch, "f": f, "i": i, "n": n, "sz": var_to_bytes(st).size(),
			"b": raw.slice(i * SNAP_CHUNK, mini(raw.size(), (i + 1) * SNAP_CHUNK))})
	_resync_apply(st, f)
	_send_snap(NetLink.now_ms())

func _send_snap(t: int) -> void:
	_snap_at = t + 300
	for m: Dictionary in _snap_out: link.send_msg(m, true)

func _guest_snap(m: Dictionary) -> void:
	var ep := int(m.get("ep", 0))
	if me != 1 or ep <= epoch: return
	if int(_snap_in.get("ep", -1)) != ep: _snap_in = {"ep": ep, "parts": {}}
	_snap_in["parts"][int(m["i"])] = m["b"]
	var n := int(m["n"])
	if _snap_in["parts"].size() < n: return
	var raw := PackedByteArray()
	for i in n: raw.append_array(_snap_in["parts"][i])
	var v: Variant = bytes_to_var(raw.decompress(int(m["sz"]), FileAccess.COMPRESSION_DEFLATE))
	if not (v is PackedInt64Array): return
	epoch = ep
	_snap_in = {}
	_resync_apply(v, int(m["f"]))

func _resync_apply(st: PackedInt64Array, f: int) -> void:
	resyncs.append([f, st.duplicate()])
	# los checksums posteriores al último tick confirmado salieron de entradas predichas: no valen
	var cf := confirmed_frame()
	for k: int in session.checksums.keys():
		if k > cf: session.checksums.erase(k)
	session.reset_to(st, f)
	reconnecting = false
	reconnects += 1
	peer_ready = false
	peer_ack = -1; peer_frame = -1; adv_avg = 0.0
	peer_ck.clear()
	phase = Ph.LOAD
	_ready_at = 0
	_load_started = NetLink.now_ms()
	link.last_recv_ms = _load_started

func _handle(m: Dictionary, t: int) -> void:
		match String(m.get("t", "")):
			"rdy":
				if int(m.get("ep", 0)) != epoch: return
				peer_ready = true
				if phase == Ph.PLAY and int(m.get("_r", 0)) == 0:
					link.send_msg({"t": "rdy", "_r": 1, "ep": epoch}) # el rival sigue cargando: que nos vea listos
			"rs":
				if me == 0 and int(m.get("ep", 0)) > epoch: _host_resync()
				elif me == 0 and int(m.get("ep", 0)) == epoch and phase == Ph.LOAD and not _snap_out.is_empty(): _send_snap(t)
			"snap":
				_guest_snap(m)
			"in":
				if int(m.get("ep", 0)) != epoch: return
				session.receive_packet(m)
				peer_ack = maxi(peer_ack, int(m.get("ack", -1)))
				peer_frame = maxi(peer_frame, int(m.get("f", -1)))
				if m.has("e") and int(m["e"]) > 0:
					var s := float(t - int(m["e"]) - int(m.get("ed", 0)))
					rtt_ms = s if rtt_ms <= 0.0 else rtt_ms * 0.9 + s * 0.1
				_echo = int(m.get("s", 0)); _echo_at = t
				var cks: Variant = m.get("ck", [])
				for i in range(0, cks.size() - 1, 2):
					peer_ck[int(cks[i])] = int(cks[i + 1])
			"ping": link.send_msg({"t": "pong", "s": m.get("s", 0)})
			"start": link.send_msg({"t": "go"}) # el anfitrión aún no recibió nuestro «go»
			"bye":
				status = "forfeit_win"; phase = Ph.OVER
			"rm":
				if int(m.get("n", -1)) == rematch_n:
					peer_wants_rematch = true
				elif me == 0 and int(m.get("n", -1)) == rematch_n - 1 and not _rmgo.is_empty():
					link.send_msg(_rmgo, true) # el invitado no recibió el «rmgo»: reenviar
			"rmno":
				peer_declined = true
			"rmgo":
				if me == 1 and int(m.get("n", -1)) == rematch_n and want_rematch:
					_restart(int(m["seed"]), int(m["ep"]))
			"bad_params":
				status = "params_mismatch"; phase = Ph.OVER

func _after_msgs(t: int) -> void:
	if session.params_mismatch and status == "":
		for i in 3: link.send_msg({"t": "bad_params"}, true) # el rival no puede detectarlo si dejamos de enviar
		status = "params_mismatch"; phase = Ph.OVER
	if link.peer_left and status == "":
		status = "peer_left"; phase = Ph.OVER
	if link.peer_abandoned and status == "":
		status = "forfeit_win"; phase = Ph.OVER # el relay confirmó el abandono del rival
	if link.state == NetLink.St.FAILED and status == "":
		status = "reconnect_failed" if reconnecting else "disconnected"; phase = Ph.OVER
	if status != "": return
	if not reconnecting and t - link.last_recv_ms > TIMEOUT_MS:
		reconnecting = true; _reco_since = t
	if reconnecting:
		if t - _reco_since > grace_ms:
			status = "disconnected"; phase = Ph.OVER; return
		link.reconnect_tick()
		if link.last_recv_ms > _reco_since and t - link.last_recv_ms < 300 and t >= _rs_at:
			# el rival vuelve a responder: pedir/forzar la resincronización
			_rs_at = t + 300
			if me == 0: _host_resync()
			else: link.send_msg({"t": "rs", "ep": epoch + 1}, true)
		elif t >= _rs_at:
			_rs_at = t + 500
			link.send_msg({"t": "rs", "ep": epoch + 1}, true) # también sirve de latido

func _play_tick(local_input: int, t: int) -> bool:
	# sincronía: si vamos por delante del rival (estimado con el RTT), cedemos un tick
	var advanced := false
	var est_peer := float(peer_frame) + rtt_ms * 0.5 / TICK_MS
	if peer_frame >= 0:
		adv_avg = adv_avg * 0.9 + (float(session.frame) - est_peer) * 0.1
	_skip_cool -= 1
	if adv_avg > SYNC_ADV and _skip_cool <= 0 and peer_frame >= 0:
		_skip_cool = SYNC_COOLDOWN
		sync_skips += 1
		adv_avg -= 1.0
	else:
		session.add_local_input(local_input)
		advanced = session.tick()
	if advanced and adaptive_delay:
		_adapt_delay()
	_send(t)
	_check_desync()
	return advanced

func _adapt_delay() -> void:
	_delay_cool -= 1
	var d := session.input_delay
	_want_up = _want_up + 1 if delay_for_rtt(rtt_ms) > d else 0
	_want_down = _want_down + 1 if delay_for_rtt(rtt_ms + DOWN_MARGIN_MS) < d else 0
	if _delay_cool > 0:
		return
	if _want_up >= UP_TICKS:
		set_input_delay(d + 1)
	elif _want_down >= DOWN_TICKS:
		set_input_delay(d - 1)

func set_input_delay(d: int) -> void:
	d = clampi(d, MIN_DELAY, MAX_DELAY)
	if d == session.input_delay:
		return
	session.set_delay(d)
	input_delay = d
	delay_changes += 1
	_want_up = 0; _want_down = 0
	_delay_cool = DELAY_COOLDOWN

var _echo := 0
var _echo_at := 0
func _send(t: int) -> void:
	var p := session.make_packet(peer_ack)
	p["inputs"] = PackedInt32Array(p["inputs"])
	p["t"] = "in"
	p["ep"] = epoch
	p["f"] = session.frame
	p["s"] = t
	if _echo > 0:
		p["e"] = _echo
		p["ed"] = t - _echo_at
	var ck := PackedInt64Array()
	var hi := mini(session.last_remote, session.frame - 1)
	for f in (range(maxi(0, hi - CK_SEND + 1), hi + 1) if session.frame % 4 == 0 else []):
		if session.checksums.has(f):
			ck.append(f); ck.append(int(session.checksums[f]))
	p["ck"] = ck
	link.send_msg(p)
	_last_send_ms = t

func _check_desync() -> void:
	for f: int in peer_ck.keys():
		if session.checksums.has(f):
			if int(session.checksums[f]) != int(peer_ck[f]) and desync_frame < 0:
				desync_frame = f
				status = "desync"
				desync_report = write_desync_report(f, int(session.checksums[f]), int(peer_ck[f]))
			checked_to = maxi(checked_to, f)
			peer_ck.erase(f)
		elif f < session.frame - 200:
			peer_ck.erase(f)

# ---------------- revancha (fase 9) ----------------
## Tras un final normal («ko») los dos pares siguen conectados (la sim sigue corriendo sin efecto y
## mantiene vivo el enlace). Cada uno elige: request_rematch() o decline_rematch(). Con los dos de
## acuerdo, el anfitrión elige una semilla nueva y una época nueva y envía «rmgo»; ambos reinician la
## sesión con los MISMOS params (mismo params_hash) y pasan por la fase LOAD («rdy») como al empezar.
signal rematch_started
var rematch_n := 0 ## revanchas ya jugadas (numera los mensajes)
var want_rematch := false
var peer_wants_rematch := false
var peer_declined := false
var _rm_at := 0
var _rmgo: Dictionary = {}

func can_rematch() -> bool:
	return status == "" and not peer_declined and link != null and not (link.state in [NetLink.St.FAILED, NetLink.St.CLOSED])

func request_rematch() -> void:
	if not can_rematch():
		return
	want_rematch = true
	_rm_at = 0

func decline_rematch() -> void:
	for i in 3:
		link.send_msg({"t": "rmno"}, true)

func _rematch_tick(t: int) -> void:
	if not want_rematch:
		return
	if t >= _rm_at:
		_rm_at = t + 250
		link.send_msg({"t": "rm", "n": rematch_n}, true)
	if me == 0 and peer_wants_rematch and status == "":
		var sd := 1 + randi() % 100000
		while sd == seed_v:
			sd = 1 + randi() % 100000
		_rmgo = {"t": "rmgo", "n": rematch_n, "seed": sd, "ep": epoch + 1}
		for i in 2: link.send_msg(_rmgo, true)
		_restart(sd, epoch + 1)

func _restart(sd: int, ep: int) -> void:
	seed_v = sd
	epoch = ep
	rematch_n += 1
	want_rematch = false
	peer_wants_rematch = false
	peer_declined = false
	status = ""
	var params := engine.params
	var spawn := engine.spawn
	engine = FightEngine.new(params, seed_v, true)
	engine.rounds = true
	engine.spawn = spawn
	var ph := session.params_hash
	session = RbSession.new(me, start_delay, 8, engine)
	session.params_hash = ph
	input_delay = start_delay
	peer_ready = false
	peer_ack = -1; peer_frame = -1; adv_avg = 0.0
	peer_ck.clear(); checked_to = -1; desync_frame = -1; desync_report = ""
	resyncs = []; _snap_out = []; _snap_in = {}
	reconnecting = false
	_want_up = 0; _want_down = 0; _delay_cool = 0
	phase = Ph.LOAD
	_ready_at = 0
	_load_started = NetLink.now_ms()
	link.last_recv_ms = _load_started
	rematch_started.emit()

func forfeit() -> void:
	if link.ready_to_play():
		for i in 3: link.send_msg({"t": "bye"}, true)
	status = "forfeit_loss"; phase = Ph.OVER

func _drain() -> Array[Dictionary]:
	var a := link.inbox
	link.inbox = []
	return a

## Estado del último tick con ambas entradas confirmadas (decisiones definitivas: fin de partida).
func confirmed_state() -> PackedInt64Array:
	var f := mini(session.last_remote, session.frame - 1)
	if session.saved.has(f + 1):
		return session.saved[f + 1]
	return session.state

## Hasta qué tick las dos entradas son definitivas.
func confirmed_frame() -> int:
	return mini(session.last_remote, session.frame - 1)

# ---------------- registros ----------------
func replay_dict() -> Dictionary:
	var n := confirmed_frame() + 1
	var a: Array[int] = []; var b: Array[int] = []
	for f in n:
		var l: int = session.local_in.get(f, 0)
		var r: int = session.remote_in.get(f, session.predicted.get(f, 0)) # sin confirmar antes de un reinicio: lo que se simuló
		a.append(l if me == 0 else r)
		b.append(r if me == 0 else l)
	var ck := {}
	for f: int in session.checksums:
		if f < n and f % 10 == 9:
			ck[str(f)] = session.checksums[f]
	return {"proto": PROTO, "ph": session.params_hash, "params": var_to_str(engine.params), "seed": seed_v,
		"delay": input_delay, "me": me, "spawn": Array(engine.spawn), "in0": a, "in1": b, "ck": ck,
		"resync": resyncs.map(func(r: Array) -> Array: return [r[0], var_to_str(r[1])])}

func save_replay(path: String = "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute(log_dir)
		path = "%s/replay_%d_p%d.json" % [log_dir, Time.get_unix_time_from_system(), me]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_string(JSON.stringify(replay_dict()))
	return path

## Re-simula una repetición sin red; devuelve los ticks cuyo checksum no coincide ([] = reproducible).
static func verify_replay(d: Dictionary) -> Array[int]:
	var params: Array = str_to_var(String(d["params"]))
	var e := FightEngine.new(params, int(d["seed"]), true)
	e.rounds = true
	var sp: Array[int] = []
	for v in d.get("spawn", []): sp.append(int(v))
	e.spawn = sp
	var s := e.initial()
	var bad: Array[int] = []
	var ck: Dictionary = d["ck"]
	var a: Array = d["in0"]; var b: Array = d["in1"]
	var rs := {}
	for r: Variant in d.get("resync", []): rs[int(r[0])] = str_to_var(String(r[1]))
	for f in a.size():
		if rs.has(f + 1): # reconexión: el estado acordado sustituye al resultado del tick f
			s = (rs[f + 1] as PackedInt64Array).duplicate()
		else:
			e.step(s, int(a[f]), int(b[f]))
		if ck.has(str(f)) and int(ck[str(f)]) != e.checksum(s):
			bad.append(f)
	return bad

func write_desync_report(f: int, mine: int, theirs: int) -> String:
	DirAccess.make_dir_recursive_absolute(log_dir)
	var path := "%s/desync_%d_p%d_f%d.json" % [log_dir, Time.get_unix_time_from_system(), me, f]
	var rep := replay_dict()
	rep["desync_frame"] = f
	rep["checksum_mine"] = mine
	rep["checksum_peer"] = theirs
	if session.saved.has(f + 1):
		rep["state_after"] = Array(session.saved[f + 1])
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null: return ""
	fh.store_string(JSON.stringify(rep))
	push_warning("Desincronía online en el tick %d: %s" % [f, path])
	return path
