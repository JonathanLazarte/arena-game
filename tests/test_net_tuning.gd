extends SceneTree
## Fase online 3: ajuste de latencia (holgura de parada, suavizado visual, retardo adaptativo en
## partida, panel de red, equipo del lobby por la red, coste de sim).
## godot --headless --path . -s res://tests/test_net_tuning.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _pair(port: int, lat: float, los: Array = [{}, {}]) -> Array[NetMatch]:
	var a := NetLink.new(); var b := NetLink.new()
	a.host_lan(port); b.join_lan("127.0.0.1", port)
	a.sim_delay_ms = lat; b.sim_delay_ms = lat
	for i in 300:
		a.poll(); b.poll()
		if a.ready_to_play() and b.ready_to_play(): break
		OS.delay_msec(5)
	var ms: Array[NetMatch] = [NetMatch.new(a), NetMatch.new(b)]
	ms[0].local_loadout = los[0]; ms[1].local_loadout = los[1]
	var done := [false, false]
	for i in 600:
		for k in 2:
			if not done[k]: done[k] = ms[k].prelude_step()
		if done[0] and done[1]: break
		OS.delay_msec(8)
	return ms

func _play(ms: Array[NetMatch], ticks: int, on_tick: Callable = Callable()) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var cur := [0, 0]
	var t0 := Time.get_ticks_msec()
	for k in ticks:
		if on_tick.is_valid(): on_tick.call(k)
		for i in 2:
			if rng.randf() < 0.25: cur[i] = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
			if ms[i].phase in [NetMatch.Ph.LOAD, NetMatch.Ph.PLAY]: ms[i].play_step(cur[i])
		var wait := t0 + int((k + 1) * NetMatch.TICK_MS) - Time.get_ticks_msec()
		if wait > 0: OS.delay_msec(wait)

func _in_sync(ms: Array[NetMatch]) -> Array[int]:
	var common := 0; var bad := 0
	for f: int in ms[0].session.checksums:
		if ms[1].session.checksums.has(f):
			common += 1
			if ms[0].session.checksums[f] != ms[1].session.checksums[f]: bad += 1
	return [common, bad]

func _run() -> void:
	# 1) holgura de parada
	check(SimParams.lenience_for_delay(1) == 0 and SimParams.lenience_for_delay(2) == 1 and SimParams.lenience_for_delay(4) == 2, "holgura de parada: retardo 1→0, 2→1, ≥3→2 ticks")
	var P := SimParams.defaults()
	var T := SimParams.online_tuning(P, 2)
	check(int(T[0]["parry_window"]) == int(P[0]["parry_window"]) + 2 and int(T[0]["parry_window"]) + int(T[0]["parry_recovery"]) == int(P[0]["parry_window"]) + int(P[0]["parry_recovery"]) and int(P[0].get("net_lenience", 0)) == 0, "holgura: ventana +2, recuperación −2 (compromiso igual), params base intactos")
	var e0 := _earliest_parry(P); var e2 := _earliest_parry(T)
	check(e0 > 0 and e2 == e0 + 2, "holgura: la parada admite 2 ticks más de antelación (%d → %d)" % [e0, e2])
	# 2) suavizado visual
	await _test_smoothing()
	# 3) retardo adaptativo con histéresis durante la partida (red 20 ms → 140 ms → 20 ms)
	var ms := _pair(47661, 10.0)
	for m in ms: m.start_play(SimParams.defaults())
	var d0 := ms[0].session.input_delay
	var hist: Array[int] = []
	_play(ms, 1500, func(k: int) -> void:
		if k == 200:
			for m in ms: m.link.sim_delay_ms = 70.0
		if k == 800:
			for m in ms: m.link.sim_delay_ms = 10.0
		if k % 50 == 0: hist.append(ms[0].session.input_delay))
	var hi := 0
	for v in hist: hi = maxi(hi, v)
	var sync := _in_sync(ms)
	print("      retardo cada 50 ticks: ", hist, "  cambios ", ms[0].delay_changes, "/", ms[1].delay_changes)
	check(hi > d0, "retardo adaptativo: sube con la latencia (%d → %d)" % [d0, hi])
	check(ms[0].session.input_delay < hi, "retardo adaptativo: vuelve a bajar al mejorar la red (%d)" % ms[0].session.input_delay)
	check(ms[0].delay_changes <= 6 and ms[1].delay_changes <= 6, "histéresis: pocos cambios (%d / %d)" % [ms[0].delay_changes, ms[1].delay_changes])
	check(sync[1] == 0 and sync[0] > 1300 and ms[0].desync_frame < 0 and ms[1].desync_frame < 0, "sin desincronía con cambios de retardo en caliente (%d ticks comunes)" % sync[0])
	check(NetMatch.verify_replay(ms[0].replay_dict()).is_empty(), "repetición reproducible con cambios de retardo")
	for m in ms: m.link.close()
	# 4) equipo del lobby por la red
	await _test_loadouts()
	# 5) coste de sim (presupuesto móvil)
	_test_perf()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

