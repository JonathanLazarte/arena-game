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

func _run() -> void:
	await process_frame
	check(BossAbilities.all_ids().size() == 45, "45 habilidades de jefe registradas (6 base + 39 extendidas)")
	for id: String in BossAbilitiesExt.ids():
		check(BossAbilities.has(id) and BossAbilities.codex(id).length() > 30, "códice y definición disponibles para %s" % id)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.sim_ai.enabled = false
	arena.time_left = 1e9
	await create_timer(3.3).timeout
	var p := arena.player
	var e := arena.enemy
	arena.controller.set_physics_process(false)

	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 1. Onda Rastrera (GroundWave)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 2. Paso Espectral (teletransporte a la espalda + golpe)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 3. Postura de Contragolpe
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 4. Furia de Fase
	quit(1 if fails > 0 else 0)