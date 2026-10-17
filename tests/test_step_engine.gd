extends SceneTree
## Etapa 1: con ab_engine apagado y encendido, las habilidades migradas dejan el mismo
## estado tick a tick. También save/load, rollback de eventos y el grafo (rama, cancel, next).
## godot --headless --path . -s res://tests/test_step_engine.gd

var fails := 0

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(ids: Array) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(ids)
	root.add_child(f)
	return f

func _bake(a_ids: Array, b_ids: Array, engine: int) -> Array:
	SimParams.ab_engine = engine
	var a := _fighter(a_ids)
	var b := _fighter(b_ids)
	await process_frame
	var p := SimParams.bake(a, b)
	a.queue_free()
	b.queue_free()
	return p

func _inputs(t: int, kind: String) -> Array:
	var ia := FightSim.IN_LOCK
	var ib := FightSim.IN_LOCK
	if t == 8:
		ia |= FightSim.IN_BOSS
	if kind == "both" and t == 10:
		ib |= FightSim.IN_BOSS
	if kind == "trade" and t >= 12 and t % 18 < 5:
		ib |= FightSim.IN_ATK
	return [ia, ib]

func _roll(P: Array, gap: int, ticks: int, kind: String, fx: SimFx = null) -> Dictionary:
	var e := FightEngine.new(P, 7, true)
	e.fx = fx
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var sums: Array[int] = []
	var hist: Array = []
	for t in ticks:
		hist.append(s.duplicate())
		var inp: Array = _inputs(t, kind)
		e.step(s, int(inp[0]), int(inp[1]))
		if fx:
			e.after_tick(t - 2, FightSim.frame(s))
		sums.append(FightSim.checksum(s))
	return {"s": s, "sums": sums, "hist": hist, "e": e}

func _first_diff(a: PackedInt64Array, b: PackedInt64Array) -> String:
	var n := mini(a.size(), b.size())
	for i in n:
		if a[i] != b[i]:
			return "idx %d: %d != %d" % [i, a[i], b[i]]
	if a.size() != b.size():
		return "largo %d != %d" % [a.size(), b.size()]
	return ""

func _same(off: Array, on: Array, gap: int, ticks: int, kind: String, label: String) -> void:
	var a: Dictionary = _roll(off, gap, ticks, kind)
	var b: Dictionary = _roll(on, gap, ticks, kind)
	var sa: Array = a["sums"]
	var sb: Array = b["sums"]
	var bad := -1
	for i in sa.size():
		if sa[i] != sb[i]:
			bad = i
			break
	if bad < 0:
		check(true, "%s: %d ticks idénticos" % [label, ticks])
		return
	var ha: Array = a["hist"]
	var hb: Array = b["hist"]
	var detail := _first_diff(ha[bad], hb[bad])
	check(false, "%s: difiere en el tick %d (%s)" % [label, bad, detail])

