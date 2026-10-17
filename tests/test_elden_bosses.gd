extends SceneTree
## Test de verificación de los jefes inspirados en Elden Ring (Radagon, Malenia, Godfrey)
## y de sus variaciones de combo (branch: skill vs alt / IN_BOSS_VAR).
## godot --headless --path . -s res://tests/test_elden_bosses.gd

var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(ids: Array) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(ids)
	root.add_child(f)
	return f

func _bake(ids_a: Array, ids_b: Array) -> Array:
	var a := _fighter(ids_a)
	var b := _fighter(ids_b)
	await process_frame
	var p := SimParams.bake(a, b)
	a.queue_free()
	b.queue_free()
	return p

func _play(id: String, gap: int, ticks: int, input_mode: String = "none", branch_step: int = 1, input_tick: int = 34) -> Dictionary:
	var p := await _bake([id], ["estocada"])
	var e := FightEngine.new(p, 5, true)
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var hp0: int = s[FightSim.F_FIELDS + FightSim.HP]
	var out := {"hurt": 0, "step": 0, "hits": 0, "latched": 0, "ended": 0, "cd": 0, "max_step": 0}
	var latched := false
	for t in ticks:
		var ia := FightSim.IN_LOCK
		if t == 8:
			ia |= FightSim.IN_BOSS
		var step_i: int = s[FightSim.AB_FIRED]
		var ts: int = s[FightSim.AB_T] - 1
		if not latched and s[FightSim.AB_SLOT] >= 0 and step_i == branch_step and ts >= input_tick:
			if input_mode == "alt":
				ia |= FightSim.IN_BOSS_VAR
				latched = true
			elif input_mode == "skill":
				ia |= FightSim.IN_BOSS
				latched = true
		e.step(s, ia, FightSim.IN_LOCK)
		if s[FightSim.AB_SLOT] >= 0:
			out["step"] = s[FightSim.AB_FIRED]
			out["max_step"] = maxi(out["max_step"], s[FightSim.AB_FIRED])
		elif t > 8 and out["ended"] == 0:
			out["ended"] = 1
			out["cd"] = s[FightSim.BOSS_CD]
		out["hits"] = maxi(out["hits"], s[FightSim.AB_HITS])
	out["hurt"] = hp0 - s[FightSim.F_FIELDS + FightSim.HP]
	out["latched"] = 1 if latched else 0
	return out

