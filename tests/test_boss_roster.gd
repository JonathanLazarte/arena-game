extends SceneTree
## Ronda 46: las 26 habilidades nuevas compilan, se ejecutan en la sim y son deterministas.
## godot --headless --path . -s res://tests/test_boss_roster.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

const NEW := ["cuerno_embiste", "tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada",
	"estocada_negra", "flor_umbral", "presa_fauces", "giro_noble", "danza_triple", "alas_picado",
	"garra_suelo", "vendaval_hacha", "anillo_fuego", "pisoton", "lluvia_lanzas", "flecha_grave",
	"lluvia_sangre", "columnas_rayo", "saeta_oscura", "orbe_lunar", "aliento_rayo", "aliento_escarcha",
	"chorro_lava", "grito_guerra", "guardia_reflejo"]
const FAMILY := {
	"cuerno_embiste": SimAbilities.T_TIMELINE, "tajo_cruzado": SimAbilities.T_TIMELINE,
	"zarpazo_sangre": SimAbilities.T_TIMELINE, "barrido_cola": SimAbilities.T_TIMELINE,
	"daga_sagrada": SimAbilities.T_TIMELINE, "estocada_negra": SimAbilities.T_TIMELINE,
	"flor_umbral": SimAbilities.T_TIMELINE, "presa_fauces": SimAbilities.T_TIMELINE,
	"giro_noble": SimAbilities.T_TIMELINE, "danza_triple": SimAbilities.T_TIMELINE,
	"alas_picado": SimAbilities.T_TIMELINE, "garra_suelo": SimAbilities.T_WAVE,
	"vendaval_hacha": SimAbilities.T_WAVE, "anillo_fuego": SimAbilities.T_WAVE, "pisoton": SimAbilities.T_WAVE,
	"lluvia_lanzas": SimAbilities.T_RAIN, "flecha_grave": SimAbilities.T_RAIN,
	"lluvia_sangre": SimAbilities.T_RAIN, "columnas_rayo": SimAbilities.T_RAIN,
	"saeta_oscura": SimAbilities.T_RAFAGA, "orbe_lunar": SimAbilities.T_RAFAGA,
	"aliento_rayo": SimAbilities.T_BREATH, "aliento_escarcha": SimAbilities.T_BREATH,
	"chorro_lava": SimAbilities.T_BREATH, "grito_guerra": SimAbilities.T_RAGE,
	"guardia_reflejo": SimAbilities.T_COUNTER,
}

func _initialize() -> void:
	_run.call_deferred()

func _fighter(ids: Array) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(ids)
	root.add_child(f)
	return f

func _play(id: String, gap: int, ticks: int, hit_back: bool) -> Dictionary:
	var A := _fighter([id])
	var B := _fighter(["estocada"])
	await process_frame
	var P := SimParams.bake(A, B)
	var hp0: int = P[1]["hp"]
	A.queue_free(); B.queue_free()
	var e := FightEngine.new(P, 7, true)
	e.spawn = [-gap / 2, 0, 0, gap / 2, 0, 128]
	var s := e.initial()
	var peak := {"aoe": 0, "wave": 0, "proj": 0, "hits": 0, "rage": 0}
	for t in ticks:
		var ia := FightSim.IN_LOCK
		if t == 8: ia |= FightSim.IN_BOSS
		var ib := FightSim.IN_LOCK
		if hit_back and t >= 20 and t % 20 < 4: ib |= FightSim.IN_ATK
		e.step(s, ia, ib)
		var aoe := 0
		var wave := 0
		for j in FightSim.HZ_MAX:
			var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
			if s[q + FightSim.HZ_ON] == 0:
				continue
			if s[q + FightSim.HZ_TYPE] == 1: aoe += 1
			else: wave += 1
		peak["aoe"] = maxi(peak["aoe"], aoe)
		peak["wave"] = maxi(peak["wave"], wave)
		var pr := 0
		for j in FightSim.PROJ_MAX:
			if s[FightSim.PROJ_BASE + j * FightSim.PR_FIELDS + FightSim.PR_ON] != 0:
				pr += 1
		peak["proj"] = maxi(peak["proj"], pr)
		peak["hits"] = maxi(peak["hits"], s[FightSim.AB_HITS])
		peak["rage"] = maxi(peak["rage"], s[FightSim.RAGE_T])
	peak["hp"] = s[FightSim.F_FIELDS + FightSim.HP]
	peak["hp0"] = hp0
	peak["hurt"] = hp0 - peak["hp"]
	return peak

