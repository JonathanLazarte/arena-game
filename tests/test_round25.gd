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
	await process_frame
	var au := root.get_node("Audio")
	au.settings_path = "user://test_r25_ajustes.cfg"
	Arena.start_mounted = true
	Arena.hitstop_enabled = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1.0e9
	await create_timer(3.2).timeout
	var p := arena.player
	var e := arena.enemy
	var c := arena.controller
	var rig := arena.rig
	for f: Fighter in [p, e]:
		f.dismount(false)
	await physics_frame
	p.owned_mount.global_position = Vector3(-30, 0.2, 30)
	e.owned_mount.global_position = Vector3(30, 0.2, 30)
	# --- 1. Direcciones ---
	e.global_position = Vector3(30, 0.2, -30)
	if is_instance_valid(p.owned_mount) and p.owned_mount.is_free():
		p.owned_mount.global_position = Vector3(-30, 0.2, 30)
	c.lock_on = false
	await physics_frame
	await dirs_test(arena, "a pie libre", false)
	await dirs_test(arena, "a pie libre", true)
	c.lock_on = true
	e.global_position = Vector3(0, 0.2, -14)
	await physics_frame
	await dirs_test(arena, "a pie fijado", true)
	c.lock_on = false
	p.owned_mount.global_position = p.global_position
	p.mount_on(p.owned_mount)
	await create_timer(0.3).timeout
	e.global_position = Vector3(30, 0.2, -30)
	await dirs_test(arena, "montado libre", true)
	p.dismount(false)
	p.owned_mount.global_position = Vector3(-30, 0.2, 30)
	await create_timer(0.4).timeout
	# --- 2. Cámara ---
	c.lock_on = false
	await physics_frame
	var y0 := rig.yaw
	rig.orbit(Vector2(0.5, 0.0))
	check(absf(rig.yaw - y0) > 0.4, "arrastrar gira la cámara (órbita)")
	var cam_before := arena.camera.global_position
	await create_timer(0.4).timeout
	check(arena.camera.global_position.distance_to(cam_before) > 1.0, "la cámara orbita alrededor del jugador")
	rig.orbit(Vector2(0, 50.0))
	check(is_equal_approx(rig.pitch, CameraRig.PITCH_MAX), "inclinación limitada arriba")
	rig.orbit(Vector2(0, -50.0))
	check(is_equal_approx(rig.pitch, CameraRig.PITCH_MIN), "inclinación limitada abajo")
	rig.pitch = CameraRig.PITCH_DEFAULT
	CameraRig.invert_y = true
	var pp := rig.pitch
	rig.orbit(Vector2(0, 0.1))
	check(rig.pitch < pp, "invertir Y")
	CameraRig.invert_y = false
	rig.pitch = CameraRig.PITCH_DEFAULT
	# Movimiento relativo a la cámara después de orbitar
	rig.orbit(Vector2(1.2, 0))
	await create_timer(0.5).timeout
	var exp_w := expected(arena, ["move_forward"])
	Input.action_press("move_forward")
	await create_timer(0.6).timeout
	var p0 := p.global_position
	await create_timer(0.3).timeout
	Input.action_release("move_forward")
	check(MeshUtil.flat(p.global_position - p0).normalized().dot(exp_w) > 0.85, "W avanza hacia donde mira la cámara")
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
	# Lock-on: la cámara sigue al objetivo; tirón cambia de objetivo
	c.lock_on = true
	p.global_position = Vector3(0, 0, 8) # ronda 29: lejos del muro (el rival ya no puede quedar fuera de la arena)
	e.global_position = p.global_position + Vector3(8, 0, 0)
	await create_timer(1.0).timeout
	var cf := MeshUtil.flat(-arena.camera.global_transform.basis.z).normalized()
	check(cf.dot(Vector3(1, 0, 0)) > 0.8, "fijado: la cámara mira hacia el objetivo")
	rig.orbit(Vector2(1.0, 0))
	check(rig.flicks == 1, "fijado: un tirón horizontal cambia de objetivo")
	au.save_settings()
	CameraRig.sensitivity = 2.0
	au.load_settings()
	check(is_equal_approx(CameraRig.sensitivity, 1.0), "sensibilidad guardada en Ajustes")
	# --- 3. Estocada de jefe ---
	c.set_physics_process(false)
	c.lock_on = true
	p.face_target = e
	for f: Fighter in [p, e]:
		f._cancel_attack()
		f.stun = 0.0
		f.stamina = f.stamina_max
		f.health = f.max_health
	p.global_position = Vector3(0, 0.2, 6)
	e.global_position = Vector3(0, 0.2, 0)
	p.facing = Vector3.FORWARD
	e.poise = 1e6
	e.stance = 1e6
	e.stance_max = 1e6
	await physics_frame
	check(p.boss_skill() and p.boss_phase == Fighter.Boss.CHARGE, "Estocada de jefe: empieza la carga")
	check(not p.boss_skill(), "enfriamiento (%d s)" % int(Fighter.BOSS_COOLDOWN))
	await create_timer(0.3).timeout
	check(p.take_hit(30.0, e, "melee") == "dodge" and p.health == p.max_health, "invulnerable durante la carga")
	p.apply_stun(1.0)
	check(p.stun <= 0.0 and p.boss_phase == Fighter.Boss.CHARGE, "no se interrumpe")
	check(p._blade_mat.emission_enabled and p._boss_fx.emitting, "telegrafía: brillo y partículas en la hoja")
	var e1 := Vector3(3, 0.2, 0)
	e.global_position = e1 # se mueve en la fase de seguimiento: lo sigue
	await create_timer(0.6).timeout
	var dir_track := p.boss_dir
	check(dir_track.dot(MeshUtil.flat(e1 - p.global_position).normalized()) > 0.95, "sigue al objetivo los primeros %.1f s" % Fighter.BOSS_TRACK)
	await until(func() -> bool: return p.boss_t > Fighter.BOSS_TRACK + 0.05, 1.0)
	var locked_dir := p.boss_dir
	e.global_position = e1 + locked_dir.cross(Vector3.UP) * 4.0 # paso lateral tras fijar
	await physics_frame
	check(p.boss_dir.is_equal_approx(locked_dir), "después fija la dirección")
	var start := p.global_position
	var hp := e.health
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.RECOVER, 2.0)
	var travel := MeshUtil.flat(p.global_position - start).length()
	# Ronda 31: la embestida corrige la dirección: el paso lateral ya no basta (solo la voltereta)
	check(p.boss_hit or travel <= Fighter.BOSS_DIST + 0.6, "embestida con seguimiento, recorrido ≤ %.0f m (%.1f m, impacto %s)" % [Fighter.BOSS_DIST, travel, p.boss_hit])
	check(p.take_hit(5.0, e, "melee") == "hit", "recuperación castigable")
	p.health = p.max_health
	p.stun = 0.0
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.NONE, 3.0)
	# Impacto
	p.boss_cd = 0.0
	p.global_position = Vector3(0, 0.2, 6)
	e.global_position = Vector3(0, 0.2, 1)
	await physics_frame
	hp = e.health
	p.boss_skill()
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.RECOVER, 3.0)
	var tr2 := MeshUtil.flat(p.global_position - Vector3(0, 0.2, 6)).length()
	check(p.boss_hit and e.health < hp, "impacta: %.1f de daño" % (hp - e.health))
	check(tr2 < Fighter.BOSS_DIST - 1.0, "se detiene al impactar (%.1f m)" % tr2)
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.NONE, 3.0)
	# --- 4. IA: esquiva y usa la Estocada de jefe ---
	e.set_boss_abilities(["estocada"]) # ronda 31: el rival lleva 3 al azar
	arena.ai.profile = (load("res://resources/ai/hard.tres") as AIDifficulty).duplicate()
	arena.ai.profile.boss_dodge_chance = 1.0
	arena.ai.profile.boss_use_chance = 0.0
	arena.ai.profile.breather_chance = 0.0
	arena.ai.enabled = true
	if e.mounted:
		e.dismount(false)
	if is_instance_valid(e.owned_mount) and e.owned_mount.is_free():
		e.owned_mount.global_position = Vector3(30, 0.2, 30)
	p.boss_cd = 0.0
	p.global_position = Vector3(0, 0.2, 6)
	e.global_position = Vector3(0, 0.2, 1)
	e.health = e.max_health
	await physics_frame
	hp = e.health
	p.boss_skill()
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.RECOVER, 3.0)
	check(arena.ai.boss_dodges == 1 and e.health == hp, "la IA esquiva la estocada con buen tiempo (difícil)")
	await until(func() -> bool: return p.boss_phase == Fighter.Boss.NONE, 3.0)
	arena.ai.profile.boss_use_chance = 1.0
	if e.mounted:
		e.dismount(false)
	e.owned_mount = null # sin montura: que no vuelva a montar
	p.global_position = Vector3(0, 0.2, 6)
	e.global_position = Vector3(0, 0.2, 0)
	e.boss_cd = 0.0
	for attempt in 8:
		if e.boss_uses > 0:
			break
		p.global_position = Vector3(0, 0.2, 6)
		e.global_position = Vector3(0, 0.2, 0)
		e.stamina = e.stamina_max
		e._cancel_attack()
		arena.ai._punish_t = 0.0
		await until(func() -> bool: return e.boss_uses > 0, 5.0)
	if e.boss_uses == 0:
		print("dbg can=%s mounted=%s lo=%d face=%.2f dist=%.1f act=%s" % [e.can_boss(), e.mounted, e.loadout, e.facing.dot(MeshUtil.flat(p.global_position-e.global_position).normalized()), e.global_position.distance_to(p.global_position), e._can_act()])
	check(e.boss_uses > 0 and arena.ai.boss_used > 0, "la IA usa la Estocada de jefe a media distancia")
	arena.ai.enabled = false
	await until(func() -> bool: return e.boss_phase == Fighter.Boss.NONE, 4.0)
	# --- 5. Paso de ataque + magnetismo ---
	p.health = p.max_health
	e.global_position = Vector3(25, 0.2, 25)
	await create_timer(2.5).timeout
	if p.mounted:
		p.dismount(false)
	p.owned_mount = null
	await create_timer(0.6).timeout
	var steps := {}
	for wid: String in ["dagas", "espada_escudo", "lanza"]:
		p.set_loadout_defs(Catalog.character("caballero") if wid != "dagas" else Catalog.character("asesino"), Catalog.weapon(wid))
		p.loadout = Fighter.Loadout.SWORD_SHIELD
		p.global_position = Vector3(0, 0.2, 0)
		e.global_position = Vector3(25, 0.2, 25)
		p.face_target = null
		p.stamina = p.stamina_max
		p.stun = 0.0
		p.down_t = 0.0 # ronda 31
		p.stun_immune_t = 0.0
		p._reset_stun_meter()
		p.combo = 0
		p.velocity = Vector3.ZERO
		p.move_input = Vector3.ZERO
		await create_timer(0.3).timeout
		var s0 := p.global_position
		p.attack_light()
		await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
		steps[wid] = MeshUtil.flat(p.global_position - s0).length()
	check(steps["dagas"] < steps["espada_escudo"] and steps["espada_escudo"] < steps["lanza"], "paso por arma: dagas %.2f < espada %.2f < lanza %.2f m" % [steps["dagas"], steps["espada_escudo"], steps["lanza"]])
	check(steps["espada_escudo"] > 0.6, "los ataques avanzan (no hace falta estar pegado)")
	p.set_loadout_defs(Catalog.character("caballero"), Catalog.weapon("espada_escudo"))
	p.global_position = Vector3(0, 0.2, 0)
	p.facing = Vector3.FORWARD
	e.global_position = Vector3(0, 0.2, -1.6)
	p.face_target = e
	p.stamina = p.stamina_max
	await physics_frame
	p.attack_heavy()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	var gap := MeshUtil.flat(e.global_position - p.global_position).length()
	check(gap > e.hit_radius + 0.5, "magnetismo: se detiene al contacto, no atraviesa (%.2f m)" % gap)
	p.global_position = Vector3(0, 0.2, 0)
	p.facing = Vector3.FORWARD
	e.global_position = Vector3(1.0, 0.2, -3.6)
	p.stamina = p.stamina_max
	await physics_frame
	p.attack_light()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	var to_e := MeshUtil.flat(e.global_position - p.global_position)
	check(to_e.length() < 3.0, "magnetismo: el paso se curva hacia el objetivo cercano (%.2f m)" % to_e.length())
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	Arena.hitstop_enabled = true
	Arena.start_mounted = false
	quit(1 if fails > 0 else 0)
