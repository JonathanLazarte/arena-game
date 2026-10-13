extends SceneTree
## Ronda 10: equipamiento guardado en user:// y aplicado a la partida.
var fails: int = 0
func _initialize() -> void:
	_run()
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1
func _run() -> void:
	await process_frame # deja que los autoloads terminen su _ready (carga del archivo)
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_loadout.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	gs.set_character("berserker")
	check(gs.weapon_id == "hacha_2m", "al cambiar a un rol, el arma incompatible pasa a la de por defecto")
	check(not gs.set_weapon("arco") and gs.weapon_id == "hacha_2m", "no deja equipar un arma no compatible")
	check(gs.set_weapon("espada_larga"), "equipa un arma compatible")
	gs.eikon_id = "golem"
	gs.difficulty = "dificil"
	gs.player_name = "Pollo"
	gs.save_loadout()
	gs.reset_defaults()
	check(gs.character_id == "caballero", "restablecido")
	gs.load_loadout()
	check(gs.character_id == "berserker" and gs.weapon_id == "espada_larga" and gs.eikon_id == "golem"
		and gs.difficulty == "dificil" and gs.player_name == "Pollo", "se recupera todo del archivo")
	# Archivo corrupto/viejo: valores inválidos se corrigen
	var cfg := ConfigFile.new()
	cfg.load(gs.save_path)
	cfg.set_value("slot_0", "character_id", "arquero") # v4: datos del personaje en la ranura
	cfg.set_value("slot_0", "weapon_id", "hacha_2m")
	cfg.set_value("loadout", "eikon_id", "dragon")
	cfg.save(gs.save_path)
	gs.load_loadout()
	check(gs.weapon_id == "arco" and gs.eikon_id == "fenix", "valores inválidos se corrigen (arma %s, eikon %s)" % [gs.weapon_id, gs.eikon_id])
	# La partida usa el equipamiento
	gs.set_character("berserker")
	gs.weapon_id = "hacha_2m"
	gs.eikon_id = "grifo"
	gs.difficulty = "normal"
	gs.from_lobby = true
	gs.random_rival = true
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	var p := arena.player
	check(p.character.id == "berserker" and p.weapon.id == "hacha_2m", "el jugador lleva berserker + hacha")
	check(is_equal_approx(p.max_health, 120.0), "vida del berserker (%.0f)" % p.max_health)
	check(p.eikon.id == "grifo" and not p.mounted and arena.ai.profile.resource_path.ends_with("normal.tres"), "eikon (montura) y dificultad del lobby; empieza a pie")
	check(arena.enemy.character != null and arena.enemy.character.allows(arena.enemy.weapon.id) and not arena.enemy.weapon.ranged, "rival con equipamiento aleatorio coherente (%s, %s)" % [arena.enemy.character.id, arena.enemy.weapon.id])
	var lb := arena.hud.end_panel.find_child("LobbyButton", true, false) as Button
	check(lb != null and lb.text == "Volver al lobby", "panel final con botón Volver al lobby")
	gs.first_run_done = true
	gs.unlocked_chars = ["berserker"]
	lb.pressed.emit()
	await create_timer(1.0).timeout # fundido a negro
	check(current_scene.name == "Lobby", "vuelve al lobby (%s)" % current_scene.name)
	check(gs.from_lobby == false, "el lobby limpia la bandera de partida")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
