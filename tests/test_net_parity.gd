extends SceneTree
## Fase online 1: paridad reglas offline (Fighter) vs simulación determinista (FightSim) con
## secuencias de entrada guionizadas. Compara daño, niveles de aturdimiento, duración del
## aturdimiento, contadores (parry, esquiva, rotura de guardia...) y el tick del primer impacto.
## godot --headless --path . -s res://tests/test_net_parity.gd
const S = preload("res://net/sim/fight_sim.gd")
const F := FightSim.F_FIELDS
const HOLD_LIGHT := 1
var fails := 0
var gaps: Array[String] = []

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

## Guion: [tick, jugador, acción, arg]. Acciones: light, heavy (arg = ticks de carga extra), block_on,
## block_off, parry, roll (arg = rumbo 0..31 relativo: 0 = hacia el rival), swap, shoot (arg = ticks mantenido).
func _initialize() -> void:
	_run()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var scen := [
		["ligero", 1.8, 60, [[2, 0, "light", 0]]],
		["combo x3", 1.8, 160, [[2, 0, "light", 0], [16, 0, "light", 0], [44, 0, "light", 0], [72, 0, "light", 0]]],
		["fuerte", 1.8, 130, [[30, 0, "heavy", 0]]],
		["fuerte cargado", 1.8, 170, [[30, 0, "heavy", 60]]],
		["bloqueo", 1.8, 80, [[0, 1, "block_on", 0], [10, 0, "light", 0]]],
		["rotura de guardia", 1.8, 700, _guard_break_script()],
		["parry + réplica", 1.8, 140, [[2, 0, "light", 0], [20, 1, "parry", 0], [40, 1, "light", 0]]],
		["voltereta (i-frames)", 1.8, 80, [[2, 0, "light", 0], [18, 1, "roll", 8]]],
		["presión sostenida", 1.8, 420, _pressure_script()],
		["flecha", 10.0, 140, [[0, 0, "swap", 0], [40, 0, "shoot", 0]]],
		["flecha cargada", 10.0, 220, [[0, 0, "swap", 0], [40, 0, "shoot", 90]]],
	]
	var all_params_ok := true
	for sc in scen:
		var off := await _offline(world, sc)
		var P: Array = off["params"]
		for pp: Dictionary in P:
			pp["buffer"] = 0 # el lado offline llama a la API sin el búfer del controlador
		var sim := _sim(P, sc)
		var name: String = sc[0]
		print("--- %s: offline %s | sim %s" % [name, str(off["r"]), str(sim)])
		var r: Dictionary = off["r"]
		for k in ["dmg0", "dmg1"]:
			check(absf(float(r[k]) - float(sim[k])) <= 0.05 + 0.01 * float(r[k]), "%s: %s offline %.2f vs sim %.2f" % [name, k, r[k], sim[k]])
		for k in ["lvl0", "lvl1", "parries", "dodges", "guard_breaks", "hits0", "hits1", "stance_breaks"]:
			check(int(r[k]) == int(sim[k]), "%s: %s offline %d vs sim %d" % [name, k, r[k], sim[k]])
		for k in ["first_hit", "stun0", "stun1"]:
			var tol := 1 if k == "first_hit" else 2
			if absi(int(r[k]) - int(sim[k])) > tol:
				gaps.append("%s: %s offline %d vs sim %d" % [name, k, r[k], sim[k]])
			check(absi(int(r[k]) - int(sim[k])) <= tol + 3, "%s: %s (ticks) offline %d vs sim %d (±%d exacto, ±%d tolerado)" % [name, k, r[k], sim[k], tol, tol + 3])
	print("Diferencias de tiempo > tolerancia exacta: %d" % gaps.size())
	for g in gaps: print("  GAP " + g)
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

func _guard_break_script() -> Array:
	var out := [[0, 1, "block_on", 0]]
	for k in 40:
		out.append([4 + k * 14, 0, "light", 0])
	return out

func _pressure_script() -> Array:
	var out := []
	for k in 30:
		out.append([2 + k * 13, 0, "light", 0])
	return out

func _empty_result() -> Dictionary:
	return {"dmg0": 0.0, "dmg1": 0.0, "lvl0": 0, "lvl1": 0, "parries": 0, "dodges": 0, "guard_breaks": 0, "hits0": 0, "hits1": 0,
		"first_hit": -1, "stun0": 0, "stun1": 0, "stance_breaks": 0, "log": []}

func _dir_off(d32: int) -> Vector3:
	var a := d32 / 32.0 * TAU
	return Vector3(sin(a), 0.0, -cos(a))

