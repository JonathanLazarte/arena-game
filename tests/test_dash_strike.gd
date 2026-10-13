extends SceneTree
## Ronda 14: estocada con dash (a pie y montado), animación propia Dash_Strike y búfer generoso.
## godot --headless --path . -s res://tests/test_dash_strike.gd

var fails: int = 0
var arena: Arena
var p: Fighter
var e: Fighter

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _place(dist: float) -> void:
	await wait(1.0)
	p.global_position = Vector3(0, 0, 8)
	p.facing = Vector3.FORWARD
	p.rotation.y = 0.0
	p.face_target = e
	p.stamina = p.stamina_max
	p.dash_cd = 0.0
	e.global_position = Vector3(0, 0, 8 - dist)
	e.facing = Vector3.BACK
	e.want_block = false
	e.stun = 0.0
	await physics_frame
	await physics_frame

## Sigue hasta el impacto: [frames hasta el golpe, resultado, estado visual visto, distancia recorrida]
func _track(max_frames: int) -> Dictionary:
	var landed := []
	var cb := func(t: Node3D, r: String, _o: bool) -> void:
		if t == e:
			landed.append(r)
	p.landed_hit.connect(cb)
	var start := p.global_position
	var hit_f := -1
	var saw_ds := false
	var saw_anim := false
	var gap := 0
	var idle_frames := 0
	for i in max_frames:
		await physics_frame
		if p.is_dash_striking():
			saw_ds = true
		if p._kv.state == "dash_strike":
			saw_anim = true
		if hit_f < 0:
			# fluidez: entre la voltereta y la estocada no hay frames "parados" (estado none)
			if p._kv.state == "none":
				idle_frames += 1
		if hit_f < 0 and landed.size() > 0:
			hit_f = i
	p.landed_hit.disconnect(cb)
	return {"hit_f": hit_f, "res": landed, "ds": saw_ds, "anim": saw_anim, "moved": MeshUtil.flat(p.global_position - start).length(), "idle": idle_frames}

