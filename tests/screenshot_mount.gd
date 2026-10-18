extends SceneTree
## Captura del jinete montado (verificación visual de la postura sentada y la altura de la silla).
## DISPLAY=:3 godot --path . --rendering-driver opengl3 --resolution 640x360 -s res://tests/screenshot_mount.gd -- /tmp/pref lobo [char_idx] [ticks_idle]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pref := args[0] if args.size() > 0 else "/tmp/mount"
	var ek := args[1] if args.size() > 1 else "lobo"
	var ci := int(args[2]) if args.size() > 2 else 0
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var A := Fighter.new()
	A.eikon = load(Catalog.EIKONS[ek])
	A.character = Catalog.characters()[ci]
	world.add_child(A)
	var B := Fighter.new()
	B.eikon = load(Catalog.EIKONS["fenix" if ek != "fenix" else "lobo"])
	world.add_child(B)
	await process_frame
	var P := SimParams.bake(A, B)
	var e := FightEngine.new(P, 5, true)
	e.gap_um = 6000000
	var s := e.initial()
	s[FightSim.METER] = FightSim.METER_MAX
	var view := SimView.new(A, B, world)
	view.params = P
	var mv := int(args[4]) if args.size() > 4 else 0 ## bits de entrada extra (p. ej. avanzar) tras montar
	for t in 70:
		e.step(s, FightSim.IN_EIKON if t == 0 else (mv if t > 30 else 0), 0)
		view.apply(s)
		await physics_frame
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40
	var p := A.global_position
	var side := A.facing.cross(Vector3.UP)
	var view_dir: Vector3 = A.facing if args.size() > 3 and args[3] == "front" else side
	var hy := A._rider_root.global_position.y
	cam.global_position = Vector3(p.x, 0, p.z) + view_dir * 6.5 + Vector3(0, hy + 0.4, 0)
	cam.look_at(Vector3(p.x, hy - 0.2, p.z))
	await process_frame
	await process_frame
	var fn := "%s_%s%s.png" % [pref, ek, "_" + args[3] if args.size() > 3 else ""]
	root.get_viewport().get_texture().get_image().save_png(fn)
	var sk := A._kv.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hips"))
	print("saved ", fn, " mounted=", A.mounted, " state=", A._kv.state, " base=", A._kv.tree.get("parameters/base/current_state"), " w=", A._kv._weight,
		" model_y=", A._kv.model.position.y, " hips_y=", hips.origin.y, " seat_y=", A.mount_node.saddle_position().y if A.mount_node and A.mount_node.has_method("saddle_position") else -1.0,
		" rider_root=", A._rider_root.global_position.y, " riding=", A._kv.riding.amount, " seat_top=", A.mount_node.seat_top, " seat_fix=", A.mount_node.seat_fix)
	for bn in ["hips", "upperleg.l", "lowerleg.l", "foot.l", "lowerleg.r"]:
		var bt := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn))
		print("  ", bn, " ", (bt.origin - A.global_position).snappedf(0.01))
	var mn: Node3D = A.mount_node
	for mi in mn.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		print("  mount mesh ", mi.name, " ", AABB(bb.position - A.global_position, bb.size))
	print("  knee_gap ", A._kv.riding.knee_gap)
	A._kv.riding.active = false
	for i in 4: await physics_frame
	await process_frame
	for bn in ["upperleg.l", "lowerleg.l", "foot.l"]:
		var bt2 := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn))
		print("  sin RidingPose ", bn, " ", (bt2.origin - A.global_position).snappedf(0.01))
	if args.size() > 5:
		root.get_viewport().get_texture().get_image().save_png(args[5])
	quit()
