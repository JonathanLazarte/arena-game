extends SceneTree
## Ronda 17: disparo con compromiso (arco/ballesta), disparo libre y huida «parta» montado,
## aturdimiento por golpe del combo y llamada del eikon con «Montar».
## godot --headless --path . -s res://tests/test_ranged_stun.gd

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

func _load(cid: String, wid: String, eid: String) -> void:
	var gs := root.get_node("GameState")
	gs.from_lobby = true
	gs.random_rival = false
	gs.character_id = cid
	gs.weapon_id = wid
	gs.eikon_id = eid
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
	await wait(0.8)

func _place(dist: float) -> void:
	p.move_input = Vector3.ZERO
	p.want_sprint = false
	e.move_input = Vector3.ZERO
	await wait(0.4)
	p.global_position = Vector3(0, 0, 8)
	p.facing = Vector3.FORWARD
	p.face_target = e
	p.stamina = p.stamina_max
	p.bow_cd = 0.0
	e.global_position = Vector3(0, 0, 8 - dist)
	e.facing = Vector3.BACK
	e.stun = 0.0
	e.poise_max = 10000.0
	e.poise = e.poise_max
	await physics_frame

func _speed() -> float:
	return MeshUtil.flat(p.velocity).length()

## Dispara en bucle durante `secs` y devuelve los instantes de cada flecha/virote.
func _spam(secs: float) -> Array[float]:
	var times: Array[float] = []
	var t := 0.0
	var n0 := p.shots_fired
	while t < secs:
		p.stamina = p.stamina_max
		p.shoot()
		await physics_frame
		t += 1.0 / 60.0
		if p.shots_fired > n0:
			n0 = p.shots_fired
			times.append(t)
	return times

