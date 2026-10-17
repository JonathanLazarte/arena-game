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
		["ataque en carrera", 6.0, 90, [[0, 0, "move_on", 0], [0, 0, "sprint_on", 0], [30, 0, "light", 0], [31, 0, "move_off", 0], [31, 0, "sprint_off", 0]]],
		["crítico tras rotura de postura", 1.8, 520, _crit_script()],
		["infusión sangrante", 1.8, 460, _spam(10, 44), {"inf": ["sangrante", ""]}],
		["infusión venenosa (veneno en el tiempo)", 1.8, 1100, _spam(8, 44), {"inf": ["venenoso", ""]}],
		["infusión gélida (+daño recibido)", 1.8, 700, _spam(14, 44), {"inf": ["gelido", ""]}],
		["infusión ardiente vs armadura", 1.8, 300, _spam(5, 44), {"inf": ["ardiente", ""], "armor": true}],
		["infusión sagrada", 1.8, 300, _spam(5, 44), {"inf": ["sagrada", ""], "armor": true}],
		["bloqueo con sangrante (30 %)", 1.8, 520, [[0, 1, "block_on", 0]] + _spam(10, 48), {"inf": ["sangrante", ""]}],
		["flecha venenosa", 10.0, 900, [[0, 0, "swap", 0], [40, 0, "shoot", 0], [140, 0, "shoot", 0], [240, 0, "shoot", 0], [340, 0, "shoot", 0], [440, 0, "shoot", 0]], {"w2": "arco", "w2inf": "venenoso"}],
		["ballesta", 10.0, 200, [[0, 0, "swap", 0], [40, 0, "shoot", 0]], {"w2": "ballesta"}],
		["ballesta cargada (abanico)", 10.0, 260, [[0, 0, "swap", 0], [40, 0, "shoot", 100]], {"w2": "ballesta"}],
		["armadura: ligero + fuerte", 1.8, 220, [[2, 0, "light", 0], [120, 0, "heavy", 0]], {"armor": true}],
		["armadura: contragolpe", 1.8, 80, [[30, 1, "heavy", 0], [36, 0, "light", 0]], {"armor": true}],
		["armadura: parry + réplica", 1.8, 140, [[2, 0, "light", 0], [20, 1, "parry", 0], [40, 1, "light", 0]], {"armor": true}],
		["flecha con adelanto (blanco andando)", 12.0, 160, [[0, 0, "swap", 0], [0, 1, "move_on", 8], [40, 0, "shoot", 0]], {"lead": 1.0}],
		["pasiva furia (vida baja)", 1.8, 60, [[2, 0, "light", 0]], {"chars": ["berserker", ""], "hp": [25.0, -1.0]}],
		["pasiva curación", 1.8, 420, [[2, 0, "light", 0]], {"chars": ["", "paladin"]}],
		# ---- Fase 4: habilidades de jefe (aviso online 1,12), magia ----
		["jefe: estocada", 6.0, 220, [[2, 0, "boss", 0]], {"boss": [["estocada"], []]}],
		["jefe: estocada esquivada rodando", 6.0, 220, [[2, 0, "boss", 0], [100, 1, "roll", 8]], {"boss": [["estocada"], []]}],
		["jefe: estocada imbloqueable", 6.0, 220, [[0, 1, "block_on", 0], [2, 0, "boss", 0]], {"boss": [["estocada"], []]}],
		["jefe: carga en área", 3.0, 200, [[2, 0, "boss", 0]], {"boss": [["carga_area"], []]}],
		["jefe: ráfaga teledirigida", 9.0, 160, [[2, 0, "boss", 0]], {"boss": [["rafaga"], []]}],
		["jefe: escudo de maná (100 % invulnerable)", 1.8, 120, [[2, 1, "boss", 0], [12, 0, "light", 0], [50, 0, "light", 0]], {"boss": [[], ["escudo_mana"]]}],
		["jefe: combo de la pausa falsa", 2.5, 300, [[2, 0, "boss", 0], [50, 0, "boss", 0], [100, 0, "boss", 0], [150, 0, "boss", 0]], {"boss": [["combo_falso"], []]}],
		["jefe: salto con caída", 6.0, 200, [[2, 0, "boss", 0]], {"boss": [["salto_caida"], []]}],
		["jefe: tajo retardado", 2.5, 200, [[2, 0, "boss", 0]], {"boss": [["tajo_retardado"], []]}],
		["jefe: presa del verdugo (agarre)", 2.5, 220, [[2, 0, "boss", 0]], {"boss": [["presa_verdugo"], []]}],
		["jefe: giro devastador", 2.5, 220, [[2, 0, "boss", 0]], {"boss": [["giro_martillo"], []]}],
		["jefe: danza del cisne", 2.5, 260, [[2, 0, "boss", 0]], {"boss": [["danza_cisne"], []]}],
		["jefe: danza del cisne bloqueada", 2.5, 260, [[0, 1, "block_on", 0], [2, 0, "boss", 0]], {"boss": [["danza_cisne"], []]}],
		["jefe: paso espectral", 4.0, 200, [[2, 0, "boss", 0]], {"boss": [["paso_espectral"], []]}],
		["jefe: onda rastrera", 6.0, 200, [[2, 0, "boss", 0]], {"boss": [["onda_rastrera"], []]}],
		["jefe: rayos trazadores", 6.0, 260, [[2, 0, "boss", 0]], {"boss": [["rayos_trazadores"], []]}],
		["jefe: aliento de dragón", 4.0, 260, [[2, 0, "boss", 0]], {"boss": [["aliento_dragon"], []]}],
		["jefe: furia de fase + ligero", 1.8, 120, [[2, 0, "boss", 0], [60, 0, "light", 0]], {"boss": [["furia_fase"], []]}],
		["jefe: postura de contragolpe", 1.8, 160, [[2, 1, "boss", 0], [40, 0, "light", 0]], {"boss": [[], ["postura_contra"]]}],
		["jefe: embate sísmico", 4.0, 240, [[2, 0, "boss", 0]], {"boss": [["embate_sismico"], []]}],
		["jefe: lanza celeste", 5.0, 220, [[2, 0, "boss", 0]], {"boss": [["lanza_celeste"], []]}],
		["jefe: lanza celeste imbloqueable", 5.0, 220, [[0, 1, "block_on", 0], [2, 0, "boss", 0]], {"boss": [["lanza_celeste"], []]}],
		["magia: chispa ígnea", 8.0, 120, [[2, 0, "spell", 0]], {"spells": [["chispa"], []]}],
		["magia: aliento helado", 3.0, 120, [[2, 0, "spell", 0]], {"spells": [["aliento_helado"], []]}],
		["magia: piel de piedra", 1.8, 120, [[2, 1, "spell", 0], [60, 0, "light", 0]], {"spells": [[], ["piel_de_piedra"]]}],
		# ---- Fase 6: huecos online cerrados ----
		["jefe: combo con remate en estocada (variante)", 2.5, 320, [[2, 0, "boss", 0], [50, 0, "boss", 0], [100, 0, "boss", 0], [150, 0, "boss_var", 0]], {"boss": [["combo_falso"], []]}],
		["jefe: ráfaga vs blanco andando", 9.0, 160, [[0, 1, "move_on", 8], [2, 0, "boss", 0]], {"boss": [["rafaga"], []]}],
		["arte: estocada impulsada", 4.0, 90, [[2, 0, "art", 0]], {"art": ["estocada_impulsada", ""]}],
		["arte: torbellino", 2.0, 90, [[2, 0, "art", 0]], {"art": ["torbellino", ""]}],
		["montado (lobo): embestida", 7.0, 120, [[2, 0, "summon", 0], [30, 0, "roll", 0]], {"eikon": ["lobo", ""], "meter": [100.0, 0.0]}],
		["montado (lobo): ligero", 2.6, 120, [[2, 0, "summon", 0], [30, 0, "light", 0]], {"eikon": ["lobo", ""], "meter": [100.0, 0.0]}],
		["montado (grifo): fuerte", 2.8, 160, [[2, 0, "summon", 0], [40, 0, "heavy", 0]], {"eikon": ["grifo", ""], "meter": [100.0, 0.0]}],
		["montado (lobo): dash + ligero ligado", 6.0, 140, [[2, 0, "summon", 0], [30, 0, "light", 0], [32, 0, "roll", 0]], {"eikon": ["lobo", ""], "meter": [100.0, 0.0]}],
		["montura sin jinete golpeada", 2.2, 200, [[2, 1, "summon", 0], [20, 1, "mount", 0], [40, 0, "light", 0], [80, 0, "light", 0], [120, 0, "light", 0]], {"eikon": ["", "lobo"], "meter": [0.0, 100.0], "sim_only": true}],
		["golem compañero golpeado", 2.0, 160, [[2, 1, "summon", 0], [10, 0, "light", 0], [50, 0, "light", 0], [90, 0, "light", 0]], {"eikon": ["", "golem"], "meter": [0.0, 100.0]}],
		# ---- Fase 7: salto y movimiento ágil ----
		["salto en el sitio", 4.0, 90, [[2, 0, "jump", 0]]],
		["salto andando", 6.0, 90, [[0, 0, "move_on", 0], [10, 0, "jump", 0], [80, 0, "move_off", 0]]],
		["picado (ataque en salto)", 2.0, 120, [[2, 0, "jump", 0], [14, 0, "light", 0]]],
		["salto montado (lobo)", 6.0, 160, [[2, 0, "summon", 0], [30, 0, "jump", 0]], {"eikon": ["lobo", ""], "meter": [100.0, 0.0]}],
		["salto esquiva onda rastrera", 6.0, 200, [[2, 1, "boss", 0], [80, 0, "jump", 0]], {"boss": [[], ["onda_rastrera"]]}],
		["onda rastrera sin saltar (control)", 6.0, 200, [[2, 1, "boss", 0]], {"boss": [[], ["onda_rastrera"]]}],
		["arranque y frenada", 9.0, 60, [[0, 0, "move_on", 0], [20, 0, "move_off", 0]]],
		["carrera: arranque y frenada", 12.0, 80, [[0, 0, "move_on", 0], [0, 0, "sprint_on", 0], [30, 0, "move_off", 0], [30, 0, "sprint_off", 0]]],
		["carrera con giro de 90°", 9.0, 90, [[0, 0, "move_on", 8], [0, 0, "sprint_on", 0], [25, 0, "move_on", 0], [60, 0, "move_off", 0], [60, 0, "sprint_off", 0]]],
		["giro brusco de 180°", 9.0, 70, [[0, 0, "move_on", 0], [20, 0, "move_on", 16], [45, 0, "move_off", 0]]],
		["montura sin jinete ataca", 2.4, 240, [[2, 1, "summon", 0], [20, 1, "mount", 0]], {"eikon": ["", "lobo"], "meter": [0.0, 100.0]}],
		["montado: bloqueo con coste de montura", 2.6, 140, [[0, 1, "block_on", 0], [2, 0, "summon", 0], [30, 0, "heavy", 0]], {"eikon": ["lobo", ""], "meter": [100.0, 0.0]}],
		["talismán: parry devuelve aguante", 1.8, 60, [[2, 0, "light", 0], [20, 1, "parry", 0]], {"trinkets": [[], ["eco_templado"]]}],
	]
	var all_params_ok := true
	for sc in scen:
		if OS.get_environment("PARITY_ONLY") != "" and not String(sc[0]).contains(OS.get_environment("PARITY_ONLY")): continue
		var off := await _offline(world, sc)
		var P: Array = off["params"]
		for pp: Dictionary in P:
			pp["buffer"] = 0 # el lado offline llama a la API sin el búfer del controlador
		var sim := _sim(P, sc, off["hp_start"])
		var name: String = sc[0]
		print("--- %s: offline %s | sim %s" % [name, str(off["r"]), str(sim)])
		var r: Dictionary = off["r"]
		if sc.size() > 4 and sc[4].get("sim_only", false):
			# offline la montura sin jinete además ataca con IA propia (no portado): solo se exige que reciba daño
			check(float(sim["pet1"]) > 0.0, "%s: la montura sin jinete recibe daño online (%.2f)" % [name, sim["pet1"]])
			continue
		for k in ["dmg0", "dmg1", "pet1"]:
			check(absf(float(r[k]) - float(sim[k])) <= 0.05 + 0.01 * float(r[k]), "%s: %s offline %.2f vs sim %.2f" % [name, k, r[k], sim[k]])
		for k in ["lvl0", "lvl1", "parries", "dodges", "guard_breaks", "hits0", "hits1", "stance_breaks", "crits", "procs0", "procs1"]:
			check(int(r[k]) == int(sim[k]), "%s: %s offline %d vs sim %d" % [name, k, r[k], sim[k]])
		check(absf(float(r["st1"]) - float(sim["st1"])) <= 1.0, "%s: aguante final del rival offline %.1f vs sim %.1f" % [name, r["st1"], sim["st1"]])
		check(absf(float(r["dist"]) - float(sim["dist"])) <= 0.25, "%s: distancia final offline %.2f vs sim %.2f m (±0,25)" % [name, r["dist"], sim["dist"]])
		check(absi(int(r["air0"]) - int(sim["air0"])) <= 2 and absf(float(r["ymax0"]) - float(sim["ymax0"])) <= 0.1, "%s: en el aire offline %d ticks / %.2f m vs sim %d / %.2f m" % [name, r["air0"], r["ymax0"], sim["air0"], sim["ymax0"]])
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

