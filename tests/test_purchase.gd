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

## Ronda 11: compras con oro (personajes, armas, eikons, monturas) y confirmación en el lobby.
func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	fresh(gs, "user://test_purchase.cfg")
	gs.choose_first_character("caballero")
	check(gs.oro == Progression.START_GOLD, "oro inicial %d" % gs.oro)
	# Ronda 29: los personajes se compran (nivel de cuenta + oro) y llevan nombre propio
	gs.oro = 99999
	check(gs.can_buy("character", "arquero") == "nivel" and gs.oro == 99999, "otro personaje pide nivel de cuenta %d" % Progression.CHAR_REQ[0])
	gs.account_xp = Progression.xp_at_level(Progression.CHAR_REQ[0])
	check(gs.buy_character("arquero", "   ") == "nombre" and not gs.is_unlocked("character", "arquero"), "sin nombre no se compra")
	check(gs.buy_character("arquero", "Legolas") == "ok" and gs.oro == 99999 - Progression.CHAR_REQ[1] and gs.char_name("arquero") == "Legolas", "se compra con nombre (%d oro)" % Progression.CHAR_REQ[1])
	check(gs.can_buy("character", "caballero") == "ya", "el propio ya está desbloqueado")
	check(gs.character_id == "caballero" and gs.weapon_id == "espada_escudo", "comprar no cambia de personaje")
	gs.switch_character("arquero")
	check(gs.character_id == "arquero" and gs.weapon_id == "arco", "cambiar al nuevo: su arma por defecto")
	gs.switch_character("caballero")
	check(gs.character_id == "caballero" and gs.weapon_id == "espada_escudo" and not gs.switch_character("paladin"), "volver conserva el equipo; no se cambia a uno bloqueado")
	gs.save_loadout()
	gs.load_loadout()
	check(gs.unlocked_chars.has("arquero") and gs.char_name("arquero") == "Legolas", "personajes y nombres guardados (v%d)" % gs.SAVE_VERSION)
	check(not gs.has_method("change_character") and not "CHARACTER_CHANGE_ITEM" in Progression.new().get_script().get_script_constant_map(), "ronda 19: «Cambio de personaje» eliminado")
	gs.account_xp = 0
	gs.oro = 5000
	# Requisito de nivel
	check(gs.account_level() == 1 and gs.can_buy("weapon", "lanza") == "nivel", "la lanza pide nivel %d" % Progression.WEAPON_REQ["lanza"][0])
	check(not gs.set_weapon("lanza"), "no se equipa sin tenerla")
	gs.account_xp = Progression.xp_at_level(Progression.WEAPON_REQ["lanza"][0])
	var o: int = gs.oro
	check(gs.buy("weapon", "lanza") == "ok" and gs.oro == o - Progression.WEAPON_REQ["lanza"][1] and gs.set_weapon("lanza"), "con nivel la compra y la equipa")
	gs.oro += Progression.EIKON_REQ["lobo"][1]
	check(gs.can_buy("eikon", "golem") == "nivel" and gs.can_buy("eikon", "lobo") == "ok", "eikon gólem pide nivel; lobo (montable) disponible")
	check(gs.buy("eikon", "lobo") == "ok" and "lobo" in gs.owned_eikons, "compra eikon montable")
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.unlocked_chars == ["caballero", "arquero"] and "lanza" in gs.owned_weapons and "lobo" in gs.owned_eikons, "las compras se guardan")
	# Flujo en el lobby con confirmación
	gs.oro = 1300
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	check(lobby.tab == "" and not lobby.right_panel.visible and not lobby.sheet.visible, "ronda 19: al entrar no hay pestaña abierta")
	lobby.set_tab("Personaje")
	await process_frame
	check(lobby.sheet.visible and lobby.sheet.find_child("AtributosButton", true, false) != null, "Personaje: ficha con botón Atributos")
	check(lobby.root_ui.find_child("CambioPersonaje", true, false) == null, "sin «Cambio de personaje»")
	lobby.set_tab("Tienda")
	await process_frame
	lobby.request_purchase("weapon", "espada_larga")
	check(lobby.modal.visible and not lobby.modal_ok.disabled, "las armas siguen comprándose")
	lobby.modal_ok.pressed.emit()
	await process_frame
	check(gs.is_unlocked("weapon", "espada_larga") and gs.oro == 1300 - Progression.WEAPON_REQ["espada_larga"][1], "aceptar compra de arma cobra (oro %d)" % gs.oro)
	check(lobby.oro_label.text.begins_with(str(gs.oro)), "la barra superior muestra el oro nuevo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
