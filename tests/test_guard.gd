extends SceneTree
## Ronda 7: escudo frontal (flechas anuladas, chip en cuerpo a cuerpo, rotura de guardia).
## godot --headless --path . -s res://tests/test_guard.gd

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
	seed(7)
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	var p := arena.player
	var e := arena.enemy
	for f: Fighter in [p, e]:
		f.knockoff_chance_heavy = 0.0
		f.knockoff_chance_dash = 0.0
		f.max_health = 2000.0
		f.health = 2000.0
	await wait(0.5)
	e.global_position = p.global_position + p.facing * 3.0
	e.facing = -p.facing
	await physics_frame
	# --- Flecha real contra el escudo: 0 daño, coste pequeño ---
	e.swap_loadout()
	await wait(2.2)
	p.stamina = Fighter.STAMINA_MAX
	p.want_block = true
	await wait(0.2)
	var h0 := p.health
	var s0 := p.stamina
	e.face_target = p
	e.global_position = p.global_position + p.facing * 9.0
	await physics_frame
	check(e.shoot(), "el rival dispara una flecha")
	await wait(0.8)
	check(is_equal_approx(p.health, h0), "flecha bloqueada: 0 daño (%.1f -> %.1f)" % [h0, p.health])
	check(s0 - p.stamina < 6.0 and s0 - p.stamina >= Fighter.COST_BLOCKED_ARROW - 0.01, "flecha bloqueada: coste pequeño de aguante (%.1f)" % (s0 - p.stamina))
	check(p.take_hit(8.0, e, "arrow") == "block" and is_equal_approx(p.health, h0), "take_hit de flecha frontal con escudo = block, 0 daño")
	# Sin escudo la flecha sí daña
	p.want_block = false
	await wait(0.1)
	var h1 := p.health
	p.take_hit(8.0, e, "arrow")
	check(p.health < h1, "sin escudo la flecha hace daño")
	# --- Cuerpo a cuerpo: chip y 4-5 ligeros hasta romper la guardia ---
	e.global_position = p.global_position + p.facing * 2.0
	p.stamina = Fighter.STAMINA_MAX
	p.exhausted = 0.0
	p.want_block = true
	await wait(0.3)
	var blocked := 0
	var chip_ok := true
	var gb0 := p.guard_breaks
	for i in 10:
		var hb := p.health
		var r := p.take_hit(Fighter.LIGHT["damage"], e, "melee")
		if r != "block":
			break
		blocked += 1
		var dmg := hb - p.health
		chip_ok = chip_ok and dmg > 0.0 and dmg <= Fighter.LIGHT["damage"] * 0.15
		if p.guard_breaks > gb0:
			break
		await wait(0.5) # cadencia realista entre golpes (sin regenerar al mantener el escudo)
	print("ligeros bloqueados hasta romper guardia: %d" % blocked)
	check(chip_ok, "bloqueo: solo daño residual (<=15%)")
	check(p.guard_breaks == gb0 + 1 and blocked >= 4 and blocked <= 5, "rotura de guardia tras 4-5 ligeros bloqueados (%d)" % blocked)
	check(p.stun >= 0.9 and not p.blocking, "rotura de guardia: tambaleo ~1 s y sin escudo (%.2f)" % p.stun)
	var hx := p.health
	p.take_hit(Fighter.LIGHT["damage"], e, "melee")
	check(hx - p.health >= Fighter.LIGHT["damage"] - 0.01, "tras romper la guardia queda expuesto (daño completo %.1f)" % (hx - p.health))
	var t := 0.0
	while p.stun > 0.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	check(t > 0.6 and t < 1.2, "el tambaleo dura ~1 s (%.2f)" % t)
	# --- Fuertes cuestan ~2x ---
	await wait(0.3)
	p.stamina = Fighter.STAMINA_MAX
	p.exhausted = 0.0
	await wait(0.3)
	var sb := p.stamina
	p.take_hit(Fighter.HEAVY["damage"], e, "melee")
	var heavy_cost := sb - p.stamina
	check(absf(heavy_cost - Fighter.COST_BLOCKED_HIT * 2.0) < 1.5, "fuerte bloqueado cuesta ~2x (%.1f)" % heavy_cost)
	var h2 := p.health
	p.take_hit(Fighter.HEAVY["damage"], e, "melee")
	p.take_hit(Fighter.HEAVY["damage"], e, "melee")
	check(p.guard_breaks == gb0 + 2, "3 fuertes bloqueados rompen la guardia")
	# Por la espalda no bloquea
	await wait(1.3)
	p.stamina = Fighter.STAMINA_MAX
	p.want_block = true
	await wait(0.2)
	e.global_position = p.global_position - p.facing * 2.0
	var h3 := p.health
	check(p.take_hit(8.0, e, "arrow") == "hit" and p.health < h3, "flecha por la espalda: el escudo frontal no cubre")
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(1 if fails > 0 else 0)
