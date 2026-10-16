extends SceneTree
## Fase 1: partida local a dos jugadores en la arena sobre FightSim (Arena.sim_mode), con entradas guionizadas.
## godot --headless --path . -s res://tests/test_net_sim_match.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	check(Arena.sim_mode == false, "modo sim apagado por defecto")
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var off: Arena = current_scene as Arena
	check(off.sim_match == null and not off.player.sim_driven and off.controller.enabled, "arena por defecto: juego offline intacto")
	Arena.sim_mode = true
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var a: Arena = current_scene as Arena
	a.time_left = 1.0e9
	var m := a.sim_match
	check(m != null and a.player.sim_driven and a.enemy.sim_driven, "modo sim: SimMatch creado y ambos Fighter en modo vista")
	check(not a.controller.enabled and not a.ai.is_physics_processing(), "modo sim: IA y PlayerController desactivados")
	check(m.params_hash == SimParams.params_checksum(SimParams.bake(a.player, a.enemy)), "params_checksum calculado al empezar")
	var z0 := a.player.global_position.z
	check(absf(m.state[FightSim.Z] / 1.0e6 - z0) < 0.01, "estado inicial desde la aparición de la arena")
	var kinds := {}
	m.on_event = func(ev: Dictionary) -> void:
		kinds[ev["kind"]] = true
		a._on_sim_event(ev)
	# jugador 1 avanza hacia el rival (bits de mundo: rumbo hacia -z) y golpea en toques; jugador 2 quieto
	var dir_to := FxMath.dir_of(0, -1000) >> 3
	m.input_override[0] = func(t: int) -> int:
		var gap: int = m.state[FightSim.Z] - m.state[FightSim.F_FIELDS + FightSim.Z]
		var mv := FightSim.make_input(dir_to, gap > 2200000, FightSim.IN_LOCK)
		if gap <= 2200000 and (t / 8) % 2 == 0: mv |= FightSim.IN_ATK
		return mv
	m.input_override[1] = func(_t: int) -> int: return FightSim.IN_LOCK
	var hp1 := a.enemy.health
	var ts := Engine.time_scale
	var hp_min := hp1
	for i in 900:
		await physics_frame
		hp_min = minf(hp_min, a.enemy.health)
	check(a.player.global_position.z < z0 - 3.0, "el jugador 1 se acerca (vista sigue a la sim)")
	check(hp_min < hp1 and a.wins[0] >= 1, "el jugador 1 golpea al 2 y gana la ronda (vida mínima %.1f)" % hp_min)
	check(kinds.has("swing") and kinds.has("hit") and kinds.has("hurt"), "eventos de efectos recibidos: %s" % [kinds.keys()])
	check(Engine.time_scale == ts and a.hitstops == 0, "sin hit-stop de Engine.time_scale en modo sim")
	check(m.tick_n >= 400, "la sim avanza un tick por tick físico (%d)" % m.tick_n)
	# reinicio de ronda: vuelve a la aparición
	a.start_round()
	check(absf(m.state[FightSim.Z] / 1.0e6 - z0) < 0.01 and m.state[FightSim.HP] == m.params[0]["hp"], "start_round reinicia el estado de la sim")
	Arena.sim_mode = false
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
