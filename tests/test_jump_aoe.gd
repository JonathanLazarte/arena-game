extends SceneTree
## Ronda 14: salto (Espacio / botón Saltar), estado en el aire, aterrizaje, ataque en salto,
## golpes de área en el suelo (GroundAoE) que el salto esquiva, golpe sísmico del Berserker
## y la IA saltando áreas.
## godot --headless --path . -s res://tests/test_jump_aoe.gd

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

func _ground(f: Fighter) -> void:
	while f.airborne or f.land_t > 0.0:
		await physics_frame
	f.stamina = f.stamina_max
	f.special_cd = 0.0
	f.stun = 0.0

func _run() -> void:
	seed(21)
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	p = arena.player
	e = arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
	await wait(0.5)
	# --- Entrada ---
	var space := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
			space = true
	check(space, "Espacio = saltar")
	var btns := {}
	for n in arena.hud.find_children("*", "TouchScreenButton", true, false):
		btns[(n as TouchScreenButton).action] = n
	check(btns.has("jump") and btns.has("special") and btns.has("dash"), "botones táctiles Saltar y Habilidad (y Dash)")
	# --- Salto por la acción ---
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	check(p.airborne and p.jumps == 1, "la acción jump salta")
	var peak := 0.0
	var air := 0
	var saw_jump_anim := false
	while p.airborne and air < 120:
		await physics_frame
		air += 1
		peak = maxf(peak, p.global_position.y)
		saw_jump_anim = saw_jump_anim or p._kv.state.begins_with("jump")
		if air == 10:
			check(not p.is_grounded(), "en el aire no cuenta como en el suelo")
			check(not p.dash() and not p.jump() and not p.special(), "en el aire: sin voltereta, doble salto ni habilidad")
	print("   %d frames en el aire, altura máx %.2f m" % [air, peak])
	check(peak > 1.2 and peak < 2.2 and air >= 35 and air <= 60, "salto con gravedad: %.2f m, %.2f s" % [peak, air / 60.0])
	check(saw_jump_anim, "animación de salto (Jump_Start / Jump_Idle)")
	check(p.land_t > 0.0 and not p.attack_light(), "al caer: breve recuperación (no puede atacar)")
	await wait(Fighter.LAND_RECOVERY + 0.05)
	check(p.is_grounded() and p.land_t <= 0.0, "recuperado en el suelo")
	# --- GroundAoE: de pie te da, saltando no ---
	await _ground(p)
	p.global_position = Vector3(0, 0, 8)
	e.global_position = Vector3(0, 0, -8)
	await physics_frame
	var h0 := p.health
	var a := GroundAoE.spawn(arena, e, e.team, p.global_position, 4.0, 0.5, 20.0)
	await physics_frame
	check(a.is_in_group("ground_aoe") and a._fill != null and not a.detonated, "anillo de aviso en el suelo antes del golpe")
	await wait(0.65)
	check(a.detonated and a.results.get(p, "") == "hit" and p.health < h0, "área en el suelo: de pie te alcanza (%.0f)" % (h0 - p.health))
	await wait(0.8)
	await _ground(p)
	h0 = p.health
	a = GroundAoE.spawn(arena, e, e.team, p.global_position, 4.0, 0.6, 20.0)
	await wait(0.35)
	check(p.jump(), "salta durante el aviso")
	await wait(0.4)
	check(a.detonated and a.results.get(p, "") == "air" and is_equal_approx(p.health, h0) and p.aoe_jumped == 1, "saltando, el área no te alcanza")
	await _ground(p)
	# Saltar demasiado pronto: ya has caído cuando detona
	h0 = p.health
	a = GroundAoE.spawn(arena, e, e.team, p.global_position, 4.0, 1.4, 20.0)
	p.jump()
	await wait(1.6)
	check(a.results.get(p, "") == "hit" and p.health < h0, "saltar demasiado pronto = te alcanza")
	await wait(0.8)
	await _ground(p)
	# Fuera del radio no pasa nada
	h0 = p.health
	a = GroundAoE.spawn(arena, e, e.team, p.global_position + Vector3(6, 0, 0), 4.0, 0.3, 20.0)
	await wait(0.45)
	check(not a.results.has(p) and is_equal_approx(p.health, h0), "fuera del anillo no te alcanza")
	# --- Golpe sísmico del Berserker ---
	await wait(0.6)
	e.character = load("res://resources/characters/berserker.tres")
	check(e.has_special() and e.character.special_id == "golpe_sismico", "el Berserker tiene el golpe sísmico")
	check(not p.has_special(), "el resto de personajes (de momento) no")
	p.global_position = Vector3(0, 0, 8)
	e.global_position = Vector3(0, 0, 5)
	await physics_frame
	await _ground(p)
	e.stamina = e.stamina_max
	e.special_cd = 0.0
	h0 = p.health
	check(e.special(), "el Berserker usa el golpe sísmico")
	var slam: GroundAoE = null
	for n in get_nodes_in_group("ground_aoe"):
		if (n as GroundAoE).source == e:
			slam = n
	check(slam != null and is_equal_approx(slam.radius, Fighter.SLAM_RADIUS) and e.special_t > 0.0 and not e.special(), "anillo de aviso de %.0f m y anticipación (sin repetir)" % Fighter.SLAM_RADIUS)
	await wait(Fighter.SLAM_TELEGRAPH + 0.1)
	check(p.health < h0 and p.stun > 0.0, "de pie: daña y derriba (%.0f)" % (h0 - p.health))
	await wait(1.0)
	await _ground(p)
	e.special_cd = 0.0
	e.stamina = e.stamina_max
	p.global_position = Vector3(0, 0, 8)
	e.global_position = Vector3(0, 0, 5)
	h0 = p.health
	e.special()
	await wait(Fighter.SLAM_TELEGRAPH - 0.3)
	p.jump()
	await wait(0.5)
	check(is_equal_approx(p.health, h0), "saltando se esquiva el golpe sísmico")
	await _ground(p)
	# Montado en el fénix (vuela) el área no alcanza
	p.eikon = load(Catalog.EIKONS["fenix"])
	p.meter = Fighter.METER_MAX
	p.summon()
	h0 = p.health
	a = GroundAoE.spawn(arena, e, e.team, p.global_position, 4.0, 0.3, 20.0)
	await wait(0.45)
	check(p.mounted and a.results.get(p, "") == "air" and is_equal_approx(p.health, h0), "en el fénix (vuela) el área no alcanza")
	p.dismiss_eikon()
	await wait(0.3)
	# --- Ataque en salto ---
	await _ground(p)
	p.global_position = Vector3(0, 0, 8)
	e.global_position = Vector3(0, 0, 6.3)
	p.facing = Vector3.FORWARD
	p.face_target = e
	await physics_frame
	var eh := e.health
	p.jump()
	await wait(0.3)
	check(p.attack_light() and p.atk_jump, "atacar en el aire = ataque en salto (picado)")
	await wait(0.8)
	check(e.health < eh and not p.airborne, "el picado golpea al caer (%.0f)" % (eh - e.health))
	# --- IA: salta las áreas que le van a alcanzar ---
	await wait(0.8)
	var prof := (arena.ai.profile as AIDifficulty).duplicate() as AIDifficulty
	prof.jump_aoe_chance = 1.0
	arena.ai.profile = prof
	arena.ai.enabled = true
	await _ground(e)
	var dodged := 0
	var hits := 0
	for k in 4:
		await wait(1.2)
		e.stamina = e.stamina_max
		var aa := GroundAoE.spawn(arena, p, p.team, e.global_position, 5.0, 0.8, 1.0)
		await wait(1.0)
		if aa.results.get(e, "") == "air":
			dodged += 1
		elif aa.results.get(e, "") == "hit":
			hits += 1
	check(arena.ai.aoe_jumps >= 3 and dodged >= 3, "la IA salta las áreas (saltos %d, esquivadas %d/4)" % [arena.ai.aoe_jumps, dodged])
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
