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
	f.stun = 0.0
	f.down_t = 0.0
	f.stagger_t = 0.0
	f.stun_immune_t = 0.0
	f.invuln = 0.0

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
	check(gs.toggle_boss_ability("rafaga") and gs.toggle_boss_ability("carga_area") and gs.toggle_boss_ability("salto_caida"), "máx. 4 equipadas")
	gs.save_loadout()
	gs.char_boss = {}
	gs.load_loadout()
	check(gs.boss_abilities().size() == 4 and "rafaga" in gs.boss_abilities(), "se guardan (v%d)" % gs.SAVE_VERSION)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Arena ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Costes
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Salto con caída: cuesta vida y aterriza en la marca
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Estocada: sigue al que camina
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Ráfaga: caminando te alcanza
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Disparo cargado (sin el controlador del jugador, que fija want_shot_hold con el botón)
	quit(1 if fails > 0 else 0)
func ranged_draw(p: Fighter) -> float:
	return p.ranged().fire_draw / p.attr_speed()
