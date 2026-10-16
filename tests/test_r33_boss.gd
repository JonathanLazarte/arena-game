extends SceneTree
## Ronda 33 (bloque final): imbloqueables, estocada con autoseguimiento de 0,15 s, aura dorada,
## avisos móviles +12 %, búfer de voltereta 0,18 s, recarga global 1,4 s, caché de rival,
## tope de partículas y las 13 habilidades de jefe extendidas.
## godot --headless --path . -s res://tests/test_r33_boss.gd
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
	f.boss_cd = 0.0
	f.ab_cds.clear()
	f._reset_stun_meter()

func _run() -> void:
	await process_frame
	var NEW := ["tajo_retardado", "presa_verdugo", "giro_martillo", "danza_cisne", "paso_espectral",
		"onda_rastrera", "rayos_trazadores", "lluvia_meteoros", "aliento_dragon", "furia_fase",
		"postura_contra", "embate_sismico", "lanza_celeste"]
	check(BossAbilitiesExt.ids().size() == 13, "13 habilidades extendidas")
	var teles := {}
	var cols := {}
	for id: String in BossAbilities.all_ids():
		var d := BossAbilities.def(id)
		var tt := BossAbilities.telegraph_text(id)
		check(tt != "" and not teles.has(tt), "aviso único: %s" % id)
		teles[tt] = true
		check(["stamina", "mana", "health"].has(String(d.get("cost_type", ""))) and float(d.get("cost", 0)) > 0.0, "coste de recurso: %s" % id)
	for id: String in NEW:
		var d := BossAbilities.def(id)
		check(not d.is_empty(), "definida: %s" % id)
		var rec := float(d.get("recovery", d.get("recovery_miss", 0.0)))
		check(rec >= 0.3, "recuperación castigable: %s (%.2f s)" % [id, rec])
		if id != "furia_fase":
			var frc := float(d.get("force", 0.0))
			for h: Array in d.get("hits", []):
				frc = maxf(frc, float(h[2]))
			frc = maxf(frc, float(d.get("cforce", 0.0)))
			check(frc > 0.0, "poder de aturdimiento: %s" % id)
		var c: Color = d.get("color", Color.WHITE)
		check(not cols.has(c), "color de aviso propio: %s" % id)
		cols[c] = true
	check(BossAbilities.is_unblockable("estocada") and BossAbilities.is_unblockable("presa_verdugo"), "estocada y presa imbloqueables")
	check(not BossAbilities.is_unblockable("danza_cisne"), "danza del cisne sí se bloquea/parrea")
	check(float(BossAbilities.def("estocada")["home_time"]) == 0.15 and Fighter.BOSS_LUNGE_HOME_T == 0.15, "estocada: autoseguimiento 0,15 s")
	check(Fighter.BOSS_GLOBAL_CD == 1.4 and Fighter.ROLL_BUFFER == 0.18 and Fighter.MAX_BURSTS == 6, "constantes R33")

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
	check(absf(p.telegraph_k - (1.12 if OS.has_feature("mobile") else 1.0)) < 0.001, "telegraph_k móvil = 1,12")

	# Caché del rival más cercano
	check(p._nearest_enemy() == e, "rival más cercano cacheado")
	# Tope de partículas
	for i in 12:
		p._burst_particles(Color.RED)
	check(Fighter.bursts_live <= 6, "máx. 6 ráfagas de partículas (%d)" % Fighter.bursts_live)

	# Aura dorada
	_fresh(p)
	p.invuln = 0.5
	await physics_frame
	await physics_frame
	check(p.golden_aura_active() and p._aura != null and p._aura.emitting, "aura dorada con invulnerabilidad")
	p.invuln = 0.0
	await physics_frame
	check(not p.golden_aura_active(), "sin aura dorada al acabar")

	# Recarga global
	_fresh(p)
	p.set_boss_abilities(["furia_fase", "embate_sismico", "lanza_celeste"])
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(0, 0, -6)
	p.face_target = e
	check(p.boss_skill("furia_fase"), "Furia de Fase")
	await create_timer(0.9).timeout
	check(p.ab_id == "" and p.boss_cd > 0.0, "recarga global activa tras la habilidad")
	check(not p.boss_skill("lanza_celeste"), "recarga global bloquea otra habilidad")
	await create_timer(1.5).timeout
	# Lanza Celeste
	var eh := e.health
	p.health = p.max_health
	check(p.boss_skill("lanza_celeste"), "Lanza Celeste tras la recarga global")
	await create_timer(2.0).timeout
	check(e.health < eh, "Lanza Celeste impacta al objetivo quieto")
	await create_timer(1.6).timeout
	# Embate Sísmico: coste de vida nunca deja a 0
	_fresh(p)
	_fresh(e)
	p.health = 10.0
	check(not p.boss_skill("embate_sismico"), "Embate Sísmico no se usa si dejaría la vida a 0")
	p.health = p.max_health
	e.global_position = Vector3(4, 0, 0)
	eh = e.health
	check(p.boss_skill("embate_sismico"), "Embate Sísmico iniciado")
	await create_timer(2.2).timeout
	check(e.health < eh, "las ondas en anillo alcanzan al rival a un lado")
	await create_timer(1.5).timeout
	# Recarga por habilidad opcional
	_fresh(p)
	Fighter.per_ability_cd_enabled = true
	check(p.boss_skill("furia_fase") and float(p.ab_cds.get("furia_fase", 0.0)) > 0.0, "recarga propia opcional registrada")
	Fighter.per_ability_cd_enabled = false
	await create_timer(0.9).timeout
	p.boss_cd = 0.0
	check(not p.can_use_boss("furia_fase"), "recarga propia bloquea repetir")

	# Búfer de voltereta
	_fresh(p)
	p.move_input = Vector3.FORWARD
	check(p.attack_light(), "ataque ligero")
	p.dash()
	check(p.roll_buf_t > 0.0, "voltereta en búfer durante el ataque")
	await create_timer(0.25).timeout
	check(p.roll_buf_t == 0.0, "el búfer expira o se consume en 0,18 s")

	print("RESULT: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
