extends SceneTree
## Fase 5: corte de red en plena partida → sim congelada, reconexión, instantánea del anfitrión,
## nuevo saludo «rdy» y partida sincronizada; corte permanente → fin por abandono tras el plazo.
## godot --headless --path . -s res://tests/test_net_reconnect.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _pair(port: int) -> Array[NetMatch]:
	var a := NetLink.new(); var b := NetLink.new()
	a.host_lan(port); b.join_lan("127.0.0.1", port)
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
	for m in ms: m.start_play(SimParams.defaults())
	return ms

var rng := RandomNumberGenerator.new()
func _play(ms: Array[NetMatch], ms_time: int) -> void:
	var t0 := Time.get_ticks_msec()
	var cur := [0, 0]
	while Time.get_ticks_msec() - t0 < ms_time:
		for i in 2:
			if rng.randf() < 0.25: cur[i] = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
			ms[i].play_step(cur[i])
		OS.delay_msec(16)

func _same(ms: Array[NetMatch], from: int) -> Array[int]:
	var common := 0; var bad := 0
	for f: int in ms[0].session.checksums:
		if f >= from and ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	return [common, bad]

func _run() -> void:
	rng.seed = 9
	check(NetMatch.PROTO == 7 and NetLink.GAME_PROTO == 7, "protocolo 7 (relay rechaza versiones distintas)")
	var ms := _pair(47661)
	_play(ms, 3000)
	check(ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY, "partida en curso")
	var f_before := ms[0].session.frame
	# corte de 7 s (más que el límite de 4 s)
	for m in ms: m.link.blackout = true
	_play(ms, 7000)
	check(ms[0].reconnecting and ms[1].reconnecting and ms[0].status == "" and ms[1].status == "", "corte de 7 s: ambos reconectando, sin fin de partida")
	check(ms[0].session.frame - f_before < 400, "sim congelada durante el corte (%d ticks)" % (ms[0].session.frame - f_before))
	for m in ms: m.link.blackout = false
	_play(ms, 4000)
	check(ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY and ms[0].epoch == 1 and ms[1].epoch == 1, "reconectado: instantánea época %d/%d (%s/%s)" % [ms[0].epoch, ms[1].epoch, ms[0].status, ms[1].status])
	var base := ms[0].session.base_frame
	check(base == ms[1].session.base_frame, "ambos siguen desde el mismo tick %d" % base)
	var r := _same(ms, base)
	check(r[0] > 150 and r[1] == 0 and ms[0].desync_frame < 0 and ms[1].desync_frame < 0, "sincronizados tras reconectar (%d ticks comunes, %d distintos)" % r)
	# solo el invitado pierde la red 5 s: el anfitrión no ve corte largo pero sí el invitado
	ms[1].link.blackout = true
	_play(ms, 5000)
	ms[1].link.blackout = false
	_play(ms, 4000)
	r = _same(ms, ms[0].session.base_frame)
	check(ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY and ms[0].epoch == ms[1].epoch and r[1] == 0 and r[0] > 100, "segundo corte (solo invitado): época %d, %d ticks comunes" % [ms[0].epoch, r[0]])
	for k in 2:
		var rp := ms[k].replay_dict()
		var path := ms[k].save_replay("user://net_reco_replay_%d.json" % k)
		var ld: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(rp["resync"].size() == 2 and NetMatch.verify_replay(rp).is_empty() and NetMatch.verify_replay(ld).is_empty() and rp["ck"].size() > 30, "repetición del %s reproducible tras 2 reconexiones (%d checksums)" % [["anfitrión", "invitado"][k], rp["ck"].size()])
	# abandono: el invitado desaparece para siempre
	for m in ms: m.grace_ms = 3000
	ms[1].link.blackout = true
	var t0 := Time.get_ticks_msec()
	while ms[0].phase != NetMatch.Ph.OVER and Time.get_ticks_msec() - t0 < 12000:
		ms[0].play_step(0); OS.delay_msec(16)
	check(ms[0].status == "disconnected" and ms[0].phase == NetMatch.Ph.OVER, "abandono: fin tras 4 s + plazo de gracia → %s (gana quien queda)" % ms[0].status)
	for m in ms: m.link.close()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
