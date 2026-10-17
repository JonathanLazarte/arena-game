extends SceneTree
## Fase 8: port a la sim de las pruebas antiguas de Fighter (test_combat, test_buffer, test_dash_strike,
## test_jump_aoe, test_eikon_*, test_riding, test_status...). Las reglas básicas (combo, bloqueo, contra de
## guardia, parry, voltereta, flechas) siguen en test_fight_sim; las habilidades en test_net_abilities.
## godot --headless --path . -s res://tests/test_sim_rules.gd
const S := preload("res://net/sim/fight_sim.gd")
const F := S.F_FIELDS
var fails := 0
var P: Array
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func duel(gap: float) -> PackedInt64Array:
	var s := S.initial(P, 1, false)
	s[S.X] = 0
	s[F + S.X] = int(gap * 1000000.0)
	return s

func run(s: PackedInt64Array, n: int, a: Callable, b: Callable = func(_t: int) -> int: return 0) -> void:
	for t in n:
		S.step(s, P, a.call(t), b.call(t))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	P = SimParams.defaults()
	# --- test_combat: ligero (toque) vs fuerte (mantener ≥ 0,4 s) ---
	var s := duel(1.8)
	run(s, 3, func(t: int) -> int: return S.IN_ATK if t == 0 else 0)
	check(s[S.ATK_STATE] == S.Atk.WINDUP and s[S.ATK_IDX] != SimParams.A_HEAVY, "toque = ataque ligero")
	s = duel(1.8)
	run(s, 30, func(_t: int) -> int: return S.IN_ATK)
	check(s[S.ATK_IDX] == SimParams.A_HEAVY and s[S.CHARGE_T] >= 0, "mantener = ataque fuerte (carga %d)" % s[S.CHARGE_T])
	s = duel(1.8)
	run(s, 120, func(t: int) -> int: return S.IN_ATK if t < 25 else 0)
	var heavy_dmg: int = P[1]["hp"] - s[F + S.HP]
	s = duel(1.8)
	run(s, 120, func(t: int) -> int: return S.IN_ATK if t == 0 else 0)
	var light_dmg: int = P[1]["hp"] - s[F + S.HP]
	check(heavy_dmg > light_dmg and light_dmg > 0, "el fuerte hace más daño que el ligero (%d > %d)" % [heavy_dmg, light_dmg])
	# --- test_combat: aguante ---
	s = duel(20.0)
	run(s, 3, func(t: int) -> int: return S.IN_ATK if t == 0 else 0)
	check(s[S.ST] < P[0]["st_max"], "atacar gasta aguante")
	# --- test_buffer: pulsar durante la recuperación encola y sale al acabar ---
	s = duel(1.8)
	var started := 0
	var prev := 0
	for t in 140:
		var a := S.IN_ATK if t == 0 or t == 40 else 0
		S.step(s, P, a, 0)
		if s[S.ATK_STATE] == S.Atk.WINDUP and prev != S.Atk.WINDUP: started += 1
		prev = s[S.ATK_STATE]
	check(started >= 2, "búfer: el segundo ataque pulsado a destiempo sale (%d ataques)" % started)
	# --- test_dash_strike: atacar al final de la voltereta = estocada ---
	s = duel(6.0)
	run(s, 60, func(t: int) -> int: return S.make_input(0, true, S.IN_ROLL if t == 0 else 0) | (S.IN_ATK if t == 10 else 0))
	check(s[S.DASH_DIR] == 0 and (s[F + S.HP] < P[1]["hp"] or s[S.HITS] + s[F + S.BLOCKS] + s[F + S.DODGES] > 0 or s[S.ATK_IDX] == SimParams.A_DASH), "voltereta + ataque = estocada (vida rival %d)" % s[F + S.HP])
	# --- paso atrás + ataque = estocada al terminar (fase 8, antes solo offline) ---
	s = duel(3.0)
	var dashed := false
	for t in 40:
		S.step(s, P, (S.IN_ROLL if t == 0 else 0) | (S.IN_ATK if t == 4 else 0), 0)
		if s[S.ATK_IDX] == SimParams.A_DASH and s[S.ATK_STATE] != S.Atk.NONE: dashed = true
	check(dashed, "paso atrás + ataque = estocada al acabar el paso")
	# --- test_jump_aoe: saltar evita la marca de suelo ---
	for jump in [false, true]:
		s = duel(10.0)
		SimAbilities.spawn_hz(s, 1, 1, 0, 0, 20, 3000000, 20000, 30000, 100000, 0)
		run(s, 40, func(t: int) -> int: return S.IN_JUMP if jump and t == 10 else 0)
		if jump:
			check(s[S.HP] == P[0]["hp"] and s[S.JUMPS] == 1, "salto: la marca de suelo no alcanza en el aire")
		else:
			check(s[S.HP] < P[0]["hp"], "sin saltar: la marca de suelo daña (%d)" % s[S.HP])
	# --- frasco no se puede beber atacando ---
	s = duel(20.0)
	s[S.HP] = 50000
	run(s, 3, func(t: int) -> int: return S.IN_ATK if t == 0 else (S.IN_FLASK if t == 2 else 0))
	check(s[S.FLASK_T] == 0 and s[S.FLASKS] == 1, "frasco: no se bebe en mitad de un ataque")
	# --- eikon / montura con parámetros reales de la arena ---
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var ar: Arena = current_scene as Arena
	ar.sim_match.running = false
	P = ar.sim_match.params.duplicate(true)
	var ek: Dictionary = P[0].get("ek", {})
	s = duel(8.0)
	s[S.METER] = S.METER_MAX
	run(s, 4, func(t: int) -> int: return S.IN_EIKON if t == 0 else 0)
	check(s[S.EK_T] > 0 and s[S.METER] == 0, "invocar con el medidor lleno (%s)" % ek.get("id", "?"))
	if int(ek.get("ride", 0)) != 0:
		check(s[S.MOUNTED] != 0, "eikon montable: se monta al invocar")
		run(s, 4, func(t: int) -> int: return S.IN_MOUNT if t == 0 else 0)
		check(s[S.MOUNTED] == 0 and s[S.EK_T] > 0, "desmontar deja la montura en la arena")
		run(s, 30, func(_t: int) -> int: return 0)
		run(s, 4, func(t: int) -> int: return S.IN_EIKON if t == 0 else 0)
		check(s[S.MOUNTED] != 0, "volver a montar cerca de la montura")
	s = duel(8.0)
	run(s, 4, func(t: int) -> int: return S.IN_EIKON if t == 0 else 0)
	check(s[S.EK_T] == 0, "sin medidor no se invoca")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
