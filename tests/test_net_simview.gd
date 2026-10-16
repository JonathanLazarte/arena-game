extends SceneTree
## Fase online 1: los Fighter existentes como vista de la simulación (sim_driven) sin cambiar el offline.
## godot --headless --path . -s res://tests/test_net_simview.gd
const S = preload("res://net/sim/fight_sim.gd")
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	var w := Node3D.new(); root.add_child(w)
	var a := Fighter.new(); a.team = 0
	var b := Fighter.new(); b.team = 1
	w.add_child(a); w.add_child(b)
	await physics_frame
	check(not a.sim_driven and not b.sim_driven, "por defecto los luchadores son offline (sim_driven = false)")
	var P := SimParams.bake(a, b)
	var view := SimView.new(a, b, w)
	check(a.sim_driven and b.sim_driven, "SimView activa el modo online")
	var s := FightSim.initial(P, 1, true)
	s[S.X] = 0; s[S.F_FIELDS + S.X] = 1800000
	var saw_atk := false
	var saw_roll := false
	for t in 120:
		var i0 := S.IN_ATK if t == 1 else 0
		var i1 := S.make_input(0, true, S.IN_ROLL) if t == 60 else 0
		FightSim.step(s, P, i0, i1)
		view.apply(s)
		await physics_frame
		saw_atk = saw_atk or a.atk_state != Fighter.Atk.NONE
		saw_roll = saw_roll or b.is_rolling()
	check(is_equal_approx(b.health, s[S.F_FIELDS + S.HP] / 1000.0) and b.health < b.max_health, "la vida del nodo refleja la sim (%.1f)" % b.health)
	check(absf(b.global_position.x - s[S.F_FIELDS + S.X] / 1000000.0) < 0.001, "la posición del nodo es la de la sim (el nodo no se mueve solo)")
	check(saw_atk and saw_roll, "estados de ataque y voltereta llegan a la vista (animación)")
	# re-simular no toca los nodos: aplicar un estado guardado antiguo restaura la vista
	var old := FightSim.initial(P, 1, true)
	view.apply(old)
	check(is_equal_approx(b.health, b.max_health), "aplicar un estado restaurado (rollback) rehace la vista")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
