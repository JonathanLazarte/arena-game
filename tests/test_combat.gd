extends SceneTree
## Prueba automática: godot --headless --path . -s res://tests/test_combat.gd
## Ejercita espada, bloqueo, parry, arco e invocación usando acciones de entrada.

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

func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	arena.ai.enabled = false
	await wait(0.3)
	e.global_position = p.global_position + p.facing * 2.8
	e.facing = -p.facing
	await wait(0.3)
	# Espada
	var h0 := e.health
	var m0 := p.meter
	await tap("attack_sword")
	await wait(0.5)
	check(e.health < h0, "espada daña al rival (%.0f -> %.0f)" % [h0, e.health])
	check(p.meter > m0, "medidor eikon del jugador sube (%.0f -> %.0f)" % [m0, p.meter])
	check(is_equal_approx(arena.hud.e_health.value, e.health), "HUD refleja vida del rival")
	# Bloqueo (mantener > ventana de parry)
	Input.action_press("block")
	await wait(0.5)
	var ph := p.health
	e.sword()
	await wait(0.4)
	var blocked := ph - p.health
	Input.action_release("block")
	await wait(0.8)
	ph = p.health
	e.sword()
	await wait(0.4)
	var unblocked := ph - p.health
	check(unblocked > 0.0 and blocked < unblocked, "escudo reduce daño (bloq %.1f vs sin %.1f)" % [blocked, unblocked])
	# Parry (bloqueo justo antes del golpe)
	await wait(0.8)
	ph = p.health
	e.sword()
	await physics_frame
	Input.action_press("block")
	await wait(0.35)
	Input.action_release("block")
	check(e.stun > 0.0 and is_equal_approx(ph, p.health), "parry aturde al rival sin daño (stun %.2f)" % e.stun)
	# Arco
	await wait(1.0)
	e.global_position = p.global_position + p.facing * 12.0
	await wait(0.3)
	h0 = e.health
	await tap("shoot_bow")
	await wait(1.0)
	check(e.health < h0, "flecha daña al rival (%.0f -> %.0f)" % [h0, e.health])
	# Invocación
	p.meter = Fighter.METER_MAX
	await tap("summon")
	await wait(0.2)
	check(is_instance_valid(p.active_eikon), "eikon invocado (%s)" % (p.eikon.eikon_name))
	check(p.meter == 0.0, "medidor se vacía al invocar")
	h0 = e.health
	await wait(4.0)
	check(e.health < h0, "eikon daña al rival (%.0f -> %.0f)" % [h0, e.health])
	# El eikon es objetivo: el rival puede dañarlo
	if is_instance_valid(p.active_eikon):
		var eik: Eikon = p.active_eikon as Eikon
		var eh := eik.health
		eik.take_hit(10.0, e, "arrow")
		check(eik.health < eh, "eikon puede recibir daño")
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(fails)
