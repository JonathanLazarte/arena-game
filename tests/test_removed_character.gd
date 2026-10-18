extends SceneTree
## Un guardado que apunta a un personaje eliminado del catálogo carga sin romperse:
## cae al personaje por defecto con un arma compatible y no queda en la lista de desbloqueados.
## godot --headless --path . -s res://tests/test_removed_character.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var path := "user://test_removed_character.cfg"
	gs.save_path = path
	for ver: int in [gs.SAVE_VERSION, 8]:
		var cfg := ConfigFile.new()
		cfg.set_value("meta", "version", ver)
		cfg.set_value("meta", "active_slot", 0)
		cfg.set_value("progreso", "first_run_done", true)
		cfg.set_value("progreso", "unlocked_chars", ["personaje_borrado", "asesino"])
		cfg.set_value("loadout", "character_id", "personaje_borrado")
		cfg.set_value("loadout", "weapon_id", "dagas")
		cfg.set_value("slot_0", "character_id", "personaje_borrado")
		cfg.set_value("slot_0", "weapon_id", "dagas")
		cfg.set_value("personajes", "desbloqueados", ["personaje_borrado", "asesino"])
		cfg.save(path)
		gs.load_loadout()
		var ids: Array = Catalog.CHARACTERS.map(func(p: String) -> String: return (load(p) as CharacterDef).id)
		check(gs.character_id in ids, "v%d: cae a un personaje existente (%s)" % [ver, gs.character_id])
		check(not "personaje_borrado" in gs.unlocked_chars and gs.character_id in gs.unlocked_chars, "v%d: el borrado no queda desbloqueado %s" % [ver, str(gs.unlocked_chars)])
		check(Catalog.character(gs.character_id).allows(gs.weapon_id), "v%d: arma compatible (%s)" % [ver, gs.weapon_id])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
