extends SceneTree
## Piso de §11.2: aviso, bloqueo de tracking y hueco entre golpes.
## godot --headless --path . -s res://tests/test_dodge_floor.gd
const NORMAL := 33
const HEAVY := 45
const JUMP := 60
const LOCK := 18
const CHAIN := 33
const EXEMPT := ["escudo_mana", "furia_fase", "grito_guerra", "postura_contra", "guardia_reflejo"]
const STEP_FILES := [
	"res://data/abilities/hoja_escarlata_catalog.json",
	"res://data/abilities/bosses_elden_catalog.json",
	"res://data/abilities/artorias_caballero_umbral.json",
	"res://data/abilities/golpe_fisura_skill.json",
]
const SPAWNS := ["ground_wave", "ground_mark", "beam", "projectile", "zone"]

var fails := 0

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter() -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(["estocada"])
	root.add_child(f)
	return f

func _heavy(id: String) -> bool:
	return BossAbilities.is_unblockable(id)

func _rafaga_floor(id: String, d: Dictionary) -> int:
	if id == "rafaga" or bool(d.get("light", false)):
		return NORMAL
	return HEAVY

func _run() -> void:
	var f := _fighter()
	await process_frame
	check(SimAbilities.DODGE_LOCK == LOCK, "el sim deja 18 ticks de rumbo quieto")
	for id: String in BossAbilities.all_ids():
		if HojaCatalog.has(id) or EldenCatalog.has(id) or ExtraCatalog.has(id):
			continue
		var ab := SimAbilities.compile(f, id)
		var fam := int(ab.get("family", -1))
		var d := BossAbilities.def(id)
		if id in EXEMPT:
			continue
		if id == "estocada":
			check(int(ab["charge"]) - int(ab["track"]) >= LOCK, "estocada deja de seguir %d ticks antes" % (int(ab["charge"]) - int(ab["track"])))
		elif id == "carga_area":
			check(int(ab["warn"]) >= NORMAL, "carga de área avisa %d ticks" % int(ab["warn"]))
		elif id == "salto_caida":
			check(int(ab["land"]) >= JUMP and int(ab["land"]) - int(ab["lock"]) >= LOCK, "salto y caída: aviso %d, quietud %d" % [int(ab["land"]), int(ab["land"]) - int(ab["lock"])])
		elif id == "combo_falso":
			check(int(ab["stage"]) >= NORMAL and int(ab["var_w"]) >= HEAVY and int(ab["slam_warn"]) >= HEAVY, "pausa falsa: etapa %d, variante %d, aviso del salto %d" % [ab["stage"], ab["var_w"], ab["slam_warn"]])
		elif fam == SimAbilities.T_TIMELINE:
			var hits: Array = ab["hits"]
			var first := JUMP if id == "alas_picado" else (HEAVY if _heavy(id) else NORMAL)
			var gap := HEAVY if _heavy(id) else CHAIN
			var prev := -gap
			var ok := true
			for i in hits.size():
				var h: Array = hits[i]
				if int(h[0]) < (first if i == 0 else prev + gap) or int(h[0]) - int(h[4]) < LOCK:
					ok = false
				prev = int(h[0])
			check(ok and not hits.is_empty(), "%s: golpes con aviso y rumbo quieto" % id)
		elif fam == SimAbilities.T_WAVE:
			check(int(ab["w"]) >= NORMAL and int(ab["warn"]) >= HEAVY, "%s: onda %d / aviso %d" % [id, ab["w"], ab["warn"]])
		elif fam == SimAbilities.T_RAIN:
			var floor := HEAVY if _heavy(id) else NORMAL
			var fires: Array = ab["fire"]
			var ok2 := int(ab["warn"]) >= floor
			for i in range(1, fires.size()):
				if int(fires[i]) - int(fires[i - 1]) < floor:
					ok2 = false
			check(ok2, "%s: lluvia con aviso %d y hueco entre marcas" % [id, ab["warn"]])
		elif fam == SimAbilities.T_BREATH:
			check(int(ab["w"]) >= NORMAL, "%s: el soplo avisa %d ticks" % [id, ab["w"]])
		elif fam == SimAbilities.T_RAFAGA:
			var need := _rafaga_floor(id, d)
			check(int(ab["w"]) >= need, "%s avisa %d (piso %d)" % [id, ab["w"], need])
		else:
			check(false, "%s no entra en el piso (familia %d)" % [id, fam])
	f.queue_free()
	for path: String in STEP_FILES:
		_steps(path)
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)

