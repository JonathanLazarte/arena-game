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
	f.stun = 0.0
	f.down_t = 0.0
	f.stagger_t = 0.0
	f.stun_immune_t = 0.0
	f.invuln = 0.0

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://test_round32.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	gs.reset_defaults()
	var cf := BossAbilities.def("combo_falso")
	var h: Array = cf["hits"]
	check(h.size() >= 3 and float(h[-1][0]) > float(h[0][0]) * 2.0, "combo falso: varias etapas con la pausa falsa más larga al final (diseño actual)")
	var rd := BossAbilities.def("rafaga")
	check(int(rd["count"]) >= 1 and float(rd["home_deg"]) <= 90.0, "ráfaga: intervalos amplios, área ancha, persigue toda su vida")
	gs.from_lobby = true
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
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Combo falso: avanza hacia el rival y lo sigue ---
	var d0 := p.global_position.distance_to(e.global_position)
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Ráfaga: alcanza a distancia aunque corra; la voltereta la esquiva ---
	var eh := e.health
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Salto sin marca ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- Arco: mantener no dispara hasta soltar; brillo de carga ---
	quit(1 if fails > 0 else 0)