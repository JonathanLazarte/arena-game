extends SceneTree
## Ronda 20: estados alterados (Sangrado, Veneno, Congelación) con acumulación, decaimiento,
## resistencias (Robustez / Inmunidad), fuentes (dagas, Lobo de Hielo, infusiones) y HUD.
## godot --headless --path . -s res://tests/test_status.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	await process_frame
	# --- Unidad ---
	var s := StatusFx.new()
	check(not s.add("sangrado", 50.0, 100.0) and is_equal_approx(s.buildup["sangrado"], 50.0), "acumula sin estallar bajo el umbral")
	s.tick(1.0)
	check(is_equal_approx(s.buildup["sangrado"], 50.0), "no decae antes de %.1f s" % StatusFx.DECAY_DELAY)
	s.tick(1.0)
	s.tick(1.0)
	check(s.buildup["sangrado"] < 50.0 - StatusFx.DECAY * 0.9, "decae tras un rato sin golpes (%.1f)" % s.buildup["sangrado"])
	check(s.add("sangrado", 100.0, 100.0) and is_equal_approx(s.buildup["sangrado"], 0.0) and s.procs["sangrado"] == 1, "al llenarse estalla y vuelve a 0")
	check(not s.add("sangrado", 200.0, 100.0), "breve bloqueo tras el estallido")
	check(s.add("veneno", 120.0, 100.0) and s.poison_t > 0.0, "veneno activa el daño continuo")
	var pd := 0.0
	for i in 10:
		pd += s.tick(0.1)
	check(is_equal_approx(pd, StatusFx.POISON_DPS), "veneno: %.1f de daño por segundo" % pd)
	check(s.add("congelacion", 120.0, 100.0) and is_equal_approx(s.damage_taken_mult(), StatusFx.FROST_TAKEN) and is_equal_approx(s.regen_mult(), StatusFx.FROST_REGEN), "congelación: +daño recibido y −regeneración")
	check(StatusFx.threshold_for(80.0) > StatusFx.threshold_for(50.0), "más resistencia = más umbral")
	check(Catalog.weapon("dagas").status.get("sangrado", 0.0) > 0.0, "las dagas causan sangrado")
	# --- Combate real ---
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_status.cfg"
	gs.reset_defaults()
	gs.from_lobby = true
	gs.random_rival = false
	gs.character_id = "asesino"
	gs.weapon_id = "dagas"
	gs.eikon_id = "lobo"
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.time_left = 1.0e9
	await create_timer(3.2).timeout # intro de la ronda
	var p := arena.player
	var e := arena.enemy
	e.poise_max = 1e6
	e.poise = 1e6
	var thr := e.status_threshold("sangrado")
	check(thr > 70.0 and thr < 130.0, "umbral de sangrado del rival %.0f (10 + Robustez)" % thr)
	var per: float = p.melee().status["sangrado"]
	var hits := 0
	var pr := [false]
	e.status_proc.connect(func(k: String) -> void: pr[0] = pr[0] or k == "sangrado")
	var hp_before := 0.0
	var hp_after := 0.0
	while not pr[0] and hits < 20:
		hp_before = e.health
		e.take_hit(1.0, p, "melee")
		hp_after = e.health
		e.stun = 0.0
		hits += 1
	var burst := hp_before - hp_after
	var expect := e.max_health * StatusFx.BLEED_PCT + StatusFx.BLEED_FLAT
	check(pr[0] and hits == ceili(thr / per), "sangrado tras %d golpes de dagas (%.0f por golpe)" % [hits, per])
	check(burst > expect * 0.9, "estallido de sangrado = 12 %% vida máx + 6 (%.1f)" % burst)
	await process_frame
	check(arena.hud.status_e["sangrado"].visible == false or e.status_fraction("sangrado") > 0.0, "barra del rival coherente tras el estallido")
	e.take_hit(1.0, p, "melee")
	e.stun = 0.0
	await create_timer(StatusFx.PROC_LOCK + 0.1).timeout # tras el bloqueo
	e.take_hit(1.0, p, "melee")
	e.stun = 0.0
	await create_timer(0.1).timeout
	print("hud ", arena.hud.status_e["sangrado"].visible, arena.hud.status_over["sangrado"].visible, arena.hud.status_over_box.visible)
	check(arena.hud.status_e["sangrado"].visible and arena.hud.status_over["sangrado"].visible, "barra de acumulación en el HUD y sobre el rival")
	var f0 := e.status_fraction("sangrado")
	await create_timer(StatusFx.DECAY_DELAY + 1.0).timeout
	check(e.status_fraction("sangrado") < f0, "la barra decae (%.2f -> %.2f)" % [f0, e.status_fraction("sangrado")])
	# Robustez: más armadura pesada = más golpes
	var thr_h := 0.0
	e.set_equipment(1, {"casco": "bastion_casco", "pecho": "bastion_pecho", "guantes": "bastion_guantes", "piernas": "bastion_piernas"})
	e._apply_character()
	thr_h = e.status_threshold("sangrado")
	check(thr_h > thr, "Bastión sube la Robustez: umbral %.0f > %.0f" % [thr_h, thr])
	var tough := Attributes.start_for(e.character.id)
	tough["aguante"] = 40
	e.set_attributes(tough)
	e._apply_character()
	check(e.status_threshold("sangrado") > thr_h, "y el Aguante también (%.0f)" % e.status_threshold("sangrado"))
	e.set_attributes({})
	e.set_equipment(1, Catalog.starter_armor(e.character.id))
	e._apply_character()
	# Veneno (infusión Venenosa)
	p.weapon = Smithing.effective(Catalog.weapon("dagas"), 0, "venenoso")
	var vthr := e.status_threshold("veneno")
	var n := 0
	while e.status_fx.poison_t <= 0.0 and n < 30:
		e.take_hit(0.1, p, "melee")
		e.stun = 0.0
		n += 1
	var h1 := e.health
	await create_timer(2.0).timeout
	check(e.status_fx.poison_t > 0.0 and h1 - e.health > StatusFx.POISON_DPS * 1.6, "veneno: daño continuo (%.1f en 2 s, umbral %.0f por Inmunidad)" % [h1 - e.health, vthr])
	check(arena.hud.status_e["veneno"].visible and "s" in (arena.hud.status_e["veneno"].get_child(0) as Label).text, "HUD: veneno activo con su tiempo")
	# Congelación: Lobo de Hielo (golpe de eikon)
	p.weapon = Catalog.weapon("dagas")
	var fthr := e.status_threshold("congelacion")
	var k := 0
	while e.status_fx.frost_t <= 0.0 and k < 20:
		e.take_hit(0.1, p, "eikon")
		e.stun = 0.0
		k += 1
	check(e.status_fx.frost_t > 0.0 and k == ceili(fthr / Fighter.LOBO_FROST), "Lobo de Hielo congela (%d golpes)" % k)
	var a0 := e.health
	e.take_hit(10.0, p, "arrow")
	var with_frost := a0 - e.health
	e.stun = 0.0
	e.status_fx.frost_t = 0.0
	var a1 := e.health
	e.take_hit(10.0, p, "arrow")
	var no_frost := a1 - e.health
	e.stun = 0.0
	check(with_frost > no_frost * 1.1, "congelado recibe más daño (%.1f vs %.1f)" % [with_frost, no_frost])
	# Arma Gélida también congela
	p.weapon = Smithing.effective(Catalog.weapon("dagas"), 3, "gelido")
	check(p.melee().status.get("congelacion", 0.0) > 20.0, "infusión Gélida: congelación por golpe (%.1f)" % p.melee().status.get("congelacion", 0.0))
	# Regeneración de aguante con congelación
	e.status_fx.frost_t = 10.0
	e.stamina = 10.0
	e._since_spend = 5.0
	await create_timer(0.5).timeout
	var reg_f := e.stamina - 10.0
	e.status_fx.frost_t = 0.0
	e.stamina = 10.0
	e._since_spend = 5.0
	await create_timer(0.5).timeout
	var reg_n := e.stamina - 10.0
	check(reg_f < reg_n * 0.8, "congelado regenera menos aguante (%.1f vs %.1f)" % [reg_f, reg_n])
	# Ronda nueva: se limpian
	e.status_fx.poison_t = 5.0
	e.reset_for_round(Vector3(0, 0, -6), Vector3.BACK)
	check(e.status_fx.poison_t == 0.0 and e.status_fraction("sangrado") == 0.0, "los estados se limpian entre rondas")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
