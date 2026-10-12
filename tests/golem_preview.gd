extends SceneTree
## Vista previa del gólem junto a un caballero: godot --path . -s res://tests/golem_preview.gd -- <png>
func _initialize() -> void:
	_run()
func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); w.add_child(sun)
	var we := WorldEnvironment.new(); we.environment = Environment.new(); we.environment.ambient_light_color = Color.WHITE; we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; we.environment.background_mode = Environment.BG_COLOR; we.environment.background_color = Color(0.3,0.4,0.5); w.add_child(we)
	MeshUtil.box(w, Vector3(1, 2, 0.05), Vector3(-2.5, 1, 0), Color.RED) # referencia 2 m
	var g := Eikon.new()
	g.data = load("res://resources/eikons/stone_golem.tres")
	g.preview = true
	w.add_child(g)
	await process_frame
	g.rotation.y = -0.6
	var cam := Camera3D.new(); w.add_child(cam); cam.look_at_from_position(Vector3(2, 3.5, -8), Vector3(0, 2.0, 0)); cam.current = true
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
