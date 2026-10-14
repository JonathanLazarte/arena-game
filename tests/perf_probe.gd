extends SceneTree
## Rendimiento (Ronda 26): tiempo real entre pasos de física (wall clock), headless.
func _initialize() -> void:
	_run()
func sample(label: String, secs: float) -> void:
	var ds: Array[float] = []
	var ph := 0.0
	var last := Time.get_ticks_usec()
	var t := 0.0
	while t < secs:
		await physics_frame
		var now := Time.get_ticks_usec()
		ds.append((now - last) / 1000.0)
		ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		last = now
		t += 1.0 / 60.0
	var s := ds.duplicate(); s.sort()
	var avg := 0.0
	for d in ds: avg += d
	print("%-26s física %.3f ms | fotograma avg %.2f p99 %.2f max %.2f | nodos %d" % [label, ph / ds.size(), avg / ds.size(), s[int(s.size() * 0.99)], s[-1], Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
func _run() -> void:
	await process_frame
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 1
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame; await process_frame
	var arena: Arena = current_scene
	arena.time_left = 1e9
	await create_timer(3.5).timeout
	var p := arena.player; var e := arena.enemy
	p.health = 1e6; p.max_health = 1e6
	await sample("a pie, IA", 4.0)
	p.global_position = e.global_position + Vector3(0, 0, 4)
	await sample("cuerpo a cuerpo", 4.0)
	p.meter = Fighter.METER_MAX
	var t0 := Time.get_ticks_usec()
	p.summon()
	print("summon() jugador: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await sample("montado en eikon 0-2 s", 2.0)
	e.meter = Fighter.METER_MAX
	t0 = Time.get_ticks_usec()
	e.summon()
	print("summon() rival: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await sample("ambos eikons", 3.0)
	var mats := {}
	var mis := root.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in mis:
		if mi.material_override: mats[mi.material_override] = 1
		elif mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m = mi.get_active_material(si)
				if m: mats[m] = 1
	print("materiales únicos %d, MeshInstance3D %d, StaticBody3D %d, AudioStreamPlayer3D %d" % [mats.size(), mis.size(),
		root.find_children("*", "StaticBody3D", true, false).size(), root.find_children("*", "AudioStreamPlayer3D", true, false).size()])
	quit()