func _crit_script() -> Array:
	var out := _pressure_script()
	out.append([388, 0, "light", 0]) # ya libre, rival con la postura rota delante
	out.append([392, 0, "light", 0])
	return out

func _pressure_script() -> Array:
	var out := []
	for k in 30:
		out.append([2 + k * 13, 0, "light", 0])
	return out

func _spam(n: int, every: int) -> Array:
	var out := []
	for k in n:
		out.append([2 + k * every, 0, "light", 0])
	return out

func _empty_result() -> Dictionary:
	return {"air0": 0, "ymax0": 0.0, "dist": 0.0, "pet1": 0.0, "dmg0": 0.0, "dmg1": 0.0, "lvl0": 0, "lvl1": 0, "parries": 0, "dodges": 0, "guard_breaks": 0, "hits0": 0, "hits1": 0,
		"first_hit": -1, "stun0": 0, "stun1": 0, "stance_breaks": 0, "crits": 0, "procs0": 0, "procs1": 0, "log": []}

func _dir_off(d32: int) -> Vector3:
	var a := d32 / 32.0 * TAU
	return Vector3(sin(a), 0.0, -cos(a))

# ---------------- Offline: Fighter real ----------------
func _offline(world: Node3D, sc: Array) -> Dictionary:
	var gap: float = sc[1]
	var n: int = sc[2]
	var script: Array = sc[3]
	var setup: Dictionary = sc[4] if sc.size() > 4 else {}
	var fs: Array[Fighter] = []
	for i in 2:
		var f := Fighter.new()
		f.team = i
		var chars: Array = setup.get("chars", ["", ""])
		if String(chars[i]) != "":
			f.set_loadout_defs(load("res://resources/characters/%s.tres" % chars[i]), f.weapon)
		var w2: WeaponDef = load("res://resources/weapons/%s.tres" % setup["w2"]) if setup.has("w2") else Fighter.FALLBACK_BOW
		if setup.has("w2inf") and i == 0:
			w2 = Smithing.effective(w2, 0, String(setup["w2inf"]))
		if setup.has("inf") and String(setup["inf"][i]) != "":
			f.set_loadout_defs(f.character, Smithing.effective(f.weapon, 0, String(setup["inf"][i])))
		if setup.get("armor", false):
			f.set_equipment(5, EquipStats.rival_armor("caballero", 5), w2)
		if setup.has("trinkets"):
			f.set_trinkets(setup["trinkets"][i])
		f.telegraph_k = SimAbilities.TELE_ONLINE
		if setup.has("boss"):
			f.set_boss_abilities(setup["boss"][i])
		f.fluid = true # como el jugador real (arena.gd)
		if setup.has("spells") or setup.has("art"):
			f.set_magic(setup.get("spells", [[], []])[i], String(setup.get("art", ["", ""])[i]))
		if setup.has("eikon"):
			f.eikon = load(Catalog.EIKONS[setup["eikon"][i]]) if String(setup["eikon"][i]) != "" else null
		world.add_child(f)
		f.secondary = w2
		if setup.has("lead"):
			f.aim_lead = float(setup["lead"])
		fs.append(f)
	await physics_frame
	fs[0].global_position = Vector3.ZERO
	fs[0].facing = Vector3(0, 0, -1)
	fs[1].global_position = Vector3(0, 0, -gap)
	fs[1].facing = Vector3(0, 0, 1)
	var hp_set: Array = setup.get("hp", [-1.0, -1.0])
	for i in 2:
		if float(hp_set[i]) > 0.0:
			fs[i].health = float(hp_set[i])
	var params := SimParams.bake(fs[0], fs[1])
	if setup.has("meter"):
		for i in 2:
			fs[i].meter = float(setup["meter"][i])
			params[i]["meter0"] = int(round(float(setup["meter"][i]) * 1000.0))
	await physics_frame
	var r := _empty_result()
	var hp0 := [fs[0].health, fs[1].health]
	var holds := [{}, {}]
	for t in n:
		for i in 2:
			if holds[i].has("move"):
				var d0: int = int(holds[i]["move"])
				fs[i].move_input = _dir_off(d0) if i == 0 else -_dir_off(d0)
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
				"boss": f.boss_skill(f.selected_boss())
				"spell": f.cast_spell()
				"boss_var": f.boss_variation()
				"art": f.special()
				"summon": f.summon()
				"mount": f.toggle_mount()
				"jump": f.jump()
				"move_on": holds[int(e[1])]["move"] = int(e[3])
				"move_off": holds[int(e[1])].erase("move")
				"sprint_on": f.want_sprint = true
				"sprint_off": f.want_sprint = false
				"shoot":
					f.shoot()
					f.want_shot_hold = int(e[3]) > 0
					holds[int(e[1])]["shot"] = t + int(e[3])
		for i in 2:
			var h: Dictionary = holds[i]
			if h.has("move"):
				var d32: int = int(h["move"])
				fs[i].move_input = _dir_off(d32) if i == 0 else -_dir_off(d32)
			if h.has("charge") and t >= int(h["charge"]):
				fs[i].want_charge = false
			if h.has("shot") and t >= int(h["shot"]):
				fs[i].want_shot_hold = false
		var h1 := fs[1].health
		var pe: Node3D = fs[1].active_eikon if is_instance_valid(fs[1].active_eikon) else null
		var ph: float = float(pe.get("health")) if pe else 0.0
		await physics_frame
		if OS.get_environment("PARITY_DBG") != "" and t < 50:
			for c in fs[0].get_parent().get_children():
				if c is Projectile: print("O %d off=%.1f p(%.2f,%.2f,%.2f) t(%.2f,%.2f)" % [t, rad_to_deg(Vector2(c.direction.x, c.direction.z).angle_to(Vector2(fs[1].global_position.x - c.global_position.x, fs[1].global_position.z - c.global_position.z))), c.global_position.x, c.global_position.y, c.global_position.z, fs[1].global_position.x, fs[1].global_position.z])
		if pe:
			r["pet1"] += maxf(ph - (float(pe.get("health")) if is_instance_valid(pe) and bool(pe.get("alive")) else 0.0), 0.0) if (not is_instance_valid(pe) or bool(pe.get("alive")) or float(pe.get("health")) <= 0.0) else 0.0
		if fs[0].airborne: r["air0"] += 1
		r["ymax0"] = maxf(r["ymax0"], fs[0].global_position.y)
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
	r["dist"] = MeshUtil.flat(fs[1].global_position - fs[0].global_position).length()
	r["st1"] = fs[1].stamina
	r["lvl0"] = fs[0].staggers * 1 + fs[0].stuns * 10 + fs[0].knockdowns * 100
	r["lvl1"] = fs[1].staggers * 1 + fs[1].stuns * 10 + fs[1].knockdowns * 100
	r["parries"] = fs[0].parries_landed + fs[1].parries_landed
	r["dodges"] = fs[0].rolls_dodged + fs[1].rolls_dodged
	r["guard_breaks"] = fs[0].guard_breaks + fs[1].guard_breaks
	r["hits0"] = fs[0].hits_landed
	r["hits1"] = fs[1].hits_landed
	r["stance_breaks"] = fs[0].stance_breaks + fs[1].stance_breaks
	r["crits"] = fs[0].crits + fs[1].crits
	for i in 2:
		var pr: Dictionary = fs[i].status_fx.procs
		r["procs%d" % i] = int(pr["sangrado"]) + int(pr["veneno"]) + int(pr["congelacion"])
	for f in fs:
		f.queue_free()
	await physics_frame
	return {"params": params, "r": r, "hp_start": hp0}

