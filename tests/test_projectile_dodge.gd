extends SceneTree
## Ronda 14: los proyectiles persiguen (giro limitado), pero una voltereta/dash bien medido los esquiva.
## godot --headless --path . -s res://tests/test_projectile_dodge.gd

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

func _reset() -> void:
	for n in get_nodes_in_group("projectile"):
		n.queue_free()
	p.global_position = Vector3(0, 0, 8)
	p.facing = Vector3.FORWARD
	p.move_input = Vector3.ZERO
	p.stamina = p.stamina_max
	p.dash_cd = 0.0
	p.roll_t = -1.0
	p.health = 5000.0
	e.global_position = Vector3(0, 0, -12)
	await wait(0.5)

## Dispara desde el rival hacia el jugador con autoapuntado.
func _fire(kind: String, speed: float) -> Projectile:
	var pr := Projectile.new()
	pr.team = e.team
	pr.shooter = e
	pr.kind = kind
	pr.speed = speed
	pr.damage = 10.0
	pr.radius = 0.7 if kind == "eikon" else 0.5
	pr.target = p
	pr.turn_rate = 1.4 if kind == "eikon" else 1.6
	pr.life = 4.0
	var origin := e.get_hit_center() + Vector3(0, 0.6, 0)
	pr.direction = (p.get_hit_center() - origin).normalized()
	arena.add_child(pr)
	pr.global_position = origin
	return pr

## Sigue el proyectil; si dodge_at > 0, rueda a la derecha cuando esté a esa distancia.
## move_side: el jugador corre hacia un lado todo el tiempo (sin rodar).
func _run_case(kind: String, speed: float, dodge_at: float, move_side: bool = false) -> Dictionary:
	await _reset()
	var h0 := p.health
	var pr := _fire(kind, speed)
	var rolled := false
	var d0 := p.rolls_dodged
	var homed := false
	var dir0 := pr.direction
	for i in 180:
		await physics_frame
		if not is_instance_valid(pr):
			break
		if move_side:
			p.move_input = Vector3.RIGHT
		if pr.direction.angle_to(dir0) > 0.02:
			homed = true
		var dist := pr.global_position.distance_to(p.get_hit_center())
		if dodge_at > 0.0 and not rolled and dist <= dodge_at:
			p.move_input = Vector3.RIGHT
			rolled = p.dash()
		if rolled and not p.is_rolling():
			p.move_input = Vector3.ZERO
	p.move_input = Vector3.ZERO
	var lost := is_instance_valid(pr) and pr.lost
	if is_instance_valid(pr):
		pr.queue_free()
	return {"dmg": h0 - p.health, "rolled": rolled, "dodged": p.rolls_dodged - d0, "lost": lost, "homed": homed}

func _run() -> void:
	seed(5)
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
	p.max_health = 5000.0
	for f: Fighter in [p, e]:
		f.meter_passive = false
	# Flecha: velocidad 32 m/s. La voltereta tiene 2 frames de arranque y 12 de i-frames (0,47 s).
	# 1) Sin esquivar pero corriendo de lado: el autoapuntado la corrige y acierta.
	var r := await _run_case("arrow", 32.0, -1.0, true)
	check(r["homed"] and r["dmg"] > 0.0, "flecha: persigue a un objetivo que corre de lado y acierta (%.0f)" % r["dmg"])
	# 2) Voltereta bien medida (cuando la flecha está a ~4,5 m: llega en los i-frames)
	r = await _run_case("arrow", 32.0, 4.5)
	check(r["rolled"] and r["dmg"] == 0.0, "flecha: voltereta a tiempo = sin daño")
	check(r["dodged"] >= 1 or r["lost"], "la atraviesa en los i-frames o la deja atrás (i-frames %d, perdida %s)" % [r["dodged"], r["lost"]])
	# 3) Voltereta demasiado pronto (flecha a 20 m): acaba antes de que llegue, gira y acierta
	r = await _run_case("arrow", 32.0, 20.0)
	check(r["rolled"] and r["dmg"] > 0.0, "flecha: voltereta mal medida (muy pronto) = te da (%.0f)" % r["dmg"])
	# 4) Bola de fuego de eikon (22 m/s, más grande): igual
	r = await _run_case("eikon", 22.0, 3.6)
	check(r["rolled"] and r["dmg"] == 0.0, "bola de eikon: voltereta a tiempo = sin daño")
	r = await _run_case("eikon", 22.0, 17.0)
	check(r["rolled"] and r["dmg"] > 0.0, "bola de eikon: voltereta mal medida = te da (%.0f)" % r["dmg"])
	# 5) Tras esquivarla no da la vuelta: no vuelve a perseguir
	await _reset()
	var pr := _fire("arrow", 32.0)
	var rolled := false
	var after := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(pr):
			break
		if not rolled and pr.global_position.distance_to(p.get_hit_center()) < 4.5:
			p.move_input = Vector3.RIGHT
			rolled = p.dash()
		if rolled and pr.lost:
			after = true
	check(after, "una vez esquivada/rebasada, la flecha deja de perseguir")
	# 6) Giro limitado: cada frame gira como mucho turn_rate/60 rad
	await _reset()
	pr = _fire("arrow", 32.0)
	var max_step := 0.0
	var last := pr.direction
	p.move_input = Vector3.RIGHT
	for i in 25:
		await physics_frame
		if not is_instance_valid(pr):
			break
		max_step = maxf(max_step, pr.direction.angle_to(last))
		last = pr.direction
	p.move_input = Vector3.ZERO
	check(max_step <= 1.6 / 60.0 + 0.002, "giro máximo por frame %.4f rad (límite %.4f)" % [max_step, 1.6 / 60.0])
	# 7) El arco real del jugador también fija objetivo
	p.loadout = Fighter.Loadout.BOW
	p.bow_cd = 0.0
	p.facing = Vector3.FORWARD
	p.shoot()
	await physics_frame
	var shot: Projectile = null
	for n in get_nodes_in_group("projectile"):
		if (n as Projectile).shooter == p:
			shot = n
	check(shot != null and shot.target == e, "las flechas del arco persiguen al rival")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
