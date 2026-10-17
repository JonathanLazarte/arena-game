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
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Combate real ---
	var gs := root.get_node("GameState")
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	var p := arena.player
	var e := arena.enemy
	var thr := e.status_threshold("sangrado")
	var hp_before := 0.0
	var hp_after := 0.0
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
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Veneno (infusión Venenosa)
	var vthr := e.status_threshold("veneno")
	var n := 0
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Congelación: Lobo de Hielo (golpe de eikon)
	var fthr := e.status_threshold("congelacion")
	var k := 0
	# Arma Gélida también congela
	p.weapon = Smithing.effective(Catalog.weapon("dagas"), 3, "gelido")
	check(p.melee().status.get("congelacion", 0.0) > 20.0, "infusión Gélida: congelación por golpe (%.1f)" % p.melee().status.get("congelacion", 0.0))
	# [fase 8] retirado: la regeneración de aguante (y su penalización por congelación) corre en la sim
	# Ronda nueva: se limpian
	e.status_fx.poison_t = 5.0
	e.reset_for_round(Vector3(0, 0, -6), Vector3.BACK)
	check(e.status_fx.poison_t == 0.0 and e.status_fraction("sangrado") == 0.0, "los estados se limpian entre rondas")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
