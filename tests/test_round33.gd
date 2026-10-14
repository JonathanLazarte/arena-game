extends SceneTree
## Ronda 33: autoseguimiento calibrado (giro fijo + velocidad), roll, hundimiento, combo de 3, armadura/inbloqueable.
## godot --headless --path . -s res://tests/test_round33.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

## Simulación pura (sin escena) del tajo teledirigido contra un objetivo que corre de lado.
static func homing_hits(dist: float, side_speed: float) -> bool:
	var d := BossAbilities.def("rafaga")
	var v := float(d["speed"])
	var w := deg_to_rad(float(d["home_deg"]))
	var cap := float(d["radius"]) + 0.75
	var p := Vector2.ZERO
	var dir := Vector2(0, 1)
	var t := Vector2(0, dist)
	var homing := true
	var time := 0.0
	var dt := 1.0 / 60.0
	while time < float(d["life"]):
		t.x += side_speed * dt
		var want := t - p
		if want.length() < cap:
			return true
		var a := dir.angle_to(want)
		if absf(a) > PI * 0.5:
			homing = false
		if homing:
			dir = dir.rotated(clampf(a, -w * dt, w * dt))
		p += dir * v * dt
		time += dt
	return false

func _run() -> void:
	await process_frame
	var sprint := 8.3 * 1.3
	check(homing_hits(3.0, sprint), "de cerca (3 m) correr de lado no basta: solo la voltereta")
	check(not homing_hits(8.0, sprint) and not homing_hits(12.0, sprint), "a media distancia (8-12 m) correr de lado lo esquiva")
	check(homing_hits(12.0, 4.1), "a media distancia caminando te alcanza")
	# --- 3. La voltereta no se hunde ---
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round33.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	Arena.start_mounted = false
	gs.from_lobby = true
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1e9
	await create_timer(3.3).timeout
	var p := arena.player
	arena.controller.set_physics_process(false)
	arena.enemy.global_position = Vector3(20, 0, 20)
	var worst := 1.0
	var rolled := 0
	var maxlift := 0.0
	for dirv: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]:
		p.global_position = Vector3.ZERO
		p.stamina = p.stamina_max
		p.move_input = dirv
		await physics_frame
		if p.dash():
			rolled += 1
		for k in 30:
			await physics_frame
			if p.is_rolling():
				worst = minf(worst, p._kv.lowest_body_y())
				maxlift = maxf(maxlift, p._kv.last_body_lift)
		p.move_input = Vector3.ZERO
		await create_timer(0.3).timeout
	check(rolled == 4 and worst >= -0.03, "voltereta: ningún hueso del cuerpo bajo el suelo (mín. %.3f m, elevación %.3f)" % [worst, maxlift])
	print("RESULT: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
