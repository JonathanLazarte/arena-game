extends SceneTree
## Ronda 8: el escudo no anula los ataques de eikon (pasa el 50 % y cuesta más aguante);
## las flechas siguen anuladas del todo.
## godot --headless --path . -s res://tests/test_eikon_block.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _shoot(arena: Arena, from: Fighter, to: Fighter, kind: String, dmg: float) -> void:
	var pr := Projectile.new()
	pr.team = from.team
	pr.shooter = from
	pr.damage = dmg
	pr.kind = kind
	var o := from.get_hit_center()
	pr.direction = (to.get_hit_center() - o).normalized()
	arena.add_child(pr)
	pr.global_position = o

func _run() -> void:
	seed(3)
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
	e.global_position = p.global_position + p.facing * 8.0
	e.facing = -p.facing
	p.want_block = true
	await wait(0.2)
	check(p.blocking, "el jugador bloquea")
	# take_hit directo
	var h0 := p.health
	var s0 := p.stamina
	check(p.take_hit(20.0, e, "eikon") == "block", "ataque de eikon frontal con escudo = block")
	check(is_equal_approx(h0 - p.health, 20.0 * Fighter.EIKON_BLOCK_PASS), "pasa el 50 %% del daño (%.1f)" % (h0 - p.health))
	check(s0 - p.stamina >= Fighter.COST_BLOCKED_EIKON - 0.01 and Fighter.COST_BLOCKED_EIKON > Fighter.COST_BLOCKED_HIT, "cuesta aguante extra (%.1f)" % (s0 - p.stamina))
	p.stamina = Fighter.STAMINA_MAX
	h0 = p.health
	check(p.take_hit(20.0, e, "arrow") == "block" and is_equal_approx(p.health, h0), "flecha bloqueada: 0 daño")
	# Proyectiles reales: bola de fuego de eikon frente a flecha
	p.stamina = Fighter.STAMINA_MAX
	h0 = p.health
	_shoot(arena, e, p, "eikon", 16.0)
	await wait(0.8)
	check(is_equal_approx(h0 - p.health, 8.0), "bola de fuego bloqueada: 8 de 16 de daño (%.1f)" % (h0 - p.health))
	p.stamina = Fighter.STAMINA_MAX
	h0 = p.health
	_shoot(arena, e, p, "arrow", 16.0)
	await wait(0.8)
	check(is_equal_approx(p.health, h0), "flecha real bloqueada: 0 daño")
	# El fénix del jugador dispara proyectiles de tipo eikon
	p.want_block = false
	e.want_block = true
	p.meter = 100.0
	p.summon() # ronda 14: el fénix se monta; su especial (E montado) dispara
	var got := false
	for i in 240:
		await physics_frame
		if i % 20 == 5:
			p.summon()
		for pr in get_nodes_in_group("projectile"):
			if (pr as Projectile).kind == "eikon":
				got = true
		if got:
			break
	check(got, "el fénix dispara proyectiles de tipo eikon")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
