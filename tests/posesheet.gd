extends SceneTree
## Ronda 28: hoja de poses de los clips Mixamo reapuntados al Knight (KayKit), para revisarlos a ojo.
## godot --path . -s res://tests/posesheet.gd -- clip1,clip2,... frac1,frac2,... out.png
func _initialize() -> void:
	_run()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var clips: PackedStringArray = args[0].split(",")
	var fracs: PackedStringArray = args[1].split(",")
	var outp: String = args[2]
	var lib := load("res://assets/animations/mixamo/lib_kaykit.res") as AnimationLibrary
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.25, 0.27, 0.32)
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.6
	w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); w.add_child(sun)
	var cols := fracs.size()
	for r in clips.size():
		for c in cols:
			var m: Node3D = (load("res://assets/models/Knight.glb") as PackedScene).instantiate()
			w.add_child(m)
			m.position = Vector3(c * 1.6, -r * 2.4, 0)
			m.rotation.y = deg_to_rad(20)
			var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var name := clips[r]
			if lib.has_animation(name):
				ap.add_animation_library("mx", lib)
				name = "mx/" + name
			ap.play(name)
			ap.seek(ap.current_animation_length * float(fracs[c]), true)
			ap.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(clips.size() * 2.4, cols * 1.6 * 0.6)
	cam.position = Vector3((cols - 1) * 0.8, -(clips.size() - 1) * 1.2 + 1.0, 10)
	w.add_child(cam)
	var c_px := 320
	var r_px := 420
	root.size = Vector2i(cols * 160, clips.size() * 240)
	for i in 6: await process_frame
	root.get_texture().get_image().save_png(outp)
	quit()
