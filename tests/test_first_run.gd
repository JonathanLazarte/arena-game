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

## Ronda 11: primera ejecución (elección del rol) y bloqueo del resto.
func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	fresh(gs, "user://test_first_run.cfg")
	check(not gs.first_run_done and gs.unlocked_chars.is_empty(), "cuenta nueva: sin personaje elegido")
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	await process_frame
	check(current_scene.name == "FirstRun", "la primera vez el lobby lleva a la pantalla de elección (%s)" % current_scene.name)
	var fr := current_scene
	var cd: CharacterDef = fr.selected()
	check(fr.role_buttons.size() == 5 and fr.stage.preview != null and fr.name_label.text == cd.display_name, "presenta los 5 roles con modelo y ficha")
	fr.select(fr.index + 1)
	fr.select(fr.index + 1)
	check(fr.selected().id == "berserker" and fr.stage.preview.cdef.id == "berserker", "navega entre roles (modelo cambia)")
	check(fr.stats_box.get_child_count() >= 5, "muestra estadísticas")
	fr.confirm_choice()
	check(fr.modal.visible and fr.modal_text.text.contains("Berserker") and not gs.first_run_done, "pide confirmación antes de elegir")
	fr.modal.visible = false
	check(not gs.first_run_done, "cancelar no elige nada")
	fr.confirm_choice()
	fr.accept()
	check(not gs.first_run_done, "ronda 29: sin nombre no se confirma")
	fr.name_input.text = "  Ragnar  "
	fr.accept_button.pressed.emit()
	check(gs.char_name() == "Ragnar", "ronda 29: el personaje lleva el nombre que puso el jugador (%s)" % gs.char_name())
	check(gs.first_run_done and gs.unlocked_chars == ["berserker"] and gs.character_id == "berserker", "solo el elegido queda desbloqueado")
	check(gs.weapon_id == "hacha_2m" and gs.is_unlocked("weapon", "hacha_2m"), "con su arma por defecto")
	await create_timer(1.6).timeout
	check(current_scene.name == "Lobby", "tras jurar va al lobby (%s)" % current_scene.name)
	var lobby := current_scene
	check(not gs.set_character("paladin") and gs.character_id == "berserker", "no se puede equipar un personaje bloqueado")
	var cfg := ConfigFile.new()
	check(cfg.load(gs.save_path) == OK and cfg.get_value("progreso", "first_run_done") == true and cfg.get_value("meta", "version") == gs.SAVE_VERSION, "elección guardada (v%d)" % gs.SAVE_VERSION)
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.first_run_done and gs.unlocked_chars == ["berserker"], "se recupera al reabrir")
	lobby.set_tab("Personaje")
	await process_frame
	var locked := 0
	for b in lobby.list_box.get_children():
		if (b as Button).text.contains("oro") or (b as Button).text.contains("Paladín"):
			locked += 1
	check(locked == 0, "ya no se listan otros personajes a la venta (%d)" % locked)
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	await process_frame
	check(current_scene.name == "Lobby", "ya no vuelve a pedir la elección")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
