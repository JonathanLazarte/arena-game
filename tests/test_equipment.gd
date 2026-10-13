extends SceneTree
## Ronda 19: Ataque/Defensa/Absorción, carga de equipo y voltereta, tienda, equipar desde
## la ficha, lobby sin pestaña al entrar y migración v5 -> v6.
## godot --headless --path . -s res://tests/test_equipment.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var cab := Catalog.character("caballero")
	# --- Datos ---
	check(Catalog.armors().size() == 36, "36 piezas (9 conjuntos x 4)")
	for cid: String in Attributes.START:
		var st := Catalog.starter_armor(cid)
		check(st.size() == 4, "%s: equipo inicial de 4 piezas" % cid)
		var ref := EquipStats.role_reference(Catalog.character(cid))
		check(ref["clase"] == "medio", "%s: el equipo inicial es carga media (%.0f %%)" % [cid, ref["carga"] * 100.0])
	var sale := Catalog.armor_sets_for_sale()
	var classes := sale.map(func(x: Dictionary) -> String: return x["class"])
	check(sale.size() == 4 and "ligero" in classes and "medio" in classes and "pesado" in classes, "conjuntos a la venta ligero/medio/pesado")
	# --- Fórmulas ---
	check(is_equal_approx(EquipStats.defense(1, Attributes.start_for("caballero")), 20.0 + 0.2 * 12 + 0.15 * 12 + 0.15 * 12), "Defensa = 20 + nivel + 0,2·VIT + 0,15·(AGU+FUE)")
	check(EquipStats.defense(10, Attributes.start_for("caballero")) > EquipStats.defense(1, Attributes.start_for("caballero")) + 8.9, "la Defensa sube con el nivel")
	var m1 := EquipStats.defense_mult(10, 30)
	var m2 := EquipStats.defense_mult(30, 30)
	var m3 := EquipStats.defense_mult(1000, 30)
	var m0 := EquipStats.defense_mult(0.5, 30)
	check(m1 < m2 and m2 < m3 and is_equal_approx(m3, 0.9 * (1000.0 / 30.0) / (1000.0 / 30.0 + 0.45)) and is_equal_approx(m0, 0.1), "multiplicador de defensa 10 %%..90 %% creciente (%.2f %.2f %.2f)" % [m1, m2, m3])
	var a := {"pecho": Catalog.armor("bastion_pecho"), "casco": Catalog.armor("bastion_casco")}
	var ab := EquipStats.absorption(a)
	check(is_equal_approx(ab["fisico"], 1.0 - (1.0 - a["pecho"].absorption["fisico"]) * (1.0 - a["casco"].absorption["fisico"])), "absorción multiplicativa (%.3f)" % ab["fisico"])
	var full := EquipStats.absorption(EquipStats.armor_defs(Catalog.starter_armor("caballero")))
	check(absf(full["fisico"] - 0.18) < 0.002, "conjunto completo del Escudero = 18 %% físico (%.3f)" % full["fisico"])
	var ref := EquipStats.role_reference(cab)
	check(is_equal_approx(EquipStats.incoming(12.0, "fisico", ref, ref), 12.0), "nivel 1 con equipo inicial: daño igual que antes")
	var heavy := EquipStats.sheet(cab, 1, Attributes.start_for("caballero"), Catalog.weapon("espada_escudo"), null, EquipStats.armor_defs({"casco": "bastion_casco", "pecho": "bastion_pecho", "guantes": "bastion_guantes", "piernas": "bastion_piernas"}))
	var naked := EquipStats.sheet(cab, 1, Attributes.start_for("caballero"), Catalog.weapon("espada_escudo"), null, EquipStats.armor_defs({}))
	var dh := EquipStats.incoming(12.0, "fisico", heavy, ref)
	var dn := EquipStats.incoming(12.0, "fisico", naked, ref)
	check(dh < 12.0 * 0.86 and dn > 12.0 * 1.15, "más absorción = menos daño (%.1f pesada / %.1f sin armadura)" % [dh, dn])
	check(is_equal_approx(dh, 12.0 * (1.0 - heavy["absorcion"]["fisico"]) / (1.0 - ref["absorcion"]["fisico"])), "daño = ataque × defensa × (1 − absorción), relativo")
	var lv20 := ref.duplicate(true)
	lv20["defensa"] = EquipStats.defense(20, Attributes.start_for("caballero"))
	check(EquipStats.incoming(12.0, "fisico", lv20, ref) < 12.0 * 0.85, "más Defensa = menos daño (%.1f)" % EquipStats.incoming(12.0, "fisico", lv20, ref))
	var fire_ref := EquipStats.incoming(10.0, "fuego", heavy, ref)
	check(fire_ref < 10.0, "el fuego usa la absorción de fuego")
	# AR
	var at := Attributes.start_for("caballero")
	var ar := EquipStats.attack_rating(cab, Catalog.weapon("espada_escudo"), at)
	check(is_equal_approx(ar["base"], 12.0) and is_equal_approx(ar["bonus"], 0.0), "Ataque nivel 1: 12 + 0")
	at["fuerza"] = 30
	var ar2 := EquipStats.attack_rating(cab, Catalog.weapon("espada_escudo"), at)
	check(ar2["bonus"] > 1.5 and is_equal_approx(ar2["total"], 12.0 * Attributes.weapon_mult(Catalog.weapon("espada_escudo"), "caballero", at)), "Ataque = base + bono (%.1f + %.1f)" % [ar2["base"], ar2["bonus"]])
	check(ar2["sagrado"] > 0.0 and ar2["fisico"] < ar2["total"], "la espada con DEV tiene parte sagrada")
	# --- Carga de equipo ---
	check(EquipStats.load_class(0.29) == "ligero" and EquipStats.load_class(0.3) == "medio" and EquipStats.load_class(0.69) == "medio" and EquipStats.load_class(0.7) == "pesado" and EquipStats.load_class(1.0) == "sobrecargado", "umbrales 30/70/100 %")
	check(heavy["clase"] == "pesado", "Bastión en el Caballero de nivel 1 = carga pesada (%.0f %%)" % (heavy["carga"] * 100.0))
	# --- Voltereta en combate según la carga ---
	gs.save_path = "user://test_equipment.cfg"
	gs.reset_defaults()
	gs.from_lobby = true
	gs.random_rival = false
	gs.character_id = "caballero"
	gs.weapon_id = "espada_escudo"
	gs.eikon_id = "fenix"
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.time_left = 1.0e9
	var p := arena.player
	await create_timer(0.6).timeout
	var res := {}
	for cfg: Array in [["ligero", {"casco": "viento_casco"}], ["medio", Catalog.starter_armor("caballero")],
			["pesado", {"casco": "bastion_casco", "pecho": "bastion_pecho", "guantes": "bastion_guantes", "piernas": "bastion_piernas"}],
			["sobrecargado", {"casco": "bastion_casco", "pecho": "bastion_pecho", "guantes": "bastion_guantes", "piernas": "bastion_piernas", "_extra": ""}]]:
		p.set_equipment(1, cfg[1], Catalog.weapon("ballesta") if cfg[0] == "sobrecargado" else null)
		if cfg[0] == "sobrecargado":
			var weak := Attributes.start_for("caballero")
			weak["aguante"] = 6
			p.set_attributes(weak)
			p.weapon = Catalog.weapon("hacha_2m") # más peso: 32 + 9 > 39,6
		p._apply_character()
		p.global_position = Vector3(0, 0, 6)
		p.stamina = p.stamina_max
		p.move_input = Vector3.FORWARD
		await create_timer(0.3).timeout
		p.move_input = Vector3.ZERO
		await create_timer(0.3).timeout
		var x0 := p.global_position
		p.move_input = Vector3.FORWARD
		p.dash()
		var t := 0
		while p.is_rolling() and t < 120:
			await physics_frame
			t += 1
		p.move_input = Vector3.ZERO
		res[cfg[0]] = {"d": MeshUtil.flat(p.global_position - x0).length(), "t": t, "if": p.roll_iframe_end() - Fighter.ROLL_STARTUP, "cls": p.eq["clase"]}
		await create_timer(0.3).timeout
	print("voltereta: ", res)
	check(res["ligero"]["cls"] == "ligero" and res["medio"]["cls"] == "medio" and res["pesado"]["cls"] == "pesado" and res["sobrecargado"]["cls"] == "sobrecargado", "clases de carga en combate")
	check(res["ligero"]["d"] > res["medio"]["d"] * 1.08, "ligera: rueda más lejos (%.2f vs %.2f m)" % [res["ligero"]["d"], res["medio"]["d"]])
	check(is_equal_approx(res["ligero"]["if"], res["medio"]["if"]), "ligera y media: mismos i-frames")
	check(res["pesado"]["d"] < res["medio"]["d"] * 0.9 and res["pesado"]["t"] > res["medio"]["t"] + 3 and res["pesado"]["if"] < res["medio"]["if"], "pesada: más corta, más lenta y un frame menos de invulnerabilidad")
	check(res["sobrecargado"]["if"] <= 0.001 and res["sobrecargado"]["d"] < res["medio"]["d"] * 0.5, "sobrecargado: sin voltereta real (tropiezo)")
	check(p.roll_mod()["regen"] < 1.0, "sobrecargado: regenera menos aguante")
	p.set_attributes({})
	p.weapon = Catalog.weapon("espada_escudo")
	p.set_equipment(1, Catalog.starter_armor("caballero"))
	p._apply_character()
	# Daño real en combate: más armadura, menos daño
	var e := arena.enemy
	p.poise_max = 1e6
	p.poise = 1e6
	var h0 := p.health
	p.take_hit(12.0, e, "melee")
	var d_med := h0 - p.health
	p.stun = 0.0
	p.set_equipment(1, {"casco": "bastion_casco", "pecho": "bastion_pecho", "guantes": "bastion_guantes", "piernas": "bastion_piernas"})
	p._apply_character()
	p.poise_max = 1e6
	p.poise = 1e6
	h0 = p.health
	p.take_hit(12.0, e, "melee")
	check(is_equal_approx(d_med, 12.0) and h0 - p.health < 11.0, "combate: equipo inicial 12 de daño; Bastión %.1f" % (h0 - p.health))
	# --- Tienda ---
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	check(gs.owned_armor.size() == 4 and gs.armor_eq["pecho"] == "escudero_pecho", "personaje nuevo: equipo inicial")
	gs.oro = 5000
	check(gs.buy_set("bastion") == "nivel", "Bastión pide nivel 6")
	gs.account_xp = Progression.xp_at_level(6)
	var o: int = gs.oro
	var pr: int = gs.set_price("bastion")
	check(gs.buy_set("bastion") == "ok" and gs.oro == o - pr and "bastion_pecho" in gs.owned_armor and gs.armor_eq["pecho"] == "escudero_pecho", "comprar conjunto: cobra y no lo equipa solo")
	check(gs.buy_set("bastion") == "ya", "no se compra dos veces")
	gs.oro = 0
	check(gs.buy("armor", "viento_casco") == "oro", "sin oro no se compra una pieza")
	gs.oro = 5000
	check(gs.buy("armor", "viento_casco") == "ok" and gs.set_price("viento") == Catalog.armor_sets_for_sale()[0]["price"] - Catalog.armor("viento_casco").price, "comprar pieza suelta")
	# --- Equipar desde la ranura (ficha) ---
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	check(lobby.tab == "" and not lobby.right_panel.visible and not lobby.sheet.visible, "lobby: ninguna pestaña preseleccionada al entrar")
	var pressed_any := false
	for t: String in lobby.tab_buttons:
		pressed_any = pressed_any or (lobby.tab_buttons[t] as Button).button_pressed
	check(not pressed_any, "ningún botón de pestaña marcado")
	lobby.set_tab("Personaje")
	await process_frame
	var sh: CharSheet = lobby.sheet
	sh.open_picker("pecho")
	var opts: Array = sh.options("pecho")
	check(opts.has("bastion_pecho") and opts.has("escudero_pecho") and opts.has("") and not opts.has("vigia_pecho"), "selector: solo lo que tienes (%s)" % [opts])
	sh.select_option("bastion_pecho")
	check(sh.picker_diff.text.contains("#9fe08a") and sh.picker_diff.text.contains("Absorción Físico"), "comparación con verde/rojo")
	sh.confirm_pick()
	check(gs.armor_eq["pecho"] == "bastion_pecho" and not sh.picker.visible, "equipar desde la ranura")
	check(not gs.equip_armor("pecho", "vigia_pecho") and not gs.equip_armor("casco", "bastion_pecho"), "no se equipa lo que no tienes ni en otra ranura")
	check(sh.equip("pecho", "") and gs.armor_eq["pecho"] == "", "quitar la pieza")
	gs.owned_weapons.append("lanza")
	check(sh.options("arma").has("lanza") and sh.equip("arma", "lanza") and gs.weapon_id == "lanza", "arma principal desde la ranura")
	check(sh.options("arma2").size() == 1, "sin armas a distancia propias: solo recambio")
	check((sh.slot_buttons["arma"] as Button).text.contains("Lanza"), "la ranura muestra lo equipado")
	gs.load_loadout()
	check(gs.weapon_id == "lanza" and gs.armor_eq["pecho"] == "", "el equipo se guarda")
	# --- Migración v5 -> v6 ---
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 5)
	cfg.set_value("meta", "active_slot", 0)
	cfg.set_value("slot_0", "character_id", "paladin")
	cfg.set_value("slot_0", "weapon_id", "espada_escudo")
	cfg.set_value("slot_0", "xp", Progression.xp_at_level(4))
	cfg.set_value("slot_0", "skills", [])
	cfg.set_value("slot_0", "attrs", Attributes.auto_allocate("paladin", 4))
	cfg.set_value("progreso", "first_run_done", true)
	cfg.set_value("progreso", "account_xp", 300)
	cfg.set_value("progreso", "owned_weapons", ["espada_escudo"])
	cfg.save("user://test_equipment_v5.cfg")
	gs.save_path = "user://test_equipment_v5.cfg"
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.migrated_from == 5 and gs.armor_migrated, "migra v5 -> v6")
	check(gs.armor_eq.size() == 4 and gs.armor_eq["casco"] == "novicio_casco" and gs.owned_armor.size() == 4, "regala y equipa el equipo inicial del Paladín")
	check(Attributes.total(gs.char_attrs()) == 80 + 6, "conserva los atributos")
	var c6 := ConfigFile.new()
	c6.load("user://test_equipment_v5.cfg")
	check(int(c6.get_value("meta", "version", 0)) >= 6 and c6.has_section_key("slot_0", "armor"), "se reescribe como v6 o posterior")
	# --- Rival ---
	check(EquipStats.rival_armor("paladin", 1) == Catalog.starter_armor("paladin") and EquipStats.rival_armor("paladin", 8)["pecho"] == "bastion_pecho" and EquipStats.rival_armor("arquero", 4)["pecho"] == "viento_pecho", "rival: armadura de su rol según nivel")
	for f: String in ["user://test_equipment.cfg", "user://test_equipment_v5.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(1 if fails > 0 else 0)
