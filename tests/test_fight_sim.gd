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
	# --- cuerpo a cuerpo ---
	s = duel(1.8)
	var hit_t := -1
	for t in 60:
		var h0: int = s[F + S.HP]
		S.step(s, P, S.IN_ATK if t == 0 else 0, 0)
		if hit_t < 0 and s[F + S.HP] < h0: hit_t = t
	var a0: Dictionary = P[0]["atk"][0]
	check(s[F + S.HP] == P[1]["hp"] - a0["raw"], "ligero: daño exacto (%d)" % (P[1]["hp"] - s[F + S.HP]))
	check(hit_t == 1 + a0["windup"] - 1, "ligero: golpea al acabar la anticipación (tick %d)" % hit_t)
	# combo de 3: tocar repetidamente encadena
	s = duel(1.8)
	run(s, 200, func(t: int) -> int: return S.IN_ATK if t % 12 < 2 and t < 120 else 0)
	var dealt: int = s[S.DMG_DEALT]
	var exp3: int = P[0]["atk"][0]["raw"] + P[0]["atk"][1]["raw"] + P[0]["atk"][2]["raw"]
	check(s[S.HITS] == 3, "combo de 3 golpes encadenado (%d golpes, %d daño)" % [s[S.HITS], dealt])
	check(s[F + S.STAGGERS] + s[F + S.STUNS] >= 1, "el combo acumula aturdimiento (nivel %d)" % s[F + S.LAST_LVL])
	# fuerte: mantener 0,4 s; cargar más da más daño
	s = duel(1.8)
	run(s, 140, func(t: int) -> int: return S.IN_ATK if t < 25 else 0)
	var heavy_dmg: int = P[1]["hp"] - s[F + S.HP]
	s = duel(1.8)
	run(s, 160, func(t: int) -> int: return S.IN_ATK if t < 120 else 0)
	var charged_dmg: int = P[1]["hp"] - s[F + S.HP]
	check(heavy_dmg == P[0]["atk"][3]["raw"], "fuerte: daño base (%d)" % heavy_dmg)
	check(charged_dmg == P[0]["atk"][3]["raw"] * 1400 / 1000, "fuerte cargado al máximo: +40 %% (%d)" % charged_dmg)
	# bloqueo: daño reducido (chip) y aguante gastado
	s = duel(1.8)
	run(s, 60, light_at(0), func(_t: int) -> int: return S.IN_BLOCK)
	check(s[F + S.BLOCKS] == 1 and P[1]["hp"] - s[F + S.HP] == P[0]["atk"][0]["raw"] * P[1]["chip_pm"] / 1000, "bloqueo: pasa el 12 %% (%d)" % (P[1]["hp"] - s[F + S.HP]))
	s = duel(1.8)
	var gc_seen := false
	for t in 80:
		S.step(s, P, light_at(0).call(t), (S.IN_BLOCK if t < 27 else 0) | (S.IN_ATK if t == 27 else 0))
		if s[F + S.ATK_GC] != 0: gc_seen = true
	check(gc_seen, "atacar justo tras bloquear = contra de guardia")
	# rotura de guardia: golpes bloqueados hasta agotar el aguante
	s = duel(1.8)
	run(s, 900, func(t: int) -> int: return S.IN_ATK if t % 12 < 2 else 0, func(_t: int) -> int: return S.IN_BLOCK)
	check(s[F + S.GUARD_BREAKS] >= 1, "rotura de guardia al agotar el aguante (%d bloqueos)" % s[F + S.BLOCKS])
	# parry: aturde al atacante 1,6 s, sin daño; la réplica hace x1,8
	s = duel(1.8)
	run(s, 30, light_at(0), func(t: int) -> int: return S.IN_PARRY if t == 18 else 0)
	check(s[F + S.PARRIES] == 1 and s[F + S.HP] == P[1]["hp"] and s[S.STUN] > 60 and s[S.RIPOSTE_T] > 0, "parry: atacante aturdido (stun %d ticks), sin daño" % s[S.STUN])
	run(s, 60, func(_t: int) -> int: return 0, light_at(0))
	check(P[0]["hp"] - s[S.HP] == P[1]["atk"][0]["raw"] * 1800 / 1000, "réplica tras parry x1,8 (%d)" % (P[0]["hp"] - s[S.HP]))
	# derribo (nivel 3) con presión sostenida + inmunidad al levantarse
	s = duel(1.8)
	var max_lvl := 0
	for t in 600:
		S.step(s, P, S.IN_ATK if (t % 12 < 2) else 0, 0)
		max_lvl = maxi(max_lvl, s[F + S.LAST_LVL])
	check(s[F + S.KNOCKDOWNS] >= 1 or s[F + S.STANCE_BREAKS] >= 1, "presión sostenida: derribo o rotura de postura (derribos %d, posturas %d, nivel máx %d)" % [s[F + S.KNOCKDOWNS], s[F + S.STANCE_BREAKS], max_lvl])
	# hit-stop como contador de congelación: el fuerte congela 5 ticks
	var ends: Array[int] = []
	for hs in [true, false]:
		var sx := duel(1.8, hs)
		var end_t := -1
		for t in 200:
			S.step(sx, P, S.IN_ATK if t < 25 else 0, 0)
			if t > 30 and end_t < 0 and sx[S.ATK_STATE] == S.Atk.NONE: end_t = t
		ends.append(end_t)
	check(ends[0] - ends[1] == S.HITSTOP_HEAVY, "hit-stop = contador de congelación (+%d ticks)" % (ends[0] - ends[1]))
	# --- arco ---
	s = duel(10.0)
	var arrow_hit := -1
	for t in 200:
		var hh: int = s[F + S.HP]
		S.step(s, P, (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t == 40 else 0), 0)
		if arrow_hit < 0 and s[F + S.HP] < hh: arrow_hit = t
	check(s[S.LOADOUT] == S.Load.BOW, "cambio a arco")
	check(P[1]["hp"] - s[F + S.HP] == P[0]["arrow_raw"], "flecha: daño (%d) al tick %d" % [P[1]["hp"] - s[F + S.HP], arrow_hit])
	s = duel(10.0)
	run(s, 260, func(t: int) -> int: return (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t >= 40 and t < 40 + 30 + 60 else 0))
	check(P[1]["hp"] - s[F + S.HP] == P[0]["arrow_raw_ch"] and s[S.SHOT_CHARGED] == 1, "disparo cargado (mantener 0,9 s tras tensar): %d" % (P[1]["hp"] - s[F + S.HP]))
	s = duel(10.0)
	run(s, 200, func(t: int) -> int: return (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t == 40 else 0), func(_t: int) -> int: return S.IN_BLOCK)
	check(s[F + S.HP] == P[1]["hp"] and s[F + S.BLOCKS] == 1 and s[F + S.ST] < P[1]["st_max"], "flecha bloqueada: sin daño, cuesta aguante")
	s = duel(10.0)
	var pool_max := 0
	for t in 400:
		S.step(s, P, (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t > 30 and t % 2 == 0 else 0), 0)
		var live := 0
		for j in S.PROJ_MAX: live += int(s[S.PROJ_BASE + j * S.PR_FIELDS + S.PR_ON])
		pool_max = maxi(pool_max, live)
	check(pool_max >= 1 and pool_max <= S.PROJ_MAX and s[S.SHOTS] > 3, "proyectiles en piscina fija (máx. vivos %d, disparos %d)" % [pool_max, s[S.SHOTS]])
	# parry de flecha: la refleja
	s = duel(10.0)
	run(s, 200, func(t: int) -> int: return (S.IN_SWAP if t == 0 else 0) | (S.IN_ATK if t == 40 else 0), func(t: int) -> int: return S.IN_PARRY if t == 78 else 0)
	check(s[F + S.PARRIES] == 1 and s[F + S.HP] == P[1]["hp"], "parry refleja la flecha (vida tirador %d)" % s[S.HP])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
