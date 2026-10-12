extends SceneTree
## Captura a pie: godot --path . -s res://tests/screenshot2.gd -- <ruta.png>
func _initialize() -> void:
	_run()
func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.ai.enabled = false
	arena.player.dismount(false)
	arena.enemy.dismount(false)
	await create_timer(0.3).timeout
	arena.player.owned_mount.global_position = Vector3(-12, 0.2, 10)
	arena.player.owned_mount.home = Vector3(-12, 0.2, 10)
	arena.enemy.owned_mount.global_position = Vector3(12, 0.2, 10)
	arena.enemy.owned_mount.home = Vector3(12, 0.2, 10)
	await create_timer(0.5).timeout
	arena.enemy.global_position = arena.player.global_position + arena.player.facing * 3.0 + arena.player.facing.cross(Vector3.UP) * 1.2
	arena.enemy.facing = -arena.player.facing
	arena.enemy.want_block = true
	await create_timer(0.6).timeout
	arena.player.attack_light()
	await create_timer(0.3).timeout
	var path := "/workspace/out/arena-shot2.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
	quit()
