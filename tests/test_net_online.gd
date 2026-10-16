extends SceneTree
## Fase online 2: transporte, saludo, sincronía, desincronía, repeticiones, rondas, arena online, panel y táctil.
## godot --headless --path . -s res://tests/test_net_online.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _pair(port: int, lat: float = 0.0, los: Array = [{}, {}]) -> Array[NetMatch]:
	var a := NetLink.new(); var b := NetLink.new()
	a.host_lan(port); b.join_lan("127.0.0.1", port)
	for l in [a, b]: l.sim_delay_ms = lat
	var ms: Array[NetMatch] = []
	for i in 300:
		a.poll(); b.poll()
		if a.ready_to_play() and b.ready_to_play(): break
		OS.delay_msec(5)
	ms = [NetMatch.new(a), NetMatch.new(b)]
	ms[0].local_loadout = los[0]; ms[1].local_loadout = los[1]
	var done := [false, false]
	for i in 600:
		for k in 2:
			if not done[k]: done[k] = ms[k].prelude_step()
		if done[0] and done[1]: break
		OS.delay_msec(8)
	return ms

func _play(ms: Array[NetMatch], ticks: int, corrupt_at: int = -1) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var cur := [0, 0]
	var t0 := Time.get_ticks_msec()
	for k in ticks:
		for i in 2:
			if rng.randf() < 0.25: cur[i] = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
			if ms[i].phase == NetMatch.Ph.PLAY: ms[i].play_step(cur[i])
		if k == corrupt_at: ms[1].session.state[FightSim.HP] -= 1
		var wait := t0 + int((k + 1) * NetMatch.TICK_MS) - Time.get_ticks_msec()
		if wait > 0: OS.delay_msec(wait)

func _run() -> void:
	check(NetMatch.delay_for_rtt(10) == 1 and NetMatch.delay_for_rtt(100) == 2 and NetMatch.delay_for_rtt(170) == 4 and NetMatch.delay_for_rtt(600) == 4, "retardo de entrada adaptativo: 10 ms→1, 100 ms→2, 170 ms→4, tope 4")
	# 1) par LAN con 40 ms de ida: saludo, sincronía, checksums
	var ms := _pair(47621, 40.0)
	check(ms[0].phase != NetMatch.Ph.HELLO and ms[1].input_delay == ms[0].input_delay and ms[0].rtt_ms > 60.0, "saludo: RTT %.0f ms medido, retardo %d acordado" % [ms[0].rtt_ms, ms[0].input_delay])
	for m in ms: m.start_play(SimParams.defaults())
	_play(ms, 600)
	print("      estado: ", ms[0].status, "/", ms[1].status, " frames ", ms[0].session.frame, "/", ms[1].session.frame, " rollbacks ", ms[0].session.rollbacks, "/", ms[1].session.rollbacks, " saltos ", ms[0].sync_skips, "/", ms[1].sync_skips)
	var common := 0; var bad := 0
	for f: int in ms[0].session.checksums:
		if ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	check(common > 500 and bad == 0 and ms[0].desync_frame < 0 and ms[1].desync_frame < 0, "600 ticks sincronizados (%d confirmados comunes, 0 distintos)" % common)
	check(ms[0].checked_to > 500 and ms[1].checked_to > 500, "checksums intercambiados en banda hasta el tick %d" % mini(ms[0].checked_to, ms[1].checked_to))
	check(absi(ms[0].session.frame - ms[1].session.frame) <= 6, "sincronía de tiempo: diferencia de fotogramas %d" % (ms[0].session.frame - ms[1].session.frame))
	var rep := ms[0].replay_dict()
	check(NetMatch.verify_replay(rep).is_empty() and rep["in0"].size() > 500, "repetición reproducible sin red (%d ticks)" % rep["in0"].size())
	var path := ms[1].save_replay("user://net_test_replay.json")
	var loaded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(NetMatch.verify_replay(loaded).is_empty(), "repetición guardada y recargada reproducible")
	var in1: Array[int] = rep["in1"]
	for f in range(100, 160): in1[f] = FightSim.IN_ATK | FightSim.IN_MOVE | (f & 31)
	check(not NetMatch.verify_replay(rep).is_empty(), "repetición alterada detectada")
	# 2) abandono
	ms[0].forfeit()
	for i in 30:
		ms[1].play_step(0); OS.delay_msec(16)
	check(ms[0].status == "forfeit_loss" and ms[1].status == "forfeit_win", "abandono: el rival gana por abandono")
	for m in ms: m.link.close()
	# 3) desincronía forzada -> informe
	ms = _pair(47622)
	for m in ms:
		m.log_dir = "user://net_test"
		m.start_play(SimParams.defaults())
	_play(ms, 200, 100)
	check(ms[0].status == "desync" or ms[1].status == "desync", "desincronía detectada (tick %d / %d)" % [ms[0].desync_frame, ms[1].desync_frame])
	var rp := ms[0].desync_report if ms[0].desync_report != "" else ms[1].desync_report
	check(rp != "" and FileAccess.file_exists(rp), "informe de desincronía escrito: %s" % rp)
	# 4) desconexión sin aviso
	ms[0].link.udp.close(); ms[0].link.state = NetLink.St.CLOSED
	ms[1].status = ""; ms[1].desync_frame = 1 << 40
	var t0 := Time.get_ticks_msec()
	while ms[1].phase == NetMatch.Ph.PLAY and Time.get_ticks_msec() - t0 < 8000:
		ms[1].play_step(0); OS.delay_msec(16)
	check(ms[1].status == "disconnected", "desconexión: detectada tras %.1f s sin paquetes" % ((Time.get_ticks_msec() - t0) / 1000.0))
	ms[1].link.close()
	# 5) params distintos
	ms = _pair(47623)
	var P2 := SimParams.defaults().duplicate(true); P2[0]["hp"] = int(P2[0]["hp"]) + 5
	ms[0].start_play(SimParams.defaults()); ms[1].start_play(P2)
	_play(ms, 60)
	print("      ", ms[0].status, "|", ms[1].status, " ", ms[0].session.frame, " ", ms[0].session.peer_hash, " ", ms[0].session.params_hash)
	check(ms[0].status == "params_mismatch" and ms[1].status == "params_mismatch" and ms[0].session.frame == 0, "params distintos: ninguno simula")
	for m in ms: m.link.close()
	# 6) rondas dentro de la sim
	_test_rounds()
	# 7) táctil y teclado en la entrada empaquetada
	await _test_touch()
	# 8) arena online, como anfitrión y como invitado
	for me_slot in [0, 1]:
		await _test_arena(me_slot, 47630 + me_slot)
	# 9) panel online del lobby (LAN en el mismo equipo)
	await _test_panel()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

