extends SceneTree
## Captura de los efectos de habilidad (SimAbilityFx) en una escena mínima.
## DISPLAY=:3 godot --path . --rendering-driver opengl3 -s res://tests/screenshot_ability_fx.gd -- out.png carga_area 40
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/abfx.png"
	var id := args[1] if args.size() > 1 else "carga_area"
	var at := int(args[2]) if args.size() > 2 else 40
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	floor.mesh = pm
	floor.material_override = MeshUtil.mat(Color(0.32, 0.3, 0.27))
	world.add_child(floor)
	var A := Fighter.new(); A.eikon = load(Catalog.EIKONS["fenix"]); A.set_boss_abilities([id]); world.add_child(A)
	var B := Fighter.new(); B.eikon = load(Catalog.EIKONS["lobo"]); world.add_child(B)
	await process_frame
	var P := SimParams.bake(A, B)
	var e := FightEngine.new(P, 3, true); e.gap_um = 5000000
	var s := e.initial()
	var view := SimView.new(A, B, world)
	view.params = P
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(7, 7, 9)
	cam.look_at(Vector3(0, 0.5, 0))
	for t in 30 + at:
		e.step(s, FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 30 else 0), FightSim.IN_LOCK)
		view.apply(s)
		await physics_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