func _run() -> void:
	seed(9)
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	p = arena.player
	e = arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
		f.knockoff_chance_dash = 0.0
		f.knockoff_chance_heavy = 0.0
	# --- Animación compuesta en Godot ---
	var ap := p._kv.ap
	check(ap.has_animation("Dash_Strike"), "existe la animación Dash_Strike (creada en Godot)")
	var an := ap.get_animation("Dash_Strike")
	var paths := []
	for i in an.get_track_count():
		paths.append(String(an.track_get_path(i)))
	check(is_equal_approx(an.length, KnightVisual.DASH_STRIKE_LEN) and paths.has("Rig/Skeleton3D:upperleg.l") and paths.has("Rig/Skeleton3D:upperarm.r"), "Dash_Strike mueve piernas (zancada) y brazos (tajo): %d pistas, %.2f s" % [an.get_track_count(), an.length])
	var sp := an.find_track(NodePath("Rig/Skeleton3D:spine"), Animation.TYPE_ROTATION_3D)
	var slice := ap.get_animation(p._kv.states["light1"])
	var sp2 := slice.find_track(NodePath("Rig/Skeleton3D:spine"), Animation.TYPE_ROTATION_3D)
	var q1 := an.rotation_track_interpolate(sp, 0.25)
	var q2 := slice.rotation_track_interpolate(sp2, 0.25 / KnightVisual.DASH_STRIKE_LEN * slice.length * KnightVisual.DASH_STRIKE_SLICE)
	check(q1.angle_to(q2) > deg_to_rad(4.0), "el tronco se inclina en la arremetida (override de hueso, %.1f°)" % rad_to_deg(q1.angle_to(q2)))
	# --- 1. Atacar DURANTE la voltereta (a pie): al acabar los i-frames sale la estocada ---
	await _place(6.5)
	var h0 := e.health
	p.move_input = Vector3.FORWARD
	check(p.dash() and p.is_rolling(), "voltereta hacia el rival")
	await physics_frame
	await physics_frame
	await physics_frame
	p.attack_light() # pulsado en los i-frames: queda en el búfer
	check(p._roll_atk_buffer, "atacar durante la voltereta queda en el búfer")
	var r := await _track(70)
	p.move_input = Vector3.ZERO
	print("   golpe en frame %d, %s, avanzó %.2f m, frames parados %d" % [r["hit_f"], str(r["res"]), r["moved"], r["idle"]])
	check(r["ds"] and r["anim"], "la voltereta enlaza con la estocada (animación Dash_Strike)")
	check(r["res"].size() > 0 and r["res"][0] == "hit" and is_equal_approx(h0 - e.health, Fighter.DASH_STRIKE["damage"] * p.damage_mult()), "la estocada impacta (%.0f de daño)" % (h0 - e.health))
	check(r["hit_f"] >= 0 and r["hit_f"] <= 39, "fluida: impacta %.2f s después de pulsar (resto de i-frames + estocada, ≤ 0,65 s)" % (r["hit_f"] / 60.0))
	check(r["idle"] == 0, "sin frames parados entre voltereta y estocada")
	check(r["moved"] > 2.5, "avanza hacia el rival (%.2f m)" % r["moved"])
	check(p.dash_strikes == 1, "contada como estocada con dash")
	# --- 2. Dash DURANTE la anticipación del ligero: se convierte en estocada ---
	await _place(5.0)
	h0 = e.health
	check(p.attack_light(), "empieza un ligero")
	await physics_frame
	await physics_frame
	p.move_input = Vector3.FORWARD
	check(p.dash() and p.atk_dash and not p.is_rolling(), "dash en la anticipación = estocada (sin voltereta)")
	r = await _track(60)
	p.move_input = Vector3.ZERO
	check(r["res"].size() > 0 and r["res"][0] == "hit" and r["hit_f"] <= 20, "impacta enseguida (frame %d)" % r["hit_f"])
	check(r["moved"] > 1.0, "con arremetida (%.2f m)" % r["moved"])
	# --- 3. Por el controlador: Dash y Atacar casi a la vez (búfer generoso) ---
	arena.controller.set_physics_process(true)
	await _place(6.5)
	h0 = e.health
	Input.action_press("move_forward")
	Input.action_press("dash")
	await physics_frame
	await physics_frame
	Input.action_release("dash")
	for i in 5:
		await physics_frame
	Input.action_press("attack_sword")
	await physics_frame
	await physics_frame
	Input.action_release("attack_sword") # ligero = al soltar, aún en la voltereta
	r = await _track(70)
	Input.action_release("move_forward")
	check(r["ds"] and e.health < h0, "Dash + Atacar por los controles = estocada que impacta")
	arena.controller.set_physics_process(false)
	# --- 4. Atacar en la recuperación de la voltereta: ya no cuenta (regla de la voltereta) ---
	await _place(12.0)
	p.move_input = Vector3.FORWARD
	p.dash()
	while p.roll_phase() != "recovery":
		await physics_frame
	p.attack_light()
	await physics_frame
	check(not p._roll_atk_buffer and not p.is_dash_striking(), "pulsado en la recuperación: no hay estocada (la voltereta sigue siendo un compromiso)")
	p.move_input = Vector3.ZERO
	# --- 5. Montado (lobo): dash + ataque usa la misma animación ---
	await wait(1.0)
	p.eikon = load(Catalog.EIKONS["lobo"])
	p.meter = Fighter.METER_MAX
	p.summon()
	await _place(8.0)
	check(p.mounted, "montado en el lobo")
	p.attack_light()
	await physics_frame
	p.move_input = Vector3.FORWARD
	check(p.dash(), "dash montado durante la anticipación")
	r = await _track(80)
	p.move_input = Vector3.ZERO
	check(r["ds"] and r["anim"] and r["res"].size() > 0, "montado: estocada con dash y animación Dash_Strike (%s)" % str(r["res"]))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
