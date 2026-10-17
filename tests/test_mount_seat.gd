extends SceneTree
## El fénix sienta al jinete en el lomo, y cerrar la ronda no llama a una función que no existe.
## godot --headless --path . -s res://tests/test_mount_seat.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(parent: Node, ek: String) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS[ek])
	parent.add_child(f)
	return f

func _summon(a: Fighter, b: Fighter) -> Dictionary:
	var P := SimParams.bake(a, b)
	var e := FightEngine.new(P, 5, true)
	var s := e.initial()
	s[FightSim.METER] = FightSim.METER_MAX
	for t in 4:
		e.step(s, FightSim.IN_EIKON if t == 0 else 0, 0)
	return {"s": s, "P": P}

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var A := _fighter(world, "fenix")
	var B := _fighter(world, "lobo")
	await process_frame
	var sum := _summon(A, B)
	check(sum.s[FightSim.EK_T] > 0 and sum.s[FightSim.MOUNTED] != 0, "fénix invocado y montado en la sim")
	var view := SimView.new(A, B, world)
	view.params = sum.P
	view.apply(sum.s)
	check(A.mounted and A.mount_node != null and A.mount_node.is_flying(), "la vista crea el fénix y monta")
	for _i in 12:
		await physics_frame
	var seat := A.mount_node.saddle_position()
	var hip := A._rider_root.global_position
	check(absf(hip.y - seat.y) < 0.08, "la cadera queda en la silla (cadera %.2f, silla %.2f)" % [hip.y, seat.y])
	check(hip.y > 1.7, "el jinete sube al lomo, no se queda a 1,3 m (%.2f)" % hip.y)
	check(absf(A.mount_node.model.position.y) < 0.01, "el modelo no suma el vuelo otra vez")
	A.dismiss_eikon()
	check(A.active_eikon == null and not A.mounted and A.mount_node == null, "dismiss_eikon retira el fénix")
	view.apply(sum.s)
	check(not A.mounted and A.active_eikon == null, "con la invocación aún viva en la sim no se redibuja al momento")
	# Lobo: el hueso Torso está en el origen; la silla sigue siendo el offset fijo.
	var world2 := Node3D.new()
	root.add_child(world2)
	var C := _fighter(world2, "lobo")
	var D := _fighter(world2, "fenix")
	await process_frame
	var sum2 := _summon(C, D)
	check(sum2.s[FightSim.MOUNTED] != 0, "lobo montado en la sim")
	var view2 := SimView.new(C, D, world2)
	view2.params = sum2.P
	view2.apply(sum2.s)
	for _i in 6:
		await physics_frame
	check(C.mounted and not C.mount_node.is_flying(), "el lobo no vuela")
	check(absf(C._rider_root.position.y - 1.3) < 0.05, "el lobo conserva la silla a 1,3 m (%.2f)" % C._rider_root.position.y)
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
