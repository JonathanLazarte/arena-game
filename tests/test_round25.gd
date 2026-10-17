extends SceneTree
## Ronda 25: 8 direcciones (a pie / montado, fijado / libre), cámara orbital, Estocada de jefe
## (jugador e IA) y paso adelante de los ataques con magnetismo.
## godot --headless --path . -s res://tests/test_round25.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func until(cond: Callable, max_t: float = 3.0) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await physics_frame
		t += 1.0 / 60.0
	return cond.call()

const DIRS := {"W": ["move_forward"], "S": ["move_back"], "A": ["move_left"], "D": ["move_right"],
	"W+A": ["move_forward", "move_left"], "W+D": ["move_forward", "move_right"],
	"S+A": ["move_back", "move_left"], "S+D": ["move_back", "move_right"]}

func expected(arena: Arena, keys: Array) -> Vector3:
	var p := arena.player
	var fwd: Vector3
	if is_instance_valid(p.face_target):
		fwd = MeshUtil.flat(p.face_target.global_position - p.global_position).normalized()
	else:
		fwd = MeshUtil.flat(-arena.camera.global_transform.basis.z).normalized()
	var right := fwd.cross(Vector3.UP)
	var v := Vector2.ZERO
	for k: String in keys:
		match k:
			"move_forward": v.y -= 1.0
			"move_back": v.y += 1.0
			"move_left": v.x -= 1.0
			"move_right": v.x += 1.0
	v = v.normalized()
	return (right * v.x + fwd * -v.y).normalized()

func dirs_test(arena: Arena, label: String, run: bool) -> void:
	var p := arena.player
	var ok_all := true
	var bad := []
	for name: String in DIRS:
		p.global_position = Vector3(0, 0.2, 0) if not p.mounted else Vector3(0, 0.2, 0)
		p.planar_vel = Vector3.ZERO
		if p.mounted and p.mount_node:
			p.mount_node.global_position = p.global_position
		await physics_frame
		arena.rig.orbit(Vector2.ZERO)
		var exp_d := expected(arena, DIRS[name])
		for k: String in DIRS[name]:
			Input.action_press(k)
		if run:
			Input.action_press("sprint")
		p.stamina = p.stamina_max
		await create_timer(2.0 if p.mounted else 0.7).timeout
		var p0 := p.global_position
		await create_timer(0.3).timeout
		var mv := MeshUtil.flat(p.global_position - p0)
		var spr := p.sprinting
		for k: String in DIRS[name]:
			Input.action_release(k)
		Input.action_release("sprint")
		var good := mv.length() > 0.4 and mv.normalized().dot(exp_d) > (0.7 if p.mounted else 0.8) and (spr or not run)
		if not good:
			bad.append("%s(%.2f,%.2f,%s)" % [name, mv.length(), mv.normalized().dot(exp_d), spr])
		ok_all = ok_all and good
		await create_timer(0.25).timeout
	check(ok_all, "%s: las 8 direcciones %s %s" % [label, "corriendo" if run else "andando", " ".join(bad)])

func _run() -> void:
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 
	await process_frame
	var au := root.get_node("Audio")
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	var p := arena.player
	var e := arena.enemy
	var c := arena.controller
	var rig := arena.rig
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 1. Direcciones ---
	await physics_frame
	await physics_frame
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 2. Cámara ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Movimiento relativo a la cámara después de orbitar
	var exp_w := expected(arena, ["move_forward"])
	# Colisión con un pilar
	var pivot := Vector3(0, 2, 0)
	var want := pivot + Vector3(0, 0, 9)
	var free := rig._collide(pivot, want)
	rig.obstacles.append(Vector3(pivot.x, 1.5, pivot.z + 4.0))
	var hit := rig._collide(pivot, want)
	rig.obstacles.pop_back()
	check(free.distance_to(want) < 0.1 and hit.distance_to(pivot) < 3.0, "un pilar en medio acerca la cámara (%.1f m)" % hit.distance_to(pivot))
	check(rig._collide(Vector3(40, 2, 0), Vector3(50, 2, 0)).x < CameraRig.new().arena_radius, "no atraviesa el muro")
	check(not rig._touch_ok(Vector2(100, 400)), "Android: la mitad izquierda no orbita (joystick)")
	var bpos: Vector2 = arena.hud.btns["attack_sword"].global_position
	check(not rig._touch_ok(bpos), "Android: sobre un botón no orbita")
	check(rig._touch_ok(Vector2(1000, 120)), "Android: mitad derecha libre orbita")
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Lock-on: la cámara sigue al objetivo; tirón cambia de objetivo
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 3. Estocada de jefe ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Ronda 31: la embestida corrige la dirección: el paso lateral ya no basta (solo la volteret
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Impacto
	await physics_frame
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 4. IA: esquiva y usa la Estocada de jefe ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 5. Paso de ataque + magnetismo ---
	quit(1 if fails > 0 else 0)