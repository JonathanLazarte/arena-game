extends SceneTree
## Captura a pie: godot --path . -s res://tests/screenshot2.gd -- <ruta.png>
func _initialize() -> void:
	_run()
func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.sim_ai.enabled = false
	pass # fase 8: dismount() vive en la sim (pulsar el bit vía sim_match.input_override)
	pass # fase 8: dismount() vive en la sim (pulsar el bit vía sim_match.input_override)
	await create_timer(0.3).timeout
	await create_timer(0.5).timeout
	arena.enemy.global_position = arena.player.global_position + arena.player.facing * 3.0 + arena.player.facing.cross(Vector3.UP) * 1.2
	arena.enemy.facing = -arena.player.facing
	arena.enemy.want_block = true
	await create_timer(0.6).timeout
	pass # fase 8: attack_light() vive en la sim (pulsar el bit vía sim_match.input_override)
	await create_timer(0.3).timeout
	var path := "/workspace/out/arena-shot2.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
	quit()
