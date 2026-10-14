extends SceneTree
## Ronda 10: las armas y personajes cambian el combate de verdad.
var fails: int = 0
func _initialize() -> void:
	_run()
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1
func wait(s: float) -> void:
	await create_timer(s).timeout

var arena: Arena

func setup_pair(cp: String, wp: String, ce: String = "caballero", we: String = "espada_escudo") -> Array:
	if arena:
		arena.queue_free()
		await process_frame
	var gs := root.get_node("GameState")
	gs.from_lobby = false
	gs.random_rival = false
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	var p := arena.player
	var e := arena.enemy
	# Reconstruye con el equipamiento pedido (como lo haría el lobby)
	for pair: Array in [[p, cp, wp], [e, ce, we]]:
		var f: Fighter = pair[0]
		f.set_loadout_defs(Catalog.character(pair[1]), Catalog.weapon(pair[2]))
		f._apply_character()
		f.reset_for_round(f.global_position, f.facing, false)
		f.dismount()
		f.owned_mount.global_position = Vector3(20 * (1 if f.team == 0 else -1), 0, 15)
	await wait(0.1)
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -1.5)
	p.facing = Vector3(0, 0, -1)
	e.facing = Vector3(0, 0, 1)
	return [p, e]

func hit_damage(p: Fighter, e: Fighter, heavy: bool) -> float:
	var h0 := e.health
	if heavy:
		p.attack_heavy()
	else:
		p.sword()
	await wait(1.6)
	return h0 - e.health

func _run() -> void:
	seed(3)
	var r: Array = await setup_pair("caballero", "espada_escudo")
	var p: Fighter = r[0]
	var e: Fighter = r[1]
	var base := await hit_damage(p, e, false)
	check(is_equal_approx(base, p.combo_hit_for(1).damage), "espada y escudo: 1.er golpe del combo %.0f (%.1f)" % [p.combo_hit_for(1).damage, base])
	check(is_equal_approx(p.sword_range(), 2.2) and p.max_combo() == 3, "espada y escudo: alcance 2.2, combo 3")
	r = await setup_pair("berserker", "hacha_2m")
	p = r[0]; e = r[1]
	var axe := await hit_damage(p, e, false)
	check(is_equal_approx(axe, p.combo_hit_for(1).damage * 1.15), "hacha + berserker: 1.er golpe x1.15 (%.1f)" % axe)
	check(p.max_combo() == 3 and not p.has_shield() and p.poise_max == 80.0 and p.max_health == 120.0 + p.mount.health_bonus, "berserker: combo 3, sin escudo, poise 80, vida 120")
	# Rompeguardias: bloquear el hacha cuesta el doble que la espada
	var c_axe := e.blocked_hit_cost(12.0, p)
	r = await setup_pair("caballero", "espada_escudo")
	var c_sword: float = (r[1] as Fighter).blocked_hit_cost(12.0, r[0])
	check(is_equal_approx(c_axe, c_sword * 2.0), "hacha: bloquearla cuesta x2 de aguante (%.1f vs %.1f)" % [c_axe, c_sword])
	# Furia
	r = await setup_pair("berserker", "hacha_2m")
	p = r[0]; e = r[1]
	var normal_mult := p.damage_mult()
	p.health = p.max_health * 0.3
	check(is_equal_approx(p.damage_mult(), normal_mult * 1.25), "Furia: +25 %% de daño bajo 40 %% de vida")
	# Dagas: rápidas y de corto alcance
	r = await setup_pair("asesino", "dagas")
	p = r[0]; e = r[1]
	check(p.sword_range() < 2.0 and p.max_combo() == 3 and p.combo_hit_for(1).windup < 0.3, "dagas: alcance corto, combo 3, 1.er golpe rápido")
	e.global_position = Vector3(0, 0, -3.0) # fuera de alcance de las dagas incluso con su paso corto (0,6 m)
	var miss := await hit_damage(p, e, false)
	check(miss == 0.0, "dagas: a 3 m no alcanzan (%.1f)" % miss)
	check(p.roll_iframe_end() > Fighter.ROLL_IFRAME_END and is_equal_approx(p.character.roll_cost_mult, 0.75), "Sombra: más i-frames y voltereta más barata")
	var st0 := p.stamina
	p.move_input = Vector3(1, 0, 0)
	p.dash()
	await wait(0.05)
	check(is_equal_approx(st0 - p.stamina, Fighter.COST_ROLL * 0.75), "Sombra: la voltereta cuesta 75 %% (%.1f)" % (st0 - p.stamina))
	p.move_input = Vector3.ZERO
	# Lanza: alcance largo, más daño a caballo, arco estrecho
	r = await setup_pair("caballero", "lanza")
	p = r[0]; e = r[1]
	e.global_position = Vector3(0, 0, -2.7)
	var lance := await hit_damage(p, e, false)
	check(lance > 0.0 and p.sword_range() > 2.7 and p.sword_half_arc() < deg_to_rad(40), "lanza: golpea a 2.7 m (%.1f), arco estrecho" % lance)
	p.mounted = true
	check(is_equal_approx(p.damage_mult(), 1.25), "lanza: x1.25 de daño montado")
	p.mounted = false
	# Espada larga sin escudo: bloquear deja pasar más daño
	r = await setup_pair("caballero", "espada_larga")
	p = r[0]; e = r[1]
	p.want_block = true # (al rival la IA desactivada le suelta el bloqueo)
	await wait(0.2)
	var blocked := await hit_damage(e, p, false)
	check(blocked > 12.0 * 0.2 and blocked < 12.0, "espada larga: bloqueo sin escudo deja pasar ~45 %% (%.1f)" % blocked)
	p.want_block = false
	# Arquero: arranca con arco, flechas +30 %, cuerpo a cuerpo con dagas
	r = await setup_pair("arquero", "arco")
	p = r[0]; e = r[1]
	check(p.loadout == Fighter.Loadout.BOW and p.melee().id == "dagas", "arquero: empieza con arco y su cuerpo a cuerpo son dagas")
	check(is_equal_approx(p.speed_mult(), 1.12) and p.stamina_max == 110.0, "arquero: velocidad x1.12, estamina 110")
	# Paladín: se cura tras 3 s sin recibir golpes
	r = await setup_pair("paladin", "espada_escudo")
	p = r[0]; e = r[1]
	p.health = 60.0
	p._since_hit = 0.0
	await wait(2.0)
	check(p.health == 60.0, "Luz sanadora: nada antes de 3 s")
	await wait(2.0)
	check(p.health > 60.5 and p.health < 64.0, "Luz sanadora: ~2 vida/s después (%.1f)" % p.health)
	check(p.blocked_hit_cost(12.0, e) < e.blocked_hit_cost(12.0, p), "paladín: bloquear le cuesta menos aguante")
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
