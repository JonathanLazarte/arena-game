extends SceneTree
## Ronda 9: voltereta a pie estilo Dark Souls (arranque vulnerable -> i-frames -> recuperación vulnerable).
## godot --headless --path . -s res://tests/test_roll.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	seed(5)
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	var p := arena.player
	var e := arena.enemy
	for f: Fighter in [p, e]:
		f.knockoff_chance_heavy = 0.0
		f.knockoff_chance_dash = 0.0
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
		f.poise = 1.0e9
	await wait(0.4)
	p.dismount()
	await wait(1.0)
	e.global_position = p.global_position + Vector3(12, 0, 0)
	# --- Constantes: 2 + 12 + 10 frames a 30 fps = 24 (DS1 fast roll al 25 %) ---
	check(Fighter.ROLL_STARTUP_FRAMES + Fighter.ROLL_IFRAMES + Fighter.ROLL_RECOVERY_FRAMES == 24, "24 frames totales a 30 fps (0.8 s)")
	check(Fighter.ROLL_IFRAMES >= 11 and Fighter.ROLL_IFRAMES <= 13, "i-frames dentro del rango DS1/DS3 (11-13)")
	# --- Medir las fases frame a frame ---
	p.stamina = Fighter.STAMINA_MAX
	var s0 := p.stamina
	var pos0 := p.global_position
	p.move_input = p.facing
	check(p.dash(), "a pie, dash() inicia la voltereta")
	check(Fighter.STAMINA_MAX - p.stamina >= Fighter.COST_ROLL - 0.01 and s0 - p.stamina <= Fighter.COST_ROLL + 0.5, "coste de aguante %.0f" % (s0 - p.stamina))
	check(p.roll_phase() == "startup", "empieza en el arranque (vulnerable)")
	check(p.take_hit(5.0, e, "melee") == "hit", "golpe en el arranque: impacta")
	var counts := {"startup": 0, "iframes": 0, "recovery": 0}
	var res_by_phase := {"startup": [], "iframes": [], "recovery": []}
	var acts_in_recovery := 0
	var guard := 0
	while p.is_rolling() and guard < 200:
		await physics_frame
		guard += 1
		var ph := p.roll_phase()
		if ph == "none":
			break
		counts[ph] += 1
		(res_by_phase[ph] as Array).append(p.take_hit(1.0, e, "melee"))
		if ph == "recovery":
			if p.attack_light() or p.dash() or p.parry():
				acts_in_recovery += 1
			p.want_block = true
	p.want_block = false
	p.move_input = Vector3.ZERO
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t_start: float = counts["startup"] * dt
	var t_if: float = counts["iframes"] * dt
	var t_rec: float = counts["recovery"] * dt
	check(absf(t_start - Fighter.ROLL_STARTUP) <= dt * 1.5, "arranque %.3f s (esperado %.3f)" % [t_start, Fighter.ROLL_STARTUP])
	check(absf(t_if - Fighter.ROLL_IFRAMES / 30.0) <= dt * 1.5, "i-frames %.3f s (esperado %.3f = 12/30)" % [t_if, Fighter.ROLL_IFRAMES / 30.0])
	check(absf(t_rec - Fighter.ROLL_RECOVERY_FRAMES / 30.0) <= dt * 1.5, "recuperación %.3f s (esperado %.3f)" % [t_rec, Fighter.ROLL_RECOVERY_FRAMES / 30.0])
	check((res_by_phase["iframes"] as Array).all(func(r): return r == "dodge"), "todo golpe en i-frames se esquiva")
	check((res_by_phase["recovery"] as Array).all(func(r): return r == "hit"), "todo golpe en la recuperación impacta")
	check((res_by_phase["startup"] as Array).all(func(r): return r == "hit"), "todo golpe en el arranque impacta")
	check(acts_in_recovery == 0, "en la recuperación no se puede atacar, rodar ni hacer parry")
	var dist := MeshUtil.flat(p.global_position - pos0).length()
	check(dist > Fighter.ROLL_DISTANCE - 0.3 and dist < Fighter.ROLL_DISTANCE + Fighter.ROLL_RECOVERY_DRIFT + 0.4, "distancia de la voltereta %.2f m" % dist)
	# --- Ataque real: rodar a tiempo esquiva; muy pronto o muy tarde, impacta ---
	for case: Array in [["a tiempo", 0.32, "dodge"], ["muy pronto", -0.15, "hit"], ["muy tarde", 0.47, "hit"]]:
		await wait(1.2)
		p.global_position = Vector3(0, 0.2, 0)
		p.facing = Vector3.FORWARD
		await physics_frame
		e.global_position = p.global_position + Vector3(0, 0, -3.0)
		e.facing = Vector3.BACK
		e.face_target = p
		p.dash_cd = 0.0
		p.stamina = Fighter.STAMINA_MAX
		e.stamina = Fighter.STAMINA_MAX
		var got := []
		var cb := func(t: Node3D, r: String, _o: bool) -> void:
			if t == p:
				got.append(r)
		e.landed_hit.connect(cb)
		var lead: float = case[1]
		# Rodar en el sitio (sin dirección = hacia delante, contra el atacante, como en DS)
		p.move_input = Vector3.ZERO
		if lead < 0.0:
			p.dash()
			await wait(-lead)
			e.attack_light()
		else:
			e.attack_light()
			await wait(lead)
			p.dash()
		await wait(1.0)
		e.landed_hit.disconnect(cb)
		check(got.size() > 0 and got[0] == case[2], "ligero (0.45 s de anticipación), rodar %s: %s" % [case[0], str(got)])
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