# ---------------- Sim ----------------
func _sim(P: Array, sc: Array, hp_start: Array) -> Dictionary:
	var gap: float = sc[1]
	var n: int = sc[2]
	var script: Array = sc[3]
	var s := FightSim.initial(P, 1, false)
	s[S.X] = 0
	s[S.FACE] = 0
	s[F + S.X] = int(round(gap * 1000000.0))
	s[F + S.FACE] = 128
	for i in 2:
		s[i * F + S.HP] = int(round(float(hp_start[i]) * 1000.0))
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
			"boss": ins[i][t] |= S.IN_BOSS
			"spell": ins[i][t] |= S.IN_SPELL
			"boss_var": ins[i][t] |= S.IN_BOSS_VAR
			"art": ins[i][t] |= S.IN_ART
			"summon": ins[i][t] |= S.IN_EIKON
			"mount": ins[i][t] |= S.IN_MOUNT
			"jump": ins[i][t] |= S.IN_JUMP
			"move_on":
				var md: int = (int(e[3]) + (16 if i == 1 else 0)) & 31
				for k in range(t, n): ins[i][k] = (ins[i][k] & ~S.IN_DIR_MASK) | S.IN_MOVE | md
			"move_off":
				for k in range(t, n): ins[i][k] &= ~(S.IN_MOVE | S.IN_DIR_MASK)
			"sprint_on":
				for k in range(t, n): ins[i][k] |= S.IN_SPRINT
			"sprint_off":
				for k in range(t, n): ins[i][k] &= ~S.IN_SPRINT
			"shoot":
				for k in range(t, mini(t + maxi(int(e[3]), 1), n)): ins[i][k] |= S.IN_ATK
	var r := _empty_result()
	for t in n:
		var h1: int = s[F + S.HP]
		var pt: int = s[F + S.EK_T]
		var ph: int = s[F + S.EK_HP]
		FightSim.step(s, P, ins[0][t], ins[1][t])
		if OS.get_environment("PARITY_DBG") != "" and t < 50:
			for j in S.PROJ_MAX:
				var q: int = S.PROJ_BASE + j * S.PR_FIELDS
				if s[q + S.PR_ON] > 0: print("S %d off=%.1f p(%.2f,%.2f,%.2f) t(%.2f,%.2f)" % [t, rad_to_deg(Vector2(s[q+S.PR_VX], s[q+S.PR_VZ]).angle_to(Vector2(s[F+S.X]-s[q+S.PR_X], s[F+S.Z]-s[q+S.PR_Z]))), s[q+S.PR_X]/1e6, s[q+S.PR_Y]/1e6, s[q+S.PR_Z]/1e6, s[F+S.X]/1e6, s[F+S.Z]/1e6])
		if pt > 0 and s[F + S.MOUNTED] == 0:
			if s[F + S.EK_T] > 0: r["pet1"] += maxf((ph - s[F + S.EK_HP]) / 1000.0, 0.0)
			elif s[F + S.EK_HP] <= 0: r["pet1"] += ph / 1000.0
		for i in 2:
			if s[i * F + S.STUN] > 0:
				r["stun%d" % i] += 1
		if OS.get_environment("PARITY_TRACE") != "" and t % 10 == 0:
			r["log"].append("t%d st%.2f e%.2f a%d" % [t, s[S.ST] / 1000.0, s[S.EXH] / 60.0, s[S.ATK_STATE]])
		if s[F + S.HP] < h1:
			r["log"].append("%d:%.1f" % [t, (h1 - s[F + S.HP]) / 1000.0])
		if r["first_hit"] < 0 and s[F + S.HP] < h1:
			r["first_hit"] = t
		if s[S.AIR] != 0: r["air0"] += 1
		r["ymax0"] = maxf(r["ymax0"], s[S.FY] / 1000000.0)
	r["dmg0"] = float(hp_start[0]) - s[S.HP] / 1000.0
	r["dmg1"] = float(hp_start[1]) - s[F + S.HP] / 1000.0
	r["crits"] = s[S.CRITS] + s[F + S.CRITS]
	for i in 2:
		r["procs%d" % i] = s[i * F + S.PROC0] + s[i * F + S.PROC1] + s[i * F + S.PROC2]
	r["lvl0"] = s[S.STAGGERS] + s[S.STUNS] * 10 + s[S.KNOCKDOWNS] * 100
	r["lvl1"] = s[F + S.STAGGERS] + s[F + S.STUNS] * 10 + s[F + S.KNOCKDOWNS] * 100
	r["parries"] = s[S.PARRIES] + s[F + S.PARRIES]
	r["dodges"] = s[S.DODGES] + s[F + S.DODGES]
	r["guard_breaks"] = s[S.GUARD_BREAKS] + s[F + S.GUARD_BREAKS]
	r["hits0"] = s[S.HITS]
	r["hits1"] = s[F + S.HITS]
	r["stance_breaks"] = s[S.STANCE_BREAKS] + s[F + S.STANCE_BREAKS]
	r["dist"] = FxMath.length(s[F + S.X] - s[S.X], s[F + S.Z] - s[S.Z]) / 1000000.0
	r["st1"] = s[F + S.ST] / 1000.0
	return r
