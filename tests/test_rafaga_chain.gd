extends SceneTree
## Ráfaga espectral: "la ráfaga se salta la global si se repite" (global_cd_on_repeat=false)
## + cola de encadenado tras el disparo + índice alternado del tajo (izq → der → …).
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("ok   " if c else "FAIL ") + msg)
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

func _sim(P: Array, presses: Array, n: int) -> Array:
	var e := FightEngine.new(P, 7, true)
	e.spawn = [-4000000, 0, 0, 4000000, 0, 128]
	var s := e.initial()
	var starts: Array = []
	var last := 0
	for t in n:
		var ia := FightSim.IN_LOCK | (FightSim.IN_BOSS if t in presses else 0)
		e.step(s, ia, FightSim.IN_LOCK)
		if s[FightSim.AB_STARTS] != last:
			last = s[FightSim.AB_STARTS]
			starts.append(t)
	return [starts, s]

func _run() -> void:
	var a := _fighter(["rafaga"])
	var b := _fighter(["estocada"])
	await process_frame
	var P := SimParams.bake(a, b)
	var ab: Dictionary = P[0]["boss"][0]
	check(int(ab.get("rep_free", 0)) == 1, "catálogo: rafaga global_cd_on_repeat=false → rep_free")
	var w := int(ab["w"]); var end := int(ab["end"])
	# 1 pulsación + 1 en la ventana de encadenado (tras el disparo): arranca sola al terminar
	var r: Array = _sim(P, [0, w + 4], 200)
	var st: Array = r[0]
	check(st.size() == 2, "pulsación tras el disparo queda en cola (%s)" % [st])
	if st.size() == 2:
		check(st[1] - st[0] < SimAbilities.GLOBAL_CD, "la repetición no espera la global de %d (Δ=%d)" % [SimAbilities.GLOBAL_CD, st[1] - st[0]])
		check(absi(st[1] - st[0] - end) <= 1, "encadena justo al terminar (Δ=%d, end=%d)" % [st[1] - st[0], end])
	# machacar: varias ráfagas seguidas, todas espaciadas < global
	var mash: Array = []
	for t in 400:
		if t % 6 == 0:
			mash.append(t)
	r = _sim(P, mash, 400)
	st = r[0]
	var ok := st.size() >= 5
	for k in range(1, st.size()):
		ok = ok and st[k] - st[k - 1] < SimAbilities.GLOBAL_CD
	check(ok, "machacar encadena ≥5 ráfagas sin la global (%s)" % [st])
	# antes del disparo la pulsación no hace nada (no se apila)
	r = _sim(P, [0, 5], 200)
	check((r[0] as Array).size() == 1, "pulsar antes del disparo no encola")
	# índice alternado del tajo
	var idx: Array = []
	for n in range(1, 5):
		idx.append(KnightVisual.rafaga_chain_index(n))
	check(idx == [0, 1, 0, 1], "tajo alterna izq/der por pulsación (%s)" % [idx])
	# otra habilidad (sin el campo) sigue respetando su recarga
	var c := _fighter(["estocada"])
	await process_frame
	var P2 := SimParams.bake(c, b)
	check(int(P2[0]["boss"][0].get("rep_free", 0)) == 0, "estocada: repetir respeta la recarga")
	print("FALLÓ %d" % fails if fails > 0 else "TODO OK")
	quit(1 if fails > 0 else 0)