func _steps(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "se lee %s" % path)
	if not (parsed is Dictionary):
		return
	for a: Variant in (parsed as Dictionary).get("abilities", []):
		if not (a is Dictionary):
			continue
		var ab: Dictionary = a
		var aid := String(ab.get("id", ""))
		for st: Variant in ab.get("steps", []):
			if not (st is Dictionary):
				continue
			var step: Dictionary = st
			var sid := String(step.get("id", ""))
			if aid == "golpe_fisura" and sid == "martillazo":
				var mv: Dictionary = step.get("movement", {})
				var wave: Dictionary = (step.get("spawns", []) as Array)[0]
				check(String(mv.get("type", "")) == "slam" and float(mv.get("max_distance_m", 9.0)) <= 0.35, "fisura martilla a %.2f m" % float(mv.get("max_distance_m", -1)))
				check(float(wave.get("speed_mps", 1)) == 0.0 and int(wave.get("warn_ticks", 0)) == 60 and float(wave.get("range_m", 0)) == 28.0, "fisura: línea quieta de 1 s y 28 m")
				continue
			if aid == "voltereta_cuchilla" and String(step.get("id", "")).begins_with("salto"):
				var leap: Dictionary = step.get("movement", {})
				check(bool(leap.get("impulse", false)) and int(step.get("windup_ticks", 0)) >= JUMP, "%s sale con impulso y avisa %d" % [sid, step.get("windup_ticks", 0)])
			if not _damaging(step):
				continue
			var need := _need(step)
			var w := int(step.get("windup_ticks", 0))
			check(w >= need, "%s/%s avisa %d (piso %d)" % [aid, sid, w, need])
			var tr: Dictionary = step.get("tracking", {})
			if float(tr.get("deg_per_sec", 0)) > 0.0 and w >= LOCK:
				check(w - int(tr.get("lock_at_tick", w)) >= LOCK, "%s/%s bloquea el rumbo %d ticks antes" % [aid, sid, w - int(tr.get("lock_at_tick", 0))])
		if aid == "golpe_fisura":
			var steps: Array = ab.get("steps", [])
			var approach: int = int((steps[0] as Dictionary).get("windup_ticks", 0)) + int((steps[0] as Dictionary).get("active_ticks", 0)) + int((steps[0] as Dictionary).get("recovery_ticks", 0))
			var hammer := approach + int((steps[1] as Dictionary).get("windup_ticks", 0))
			var lock := int(((steps[0] as Dictionary).get("tracking", {}) as Dictionary).get("lock_at_tick", 0))
			check(hammer >= HEAVY and hammer - lock >= LOCK, "fisura: del aviso al martillo %d, quietud %d" % [hammer, hammer - lock])
		if aid == "voltereta_cuchilla":
			var ids: Array = []
			for st2: Variant in ab.get("steps", []):
				ids.append(String((st2 as Dictionary).get("id", "")))
			check(ids == ["salto_1", "salida", "salto_2"], "voltereta: salto, salida, salto")

func _damaging(step: Dictionary) -> bool:
	if not (step.get("hitboxes", []) as Array).is_empty():
		return true
	for sp: Variant in step.get("spawns", []):
		if sp is Dictionary and String((sp as Dictionary).get("type", "")) in SPAWNS:
			return true
	return false

func _heavy_step(step: Dictionary) -> bool:
	for hb: Variant in step.get("hitboxes", []):
		if not (hb is Dictionary):
			continue
		var box: Dictionary = hb
		if box.get("blockable", true) == false or int(box.get("stun_power", 0)) >= 40:
			return true
		var oh: Variant = box.get("on_hit", null)
		if oh is Dictionary and bool((oh as Dictionary).get("knockdown", false)):
			return true
	for sp: Variant in step.get("spawns", []):
		if sp is Dictionary and (sp as Dictionary).get("blockable", true) == false:
			return true
	return false

func _need(step: Dictionary) -> int:
	var mv := String((step.get("movement", {}) as Dictionary).get("type", ""))
	if mv == "leap":
		return JUMP
	if mv == "slam":
		return 48
	var wave_only := (step.get("hitboxes", []) as Array).is_empty()
	for sp: Variant in step.get("spawns", []):
		if sp is Dictionary and String((sp as Dictionary).get("type", "")) == "ground_wave":
			if wave_only:
				return HEAVY
	return HEAVY if _heavy_step(step) else NORMAL
