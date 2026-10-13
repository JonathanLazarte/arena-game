extends SceneTree
## Captura del lobby (ronda 10): godot --path . --rendering-driver opengl3 -s res://tests/screenshot_lobby.gd -- <ruta.png> [personaje] [pestaña]

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var gs := root.get_node("GameState")
	gs.save_path = "user://screenshot_loadout.cfg"
	gs.reset_defaults()
	if args.size() > 1:
		gs.set_character(args[1])
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.spin_speed = 0.0
	lobby.pedestal.rotation.y = 0.5
	if args.size() > 2:
		lobby.set_tab(args[2])
	await create_timer(1.0).timeout
	var path := args[0] if args.size() > 0 else "/workspace/out/lobby.png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
