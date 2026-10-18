extends SceneTree
const ExtraCatalog = preload("res://scripts/data/extra_catalog.gd")
## Caballero Umbral y Golpe de Fisura entran al menú y a SimCatalog.
## Los códigos de las 58 anteriores no se corren. godot --headless --path . -s res://tests/test_artorias.gd
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

func _play(id: String, gap: int, ticks: int) -> Dictionary:
	var p := await _bake([id], ["estocada"])
	var e := FightEngine.new(p, 5, true)
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var hp0: int = s[FightSim.F_FIELDS + FightSim.HP]
	var out := {"hurt": 0, "fy": 0, "aoe": 0, "cd": 0, "hits": 0, "starts": 0, "hz_type": -1, "hz_spd": -1, "hz_warn": 0, "hz_range": 0, "hz_w": 0, "air_run": 0, "air_bouts": 0, "air_a": 0, "air_b": 0, "hurt_hold": -1, "hurt_boom": -1, "min_gap": 999000000, "shakes": 0, "booms": 0, "slam_d": -1}
	var air_now := 0
	var was_air := false
	var slam_x := -1
	var slam_z := -1
	var prev := s.duplicate()
	for t in ticks:
		var ia := FightSim.IN_LOCK
		if t == 8:
			ia |= FightSim.IN_BOSS
		prev = s.duplicate()
		e.step(s, ia, FightSim.IN_LOCK)
		var gap_now := FxMath.length(s[FightSim.X] - s[FightSim.F_FIELDS + FightSim.X], s[FightSim.Z] - s[FightSim.F_FIELDS + FightSim.Z])
		out["min_gap"] = mini(int(out["min_gap"]), gap_now)
		for ev: Dictionary in SimEvents.diff(prev, s, p):
			if String(ev.get("kind", "")) == "ground_boom":
				out["booms"] = int(out["booms"]) + 1
			elif String(ev.get("kind", "")) == "ab_ev" and int(ev.get("shake", 0)) >= 2:
				out["shakes"] = int(out["shakes"]) + 1
		if s[FightSim.AB_SLOT] >= 0 and s[FightSim.AB_FIRED] == 1 and slam_x < 0:
			slam_x = s[FightSim.X]
			slam_z = s[FightSim.Z]
		if slam_x >= 0 and int(out["slam_d"]) < 0:
			for j2 in FightSim.HZ_MAX:
				var q2 := FightSim.HZ_BASE + j2 * FightSim.HZ_FIELDS
				if s[q2 + FightSim.HZ_ON] != 0 and s[q2 + FightSim.HZ_SPD] == 0:
					out["slam_d"] = FxMath.length(s[FightSim.X] - slam_x, s[FightSim.Z] - slam_z)
					break
		if s[FightSim.AB_SLOT] < 0 and t > 8 and out["cd"] == 0:
			out["cd"] = s[FightSim.BOSS_CD]
		out["fy"] = maxi(out["fy"], s[FightSim.FY])
		out["hits"] = maxi(out["hits"], s[FightSim.AB_HITS])
		out["starts"] = s[FightSim.AB_STARTS]
		var up := s[FightSim.AIR] != 0
		if up:
			air_now += 1
			out["air_run"] = maxi(int(out["air_run"]), air_now)
			if not was_air:
				out["air_bouts"] = int(out["air_bouts"]) + 1
		else:
			if was_air:
				if int(out["air_a"]) == 0:
					out["air_a"] = air_now
				elif int(out["air_b"]) == 0:
					out["air_b"] = air_now
			air_now = 0
		was_air = up
		var aoe := 0
		for j in FightSim.HZ_MAX:
			var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
			if s[q + FightSim.HZ_ON] == 0:
				continue
			aoe += 1
			out["hz_type"] = s[q + FightSim.HZ_TYPE]
			out["hz_spd"] = s[q + FightSim.HZ_SPD]
			out["hz_warn"] = s[q + FightSim.HZ_WARN]
			out["hz_range"] = s[q + FightSim.HZ_RANGE]
			out["hz_w"] = s[q + FightSim.HZ_W]
			if s[q + FightSim.HZ_TYPE] == 2 and s[q + FightSim.HZ_SPD] == 0:
				var hurt_now: int = hp0 - s[FightSim.F_FIELDS + FightSim.HP]
				if s[q + FightSim.HZ_T] < s[q + FightSim.HZ_WARN]:
					out["hurt_hold"] = hurt_now
				elif int(out["hurt_boom"]) < 0:
					out["hurt_boom"] = hurt_now
		out["aoe"] = maxi(out["aoe"], aoe)
	out["hurt"] = hp0 - s[FightSim.F_FIELDS + FightSim.HP]
	return out

