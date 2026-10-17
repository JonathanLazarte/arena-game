extends SceneTree
## Fase 9: apuntado del arco con el ratón como entrada de la sim (IN_AIM + rumbo en 6 bits).
## godot --headless --path . -s res://tests/test_bow_aim.gd
const S = preload("res://net/sim/fight_sim.gd")
var fails := 0
var P: Array
const F := S.F_FIELDS
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func duel(gap: float) -> PackedInt64Array:
	var s := S.initial(P, 1, false)
	s[S.X] = 0
	s[S.Z] = 0
	s[F + S.X] = int(gap * 1000000.0)
	s[F + S.Z] = 0
	return s

## Dispara una flecha con el arco (cambio a arco y toque de ataque) con la entrada extra `aim`.
## Devuelve el rumbo (0..255) de la primera flecha viva, o -1.
func shot_heading(aim: int) -> int:
	var s := duel(10.0)
	for t in 120:
		var inp := (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t >= 40 and t <= 41 else 0) | (aim if t >= 30 else 0)
		S.step(s, P, inp, 0)
		for j in S.PROJ_MAX:
			var q := S.PROJ_BASE + j * S.PR_FIELDS
			if s[q + S.PR_ON] != 0 and s[q + S.PR_OWNER] == 0 and s[q + S.PR_KIND] == 0:
				return FxMath.dir_of(s[q + S.PR_VX], s[q + S.PR_VZ])
	return -1

func hdiff(a: int, b: int) -> int:
	var d := absi(a - b) % 256
	return mini(d, 256 - d)

func _initialize() -> void:
	P = SimParams.defaults()
	# codificación
	var ok := true
	for h in 256:
		var v := S.aim_bits(h)
		if hdiff(S.aim_heading(v), h) > 2 or (v & S.IN_AIM) == 0 or v >= (1 << 31) or (v & 0xFFFFFF) != 0:
			ok = false
	check(ok, "aim_bits: 64 rumbos (±2), bit 30, sin tocar los bits 0-23 ni el 31")
	var packed := PackedInt32Array([S.aim_bits(200) | S.IN_ATK | 17])
	check(int(packed[0]) == (S.aim_bits(200) | S.IN_ATK | 17), "cabe en el paquete int32 sin cambiar de signo")
	# disparos
	var h0 := shot_heading(0)
	check(h0 >= 0 and hdiff(h0, 0) <= 3, "sin apuntado: la flecha va al rival (rumbo %d)" % h0)
	var h90 := shot_heading(S.aim_bits(64))
	check(h90 >= 0 and hdiff(h90, 64) <= 3, "mira a 90° del rival: la flecha sale hacia la mira (rumbo %d)" % h90)
	var h200 := shot_heading(S.aim_bits(200))
	check(h200 >= 0 and hdiff(h200, 200) <= 3, "mira a la espalda: hacia la mira (rumbo %d)" % h200)
	var hnear := shot_heading(S.aim_bits(6))
	check(hnear >= 0 and hdiff(hnear, 0) <= 3, "mira a ~8° del rival: corrige hacia él (rumbo %d)" % hnear)
	# encararse a la mira mientras tensa
	var s := duel(10.0)
	for t in 80:
		S.step(s, P, (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t >= 40 else 0) | (S.aim_bits(128) if t >= 30 else 0), 0)
	check(hdiff(s[S.FACE], 128) <= 4, "tensando con mira atrás: se gira hacia ella (rumbo %d)" % s[S.FACE])
	# espada: la mira no cambia nada
	var a := duel(3.0); var b := duel(3.0)
	for t in 90:
		var base := (S.IN_ATK if t == 10 else 0) | ((t % 32) | S.IN_MOVE if t > 40 else 0)
		S.step(a, P, base, 0)
		S.step(b, P, base | S.aim_bits(99), 0)
	check(a[S.X] == b[S.X] and a[S.FACE] == b[S.FACE] and a[F + S.HP] == b[F + S.HP], "con espada la mira no influye")
	# rollback con apuntado cambiante
	for rtt in [80, 180]:
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.seed_v = 21 + rtt; h.loss = 0.04
		h.bot_mask = 0x3FFF & ~S.IN_BLOCK
		h.engine_factory = func() -> RbEngine: return FightEngine.new(P, 9, true)
		h.input_fn = func(i: int, t: int, bot: int) -> int:
			var v := (bot & ~S.IN_SWAP & ~S.IN_ATK) | (S.IN_SWAP if t == 150 else 0) | (S.IN_ATK if t % 30 < 2 else 0)
			return v | S.aim_bits((t * 7 + i * 90) & 255) if (t / 20) % 2 == 0 else v
		var r := h.run(900)
		var shots: int = h.last_peers[0].state[S.SHOTS] + h.last_peers[0].state[F + S.SHOTS]
		check(r["mismatches"] == 0 and r["common"] > 600 and shots > 0, "%d ms: apuntado bajo rollback sin desincronías (%d ticks, %d disparos)" % [rtt, r["common"], shots])
	# muestreo local (SimMatch): con el arco, el punto de mira produce los bits
	var root3 := Node3D.new()
	root.add_child(root3)
	var fa := Fighter.new(); var fb := Fighter.new()
	root3.add_child(fa); root3.add_child(fb)
	fa.global_position = Vector3.ZERO; fb.global_position = Vector3(0, 0, -8)
	var sm := SimMatch.new()
	root3.add_child(sm)
	sm.setup(fa, fb, root3)
	sm.reset_round()
	sm.running = false
	sm.aim_world_override = Vector3(5, 1, 0)
	check(sm.aim_input(0) == 0, "con espada no se envía mira")
	sm.state[S.LOADOUT] = S.Load.BOW
	var v2 := sm.aim_input(0)
	check((v2 & S.IN_AIM) != 0 and hdiff(S.aim_heading(v2), 0) <= 2, "con arco: mira hacia +X → rumbo 0 (%d)" % S.aim_heading(v2))
	SimMatch.mouse_aim = false
	check(sm.aim_input(0) == 0, "opción desactivada en Ajustes: sin mira")
	SimMatch.mouse_aim = true
	root3.queue_free()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
