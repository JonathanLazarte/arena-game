extends SceneTree
## Fase 9: revancha online sobre un par LAN local (dos SimMatch con NetMatch en el mismo proceso):
## los dos piden revancha → siguen conectados, sesión nueva con los mismos params y semilla nueva
## acordada, nueva partida sincronizada; si uno vuelve al lobby, el otro lo ve.
## godot --headless --path . -s res://tests/test_net_rematch.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _pair(port: int, lat: float) -> Array[NetMatch]:
	var a := NetLink.new(); var b := NetLink.new()
	a.host_lan(port); b.join_lan("127.0.0.1", port)
	for l in [a, b]: l.sim_delay_ms = lat
	for i in 300:
		a.poll(); b.poll()
		if a.ready_to_play() and b.ready_to_play(): break
		OS.delay_msec(5)
	var ms: Array[NetMatch] = [NetMatch.new(a), NetMatch.new(b)]
	var done := [false, false]
	for i in 600:
		for k in 2:
			if not done[k]: done[k] = ms[k].prelude_step()
		if done[0] and done[1]: break
		OS.delay_msec(8)
	return ms

var ended := [-1, -1]
var restarted := [0, 0]
var sms: Array[SimMatch] = []

func _fighter(parent: Node3D, pos: Vector3) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	parent.add_child(f)
	f.max_health = 4.0 # un golpe = ronda: partidas cortas
	f.health = 4.0
	f.global_position = pos
	f.facing = Vector3.FORWARD if pos.z > 0 else Vector3.BACK
	return f

## Avanza los dos pares en tiempo real (60 Hz) hasta que cond() o se agoten los ticks.
func _run_until(ticks: int, cond: Callable) -> int:
	var t0 := Time.get_ticks_msec()
	for k in ticks:
		for sm in sms: sm.step_once()
		if cond.call():
			return k
		var wait := t0 + int((k + 1) * NetMatch.TICK_MS) - Time.get_ticks_msec()
		if wait > 0: OS.delay_msec(wait)
	return -1

func _bot(seed: int) -> Callable:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var cur := [0]
	return func(_t: int) -> int:
		if rng.randf() < 0.3: cur[0] = (rng.randi() & (FightSim.IN_DIR_MASK | FightSim.IN_MOVE | FightSim.IN_ATK | FightSim.IN_ROLL)) | FightSim.IN_LOCK
		return cur[0]

func _run() -> void:
	var ms := _pair(47661, 20.0)
	check(ms[0].link.ready_to_play() and ms[1].link.ready_to_play() and ms[0].seed_v == ms[1].seed_v, "par LAN conectado y saludo hecho")
	var world := Node3D.new()
	root.add_child(world)
	for i in 2:
		var a := _fighter(world, Vector3(0, 0, 4))
		var b := _fighter(world, Vector3(0, 0, -4))
		var sm := SimMatch.new()
		world.add_child(sm)
		sm.setup(a, b, world, ms[i])
		sm.running = false # lo avanza la prueba
		sm.input_override[ms[i].me] = _bot(7 + i)
		var idx := i
		sm.match_ended.connect(func(w: int, reason: String) -> void: ended[idx] = w if reason == "ko" else -2)
		sm.rematch_started.connect(func() -> void: restarted[idx] += 1)
		sms.append(sm)
	await process_frame
	var seed0 := ms[0].seed_v
	var hash0 := ms[0].session.params_hash
	var k := _run_until(3600, func() -> bool: return ended[0] >= 0 and ended[1] >= 0)
	check(k >= 0 and ended[0] == ended[1], "primera partida termina por KO en ambos (ganador %d, %d ticks)" % [ended[0], k])
	check(ms[0].can_rematch() and ms[1].can_rematch(), "tras el KO siguen conectados y la revancha es posible")
	# solo uno pide revancha: el otro lo ve, pero no empieza nada
	ms[0].request_rematch()
	_run_until(60, func() -> bool: return false)
	check(ms[1].peer_wants_rematch and ms[0].rematch_n == 0 and restarted == [0, 0], "uno pide revancha: el rival lo ve («quiere la revancha»), nadie reinicia aún")
	check(ms[0].link.state == NetLink.St.CONNECTED and ms[1].link.state == NetLink.St.CONNECTED, "sin cerrar el enlace mientras se decide")
	# el otro acepta
	ended = [-1, -1]
	ms[1].request_rematch()
	var k2 := _run_until(600, func() -> bool: return restarted == [1, 1] and ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY)
	check(k2 >= 0, "los dos aceptan: revancha arrancada en ambos (%d ticks)" % k2)
	check(ms[0].seed_v == ms[1].seed_v and ms[0].seed_v != seed0, "semilla nueva acordada (%d → %d)" % [seed0, ms[0].seed_v])
	check(ms[0].epoch == ms[1].epoch and ms[0].epoch >= 1, "época nueva común (%d)" % ms[0].epoch)
	check(ms[0].session.params_hash == hash0 and ms[1].session.params_hash == hash0, "mismos params (hash %d)" % hash0)
	check(sms[0].last_confirmed_wins == [0, 0] and not sms[0]._ended, "SimMatch: marcador a cero y partida en curso")
	var f_start := ms[0].session.frame
	_run_until(400, func() -> bool: return ended[0] >= 0 and ended[1] >= 0)
	var common := 0; var bad := 0
	for f: int in ms[0].session.checksums:
		if ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	check(common > 150 and bad == 0 and ms[0].status in ["", "ko"] and ms[0].desync_frame < 0, "revancha sincronizada (%d ticks confirmados comunes, %d distintos, inicio en %d)" % [common, bad, f_start])
	_run_until(3600, func() -> bool: return ended[0] >= 0 and ended[1] >= 0)
	check(ended[0] >= 0 and ended[0] == ended[1], "la revancha termina con el mismo ganador en ambos (%d)" % ended[0])
	# segunda vez: uno pide y el otro vuelve al lobby
	ms[0].request_rematch()
	_run_until(20, func() -> bool: return false)
	ms[1].decline_rematch()
	ms[1].link.close()
	var k3 := _run_until(120, func() -> bool: return ms[0].peer_declined)
	check(k3 >= 0 and ms[0].rematch_n == 1, "el rival vuelve al lobby: se avisa y no hay revancha")
	check(not ms[0].can_rematch(), "ya no se puede pedir otra")
	ms[0].link.close()
	world.queue_free()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