# ---------------- Offline: Fighter real ----------------
func _offline(world: Node3D, sc: Array) -> Dictionary:
	var gap: float = sc[1]
	var n: int = sc[2]
	var script: Array = sc[3]
	var fs: Array[Fighter] = []
	for i in 2:
		var f := Fighter.new()
		f.team = i
		world.add_child(f)
		f.secondary = Fighter.FALLBACK_BOW
		fs.append(f)
	await physics_frame
	fs[0].global_position = Vector3.ZERO
	fs[0].facing = Vector3(0, 0, -1)
	fs[1].global_position = Vector3(0, 0, -gap)
	fs[1].facing = Vector3(0, 0, 1)
	var params := SimParams.bake(fs[0], fs[1])
	await physics_frame
	var r := _empty_result()
	var hp0 := [fs[0].health, fs[1].health]
	var holds := [{}, {}]
	for t in n:
		for e: Array in script:
			if int(e[0]) != t:
				continue
			var f := fs[int(e[1])]
			match String(e[2]):
				"light": f.attack_light()
				"heavy":
					f.attack_heavy()
					if int(e[3]) > 0:
						f.want_charge = true
						holds[int(e[1])]["charge"] = t + int(e[3])
				"block_on": f.want_block = true
				"block_off": f.want_block = false
				"parry": f.parry()
				"roll":
					f.move_input = _dir_off(int(e[3]))
					f.dash()
				"swap": f.swap_loadout()
				"shoot":
					f.shoot()
					f.want_shot_hold = int(e[3]) > 0
					holds[int(e[1])]["shot"] = t + int(e[3])
		for i in 2:
			var h: Dictionary = holds[i]
			if h.has("charge") and t >= int(h["charge"]):
				fs[i].want_charge = false
			if h.has("shot") and t >= int(h["shot"]):
				fs[i].want_shot_hold = false
		var h1 := fs[1].health
		await physics_frame
		for i in 2:
			fs[i].move_input = Vector3.ZERO
			if fs[i].stun > 0.0:
				r["stun%d" % i] += 1
		if OS.get_environment("PARITY_TRACE") != "" and t % 10 == 0:
			r["log"].append("t%d st%.2f e%.2f a%d" % [t, fs[0].stamina, fs[0].exhausted, fs[0].atk_state])
		if fs[1].health < h1:
			r["log"].append("%d:%.1f" % [t, h1 - fs[1].health])
		if r["first_hit"] < 0 and fs[1].health < h1:
			r["first_hit"] = t
	r["dmg1"] = float(hp0[1]) - fs[1].health
	r["dmg0"] = float(hp0[0]) - fs[0].health
	r["lvl0"] = fs[0].staggers * 1 + fs[0].stuns * 10 + fs[0].knockdowns * 100
	r["lvl1"] = fs[1].staggers * 1 + fs[1].stuns * 10 + fs[1].knockdowns * 100
	r["parries"] = fs[0].parries_landed + fs[1].parries_landed
	r["dodges"] = fs[0].rolls_dodged + fs[1].rolls_dodged
	r["guard_breaks"] = fs[0].guard_breaks + fs[1].guard_breaks
	r["hits0"] = fs[0].hits_landed
	r["hits1"] = fs[1].hits_landed
	r["stance_breaks"] = fs[0].stance_breaks + fs[1].stance_breaks
	for f in fs:
		f.queue_free()
	await physics_frame
	return {"params": params, "r": r}

# ---------------- Sim ----------------
func _sim(P: Array, sc: Array) -> Dictionary:
	var gap: float = sc[1]
	var n: int = sc[2]
	var script: Array = sc[3]
	var s := FightSim.initial(P, 1, false)
	s[S.X] = 0
	s[S.FACE] = 0
	s[F + S.X] = int(round(gap * 1000000.0))
	s[F + S.FACE] = 128
	# compila el guion a entradas por tick
	var ins := [[], []]
	for i in 2:
		ins[i].resize(n + 1)
		ins[i].fill(0)
	var block := [false, false]
	for e: Array in script:
		var t: int = e[0]
		var i: int = e[1]
		match String(e[2]):
			"light":
				if t - 1 >= 0: ins[i][t - 1] |= S.IN_ATK # toque: pulsado un tick, sale al soltar
			"heavy":
				for k in range(maxi(t - S.HEAVY_HOLD, 0), mini(t + maxi(int(e[3]), 1), n)):
					ins[i][k] |= S.IN_ATK
			"block_on":
				for k in range(t, n): ins[i][k] |= S.IN_BLOCK
			"block_off":
				for k in range(t, n): ins[i][k] &= ~S.IN_BLOCK
			"parry": ins[i][t] |= S.IN_PARRY
			"roll":
				# rumbo relativo al frente del luchador: el jugador 1 mira hacia -X (128)
				var d32: int = (int(e[3]) + (16 if i == 1 else 0)) & 31
				ins[i][t] |= S.IN_ROLL | S.IN_MOVE | d32
			"swap": ins[i][t] |= S.IN_SWAP
			"shoot":
				for k in range(t, mini(t + maxi(int(e[3]), 1), n)): ins[i][k] |= S.IN_ATK
	var r := _empty_result()
	for t in n:
		var h1: int = s[F + S.HP]
		FightSim.step(s, P, ins[0][t], ins[1][t])
		for i in 2:
			if s[i * F + S.STUN] > 0:
				r["stun%d" % i] += 1
		if OS.get_environment("PARITY_TRACE") != "" and t % 10 == 0:
			r["log"].append("t%d st%.2f e%.2f a%d" % [t, s[S.ST] / 1000.0, s[S.EXH] / 60.0, s[S.ATK_STATE]])
		if s[F + S.HP] < h1:
			r["log"].append("%d:%.1f" % [t, (h1 - s[F + S.HP]) / 1000.0])
		if r["first_hit"] < 0 and s[F + S.HP] < h1:
			r["first_hit"] = t
	r["dmg0"] = (P[0]["hp"] - s[S.HP]) / 1000.0
	r["dmg1"] = (P[1]["hp"] - s[F + S.HP]) / 1000.0
	r["lvl0"] = s[S.STAGGERS] + s[S.STUNS] * 10 + s[S.KNOCKDOWNS] * 100
	r["lvl1"] = s[F + S.STAGGERS] + s[F + S.STUNS] * 10 + s[F + S.KNOCKDOWNS] * 100
	r["parries"] = s[S.PARRIES] + s[F + S.PARRIES]
	r["dodges"] = s[S.DODGES] + s[F + S.DODGES]
	r["guard_breaks"] = s[S.GUARD_BREAKS] + s[F + S.GUARD_BREAKS]
	r["hits0"] = s[S.HITS]
	r["hits1"] = s[F + S.HITS]
	r["stance_breaks"] = s[S.STANCE_BREAKS] + s[F + S.STANCE_BREAKS]
	return r
