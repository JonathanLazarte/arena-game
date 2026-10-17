extends SceneTree
## Fase 5 contra el relay real (node server/dist): ping por región, partida rápida, versión,
## reconexión desde otra dirección (NAT renovado) con ficha y abandono confirmado por el relay («F»).
## Requiere node y `npm run build` en server/. godot --headless --path . -s res://tests/test_net_relay5.gd
var fails := 0
var pids: Array[int] = []
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _relay(port: int, region: String, grace: int = 20000) -> void:
	var js := ProjectSettings.globalize_path("res://server/dist/src/index.js")
	pids.append(OS.create_process("/usr/bin/env", ["PORT=%d" % port, "REGION=" + region, "HEALTH_PORT=0", "GRACE_MS=%d" % grace, "node", js]))

func _wait(cond: Callable, ms: int, links: Array) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for l in links: l.poll()
		if cond.call(): return true
		OS.delay_msec(10)
	return false

func _run() -> void:
	_relay(47911, "sa-east"); _relay(47912, "us-east", 3000)
	OS.delay_msec(1200)
	# ping por región
	var rg := NetRegions.new()
	rg.start("sp=127.0.0.1:47911, us=127.0.0.1:47912, muerto=127.0.0.1:47919")
	while not rg.done:
		rg.poll(); OS.delay_msec(10)
	check(int(rg.servers[0]["ms"]) >= 0 and rg.servers[0]["region"] == "sa-east" and int(rg.servers[2]["ms"]) == -1 and not rg.best().is_empty(), "ping a regiones: %s" % rg.summary())
	# versión distinta
	var old := NetLink.new(); old.create_room("127.0.0.1", 47911)
	old._ctl = old._msg("C", {"v": 3})
	check(_wait(func() -> bool: return old.state == NetLink.St.FAILED, 2000, [old]) and old.error == "version", "relay rechaza protocolo 3: %s" % old.error)
	# partida rápida
	var a := NetLink.new(); var b := NetLink.new()
	a.force_relay = true; b.force_relay = true
	a.quick_match("127.0.0.1", 47911)
	check(_wait(func() -> bool: return a.state == NetLink.St.WAITING, 2000, [a]) and a.queue_pos == 0, "en cola de partida rápida")
	b.quick_match("127.0.0.1", 47911)
	check(_wait(func() -> bool: return a.ready_to_play() and b.ready_to_play(), 3000, [a, b]) and a.slot != b.slot and a.token != "" and a.region == "sa-east", "emparejados por partida rápida (sala %s, región %s)" % [a.code, a.region])
	var ms: Array[NetMatch] = [NetMatch.new(a), NetMatch.new(b)]
	if a.slot == 1: ms = [NetMatch.new(b), NetMatch.new(a)]
	var done := [false, false]
	for i in 600:
		for k in 2:
			if not done[k]: done[k] = ms[k].prelude_step()
		if done[0] and done[1]: break
		OS.delay_msec(8)
	for m in ms: m.start_play(SimParams.defaults())
	var play := func(t: int) -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < t:
			for m: NetMatch in ms: m.play_step(FightSim.IN_LOCK | (randi() & 0xFF if randf() < 0.2 else 0))
			OS.delay_msec(16)
	play.call(2500)
	check(ms[0].phase == NetMatch.Ph.PLAY and ms[1].session.frame > 60, "partida por relay en curso")
	# el invitado pierde la red y vuelve desde otro puerto (NAT renovado)
	var g := ms[1].link
	g.blackout = true
	play.call(5000)
	g.udp.close(); g.udp.bind(0, "0.0.0.0"); g.blackout = false
	play.call(5000)
	var common := 0; var bad := 0
	for f: int in ms[0].session.checksums:
		if f >= ms[0].session.base_frame and ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	check(g.reconnected >= 1 and ms[0].epoch >= 1 and ms[0].epoch == ms[1].epoch and ms[0].phase == NetMatch.Ph.PLAY and ms[1].phase == NetMatch.Ph.PLAY and bad == 0 and common > 100,
		"reconexión con ficha desde otra dirección: época %d, %d ticks comunes, 0 distintos (%s/%s)" % [ms[0].epoch, common, ms[0].status, ms[1].status])
	for m in ms: m.link.close()
	# abandono confirmado por el relay (gracia 3 s en us-east)
	var c := NetLink.new(); var d := NetLink.new()
	c.quick_match("127.0.0.1", 47912); _wait(func() -> bool: return c.state == NetLink.St.WAITING, 2000, [c])
	d.quick_match("127.0.0.1", 47912)
	_wait(func() -> bool: return c.ready_to_play() and d.ready_to_play(), 3000, [c, d])
	d.blackout = true
	check(_wait(func() -> bool: return c.peer_abandoned, 9000, [c, d]), "el relay avisa del abandono del rival («F») → victoria por abandono")
	c.close(); d.close()
	for p in pids: OS.kill(p)
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
