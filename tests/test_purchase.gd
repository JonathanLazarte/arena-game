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
	# Ronda 15: los personajes no se compran ni se cambian
	gs.oro = 99999
	check(gs.can_buy("character", "arquero") == "no_venta" and gs.buy("character", "arquero") == "no_venta" and gs.oro == 99999, "no se puede comprar un personaje aunque sobre oro")
	check(gs.can_buy("character", "caballero") == "ya", "el propio ya está desbloqueado")
	check(not gs.set_character("arquero") and gs.character_id == "caballero" and gs.unlocked_chars == ["caballero"], "no se puede cambiar de personaje")
	check(gs.change_character("arquero") == "proximamente" and gs.character_id == "caballero", "«Cambio de personaje»: gancho presente pero Próximamente")
	check(not Progression.CHARACTER_CHANGE_ENABLED and not Progression.CHARACTER_CHANGE_ITEM["available"], "el objeto de tienda no está a la venta")
	check(not "CHARACTER_PRICE" in Progression.new().get_script().get_script_constant_map(), "sin tabla de precios de personajes")
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
	check(gs.unlocked_chars == ["caballero"] and "lanza" in gs.owned_weapons and "lobo" in gs.owned_eikons, "las compras se guardan")
	# Flujo en el lobby con confirmación
	gs.oro = 1300
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.set_tab("Personaje")
	await process_frame
	var txt := ""
	var cc: Button = null
	for bt in lobby.list_box.get_children():
		if bt.is_queued_for_deletion(): continue
		txt += (bt as Button).text + "|"
		if not bt.is_queued_for_deletion() and String(bt.name).begins_with("CambioPersonaje"): cc = bt
	check(not txt.contains("Paladín") and not txt.contains("oro") and txt.contains("Caballero"), "lobby: la pestaña Personaje solo muestra el tuyo (%s)" % txt)
	check(cc != null and cc.text.contains("Próximamente"), "lobby: «Cambio de personaje — Próximamente»")
	cc.pressed.emit()
	check(lobby.modal.visible and lobby.modal_ok.disabled, "lobby: el objeto no se puede comprar aún")
	lobby.close_modal()
	check(gs.oro == 1300 and gs.character_id == "caballero", "nada cambia")
	lobby.request_purchase("weapon", "espada_larga")
	check(lobby.modal.visible and not lobby.modal_ok.disabled, "las armas siguen comprándose")
	lobby.modal_ok.pressed.emit()
	await process_frame
	check(gs.is_unlocked("weapon", "espada_larga") and gs.oro == 1300 - Progression.WEAPON_REQ["espada_larga"][1], "aceptar compra de arma cobra (oro %d)" % gs.oro)
	check(lobby.oro_label.text.begins_with(str(gs.oro)), "la barra superior muestra el oro nuevo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
