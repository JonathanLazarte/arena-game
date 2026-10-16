extends SceneTree
## Ronda 34: BossAbilitiesExt conectadas (tajo retardado, paso espectral, onda rastrera,
## postura de contragolpe, furia de fase), GroundWave, hitstop local y curva de paso de ataque.
## godot --headless --path . -s res://tests/test_round34.gd
var fails := 0

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	_run()

func _fresh(f: Fighter) -> void:
	f._end_ability(true)
	f._end_boss()
	f._cancel_attack()
	f.health = f.max_health
	f.stamina = f.stamina_max
	f.energy = f.energy_max
	f.exhausted = 0.0
	f.stun = 0.0
	f.down_t = 0.0
	f.stagger_t = 0.0
	f.stun_immune_t = 0.0
	f.invuln = 0.0
	f.rage_t = 0.0
	f._reset_stun_meter()

func _run() -> void:
	await process_frame
	check(BossAbilities.all_ids().size() == 17, "17 habilidades de jefe registradas (6 base + 11 extendidas)")
	for id: String in BossAbilitiesExt.ids():
		check(BossAbilities.has(id) and BossAbilities.codex(id).length() > 30, "códice y definición disponibles para %s" % id)
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1e9
	await create_timer(3.3).timeout
	var p := arena.player
	var e := arena.enemy
	arena.controller.set_physics_process(false)

	# 1. Onda Rastrera (GroundWave)
	_fresh(p)
	_fresh(e)
	p.set_boss_abilities(["onda_rastrera", "paso_espectral", "postura_contra"])
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -7)
	p.facing = Vector3.FORWARD
	p.face_target = e
	var eh0 := e.health
	check(p.boss_skill("onda_rastrera"), "Onda Rastrera iniciada")
	await create_timer(1.8).timeout
	check(e.health < eh0, "GroundWave impacta al enemigo en el suelo (%.1f -> %.1f)" % [eh0, e.health])
	await create_timer(0.6).timeout

	# 2. Paso Espectral (teletransporte a la espalda + golpe)
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 4)
	e.global_position = Vector3(0, 0, -2)
	e.facing = Vector3.BACK
	p.face_target = e
	eh0 = e.health
	check(p.boss_skill("paso_espectral"), "Paso Espectral iniciado")
	await create_timer(1.3).timeout
	check(p.global_position.z < e.global_position.z and e.health < eh0, "Paso Espectral reaparece detrás del rival y golpea")
	await create_timer(1.0).timeout

	# 3. Postura de Contragolpe
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -2.0)
	p.facing = Vector3.FORWARD
	var ph0 := p.health
	eh0 = e.health
	check(p.boss_skill("postura_contra"), "Postura de Contragolpe iniciada")
	await create_timer(0.45).timeout
	var res := p.take_hit(25.0, e, "melee")
	check(res == "parry" and p.health == ph0 and e.health < eh0, "Postura de Contragolpe anula el daño y castiga al atacante")
	await create_timer(1.0).timeout

	# 4. Furia de Fase
	_fresh(p)
	p.set_boss_abilities(["furia_fase"])
	var dmg0 := p.damage_mult()
	check(p.boss_skill("furia_fase"), "Furia de Fase iniciada")
	await create_timer(0.6).timeout
	check(p.rage_t > 0.0 and p.damage_mult() > dmg0 * 1.25, "Furia de Fase activa buff de daño y velocidad")

	print("RESULT: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