func _run() -> void:
	seed(17)
	# ---------- Datos ----------
	var bow: WeaponDef = load("res://resources/weapons/arco.tres")
	var xb: WeaponDef = load("res://resources/weapons/ballesta.tres")
	check(xb.fire_draw < bow.fire_draw and xb.fire_recovery < bow.fire_recovery, "ballesta: menos compromiso al disparar que el arco")
	check(xb.reload_time > 1.0 and xb.arrow_damage > bow.arrow_damage and xb.projectile_speed > bow.projectile_speed, "ballesta: recarga, más daño, virote más rápido")
	check(xb.ranged_hitstun > bow.ranged_hitstun, "el virote aturde más que la flecha")
	check(Progression.WEAPON_REQ.has("ballesta") and Progression.WEAPON_REQ["ballesta"][0] >= 2 and Progression.WEAPON_REQ["ballesta"][1] > 0, "ballesta con nivel y precio (%s)" % [Progression.WEAPON_REQ["ballesta"]])
	check(Catalog.character("arquero").allows("ballesta") and Catalog.character("asesino").allows("ballesta") and not Catalog.character("caballero").allows("ballesta"), "ballesta para Arquero y Asesino")
	var hs_ok := true
	var h1s := {}
	for wid: String in ["espada_escudo", "espada_larga", "hacha_2m", "dagas", "lanza"]:
		var w: WeaponDef = load("res://resources/weapons/%s.tres" % wid)
		var a: ComboHit = w.combo[0]
		var b2: ComboHit = w.combo[1]
		var c: ComboHit = w.combo[2]
		h1s[wid] = a.hitstun
		hs_ok = hs_ok and is_equal_approx(a.hitstun, b2.hitstun) and c.hitstun >= a.hitstun * 2.0
		# el golpe siguiente llega después de que acabe el aturdimiento + arranque de voltereta
		var gap := a.active + Fighter.CHAIN_MIN_RECOVERY + b2.windup
		hs_ok = hs_ok and a.hitstun + Fighter.ROLL_STARTUP < gap - 0.15
	check(hs_ok, "aturdimiento por golpe: 1 = 2, remate ≥ ×2 y da tiempo a rodar antes del 2.º")
	check(h1s["dagas"] < h1s["lanza"] and h1s["lanza"] < h1s["hacha_2m"], "dagas < lanza < hacha (%s)" % [h1s])
	# ---------- Arco a pie: raíz y lentitud ----------
	await _load("arquero", "arco", "lobo")
	await _place(16.0)
	p.face_target = null
	p.move_input = Vector3.RIGHT
	await wait(0.5)
	var walk := _speed()
	p.shoot()
	var draw_max := 0.0
	while p.shot_state == Fighter.Shot.DRAW:
		await physics_frame
		if p.shot_t > 0.08:
			draw_max = maxf(draw_max, _speed())
	var rec := []
	while p.shot_state == Fighter.Shot.RECOVER:
		await physics_frame
		if p.shot_t > 0.15:
			rec.append(_speed())
	await wait(0.5)
	var after := _speed()
	var rec_avg: float = rec.reduce(func(a, b): return a + b, 0.0) / maxf(rec.size(), 1)
	check(draw_max < 0.3, "arco: quieto mientras tensa (%.2f m/s)" % draw_max)
	check(rec_avg > walk * 0.12 and rec_avg < walk * 0.35, "arco: tras soltar anda al ~25 %% (%.2f de %.2f)" % [rec_avg, walk])
	check(after > walk * 0.9, "después recupera la marcha (%.2f)" % after)
	# Correr y disparar: el disparo corta la carrera y apaga «Correr»
	arena.controller.set_physics_process(true)
	arena.controller.lock_on = false
	arena.controller.run_toggled = true
	Input.action_press("move_right")
	await wait(0.6)
	var was_spr := p.sprinting
	Input.action_press("attack_sword")
	await physics_frame
	await physics_frame
	Input.action_release("attack_sword")
	await wait(0.2)
	check(was_spr and p.shot_state != Fighter.Shot.NONE and not p.sprinting and arena.controller.run_toggled, "disparar corriendo: suspende la carrera sin apagar «Correr» (ronda 18)")
	var gd := 0
	while p.is_shooting() and gd < 120:
		await physics_frame
		gd += 1
	await wait(0.3)
	check(p.sprinting and arena.controller.run_toggled, "al acabar el disparo vuelve a correr solo (toggle)")
	# Mayús mantenida: también reanuda
	arena.controller.run_toggled = false
	Input.action_press("sprint")
	await wait(0.4)
	Input.action_press("attack_sword")
	await physics_frame
	await physics_frame
	Input.action_release("attack_sword")
	await wait(0.15)
	var sus := not p.sprinting
	gd = 0
	while p.is_shooting() and gd < 120:
		await physics_frame
		gd += 1
	await wait(0.3)
	check(sus and p.sprinting, "con Mayús mantenida: suspende y reanuda la carrera")
	Input.action_release("sprint")
	Input.action_release("move_right")
	arena.controller.set_physics_process(false)
	# Cadencias
	await _place(30.0)
	var tb := await _spam(4.0)
	var bow_int := (tb[-1] - tb[0]) / maxf(tb.size() - 1, 1) if tb.size() > 1 else 99.0
	check(abs(bow_int - (bow.fire_draw + bow.fire_recovery + bow.fire_cooldown)) < 0.08, "arco: un disparo cada %.2f s" % bow_int)
	# ---------- Ballesta ----------
	await _load("arquero", "ballesta", "lobo")
	check(p.weapon.id == "ballesta" and p._bow.name == "Ballesta", "la ballesta usa el modelo 1H_Crossbow")
	await _place(30.0)
	var root_t := 0.0
	p.move_input = Vector3.RIGHT
	await wait(0.4)
	p.shoot()
	var t0 := 0.0
	var first := -1.0
	while p.shot_state != Fighter.Shot.NONE:
		await physics_frame
		t0 += 1.0 / 60.0
		if _speed() < 0.3:
			root_t += 1.0 / 60.0
		if first < 0.0 and p.shots_fired > 0:
			first = t0
	check(first > 0.0 and first < bow.fire_draw, "ballesta: el virote sale antes que la flecha (%.2f s)" % first)
	check(root_t < bow.fire_draw, "ballesta: menos tiempo inmóvil (%.2f s)" % root_t)
	p.move_input = Vector3.ZERO
	var tx := await _spam(6.0)
	var xb_int := (tx[-1] - tx[0]) / maxf(tx.size() - 1, 1) if tx.size() > 1 else 99.0
	check(xb_int > bow_int * 1.4, "ballesta: cadencia más lenta por la recarga (%.2f s vs %.2f s)" % [xb_int, bow_int])
	# daño y aturdimiento del virote
	await _place(10.0)
	while p.shot_state != Fighter.Shot.NONE:
		await physics_frame
	p.bow_cd = 0.0
	var h0 := e.health
	p.shoot()
	await wait(0.6)
	check(h0 - e.health >= xb.arrow_damage and (e.stun_acc > 0.0 or e.staggers > 0), "virote: %.0f de daño y suma fuerza de aturdimiento (%.1f, ronda 31: acumulado)" % [h0 - e.health, e.stun_acc])
	# ---------- Montado: disparo libre y huida parta ----------
	await _place(14.0)
	p.meter = Fighter.METER_MAX
	check(p.summon() and p.mounted, "monta su lobo")
	await wait(0.8)
	p.face_target = e
	p.want_sprint = true
	p.move_input = Vector3.RIGHT
	await wait(0.8)
	var gal := _speed()
	p.bow_cd = 0.0
	await wait(0.6)
	p.shoot()
	var min_sp := 99.0
	while p.shot_state == Fighter.Shot.DRAW or p.shot_state == Fighter.Shot.RECOVER:
		await physics_frame
		min_sp = minf(min_sp, _speed())
	check(min_sp > gal * 0.85, "montado: dispara sin frenar a la montura (%.1f de %.1f)" % [min_sp, gal])
	# huida: entrada lejos del rival (>110°) al galope
	p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized()
	for i in 50:
		p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized()
		await physics_frame
	var to_e := MeshUtil.flat(e.global_position - p.global_position).normalized()
	check(p.facing.dot(to_e) < -0.9 and p.sprinting, "montado y fijado: la montura se gira y huye al galope")
	check(p.aim_facing().dot(to_e) > 0.95 and absf(p.rider_yaw) > deg_to_rad(150.0), "el jinete se gira en la silla y mira al rival (giro %.0f°)" % rad_to_deg(p.rider_yaw))
	check(not p.attack_light(), "girado en la silla no hay cuerpo a cuerpo (solo arco)")
	p.bow_cd = 0.0
	p.stamina = p.stamina_max
	var n0 := p.shots_fired
	while p.shot_state != Fighter.Shot.NONE:
		p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized()
		await physics_frame
	p.bow_cd = 0.0
	check(p.shoot(), "dispara hacia atrás huyendo")
	var shot: Projectile = null
	for i in 40:
		p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized()
		await physics_frame
		if p.shots_fired > n0 and shot == null:
			for n in get_nodes_in_group("projectile"):
				if (n as Projectile).shooter == p:
					shot = n
	to_e = (e.get_hit_center() - (shot.global_position if shot else p.global_position)).normalized()
	check(shot != null and shot.direction.dot(to_e) > 0.9 and p.facing.dot(MeshUtil.flat(to_e)) < -0.8, "tiro parto: la flecha va hacia el rival mientras huye")
	p.want_sprint = false
	p.move_input = Vector3.ZERO
	# ---------- Llamar al eikon con «Montar» ----------
	await wait(0.5)
	p.toggle_mount()
	await wait(0.3)
	var wolf: Mount = p.owned_mount
	check(not p.mounted and wolf != null, "desmontado")
	wolf.global_position = Vector3(16, 0, 0)
	p.global_position = Vector3(-4, 0.2, 0)
	await physics_frame
	check(not p.toggle_mount() and wolf.called, "«Montar» lejos: lo llama")
	p.toggle_mount()
	check(not wolf.called, "pulsar otra vez cancela la llamada")
	p.toggle_mount()
	var t_call := 0.0
	p.move_input = Vector3.BACK # el jugador se mueve: lo sigue
	var w_start := wolf.global_position
	while not p.mounted and t_call < 6.0:
		await physics_frame
		t_call += 1.0 / 60.0
	p.move_input = Vector3.ZERO
	check(p.mounted and p.mount_node == wolf, "viene corriendo (siguiéndolo) y lo monta solo (%.1f s)" % t_call)
	# aturdido: monta en cuanto queda libre
	p.toggle_mount()
	await wait(0.3)
	wolf.global_position = Vector3(14, 0, 0)
	p.global_position = Vector3(0, 0.2, 0)
	p.toggle_mount()
	p.apply_stun(2.5)
	await wait(1.5)
	check(not p.mounted and wolf.called, "aturdido: espera a quedar libre")
	await wait(1.6)
	check(p.mounted, "al acabar el aturdimiento monta")
	# si el eikon cae, se cancela
	p.toggle_mount()
	await wait(0.3)
	wolf.global_position = Vector3(16, 0, 0)
	p.global_position = Vector3(-4, 0.2, 0)
	p.toggle_mount()
	wolf.take_hit(9999.0, e, "melee")
	await wait(0.5)
	check(not p.mounted and not is_instance_valid(wolf), "si el eikon muere, la llamada se cancela")
	# ---------- Aturdimiento por golpe del combo (espada) ----------
	await _load("caballero", "espada_escudo", "fenix")
	await _place(1.8)
	var sh1 := p.combo_hit_for(1).hitstun
	# a) codicioso: no rueda -> el 2.º golpe conecta
	e.health = 5000.0
	var r := await _combo_vs(false)
	check(r["hits"] >= 2, "si no rueda (codicioso) el 2.º golpe le da (%d golpes)" % r["hits"])
	# Ronda 31: un golpe solo no aturde (acumulado); el remate aporta más fuerza que el primero
	check(r["stun1"] <= StunRules.STAGGER_T + 0.01, "golpe 1: como mucho tambaleo (%.2f s)" % r["stun1"])
	var fin := p.combo_hit_for(p.melee().combo.size())
	check(fin.hitstun > sh1 or fin.stun_force > p.combo_hit_for(1).stun_force, "remate: más fuerza de aturdimiento que el 1.º (%.2f vs %.2f)" % [fin.hitstun, sh1])
	# b) rueda en cuanto acaba el aturdimiento -> esquiva el 2.º
	await _place(1.8)
	r = await _combo_vs(true)
	check(r["rolled"] and r["hits"] == 1, "tras el golpe 1, rodar al quedar libre esquiva el 2.º (%d golpes, voltereta %s)" % [r["hits"], r["rolled"]])
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)

## El jugador encadena el combo completo; el rival (defensor) rueda nada más poder si roll=true.
func _combo_vs(roll: bool) -> Dictionary:
	var hits := 0
	var h0 := e.health
	var stun1 := 0.0
	var fin_stun := 0.0
	var rolled := false
	p.attack_light()
	for i in 260:
		if p.atk_state == Fighter.Atk.RECOVERY and p.combo < 3:
			p.attack_light()
		await physics_frame
		if e.health < h0:
			hits += 1
			h0 = e.health
			if hits == 1:
				stun1 = e.stun + 1.0 / 60.0
			if p.combo == 3:
				fin_stun = e.stun + 1.0 / 60.0
		if roll and hits >= 1 and not rolled and e.stun <= 0.0:
			e.move_input = Vector3.FORWARD.rotated(Vector3.UP, 0.0) # se aleja (el jugador está en +Z)
			rolled = e.dash()
		if p.atk_state == Fighter.Atk.NONE and i > 10:
			break
	e.move_input = Vector3.ZERO
	return {"hits": hits, "stun1": stun1, "fin_stun": fin_stun, "rolled": rolled}
