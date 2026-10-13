extends SceneTree
## Ronda 9: la IA no persigue sin parar; hace respiros (se aleja, rodea a distancia,
## recupera aguante o espera) de varios segundos aleatorios, sobre todo en "easy".
## godot --headless --path . -s res://tests/test_ai_breather.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _sim(profile_path: String, secs: float) -> Dictionary:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.controller.set_physics_process(false)
	arena.ai.profile = load(profile_path)
	var p := arena.player
	var e := arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 1.0e6
		f.health = 1.0e6
		f.meter_passive = false
	var ai := arena.ai
	var durs: Array[float] = []
	var cur := 0.0
	var dist_sum := 0.0
	var dist_n := 0
	var attacks_in_breather := 0
	var last_started := e.attacks_started
	var frames := int(secs * Engine.physics_ticks_per_second / Engine.time_scale) # secs de juego
	for i in frames:
		await physics_frame
		# El jugador se queda quieto delante (es la IA la que debe dar espacio)
		p.move_input = Vector3.ZERO
		if ai.phase == AIController.Phase.BREATHE:
			cur += Engine.time_scale / Engine.physics_ticks_per_second # tiempo de juego
			dist_sum += MeshUtil.flat(e.global_position - p.global_position).length()
			dist_n += 1
			if e.attacks_started != last_started:
				attacks_in_breather += 1
		elif cur > 0.0:
			durs.append(cur)
			cur = 0.0
		last_started = e.attacks_started
	return {"breathers": ai.breathers, "time": ai.breathe_time, "durs": durs,
		"avg_dist": dist_sum / maxf(dist_n, 1), "attacks": attacks_in_breather, "attacks_total": e.attacks_started}

func _run() -> void:
	seed(21)
	Engine.time_scale = 3.0
	var easy: Dictionary = await _sim("res://resources/ai/easy.tres", 60.0)
	print("   easy: ", easy)
	check(easy["breathers"] >= 3, "easy: varios respiros en 60 s (%d)" % easy["breathers"])
	check(easy["time"] >= 12.0, "easy: al menos 12 s de respiro en 60 s de juego (%.1f s)" % easy["time"])
	var durs: Array = easy["durs"]
	check(durs.size() >= 2 and durs.max() - durs.min() > 0.4, "duraciones aleatorias (%s)" % str(durs.map(func(d): return snappedf(d, 0.1))))
	check(durs.size() > 0 and durs.min() >= 2.0, "cada respiro dura varios segundos (mín %.1f s)" % (durs.min() if durs.size() > 0 else 0.0))
	check(easy["avg_dist"] >= 8.5, "durante el respiro se queda lejos (media %.1f m)" % easy["avg_dist"])
	check(easy["attacks"] == 0, "no ataca durante el respiro")
	check(easy["attacks_total"] > 0, "fuera del respiro sigue atacando (%d ataques)" % easy["attacks_total"])
	seed(21)
	var hard: Dictionary = await _sim("res://resources/ai/hard.tres", 60.0)
	print("   hard: ", hard)
	check(easy["time"] > hard["time"], "easy respira más que hard (%.1f s vs %.1f s)" % [easy["time"], hard["time"]])
	Engine.time_scale = 1.0
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