func _run() -> void:
	var cat := SimSteps.catalog()
	check(cat.size() == 4, "el catálogo de la etapa tiene 4 habilidades (hay %d)" % cat.size())
	var off0: Array = await _bake(["tajo_retardado"], ["estocada"], 0)
	var on0: Array = await _bake(["tajo_retardado"], ["estocada"], 1)
	check(int(off0[0]["ab_engine"]) == 0 and int(on0[0]["ab_engine"]) == 1, "ab_engine 0 y 1 queda en los params")
	check(SimParams.params_checksum(off0) != SimParams.params_checksum(on0), "el flag entra en params_checksum")
	for id: String in SimSteps.IDS:
		var fam: int = SimAbilities.T_TIMELINE
		if id == "pisoton":
			fam = SimAbilities.T_WAVE
		elif id == "flecha_grave":
			fam = SimAbilities.T_RAIN
		var p0: Array = await _bake([id], ["estocada"], 0)
		var p1: Array = await _bake([id], ["estocada"], 1)
		var c0: Dictionary = p0[0]["boss"][0]
		var c1: Dictionary = p1[0]["boss"][0]
		check(int(c0["type"]) == fam and int(c1["type"]) == SimAbilities.T_STEPS, "%s: tipo viejo %d y motor %d" % [id, fam, SimAbilities.T_STEPS])
		check(int(c0["raw"]) == int(c1["raw"]) and int(c0["end"]) == int(c1["end"]) and int(c0.get("force", c1.get("force", 0))) == int(c1.get("force", -1)),
			"%s: raw %d/%d end %d/%d" % [id, int(c0["raw"]), int(c1["raw"]), int(c0["end"]), int(c1["end"])])
		_same(p0, p1, 2200000, 220, "idle", "%s de cerca" % id)
		_same(p0, p1, 14000000, 180, "idle", "%s de lejos" % id)
		_same(p0, p1, 3500000, 200, "trade", "%s recibiendo golpes" % id)
	var duo0: Array = await _bake(["pisoton", "tajo_retardado"], ["flecha_grave", "estocada_negra"], 0)
	var duo1: Array = await _bake(["pisoton", "tajo_retardado"], ["flecha_grave", "estocada_negra"], 1)
	_same(duo0, duo1, 5000000, 240, "both", "los dos usan el motor")
	# la habilidad de cerca hace algo (si no, el checksum idéntico no prueba nada)
	var probe: Dictionary = _roll(off0, 2200000, 220, "idle")
	check(int(probe["s"][FightSim.AB_HITS]) > 0, "el tajo de cerca conecta en el camino viejo (golpes %d)" % int(probe["s"][FightSim.AB_HITS]))
	# save / load a mitad del tajo
	var mid_off: Dictionary = _roll(off0, 2200000, 50, "idle")
	var mid_on: Dictionary = _roll(on0, 2200000, 50, "idle")
	var cont_a: PackedInt64Array = (mid_off["s"] as PackedInt64Array).duplicate()
	var cont_b: PackedInt64Array = (mid_on["s"] as PackedInt64Array).duplicate()
	var ea := FightEngine.new(off0, 7, true)
	var eb := FightEngine.new(on0, 7, true)
	var save_ok := true
	for t in range(50, 220):
		var inp: Array = _inputs(t, "idle")
		ea.step(cont_a, int(inp[0]), int(inp[1]))
		eb.step(cont_b, int(inp[0]), int(inp[1]))
		if FightSim.checksum(cont_a) != FightSim.checksum(cont_b):
			save_ok = false
			check(false, "save/load: difiere en el tick %d (%s)" % [t, _first_diff(cont_a, cont_b)])
			break
	if save_ok:
		check(true, "save/load a mitad del tajo: el resto coincide")
	# eventos del motor, sin duplicar tras un rollback
	var keys := {}
	var fx := SimFx.new()
	fx.hold_ticks = 2
	fx.callback = func(ev: Dictionary) -> void:
		var k := String(ev["key"])
		if keys.has(k):
			keys[k] = int(keys[k]) + 1
		else:
			keys[k] = 1
	var played: Dictionary = _roll(on0, 2200000, 160, "idle", fx)
	var e: FightEngine = played["e"]
	var n_keys := 0
	for k: String in keys:
		if k.contains("ab_ev"):
			n_keys += 1
	check(n_keys >= 3, "salen los eventos del paso (%d)" % n_keys)
	e.on_rollback(40)
	var rs: PackedInt64Array = (played["hist"] as Array)[40]
	for t in range(40, 160):
		var inp2: Array = _inputs(t, "idle")
		e.step(rs, int(inp2[0]), int(inp2[1]))
	e.after_tick(158, FightSim.frame(rs))
	var dup := false
	for k2: String in keys:
		if int(keys[k2]) > 1:
			dup = true
	check(not dup and fx.cancelled == 0, "rollback: sin eventos duplicados ni cancelados de más (cancelados %d)" % fx.cancelled)
	check(FightSim.checksum(rs) == int((played["sums"] as Array)[159]), "la re-simulación cae en el mismo estado")
	await _graph()
	SimParams.ab_engine = 0
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

func _gstep(total: int, windup: int, reach: int, nxt: Dictionary, branch: Variant, cancel: Variant) -> Dictionary:
	return {
		"total": total, "windup": windup, "reach": reach, "cos": 0, "raw": 3000, "force": 0, "kind": 3,
		"branch": branch, "cancel": cancel, "next": nxt,
	}

