extends SceneTree
## Pose de clips sueltos (clip@tiempo) sobre el personaje, para revisar el reapuntado.
## DISPLAY=:3 godot --path . --rendering-driver opengl3 --resolution 400x400 -s res://tests/screenshot_clips.gd -- /tmp/pref "xh/attack1@0.75,mx/roll_f@0.5" [yaw_deg] [char_idx]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pref := args[0]
	var items := args[1].split(",")
	var yaw := float(args[2]) if args.size() > 2 else 35.0
	var ci := int(args[3]) if args.size() > 3 else 0
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var A := Fighter.new()
	A.character = Catalog.characters()[ci]
	world.add_child(A)
	await process_frame
	var kv: KnightVisual = A._kv
	kv.tree.active = false
	# bibliotecas extra para comparar antes/después: OLD_LIBS=pref=ruta,... (variable de entorno)
	for spec in OS.get_environment("OLD_LIBS").split(",", false):
		var kv2 := spec.split("=")
		if kv2.size() == 2 and not kv.ap.has_animation_library(StringName(kv2[0])):
			kv.ap.add_animation_library(StringName(kv2[0]), load(kv2[1]))
	for pre: String in {"dl1": "doublel_one_hand", "dlc": "doublel_common", "xk": "explosive_knight", "xh": "explosive_hammer", "xn": "explosive_ninja", "xs": "explosive_swordsman"}:
		var nm: String = {"dl1": "doublel_one_hand", "dlc": "doublel_common", "xk": "explosive_knight", "xh": "explosive_hammer", "xn": "explosive_ninja", "xs": "explosive_swordsman"}[pre]
		if not kv.ap.has_animation_library(StringName(pre)):
			kv.ap.add_animation_library(StringName(pre), load("res://assets/animations/%s.res" % nm))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 34
	var y := deg_to_rad(yaw)
	cam.global_position = Vector3(sin(y) * 4.8, 1.0, cos(y) * 4.8)
	cam.look_at(Vector3(0, 0.62, 0))
	var i := 0
	for it: String in items:
		var parts := it.split("@")
		var clip := parts[0]
		var t := float(parts[1]) if parts.size() > 1 else 0.0
		kv.ap.play(clip)
		kv.ap.seek(t, true)
		kv.ap.pause()
		await process_frame
		await process_frame
		var fn := "%s_%02d.png" % [pref, i]
		root.get_viewport().get_texture().get_image().save_png(fn)
		print("saved ", fn, " ", clip, "@", t, " has=", kv.ap.has_animation(clip))
		i += 1
	quit()