func _test_rounds() -> void:
	var e := FightEngine.new(SimParams.defaults()); e.rounds = true; e.gap_um = 1800000
	var s := e.initial()
	s[FightSim.F_FIELDS + FightSim.HP] = 1
	var g := FightSim.P_BASE
	var k := 0
	while s[g + FightSim.G_END_T] == 0 and k < 300:
		e.step(s, FightSim.IN_ATK | FightSim.IN_LOCK if k % 10 < 3 else FightSim.IN_LOCK, FightSim.IN_LOCK); k += 1
	check(s[g + FightSim.G_WINS0] == 1 and s[g + FightSim.G_END_T] > 0, "ronda: KO suma la victoria al jugador 0")
	for i in FightEngine.ROUND_GAP: e.step(s, 0, 0)
	check(s[g + FightSim.G_ROUND] == 1 and s[FightSim.F_FIELDS + FightSim.ALIVE] == 1 and s[FightSim.F_FIELDS + FightSim.HP] == e.params[1]["hp"] and s[g + FightSim.G_WINS0] == 1, "ronda: reinicio determinista tras %d ticks, victorias conservadas" % FightEngine.ROUND_GAP)
	s[g + FightSim.G_WINS0] = 2
	check(e.match_over(s) == 0, "partida: gana quien llega a 2")

