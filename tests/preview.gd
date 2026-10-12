extends SceneTree
## Vista previa de un modelo: -- <glb> <escala> <rotX_grados> <png>
func _initialize() -> void:
	_run()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var w := Node3D.new()
	root.add_child(w)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); w.add_child(sun)
	var we := WorldEnvironment.new(); we.environment = Environment.new(); we.environment.ambient_light_color = Color.WHITE; we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; we.environment.background_mode = Environment.BG_COLOR; we.environment.background_color = Color(0.3,0.4,0.5); w.add_child(we)
	MeshUtil.box(w, Vector3(1, 2, 0.05), Vector3(-2, 1, 0), Color.RED) # referencia 2 m
	MeshUtil.box(w, Vector3(0.05, 0.05, 1.0), Vector3(0, 0.02, -2), Color.BLUE) # -Z
	var m := (load(a[0]) as PackedScene).instantiate() as Node3D
	m.basis = Basis(Vector3.RIGHT, deg_to_rad(float(a[2]))) * Basis.from_scale(Vector3.ONE * float(a[1]))
	w.add_child(m)
	var cam := Camera3D.new(); w.add_child(cam); cam.look_at_from_position(Vector3(7, 3, 2), Vector3(0, 1, 0)); cam.current = true
	for i in 10: await process_frame
	root.get_viewport().get_texture().get_image().save_png(a[3])
	quit()
