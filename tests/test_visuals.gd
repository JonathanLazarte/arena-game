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
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.sim_ai.enabled = false
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
	# [fase 8] el caballo es un títere de SimWorld (se crea al montar); ver test_net_sim_match
	check(Arena.RADIUS == 42.0 and absf(Projectile.arena_radius - 42.0) < 0.01, "arena x1.4 (radio 42)")
	check(p._kv.accent_mat.albedo_color != e._kv.accent_mat.albedo_color, "cada luchador con su tinte")
	await wait(0.3)
	# [fase 8] retirado: «montado en reposo» (la montura es un títere de SimWorld; sin start_mounted)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Ataque: estado y velocidad ajustada por fase
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): A pie: bloqueo, parry, voltereta
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Golpe recibido y aturdimiento
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Arco: apuntar y cambiar
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Locomoción a pie
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Caballo libre: blend por velocidad
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Muerte
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Eikons con modelo
	quit(1 if fails > 0 else 0)