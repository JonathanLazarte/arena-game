extends SceneTree
## Ronda 31: aturdimiento acumulado (3 niveles), súper-armadura, habilidades de jefe, disparo cargado y calibración.
## godot --headless --path . -s res://tests/test_round31.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _fresh(f: Fighter) -> void:
	f.health = f.max_health
	f.exhausted = 0.0
	f.stamina = f.stamina_max
	f._cancel_attack()
	f.stun = 0.0
	f.down_t = 0.0
	f.stagger_t = 0.0
	f.stun_immune_t = 0.0
	f.invuln = 0.0
	f._reset_stun_meter()

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round31.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	# --- Calibración ---
	var a99 := Attributes.start_for("caballero")
	a99["destreza"] = 99
	var hi := Attributes.derived("caballero", a99)
	var lo := Attributes.derived("caballero", Attributes.start_for("caballero"))
	check(absf(lo["vel"] - 1.0) < 0.001 and hi["vel"] > 1.16 and hi["vel"] <= 1.25, "tope de velocidad de ataque > +16 %% (%.3f, tope 1,25)" % hi["vel"])
	var g_early := Attributes.curve("velocidad", 20) - Attributes.curve("velocidad", 19)
	var g_late := Attributes.curve("velocidad", 55) - Attributes.curve("velocidad", 54)
	check(g_early > g_late * 2.0, "velocidad con rendimientos decrecientes (%.4f → %.4f)" % [g_early, g_late])
	var esc := Attributes.curve("escala", 20) - Attributes.curve("escala", 19)
	check(g_early >= esc * 0.3 and g_early <= esc, "punto de DES (vel %.3f) equilibrado con FUE (daño %.3f)" % [g_early, esc])
	# --- Reglas ---
	check(StunRules.level_for(0.5) == 0 and StunRules.level_for(1.0) == 1 and StunRules.level_for(1.7) == 2 and StunRules.level_for(2.5) == 3, "3 niveles por umbral")
	check(StunRules.str_force(30) > StunRules.str_force(10) and StunRules.str_force(60) - StunRules.str_force(50) < StunRules.str_force(30) - StunRules.str_force(20), "fuerza por Fuerza con rendimientos decrecientes")
	var codex_ok := true
	for id: String in BossAbilities.ORDER:
		var d := BossAbilities.def(id)
		codex_ok = codex_ok and BossAbilities.codex(id).length() > 40 and d.has("cost_type") and d.has("resist") and d.has("tele")
	check(codex_ok and BossAbilities.ORDER.size() == 6, "6 habilidades con coste, resistencia, aviso y ficha de enciclopedia")
	check(gs.boss_abilities() == ["estocada"], "por defecto: estocada")
	check(gs.toggle_boss_ability("rafaga") and gs.toggle_boss_ability("carga_area") and not gs.toggle_boss_ability("salto_caida"), "máx. 3 equipadas")
	gs.save_loadout()
	gs.char_boss = {}
	gs.load_loadout()
	check(gs.boss_abilities().size() == 3 and "rafaga" in gs.boss_abilities(), "se guardan (v%d)" % gs.SAVE_VERSION)
	# --- Arena ---
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
	check(p.boss_ids.size() == 3 and e.boss_ids.size() == 3, "jugador con lo equipado y rival con 3 al azar")
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -2)
	_fresh(e)
	var r := e.effective_robustness()
	check(e.add_stun_force(r * 10.0) == 0 and e.stun <= 0.0, "ningún golpe aturde solo (robustez %.0f)" % r)
	check(e.add_stun_force(r * 0.2) == 1 and e.staggers == 1, "acumulado → tambaleo")
	e._stagger_roll_cancel()
	check(e.stun <= 0.0, "rodar sale del tambaleo")
	check(e.add_stun_force(r * 0.7) == 2, "más fuerza en la ventana → aturdido")
	e.stun = 0.0
	e.add_stun_force(r * 0.95)
	check(e.knockdowns == 1 and e.is_knocked_down() and e.stun_immune_t > 0.0, "tercer nivel → derribo con inmunidad")
	check(e.add_stun_force(r * 5.0) == 0, "inmune al aturdimiento en el suelo/levantándose")
	e.invuln = 0.0
	var hp := e.health
	e.take_hit(10.0, p, "aoe")
	check(hp - e.health > 0.0, "pero sí recibe daño (%.1f, x%.2f)" % [hp - e.health, StunRules.GETUP_DMG_MULT])
	_fresh(e)
	e.add_stun_force(r * 0.5)
	await create_timer(StunRules.WINDOW + 0.3).timeout
	check(e.stun_acc == 0.0 and e.stun_level_reached == 0, "al cerrar la ventana se recupera del todo")
	_fresh(e)
	e.stamina = e.stamina_max
	var base_r := e.effective_robustness()
	var started := e.attack_heavy()
	await physics_frame
	check(started and e.effective_robustness() > base_r * 1.5, "súper-armadura en la anticipación del fuerte (%.0f → %.0f)" % [base_r, e.effective_robustness()])
	await create_timer(1.8).timeout
	# Costes
	p.set_boss_abilities(["salto_caida", "escudo_mana", "carga_area"])
	_fresh(p)
	p.health = 10.0
	check(not p.can_use_boss("salto_caida"), "coste de vida: no se puede si te deja a 0")
	p.health = p.max_health
	p.energy = 0.0
	check(not p.can_use_boss("escudo_mana"), "coste de maná: sin Energía no se puede")
	p.energy = p.energy_max
	check(p.boss_skill("escudo_mana"), "escudo de maná")
	await create_timer(0.3).timeout
	hp = p.health
	p.take_hit(30.0, e, "melee")
	check(p.health == hp and p.ab_immune(), "escudo: invulnerable total")
	await create_timer(1.6).timeout
	check(p.ab_id == "", "el escudo termina a los 1,5 s")
	_fresh(p)
	p.energy = p.energy_max
	check(p.boss_skill("carga_area"), "carga en área")
	check(p.current_stun_resist() >= 3.0, "carga: robustez muy alta")
	var rr := p.effective_robustness()
	for i in 4:
		p.add_stun_force(rr * 0.9)
	check(p.ab_id == "" and p.ab_interrupted >= 1, "carga: un combo fuerte la interrumpe")
	await create_timer(2.0).timeout
	p.boss_sel = 0
	check(p.cycle_boss() == "escudo_mana", "N cambia la habilidad seleccionada")
	# Salto con caída: cuesta vida y aterriza en la marca
	_fresh(p)
	p.health = p.max_health
	e.global_position = Vector3(0, 0, -8)
	var hp0 := p.health
	check(p.boss_skill("salto_caida") and p.health < hp0, "salto: paga vida")
	await create_timer(2.6).timeout
	check(p.ab_id == "" and p.global_position.distance_to(Vector3(0, 0, -8)) < 2.0, "salto: cae sobre la marca fijada")
	# Estocada: sigue al que camina
	_fresh(p)
	_fresh(e)
	p.set_boss_abilities(["estocada", "rafaga", "combo_falso"])
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -8)
	p.face_target = e
	p.stamina = p.stamina_max
	var eh := e.health
	check(p.boss_skill("estocada"), "estocada")
	for i in 150:
		e.move_input = Vector3(1, 0, 0) # camina de lado
		e.want_sprint = false
		await physics_frame
	e.move_input = Vector3.ZERO
	check(e.health < eh, "estocada: caminar de lado no la esquiva")
	await create_timer(1.5).timeout
	# Ráfaga: caminando te alcanza
	_fresh(p)
	_fresh(e)
	p.energy = p.energy_max
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -10)
	eh = e.health
	check(p.boss_skill("rafaga"), "ráfaga")
	for i in 120:
		e.move_input = Vector3(1, 0, 0) * 0.5
		await physics_frame
	check(e.health < eh, "ráfaga: caminando te alcanza (%.0f daño)" % (eh - e.health))
	e.move_input = Vector3.ZERO
	await create_timer(1.0).timeout
	# Disparo cargado (sin el controlador del jugador, que fija want_shot_hold con el botón)
	arena.controller.set_physics_process(false)
	_fresh(p)
	if p.loadout != Fighter.Loadout.BOW:
		p.swap_loadout()
		await create_timer(0.8).timeout
	var n0 := p.charged_shots
	p.stamina = p.stamina_max
	p.want_shot_hold = false
	p.shoot()
	await create_timer(1.2).timeout
	check(p.charged_shots == n0 and p.shots_fired > 0, "toque = disparo normal")
	p.stamina = p.stamina_max
	p.want_shot_hold = true
	p.shoot()
	await create_timer(ranged_draw(p) + 0.3).timeout
	p.want_shot_hold = false
	await create_timer(1.0).timeout
	check(p.charged_shots == n0, "soltar antes de cargar = disparo normal")
	p.stamina = p.stamina_max
	p.want_shot_hold = true
	p.shoot()
	await create_timer(ranged_draw(p) + Fighter.CHARGE_HOLD + 0.4).timeout
	p.want_shot_hold = false
	await create_timer(0.3).timeout # ronda 32: sale al soltar
	check(p.charged_shots == n0 + 1, "mantener = disparo cargado (%s)" % p.charged_shot_kind())
	print("RESULT: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)

func ranged_draw(p: Fighter) -> float:
	return p.ranged().fire_draw / p.attr_speed()
