extends SceneTree
## Fase 8: IA del rival sobre la sim (SimAI) + frasco y Fase II en FightSim.
## godot --headless --path . -s res://tests/test_sim_ai.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

const PROF := {"easy": "res://resources/ai/easy.tres", "normal": "res://resources/ai/normal.tres", "hard": "res://resources/ai/hard.tres"}

## Jugador 0 guionizado contra SimAI en el hueco 1. mode: "idle" quieto, "attacker" se acerca y golpea.
func duel(prof: String, seed_v: int, ticks: int, mode: String) -> Dictionary:
	var P := SimParams.defaults()
	var eng := FightEngine.new(P, seed_v, true)
	var s := eng.initial()
	var ai := SimAI.new(1, load(PROF[prof]), seed_v)
	var trace := 0
	for t in ticks:
		var in0 := FightSim.IN_LOCK
		if mode == "attacker":
			var dx: int = s[FightSim.F_FIELDS + FightSim.X] - s[FightSim.X]
			var dz: int = s[FightSim.F_FIELDS + FightSim.Z] - s[FightSim.Z]
			var d := FxMath.length(dx, dz)
			in0 = FightSim.make_input(FxMath.dir_of(dx, dz) >> 3, d > 2000000, FightSim.IN_LOCK)
			if d < 2600000 and t % 75 < 2: in0 |= FightSim.IN_ATK
		var in1 := ai.think(s, P)
		trace = (trace * 31 + in1) & 0xFFFFFFFF
		eng.step(s, in0, in1)
		if s[FightSim.ALIVE] == 0 or s[FightSim.F_FIELDS + FightSim.ALIVE] == 0:
			break
	return {"s": s, "ai": ai, "trace": trace, "p_hp": s[FightSim.HP], "ai_hits": s[FightSim.F_FIELDS + FightSim.HITS]}

func _run() -> void:
	var a := duel("normal", 7, 1800, "attacker")
	var b := duel("normal", 7, 1800, "attacker")
	check(a["trace"] == b["trace"] and FightSim.checksum(a["s"]) == FightSim.checksum(b["s"]), "determinista: misma semilla → mismas entradas y estado")
	var c := duel("normal", 8, 1800, "attacker")
	check(c["trace"] != a["trace"], "otra semilla → otra partida")
	var idle := duel("normal", 3, 3600, "idle")
	check(int(idle["ai_hits"]) > 0 and int(idle["p_hp"]) < 100000, "la IA se acerca y golpea a un jugador quieto (%d golpes)" % int(idle["ai_hits"]))
	var tot := {"easy": [0, 0, 0, 0, 0], "hard": [0, 0, 0, 0, 0]}
	for prof in ["easy", "hard"]:
		for sd in [1, 2, 3]:
			var r := duel(prof, sd, 3600, "attacker")
			var ai: SimAI = r["ai"]
			tot[prof][0] += ai.dodges
			tot[prof][1] += ai.parries_tried
			tot[prof][2] += int(r["ai_hits"])
			tot[prof][3] += ai.breathers
			tot[prof][4] += ai._opp_atk_starts
	print("easy %s  hard %s  [esquivas, paradas, golpes, respiros, ataques del jugador]" % [tot["easy"], tot["hard"]])
	check(tot["hard"][0] + tot["hard"][1] > 0, "difícil lee los ataques telegrafiados (esquiva/para)")
	var rate := func(v: Array) -> float: return float(v[0] + v[1]) / maxf(v[4], 1.0)
	check(rate.call(tot["hard"]) >= rate.call(tot["easy"]), "difícil reacciona a más ataques que fácil (%.2f vs %.2f)" % [rate.call(tot["hard"]), rate.call(tot["easy"])])
	check(tot["easy"][3] + tot["hard"][3] > 0, "la IA se toma respiros")
	# --- frasco ---
	var P := SimParams.defaults()
	var eng := FightEngine.new(P, 1, true)
	var s := eng.initial()
	s[FightSim.HP] = 40000
	eng.step(s, FightSim.IN_FLASK, 0)
	check(s[FightSim.FLASK_T] > 0 and s[FightSim.FLASKS] == 0, "frasco: empieza a beber y gasta la carga")
	for t in 70:
		eng.step(s, 0, 0)
	check(s[FightSim.HP] == 40000 + 35000 and s[FightSim.FLASK_T] == 0, "frasco: cura el 35 %% al terminar (%d)" % s[FightSim.HP])
	eng.step(s, FightSim.IN_FLASK, 0)
	check(s[FightSim.FLASK_T] == 0, "sin cargas no vuelve a beber")
	# --- Fase II ---
	P = SimParams.defaults()
	P[1]["boss"] = [{"id": "a", "type": 99}, {"id": "b", "type": 99}, {"id": "c", "type": 99}]
	P[1]["boss_n"] = 2
	P[1]["ph2"] = {"hp_pm": 500, "rage": 540, "invuln": 51, "summon": 1}
	eng = FightEngine.new(P, 1, true)
	s = eng.initial()
	check(SimAbilities.boss_avail(s, P, 1) == 2, "Fase II: antes, 2 habilidades disponibles")
	s[FightSim.F_FIELDS + FightSim.HP] = 49000
	eng.step(s, 0, 0)
	var o := FightSim.F_FIELDS
	check(s[o + FightSim.PH2] == 1 and SimAbilities.boss_avail(s, P, 1) == 3, "Fase II al 50 %: desbloquea la tercera habilidad")
	check(s[o + FightSim.RAGE_T] >= 500 and s[o + FightSim.INVULN] > 0 and s[o + FightSim.METER] == FightSim.METER_MAX, "Fase II: furia, invulnerabilidad y medidor lleno")
	# --- golpe sísmico del personaje (arte tipo 3) ---
	P = SimParams.defaults()
	P[0]["art"] = {"type": 3, "cost": 30000, "cd": 480, "st": 25000, "t": 42, "r": 5000000, "raw": 22000}
	P[0]["mana_max"] = 100000
	eng = FightEngine.new(P, 1, true)
	s = eng.initial()
	s[FightSim.F_FIELDS + FightSim.X] = s[FightSim.X] + 3000000
	eng.step(s, FightSim.IN_ART, 0)
	check(s[FightSim.ART_T] > 0 and s[FightSim.ART_CD] > 0, "golpe sísmico: empieza (marca con aviso)")
	for t in 50:
		eng.step(s, 0, 0)
	check(s[FightSim.F_FIELDS + FightSim.HP] < 100000, "golpe sísmico: daña al rival dentro del radio (%d)" % s[FightSim.F_FIELDS + FightSim.HP])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
