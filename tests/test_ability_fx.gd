extends SceneTree
## Fase 9: efectos de habilidades dibujados desde el estado de la sim (SimAbilityFx): para cada
## habilidad de jefe se usa en la sim y se comprueba el visual antiguo correspondiente (brillo,
## aura de la estocada, burbuja, desaparición, rastro, aliento, furia, marcas, columna, ondas y
## proyectiles), y que la vista nunca escribe en el estado.
## godot --headless --path . -s res://tests/test_ability_fx.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(parent: Node3D, boss: Array, spells: Array = [], ek := "fenix") -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS[ek])
	f.set_magic(spells, "")
	f.set_boss_abilities(boss)
	parent.add_child(f)
	return f

## Usa `id` (o un hechizo) en la sim y devuelve lo que se vio.
func _case(id: String, spell := "") -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var A := _fighter(world, [id] if id != "" else [], [spell] if spell != "" else [], "grifo" if spell != "" else "fenix")
	var B := _fighter(world, [])
	await process_frame
	var P := SimParams.bake(A, B)
	var e := FightEngine.new(P, 3, true)
	e.gap_um = 3200000
	var s := e.initial()
	var fx := SimAbilityFx.new(A, B, world)
	var seen := {"glow": false, "boss_fx": false, "bubble": false, "hidden": false, "hz": false, "hz_salto": false,
		"column": false, "line": false, "crest": false, "slash": false, "orb": false, "cone": false, "rage": false,
		"mutated": false, "orb_c": Color.BLACK, "started": 0}
	var hit_b := id == "postura_contra"
	for t in 420:
		var ia := FightSim.IN_LOCK
		if t == 30: ia |= FightSim.IN_SPELL if spell != "" else FightSim.IN_BOSS
		var ib := FightSim.IN_LOCK | (FightSim.IN_ATK if hit_b and t >= 50 and t % 24 < 3 else 0)
		e.step(s, ia, ib)
		var before := s.duplicate()
		fx.apply(s, P)
		if s != before: seen["mutated"] = true
		var k := fx.glow_key(0)
		if k != "" and (k == id or k.begins_with(id + ":")): seen["glow"] = true
		if A._boss_fx and A._boss_fx.emitting: seen["boss_fx"] = true
		if is_instance_valid(A.ab_bubble): seen["bubble"] = true
		if not A._rider_root.visible: seen["hidden"] = true
		if fx.cone_on(0): seen["cone"] = true
		if fx.rage_on(0): seen["rage"] = true
		for j in FightSim.HZ_MAX:
			var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
			if s[q + FightSim.HZ_ON] == 0: continue
			if fx.hazard_root(j).visible: seen["hz"] = true
			else: seen["hz_salto"] = true
			if fx.hazard_part(j, "column").visible and fx.hazard_root(j).visible: seen["column"] = true
			if fx.hazard_part(j, "line").visible and fx.hazard_root(j).visible: seen["line"] = true
			if fx.hazard_part(j, "crest").visible and fx.hazard_root(j).visible: seen["crest"] = true
		for j in FightSim.PROJ_MAX:
			if fx.proj_root(j).visible:
				if fx.proj_part(j, "slash").visible: seen["slash"] = true
				if fx.proj_part(j, "orb").visible:
					seen["orb"] = true
					seen["orb_c"] = (fx.proj_part(j, "trail") as MeshInstance3D).material_override.albedo_color
	seen["started"] = s[FightSim.AB_STARTS] + s[FightSim.SPELLS]
	seen["end_glow"] = fx.glow_key(0)
	seen["end_visible"] = A._rider_root.visible
	seen["end_bubble"] = is_instance_valid(A.ab_bubble)
	seen["trails"] = fx.trails[0]
	seen["bursts"] = fx.bursts[0]
	seen["idle"] = s[FightSim.AB_SLOT] < 0 and s[FightSim.BS_PH] == 0
	world.queue_free()
	await process_frame
	return seen

func _run() -> void:
	var timeline := ["tajo_retardado", "presa_verdugo", "giro_martillo", "danza_cisne", "paso_espectral",
		"cuerno_embiste", "tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada", "estocada_negra",
		"flor_umbral", "presa_fauces", "giro_noble", "danza_triple", "alas_picado"]
	var rains := ["carga_area", "rayos_trazadores", "lluvia_meteoros", "flecha_grave", "lluvia_sangre"]
	var columns := ["lanza_celeste", "lluvia_lanzas", "columnas_rayo"]
	var waves := ["onda_rastrera", "embate_sismico", "garra_suelo", "vendaval_hacha", "anillo_fuego", "pisoton"]
	var breaths := ["aliento_dragon", "aliento_rayo", "aliento_escarcha", "chorro_lava"]
	var rages := ["furia_fase", "grito_guerra"]
	var slashes := ["rafaga", "saeta_oscura", "orbe_lunar"]
	var counters := ["postura_contra", "guardia_reflejo"]
	for id: String in BossAbilities.all_ids():
		var r: Dictionary = await _case(id)
		var ok: bool = r["started"] > 0 and r["glow"] and not r["mutated"]
		var what := "brillo"
		if id == "estocada":
			ok = ok and r["boss_fx"]; what += " + aura de partículas"
		elif id == "escudo_mana":
			ok = ok and r["bubble"] and not r["end_bubble"]; what += " + burbuja (se quita al acabar)"
		elif id == "paso_espectral":
			ok = ok and r["hidden"] and r["end_visible"] and r["bursts"] >= 2 and r["trails"] > 0; what += " + desaparece/reaparece con estallido + rastro"
		elif id == "salto_caida":
			ok = ok and r["hz_salto"] and not r["hz"]; what += " + marca oculta (sin aviso)"
		elif id in columns:
			ok = ok and r["hz"] and r["column"]; what += " + columna de luz"
		elif id in rains:
			ok = ok and r["hz"]; what += " + marca de suelo (anillo, relleno, borde)"
		elif id in waves:
			ok = ok and r["line"] and r["crest"]; what += " + línea de aviso y cresta"
		elif id in slashes:
			ok = ok and r["slash"]; what += " + media luna"
		elif id in breaths:
			ok = ok and r["cone"] and r["bursts"] > 0; what += " + cono y chispas"
		elif id in rages:
			ok = ok and r["rage"] and r["bursts"] > 0; what += " + aura de furia"
		elif id in counters:
			what += " (contragolpe: estallidos %d)" % r["bursts"]
		if id in timeline and id != "paso_espectral":
			ok = ok and r["trails"] > 0; what += " + rastro de espada (%d)" % r["trails"]
		check(ok, "%s: %s; la vista no toca la sim" % [id, what])
		if r["idle"]:
			check(r["end_glow"] == "", "%s: al acabar se apaga el brillo" % id)
	var sp: Dictionary = await _case("", "saeta_vendaval")
	check(sp["started"] > 0 and sp["orb"] and not sp["mutated"], "hechizo: orbe con estela (color %s)" % sp["orb_c"])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