func _gability(steps: Array) -> Dictionary:
	return {
		"code": SimAbilities.code_of("tajo_retardado"), "id": "tajo_retardado", "type": SimAbilities.T_STEPS,
		"cost_type": 0, "cost": 1000, "graph": 1, "exec": SimSteps.EXEC_GRAPH,
		"family": SimAbilities.T_TIMELINE, "resist": 0, "arm0": 0, "arm1": 0, "evs": [], "steps": steps,
	}

func _trace(ab: Dictionary, presses: Dictionary, gap: int) -> Array:
	var base: Array = await _bake(["tajo_retardado"], ["estocada"], 0)
	base[0]["boss"] = [ab]
	var e := FightEngine.new(base, 3, false)
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var seen: Array = []
	for t in 90:
		var ia := 0
		if t == 8:
			ia |= FightSim.IN_BOSS
		if presses.has(t):
			ia |= int(presses[t])
		e.step(s, ia, 0)
		if s[FightSim.AB_SLOT] >= 0:
			seen.append(s[FightSim.AB_FIRED])
		else:
			seen.append(-1)
	return seen

func _saw(seen: Array, step: int) -> bool:
	return step in seen

func _graph() -> void:
	var tail := {"hit": -1, "block": -1, "whiff": -1, "default": -1}
	var idle := _gstep(18, 4, 0, tail, null, null)
	var root := _gstep(40, 30, 0, tail, {
		"from": 16, "to": 28, "buffer": 6, "commit": SimSteps.COMMIT_END, "default": -1,
		"opts": [[0, 1], [1, 2]],
	}, null)
	var ab := _gability([root, idle, idle])
	var none: Array = await _trace(ab, {}, 4000000)
	check(_saw(none, 0) and not _saw(none, 1) and not _saw(none, 2), "rama: sin pulsar, no elige remate")
	var skill: Array = await _trace(ab, {25: FightSim.IN_BOSS}, 4000000)
	check(_saw(skill, 1) and not _saw(skill, 2), "rama: la habilidad sigue al paso normal")
	var alt: Array = await _trace(ab, {25: FightSim.IN_BOSS_VAR}, 4000000)
	check(_saw(alt, 2) and not _saw(alt, 1), "rama: alt sigue al paso alternativo")
	var both: Array = await _trace(ab, {25: FightSim.IN_BOSS | FightSim.IN_BOSS_VAR}, 4000000)
	check(_saw(both, 1) and not _saw(both, 2), "rama: en el mismo tick gana la opción que está primero")
	var early: Array = await _trace(ab, {25: FightSim.IN_BOSS, 30: FightSim.IN_BOSS_VAR}, 4000000)
	check(_saw(early, 1) and not _saw(early, 2), "rama: la primera pulsación gana")
	var buf: Array = await _trace(ab, {19: FightSim.IN_BOSS_VAR}, 4000000)
	check(_saw(buf, 2), "rama: el búfer acepta la pulsación antes de la ventana")
	var alt_first := _gstep(40, 30, 0, tail, {
		"from": 16, "to": 28, "buffer": 6, "commit": SimSteps.COMMIT_END, "default": -1,
		"opts": [[1, 2], [0, 1]],
	}, null)
	var tie: Array = await _trace(_gability([alt_first, idle, idle]), {25: FightSim.IN_BOSS | FightSim.IN_BOSS_VAR}, 4000000)
	check(_saw(tie, 2) and not _saw(tie, 1), "rama: si alt está primero en las opciones, gana el empate")
	var cancel_step := _gstep(40, 30, 0, tail, null, {"from": 10, "to": 20, "trigger": 0, "only": 0, "step": 1})
	var canceled: Array = await _trace(_gability([cancel_step, idle]), {}, 4000000)
	check(_saw(canceled, 1), "cancel_into automático salta al paso siguiente")
	var whiff_step := _gstep(24, 8, 2000000, {"hit": 2, "block": -1, "whiff": 1, "default": -1}, null, null)
	var far: Array = await _trace(_gability([whiff_step, idle, idle]), {}, 12000000)
	var near: Array = await _trace(_gability([whiff_step, idle, idle]), {}, 1800000)
	check(_saw(far, 1) and not _saw(far, 2), "next: el fallo sigue on_whiff")
	check(_saw(near, 2) and not _saw(near, 1), "next: el golpe sigue on_hit")
