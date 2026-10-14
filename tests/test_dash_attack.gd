extends SceneTree
## Ronda 9: atacar durante el dash montado. La anticipación (ligero o fuerte cargado)
## se puede empezar antes o durante el dash y el golpe sale al acabar el dash, delante del rival.
## godot --headless --path . -s res://tests/test_dash_attack.gd

var fails: int = 0

func _initialize() -> void:
	Fighter.dash_strike_enabled = true # ronda 33: desactivada por defecto
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

var arena: Arena
var p: Fighter
var e: Fighter

func _setup_case() -> void:
	await wait(1.6)
	p.global_position = Vector3(0, 0.2, 10)
	p.facing = Vector3.FORWARD
	p.rotation.y = 0.0
	if p.mount_node:
		p.mount_node.global_transform = p.global_transform
	e.global_position = Vector3(0, 0.2, 2.5) # 7.5 m delante
	e.facing = Vector3.BACK
	e.want_block = false
	p.dash_cd = 0.0
	p.stamina = Fighter.STAMINA_MAX
	p.face_target = e
	await physics_frame
	await physics_frame

## Sigue frame a frame hasta el golpe; devuelve [frame en que acaba el dash, frame del golpe, distancia al golpear]
func _track(max_frames: int) -> Array:
	var end_f := -1
	var hit_f := -1
	var hit_d := -1.0
	var was := p.dash_time > 0.0
	var landed := []
	var cb := func(t: Node3D, r: String, _o: bool) -> void:
		if t == e:
			landed.append(r)
	p.landed_hit.connect(cb)
	for i in max_frames:
		await physics_frame
		if was and p.dash_time <= 0.0 and end_f < 0:
			end_f = i
		was = p.dash_time > 0.0
		if hit_f < 0 and landed.size() > 0:
			hit_f = i
			hit_d = MeshUtil.flat(e.global_position - p.global_position).length()
	p.landed_hit.disconnect(cb)
	return [end_f, hit_f, hit_d, landed]

func _run() -> void:
	seed(11)
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	p = arena.player
	e = arena.enemy
	for f: Fighter in [p, e]:
		f.knockoff_chance_heavy = 0.0
		f.knockoff_chance_dash = 0.0
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
	check(p.mounted, "el jugador va montado")
	# --- 1. Ligero empezado ANTES del dash ---
	arena.controller.set_physics_process(false)
	await _setup_case()
	var h0 := e.health
	check(p.attack_light(), "empieza la anticipación del ligero")
	await physics_frame
	p.move_input = Vector3.FORWARD
	check(p.dash(), "dash montado permitido durante la anticipación")
	var r: Array = await _track(90)
	p.move_input = Vector3.ZERO
	print("   dash acaba en frame %d, golpe en frame %d, a %.2f m, %s" % [r[0], r[1], r[2], str(r[3])])
	check(r[1] >= 0 and r[3][0] == "hit", "el ligero impacta")
	check(r[0] >= 0 and absf(r[1] - r[0]) <= 2, "el golpe sale al acabar el dash (±2 frames)")
	check(r[2] < p.sword_range(), "golpea justo delante del rival (%.2f m)" % r[2])
	check(is_equal_approx(h0 - e.health, p.combo_hit_for(1).damage * p.damage_mult()), "solo daño de espada (1.er golpe del combo), sin embestida (%.0f)" % (h0 - e.health))
	check(p.dash_strikes == 1, "contado como golpe de dash")
	# --- 2. Fuerte cargado con el botón (mantener), dash y golpe: por el controlador ---
	arena.controller.set_physics_process(true)
	await _setup_case()
	h0 = e.health
	Input.action_press("attack_sword")
	for i in int(Fighter.HEAVY_HOLD * 60.0) + 3:
		await physics_frame
	check(p.atk_state == Fighter.Atk.WINDUP and p.atk_heavy, "mantener carga el fuerte (anticipación)")
	Input.action_press("move_forward")
	Input.action_press("dash")
	await physics_frame
	await physics_frame
	Input.action_release("dash")
	check(p.dash_time > 0.0, "dash durante la carga del fuerte")
	r = await _track(120)
	Input.action_release("attack_sword")
	Input.action_release("move_forward")
	print("   dash acaba en frame %d, golpe en frame %d, a %.2f m, %s" % [r[0], r[1], r[2], str(r[3])])
	check(r[1] >= 0 and r[3][0] == "hit" and is_equal_approx(h0 - e.health, Fighter.HEAVY["damage"]), "el fuerte impacta (%.0f de daño)" % (h0 - e.health))
	check(r[0] >= 0 and absf(r[1] - r[0]) <= 2, "el fuerte sale al acabar el dash (±2 frames)")
	check(r[2] < p.sword_range(), "delante del rival (%.2f m)" % r[2])
	# --- 3. Ataque empezado DURANTE el dash ---
	arena.controller.set_physics_process(false)
	await _setup_case()
	h0 = e.health
	p.move_input = Vector3.FORWARD
	check(p.dash(), "dash")
	await physics_frame
	await physics_frame
	check(p.attack_light(), "ligero empezado durante el dash")
	r = await _track(90)
	p.move_input = Vector3.ZERO
	print("   dash acaba en frame %d, golpe en frame %d, a %.2f m, %s" % [r[0], r[1], r[2], str(r[3])])
	check(r[1] >= 0 and r[3][0] == "hit", "impacta")
	check(r[0] >= 0 and absf(r[1] - r[0]) <= 2, "golpe al acabar el dash")
	# --- 4. El dash montado sin ataque no cambia (embestida + empuje) ---
	await _setup_case()
	h0 = e.health
	p.move_input = Vector3.FORWARD
	p.dash()
	await wait(0.6)
	p.move_input = Vector3.ZERO
	check(is_equal_approx(h0 - e.health, Fighter.DASH_DAMAGE), "dash sin ataque: embestida de %.0f como antes" % (h0 - e.health))
	check(p.roll_t < 0.0, "montado no hay voltereta")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
