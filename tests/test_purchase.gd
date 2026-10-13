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
	check(gs.can_buy("character", "arquero") == "oro" and gs.buy("character", "arquero") == "oro" and gs.oro == Progression.START_GOLD, "sin oro suficiente no compra ni cobra")
	check(gs.can_buy("character", "caballero") == "ya", "el propio ya está desbloqueado")
	gs.oro = 5000
	check(gs.buy("character", "arquero") == "ok" and gs.oro == 5000 - Progression.CHARACTER_PRICE["arquero"], "compra el arquero por %d" % Progression.CHARACTER_PRICE["arquero"])
	check(gs.is_unlocked("character", "arquero") and gs.is_unlocked("weapon", "arco") and gs.set_character("arquero"), "desbloqueado con su arma y equipable")
	check(gs.buy("character", "arquero") == "ya", "no se compra dos veces")
	gs.set_character("caballero")
	# Requisito de nivel
	check(gs.account_level() == 1 and gs.can_buy("weapon", "lanza") == "nivel", "la lanza pide nivel %d" % Progression.WEAPON_REQ["lanza"][0])
	check(not gs.set_weapon("lanza"), "no se equipa sin tenerla")
	gs.account_xp = Progression.xp_at_level(Progression.WEAPON_REQ["lanza"][0])
	var o: int = gs.oro
	check(gs.buy("weapon", "lanza") == "ok" and gs.oro == o - Progression.WEAPON_REQ["lanza"][1] and gs.set_weapon("lanza"), "con nivel la compra y la equipa")
	check(gs.can_buy("eikon", "golem") == "nivel" and gs.can_buy("mount", "unicornio") == "ok", "eikon gólem pide nivel; unicornio disponible")
	check(gs.buy("mount", "unicornio") == "ok" and "unicornio" in gs.owned_mounts, "compra montura")
	gs.reset_defaults()
	gs.load_loadout()
	check("arquero" in gs.unlocked_chars and "lanza" in gs.owned_weapons and "unicornio" in gs.owned_mounts, "las compras se guardan")
	# Flujo en el lobby con confirmación
	gs.oro = 1300
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.request_purchase("character", "paladin")
	check(lobby.modal.visible and lobby.modal_ok.disabled and lobby.modal_title.text == "Oro insuficiente", "lobby: avisa de oro insuficiente")
	lobby.close_modal()
	gs.oro = 2000
	lobby.request_purchase("character", "paladin")
	check(lobby.modal.visible and not lobby.modal_ok.disabled and lobby.modal_text.text.contains("1800"), "lobby: confirmación con precio")
	lobby.close_modal()
	check(not gs.is_unlocked("character", "paladin") and gs.oro == 2000, "cancelar no compra")
	lobby.request_purchase("character", "paladin")
	lobby.modal_ok.pressed.emit()
	await process_frame
	check(gs.is_unlocked("character", "paladin") and gs.oro == 200 and gs.character_id == "paladin", "aceptar compra, cobra y equipa (oro %d)" % gs.oro)
	check(lobby.oro_label.text.begins_with("200"), "la barra superior muestra el oro nuevo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
