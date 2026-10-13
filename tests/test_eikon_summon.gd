extends SceneTree
## Ronda 9: "el eikon (fénix) no funciona". Recorre todo el camino: medidor, entrada
## (teclado E y botón táctil Eikon), aparición, ataques contra un rival que se mueve.
## godot --headless --path . -s res://tests/test_eikon_summon.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _run() -> void:
	seed(4)
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	var p := arena.player
	var e := arena.enemy
	e.max_health = 5000.0
	e.health = 5000.0
	check(p.eikon != null and p.eikon.eikon_name == "Fénix", "el jugador tiene el fénix")
	# --- Medidor ---
	await wait(0.5)
	var m0 := p.meter
	await wait(3.0)
	check(p.meter - m0 > 2.5, "el medidor sube solo en combate (+%.1f en 3 s)" % (p.meter - m0))
	p.meter = 70.0
	arena.start_round()
	await physics_frame
	check(p.meter >= 70.0, "el medidor se conserva entre rondas (%.0f)" % p.meter)
	# --- Pulsar E sin medidor lleno: aviso en el HUD (antes no pasaba nada) ---
	var fails_seen := []
	p.summon_failed.connect(func(r: String) -> void: fails_seen.append(r))
	_key(KEY_E, true)
	await physics_frame
	await physics_frame
	_key(KEY_E, false)
	await physics_frame
	check(fails_seen.has("meter") and arena.hud.message.text.contains("Eikon"), "E con el medidor a medias avisa: '%s'" % arena.hud.message.text)
	check(not is_instance_valid(p.active_eikon), "sin medidor lleno no invoca")
	# --- Teclado: E con el medidor lleno ---
	p.meter = Fighter.METER_MAX
	await physics_frame
	_key(KEY_E, true)
	await physics_frame
	await physics_frame
	_key(KEY_E, false)
	await physics_frame
	check(is_instance_valid(p.active_eikon), "tecla E invoca al fénix")
	check(p.meter < 1.0, "el medidor se vacía al invocar")
	var ek := p.active_eikon as Mount
	check(is_instance_valid(ek) and p.mounted and p.mount_node == ek and ek.is_flying(), "ronda 14: el fénix aparece ensillado y el jugador lo monta")
	if is_instance_valid(ek):
		p.dismiss_eikon()
	await physics_frame
	# --- Botón táctil Eikon (móvil) ---
	var btn: TouchScreenButton = null
	for n in arena.hud.find_children("*", "TouchScreenButton", true, false):
		if (n as TouchScreenButton).action == "summon":
			btn = n
	check(btn != null, "existe el botón táctil Eikon ligado a la acción summon")
	p.meter = Fighter.METER_MAX
	await physics_frame
	if btn:
		# Sin pantalla (headless) el viewport mide 0x0 y no se pueden simular toques reales;
		# el TouchScreenButton hace exactamente esto al pulsarse: Input.action_press(action).
		# (Con xvfb se comprobó que un InputEventScreenTouch en (1050, 500) lo pulsa.)
		check(btn.visibility_mode == TouchScreenButton.VISIBILITY_ALWAYS and btn.is_visible_in_tree() and (btn.shape as CircleShape2D).radius >= 40.0, "botón Eikon visible y de buen tamaño")
		Input.action_press(btn.action)
		await physics_frame
		await physics_frame
		Input.action_release(btn.action)
		await physics_frame
	check(is_instance_valid(p.active_eikon), "el botón táctil invoca al fénix")
	# --- Ataques contra un rival que se mueve (IA activa) ---
	arena.ai.enabled = true
	var h0 := e.health
	var bolts := [0]
	var fire := [false]
	for i in 600:
		await physics_frame
		if i % 20 == 0:
			p.summon() # montado en el fénix: E = Llamarada
		for pr in get_nodes_in_group("projectile"):
			var proj := pr as Projectile
			if proj.kind == "eikon" and not proj.has_meta("seen"):
				proj.set_meta("seen", true)
				bolts[0] += 1
				fire[0] = fire[0] or proj.get_child_count() >= 2
		if not is_instance_valid(p.active_eikon):
			break
	var dealt := h0 - e.health
	check(bolts[0] >= 5, "el fénix montado lanza bolas de fuego (Llamarada, %d)" % bolts[0])
	check(fire[0], "las bolas de fuego tienen núcleo y estela visibles")
	check(dealt >= 9.0, "daña al rival en movimiento (%.0f en 10 s)" % dealt)
	# --- Reiniciar la partida sí vacía el medidor ---
	p.meter = 80.0
	arena.restart_match()
	await physics_frame
	check(p.meter < 1.0, "reiniciar la partida vacía el medidor")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
