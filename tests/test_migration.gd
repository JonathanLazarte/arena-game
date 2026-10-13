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

## Ronda 11: migración del guardado v1 (ronda 10) a v2.
func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	fresh(gs, "user://test_migration.cfg")
	var v1 := ConfigFile.new()
	v1.set_value("jugador", "nombre", "Pollo")
	v1.set_value("jugador", "oro", 1250)
	v1.set_value("loadout", "character_id", "asesino")
	v1.set_value("loadout", "weapon_id", "espada_larga")
	v1.set_value("loadout", "eikon_id", "golem")
	v1.set_value("loadout", "mount_id", "grifo")
	v1.set_value("loadout", "difficulty", "dificil")
	v1.save(gs.save_path)
	gs.load_loadout()
	check(gs.migrated_from == 1, "detecta guardado v1")
	check(gs.first_run_done, "no vuelve a pedir la elección")
	check(gs.player_name == "Pollo" and gs.oro == 1250 and gs.difficulty == "dificil", "conserva nombre, oro y dificultad")
	check(gs.unlocked_chars == ["asesino"] and gs.character_id == "asesino", "desbloquea solo el personaje que usaba")
	check(gs.weapon_id == "espada_larga" and gs.is_unlocked("weapon", "espada_larga") and gs.is_unlocked("weapon", "dagas"), "conserva su arma equipada y la por defecto")
	check(gs.eikon_id == "golem" and gs.mount_id == "grifo" and "golem" in gs.owned_eikons and "grifo" in gs.owned_mounts, "no pierde eikon ni montura")
	check(gs.account_xp == 0 and gs.account_level() == 1, "progresión empieza en nivel 1")
	var cfg := ConfigFile.new()
	cfg.load(gs.save_path)
	check(cfg.get_value("meta", "version", 0) == 2 and cfg.get_value("progreso", "unlocked_chars") == ["asesino"], "reescribe el archivo como v2")
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.migrated_from == 0 and gs.character_id == "asesino" and gs.oro == 1250, "segunda carga: v2 directo, sin migrar otra vez")
	# Guardado v1 con personaje inválido
	var bad := ConfigFile.new()
	bad.set_value("loadout", "character_id", "dragon")
	bad.save(gs.save_path)
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.first_run_done and gs.unlocked_chars == ["caballero"] and gs.character_id == "caballero", "v1 corrupto: cae en Caballero")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	finish()
