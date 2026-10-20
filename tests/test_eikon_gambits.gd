extends SceneTree
## Fase 4: Gambits de Eikon estilo FFXII (condicionales de vida, situación táctica y acciones con CD).
## godot --headless --path . -s res://tests/test_eikon_gambits.gd

var fails := 0

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(eikon_id: String, gambits: Array = []) -> Fighter:
	var f := Fighter.new()
	f.character = Catalog.character("caballero")
	f.eikon = load(Catalog.EIKONS[eikon_id])
	f.eikon_gambits = gambits if not gambits.is_empty() else EikonGambits.default_for(eikon_id)
	root.add_child(f)
	return f

func _run() -> void:
	print("--- TEST FASE 4: DEFINICIONES Y ESTRUCTURA DE GAMBITS ---")
	for eid: String in ["fenix", "lobo", "golem", "grifo"]:
		var defs: Array = EikonGambits.default_for(eid)
		check(defs.size() == 3, "%s: tiene 3 ranuras por defecto" % eid)
		for slot in defs:
			check(slot.has("cond") and slot.has("act"), "%s: ranura tiene cond y act" % eid)
			check(EikonGambits.CONDITIONS.has(slot["cond"]), "%s: condición válida (%s)" % [eid, slot["cond"]])
			check(EikonGambits.ACTIONS.has(slot["act"]), "%s: acción válida (%s)" % [eid, slot["act"]])

	var sanitized: Array = EikonGambits.sanitize([{"cond": "invalid", "act": "invalid"}], "fenix")
	check(sanitized.size() == 3, "sanitize fuerza 3 ranuras")
	check(sanitized[0]["cond"] != "invalid" and sanitized[0]["act"] != "invalid", "sanitize corrige claves no válidas")

	print("--- TEST FASE 4: GAMESTATE Y PERSISTENCIA ---")
	var gs := root.get_node_or_null("GameState")
	if gs:
		var g0: Array = gs.eikon_gambits_for("fenix")
		check(g0.size() == 3, "GameState expone 3 ranuras para fénix")
		var init_cond: String = String(g0[0]["cond"])
		gs.cycle_gambit_condition(0, "fenix")
		var g1: Array = gs.eikon_gambits_for("fenix")
		check(g1[0]["cond"] != init_cond, "cycle_gambit_condition avanza la condición (%s -> %s)" % [init_cond, g1[0]["cond"]])
		var init_act: String = String(g0[0]["act"])
		gs.cycle_gambit_action(0, "fenix")
		var g2: Array = gs.eikon_gambits_for("fenix")
		check(g2[0]["act"] != init_act, "cycle_gambit_action avanza la acción (%s -> %s)" % [init_act, g2[0]["act"]])

	print("--- TEST FASE 4: DETERMINISMO Y EVALUACIÓN DE GAMBITS EN SIMULACIÓN ---")
	# Creamos luchadores:
	# A: Fénix con Eikon Gambits:
	#   Slot 0: owner_hp_lt_50 -> shield
	#   Slot 1: enemy_hp_lt_35 -> special
	#   Slot 2: always -> basic
	var gambits_A := [
		{"cond": EikonGambits.COND_OWNER_HP_50, "act": EikonGambits.ACT_SHIELD},
		{"cond": EikonGambits.COND_ENEMY_HP_35, "act": EikonGambits.ACT_SPECIAL},
		{"cond": EikonGambits.COND_ALWAYS, "act": EikonGambits.ACT_BASIC},
	]
	var A := _fighter("fenix", gambits_A)
	var B := _fighter("lobo")
	await process_frame

	var P := SimParams.bake(A, B)
	# Fénix no es montable en este test para probarlo como compañero directo a pie
	P[0]["ek"]["ride"] = 0
	P[1]["ek"]["ride"] = 0

	var eng := FightEngine.new(P, 1, true)
	var s := eng.initial()

	# Invocamos eikon de A (llenamos medidor y activamos eikon a pie)
	s[FightSim.METER] = FightSim.METER_MAX
	s[FightSim.EK_T] = 1000 # 16.6 segundos de eikon activo
	s[FightSim.EK_X] = s[FightSim.X]
	s[FightSim.EK_Z] = s[FightSim.Z]

	# Test 1: Con vida al 100%, Slot 0 (owner_hp < 50%) NO debe activarse
	eng.step(s, 0, 0)
	check(s[FightSim.SKIN_T] == 0, "A con 100%% de vida: Slot 0 (escudo) no se activa")

	# Test 2: Reducimos vida de A a 40% (40000 / 100000)
	s[FightSim.HP] = 40000
	s[FightSim.EK_CD] = 0 # listo para evaluar
	eng.step(s, 0, 0)
	check(s[FightSim.SKIN_T] > 0, "A con 40%% de vida: Slot 0 (escudo) se activa inmediatamente (%d ticks)" % s[FightSim.SKIN_T])
	
	# Comprobamos que el slot 0 entró en enfriamiento y no resetea SKIN_T indefinidamente
	var skin_val := s[FightSim.SKIN_T]
	for k in 10:
		eng.step(s, 0, 0)
	check(s[FightSim.SKIN_T] < skin_val, "Cooldown del Gambit impide spam continuo (skin_t decrementa de %d a %d)" % [skin_val, s[FightSim.SKIN_T]])

	# Test 3: Rival (B) con poca vida (< 35%) activa Slot 1 (Ataque Especial)
	s[FightSim.F_FIELDS + FightSim.HP] = 30000 # 30%
	s[FightSim.HP] = 80000 # Dueño ya curado, para que Slot 0 no cumpla condición
	s[FightSim.EK_CD] = 0
	var specials_before := s[FightSim.EK_SPECIALS]
	eng.step(s, 0, 0)
	check(s[FightSim.EK_SPECIALS] > specials_before, "Rival con <35%% HP: Eikon activa ataque especial (%d -> %d)" % [specials_before, s[FightSim.EK_SPECIALS]])

	# Test 4: Interrupción táctica (COND_ENEMY_CHARGING -> ACT_DISRUPT)
	var gambits_disrupt := [
		{"cond": EikonGambits.COND_ENEMY_CHARGING, "act": EikonGambits.ACT_DISRUPT},
		{"cond": EikonGambits.COND_ALWAYS, "act": EikonGambits.ACT_BASIC},
		{"cond": EikonGambits.COND_ALWAYS, "act": EikonGambits.ACT_BASIC},
	]
	var C := _fighter("golem", gambits_disrupt)
	var D := _fighter("lobo")
	await process_frame
	var P2 := SimParams.bake(C, D)
	P2[0]["ek"]["ride"] = 0
	var eng2 := FightEngine.new(P2, 2, true)
	var s2 := eng2.initial()
	s2[FightSim.EK_T] = 1000
	s2[FightSim.EK_X] = s2[FightSim.F_FIELDS + FightSim.X] + 1500000 # a 1.5 metros del rival
	s2[FightSim.EK_Z] = s2[FightSim.F_FIELDS + FightSim.Z]

	# Rival inicia carga de ataque (BS_PH = 1)
	s2[FightSim.F_FIELDS + FightSim.BS_PH] = 1
	for k in 5:
		eng2.step(s2, 0, 0)
	check(s2[FightSim.F_FIELDS + FightSim.BS_PH] == 0, "Rival cargando: Eikon ejecuta Rugido Disruptor y corta la carga (BS_PH pasa a 0)")

	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
