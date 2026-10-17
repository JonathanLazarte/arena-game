extends SceneTree
## Fase 4: pilares de la arena en la sim (cuerpo y flechas), paridad con el Fighter real.
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
	# 3) paridad: Fighter real en la arena andando contra el pilar
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene as Arena
	ar.controller.enabled = false
	ar.controller.set_physics_process(false)
	ar.time_left = 1.0e9
	var f := ar.player
	f.global_position = Vector3(20, 0.2, 0)
	ar.enemy.global_position = Vector3(-30, 0.2, 0)
	var off_min := 99.0
	for t in 240:
		f.move_input = Vector3(1, 0, 0)
		await physics_frame
		off_min = minf(off_min, Vector2(f.global_position.x - 23.8, f.global_position.z).length())
	var bp := SimParams.bake(ar.player, ar.enemy)
	check(int(bp[0]["pillars"]) == 1, "bake en la arena: pilares activados")
	print("      distancia mínima al pilar: offline %.2f m, sim %.2f m" % [off_min, mind / 1.0e6])
	check(absf(off_min - mind / 1.0e6) < 0.15, "paridad: el luchador se detiene a la misma distancia del pilar (±0,15 m)")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
