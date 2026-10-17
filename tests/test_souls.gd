extends SceneTree
## Ronda 4: combate estilo souls, armas (espada+escudo O arco), parry de 1 s y lectura de la IA.
## godot --headless --path . -s res://tests/test_souls.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	await physics_frame
	Input.action_release(action)

func idle(f: Fighter) -> void:
	while f.atk_state != Fighter.Atk.NONE or f.stun > 0.0:
		await physics_frame

func idle_atk(f: Fighter) -> void:
	while f.atk_state != Fighter.Atk.NONE:
		await physics_frame

func place(p: Fighter, e: Fighter, d: float) -> void:
	e.global_position = p.global_position + p.facing * d
	e.facing = -p.facing
	await physics_frame

func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9 # sin límite de tiempo de ronda durante la prueba
	seed(4)
	var p := arena.player
	var e := arena.enemy
	arena.sim_ai.enabled = false
	e.knockoff_chance_dash = 0.0 # derribos aleatorios fuera de la prueba de fuerte
	e.knockoff_chance_heavy = 0.0
	p.knockoff_chance_dash = 0.0
	p.knockoff_chance_heavy = 0.0
	e.max_health = 2000.0
	e.health = 2000.0
	p.max_health = 2000.0
	p.health = 2000.0
	await wait(0.5)
	await place(p, e, 3.0)
	await wait(0.3)

	# [fase 8] retirado: «no se puede spamear» (compromiso del ataque) vive en la sim; ver test_fight_sim (combo/recuperación)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 2. Durante la anticipación/recuperación no hay otras acciones ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Ronda 9: montado SÍ se puede hacer dash durante la anticipación (dash + ataque, ver test_d
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 3. Fallar el golpe = recuperación más larga, castigable ---
	await physics_frame
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 4. Ataque fuerte (mantener) ---
	var st0 := p.stamina
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 5. Poise / intercambio: un golpe interrumpe el ligero del rival ---
	var ph := p.health
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 6. Cambio de arma: 2 s sin atacar ni bloquear ---
	var swap_ok := true
	var hud_ok := false
	var tt := 0.0
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 7. Modo arco: sin escudo ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 8. Parry dedicado (ventana 0,3 s + recuperación vulnerable) --- (ronda 21: solo a pie)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): El escudo ya no hace parry: alzarlo justo antes = bloqueo normal
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Parry demasiado pronto: falla y queda expuesto (+25 % daño)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 9. La IA lee ataques: esquiva y castiga; se compromete con los suyos ---
	var e_attacked_recovery := false
	quit(fails)