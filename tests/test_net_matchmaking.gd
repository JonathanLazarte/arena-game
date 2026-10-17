extends SceneTree
## Fase 7: el panel online nunca se queda colgado. Relay inalcanzable → error claro en ~5 s con la
## sugerencia de LAN / server/DEPLOY.md; sin relay configurado → aviso inmediato. Y contra un relay
## local (node server/dist): sala con código y partida rápida de extremo a extremo (hasta jugar).
## godot --headless --path . -s res://tests/test_net_matchmaking.gd
var fails := 0
var pids: Array[int] = []
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _relay(port: int, region: String) -> void:
	var js := ProjectSettings.globalize_path("res://server/dist/src/index.js")
	pids.append(OS.create_process("/usr/bin/env", ["PORT=%d" % port, "REGION=" + region, "HEALTH_PORT=0", "node", js]))

func _wait(cond: Callable, ms: int, links: Array) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for l in links: l.poll()
		if cond.call(): return true
		OS.delay_msec(10)
	return false

func _panel() -> OnlinePanel:
	var p := OnlinePanel.new()
	p.go_scene = false
	root.add_child(p)
	return p

## Avanza el panel a mano (headless: _physics_process sin bucle de escena) hasta cond o plazo.
func _drive(panels: Array, cond: Callable, ms: int) -> int:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for p: OnlinePanel in panels: p._physics_process(0.016)
		if cond.call(): return Time.get_ticks_msec() - t0
		OS.delay_msec(10)
	return -1

func _run() -> void:
	# 1) relay inalcanzable (nadie escucha en ese puerto): NetLink falla en ~5 s, no se cuelga
	for kind in ["C", "J", "Q"]:
		var l := NetLink.new()
		var t0 := Time.get_ticks_msec()
		match kind:
			"C": l.create_room("127.0.0.1", 47998)
			"J": l.join_room("127.0.0.1", 47998, "ABCD1")
			"Q": l.quick_match("127.0.0.1", 47998)
		var ok := _wait(func() -> bool: return l.state == NetLink.St.FAILED, 7000, [l])
		var dt := Time.get_ticks_msec() - t0
		check(ok and l.error == "relay_unreachable" and dt >= 4500 and dt <= 6500, "%s sin relay: FAILED relay_unreachable en %d ms" % [kind, dt])
		l.close()
	# 2) panel: sin relay configurado → aviso inmediato; relay caído → error claro con LAN/DEPLOY
	var p := _panel()
	p.relay_edit.text = ""
	p.quick_match()
	check(p.link == null and p.status_label.text.contains("LAN") and p.status_label.text.contains("DEPLOY.md"), "sin relay configurado: «%s»" % p.status_label.text.left(80))
	p.create_room()
	check(p.link == null and p.status_label.text.contains("DEPLOY.md"), "crear sala sin relay: aviso, sin colgarse")
	p.relay_edit.text = "127.0.0.1:47998"
	p.quick_match()
	var dt2 := _drive([p], func() -> bool: return p.link == null, 7000)
	check(dt2 >= 0 and p.status_label.text.contains("no responde") and p.status_label.text.contains("LAN") and p.status_label.text.contains("DEPLOY.md"),
		"partida rápida contra relay caído: error en %d ms: «%s»" % [dt2, p.status_label.text.left(90)])
	p.relay_edit.text = "127.0.0.1:47998"
	p.code_edit.text = "ABCD1"
	p.join_room()
	dt2 = _drive([p], func() -> bool: return p.link == null, 7000)
	check(dt2 >= 0 and p.status_label.text.contains("no responde"), "unirse con código contra relay caído: error en %d ms" % dt2)
	p.relay_edit.text = "no-existe.invalid:47800"
	p.create_room()
	dt2 = _drive([p], func() -> bool: return p.link == null, 7000)
	check(dt2 >= 0 and p.status_label.text.contains("DEPLOY.md"), "relay con nombre que no resuelve: «%s»" % p.status_label.text.left(90))
	p.queue_free()
	# 3) relay local: sala con código y partida rápida por el panel, hasta empezar a jugar
	_relay(47921, "local")
	OS.delay_msec(1200)
	var a := _panel(); var b := _panel()
	a.relay_edit.text = "127.0.0.1:47921"; b.relay_edit.text = "127.0.0.1:47921"
	a.create_room()
	_drive([a], func() -> bool: return a.link != null and a.link.state == NetLink.St.WAITING and a.link.code != "", 3000)
	var code: String = a.link.code if a.link else ""
	check(code.length() >= 4 and a.status_label.text.contains(code), "sala creada en el relay local: código %s" % code)
	b.code_edit.text = code
	b.join_room()
	var dt3 := _drive([a, b], func() -> bool: return NetMatch.current != null and a.link == null and b.link == null, 15000)
	check(dt3 >= 0 and a.status_label.text.begins_with("¡A luchar!") and b.status_label.text.begins_with("¡A luchar!"), "sala con código: los dos llegan a «¡A luchar!» (%d ms)" % dt3)
	var ma: NetMatch = a.m; var mb: NetMatch = b.m
	_play([ma, mb], 1500)
	check(ma != null and mb != null and ma.session.frame > 40 and mb.session.frame > 40 and _same(ma, mb), "sala con código: partida en curso y sincronizada")
	for m in [ma, mb]: if m: m.link.close()
	NetMatch.current = null
	a.queue_free(); b.queue_free()
	var c := _panel(); var d := _panel()
	c.relay_edit.text = "127.0.0.1:47921"; d.relay_edit.text = "127.0.0.1:47921"
	c.chosen = {}; d.chosen = {}
	c.quick_match()
	_drive([c], func() -> bool: return c.link != null and c.link.queue_pos >= 0, 3000)
	check(c.status_label.text.contains("En cola"), "partida rápida: en cola («%s»)" % c.status_label.text.left(60))
	d.quick_match()
	var dt4 := _drive([c, d], func() -> bool: return NetMatch.current != null and c.link == null and d.link == null, 15000)
	check(dt4 >= 0 and c.status_label.text.begins_with("¡A luchar!") and d.status_label.text.begins_with("¡A luchar!"), "partida rápida: emparejados y a luchar (%d ms)" % dt4)
	var mc: NetMatch = c.m; var md: NetMatch = d.m
	_play([mc, md], 1500)
	check(mc != null and md != null and mc.session.frame > 40 and _same(mc, md), "partida rápida: partida en curso y sincronizada")
	for m in [mc, md]: if m: m.link.close()
	for pid in pids: OS.kill(pid)
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

func _play(ms: Array, t: int) -> void:
	for m: NetMatch in ms:
		if m and m.phase != NetMatch.Ph.PLAY and m.phase != NetMatch.Ph.LOAD: m.start_play(SimParams.defaults())
	for m: NetMatch in ms:
		if m: m.local_ready = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < t:
		for m: NetMatch in ms:
			if m: m.play_step(FightSim.IN_LOCK | (randi() & 0xFF if randf() < 0.2 else 0))
		OS.delay_msec(16)

func _same(x: NetMatch, y: NetMatch) -> bool:
	var common := 0
	for f: int in x.session.checksums:
		if y.session.checksums.has(f):
			if x.session.checksums[f] != y.session.checksums[f]: return false
			common += 1
	return common > 20
