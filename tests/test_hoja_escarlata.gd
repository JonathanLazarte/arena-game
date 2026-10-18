extends SceneTree
## Ronda 48: las 4 habilidades de Hoja Escarlata corren en la sim. Las 45 anteriores siguen igual.
## godot --headless --path . -s res://tests/test_hoja_escarlata.gd
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

func _play(id: String, gap: int, ticks: int, alt: bool) -> Dictionary:
	var p := await _bake([id], ["estocada"])
	var e := FightEngine.new(p, 5, true)
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var hp0: int = s[FightSim.F_FIELDS + FightSim.HP]
	var self0: int = s[FightSim.HP]
	var out := {"hurt": 0, "fy": 0, "aoe": 0, "step": 0, "cd": 0, "ended": 0, "hits": 0}
	var latched := false
	for t in ticks:
		var ia := FightSim.IN_LOCK
		if t == 8:
			ia |= FightSim.IN_BOSS
		var step_i: int = s[FightSim.AB_FIRED]
		# La entrada es un flanco. El tick en que empieza el paso tiene AB_T en 0 y el latch no cuenta.
		if alt and s[FightSim.AB_SLOT] >= 0 and step_i == 2 and s[FightSim.AB_T] >= 2 and s[FightSim.AB_T] % 2 == 0:
			ia |= FightSim.IN_BOSS_VAR
			latched = true
		e.step(s, ia, FightSim.IN_LOCK)
		if s[FightSim.AB_SLOT] >= 0:
			out["step"] = maxi(out["step"], s[FightSim.AB_FIRED])
		elif t > 8 and out["ended"] == 0:
			out["ended"] = 1
			out["cd"] = s[FightSim.BOSS_CD]
		out["fy"] = maxi(out["fy"], s[FightSim.FY])
		out["hits"] = maxi(out["hits"], s[FightSim.AB_HITS])
		var aoe := 0
		for j in FightSim.HZ_MAX:
			var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
			if s[q + FightSim.HZ_ON] != 0 and s[q + FightSim.HZ_TYPE] == 1:
				aoe += 1
		out["aoe"] = maxi(out["aoe"], aoe)
	out["hurt"] = hp0 - s[FightSim.F_FIELDS + FightSim.HP]
	out["self"] = s[FightSim.HP] - self0
	out["latched"] = 1 if latched else 0
	return out

func _run() -> void:
	check(FileAccess.file_exists("res://docs/backup/habilidades_ronda46/boss_abilities.gd"), "respaldo de las 6 base")
	check(FileAccess.file_exists("res://docs/backup/habilidades_ronda46/boss_abilities_ext.gd"), "respaldo de las 39 ampliadas")
	var ids: Array = BossAbilities.all_ids()
	check(ids.size() == 68, "68 habilidades (hay %d)" % ids.size())
	check(ids[0] == "estocada" and ids[44] == "guardia_reflejo", "las 45 anteriores no se movieron")
	check(ids.slice(45, 49) == ["trazos_hoja", "danza_garza", "caida_hoja", "floracion_escarlata"], "las nuevas van al final")
	check(HojaCatalog.preset() == ["trazos_hoja", "danza_garza", "floracion_escarlata"], "preset Hoja Escarlata")
	check(SimAbilities.code_of("estocada") == 0 and SimAbilities.code_of("trazos_hoja") == 45, "los códigos viejos no se corren")
	for id: String in ["trazos_hoja", "danza_garza", "caida_hoja", "floracion_escarlata"]:
		check(BossAbilities.codex(id).length() > 40 and BossAbilities.telegraph_text(id) != "", "códice %s" % id)
		check(BossIcon.has_glyph(id), "icono %s" % id)

	var p0 := await _bake(["trazos_hoja", "estocada"], ["estocada"])
	var baked: Array = p0[0]["boss"]
	check(baked.size() == 2, "el horneado conserva las dos habilidades (hay %d)" % baked.size())
	if baked.size() >= 1:
		check(int(baked[0]["type"]) == SimAbilities.T_CATALOG, "Trazos compila como catálogo")
	if baked.size() >= 2:
		check(int(baked[1]["type"]) == SimAbilities.T_STEPS and int(baked[1].get("family", -1)) == SimAbilities.T_ESTOCADA, "la estocada sale por el motor de pasos")

	var est := await _play("trazos_hoja", 1800000, 700, false)
	check(est["hurt"] > 0 and est["hits"] > 0 and est["step"] == 3 and est["cd"] > 0, "estocada final por defecto (daño %d, paso %d, cd %d)" % [est["hurt"], est["step"], est["cd"]])
	var pat := await _play("trazos_hoja", 1800000, 700, true)
	check(pat["latched"] == 1 and pat["step"] == 4 and pat["hurt"] > 0, "patada si se pulsa la variante (paso %d, daño %d)" % [pat["step"], pat["hurt"]])

	var garza := await _play("danza_garza", 6000000, 80, false)
	check(garza["fy"] > 1500000, "la garza salta (altura %d µm)" % garza["fy"])
	var hoja := await _play("caida_hoja", 6000000, 70, false)
	check(hoja["fy"] > 1500000, "Caída de la Hoja se eleva (altura %d µm)" % hoja["fy"])

	var flor := await _play("floracion_escarlata", 3000000, 140, false)
	check(flor["hurt"] > 0 and flor["aoe"] > 0 and flor["self"] < 0, "floración pega, deja anillos y cuesta vida (daño %d, anillos %d)" % [flor["hurt"], flor["aoe"]])

	var pf := await _bake(["floracion_escarlata"], ["estocada"])
	var eng := FightEngine.new(pf, 3, true)
	var st := eng.initial()
	check(SimAbilities.can_use(st, pf, 0, 0), "sin regla de Fase II el jugador puede usarla")
	pf[0]["ph2"] = {"hp_pm": 500, "rage": 540, "invuln": 51, "summon": 0}
	check(not SimAbilities.can_use(st, pf, 0, 0), "el campeón no la usa antes de la Fase II")
	st[FightSim.PH2] = 1
	check(SimAbilities.can_use(st, pf, 0, 0), "en Fase II sí")

	var sums: Array[int] = []
	var pd := await _bake(["trazos_hoja", "danza_garza"], ["caida_hoja"])
	for _rep in 2:
		var e2 := FightEngine.new(pd, 4, true)
		e2.gap_um = 2500000
		var s2 := e2.initial()
		for t in 180:
			var a := FightSim.IN_LOCK
			if t == 12: a |= FightSim.IN_BOSS
			if t == 70: a |= FightSim.IN_BOSS_VAR
			e2.step(s2, a, FightSim.IN_LOCK)
		sums.append(FightSim.checksum(s2))
	check(sums[0] == sums[1] and sums[0] != 0, "dos pasadas idénticas (checksum %d)" % sums[0])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
