extends SceneTree
var fails: int = 0
func _initialize() -> void:
	_run()
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1
func finish() -> void:
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
func fresh(gs: Node, path: String) -> void:
	gs.save_path = path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	gs.reset_defaults()

## Ronda 11: curva de XP, recompensas, niveles, árbol de habilidades y pantalla de resultados.
func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	fresh(gs, "user://test_progression.cfg")
	check(Progression.xp_to_next(1) == 100 and Progression.xp_to_next(2) == 260 and Progression.xp_to_next(5) == 950, "curva 100·n^1.4: 100, 260, ... 950 (%d %d %d)" % [Progression.xp_to_next(1), Progression.xp_to_next(2), Progression.xp_to_next(5)])
	var inc := true
	for n in range(1, 29):
		inc = inc and Progression.xp_to_next(n + 1) > Progression.xp_to_next(n)
	check(inc, "la curva siempre crece")
	check(Progression.level_for_xp(0) == 1 and Progression.level_for_xp(99) == 1 and Progression.level_for_xp(100) == 2 and Progression.level_for_xp(360) == 3, "niveles por XP")
	check(Progression.level_for_xp(10000000) == Progression.MAX_LEVEL, "tope de nivel %d" % Progression.MAX_LEVEL)
	var w := Progression.match_rewards({"won": true, "rounds": 2, "hits": 10, "parries": 1, "difficulty": "normal"})
	check(w["xp"] == 120 + 50 + 30 + 10 and w["gold"] == 150 + 40 + 5, "victoria: %d XP, %d oro" % [w["xp"], w["gold"]])
	var l := Progression.match_rewards({"won": false, "rounds": 1, "hits": 100, "parries": 0, "difficulty": "normal"})
	check(l["xp"] == 50 + 25 + 90 and l["gold"] == 60 + 20, "derrota: golpes topados a 30 (%d XP)" % l["xp"])
	var hard := Progression.match_rewards({"won": true, "rounds": 2, "hits": 10, "parries": 1, "difficulty": "dificil"})
	check(hard["xp"] > w["xp"] and hard["gold"] > w["gold"], "difícil da más")
	gs.choose_first_character("caballero")
	var r: Dictionary = gs.apply_match_result({"won": true, "rounds": 2, "hits": 10, "parries": 1, "difficulty": "normal"})
	check(gs.account_xp == 210 and gs.char_xp["caballero"] == 210 and gs.account_level() == 2 and gs.char_level() == 2, "XP a cuenta y personaje: nivel 2")
	check(r["account_after"] == 2 and r["level_bonus"] == Progression.GOLD_LEVEL_UP and gs.oro == Progression.START_GOLD + 195 + 100, "bonus de oro al subir (oro %d)" % gs.oro)
	# Habilidades
	check(gs.skill_points() == 1, "1 punto de habilidad a nivel 2")
	check(gs.learn_skill("cab_parada") == "req", "hay que aprender antes el requisito")
	check(gs.learn_skill("ber_piel") == "req", "no se aprenden nodos de otro rol")
	check(gs.learn_skill("cab_resistencia") == "ok" and gs.skill_points() == 0, "aprende Resistencia")
	check(gs.learn_skill("cab_parada") == "puntos", "sin puntos no aprende")
	gs.char_xp["caballero"] = Progression.xp_at_level(6)
	check(gs.skill_points() == 4 and gs.learn_skill("cab_parada") == "ok" and gs.learn_skill("cab_hierro") == "ok", "a nivel 6 aprende más (puntos %d)" % gs.skill_points())
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.char_skills("caballero").size() == 3 and gs.account_xp == 210, "progreso guardado")
	# Efecto en combate y pantalla de resultados
	gs.from_lobby = true
	gs.random_rival = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var a: Arena = current_scene
	a.ai.enabled = false
	var p := a.player
	check(is_equal_approx(p.stamina_max, 115.0) and is_equal_approx(p.parry_window, Fighter.PARRY_WINDOW + 0.06), "habilidades: estamina 115 y ventana de parry 0,36 s")
	var e := a.enemy
	check(p.blocked_hit_cost(12.0, e) < e.blocked_hit_cost(12.0, p) * 0.7, "Guardia de hierro: −35 %% al bloquear")
	var xp0: int = gs.account_xp
	p.hits_landed = 5
	a.wins = [1, 0]
	a._on_fighter_died(a.enemy)
	await process_frame
	check(a.state == "over" and a.hud.end_panel.visible and a.hud.end_label.text == "VICTORIA", "pantalla de resultados al ganar")
	check(gs.account_xp > xp0 and a.match_result["xp"] == gs.account_xp - xp0, "XP sumada (%d)" % a.match_result.get("xp", 0))
	var total := a.hud.results_box.find_child("Total", true, false) as Label
	check(total != null and total.text.contains("EXP") and total.text.contains("Oro"), "muestra XP y oro ganados")
	check(not a.hud.joystick.visible, "oculta los controles táctiles")
	gs.from_lobby = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
