extends SceneTree
## Ronda 16: autoapuntado = solo apuntar. Los proyectiles vuelan rectos (sin perseguir); correr de
## lado a distancia los esquiva; la voltereta los atraviesa en los i-frames.
## godot --headless --path . -s res://tests/test_projectile_dodge.gd

var fails: int = 0
var arena: Arena
var p: Fighter
var e: Fighter
var enemy_dist: float = 20.0

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
	e.global_position = Vector3(0, 0, 8 - enemy_dist)
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
	pr.life = 4.0
	var origin := e.get_hit_center() + Vector3(0, 0.6, 0)
	pr.direction = Projectile.aim_dir(origin, p, speed, 0.0)
	pr.aimed_at = p
	arena.add_child(pr)
	pr.global_position = origin
	return pr

## Sigue el proyectil; si dodge_at > 0, rueda a la derecha cuando esté a esa distancia.
## move_side: el jugador corre hacia un lado todo el tiempo (sin rodar).
func _run_case(kind: String, speed: float, dodge_at: float, move_side: bool = false, roll_dir: Vector3 = Vector3.RIGHT) -> Dictionary:
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
			p.move_input = roll_dir
			rolled = p.dash()
		if rolled and not p.is_rolling():
			p.move_input = Vector3.ZERO
	p.move_input = Vector3.ZERO
	var lost := false
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
	# Flecha: 32 m/s. La voltereta tiene 2 frames de arranque y 12 de i-frames (0,47 s).
	# 1) Vuela recta: la dirección no cambia nunca (sin homing)
	enemy_dist = 20.0
	var r := await _run_case("arrow", 32.0, -1.0, true)
	check(not r["homed"], "flecha: vuela recta, no persigue (sin giro)")
	# 2) A distancia, correr de lado la esquiva
	enemy_dist = 28.0
	r = await _run_case("arrow", 32.0, -1.0, true)
	check(r["dmg"] == 0.0, "flecha a 28 m: correr de lado la esquiva (daño %.0f)" % r["dmg"])
	r = await _run_case("eikon", 22.0, -1.0, true)
	check(not r["homed"] and r["dmg"] == 0.0, "bola de eikon a 28 m: recta, correr de lado la esquiva")
	# 3) Quieto: te da (apuntó a tu posición)
	r = await _run_case("arrow", 32.0, -1.0, false)
	check(r["dmg"] > 0.0, "quieto: la flecha apuntada te da (%.0f)" % r["dmg"])
	# 4) Voltereta bien medida: la atraviesa en los i-frames (hacia atrás, en su línea)
	enemy_dist = 20.0
	r = await _run_case("arrow", 32.0, 4.5, false, Vector3.BACK)
	check(r["rolled"] and r["dmg"] == 0.0 and r["dodged"] >= 1, "flecha: voltereta a tiempo = la atraviesa con i-frames (%d)" % r["dodged"])
	# 5) Voltereta mal medida en su línea (muy pronto, hacia atrás): te da
	r = await _run_case("arrow", 32.0, 19.0, false, Vector3.BACK)
	check(r["rolled"] and r["dmg"] > 0.0, "flecha: voltereta mal medida = te da (%.0f)" % r["dmg"])
	r = await _run_case("eikon", 22.0, 3.6, false, Vector3.BACK)
	check(r["rolled"] and r["dmg"] == 0.0, "bola de eikon: voltereta a tiempo = sin daño")
	r = await _run_case("eikon", 22.0, 17.0, false, Vector3.BACK)
	check(r["rolled"] and r["dmg"] > 0.0, "bola de eikon: voltereta mal medida = te da (%.0f)" % r["dmg"])
	# 6) Apuntado honesto: lead 0 = a la posición actual; lead 0,5 = medio adelanto
	await _reset()
	p.move_input = Vector3.RIGHT
	await wait(0.5)
	var o := e.get_hit_center()
	var now := (p.get_hit_center() - o).normalized()
	check(Projectile.aim_dir(o, p, 32.0, 0.0).dot(now) > 0.99999, "sin adelanto apunta a la posición actual")
	var led := Projectile.aim_dir(o, p, 32.0, 0.5)
	check(led.dot(now) < 0.9999 and MeshUtil.flat(led).cross(MeshUtil.flat(now)).y != 0.0, "con adelanto (IA difícil) apunta algo por delante")
	p.move_input = Vector3.ZERO
	var easy: AIDifficulty = load("res://resources/ai/easy.tres")
	var normal: AIDifficulty = load("res://resources/ai/normal.tres")
	var hard: AIDifficulty = load("res://resources/ai/hard.tres")
	check(easy.aim_lead == 0.0 and normal.aim_lead == 0.0 and hard.aim_lead == 0.5, "IA: adelanto solo en difícil (0 / 0 / 0,5)")
	# 7) El arco real del jugador apunta al rival al disparar y vuela recto
	await _reset()
	p.loadout = Fighter.Loadout.BOW
	p.bow_cd = 0.0
	p.face_target = e
	p.facing = Vector3.FORWARD
	p.shoot()
	await wait(p.ranged().fire_draw + 0.05) # Ronda 17: la flecha sale al acabar de tensar
	var shot: Projectile = null
	for n in get_nodes_in_group("projectile"):
		if (n as Projectile).shooter == p:
			shot = n
	check(shot != null and shot.aimed_at == e, "las flechas del arco se apuntan al rival al disparar")
	if shot:
		var d0 := shot.direction
		var to_e := (e.get_hit_center() - shot.global_position).normalized()
		await wait(0.2)
		check(is_instance_valid(shot) and shot.direction.is_equal_approx(d0) and d0.dot(to_e) > 0.98, "…y vuelan rectas hacia donde estaba")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)
