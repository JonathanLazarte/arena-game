extends SceneTree
## Ronda 32: pose de carga del fuerte, combo falso lento con avance, ráfaga dorada 100 % teledirigida,
## salto sin marca, arco que dispara al soltar (con brillo de carga) y botón para cambiar de habilidad.
## godot --headless --path . -s res://tests/test_round32.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _fresh(f: Fighter) -> void:
	f.health = f.max_health
	f.exhausted = 0.0
	f.stamina = f.stamina_max
	f.energy = f.energy_max
	f._cancel_attack()
	f.stun = 0.0
	f.down_t = 0.0
	f.stagger_t = 0.0
	f.stun_immune_t = 0.0
	f.invuln = 0.0
	f._reset_stun_meter()

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round32.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	var cf := BossAbilities.def("combo_falso")
	var h: Array = cf["hits"]
	check(float(h[1][0]) - float(h[0][0]) >= 2.8 and float(h[3][0]) - float(h[2][0]) > float(h[2][0]) - float(h[1][0]), "combo falso lento (~3 s entre golpes) con la pausa falsa más larga al final")
	var rd := BossAbilities.def("rafaga")
	check(float(rd["interval"]) >= 0.8 and float(rd["radius"]) >= 1.2 and float(rd["home_time"]) >= float(rd["life"]), "ráfaga: intervalos amplios, área ancha, persigue toda su vida")
	Arena.start_mounted = false
	gs.from_lobby = true
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
	# --- HUD: flecha para cambiar de habilidad ---
	p.set_boss_abilities(["estocada", "rafaga", "combo_falso"])
	await process_frame
	await process_frame
	var bn: Button = arena.hud.boss_next_btn
	check(bn != null and bn.visible, "botón ▶ de habilidad de jefe visible (PC y táctil)")
	p.boss_sel = 0
	bn.pressed.emit()
	check(p.selected_boss() == "rafaga", "el botón cambia la habilidad seleccionada")
	# --- Pose de carga del fuerte desde que se mantiene ---
	_fresh(p)
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(0, 0, -15)
	p.hold_pose_t = 0.15
	await physics_frame
	await physics_frame
	check(p.atk_state == Fighter.Atk.NONE and p._kv.state == "heavy", "mantener ataque: la pose de carga se ve antes de que salga el fuerte (%s)" % p._kv.state)
	p.hold_pose_t = 0.0
	await physics_frame
	# --- Combo falso: avanza hacia el rival y lo sigue ---
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(3, 0, -6)
	p.facing = Vector3(0, 0, -1)
	p.face_target = e
	var d0 := p.global_position.distance_to(e.global_position)
	check(p.boss_skill("combo_falso"), "combo falso")
	await create_timer(1.4).timeout
	var d1 := p.global_position.distance_to(e.global_position)
	check(d1 < d0 - 1.5 and p.facing.dot(MeshUtil.flat(e.global_position - p.global_position).normalized()) > 0.8, "cada golpe avanza hacia el rival apuntándole (%.1f → %.1f m)" % [d0, d1])
	check(p.ab_id == "combo_falso" and p.ab_fired == 1, "a 1,4 s solo ha salido el primer golpe (lento)")
	p._end_ability(true)
	# --- Ráfaga: alcanza a distancia aunque corra; la voltereta la esquiva ---
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 8)
	e.global_position = Vector3(0, 0, -12)
	p.face_target = e
	var eh := e.health
	check(p.boss_skill("rafaga"), "ráfaga")
	for i in 220:
		e.move_input = Vector3(1, 0, 0)
		e.want_sprint = true
		e.stun = 0.0
		await physics_frame
	e.move_input = Vector3.ZERO
	e.want_sprint = false
	var slashes := 0
	for n in get_nodes_in_group("projectile"):
		if (n as Projectile).slash: slashes += 1
	check(e.health < eh, "corriendo a distancia NO escapa (%.0f daño)" % (eh - e.health))
	await create_timer(1.0).timeout
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(0, 0, -6)
	eh = e.health
	arena.ai.enabled = true
	arena.ai.profile.boss_dodge_chance = 1.0
	var r0: int = arena.ai.slash_rolls
	p.energy = p.energy_max
	check(p.boss_skill("rafaga"), "ráfaga contra la IA")
	await create_timer(3.5).timeout
	check(arena.ai.slash_rolls - r0 >= 2, "la IA rueda cada tajo (%d volteretas)" % (arena.ai.slash_rolls - r0))
	arena.ai.enabled = false
	# --- Salto sin marca ---
	p.set_boss_abilities(["salto_caida", "rafaga", "combo_falso"])
	_fresh(p)
	_fresh(e)
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(0, 0, -4)
	p.health = p.max_health
	check(p.boss_skill("salto_caida"), "salto con caída")
	await create_timer(1.4).timeout
	var hid := 0
	var vis := 0
	for n in get_nodes_in_group("ground_aoe"):
		var a := n as GroundAoE
		if not a.hidden: vis += 1
		else: hid += 1
	check(p.ab_marker == null and vis == 0 and hid == 1, "sin marca ni anillo en el suelo")
	await create_timer(1.5).timeout
	_fresh(p)
	_fresh(e)
	arena.ai.enabled = true
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(0, 0, -4)
	var jd: int = arena.ai.jump_dodges
	var ehh := e.health
	check(p.boss_skill("salto_caida"), "salto contra la IA")
	await create_timer(2.4).timeout
	check(arena.ai.jump_dodges > jd or e.health == ehh, "la IA reacciona al verle bajar (rueda o se aparta)")
	arena.ai.enabled = false
	await create_timer(1.0).timeout
	# --- Arco: mantener no dispara hasta soltar; brillo de carga ---
	_fresh(p)
	if p.loadout != Fighter.Loadout.BOW:
		p.swap_loadout()
		await create_timer(0.8).timeout
	var shots := p.shots_fired
	p.want_shot_hold = true
	p.shoot()
	await create_timer(3.0).timeout
	check(p.shots_fired == shots and p.shot_state == Fighter.Shot.DRAW, "mantener: tensa y apunta, no dispara")
	check(p.bow_charged_ready() and p._kv.bow_charged and p.charge_ready_events >= 1, "carga completa: brillo en el arco + aviso")
	p.want_shot_hold = false
	await create_timer(0.2).timeout
	check(p.shots_fired == shots + 1 and p.charged_shots >= 1 and not p._kv.bow_charged, "al soltar sale el tiro cargado y se apaga el brillo")
	await create_timer(1.0).timeout
	shots = p.shots_fired
	var c0 := p.charged_shots
	p.stamina = p.stamina_max
	p.want_shot_hold = true
	p.shoot()
	await create_timer(p.ranged().fire_draw / p.attr_speed() + 0.2).timeout
	check(p.shots_fired == shots, "aún sin disparar mientras se mantiene")
	p.want_shot_hold = false
	await create_timer(0.2).timeout
	check(p.shots_fired == shots + 1 and p.charged_shots == c0, "soltar antes del umbral = tiro normal")
	print("RESULT: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
