extends SceneTree
## Capturas de pose de una habilidad en varios ticks (verificación visual de animaciones).
## DISPLAY=:3 godot --path . --rendering-driver opengl3 --resolution 480x480 -s res://tests/screenshot_pose.gd -- /tmp/pref golpe_fisura 10,30,45,80 [char_idx]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pref := args[0] if args.size() > 0 else "/tmp/pose"
	var id := args[1] if args.size() > 1 else "golpe_fisura"
	var ticks: Array = []
	for x in (args[2] if args.size() > 2 else "10,30,45,80").split(","):
		ticks.append(int(x))
	var ci := int(args[3]) if args.size() > 3 else 0
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
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	floor.mesh = pm
	floor.material_override = MeshUtil.mat(Color(0.32, 0.3, 0.27))
	world.add_child(floor)
	var A := Fighter.new(); A.eikon = load(Catalog.EIKONS["fenix"])
	A.character = Catalog.characters()[ci]
	A.set_boss_abilities([id]); world.add_child(A)
	var B := Fighter.new(); B.eikon = load(Catalog.EIKONS["lobo"]); world.add_child(B)
	await process_frame
	var P := SimParams.bake(A, B)
	var e := FightEngine.new(P, 3, true); e.gap_um = 5000000
	var s := e.initial()
	var view := SimView.new(A, B, world)
	view.params = P
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 45
	var last: int = ticks.max()
	for t in 30 + last + 1:
		e.step(s, FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 30 else 0), FightSim.IN_LOCK)
		view.apply(s)
		await physics_frame
		var k := t - 30
		if k in ticks:
			var p := A.global_position
			var side := A.facing.cross(Vector3.UP)
			cam.global_position = p + side * 4.0 + Vector3(0, 2.2 + A._kv.model.position.y, 0) + A.facing * 1.5
			cam.look_at(p + Vector3(0, 1.0 + A._kv.model.position.y, 0))
			await process_frame
			await process_frame
			var fn := "%s_%s_%03d.png" % [pref, id, k]
			root.get_viewport().get_texture().get_image().save_png(fn)
			print("saved ", fn, " state=", A._kv.state, " clip=", A._kv._ab_smp.get("clip", ""), " step=", A.ab_fired, " w=", A._kv._weight, " bp=", A._kv.tree.get("parameters/loco/blend_position"), " cur=", A._kv.playback.get_current_node(), " fade=", A._kv.playback.get_fading_from_node(), " vel=", A.planar_vel, " st=", A.state if "state" in A else "")
	quit()