## Antelación máxima (ticks antes del golpe) con la que una parada todavía sale.
func _earliest_parry(params: Array) -> int:
	var best := -1
	for lead in range(1, 40):
		var e := FightEngine.new(params, 1, false); e.gap_um = 1800000
		var s := e.initial()
		for t in 90:
			var b := FightSim.IN_LOCK | (FightSim.IN_PARRY if t == 40 - lead else 0)
			e.step(s, (FightSim.IN_ATK if t == 30 else 0) | FightSim.IN_LOCK, b)
		if s[FightSim.F_FIELDS + FightSim.PARRIES] > 0: best = lead
	return best

func _test_smoothing() -> void:
	var w := Node3D.new(); root.add_child(w)
	var a := Fighter.new(); var b := Fighter.new()
	w.add_child(a); w.add_child(b)
	await process_frame
	var v := SimView.new(a, b, w)
	v.smooth = true
	var e := FightEngine.new(SimParams.defaults())
	var s := e.initial()
	v.apply(s)
	var c := s.duplicate()
	c[FightSim.X] += 500000 # el rollback corrige 0,5 m
	var before := c.duplicate()
	v.apply(c, true)
	var jumped := absf(a.global_position.x - c[FightSim.X] / 1.0e6)
	check(jumped > 0.3, "suavizado: tras la corrección no salta (%.2f m de la posición corregida)" % jumped)
	var n := 0
	while v.offsets[0].length() > 0.0 and n < 60:
		v.apply(c); n += 1
	check(n <= 25 and absf(a.global_position.x - c[FightSim.X] / 1.0e6) < 0.003, "suavizado: converge al estado en %d ticks" % n)
	check(c == before, "suavizado: el estado de la sim no se modifica")
	c[FightSim.X] += 5000000
	v.apply(c, true)
	check(absf(a.global_position.x - c[FightSim.X] / 1.0e6) < 0.003, "suavizado: saltos > 1,5 m se aplican de golpe")
	w.queue_free()
	await process_frame

