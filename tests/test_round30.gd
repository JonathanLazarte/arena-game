extends SceneTree
## Ronda 30: movimiento fluido, propiedad de personajes (reclutar), ficha personal, menú sin pausa,
## anillos/talismanes, títulos y grabado con brillo.
## godot --headless --path . -s res://tests/test_round30.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round30.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	# --- 1. Entrada y giro ---
	var circle := true
	for i in 36:
		var a := TAU * i / 36.0
		var o := PlayerController.shape_stick(Vector2(cos(a), sin(a)))
		circle = circle and absf(o.length() - 1.0) < 0.001 and absf(o.angle() - Vector2(cos(a), sin(a)).angle()) < 0.001
	check(circle, "stick: zona muerta radial + curva; girar el stick da un círculo perfecto")
	check(PlayerController.shape_stick(Vector2(0.1, 0.1)) == Vector2.ZERO and PlayerController.shape_stick(Vector2(0.6, 0)).x < 0.6, "zona muerta y curva de respuesta")
	var cur := Vector2(0, -1)
	var diag := false
	var min_len := 1.0
	for i in 12:
		cur = PlayerController.smooth_input(cur, Vector2(1, 0), 1.0 / 60.0)
		diag = diag or (cur.x > 0.5 and cur.y < -0.5)
		min_len = minf(min_len, cur.length())
	check(diag and min_len > 0.95 and cur.distance_to(Vector2(1, 0)) < 0.01, "W→D pasa por la diagonal sin perder magnitud (min %.2f), en ~0,08 s" % min_len)
	var v := Vector3(0, 0, -5)
	var vmin := 5.0
	for i in 20:
		v = Fighter._steer_velocity(v, Vector3(5, 0, 0), 30.0 / 60.0, deg_to_rad(Fighter.TURN_RATE_DEG) / 60.0)
		vmin = minf(vmin, v.length())
	check(vmin > 4.9 and v.normalized().dot(Vector3(1, 0, 0)) > 0.99, "la velocidad gira sin caer a cero (min %.2f)" % vmin)
	# --- 2/3. Propiedad, reclutar, ficha ---
	gs.choose_first_character("caballero", "Ana")
	check(gs.unlocked_chars == ["caballero"], "al empezar solo tienes uno")
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.cycle_character(1)
	check(gs.character_id == "caballero" and lobby.view_char == "caballero", "el selector no muestra personajes que no tienes")
	var nx := lobby.root_ui.get_node("CharNext") as Button
	check(not nx.visible, "con un solo personaje no hay flechas")
	check("Reclutar" in lobby.TABS, "pestaña Reclutar")
	gs.oro = 99999
	gs.account_xp = Progression.xp_at_level(Progression.CHAR_REQ[0])
	lobby.set_tab("Reclutar")
	await process_frame
	check(lobby.recruit("arquero", "  ") == "nombre" and not gs.is_unlocked("character", "arquero"), "reclutar exige nombre")
	check(lobby.recruit("arquero", "Lia") == "ok" and gs.character_id == "arquero" and gs.char_name() == "Lia", "reclutar con nombre")
	await process_frame
	check(nx.visible and nx.get_global_rect().end.x < lobby.right_panel.position.x and nx.size.x <= 44, "flechas pequeñas junto al personaje, fuera del panel derecho")
	lobby.cycle_character(1)
	check(gs.character_id == "caballero", "cicla entre los tuyos")
	gs.apply_match_result({"won": true, "secs": 125.0, "rounds": 2, "lost_rounds": 0})
	check(gs.char_stat()["wins"] == 1 and gs.char_stat()["matches"] == 1 and absf(gs.char_stat()["secs"] - 125.0) < 0.01 and gs.char_stat("arquero")["matches"] == 0, "ficha: victorias, partidas y tiempo por personaje")
	lobby.set_tab("Personaje")
	await process_frame
	check(lobby.sheet.left.text.contains("Ana") and lobby.sheet.left.text.contains("Victorias 1 / 1") and lobby.sheet.left.text.contains("0 h 02 min"), "ficha en el lobby: nombre, horas, victorias")
	# --- 6. Anillos y talismanes ---
	check(gs.buy("trinket", "cefiro") == "ok" and gs.buy("trinket", "aliento_largo") == "ok" and gs.buy("trinket", "eco_templado") == "ok", "se compran accesorios")
	check(gs.equip_trinket("ring", 0, "cefiro") and gs.equip_trinket("talisman", 1, "aliento_largo") and not gs.equip_trinket("ring", 1, "aliento_largo"), "se equipan en su tipo de ranura")
	check(lobby.sheet.equip("talisman0", "eco_templado") and gs.talismans_eq == ["eco_templado", "aliento_largo", ""], "desde la ficha")
	gs.equip_trinket("talisman", 2, "eco_templado")
	check(gs.talismans_eq == ["", "aliento_largo", "eco_templado"], "sin duplicados: se mueve de ranura")
	var fx := Trinkets.combine(gs.equipped_trinkets())
	check(fx["roll_iframes"] == 2 and is_equal_approx(fx["stamina_cost"], 0.88) and fx["parry_stamina"] == 18.0, "efectos combinados")
	gs.switch_character("arquero")
	check(gs.equipped_trinkets().is_empty(), "accesorios por personaje")
	gs.switch_character("caballero")
	check(gs.rings_eq[0] == "cefiro", "al volver conserva los suyos")
	# Títulos
	check(not gs.set_title("vencedor") and gs.set_title("recien_llegado"), "solo títulos ganados")
	gs.char_stats["caballero"]["wins"] = 5
	check("vencedor" in gs.earned_titles() and gs.set_title("vencedor") and gs.display_name_with_title() == "Ana  «Vencedor»", "título junto al nombre")
	check(is_equal_approx(Trinkets.combine(gs.equipped_trinkets())["stamina_cost"], 0.88 * 0.98), "el título da su bonificación pequeña")
	gs.save_loadout()
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.SAVE_VERSION >= 10 and gs.rings_eq[0] == "cefiro" and "cefiro" in gs.owned_trinkets and gs.title_id() == "vencedor" and gs.char_stat()["wins"] == 5, "v10: accesorios, título y ficha persisten")
	# Migración v9 -> v10
	var cfg := ConfigFile.new()
	cfg.load(gs.save_path)
	cfg.set_value("meta", "version", 9)
	cfg.save(gs.save_path)
	gs.load_loadout()
	check(gs.owned_trinkets.is_empty() and gs.rings_eq == ["", ""] and gs.char_stat()["matches"] == 0 and gs.character_id == "caballero" and gs.unlocked_chars.has("arquero"), "partida v9: sin accesorios, ficha a cero, personajes intactos")
	gs.buy("trinket", "cefiro")
	gs.buy("trinket", "aliento_largo")
	gs.equip_trinket("ring", 0, "cefiro")
	gs.equip_trinket("talisman", 0, "aliento_largo")
	# Grabado
	check(Smithing.engraving_glow(4) == Color.BLACK and Smithing.engraving_glow(5) != Color.BLACK, "el grabado brilla desde +5")
	gs.weapon_up[gs.weapon_id] = 6
	# --- 4. Menú sin pausa, en arena ---
	gs.from_lobby = true
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1e9
	await create_timer(3.3).timeout
	var p := arena.player
	check(p.trinket_ids.has("cefiro") and is_equal_approx(p.tfx["stamina_cost"], 0.88), "el luchador lleva sus accesorios")
	var s0: float = p.stamina
	p.spend_stamina(10.0)
	check(is_equal_approx(s0 - p.stamina, 8.8), "−12 %% de gasto de aguante (%.2f)" % (s0 - p.stamina))
	check(p._kv.base_glow != Color.BLACK, "arma +6: la hoja brilla")
	# giro: velocidad angular limitada
	p.face_target = null
	arena.controller.lock_on = false
	p.facing = Vector3(0, 0, -1)
	p.move_input = Vector3(0, 0, 1)
	arena.controller.enabled = false
	var f0 := p.facing
	await physics_frame
	p.move_input = Vector3(0, 0, 1)
	await physics_frame
	var deg := rad_to_deg(f0.angle_to(p.facing))
	check(deg > 5.0 and deg < 2.0 * Fighter.TURN_RATE_DEG / 60.0 + 1.0, "giro con velocidad angular (%.1f° en 2 frames)" % deg)
	for i in 30:
		p.move_input = Vector3(1, 0, 0)
		await physics_frame
	var lean_seen := false
	for i in 20:
		p.move_input = Vector3(0, 0, -1)
		await physics_frame
		lean_seen = lean_seen or absf(p.lean) > 0.02
	check(lean_seen, "se inclina hacia el giro")
	arena.controller.enabled = true
	arena.hud.open_pause()
	var t0 := arena.time_left
	var pos0 := p.global_position
	for i in 40:
		await physics_frame
	check(arena.hud.is_pause_open() and not paused, "menú abierto: el juego NO se pausa")
	check(p.move_input == Vector3.ZERO and p.blocking and MeshUtil.flat(p.velocity).length() < 0.5, "con el menú abierto el personaje se queda quieto en guardia")
	check(arena.rig.menu_open, "ratón libre con el menú")
	arena.hud.close_pause()
	await physics_frame
	check(not arena.controller.menu_hold and not arena.rig.menu_open, "se cierra y se vuelve a jugar")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	check(arena.hud.is_pause_open(), "Esc abre el menú")
	arena.hud.close_pause()
	gs.from_lobby = false
	gs.reset_defaults()
	check(gs.apply_debug_grant() and gs.oro >= gs.DEBUG_GOLD and gs.material("piedra_antigua") >= 15 and gs.owned_trinkets.size() == Trinkets.RINGS.size() + Trinkets.TALISMANS.size() and not gs.apply_debug_grant(), "recursos de prueba: una sola vez por perfil")
	gs.reset_defaults()
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(fails)
