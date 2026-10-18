extends SceneTree
## Distancia efectiva de la cámara en la arena real (sin pantalla): imprime, durante unos segundos
## de combate, la distancia cámara→pivote, cámara→jugador y la distancia entre luchadores.
## godot --headless --path . -s res://tests/print_camera.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	var t := 0.0
	var samples := 0
	var acc := 0.0
	while t < 14.0:
		await physics_frame
		t += 1.0 / 60.0
		var cam: Camera3D = arena.camera
		var p: Fighter = arena.player
		var e: Fighter = arena.enemy
		if cam == null or p == null or e == null or arena.state != "fight":
			continue
		var dl := MeshUtil.flat(e.global_position - p.global_position).length()
		var pivot := p.global_position + Vector3(0, 2.0, 0)
		var dcp := cam.global_position.distance_to(p.global_position + Vector3(0, 1.0, 0))
		if fmod(t, 1.0) < 1.0 / 60.0:
			print("t=%.1f lock=%s rivales=%.1f m  cámara→pivote %.2f m  cámara→jugador %.2f m  fov %.0f" % [t, is_instance_valid(p.face_target), dl, cam.global_position.distance_to(pivot), dcp, cam.fov])
		if dl < 9.0:
			acc += dcp
			samples += 1
	print("CAM_DIST medio a <9 m del rival: %.2f m (%d muestras)" % [acc / maxf(samples, 1), samples])
	print("CameraRig: DIST=%s LOCK=%s+%s·d≤%s" % [CameraRig.DIST, CameraRig.LOCK_DIST, CameraRig.LOCK_DIST_K, CameraRig.LOCK_DIST_EXTRA] if "LOCK_DIST" in CameraRig else "CameraRig: DIST=%s" % CameraRig.DIST)
	quit()
