extends SceneTree
## Captura del jinete montado (ronda 8):
## godot --path . -s res://tests/screenshot_mounted.gd -- <ruta.png> [galope]

func _initialize() -> void:
	_run()

func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	var args := OS.get_cmdline_user_args()
	var p := arena.player
	arena.enemy.global_position = p.global_position + Vector3(14, 0, -10)
	await create_timer(1.0).timeout
	if args.size() > 1 and args[1] == "gallop":
		p.move_input = p.facing
		await create_timer(1.2).timeout
	var cam := Camera3D.new()
	arena.add_child(cam)
	var side := p.facing.cross(Vector3.UP)
	cam.fov = 50
	var view := side * 3.6 + p.facing * 2.6 + Vector3(0, 1.7, 0)
	if args.size() > 3 and args[3] == "front":
		view = p.facing * 3.6 + side * 1.2 + Vector3(0, 1.6, 0)
	cam.look_at_from_position(p.global_position + view, p.global_position + Vector3(0, 1.6, 0))
	cam.current = true
	if args.size() > 2 and args[2] == "hide":
		p.mount_node.model.visible = false
	for c in arena.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	await create_timer(0.3).timeout
	var path := args[0] if args.size() > 0 else "/workspace/out/arena-mounted.png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " mounted=", p.mounted)
	quit()
