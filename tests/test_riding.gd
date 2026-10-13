extends SceneTree
## Ronda 8: postura de jinete a horcajadas, pegado al punto de silla del caballo.
## godot --headless --path . -s res://tests/test_riding.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	var p := arena.player
	await create_timer(0.8).timeout
	check(p.mounted, "el jugador empieza montado")
	check(p._kv.riding.amount > 0.99, "postura a horcajadas activa (%.2f)" % p._kv.riding.amount)
	var gap_m := p._kv.riding.knee_gap
	var keep := p._kv.riding.thigh_spread_deg
	p._kv.riding.thigh_spread_deg = 0.0 # misma pose sentada, sin abrir las piernas
	await process_frame
	await process_frame
	var gap_sit := p._kv.riding.knee_gap
	p._kv.riding.thigh_spread_deg = keep
	await physics_frame
	check(gap_m > gap_sit + 0.1, "a horcajadas las rodillas van abiertas a los flancos (%.2f vs %.2f m sentado en silla)" % [gap_m, gap_sit])
	var hips := p._rider_root.global_position
	var sp := p.mount_node.saddle_position()
	check(hips.distance_to(sp) < 0.05, "el jinete está en el punto de silla (%.3f m)" % hips.distance_to(sp))
	check(sp.y > p.mount_node.global_position.y + 1.2, "la silla está sobre el lomo (%.2f m)" % (sp.y - p.mount_node.global_position.y))
	# Al galopar el jinete sigue la silla (sube y baja con el lomo)
	p.move_input = p.facing
	var ys: Array[float] = []
	var max_err := 0.0
	for i in 60:
		await physics_frame
		ys.append(p._rider_root.global_position.y)
		max_err = maxf(max_err, p._rider_root.global_position.distance_to(p.mount_node.saddle_position()))
	check(max_err < 0.35, "galopando sigue la silla (error máx %.3f m)" % max_err)
	check(ys.max() - ys.min() > 0.005, "el jinete se mueve con el lomo (%.3f m)" % (ys.max() - ys.min()))
	p.move_input = Vector3.ZERO
	p.dismount()
	await create_timer(0.6).timeout
	check(p._kv.riding.amount < 0.01, "a pie se quita la postura de montar")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
