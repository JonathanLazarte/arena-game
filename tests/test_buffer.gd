extends SceneTree
## Ronda 23: búfer de entrada (acciones pulsadas antes de poder hacerse), hit-stop y ajuste.
## godot --headless --path . -s res://tests/test_buffer.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func tap(a: String) -> void:
	Input.action_press(a)
	await physics_frame
	await physics_frame
	Input.action_release(a)
	await physics_frame

func until(cond: Callable, max_t: float = 3.0) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await physics_frame
		t += 1.0 / 60.0
	return cond.call()

func ready_p(p: Fighter) -> void:
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE and p.stun <= 0.0 and not p.is_swapping() and p.roll_t < 0.0 and p.dash_cd <= 0.0 and p.land_t <= 0.0 and not p.airborne)
	p.stamina = p.stamina_max

func _run() -> void:
	await process_frame
	var au := root.get_node("Audio")
	au.settings_path = "user://test_buffer_ajustes.cfg"
	Arena.start_mounted = false
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
	e.global_position = p.global_position + p.facing * 8.0
	check(is_equal_approx(PlayerController.BUFFER_WINDOW, 0.4), "ventana por defecto 0,4 s")
	# 1. Cambio de arma pulsado al final del golpe: sale después
	await ready_p(p)
	p.attack_light()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY and p.atk_dur - p.atk_t < 0.3)
	await tap("swap_weapon")
	check(c.buffered == "swap" and not p.is_swapping(), "cambio pulsado al final de la recuperación: queda en el búfer")
	await until(func() -> bool: return p.is_swapping(), 1.0)
	check(p.is_swapping() and "swap" in c.buffer_fired and c.buffered == "", "el cambio sale en cuanto termina el golpe")
	await until(func() -> bool: return not p.is_swapping())
	await tap("swap_weapon") # vuelve a espada
	await until(func() -> bool: return not p.is_swapping() and p.loadout == Fighter.Loadout.SWORD_SHIELD)
	# 2. Caducidad
	await ready_p(p)
	PlayerController.buffer_window = 0.1
	p.attack_heavy()
	await physics_frame
	await tap("swap_weapon")
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	await physics_frame
	check(not p.is_swapping() and c.buffered == "", "pasada la ventana, la pulsación se descarta")
	PlayerController.buffer_window = PlayerController.BUFFER_WINDOW
	# 3. Un golpe recibido vacía el búfer
	await ready_p(p)
	p.attack_light()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY)
	await tap("swap_weapon")
	check(c.buffered == "swap", "en búfer antes del golpe")
	p.apply_stun(0.3)
	await physics_frame
	await physics_frame
	check(c.buffered == "", "aturdido por un golpe: búfer vacío")
	await until(func() -> bool: return p.stun <= 0.0 and p.atk_state == Fighter.Atk.NONE)
	await physics_frame
	check(not p.is_swapping(), "no sale lo que se pulsó antes del golpe")
	# 4. Pulsado durante el aturdimiento: sale al recuperarse
	await ready_p(p)
	p.apply_stun(0.3)
	await physics_frame
	await create_timer(0.1).timeout
	await tap("dash")
	check(c.buffered == "dash" and p.roll_t < 0.0, "esquiva pulsada aturdido: en búfer")
	await until(func() -> bool: return p.roll_t >= 0.0, 0.6)
	check(p.roll_t >= 0.0, "la voltereta sale apenas termina el aturdimiento")
	# 5. Prioridad: la esquiva guardada no la pisa otra acción
	await ready_p(p)
	p.attack_light()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY)
	p.atk_t = 0.0 # aún sin cancelar
	await tap("dash")
	var was := String(c.buffered)
	await tap("swap_weapon")
	check(was == "dash" and c.buffered in ["dash", ""], "la esquiva en búfer tiene prioridad sobre el cambio")
	await until(func() -> bool: return p.roll_t >= 0.0, 1.0)
	check(p.roll_t >= 0.0 and not p.is_swapping(), "sale la esquiva (cancela la recuperación)")
	# 6. Combo: el ligero pulsado durante el golpe encadena (y no dispara un ataque de más)
	await ready_p(p)
	p.attack_light()
	var started := p.attacks_started
	await until(func() -> bool: return p.atk_t > p.atk_dur * 0.6)
	await tap("attack_sword")
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	check(p.attacks_started - started == 1, "ligero en búfer = siguiente golpe del combo (%d)" % (p.attacks_started - started))
	await create_timer(0.6).timeout
	check(p.atk_state == Fighter.Atk.NONE, "sin ataque extra después del combo")
	# 7. Salto pulsado en la recuperación
	await ready_p(p)
	p.attack_light()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY and p.atk_dur - p.atk_t < 0.3)
	await tap("jump")
	await until(func() -> bool: return p.airborne, 1.0)
	check(p.airborne, "salto en búfer sale tras el golpe")
	await until(func() -> bool: return not p.airborne)
	# 8. Hit-stop en golpe fuerte
	await ready_p(p)
	e.global_position = p.global_position + p.facing * 1.8
	e.poise_max = 1e6
	e.poise = 1e6
	var hs := arena.hitstops
	p.attack_heavy()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	await create_timer(0.2).timeout
	check(arena.hitstops > hs and is_equal_approx(Engine.time_scale, 1.0), "golpe fuerte: hit-stop y vuelve el tiempo normal")
	# 9. Ajuste persistente
	au.set_buffer_window(0.75)
	PlayerController.buffer_window = 0.4
	au.load_settings()
	check(is_equal_approx(PlayerController.buffer_window, 0.75), "la ventana del búfer se guarda en Ajustes")
	au.set_buffer_window(PlayerController.BUFFER_WINDOW)
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