func _test_touch() -> void:
	var w := Node3D.new(); root.add_child(w)
	var sm := SimMatch.new(); w.add_child(sm)
	var a := Fighter.new(); var b := Fighter.new()
	w.add_child(a); w.add_child(b)
	a.global_position = Vector3(0, 0, 5); b.global_position = Vector3(0, 0, -5)
	await process_frame
	sm.fighters = [a, b]
	sm.local_slot = 1
	var js := TouchStick.new(); w.add_child(js)
	sm.joystick = js
	js.axis = Vector2(0, -1)
	var v := sm.sample_device(1)
	check(v & FightSim.IN_MOVE != 0, "táctil: el joystick del HUD mueve al jugador local (hueco 1)")
	check(sm.sample_device(0) & FightSim.IN_MOVE == 0, "táctil: el otro hueco no recibe el joystick")
	Input.action_press("attack_sword"); Input.action_press("run_toggle")
	v = sm.sample_device(1)
	check(v & FightSim.IN_ATK != 0 and v & FightSim.IN_SPRINT != 0, "botones táctiles (Atacar, Correr alternado) en la entrada empaquetada")
	Input.action_release("attack_sword"); Input.action_release("run_toggle")
	check(sm.sample_device(1) & FightSim.IN_SPRINT != 0, "Correr táctil queda activado (alternar)")
	js.axis = Vector2.ZERO
	w.queue_free()
	await process_frame

func _test_arena(me_slot: int, port: int) -> void:
	var ms := _pair(port, 15.0)
	var mine := ms[me_slot]; var bot := ms[1 - me_slot]
	NetMatch.current = mine
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene as Arena
	check(ar.online == mine and ar.sim_match != null and ar.sim_match.net == mine and ar.sim_match.local_slot == me_slot, "arena online (hueco %d): SimMatch en red, jugador local = nodo player" % me_slot)
	check(not ar.controller.enabled and not ar.ai.is_physics_processing(), "arena online (hueco %d): sin IA ni controlador offline" % me_slot)
	bot.start_play(ar.sim_match.params, ar.sim_match.engine.spawn)
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var cur := 0
	var mine_in := 0
	ar.sim_match.input_override[me_slot] = func(_t: int) -> int: return mine_in
	for i in 420:
		if rng.randf() < 0.25: cur = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
		if rng.randf() < 0.25: mine_in = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
		bot.play_step(cur)
		await physics_frame
	var view_ok := absf(ar.player.global_position.x - ar.sim_match.view.offsets[me_slot].x - mine.session.state[me_slot * FightSim.F_FIELDS + FightSim.X] / 1.0e6) < 0.01
	check(mine.session.frame > 300 and mine.desync_frame < 0 and bot.desync_frame < 0 and mine.checked_to > 250, "arena online (hueco %d): %d ticks sin desincronía, checksums hasta %d" % [me_slot, mine.session.frame, mine.checked_to])
	check(view_ok, "arena online (hueco %d): el nodo player muestra al luchador local" % me_slot)
	check(ar.hud.timer_label.text.ends_with("ms"), "arena online: HUD muestra la latencia (%s)" % ar.hud.timer_label.text)
	bot.forfeit()
	for i in 20: await physics_frame
	check(ar.state == "over" and mine.status == "forfeit_win" and NetMatch.current == null, "arena online (hueco %d): abandono del rival termina la partida a favor" % me_slot)
	bot.link.close()
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_net_online.cfg"
	gs.first_run_done = true
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	await process_frame

func _test_panel() -> void:
	var lob := current_scene
	var has := lob != null and lob.has_method("open_online")
	check(has, "lobby: botón ONLINE disponible")
	if not has: return
	var p1: OnlinePanel = lob.open_online()
	await process_frame
	p1.go_scene = false
	p1.host_lan()
	check(p1.status_label.text.contains("Tu IP"), "panel LAN: muestra la IP del anfitrión (%s)" % p1.status_label.text.replace("\n", " "))
	var p2 := OnlinePanel.new(); root.add_child(p2)
	await process_frame
	p2.go_scene = false
	p2.ip_edit.text = "127.0.0.1"
	p2.join_lan()
	for i in 240:
		await physics_frame
		if p1.status_label.text.begins_with("¡A luchar") and p2.status_label.text.begins_with("¡A luchar"): break
	check(p1.status_label.text.begins_with("¡A luchar") and p2.status_label.text.begins_with("¡A luchar"), "panel: anfitrión e invitado LAN se emparejan (%s)" % p2.status_label.text)
	p2.relay_edit.text = ""
	p2.create_room()
	check(p2.status_label.text.contains("relay"), "panel: sin servidor configurado avisa y sugiere LAN")
	if NetMatch.current: NetMatch.current.link.close()
	NetMatch.current = null
	p1.cancel(); p2.cancel()
