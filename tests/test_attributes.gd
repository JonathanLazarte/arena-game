extends SceneTree
## Ronda 18: atributos (fórmulas y umbrales blandos, escalado y requisitos, redistribución,
## migración del guardado v4 -> v5, rival y efectos en combate).
## godot --headless --path . -s res://tests/test_attributes.gd

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
	# --- Repartos iniciales ---
	for cid: String in Attributes.START:
		var s: Dictionary = Attributes.START[cid]
		check(Attributes.total(s) == 80 and s.size() == 8, "%s: 8 atributos, suma 80" % cid)
		var d := Attributes.derived(cid, s)
		check(d["vida"] == 0.0 and d["estamina"] == 0.0 and d["vel"] == 1.0 and d["iframes"] == 0 and d["stun_taken"] == 1.0,
			"%s: a nivel 1 sin bonos (equilibrio igual que antes)" % cid)
		for wid in Catalog.character(cid).weapons:
			var w := Catalog.weapon(wid)
			check(Attributes.unmet(w, s).is_empty() and is_equal_approx(Attributes.weapon_mult(w, cid, s), 1.0),
				"%s cumple requisitos de %s y daño x1.0" % [cid, wid])
	check(Attributes.START["berserker"]["fuerza"] == 16 and Attributes.START["asesino"]["destreza"] == 16 and Attributes.START["arquero"]["destreza"] == 16, "repartos por rol (Fuerza/Destreza)")
	check(Attributes.START["paladin"]["devocion"] >= 14 and Attributes.START["paladin"]["vitalidad"] >= 13, "Paladín: Devoción y Vitalidad altas")
	# --- Curvas: rendimientos decrecientes ---
	var g1 := Attributes.curve("vida", 25) - Attributes.curve("vida", 15)
	var g2 := Attributes.curve("vida", 40) - Attributes.curve("vida", 30)
	var g3 := Attributes.curve("vida", 60) - Attributes.curve("vida", 50)
	check(is_equal_approx(g1, 40.0) and g2 < g1 and g3 < g2, "Vitalidad: 4/pt hasta 25, luego menos (%.0f > %.0f > %.0f)" % [g1, g2, g3])
	check(is_equal_approx(Attributes.curve("vida", 30), 25 * 4.0 + 5 * 2.0), "fórmula por tramos exacta (vida a 30 = 110)")
	for nm: String in Attributes.CURVES:
		var a := Attributes.curve(nm, 20) - Attributes.curve(nm, 10)
		var b := Attributes.curve(nm, 60) - Attributes.curve(nm, 50)
		check(b < a, "umbral blando en %s" % nm)
	var hi := Attributes.derived("caballero", Attributes.auto_allocate("caballero", 30))
	var maxed := Attributes.START["caballero"].duplicate()
	maxed["destreza"] = 60
	maxed["aguante"] = 60
	maxed["fuerza"] = 60
	var mx := Attributes.derived("caballero", maxed)
	check(mx["vel"] <= 1.25 and mx["iframes"] <= 2 and mx["stun_taken"] >= 0.6 and mx["stun_dealt"] <= 1.35, "topes de seguridad (vel %.2f, i-frames %d, robustez %.2f)" % [mx["vel"], mx["iframes"], mx["stun_taken"]])
	check(mx["iframes"] >= 1, "Destreza alta: +1 a +2 frames de invulnerabilidad (%d)" % mx["iframes"])
	check(hi["vida"] > 0.0, "nivel 30 auto: más vida (%.0f)" % hi["vida"])
	# --- Escalado y requisitos ---
	var axe := Catalog.weapon("hacha_2m")
	var dag := Catalog.weapon("dagas")
	var bow := Catalog.weapon("arco")
	check(Attributes.grade(axe.scaling["fuerza"]) == "A" and Attributes.grade(dag.scaling["destreza"]) == "S" and Attributes.grade(bow.scaling["destreza"]) == "B", "letras: hacha FUE A, dagas DES S, arco DES B")
	check(Attributes.grade(Catalog.weapon("ballesta").scaling["destreza"]) == "C" and Attributes.grade(0.1) == "E" and Attributes.grade(0.3) == "D", "letras C/D/E")
	var b30 := Attributes.START["berserker"].duplicate()
	b30["fuerza"] = 30
	var b30d := b30.duplicate()
	b30d["fuerza"] = 16
	b30d["destreza"] = 30
	check(Attributes.weapon_mult(axe, "berserker", b30) > 1.15, "hacha escala con Fuerza (x%.2f)" % Attributes.weapon_mult(axe, "berserker", b30))
	check(Attributes.weapon_mult(axe, "berserker", b30d) < Attributes.weapon_mult(axe, "berserker", b30), "hacha casi no escala con Destreza")
	var a30 := Attributes.START["arquero"].duplicate()
	a30["destreza"] = 30
	check(Attributes.weapon_mult(bow, "arquero", a30) > 1.1 and Attributes.weapon_mult(Catalog.weapon("ballesta"), "arquero", a30) > 1.05, "arco y ballesta escalan con Destreza")
	var weak := Attributes.START["paladin"].duplicate()
	weak["fuerza"] = 9
	check(Attributes.unmet(axe, weak) == ["fuerza"] and is_equal_approx(Attributes.weapon_mult(axe, "paladin", weak), Attributes.weapon_mult(axe, "paladin", weak, false) * 0.7), "bajo requisito: −30 % y aviso")
	check(Attributes.scaling_text(axe).contains("FUE A") and Attributes.req_text(axe) == "FUE 11", "texto de escalado y requisitos")
	# --- Puntos, reparto, redistribución ---
	gs.save_path = "user://test_attrs.cfg"
	gs.reset_defaults()
	gs.choose_first_character("berserker")
	gs.char_xp["berserker"] = Progression.xp_at_level(6)
	check(gs.char_level() == 6 and gs.attr_points() == 10, "nivel 6: 10 puntos de atributo (%d)" % gs.attr_points())
	check(gs.skill_points() == 5, "el árbol de habilidades conserva sus puntos (5)")
	var a: Dictionary = gs.char_attrs().duplicate()
	a["fuerza"] += 6
	a["vitalidad"] += 4
	check(gs.set_attrs(a) == "ok" and gs.attr_points() == 0, "confirmar reparto")
	var bad := a.duplicate()
	bad["aguante"] += 1
	check(gs.set_attrs(bad) == "invalido", "no se gastan puntos que no hay")
	var under := a.duplicate()
	under["destreza"] = 5
	check(gs.set_attrs(under) == "invalido", "no se baja del reparto inicial")
	gs.respec()
	check(gs.attr_points() == 10 and gs.char_attrs() == Attributes.start_for("berserker"), "redistribuir: vuelve al inicio y devuelve los puntos (gratis)")
	gs.set_attrs(a)
	gs.load_loadout()
	check(gs.char_attrs()["fuerza"] == 22 and gs.migrated_from == 0, "guardado v5: los atributos se conservan")
	# --- Migración v4 -> v5 ---
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 4)
	cfg.set_value("meta", "active_slot", 0)
	cfg.set_value("slot_0", "character_id", "asesino")
	cfg.set_value("slot_0", "weapon_id", "dagas")
	cfg.set_value("slot_0", "xp", Progression.xp_at_level(8))
	cfg.set_value("slot_0", "skills", ["ase_sigilo"])
	cfg.set_value("progreso", "first_run_done", true)
	cfg.set_value("progreso", "account_xp", 500)
	cfg.set_value("progreso", "owned_weapons", ["dagas"])
	cfg.save("user://test_attrs_v4.cfg")
	gs.save_path = "user://test_attrs_v4.cfg"
	gs.reset_defaults()
	gs.load_loadout()
	var ma: Dictionary = gs.char_attrs()
	check(gs.migrated_from == 4 and gs.attr_migrated, "migra v4 -> v5")
	check(gs.character_id == "asesino" and gs.char_level() == 8 and gs.char_skills() == ["ase_sigilo"], "conserva personaje, nivel y habilidades")
	check(Attributes.total(ma) == 80 + 14 and gs.attr_points() == 0 and Attributes.valid("asesino", ma, 8), "nivel 8: 14 puntos repartidos solos")
	check(int(ma["destreza"]) - 16 >= 5, "reparto por rol: el Asesino sube Destreza (%d)" % ma["destreza"])
	var cfg2 := ConfigFile.new()
	cfg2.load("user://test_attrs_v4.cfg")
	check(int(cfg2.get_value("meta", "version", 0)) >= 5 and cfg2.has_section_key("slot_0", "attrs"), "se reescribe como v5 con atributos")
	# --- Rival acorde al nivel ---
	var r10 := Attributes.auto_allocate("caballero", 10)
	check(Attributes.total(r10) == 80 + 18 and Attributes.valid("caballero", r10, 10), "rival nivel 10: reparto válido")
	# --- Efectos en combate ---
	gs.reset_defaults()
	gs.save_path = "user://test_attrs.cfg"
	gs.from_lobby = true
	gs.random_rival = false
	gs.character_id = "caballero"
	gs.weapon_id = "espada_escudo"
	gs.eikon_id = "fenix"
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene
	ar.ai.enabled = false
	ar.controller.set_physics_process(false)
	ar.time_left = 1.0e9
	var p := ar.player
	var e := ar.enemy
	await create_timer(0.5).timeout
	for f: Fighter in [p, e]:
		f.poise_max = 1.0e6
		f.poise = f.poise_max
		f.max_health = 9999.0
		f.health = 9999.0
	# Ronda 31: el aturdimiento es acumulado; Aguante sube la robustez y Fuerza la fuerza del golpe
	p.poise_max = 50.0
	var base_r := p.robustness()
	var tough := Attributes.start_for("caballero")
	tough["aguante"] = 35
	p.set_attributes(tough)
	p._refresh_derived()
	var tough_r := p.robustness()
	check(tough_r > base_r * 1.15, "Aguante sube la robustez (%.1f -> %.1f)" % [base_r, tough_r])
	p.set_attributes({})
	p._refresh_derived()
	var base_f := e.hit_stun_force()
	var strong := e.attributes().duplicate()
	strong["fuerza"] = 35
	e.set_attributes(strong)
	e._refresh_derived()
	check(e.hit_stun_force() > base_f * 1.15, "Fuerza sube la fuerza de aturdimiento (%.1f -> %.1f)" % [base_f, e.hit_stun_force()])
	p.stun = 0.0
	var ie0 := p.roll_iframe_end()
	var rc0: float = p.ad["roll_cost"]
	var dex := Attributes.start_for("caballero")
	dex["destreza"] = 45
	p.set_attributes(dex)
	p._refresh_derived()
	check(p.roll_iframe_end() > ie0 + 0.9 / Fighter.ROLL_FPS, "Destreza añade frames de invulnerabilidad (+%d)" % p.ad["iframes"])
	check(p.ad["roll_cost"] < rc0 and p.attr_speed() > 1.05, "Destreza: voltereta más barata y ataque más rápido")
	check(p._atk_data()["windup"] < float(p.melee().attack(false)["windup"]) - 0.001 or p.cur_hit != null, "la anticipación se acorta con Destreza")
	var vit := Attributes.start_for("caballero")
	vit["vitalidad"] = 30
	p.set_attributes({})
	p._apply_character()
	var h0 := p.max_health
	p.set_attributes(vit)
	p._apply_character()
	check(p.max_health > h0 + 60.0, "Vitalidad sube la vida (%.0f -> %.0f)" % [h0, p.max_health])
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(1 if fails > 0 else 0)
