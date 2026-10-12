extends SceneTree
## Captura de pantalla: godot --path . -s res://tests/screenshot.gd -- <ruta.png>

func _initialize() -> void:
	_run()

func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	await create_timer(1.5).timeout
	arena.enemy.global_position = arena.player.global_position + Vector3(2, 0, -7)
	arena.player.meter = 100.0
	arena.player.summon()
	await create_timer(1.2).timeout
	await create_timer(0.6).timeout
	arena.enemy.global_position = arena.player.global_position + arena.player.facing * 3.2
	arena.ai.enabled = false
	arena.enemy.attack_heavy() # telegrafía: hoja alzada y brillante
	await create_timer(0.5).timeout
	var path := "/workspace/out/arena-shot.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
	quit()
