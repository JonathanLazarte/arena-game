extends SceneTree
## Fase 4: pilares de la arena en la sim (cuerpo y flechas), activados en la arena real.
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var P := SimParams.defaults().duplicate(true)
	for p: Dictionary in P: p["pillars"] = 1
	# 1) andar contra el pilar 1 (23,8 m, 0): no se atraviesa
	var e := FightEngine.new(P); var s := e.initial()
	s[FightSim.X] = 20000000; s[FightSim.Z] = 0
	s[FightSim.F_FIELDS + FightSim.X] = -30000000
	var dir_east := FxMath.dir_of(1000, 0) >> 3
	var mind := 1 << 40
	for t in 240:
		e.step(s, FightSim.make_input(dir_east, true, 0), 0)
		mind = mini(mind, FxMath.length(s[FightSim.X] - 23800000, s[FightSim.Z]))
	check(mind >= FightSim.PILLAR_BODY_R - 1, "sim: el luchador no entra en el pilar (distancia mínima %.2f m)" % (mind / 1.0e6))
	# 2) flecha contra un pilar entre los dos
	s = e.initial()
	s[FightSim.X] = 23800000; s[FightSim.Z] = 8000000; s[FightSim.FACE] = FxMath.dir_of(0, -1000)
	s[FightSim.F_FIELDS + FightSim.X] = 23800000; s[FightSim.F_FIELDS + FightSim.Z] = -8000000
	var hp1 := s[FightSim.F_FIELDS + FightSim.HP]
	e.step(s, FightSim.IN_SWAP | FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 60: e.step(s, FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 30: e.step(s, FightSim.IN_ATK | FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 200: e.step(s, FightSim.IN_LOCK, FightSim.IN_LOCK)
	check(s[FightSim.SHOTS] > 0 and s[FightSim.F_FIELDS + FightSim.HP] == hp1, "sim: la flecha se detiene en el pilar (%d disparos, vida intacta)" % s[FightSim.SHOTS])
	var P0 := SimParams.defaults()
	var e0 := FightEngine.new(P0); var s0 := e0.initial()
	s0[FightSim.X] = 23800000; s0[FightSim.Z] = 8000000; s0[FightSim.FACE] = FxMath.dir_of(0, -1000)
	s0[FightSim.F_FIELDS + FightSim.X] = 23800000; s0[FightSim.F_FIELDS + FightSim.Z] = -8000000
	e0.step(s0, FightSim.IN_SWAP | FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 60: e0.step(s0, FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 30: e0.step(s0, FightSim.IN_ATK | FightSim.IN_LOCK, FightSim.IN_LOCK)
	for t in 200: e0.step(s0, FightSim.IN_LOCK, FightSim.IN_LOCK)
	check(s0[FightSim.F_FIELDS + FightSim.HP] < hp1, "control: sin pilares la misma flecha impacta")
	# 3) en la arena real los pilares quedan activados en los params (fase 8: ya no hay Fighter offline que comparar)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene as Arena
	check(int(ar.sim_match.params[0]["pillars"]) == 1, "bake en la arena: pilares activados")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