func _run() -> void:
	check(BossAbilities.all_ids().size() == 49, "49 habilidades (hay %d)" % BossAbilities.all_ids().size())
	check(NEW.size() == 26 and FAMILY.size() == 26, "lote de 26")
	var seen := {}
	for id: String in BossAbilities.all_ids():
		var sn := BossAbilities.short_name(id)
		check(not seen.has(sn), "nombre corto único: %s" % sn)
		seen[sn] = true
		check(BossIcon.has_glyph(id), "icono %s" % id)
		check(BossAbilities.telegraph_text(id) != "", "aviso %s" % id)
	for id: String in NEW:
		var A := _fighter([id])
		var B := _fighter(["estocada"])
		await process_frame
		var P := SimParams.bake(A, B)
		var ab: Dictionary = P[0]["boss"][0]
		check(int(ab["type"]) == int(FAMILY[id]) and String(ab["id"]) == id, "%s compila como %d" % [id, FAMILY[id]])
		check(float(BossAbilities.def(id).get("recovery", BossAbilities.def(id).get("recovery_miss", 0.4))) >= 0.3, "%s tiene recuperación" % id)
		A.queue_free(); B.queue_free()
	var est: Dictionary = await _play("estocada_negra", 2200000, 220, false)
	check(est["hits"] > 0 and est["hurt"] > 0, "estocada negra conecta de cerca (golpes %d, daño %d)" % [est["hits"], est["hurt"]])
	var onda: Dictionary = await _play("garra_suelo", 5000000, 200, false)
	check(onda["wave"] > 0, "garra de suelo suelta la onda")
	var lluvia: Dictionary = await _play("lluvia_sangre", 6000000, 180, false)
	check(lluvia["aoe"] > 0, "lluvia de sangre marca el suelo (%d)" % lluvia["aoe"])
	var flor: Dictionary = await _play("flor_umbral", 14000000, 280, false)
	check(flor["aoe"] > 0 and flor["hits"] == 0, "la flor brota aunque el cuerpo no llegue (marcas %d, golpes %d)" % [flor["aoe"], flor["hits"]])
	var soplo: Dictionary = await _play("chorro_lava", 3000000, 220, false)
	check(soplo["hits"] > 0 and soplo["hurt"] > 0, "el chorro de lava quema dentro del cono (golpes %d)" % soplo["hits"])
	var saeta: Dictionary = await _play("saeta_oscura", 7000000, 120, false)
	check(saeta["proj"] > 0, "la saeta oscura sale")
	var grito: Dictionary = await _play("grito_guerra", 4000000, 80, false)
	check(grito["rage"] > 0, "el grito deja la furia activa (%d)" % grito["rage"])
	var guarda: Dictionary = await _play("guardia_reflejo", 1800000, 160, true)
	check(guarda["hits"] > 0 and guarda["hurt"] > 0, "la guardia refleja castiga el ataque (golpes %d)" % guarda["hits"])
	# misma semilla y las mismas entradas → mismo checksum
	var A2 := _fighter(["danza_triple", "lluvia_lanzas", "aliento_rayo"])
	var B2 := _fighter(["orbe_lunar", "pisoton", "anillo_fuego"])
	await process_frame
	var P2 := SimParams.bake(A2, B2)
	A2.queue_free(); B2.queue_free()
	var sums: Array[int] = []
	for _rep in 2:
		var e := FightEngine.new(P2, 3, true)
		e.gap_um = 4000000
		var s := e.initial()
		for t in 240:
			var a := FightSim.IN_LOCK | FightSim.IN_MOVE
			if t % 50 == 10: a |= FightSim.IN_BOSS
			if t % 50 == 30: a |= FightSim.IN_BOSS_NEXT
			e.step(s, a, FightSim.IN_LOCK | (FightSim.IN_ATK if t % 37 < 3 else 0))
		sums.append(FightSim.checksum(s))
	check(sums[0] == sums[1] and sums[0] != 0, "dos pasadas idénticas (checksum %d)" % sums[0])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
