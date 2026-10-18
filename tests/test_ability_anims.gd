extends SceneTree
## Animación de habilidades de catálogo (data/animations/ability_anims.json): claves alineadas
## con windup/activo/recuperación de cada paso, clips presentes, y pose derivada del tick de la
## sim (mismo tick → mismo tiempo de clip, también "volviendo atrás" como en un rollback).
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("ok   " if c else "FAIL ") + msg)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _steps_of(file: String, id: String) -> Array:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	for a: Dictionary in raw["abilities"]:
		if String(a["id"]) == id:
			return a["steps"]
	return []

func _fighter(ids: Array) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(ids)
	root.add_child(f)
	return f

func _run() -> void:
	var d := AbilityAnims.data()
	check(d.get("abilities", {}).has("golpe_fisura") and d["abilities"].has("voltereta_cuchilla"), "Fisura y Volteretas tienen animación")
	# 1) claves: cubren el paso entero y van en orden
	for id: String in AbilityAnims.all_ids():
		var a: Dictionary = d["abilities"][id]
		var steps := _steps_of(String(a["file"]), id)
		check(not steps.is_empty(), "%s: pasos en %s" % [id, a["file"]])
		for st: Dictionary in steps:
			var total := int(st["windup_ticks"]) + int(st["active_ticks"]) + int(st["recovery_ticks"])
			var segs: Array = a["steps"].get(String(st["id"]), [])
			check(not segs.is_empty(), "%s/%s: tiene tramos" % [id, st["id"]])
			var last := -1
			var mono := true
			for seg: Dictionary in segs:
				for k: Array in seg["keys"]:
					mono = mono and int(k[0]) >= last
					last = int(k[0])
			check(mono, "%s/%s: claves en orden" % [id, st["id"]])
			check(last == total or (segs[segs.size() - 1] as Dictionary).has("loop"), "%s/%s: la última clave cae al final del paso (%d = %d)" % [id, st["id"], last, total])
	# contacto de la Fisura: el impacto del martillo cae en el tick del golpe (windup = ev_impacto)
	var fs := _steps_of("res://data/abilities/golpe_fisura_skill.json", "golpe_fisura")
	var mz: Dictionary = fs[1]
	var ev_t := -1
	for ev: Dictionary in mz.get("events", []):
		if String(ev["id"]) == "ev_impacto":
			ev_t = int(ev["tick"])
	var seg_m: Dictionary = AbilityAnims.sample("golpe_fisura", 1, ev_t)["seg"]
	check(ev_t == int(mz["windup_ticks"]) and absf(AbilityAnims.clip_time(seg_m, ev_t, 1.73) - 0.75) < 0.001, "Fisura: impacto del clip (0,75 s) en el tick %d = windup" % ev_t)
	# 2) vista: clips presentes y pose derivada del tick
	var f := _fighter(["golpe_fisura", "voltereta_cuchilla"])
	await process_frame
	var kv: KnightVisual = f._kv
	for id: String in AbilityAnims.all_ids():
		for seg: Dictionary in AbilityAnims.segments(id):
			check(kv.ap.has_animation(AbilityAnims.clip_name(seg)), "clip presente: %s" % AbilityAnims.clip_name(seg))
	f.sim_driven = true
	f.ab_id = "golpe_fisura"
	f.ab_fired = 1
	var seen: Array = []
	for tick: int in [15, 40, 15]:
		f.ab_tick = tick
		for k in 3:
			kv.update(f, 1.0 / 60.0)
			await physics_frame
		var st := kv.state
		var pos := float(kv.tree.get("parameters/act/%s/anim/current_position" % st)) if st in KnightVisual.AB_STATES else -1.0
		seen.append(pos)
	check(kv.state in KnightVisual.AB_STATES, "Fisura usa el estado de clip propio (%s)" % kv.state)
	check(absf(seen[0] - 0.75) < 0.02, "tick 14 del martillazo → 0,75 s del clip (%.3f)" % seen[0])
	check(absf(seen[0] - seen[2]) < 0.001 and seen[1] > seen[0], "pose = f(tick): volver al tick 15 da la misma pose (%s)" % [seen])
	f.ab_id = "voltereta_cuchilla"
	f.ab_fired = 2
	f.ab_tick = 70
	kv.update(f, 1.0 / 60.0)
	await physics_frame
	var an: AnimationNodeAnimation = kv._ab_anim[kv.state]
	check(String(an.animation).begins_with("abm/"), "Volteretas: el 2.º tajo es el espejado (%s)" % an.animation)
	# 3) sim: los pasos duran lo que dicen las claves
	var b := _fighter(["estocada"])
	await process_frame
	var P := SimParams.bake(f, b)
	var e := FightEngine.new(P, 7, true)
	e.spawn = [-3000000, 0, 0, 3000000, 0, 128]
	var s := e.initial()
	var lens := {}
	var started := false
	for t in 200:
		e.step(s, FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 0 else 0), FightSim.IN_LOCK)
		if s[FightSim.AB_SLOT] >= 0:
			started = true
			var si: int = s[FightSim.AB_FIRED]
			lens[si] = int(lens.get(si, 0)) + 1
	check(started and int(lens.get(0, 0)) == 31 and int(lens.get(1, 0)) >= 58, "sim: saltar dura 31 ticks y martillazo 58 (%s)" % [lens])
	print("FALLÓ %d" % fails if fails > 0 else "TODO OK")
	quit(1 if fails > 0 else 0)