func _run() -> void:
	var ids: Array = BossAbilities.all_ids()
	var art: Array = ["cadena_mandobles", "embestida_perforante", "carga_abisal", "tajo_deslizante", "giros_dobles", "triple_clavada", "salto_estocada", "voltereta_cuchilla", "potenciar_filo", "golpe_fisura"]
	check(ids.size() == 68, "68 habilidades (hay %d)" % ids.size())
	check(ids.slice(58, 68) == art, "Artorias y Fisura van al final")
	check(SimAbilities.code_of("estocada") == 0 and SimAbilities.code_of("martillo_alba") == 49 and SimAbilities.code_of("cadena_mandobles") == 58, "los códigos viejos no se corren")
	check(ExtraCatalog.preset("caballero_umbral") == ["cadena_mandobles", "embestida_perforante", "carga_abisal"], "set base")
	check(ExtraCatalog.preset("caballero_umbral_furia") == ["tajo_deslizante", "giros_dobles", "triple_clavada"], "set furia")
	check(ExtraCatalog.preset("caballero_umbral_agil") == ["salto_estocada", "voltereta_cuchilla", "potenciar_filo"], "set ágil")
	check(ExtraCatalog.preset("prueba_fisura") == ["golpe_fisura"], "preset de fisura")
	for id: String in art:
		check(BossAbilities.codex(id).length() > 40 and BossAbilities.telegraph_text(id) != "" and BossIcon.has_glyph(id), "códice e icono %s" % id)
		var baked: Array = (await _bake([id], ["estocada"]))[0]["boss"]
		check(baked.size() == 1 and int(baked[0]["type"]) == SimAbilities.T_CATALOG and String(baked[0]["id"]) == id, "%s compila como catálogo" % id)

	var cadena: Dictionary = await _play("cadena_mandobles", 1600000, 420)
	check(cadena["starts"] > 0 and cadena["hurt"] > 0 and cadena["hits"] > 0, "mandobles conectan de cerca (daño %d, golpes %d)" % [cadena["hurt"], cadena["hits"]])
	var salto: Dictionary = await _play("salto_estocada", 4000000, 240)
	check(salto["starts"] > 0 and salto["fy"] > 1500000, "Salto Estocada se eleva (altura %d µm)" % salto["fy"])
	var clavada: Dictionary = await _play("triple_clavada", 1600000, 360)
	check(clavada["starts"] > 0 and clavada["hits"] > 0, "Triple Clavada pega en el suelo de cerca (golpes %d)" % clavada["hits"])
	var fisura: Dictionary = await _play("golpe_fisura", 5000000, 300)
	check(fisura["starts"] > 0 and fisura["fy"] > 1500000 and fisura["aoe"] == 1 and int(fisura["hz_type"]) == 2 and int(fisura["hz_spd"]) == 0 and int(fisura["hz_warn"]) == 60 and int(fisura["hz_range"]) >= 27000000 and int(fisura["hz_w"]) >= 2000000 and int(fisura["hurt_hold"]) >= 0 and int(fisura["hurt_boom"]) > int(fisura["hurt_hold"]) and int(fisura["shakes"]) >= 1 and int(fisura["booms"]) >= 1 and int(fisura["slam_d"]) >= 0 and int(fisura["slam_d"]) < 600000, "Fisura: línea de 1 s (%d µm × %d µm), martillazo se mueve %d µm" % [fisura["hz_range"], fisura["hz_w"], fisura["slam_d"]])
	var volt: Dictionary = await _play("voltereta_cuchilla", 3500000, 520)
	check(volt["starts"] > 0 and int(volt["air_a"]) >= 48 and int(volt["air_a"]) <= 80 and int(volt["air_b"]) >= 48 and int(volt["air_b"]) <= 80 and int(volt["air_bouts"]) >= 2 and volt["fy"] >= 2000000 and int(volt["hits"]) >= 2 and int(volt["hurt"]) > 0, "Volteretas: %d y %d ticks en el aire, golpes %d, daño %d, acercamiento %d µm" % [volt["air_a"], volt["air_b"], volt["hits"], volt["hurt"], volt["min_gap"]])

	var pf := await _bake(["carga_abisal"], ["estocada"])
	var eng := FightEngine.new(pf, 3, true)
	var st := eng.initial()
	check(SimAbilities.can_use(st, pf, 0, 0), "sin regla de Fase II el jugador puede usar la carga abisal")
	pf[0]["ph2"] = {"hp_pm": 500, "rage": 540, "invuln": 51, "summon": 0}
	check(not SimAbilities.can_use(st, pf, 0, 0), "el campeón no la usa antes de la Fase II")
	st[FightSim.PH2] = 1
	check(SimAbilities.can_use(st, pf, 0, 0), "en Fase II sí")

	var sums: Array[int] = []
	var pd := await _bake(["cadena_mandobles", "salto_estocada"], ["golpe_fisura"])
	for _rep in 2:
		var e2 := FightEngine.new(pd, 4, true)
		e2.gap_um = 2500000
		var s2 := e2.initial()
		for t in 200:
			var a := FightSim.IN_LOCK
			if t == 12:
				a |= FightSim.IN_BOSS
			e2.step(s2, a, FightSim.IN_LOCK)
		sums.append(FightSim.checksum(s2))
	check(sums[0] == sums[1] and sums[0] != 0, "dos pasadas idénticas (checksum %d)" % sums[0])
	check(FightSim.boss_cd_read(st, 0, 70) == 0, "una ranura fuera de las 64 no lee memoria ajena")

	if fails > 0:
		print("FALLÓ: %d" % fails)
		quit(1)
	else:
		print("OK")
		quit(0)