func _run() -> void:
	print("--- VERIFICACIÓN DE CATÁLOGOS ELDEN BOSSES ---")
	check(FileAccess.file_exists("res://data/abilities/bosses_elden_catalog.json"), "existe bosses_elden_catalog.json")
	var ids := EldenCatalog.ids()
	check(ids.size() == 9, "9 habilidades en EldenCatalog (hay %d)" % ids.size())
	check(EldenCatalog.preset("orden_dorada") == ["martillo_alba", "lanza_veredicto", "triptico_sagrado"], "preset Radagon (Orden Dorada)")
	check(EldenCatalog.preset("hoja_espiral") == ["danza_espirales", "estocada_penetrante", "floracion_purpurea"], "preset Malenia (Hoja Espiral)")
	check(EldenCatalog.preset("senor_telurico") == ["pisoton_telurico", "presa_del_coloso", "hendedura_cataclismica"], "preset Godfrey (Señor Telúrico)")

	for id: String in ids:
		check(BossAbilities.has(id), "BossAbilities reconoce %s" % id)
		check(BossAbilities.codex(id).length() > 30, "códice de %s válido" % id)

	print("--- TEST DE COMPILACIÓN SIM ---")
	var p0 := await _bake(["martillo_alba", "estocada"], ["estocada"])
	var baked: Array = p0[0]["boss"]
	check(baked.size() == 2, "el horneado conserva ambas habilidades")
	check(int(baked[0]["type"]) == SimAbilities.T_CATALOG, "Martillo del Alba compila como T_CATALOG")

	print("--- TEST VARIACIÓN DE COMBOS (BRANCH) ---")
	# 1. Radagon: Martillo del Alba
	# Pulsando skill en la ventana -> Remate Estallido (paso 2)
	var rad_skill := await _play("martillo_alba", 1800000, 220, "skill", 1, 32)
	check(rad_skill["latched"] == 1 and rad_skill["max_step"] == 2 and rad_skill["hurt"] > 0, "Radagon branch skill: remate estallido (paso %d, daño %d)" % [rad_skill["max_step"], rad_skill["hurt"]])
	# Pulsando alt en la ventana -> Remate Barrido (paso 3)
	var rad_alt := await _play("martillo_alba", 1800000, 220, "alt", 1, 32)
	check(rad_alt["latched"] == 1 and rad_alt["max_step"] == 3 and rad_alt["hurt"] > 0, "Radagon branch alt: remate barrido (paso %d, daño %d)" % [rad_alt["max_step"], rad_alt["hurt"]])
	# Sin pulsar en la ventana -> termina en paso 1
	var rad_none := await _play("martillo_alba", 1800000, 220, "none")
	check(rad_none["max_step"] == 1 and rad_none["ended"] == 1, "Radagon sin input: termina por default (paso %d)" % rad_none["max_step"])

	# 2. Godfrey: Pisotón Telúrico
	# Pulsando skill en la ventana -> Hachazo Partidor (paso 1)
	var god_skill := await _play("pisoton_telurico", 1800000, 160, "skill", 0, 20)
	check(god_skill["latched"] == 1 and god_skill["max_step"] == 1 and god_skill["hurt"] > 0, "Godfrey branch skill: hachazo partidor (paso %d, daño %d)" % [god_skill["max_step"], god_skill["hurt"]])
	# Pulsando alt en la ventana -> Rugido de Guerra (paso 2)
	var god_alt := await _play("pisoton_telurico", 1800000, 160, "alt", 0, 20)
	check(god_alt["latched"] == 1 and god_alt["max_step"] == 2 and god_alt["hurt"] > 0, "Godfrey branch alt: rugido de guerra (paso %d, daño %d)" % [god_alt["max_step"], god_alt["hurt"]])
	# Sin pulsar en la ventana -> termina en paso 0
	var god_none := await _play("pisoton_telurico", 1800000, 160, "none")
	check(god_none["max_step"] == 0 and god_none["ended"] == 1, "Godfrey sin input: termina por default (paso %d)" % god_none["max_step"])

	# 3. Malenia: Danza de Espirales
	# Pulsando skill en la ventana -> Segunda ráfaga y caída final (paso 3)
	var mal_skill := await _play("danza_espirales", 1800000, 220, "skill", 1, 18)
	check(mal_skill["latched"] == 1 and mal_skill["max_step"] == 3 and mal_skill["hurt"] > 0, "Malenia branch skill: danza completa hasta caída (paso %d, daño %d)" % [mal_skill["max_step"], mal_skill["hurt"]])
	# Pulsando alt en la ventana -> Repliegue / Corte Evasivo (paso 4)
	var mal_alt := await _play("danza_espirales", 1800000, 200, "alt", 1, 18)
	check(mal_alt["latched"] == 1 and mal_alt["max_step"] == 4 and mal_alt["hurt"] > 0, "Malenia branch alt: corte evasivo y retirada (paso %d, daño %d)" % [mal_alt["max_step"], mal_alt["hurt"]])

	# 4. Godfrey: Presa del Coloso (Grab imbloqueable)
	var presa := await _play("presa_del_coloso", 2000000, 140, "none")
	check(presa["hurt"] > 0 and presa["max_step"] == 1, "Presa del Coloso conecta y ejecuta estrellamiento (daño %d)" % presa["hurt"])

	print("--- DETERMINISMO ---")
	var run1 := await _play("martillo_alba", 1800000, 120, "alt", 1, 32)
	var run2 := await _play("martillo_alba", 1800000, 120, "alt", 1, 32)
	check(run1["hurt"] == run2["hurt"] and run1["max_step"] == run2["max_step"], "simulaciones idénticas producen resultados idénticos")

	print("\nRESUMEN FINAL: %d fallos." % fails)
	quit(0 if fails == 0 else 1)
