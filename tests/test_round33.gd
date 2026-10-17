extends SceneTree
## Ronda 33: autoseguimiento calibrado (giro fijo + velocidad), roll, hundimiento, combo de 3, armadura/inbloqueable.
## godot --headless --path . -s res://tests/test_round33.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

## Simulación pura (sin escena) del tajo teledirigido contra un objetivo que corre de lado.
static func homing_hits(dist: float, side_speed: float) -> bool:
	var d := BossAbilities.def("rafaga")
	var v := float(d["speed"])
	var w := deg_to_rad(float(d["home_deg"]))
	var cap := float(d["radius"]) + 0.75
	var p := Vector2.ZERO
	var dir := Vector2(0, 1)
	var t := Vector2(0, dist)
	var homing := true
	var time := 0.0
	var dt := 1.0 / 60.0
	while time < float(d["life"]):
		t.x += side_speed * dt
		var want := t - p
		if want.length() < cap:
			return true
		var a := dir.angle_to(want)
		if absf(a) > PI * 0.5:
			homing = false
		if homing:
			dir = dir.rotated(clampf(a, -w * dt, w * dt))
		p += dir * v * dt
		time += dt
	return false

func _run() -> void:
	await process_frame
	var sprint := 8.3 * 1.3
	check(homing_hits(3.0, sprint), "de cerca (3 m) correr de lado no basta: solo la voltereta")
	check(not homing_hits(8.0, sprint) and not homing_hits(12.0, sprint), "a media distancia (8-12 m) correr de lado lo esquiva")
	check(homing_hits(12.0, 4.1), "a media distancia caminando te alcanza")
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 3. La voltereta no se hunde ---
	quit(1 if fails > 0 else 0)