extends SceneTree
## Ronda 29: selector/nombres de personaje, suelo/muro/pilares garantizados, salto comprometido,
## orientación comprometida en el golpe, HUD del rival reducido y clips Mixamo en todos.
## godot --headless --path . -s res://tests/test_round29.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round29.cfg"
	gs.reset_defaults()
	check(gs.clean_name("   ") == "" and gs.clean_name("  Ana  ") == "Ana" and gs.clean_name("x".repeat(40)).length() == gs.NAME_MAX, "nombres limpiados y acotados")
	gs.choose_first_character("berserker", "Ragnar")
	check(gs.char_name() == "Ragnar" and gs.char_name("caballero") == Catalog.character("caballero").display_name, "nombre propio; los no comprados muestran su clase")
	gs.account_xp = Progression.xp_at_level(Progression.CHAR_REQ[0])
	gs.oro = 99999
	check(gs.buy_character("asesino", "Ezio") == "ok" and gs.switch_character("asesino") and gs.weapon_id == "dagas", "comprar con nombre y cambiar")
	gs.switch_character("berserker")
	gs.save_loadout()
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.character_id == "berserker" and gs.char_name() == "Ragnar" and gs.char_name("asesino") == "Ezio" and gs.unlocked_chars.has("asesino") and gs.weapon_id == "hacha_2m", "v%d: nombres, personajes y equipo persisten" % gs.SAVE_VERSION)
	for pair: Array in [["asesino", "dagas"], ["arquero", "arco"], ["caballero", "espada_escudo"]]:
		var kv := KnightVisual.new()
		root.add_child(kv)
		kv.setup(Color.WHITE, Catalog.character(pair[0]), Catalog.weapon(pair[1]))
		var want: String = "mx/light_idle" if pair[1] != "espada_escudo" else "mx/sns_idle"
		check(kv.idle_clip == want and String(kv.states["light0"]).begins_with("mx/"), "%s + %s: Mixamo (idle %s, ligero %s)" % [pair[0], pair[1], kv.idle_clip, kv.states["light0"]])
		kv.queue_free()
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
	var e := arena.enemy
	check(p.display_name == "Ragnar", "arena/HUD: el luchador lleva el nombre (%s)" % p.display_name)
	check(arena.hud.e_health.visible and not arena.hud.e_stamina.visible and not arena.hud.e_meter.visible, "HUD del rival: solo vida (+ estados)")
	e.global_position = Vector3(30, 0, -30)
	p.global_position = Vector3(0, -1.5, 0)
	await physics_frame
	await physics_frame
	check(p.global_position.y >= -0.001, "nunca bajo el suelo (y=%.2f)" % p.global_position.y)
	var dir := Vector3(1, 0, 0)
	p.global_position = Vector3(Projectile.arena_radius - 1.0, 0, 0)
	var min_y := 0.0
	var max_r := 0.0
	for i in 6:
		p.facing = dir
		p.move_input = dir
		p.stamina = p.stamina_max
		p.dash()
		for k in 30:
			await physics_frame
			p.move_input = dir
			min_y = minf(min_y, p.global_position.y)
			max_r = maxf(max_r, Vector2(p.global_position.x, p.global_position.z).length())
	check(max_r <= Projectile.arena_radius and min_y >= -0.001, "volteretas contra el muro: dentro (r=%.2f/%.0f, y>=%.2f)" % [max_r, Projectile.arena_radius, min_y])
	var o: Vector3 = Projectile.obstacles[0]
	var pc := Vector3(o.x, 0, o.z)
	p.move_input = Vector3.ZERO
	p.global_position = pc + Vector3(0, 0, 9)
	e.global_position = pc + Vector3(0, 0, -6)
	p.face_target = e
	p.facing = Vector3(0, 0, -1)
	p.stamina = p.stamina_max
	p.energy = p.energy_max
	p.boss_skill()
	var min_d := 99.0
	min_y = 0.0
	for i in 240:
		await physics_frame
		min_d = minf(min_d, MeshUtil.flat(p.global_position - pc).length())
		min_y = minf(min_y, p.global_position.y)
	check(min_d > 1.3 and min_y >= -0.001, "embestida de jefe contra un pilar: no lo atraviesa (d=%.2f, y>=%.2f)" % [min_d, min_y])
	check(p._kv.foot_lift() >= 0.0, "elevación de pies disponible (%.3f)" % p._kv.last_lift)
	await create_timer(1.5).timeout
	p.global_position = Vector3(0, 0, 0)
	p.stamina = p.stamina_max
	p.face_target = null
	for i in 30:
		p.move_input = Vector3(0, 0, -1)
		await physics_frame
	check(p.jump(), "salta")
	await physics_frame
	await physics_frame
	var v0 := p.planar_vel
	var f0 := p.facing
	for i in 12:
		p.move_input = Vector3(1, 0, 0)
		await physics_frame
	check(p.airborne and p.planar_vel.distance_to(v0) < 0.01 and p.facing.distance_to(f0) < 0.01, "en el aire: sin control ni giro (v %s -> %s)" % [v0, p.planar_vel])
	for i in 90:
		p.move_input = Vector3.ZERO
		await physics_frame
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -3)
	p.face_target = e
	p.stamina = p.stamina_max
	for i in 30:
		await physics_frame
	p.attack_light()
	while p.atk_state != Fighter.Atk.ACTIVE and p.atk_state != Fighter.Atk.NONE:
		await physics_frame
	var fa := p.facing
	e.global_position = Vector3(3, 0, 0)
	for i in 3:
		await physics_frame
	check(p.atk_state != Fighter.Atk.WINDUP and p.facing.distance_to(fa) < 0.01, "frames activos: la dirección del golpe queda fijada")
	gs.from_lobby = false
	gs.reset_defaults()
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(fails)
