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
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.sim_ai.enabled = false
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
	await wait(0.1)
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -1.5)
	p.facing = Vector3(0, 0, -1)
	e.facing = Vector3(0, 0, 1)
	return [p, e]

## Fase 8: el daño se resuelve en la sim con los parámetros horneados de los dos Fighter.
func hit_damage(p: Fighter, e: Fighter, heavy: bool) -> float:
	var P := SimParams.bake(p, e)
	var S := FightSim
	var s := S.initial(P, 1, false)
	s[S.X] = 0
	s[S.F_FIELDS + S.X] = 1500000
	var blk: int = S.IN_BLOCK if e.want_block else 0
	for t in 120:
		var a: int = S.IN_ATK if (t < 30 if heavy else t == 0) else 0
		S.step(s, P, a, blk)
	return float(int(P[1]["hp"]) - s[S.F_FIELDS + S.HP]) / 1000.0

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
	check(p.max_combo() == 3 and not p.has_shield() and p.poise_max == 80.0 and p.max_health >= 120.0, "berserker: combo 3, sin escudo, poise 80, vida 120")
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
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Dagas: rápidas y de corto alcance
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
	check(p.ranged() != null and p.ranged().ranged, "arquero: lleva arco (el arma principal por defecto es cuerpo a cuerpo, ver test_loadout)")
	check(is_equal_approx(p.speed_mult(), 1.12) and p.stamina_max == 110.0, "arquero: velocidad x1.12, estamina 110")
	# Paladín: se cura tras 3 s sin recibir golpes
	r = await setup_pair("paladin", "espada_escudo")
	p = r[0]; e = r[1]
	# fase 8: la curación pasiva vive en la sim (heal_tick por tick a 60 Hz tras el retardo)
	var ht := float(SimParams.bake(p, e)[0]["heal_tick"]) * 60.0 / 1000.0
	check(ht > 1.5 and ht < 2.5, "Luz sanadora: ~2 vida/s horneado para la sim (%.2f)" % ht)
	check(p.blocked_hit_cost(12.0, e) < e.blocked_hit_cost(12.0, p), "paladín: bloquear le cuesta menos aguante")
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
