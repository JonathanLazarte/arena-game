extends SceneTree
## Simulación: el jugador deambula (sin lock-on); se mide que la IA no se pegue
## a su espalda (<20% del tiempo detrás, sin contar sus pausas para respirar) y que nunca se solape (<1.8 m).

func _initialize() -> void:
	_run()

func _run() -> void:
	var seed_arg0 := OS.get_cmdline_user_args()
	seed(int(seed_arg0[0]) if seed_arg0.size() > 0 else 12345) # también el eikon del rival
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	var seed_arg := OS.get_cmdline_user_args()
	seed(int(seed_arg[0]) if seed_arg.size() > 0 else 12345)
	var p := arena.player
	var e := arena.enemy
	arena.controller.enabled = false
	arena.controller.lock_on = false
	p.max_health = 100000.0
	p.knockoff_chance_dash = 0.0
	p.knockoff_chance_heavy = 0.0
	p.health = p.max_health
	Engine.time_scale = 3.0
	var frames := 0
	var behind := 0
	var min_d := INF
	var t := 0.0
	var dir := Vector3.FORWARD
	var swords := 0
	while t < 90.0:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if fmod(t, 2.0) < dt:
			dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var pp := MeshUtil.flat(p.global_position)
		if pp.length() > 20.0 and dir.dot(pp.normalized()) > 0.0:
			dir = (-pp.normalized()).rotated(Vector3.UP, randf_range(-0.8, 0.8)) # como un jugador real, evita el muro
		p.face_target = null
		p.move_input = dir * 0.5
		if arena.state != "fight":
			continue
		frames += 1
		var rel := MeshUtil.flat(e.global_position - p.global_position)
		min_d = minf(min_d, rel.length())
		# Las pausas para respirar (ronda 9) dejan a la IA quieta mientras el jugador se aleja:
		# eso no es "pegarse a la espalda", así que no cuentan como detrás.
		var resting := arena.ai.phase in [AIController.Phase.BREATHE, AIController.Phase.REST]
		if rel.length() > 0.1 and p.facing.dot(rel.normalized()) < -0.3 and not resting:
			behind += 1
		if e.is_attacking():
			swords += 1
	var pct := 100.0 * behind / maxf(frames, 1)
	print("frames=%d detras=%.1f%% dist_min=%.2f ataques=%d" % [frames, pct, min_d, swords])
	var ok := pct < 20.0 and min_d >= 1.8 and swords > 0
	print("RESULT: %s" % ("OK" if ok else "FALLO"))
	quit(0 if ok else 1)
