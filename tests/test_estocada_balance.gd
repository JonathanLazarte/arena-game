extends SceneTree
## Prueba de balance de la Estocada (Fase 1):
## 1. La carga (BS_PH == 1) no es invulnerable (recibe daño).
## 2. Un tambaleo leve (stun_lvl1) no interrumpe la carga (súper-armadura).
## 3. Un aturdimiento pesado (stun_lvl2) o derribo sí interrumpe la carga.
## 4. La embestida (BS_PH == 2) mantiene su invulnerabilidad/i-frames.
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

func _bake(a_ids: Array, b_ids: Array) -> Array:
	var a := _fighter(a_ids)
	var b := _fighter(b_ids)
	await process_frame
	var p := SimParams.bake(a, b)
	a.queue_free()
	b.queue_free()
	return p

func _run() -> void:
	var P: Array = await _bake(["estocada"], ["estocada"])
	var e := FightEngine.new(P, 7, true)
	e.spawn = [-2000000, 0, 0, 2000000, 0, 128] # 4m de distancia
	var s := e.initial()

	# Tick 0 a 10: Player 0 arranca estocada en t=2
	for t in range(0, 10):
		var ia := FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 2 else 0)
		e.step(s, ia, FightSim.IN_LOCK)

	check(s[FightSim.BS_PH] == 1, "Player 0 entra en fase de carga (BS_PH == 1)")
	check(s[FightSim.INVULN] == 0, "Durante la carga INVULN es 0 (no es invulnerable)")

	# 1. Comprobar que recibe daño normal durante la carga
	var hp_before: int = s[FightSim.HP]
	var res := FightSim._take_hit(s, P, 1, 0, 10000, 0, -1, 1000, 1000, 0) # Player 1 golpea a Player 0
	check(res == 1, "Ataque rival impacta a la estocada cargando (res == 1)")
	check(s[FightSim.HP] < hp_before, "Player 0 recibe daño durante la carga (%d -> %d)" % [hp_before, s[FightSim.HP]])
	check(s[FightSim.BS_PH] == 1, "Ataque que no aturde no corta la carga")

	# 2. Comprobar súper-armadura: tambaleo leve (stun_lvl1) no interrumpe
	FightSim._apply_stun(s, 0, FightSim.T_STAGGER, P)
	check(s[FightSim.BS_PH] == 1, "Tambaleo leve no interrumpe la carga (súper-armadura)")

	# 3. Comprobar interrupción: stun nivel 2 interrumpe la carga
	FightSim._apply_stun(s, 0, FightSim.T_STUN, P)
	check(s[FightSim.BS_PH] == 0, "Stun nivel 2 interrumpe y resetea la estocada (BS_PH == 0)")
	check(s[FightSim.STUN] > 0, "Player 0 queda aturdido tras la interrupción")

	# 4. Comprobar que en fase 2 (embestida) sí tiene INVULN
	var s2 := e.initial()
	var entered_ph2 := false
	for t in range(0, 120):
		var ia := FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 2 else 0)
		e.step(s2, ia, FightSim.IN_LOCK)
		if s2[FightSim.BS_PH] == 2 and s2[FightSim.BS_T] > 0:
			entered_ph2 = true
			check(s2[FightSim.INVULN] > 0, "En fase 2 (embestida) INVULN está activo (%d)" % s2[FightSim.INVULN])
			break
	check(entered_ph2, "La estocada transiciona a fase 2 (embestida)")

	print("FALLÓ %d" % fails if fails > 0 else "TODO OK")
	quit(1 if fails > 0 else 0)
