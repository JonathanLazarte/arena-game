extends SceneTree
## Ronda 15: cambio de arma rápido (sin bloquear el movimiento) y correr a pie fijado
## (strafe estilo souls: no se da la vuelta). godot --headless --path . -s res://tests/test_run_swap.gd

var fails: int = 0
var arena: Arena
var p: Fighter
var e: Fighter

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _place() -> void:
	p.move_input = Vector3.ZERO
	p.want_sprint = false
	await wait(0.4)
	p.global_position = Vector3(0, 0, 8)
	p.facing = Vector3.FORWARD
	p.planar_vel = Vector3.ZERO
	p.stamina = p.stamina_max
	p.exhausted = 0.0
	e.global_position = Vector3(0, 0, 0)
	e.move_input = Vector3.ZERO
	await physics_frame

func _to_target() -> Vector3:
	return MeshUtil.flat(e.global_position - p.global_position).normalized()

func _run() -> void:
	seed(15)
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	p = arena.player
	e = arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
	await wait(1.0)
	# --- 1. Cambio de arma: 0,35–0,5 s ---
	check(Fighter.SWAP_TIME >= 0.35 and Fighter.SWAP_TIME <= 0.5, "tiempo de cambio %.2f s (0,35–0,5)" % Fighter.SWAP_TIME)
	await _place()
	p.face_target = null
	# referencia: distancia caminando sin cambiar de arma
	p.move_input = Vector3.RIGHT
	var x0 := p.global_position
	await wait(0.6)
	var ref := MeshUtil.flat(p.global_position - x0).length()
	# ahora caminando mientras cambia
	x0 = p.global_position
	var l0 := p.loadout
	check(p.swap_loadout(), "empieza el cambio caminando")
	var frames := 0
	var still := 0
	var blocked := true
	var saw_swap_anim := false
	var min_k := 1.0
	var max_k := 0.0
	var vis_switches := 0
	var prev_vis: bool = p._bow.visible
	p.want_block = true
	while p.is_swapping():
		await physics_frame
		frames += 1
		if MeshUtil.flat(p.velocity).length() < 0.5:
			still += 1
		if p.is_swapping() and (p.attack_light() or p.shoot() or p.blocking):
			blocked = false
		if p._kv.state == "swap":
			saw_swap_anim = true
		min_k = minf(min_k, p._kv._swap_k)
		max_k = maxf(max_k, p._kv._swap_k)
		if p._bow.visible != prev_vis:
			vis_switches += 1
			prev_vis = p._bow.visible
	p.want_block = false
	var secs := frames / 60.0
	check(secs >= 0.33 and secs <= 0.52, "el cambio dura %.2f s" % secs)
	check(p.loadout != l0, "arma cambiada al terminar")
	check(still <= 1, "el movimiento nunca se bloquea durante el cambio (%d frames parado)" % still)
	await wait(0.6 - secs)
	var moved := MeshUtil.flat(p.global_position - x0).length()
	check(moved >= ref * 0.9, "recorre lo mismo cambiando que sin cambiar (%.2f vs %.2f m)" % [moved, ref])
	check(blocked, "durante el cambio no se ataca, dispara ni bloquea")
	check(saw_swap_anim, "animación de desenfundar/enfundar (tren superior) durante el cambio")
	check(min_k < 0.3 and max_k > 0.7 and vis_switches == 1, "transición suave: el arma encoge y crece (k %.2f–%.2f), un único cambio de malla" % [min_k, max_k])
	check(is_equal_approx(p._kv._swap_k, 1.0) or p._kv._swap_k > 0.95, "al terminar el arma vuelve a su tamaño")
	p.move_input = Vector3.ZERO
	# La IA usa el mismo cambio rápido
	arena.ai.set_physics_process(false)
	e.move_input = Vector3.LEFT
	var ex := e.global_position
	check(e.swap_loadout(), "la IA también cambia")
	var ef := 0
	while e.is_swapping():
		await physics_frame
		ef += 1
	check(ef / 60.0 <= 0.52 and MeshUtil.flat(e.global_position - ex).length() > 1.0, "IA: cambio rápido (%.2f s) moviéndose" % (ef / 60.0))
	e.move_input = Vector3.ZERO
	if e.loadout != Fighter.Loadout.SWORD_SHIELD: e.swap_loadout()
	if p.loadout != Fighter.Loadout.SWORD_SHIELD: p.swap_loadout()
	await wait(0.6)
	# --- 2. Ronda 16: correr fijado hacia atrás = se gira y corre de cara (hacia la cámara) ---
	check(is_equal_approx(Fighter.RUN_TURN_DEG, 110.0), "umbral de giro corriendo fijado: 110°")
	await _place()
	p.face_target = e
	p.move_input = Vector3.BACK # alejarse del rival (está en -Z)
	p.want_sprint = true
	var spr := 0
	x0 = p.global_position
	for i in 60:
		await physics_frame
		if p.sprinting:
			spr += 1
	var run_back := MeshUtil.flat(p.global_position - x0).length()
	var bp: Vector2 = p._kv.tree.get("parameters/loco/blend_position")
	check(p.facing.dot(Vector3.BACK) > 0.95 and p.facing.dot(_to_target()) < -0.9, "corriendo hacia atrás fijado se da la vuelta y mira hacia donde corre (cámara)")
	check(spr > 50 and not p.reversing, "corre de verdad hacia delante (sprint %d/60), sin correr de espaldas" % spr)
	check(bp.y > 0.9, "locomoción de carrera hacia delante (blend y %.2f)" % bp.y)
	check(p.face_target == e, "el fijado se mantiene mientras huye")
	# diagonal atrás (135° > 110°): también se gira
	await _place()
	p.face_target = e
	p.move_input = (Vector3.BACK + Vector3.RIGHT).normalized()
	p.want_sprint = true
	await wait(0.5)
	check(p.facing.dot(p.move_input) > 0.9, "diagonal hacia atrás (135°): corre de cara hacia allí")
	# lateral puro (90° < 110°): strafe mirando al rival
	await _place()
	p.face_target = e
	p.move_input = Vector3.RIGHT
	p.want_sprint = true
	var face_ok := true
	var lat := 0.0
	for i in 45:
		p.move_input = _to_target().cross(Vector3.UP) # como el control: relativo al rival
		await physics_frame
		if p.facing.dot(_to_target()) < 0.9:
			face_ok = false
		lat = maxf(lat, (p._kv.tree.get("parameters/loco/blend_position") as Vector2).x)
	check(face_ok and p.sprinting, "corriendo de lado fijado: strafe encarado al rival")
	check(lat > 0.6, "mezcla con el strafe lateral (blend x %.2f)" % lat)
	# diagonal adelante: strafe encarado
	await _place()
	p.face_target = e
	p.move_input = (Vector3.FORWARD + Vector3.LEFT).normalized()
	p.want_sprint = true
	face_ok = true
	for i in 30:
		p.move_input = (_to_target() - _to_target().cross(Vector3.UP)).normalized()
		await physics_frame
		if p.facing.dot(_to_target()) < 0.9:
			face_ok = false
	check(face_ok and p.sprinting, "diagonal adelante fijado: sigue encarado")
	# caminar hacia atrás fijado: retrocede mirando al rival
	await _place()
	p.face_target = e
	p.move_input = Vector3.BACK
	x0 = p.global_position
	face_ok = true
	for i in 60:
		await physics_frame
		if p.facing.dot(_to_target()) < 0.95:
			face_ok = false
	var walk_back := MeshUtil.flat(p.global_position - x0).length()
	check(face_ok and p.global_position.z > x0.z + 0.5, "caminando hacia atrás fijado retrocede encarado al rival (%.2f m)" % walk_back)
	check(run_back > walk_back * 1.2, "correr es más rápido que retroceder (%.2f vs %.2f)" % [run_back, walk_back])
	# --- 3. Sin fijar: correr gira al personaje ---
	await _place()
	p.face_target = null
	p.move_input = Vector3.BACK
	p.want_sprint = true
	await wait(0.6)
	check(p.facing.dot(Vector3.BACK) > 0.9 and p.sprinting and not p.reversing, "sin fijar, correr hacia atrás da la vuelta (mira hacia donde corre)")
	# Ronda 25: a pie, sin fijar, caminar hacia atrás también gira (cámara orbital; arreglo diagonal atrás)
	await _place()
	p.face_target = null
	p.move_input = Vector3.BACK
	await wait(0.6)
	check(not p.reversing and p.facing.dot(Vector3.BACK) > 0.9, "sin correr, sin fijar, a pie: se gira hacia atrás (Ronda 25)")
	# --- 4. Gasta aguante y se detiene al agotarse ---
	await _place()
	p.face_target = e
	p.move_input = Vector3.BACK
	p.want_sprint = true
	p.stamina = 6.0
	var st0 := p.stamina
	await wait(0.15)
	check(p.stamina < st0, "correr gasta aguante")
	await wait(0.4)
	check(p.exhausted > 0.0 and not p.sprinting, "agotado: deja de correr")
	p.want_sprint = false
	# --- 5. Botón/tecla «Correr» alterna (controlador) ---
	await _place()
	arena.controller.set_physics_process(true)
	arena.controller.lock_on = true
	Input.action_press("run_toggle")
	await physics_frame
	await physics_frame
	Input.action_release("run_toggle")
	Input.action_press("move_back")
	await wait(0.5)
	check(arena.controller.run_toggled and p.want_sprint and p.sprinting, "«Correr» activa la carrera sin mantener nada")
	check(p.facing.dot(_to_target()) < -0.9, "con el control real, corriendo hacia atrás se gira hacia la cámara")
	check(arena.hud._run_label.text.begins_with("Correr"), "botón táctil «Correr» a pie (%s)" % arena.hud._run_label.text)
	Input.action_press("run_toggle")
	await physics_frame
	await physics_frame
	Input.action_release("run_toggle")
	await wait(0.2)
	check(not arena.controller.run_toggled and not p.sprinting, "volver a pulsar lo desactiva")
	Input.action_release("move_back")
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
