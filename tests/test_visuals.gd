extends SceneTree
## Ronda 6: modelos CC0 + AnimationTree mapeado a estados de combate.
## godot --headless --path . -s res://tests/test_visuals.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	seed(6)
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.ai.enabled = false
	arena.controller.enabled = false
	arena.controller.set_physics_process(false)
	arena.controller.set_process(false)
	arena.time_left = 1.0e9
	var p := arena.player
	var e := arena.enemy
	p.knockoff_chance_heavy = 0.0
	e.knockoff_chance_heavy = 0.0
	var kv := p._kv
	check(kv.tree != null and kv.tree.active, "AnimationTree del caballero activo")
	check(p._shield == kv.shield and kv.sword.get_parent() is BoneAttachment3D and kv.bow.get_parent() is BoneAttachment3D, "armas en BoneAttachment3D (espada/escudo KayKit, arco propio)")
	check(p.owned_mount.tree != null and p.owned_mount.tree.active, "AnimationTree del caballo activo")
	check(Arena.RADIUS == 42.0 and absf(Projectile.arena_radius - 42.0) < 0.01, "arena x1.4 (radio 42)")
	check(p._kv.accent_mat.albedo_color != e._kv.accent_mat.albedo_color, "cada luchador con su tinte")
	await wait(0.3)
	check(kv.state == "none" and kv.mix.filter_enabled, "montado en reposo: sin acción, máscara de medio cuerpo activa")
	# Ataque: estado y velocidad ajustada por fase
	e.global_position = p.global_position + p.facing * 30.0
	p.attack_light()
	await physics_frame
	await physics_frame
	check(kv.state == "light0", "ataque ligero -> light0 (%s)" % kv.state)
	var sc: float = kv.tree.get("parameters/act/light0/ts/scale")
	var expect: float = kv._clip_len("light0") * KnightVisual.CONTACT / p.atk_dur
	check(p.atk_state == Fighter.Atk.WINDUP and absf(sc - expect) < 0.01, "windup ajusta la velocidad del clip (%.2f)" % sc)
	await wait(1.6)
	p.attack_heavy()
	await physics_frame
	await physics_frame
	check(kv.state == "heavy", "ataque fuerte -> heavy (2H chop)")
	await wait(2.2)
	# A pie: bloqueo, parry, voltereta
	p.dismount(false)
	await wait(0.8)
	check(not kv.mix.filter_enabled or kv.state == "none", "a pie sin acción: cuerpo completo")
	p.want_block = true
	await wait(0.2)
	check(kv.state == "block" and kv.mix.filter_enabled, "bloquear -> Blocking (medio cuerpo, se puede andar)")
	p.want_block = false
	await wait(0.2)
	p.parry()
	await physics_frame
	await physics_frame
	check(kv.state == "parry", "parry -> Block_Attack")
	await wait(1.3)
	p.stamina = Fighter.STAMINA_MAX
	p.move_input = p.facing.cross(Vector3.UP)
	await physics_frame
	p.dash()
	await physics_frame
	await physics_frame
	check(kv.state == "dodge_r", "voltereta lateral -> Dodge_Right (%s)" % kv.state)
	p.move_input = Vector3.ZERO
	await wait(Fighter.ROLL_TOTAL + 0.1) # la voltereta estilo DS dura 0.8 s (ronda 9)
	# Golpe recibido y aturdimiento
	p.take_hit(1.0, e, "melee")
	await physics_frame
	await physics_frame
	check(kv.state == "hit", "golpe -> Hit_A")
	await wait(0.6)
	p.apply_stun(1.0)
	await physics_frame
	await physics_frame
	check(kv.state == "stun", "aturdido -> Hit_B")
	await wait(1.2)
	# Arco: apuntar y cambiar
	p.swap_loadout()
	for i in 6: # ~0,1 s del cambio (0,42 s)
		await physics_frame
	check(kv.state == "swap" and kv.sword.visible and not kv.bow.visible and kv._swap_k < 0.95, "cambio de arma -> Use_Item, la espada se enfunda (encoge %.2f)" % kv._swap_k)
	await wait(2.2)
	check(kv.state == "aim" and kv.bow.visible, "modo arco -> 2H_Ranged_Aiming")
	# Locomoción a pie
	p.move_input = p.facing
	await wait(0.8)
	var bp: Vector2 = kv.tree.get("parameters/loco/blend_position")
	check(bp.y > 0.5, "andar hacia delante -> blend de locomoción (%.2f)" % bp.y)
	p.move_input = Vector3.ZERO
	await wait(0.6) # el jugador puede haber empujado al caballo al andar
	# Caballo libre: blend por velocidad
	var m := p.owned_mount
	var bpos: float = m.tree.get("parameters/blend_position")
	check(bpos < 0.5, "caballo sin jinete casi parado: Idle/Walk (%.2f)" % bpos)
	# Muerte
	p.take_hit(500.0, e, "melee")
	await wait(0.3)
	check(kv.state == "death", "muerte -> Death_A")
	# Eikons con modelo
	arena.time_left = 1.0e9
	e.meter = 100.0
	e.summon()
	await wait(0.5)
	var ek: Node = e.active_eikon
	check(ek != null and ((ek is Eikon and ek._ap != null and ek._ap.is_playing()) or (ek is Mount and ek.tree != null and ek.tree.active)), "eikon con modelo animado (%s)" % [e.eikon.eikon_name])
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(1 if fails > 0 else 0)
