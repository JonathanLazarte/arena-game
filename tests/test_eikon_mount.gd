extends SceneTree
## Ronda 14: eikons = monturas. Reglas de montar, especiales, duración y compañero no montable.
## godot --headless --path . -s res://tests/test_eikon_mount.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	seed(3)
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	var p := arena.player
	var e := arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
	await wait(0.4)
	check(not p.mounted and not e.mounted, "el combate empieza a pie")
	check(get_nodes_in_group("mount").is_empty(), "no hay monturas en la arena al empezar")
	check(not p.toggle_mount(), "sin eikon invocado no hay nada que montar")
	# --- Fénix: montable y vuela ---
	check(p.eikon.id == "fenix" and p.eikon.rideable, "el fénix es montable")
	check(not p.summon(), "sin medidor no se invoca")
	p.meter = Fighter.METER_MAX
	check(p.summon(), "medidor lleno: invoca")
	var m := p.active_eikon as Mount
	check(m != null and p.mounted and p.mount_node == m and m.owner_fighter == p and m.eikon == p.eikon, "aparece ensillado y lo monta al instante")
	check(is_equal_approx(p.stats().speed, p.eikon.ride.speed) and p.stats().mount_name == "Fénix", "usa las estadísticas de montura del eikon (vel %.1f)" % p.stats().speed)
	check(not p.is_grounded() and m.is_flying(), "en el fénix se vuela (no toca el suelo)")
	check(not p.jump(), "en el fénix no se salta (ya vuela)")
	await wait(0.3)
	check(p._kv.riding.amount > 0.5 and p._rider_root.global_position.y > 1.5, "postura de montar sobre el fénix (altura %.2f)" % p._rider_root.global_position.y)
	# Especial montado: E
	var n0 := get_nodes_in_group("projectile").size()
	check(p.summon() and p.eikon_specials == 1, "E montado = especial (Llamarada)")
	await physics_frame
	var bolt: Projectile = null
	for pr in get_nodes_in_group("projectile"):
		bolt = pr as Projectile
	check(bolt != null and get_nodes_in_group("projectile").size() > n0 and bolt.kind == "eikon" and bolt.aimed_at == e, "la Llamarada es un proyectil de eikon apuntado al rival")
	check(not p.summon(), "especial en enfriamiento")
	# Bajar / subir. Solo el dueño puede montarlo.
	check(p.toggle_mount() and not p.mounted and m.is_free(), "F baja del eikon y queda libre")
	e.global_position = m.global_position + Vector3(1.0, 0, 0)
	await physics_frame
	check(not e.mount_on(m) and e.nearest_free_mount() != m and not e.can_remount(), "el rival NO puede montar tu eikon")
	check(p.summon() == false, "a pie con el eikon activo: E no invoca otro")
	p.global_position = m.global_position + Vector3(-1.0, 0, 0)
	await physics_frame
	check(p.toggle_mount() and p.mounted and p.mount_node == m, "F vuelve a montar tu eikon")
	# Duración: al acabarse te baja (sin derribo) y desaparece
	m.life = 0.05
	await wait(0.2)
	check(not p.mounted and not is_instance_valid(m) and p.active_eikon == null and p.stun <= 0.0, "al acabar la invocación te baja sin aturdir y desaparece")
	check(not p.toggle_mount(), "ya no hay montura")
	# --- Lobo de Hielo: montable, brinco y Colmillo ---
	p.eikon = load(Catalog.EIKONS["lobo"])
	p.meter = Fighter.METER_MAX
	p.global_position = Vector3(0, 0, 6)
	p.facing = Vector3.FORWARD
	e.global_position = Vector3(0, 0, 3)
	await physics_frame
	check(p.summon() and p.mounted and p.mount_node.eikon.id == "lobo", "invoca y monta el lobo")
	check(p.is_grounded(), "en el lobo se toca el suelo")
	await wait(0.2)
	p.stamina = p.stamina_max
	check(p.jump(), "montado en el lobo: brinco de la montura")
	await wait(0.18)
	check(not p.is_grounded() and p.global_position.y > 0.4, "el brinco despega del suelo (%.2f m)" % p.global_position.y)
	await wait(1.0)
	check(p.is_grounded() and p.mounted, "aterriza y sigue montado")
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(0, 0, 3)
	p.facing = Vector3.FORWARD
	await physics_frame
	var h0 := e.health
	check(p.eikon_special() and e.health < h0 and e.stun > 0.0, "Colmillo helado: daña y congela al de delante (%.0f)" % (h0 - e.health))
	p.dismiss_eikon()
	await physics_frame
	check(not p.mounted, "dismiss_eikon baja del eikon")
	# --- Grifo: Vendaval empuja ---
	p.eikon = load(Catalog.EIKONS["grifo"])
	p.meter = Fighter.METER_MAX
	await wait(0.6)
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(2.5, 0, 6)
	await physics_frame
	check(p.summon() and p.mounted and p.mount_node.data.model_path.contains("horse"), "el grifo reutiliza el modelo de montura")
	h0 = e.health
	check(p.eikon_special() and e.health < h0 and e.knock.length() > 1.0, "Vendaval: daña y empuja")
	p.dismiss_eikon()
	# --- Gólem: NO montable, lucha a pie a tu lado ---
	p.eikon = load(Catalog.EIKONS["golem"])
	p.meter = Fighter.METER_MAX
	await wait(0.6)
	check(p.summon(), "invoca el gólem")
	check(p.active_eikon is Eikon and not p.mounted and p.nearest_free_mount() == null, "el gólem no se monta: es un compañero con IA")
	check(p.summon() == false, "E con el gólem activo no hace nada más")
	# --- Nueva ronda: sin eikons y a pie ---
	p.meter = Fighter.METER_MAX
	p.eikon = load(Catalog.EIKONS["fenix"])
	p.dismiss_eikon()
	p.summon()
	arena.start_round()
	await physics_frame
	check(not p.mounted and p.active_eikon == null and get_nodes_in_group("eikon_mount").filter(func(n): return not n.is_queued_for_deletion()).is_empty(), "cada ronda empieza a pie y sin eikon")
	# --- IA: invoca su eikon montable y lo monta ---
	e.eikon = load(Catalog.EIKONS["lobo"])
	e.meter = Fighter.METER_MAX
	arena.ai.enabled = true
	var rode := false
	for i in 120:
		await physics_frame
		if e.mounted and e.mount_node and e.mount_node.owner_fighter == e:
			rode = true
			break
	check(rode, "la IA invoca y monta su eikon")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
