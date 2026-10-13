extends SceneTree
## Prueba automática: godot --headless --path . -s res://tests/test_combat.gd
## Ejercita espada, bloqueo, parry, arco e invocación usando acciones de entrada.

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	await physics_frame
	Input.action_release(action)

func _run() -> void:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9 # sin límite de tiempo de ronda durante la prueba
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	arena.ai.enabled = false
	await wait(0.3)
	e.global_position = p.global_position + p.facing * 2.8
	e.facing = -p.facing
	await wait(0.3)
	# Espada
	var h0 := e.health
	var m0 := p.meter
	await tap("attack_sword")
	await wait(0.8)
	check(e.health < h0, "espada daña al rival (%.0f -> %.0f)" % [h0, e.health])
	check(p.meter > m0, "medidor eikon del jugador sube (%.0f -> %.0f)" % [m0, p.meter])
	check(is_equal_approx(arena.hud.e_health.value, e.health), "HUD refleja vida del rival")
	# Bloqueo (el escudo solo bloquea; el parry es otra acción)
	Input.action_press("block")
	await wait(1.3)
	var ph := p.health
	e.sword()
	await wait(0.8)
	var blocked := ph - p.health
	Input.action_release("block")
	await wait(1.0)
	ph = p.health
	e.sword()
	await wait(0.8)
	var unblocked := ph - p.health
	check(unblocked > 0.0 and blocked < unblocked, "escudo reduce daño (bloq %.1f vs sin %.1f)" % [blocked, unblocked])
	# Parry (acción dedicada, ~0,2 s antes del impacto). Ronda 21: montado no hay parry.
	check(not p.parry(), "montado: sin parry")
	p.dismount(false)
	await wait(1.0)
	ph = p.health
	e.sword()
	await wait(0.25) # parry dedicado ~0,2 s antes del impacto (ventana 0,3 s)
	await tap("parry")
	await wait(0.6)
	check(e.stun > 0.0 and is_equal_approx(ph, p.health), "parry aturde al rival sin daño (stun %.2f)" % e.stun)
	p.owned_mount.global_position = p.global_position
	p.mount_on(p.owned_mount) # vuelve a montar para el resto (combate montado clásico)
	await wait(0.3)
	# Arco
	await wait(1.0)
	e.global_position = p.global_position + p.facing * 12.0
	await wait(0.3)
	h0 = e.health
	check(not p.shoot(), "con espada+escudo no se puede disparar")
	await tap("swap_weapon")
	await wait(2.1)
	check(p.loadout == Fighter.Loadout.BOW, "cambio a arco")
	await tap("attack_sword") # en modo arco, Atacar dispara
	await wait(1.0)
	check(e.health < h0, "flecha daña al rival (%.0f -> %.0f)" % [h0, e.health])
	await tap("swap_weapon")
	await wait(2.1)
	# Invocación
	p.eikon = load("res://resources/eikons/stone_golem.tres") # compañero (no montable); el fénix se monta: ver test_eikon_mount
	e.global_position = p.global_position + p.facing * 5.0
	p.meter = Fighter.METER_MAX
	await tap("summon")
	await wait(0.2)
	check(is_instance_valid(p.active_eikon), "eikon invocado (%s)" % (p.eikon.eikon_name))
	check(p.meter == 0.0, "medidor se vacía al invocar")
	h0 = e.health
	await wait(4.0)
	check(e.health < h0, "eikon daña al rival (%.0f -> %.0f)" % [h0, e.health])
	# El eikon es objetivo: el rival puede dañarlo
	if is_instance_valid(p.active_eikon):
		var eik: Eikon = p.active_eikon as Eikon
		var eh := eik.health
		eik.take_hit(10.0, e, "arrow")
		check(eik.health < eh, "eikon puede recibir daño")
	# --- Dash: daño, empuje e invulnerabilidad ---
	p.dismiss_eikon()
	await wait(1.2)
	e.global_position = p.global_position + p.facing * 6.0
	e.facing = -p.facing
	await wait(0.4)
	h0 = e.health
	var epos := e.global_position
	var shakes: Array[float] = []
	p.impact.connect(func(st: float) -> void: shakes.append(st))
	await tap("dash")
	var dodge: String = p.take_hit(5.0, e, "melee") if p.invuln > 0.0 else "none"
	await wait(0.5)
	check(dodge == "dodge", "dash da invulnerabilidad (i-frames)")
	check(e.health < h0, "dash golpea al rival (%.0f -> %.0f)" % [h0, e.health])
	check(e.global_position.distance_to(epos) > 1.5, "dash empuja al rival (%.1f m)" % e.global_position.distance_to(epos))
	check(shakes.size() > 0, "impacto del dash dispara temblor de cámara")
	# --- Lock-on ---
	await wait(0.5)
	var dist0 := MeshUtil.flat(e.global_position - p.global_position).length()
	Input.action_press("move_right")
	await wait(1.2)
	Input.action_release("move_right")
	var to_e := MeshUtil.flat(e.global_position - p.global_position)
	check(p.face_target == e, "lock-on activo por defecto")
	check(p.facing.dot(to_e.normalized()) > 0.9, "con lock-on el jugador mira al rival al rodearlo (dot %.2f)" % p.facing.dot(to_e.normalized()))
	check(absf(to_e.length() - dist0) < 4.0, "strafe mantiene la distancia (%.1f -> %.1f)" % [dist0, to_e.length()])
	await tap("lock_on")
	await physics_frame
	check(p.face_target == null, "Tab/Q desactiva el lock-on")
	# --- Marcha atrás (sin lock-on) ---
	e.global_position = p.global_position + p.facing * 15.0
	await wait(0.6)
	var f0 := p.facing
	var pos0 := p.global_position
	Input.action_press("move_back")
	await wait(1.0)
	Input.action_release("move_back")
	var moved := MeshUtil.flat(p.global_position - pos0)
	check(p.facing.dot(f0) > 0.95, "marcha atrás sin girar (dot %.2f)" % p.facing.dot(f0))
	check(moved.length() > 1.5 and moved.normalized().dot(-f0) > 0.9, "retrocede %.1f m" % moved.length())
	await tap("lock_on")
	# ================= Ronda 3: alcance, montar/desmontar, aguante =================
	var UP := Vector3.UP
	arena.ai.enabled = false
	arena.controller.lock_on = false
	p.dismiss_eikon()
	p.health = p.max_health
	e.health = e.max_health
	await wait(1.0)
	# --- Alcance montado: 3.2 m en el lateral ---
	e.global_position = p.global_position + p.facing.cross(UP) * 3.2
	e.facing = -p.facing
	await physics_frame
	check(p.in_sword_arc(e), "montado: rival a 3.2 m en el lateral dentro del arco")
	h0 = e.health
	var st0 := p.stamina
	await tap("attack_sword")
	await wait(0.8)
	check(e.health < h0, "espada montada alcanza 3.2 m lateral (%.0f -> %.0f)" % [h0, e.health])
	check(p.stamina < st0, "espada gasta aguante (%.0f -> %.0f)" % [st0, p.stamina])
	await wait(1.0)
	e.global_position = p.global_position + p.facing * 4.8
	await physics_frame
	h0 = e.health
	await tap("attack_sword")
	await wait(0.8)
	check(not p.in_sword_arc(e) and is_equal_approx(e.health, h0), "montado: 4.8 m queda fuera de alcance")
	# --- Desmontar ---
	await wait(1.0)
	var spd_mounted := p.stats().speed
	await tap("mount")
	await physics_frame
	var pm := p.owned_mount
	check(not p.mounted and pm.is_free(), "F desmonta; la montura queda libre")
	check(p.global_position.distance_to(pm.global_position) < Fighter.MOUNT_REACH, "la montura queda cerca")
	check(p.stats().speed < spd_mounted and p.stats().turn_speed > 3.2, "a pie: más lento y gira más cerrado")
	# --- Alcance a pie (rival también a pie) ---
	e.dismount()
	e.global_position = p.global_position + p.facing * 2.0
	e.facing = -p.facing
	await physics_frame
	check(p.in_sword_arc(e), "a pie: 2.0 m dentro del alcance")
	h0 = e.health
	await tap("attack_sword")
	await wait(0.8)
	check(e.health < h0, "espada a pie golpea a 2.0 m")
	e.global_position = p.global_position + p.facing * 3.2
	await physics_frame
	check(not p.in_sword_arc(e), "a pie: 3.2 m fuera de alcance")
	# --- Voltereta a pie ---
	await wait(0.6)
	st0 = p.stamina
	await tap("dash")
	check(p.is_rolling() and not p.mounted, "a pie el dash es una voltereta (con i-frames tras el arranque, ver test_roll)")
	check(st0 - p.stamina >= Fighter.COST_ROLL - 1.0, "voltereta gasta aguante")
	# --- Volver a montar ---
	await wait(0.5)
	p.global_position = pm.global_position + Vector3(1.5, 0, 0)
	await physics_frame
	while not p.can_mount_now(): # ronda 17: solo se sube estando libre
		await physics_frame
	await tap("mount")
	await physics_frame
	var mt := 0
	while not p.mounted and mt < 90: # ronda 17: si aún no está libre, el eikon lo monta al quedar libre
		await physics_frame
		mt += 1
	check(p.mounted and p.mount_node == pm, "F vuelve a montar cerca de la montura")
	while e.stun > 0.0:
		await physics_frame
	if not e.mounted and e.owned_mount.is_free():
		e.global_position = e.owned_mount.global_position + Vector3(1.0, 0, 0) # su caballo pasea: acercarlo de forma determinista
		await physics_frame
	check(e.toggle_mount(), "el rival vuelve a montar")
	# --- Derribo con dash ---
	await wait(0.5)
	e.global_position = p.global_position + p.facing * 6.0
	e.facing = -p.facing
	e.knockoff_chance_dash = 1.0
	p.stamina = Fighter.STAMINA_MAX
	await wait(0.5)
	await tap("dash")
	await wait(0.5)
	check(not e.mounted, "dash derriba al rival de su montura")
	e.knockoff_chance_dash = 0.5
	# --- La IA vuelve a montar ---
	p.global_position = Vector3(0, 0.2, 20)
	arena.ai.enabled = true
	var t_rm := 0.0
	while not e.mounted and t_rm < 6.0:
		await wait(0.2)
		t_rm += 0.2
	check(e.mounted, "la IA desmontada vuelve a montar (%.1f s)" % t_rm)
	# --- IA con poco aguante: pausa y luego vuelve ---
	p.health = p.max_health
	await wait(0.3)
	e.stamina = 10.0
	await wait(0.3)
	check(arena.ai.phase == AIController.Phase.REST, "IA con poco aguante pasa a descansar")
	var attacks := 0
	for i in 60:
		await physics_frame
		if e.is_attacking():
			attacks += 1
	check(attacks == 0, "IA no ataca mientras descansa")
	var t_back := 0.0
	while arena.ai.phase == AIController.Phase.REST and t_back < 8.0:
		await wait(0.2)
		t_back += 0.2
	check(arena.ai.phase != AIController.Phase.REST and e.stamina > 60.0, "IA recupera aguante y vuelve a luchar (%.1f s, fase %d, aguante %.0f)" % [t_back, arena.ai.phase, e.stamina])
	arena.ai.enabled = false
	# --- Aguante: bloqueo drena, regenera, agotamiento ---
	p.health = p.max_health
	e.global_position = p.global_position + Vector3(0, 0, -15)
	p.stamina = Fighter.STAMINA_MAX
	Input.action_press("block")
	await wait(1.0)
	Input.action_release("block")
	var after_block := p.stamina
	check(after_block < 99.5, "mantener escudo drena aguante (%.0f)" % after_block)
	await wait(1.5)
	check(p.stamina > after_block, "aguante se regenera (%.0f -> %.0f)" % [after_block, p.stamina])
	p.stamina = 4.0
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await wait(0.5)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	check(p.is_exhausted(), "galopar sin aguante -> agotado")
	check(not p.sword() and not p.dash(), "agotado: no puede atacar ni hacer dash")
	await wait(1.7)
	check(not p.is_exhausted(), "el agotamiento termina (~1.5 s)")
	arena.controller.lock_on = true
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(fails)
