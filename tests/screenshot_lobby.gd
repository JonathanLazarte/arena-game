extends SceneTree
## Capturas de la ronda 11:
## godot --path . --rendering-driver opengl3 -s res://tests/screenshot_lobby.gd -- <ruta.png> <modo> [personaje] [pestaña]
## modo: lobby | first_run | results

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "/workspace/out/lobby.png"
	var mode := args[1] if args.size() > 1 else "lobby"
	var gs := root.get_node("GameState")
	gs.save_path = "user://screenshot_loadout.cfg"
	gs.reset_defaults()
	if mode == "first_run":
		change_scene_to_file("res://scenes/first_run.tscn")
		await process_frame
		await process_frame
		current_scene.select(2)
		await create_timer(1.2).timeout
	elif mode == "results":
		gs.choose_first_character("berserker")
		gs.account_xp = 80
		gs.char_xp["berserker"] = 80
		gs.from_lobby = true
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var a: Arena = current_scene
		a.ai.enabled = false
		a.player.hits_landed = 14
		a.player.parries_landed = 2
		a.wins = [1, 2]
		a.state = "fight"
		a.wins[1] = 1
		a._on_fighter_died(a.player)
		a.wins = [2, 1]
		a.state = "fight"
		a.wins[0] = 1
		a._on_fighter_died(a.enemy)
		await create_timer(2.0).timeout
	else:
		var cid := args[2] if args.size() > 2 else "caballero"
		gs.choose_first_character(cid)
		gs.oro = 2400
		gs.account_xp = 900
		gs.char_xp[cid] = 900
		if args.size() > 3 and args[3] == "Habilidades":
			gs.learn_skill(Progression.tree(cid)[0]["id"])
			gs.learn_skill(Progression.tree(cid)[1]["id"])
		change_scene_to_file("res://scenes/lobby.tscn")
		await process_frame
		await process_frame
		var lobby := current_scene
		lobby.spin_speed = 0.0
		lobby.pedestal.rotation.y = 0.4
		if args.size() > 3:
			lobby.set_tab(args[3])
		await create_timer(1.2).timeout
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
