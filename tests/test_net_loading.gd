extends SceneTree
## Carga lenta del invitado: el anfitrión espera «rdy» (latidos durante la carga) sin desconectar
## a los 4 s; la sesión arranca solo con ambos listos; un rival que nunca carga expira a 30 s (no ahí).
## godot --headless --path . -s res://tests/test_net_loading.gd
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
	return ms

func _run() -> void:
	var ms := _pair(47641)
	check(ms[0].status == "" and ms[1].status == "", "saludo completo")
	# anfitrión entra en la arena enseguida; el invitado tarda 6 s en cargar la escena (sin sondear la red)
	ms[0].start_play(SimParams.defaults())
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		ms[0].play_step(0); OS.delay_msec(16)
	check(ms[0].phase == NetMatch.Ph.LOAD and ms[0].status == "" and ms[0].waiting_peer(), "anfitrión sigue esperando tras 6 s (>4 s) con «Cargando rival…»: %s" % ms[0].status)
	check(ms[0].session.frame == 0, "la sesión no avanza sin ambos listos")
	# el invitado termina de crear la escena; aún calienta sombreadores 1.5 s (latidos «ka»)
	ms[1].start_play(SimParams.defaults())
	ms[1].local_ready = false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		ms[0].play_step(0); ms[1].play_step(0); OS.delay_msec(16)
	check(ms[0].phase == NetMatch.Ph.LOAD and ms[1].phase == NetMatch.Ph.LOAD, "calentando: nadie arranca todavía")
	ms[1].local_ready = true
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	t0 = Time.get_ticks_msec()
	for k in 420:
		for i in 2:
			ms[i].play_step((rng.randi() & 0x1FFF) | FightSim.IN_LOCK if rng.randf() < 0.25 else 0)
		OS.delay_msec(16)
	check(ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY, "ambos listos → partida en curso (%s/%s)" % [ms[0].status, ms[1].status])
	check(ms[0].session.frame > 300 and ms[1].session.frame > 300, "frames %d/%d" % [ms[0].session.frame, ms[1].session.frame])
	var bad := 0; var common := 0
	for f: int in ms[0].session.checksums:
		if ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	check(common > 200 and bad == 0, "sincronizados tras la carga lenta (%d comunes)" % common)
	for m in ms: m.link.close()
	# rival que nunca carga: el plazo de carga es LOAD_TIMEOUT_MS, no TIMEOUT_MS
	check(NetMatch.LOAD_TIMEOUT_MS >= 30000 and NetMatch.LOAD_TIMEOUT_MS > NetMatch.TIMEOUT_MS * 5, "plazo de carga 30 s")
	ms = _pair(47642)
	ms[0].start_play(SimParams.defaults())
	ms[0].link.last_recv_ms -= NetMatch.LOAD_TIMEOUT_MS + 10 # simular 30 s sin noticias
	ms[1].link.udp.close(); ms[1].link.state = NetLink.St.CLOSED
	for i in 5: ms[0].play_step(0); OS.delay_msec(16)
	check(ms[0].status == "load_timeout" and ms[0].phase == NetMatch.Ph.OVER, "rival que no carga en 30 s → fin con aviso (no pantalla negra): %s" % ms[0].status)
	ms[0].link.close()
	print("FAILS: ", fails)
	quit(1 if fails > 0 else 0)
