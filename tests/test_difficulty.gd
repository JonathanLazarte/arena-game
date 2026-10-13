extends SceneTree
## Ronda 7: perfiles de dificultad. El rival por defecto es "easy" (nivel 1),
## ataca menos por minuto que el perfil anterior ("normal") pero sigue entrando.
## godot --headless --path . -s res://tests/test_difficulty.gd

var fails: int = 0
const SIM := 60.0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _measure(arena: Arena, prof: AIDifficulty) -> Dictionary:
	var p := arena.player
	var e := arena.enemy
	arena.ai.profile = prof
	arena.start_round()
	arena.time_left = 1.0e9
	p.max_health = 1.0e6
	p.health = 1.0e6
	e.knockoff_chance_heavy = 0.0
	e.knockoff_chance_dash = 0.0
	p.knockoff_chance_heavy = 0.0
	p.knockoff_chance_dash = 0.0
	var a0 := e.attacks_started
	var t := 0.0
	var min_d := INF
	var commits := 0
	var last_phase := arena.ai.phase
	while t < SIM:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		p.face_target = e # jugador pasivo que mira al rival
		p.move_input = Vector3.ZERO
		min_d = minf(min_d, MeshUtil.flat(e.global_position - p.global_position).length())
		if arena.ai.phase != last_phase and arena.ai.phase == AIController.Phase.COMMIT:
			commits += 1
		last_phase = arena.ai.phase
	var apm := (e.attacks_started - a0) / (SIM / 60.0)
	return {"apm": apm, "min_d": min_d, "commits": commits}

func _run() -> void:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	check(arena.ai.profile.profile_name == "easy" and arena.ai.profile.level == 1, "el rival por defecto es nivel 1 'easy'")
	var easy: AIDifficulty = load("res://resources/ai/easy.tres")
	var normal: AIDifficulty = load("res://resources/ai/normal.tres")
	var hard: AIDifficulty = load("res://resources/ai/hard.tres")
	check(easy.engage_pause_min > normal.engage_pause_min and easy.max_chain < normal.max_chain and easy.reaction_time > normal.reaction_time \
		and easy.punish_chance < normal.punish_chance and easy.parry_chance < normal.parry_chance and easy.dodge_chance < normal.dodge_chance, "easy: pausas largas, cadenas cortas, reacción lenta, menos castigo/parry/esquiva")
	check(hard.dodge_chance > normal.dodge_chance and hard.engage_pause_min < normal.engage_pause_min, "hard: más agresivo y reactivo")
	var r_easy: Dictionary
	var r_norm: Dictionary
	seed(11)
	r_easy = await _measure(arena, easy)
	seed(11)
	r_norm = await _measure(arena, normal)
	print("easy: %.1f ataques/min, %d compromisos, dist_min %.2f" % [r_easy.apm, r_easy.commits, r_easy.min_d])
	print("normal: %.1f ataques/min, %d compromisos, dist_min %.2f" % [r_norm.apm, r_norm.commits, r_norm.min_d])
	check(r_easy.apm < r_norm.apm * 0.85, "easy ataca menos por minuto que normal (%.1f vs %.1f)" % [r_easy.apm, r_norm.apm])
	check(r_easy.apm > 4.0 and r_easy.commits >= 2, "easy sigue entrando a pelear (%.1f/min, %d entradas)" % [r_easy.apm, r_easy.commits])
	check(r_easy.min_d >= 1.8 and r_norm.min_d >= 1.8, "anti-solape: nunca se pega (%.2f / %.2f)" % [r_easy.min_d, r_norm.min_d])
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(1 if fails > 0 else 0)
