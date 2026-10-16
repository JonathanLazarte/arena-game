extends SceneTree
## Fase online 1: reglas de la simulación determinista (net/sim) sin escena.
## godot --headless --path . -s res://tests/test_fight_sim.gd
const S = preload("res://net/sim/fight_sim.gd")
const F := FightSim.F_FIELDS
var fails := 0
var P: Array

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

## Estado con los luchadores a `gap` m en el eje X, encarados.
func duel(gap: float, hitstop := false) -> PackedInt64Array:
	var s := S.initial(P, 1, hitstop)
	s[S.X] = 0
	s[F + S.X] = int(gap * 1000000.0)
	return s

func run(s: PackedInt64Array, n: int, a: Callable, b: Callable = func(_t: int) -> int: return 0) -> void:
	for t in n:
		S.step(s, P, a.call(t), b.call(t))

func light_at(t0: int) -> Callable:
	return func(t: int) -> int: return S.IN_ATK if t == t0 else 0

func _initialize() -> void:
	P = SimParams.defaults()
	# --- determinismo, guardar/cargar ---
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var ins: Array[int] = []
	for i in 2400: ins.append(rng.randi() & 0x3FFF)
	var a := duel(2.0); var b := duel(2.0)
	var snap := PackedInt64Array()
	for i in 1200:
		if i == 600: snap = a.duplicate()
		S.step(a, P, ins[i], ins[i + 1200]); S.step(b, P, ins[i], ins[i + 1200])
	check(S.checksum(a) == S.checksum(b), "simulación determinista (1200 ticks, entradas aleatorias)")
	for i in range(600, 1200): S.step(snap, P, ins[i], ins[i + 1200])
	check(snap == a, "cargar estado + re-simular = mismo estado")
	check(a[S.HP] < P[0]["hp"] or a[F + S.HP] < P[1]["hp"], "las entradas aleatorias producen combate (vida %d / %d)" % [a[S.HP], a[F + S.HP]])
	var r1 := S.initial(P, 7); var r2 := S.initial(P, 7)
	check(S.rng_next(r1) == S.rng_next(r2) and S.rng_next(r1) != S.rng_next(S.initial(P, 8)), "RNG con semilla en el estado")
	# --- movimiento ---
	var s := duel(10.0)
	run(s, 60, func(_t: int) -> int: return S.make_input(0, true, 0))
	var walked: float = (s[S.X]) / 1000000.0
	check(walked > 6.5 and walked < 8.4, "andar 1 s ≈ velocidad a pie (%.2f m)" % walked)
	s = duel(10.0)
	s[S.FACE] = 128
	run(s, 30, func(_t: int) -> int: return S.make_input(0, true, 0))
	check(s[S.FACE] == 0, "giro a velocidad angular fija (180° en < 0,5 s)")
	# --- voltereta ---
	s = duel(20.0)
	run(s, 48, func(t: int) -> int: return S.make_input(0, true, S.IN_ROLL) if t == 0 else 0)
	var rolled: float = s[S.X] / 1000000.0
	check(rolled > 4.3 and rolled < 5.3, "voltereta recorre ≈ 4,5 + 0,4 m (%.2f)" % rolled)
	check(s[S.ST] < P[0]["st_max"], "voltereta gasta aguante")
	# rodar a través de un golpe: i-frames
	s = duel(1.8)
	run(s, 60, light_at(0), func(t: int) -> int: return S.make_input(8, true, S.IN_ROLL if t == 16 else 0))
	check(s[F + S.HP] == P[1]["hp"] and s[F + S.DODGES] == 1, "i-frames de la voltereta esquivan el golpe")
	# búfer de voltereta 0,18 s: pulsada durante la anticipación (no se puede), sale al quedar libre
	s = duel(5.0)
	var rolled_at := -1
	var cancel_at := -1
	for t in 120:
		S.step(s, P, (S.IN_ATK if t == 0 else 0) | (S.make_input(16, true, S.IN_ROLL) if t == 52 else S.make_input(16, true, 0) if t > 52 else 0), 0)
		if rolled_at < 0 and s[S.ROLL_T] >= 0: rolled_at = t
		if cancel_at < 0 and s[S.ATK_STATE] == S.Atk.RECOVERY and s[S.ATK_T] * 2 >= s[S.ATK_DUR]: cancel_at = t
	check(rolled_at > 52 and rolled_at - 52 <= P[0]["roll_buffer"], "búfer de voltereta: pulsada en la recuperación, sale %d ticks después (al poder cancelar)" % (rolled_at - 52))
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