func _test_loadouts() -> void:
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_net_tuning.cfg"
	gs.first_run_done = true
	gs.character_id = "berserker"
	var lo_host := NetLoadout.from_game_state(gs)
	var lo_guest := lo_host.duplicate(true)
	lo_guest["char"] = "arquero"; lo_guest["name"] = "Invitado"
	lo_guest["w"] = ["espada_escudo", 3, ""]
	check(lo_host["char"] == "berserker" and lo_host.has("w") and lo_host.has("armor"), "equipo: se serializa del lobby como datos (%s)" % lo_host["char"])
	var bad := {"char": "no_existe", "w": ["???", 999, "x"], "attrs": {"fuerza": 99999}, "level": -4}
	var ba := NetLoadout.fighter_args(bad)
	check(ba["cd"] != null and ba["wd"] != null and int(ba["eqp"]["level"]) == 1, "equipo: datos inválidos del rival se sanean")
	var ex := NetLoadout.fighter_args({"char": "berserker", "eikon": "lobo", "spells": ["a", "b", "c", "d", "e"], "boss": ["x", "y", "z", "w"], "seal": "s"})
	check(String(ex["eikon_path"]) == Catalog.EIKONS["lobo"] and ex["spells"].size() == 4 and ex["boss"].size() == 3 and lo_host.has("boss") and lo_host.has("spells") and lo_host.has("eikon"), "equipo: eikon/hechizos/sello/jefe viajan y se acotan")
	var ms := _pair(47671, 5.0, [lo_host, lo_guest])
	check(ms[0].peer_loadout.get("char") == "arquero" and ms[1].peer_loadout.get("char") == "berserker", "equipo: cada par recibe el del rival en el saludo")
	NetMatch.current = ms[1] # la arena hace de invitado
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene as Arena
	check(ar.player.character.id == "arquero" and ar.enemy.character.id == "berserker", "arena online: luchadores con el equipo de cada jugador (%s vs %s)" % [ar.player.character.id, ar.enemy.character.id])
	# el anfitrión (sin escena) construye los mismos luchadores desde los dos equipos
	var w := Node3D.new(); root.add_child(w)
	var host_f: Array[Fighter] = []
	for lo in ms[0].loadouts_by_slot():
		var a := NetLoadout.fighter_args(lo)
		var f := Fighter.new()
		f.set_loadout_defs(a["cd"], a["wd"]); f.set_skills(a["skills"]); f.set_attributes(a["attrs"])
		var q: Dictionary = a["eqp"]
		f.set_equipment(int(q["level"]), q["armor"], q["w2"], String(q["left_hand"]), q["offhand"], bool(q["shield"]))
		f.set_trinkets(q["trinkets"])
		NetLoadout.apply_extras(f, a)
		w.add_child(f); host_f.append(f)
	await process_frame
	var hp := SimParams.bake(host_f[0], host_f[1])
	for si in 2:
		for k in hp[si]:
			if str(hp[si][k]) != str(ar.sim_match.params[si].get(k)): print("DIFF ", si, " ", k, " host=", str(hp[si][k]).left(300), " arena=", str(ar.sim_match.params[si].get(k)).left(300))
	check(SimParams.params_checksum(hp) == SimParams.params_checksum(ar.sim_match.params), "equipo: el bake del anfitrión coincide con el del invitado (params_checksum)")
	ms[0].start_play(hp, ar.sim_match.engine.spawn)
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var cur := 0
	ar.sim_match.input_override[1] = func(_t: int) -> int: return FightSim.IN_LOCK | (FightSim.IN_ATK if (_t / 9) % 2 == 0 else 0)
	for i in 300:
		if rng.randf() < 0.25: cur = (rng.randi() & 0x1FFF) | FightSim.IN_LOCK
		ms[0].play_step(cur)
		await physics_frame
	check(ms[1].session.frame > 200 and ms[1].desync_frame < 0 and ms[0].desync_frame < 0 and ms[1].status == "", "arena online con equipos distintos: %d ticks sincronizados" % ms[1].session.frame)
	var ov := ar.net_overlay
	ov.set_shown(true)
	var tx := ov.text()
	check(ov != null and ov.label.visible and tx.contains("Ping") and tx.contains("Retardo") and tx.contains("Rollback") and tx.contains("estado OK"), "panel de red: visible y con ping/retardo/rollback/estado")
	print("      " + tx.replace("\n", " | "))
	ov.set_shown(false)
	check(not ov.label.visible, "panel de red: se oculta (F3 / botón Red)")
	ms[0].forfeit()
	for i in 10: await physics_frame
	ms[0].link.close()
	w.queue_free()

func _test_perf() -> void:
	var e := FightEngine.new(SimParams.defaults()); e.gap_um = 2000000
	var s := e.initial()
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var n := 3000
	var t0 := Time.get_ticks_usec()
	for i in n:
		e.step(s, (rng.randi() & 0x1FFF) | FightSim.IN_LOCK, (rng.randi() & 0x1FFF) | FightSim.IN_LOCK)
	var us := float(Time.get_ticks_usec() - t0) / n
	var worst := us * 9.0 + 8.0 * 0.2 # rollback de 8 ticks + el tick nuevo + copias de estado
	print("      paso de sim %.1f µs; peor tick con rollback de 8: %.0f µs (escritorio); ×5 móvil medio ≈ %.2f ms" % [us, worst, worst * 5.0 / 1000.0])
	check(worst * 5.0 < 4000.0, "presupuesto móvil: peor tick estimado < 4 ms (%.2f ms)" % (worst * 5.0 / 1000.0))
