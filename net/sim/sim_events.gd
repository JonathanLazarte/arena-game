class_name SimEvents
extends RefCounted
## Eventos de presentación derivados de la diferencia entre dos estados (antes/después de un tick).
## La sim no emite nada: los efectos (sonido, partículas, sacudida) se deducen del estado, así
## que una re-simulación produce exactamente las mismas claves y SimFx puede deduplicarlas.

const COUNTERS := {
	FightSim.HITS: "hit", FightSim.BLOCKS: "block", FightSim.PARRIES: "parry",
	FightSim.DODGES: "dodge", FightSim.STAGGERS: "stagger", FightSim.STUNS: "stun",
	FightSim.GUARD_BREAKS: "guard_break", FightSim.STANCE_BREAKS: "stance_break",
	FightSim.CRITS: "crit", FightSim.SHOTS: "shot",
	FightSim.PROC0: "bleed", FightSim.PROC1: "poison", FightSim.PROC2: "frost",
	# fase 4 (la telegrafía de «ability» lleva el código de habilidad en "code" = AB_LAST)
	FightSim.AB_STARTS: "ability", FightSim.AB_HITS: "ability_hit", FightSim.AB_INTR: "ability_interrupt",
	FightSim.GRABS: "grab", FightSim.SPELLS: "cast", FightSim.SUMMONS: "summon",
	FightSim.EK_SPECIALS: "eikon_special", FightSim.EK_HITS: "eikon_hit",
	FightSim.SHIELD_ABSORB: "shield_absorb", FightSim.DISMOUNTS: "dismount",
}

## Devuelve [{key, frame, kind, player}] del tick prev -> cur.
static func diff(prev: PackedInt64Array, cur: PackedInt64Array, P: Array = []) -> Array:
	var out: Array = []
	var fr := FightSim.frame(prev)
	for i in 2:
		var o := i * FightSim.F_FIELDS
		for k: int in COUNTERS:
			if cur[o + k] > prev[o + k]:
				var e := _ev(fr, COUNTERS[k], i)
				if k == FightSim.AB_STARTS: e["code"] = int(cur[o + FightSim.AB_LAST])
				out.append(e)
		if prev[o + FightSim.ATK_STATE] != FightSim.Atk.WINDUP and cur[o + FightSim.ATK_STATE] == FightSim.Atk.WINDUP:
			out.append(_ev(fr, "swing", i))
		if prev[o + FightSim.ROLL_T] < 0 and cur[o + FightSim.ROLL_T] >= 0:
			out.append(_ev(fr, "roll", i))
		if cur[o + FightSim.HP] < prev[o + FightSim.HP]:
			out.append(_ev(fr, "hurt", i))
		if prev[o + FightSim.DOWN_T] <= 0 and cur[o + FightSim.DOWN_T] > 0:
			out.append(_ev(fr, "knockdown", i))
		if cur[o + FightSim.FLASKS] < prev[o + FightSim.FLASKS]:
			out.append(_ev(fr, "flask", i))
		if prev[o + FightSim.PH2] == 0 and cur[o + FightSim.PH2] != 0:
			out.append(_ev(fr, "phase2", i))
		if prev[o + FightSim.ALIVE] != 0 and cur[o + FightSim.ALIVE] == 0:
			out.append(_ev(fr, "death", i))
		var ext := FightSim.ext_of(i)
		if prev.size() > ext + FightSim.EX_COUNTER_HITS and cur.size() > ext + FightSim.EX_COUNTER_HITS:
			if cur[ext + FightSim.EX_COUNTER_HITS] > prev[ext + FightSim.EX_COUNTER_HITS]:
				out.append(_ev(fr, "counter_hit", i))
			if cur[ext + FightSim.EX_CHARGE_TIER] > prev[ext + FightSim.EX_CHARGE_TIER]:
				var tier_idx := int(cur[ext + FightSim.EX_CHARGE_TIER]) - 1
				var code_c := int(cur[o + FightSim.AB_LAST])
				var step_c := int(cur[o + FightSim.AB_FIRED])
				var start_c := fr - maxi(int(cur[o + FightSim.AB_T]) - 1, 0)
				var cev := {
					"key": "%d:charge_tier:%d:%d:%d:%d" % [fr, i, code_c, step_c, tier_idx],
					"dedup_key": "%d:%d:%d:tier_%d:%d" % [i, code_c, step_c, tier_idx, start_c],
					"frame": fr, "kind": "charge_tier", "player": i, "tier": tier_idx + 1,
				}
				var st_c := SimCatalog._step_of(cur, P, i)
				if st_c.has("charge"):
					var tiers_arr: Array = (st_c["charge"] as Dictionary).get("tiers", [])
					if tier_idx >= 0 and tier_idx < tiers_arr.size() and tiers_arr[tier_idx] is Dictionary:
						var td: Dictionary = tiers_arr[tier_idx]
						cev["vfx"] = String(td.get("vfx", ""))
						cev["sfx"] = String(td.get("sfx", ""))
				out.append(cev)
		_ab_events(prev, cur, P, out, fr, i)
	_ground_booms(prev, cur, out, fr)
	return out

## Eventos del motor de pasos. La clave sale del estado (habilidad, paso, tick): un rollback
## que repite el tick repite la clave y SimFx no la dispara dos veces.
static func _ab_events(prev: PackedInt64Array, cur: PackedInt64Array, P: Array, out: Array, fr: int, i: int) -> void:
	if i >= P.size():
		return
	var o := i * FightSim.F_FIELDS
	var slot := cur[o + FightSim.AB_SLOT]
	if slot < 0:
		return
	var boss: Array = P[i].get("boss", [])
	if slot < 0 or slot >= boss.size():
		return
	var ab: Dictionary = boss[slot]
	var typ := int(ab.get("type", -1))
	var evs: Array = []
	var step_i := 0
	if typ == SimAbilities.T_CATALOG:
		var steps: Array = ab.get("steps", [])
		step_i = cur[o + FightSim.AB_FIRED]
		if step_i < 0 or step_i >= steps.size():
			return
		var st: Dictionary = steps[step_i]
		evs = st.get("evs", [])
	elif typ == SimAbilities.T_STEPS:
		evs = ab.get("evs", [])
	else:
		return
	var same := prev[o + FightSim.AB_SLOT] == slot and prev[o + FightSim.AB_LAST] == cur[o + FightSim.AB_LAST]
	if typ == SimAbilities.T_CATALOG:
		same = same and prev[o + FightSim.AB_FIRED] == cur[o + FightSim.AB_FIRED]
	var ts_prev := prev[o + FightSim.AB_T] - 1 if same else -1
	var ts := cur[o + FightSim.AB_T] - 1
	var code := int(cur[o + FightSim.AB_LAST])
	var step_start_fr := fr - maxi(ts, 0)
	for ev: Dictionary in evs:
		var tick := int(ev.get("tick", 0))
		if ts_prev < tick and ts >= tick:
			var id := String(ev.get("id", ""))
			var step := step_i if typ == SimAbilities.T_CATALOG else int(ev.get("step", 0))
			var shake_lvl := int(ev.get("shake", 0))
			var item := {
				"key": "%d:ab_ev:%d:%d:%d:%s" % [fr, i, code, step, id],
				"dedup_key": "%d:%d:%d:%s:%d" % [i, code, step, id, step_start_fr],
				"frame": fr, "kind": "ab_ev", "player": i, "shake": shake_lvl,
				"ability": code, "step": step, "event_id": id, "start_tick": step_start_fr,
			}
			if ev.has("dur"): item["duration_ticks"] = int(ev["dur"])
			if ev.has("outlive"): item["outlive_step"] = int(ev["outlive"]) != 0
			if ev.has("attach"): item["attach"] = AbilityCatalog.ATTACH_POINTS[clampi(int(ev["attach"]), 0, AbilityCatalog.ATTACH_POINTS.size() - 1)]
			if ev.has("sfx_attach"): item["sfx_attach"] = AbilityCatalog.ATTACH_POINTS[clampi(int(ev["sfx_attach"]), 0, AbilityCatalog.ATTACH_POINTS.size() - 1)]
			if ev.has("follow"): item["follow"] = int(ev["follow"]) != 0
			if ev.has("sfx_loop"): item["sfx_loop"] = int(ev["sfx_loop"]) != 0
			if ev.has("stop_int"): item["stop_on_interrupt"] = int(ev["stop_int"]) != 0
			if ev.has("footstep"): item["footstep"] = int(ev["footstep"]) != 0
			if ev.has("vfx"): item["vfx"] = String(ev["vfx"])
			if ev.has("sfx"): item["sfx"] = String(ev["sfx"])
			if ev.has("shake_obj") and ev["shake_obj"] is Dictionary:
				var so: Dictionary = ev["shake_obj"]
				item["falloff_start_um"] = int(so.get("falloff_start", 0))
				item["falloff_end_um"] = int(so.get("falloff_end", 0))
				item["haptic"] = AbilityCatalog.HAPTIC_LEVELS[clampi(int(so.get("haptic", shake_lvl)), 0, 3)]
				item["origin_x"] = int(cur[o + FightSim.X])
				item["origin_z"] = int(cur[o + FightSim.Z])
			elif shake_lvl > 0:
				item["haptic"] = AbilityCatalog.HAPTIC_LEVELS[clampi(shake_lvl, 0, 3)]
				item["origin_x"] = int(cur[o + FightSim.X])
				item["origin_z"] = int(cur[o + FightSim.Z])
			out.append(item)

## Calcula la intensidad de sacudida de cámara según la distancia al origen (falloff_start_m..falloff_end_m).
static func shake_intensity(ev: Dictionary, listener_x_um: int, listener_z_um: int) -> float:
	var lvl := float(ev.get("shake", 0))
	if lvl <= 0.0 or not ev.has("falloff_end_um"):
		return lvl
	var f_start := int(ev.get("falloff_start_um", 0))
	var f_end := int(ev.get("falloff_end_um", 0))
	if f_end <= 0:
		return lvl
	var dx := listener_x_um - int(ev.get("origin_x", 0))
	var dz := listener_z_um - int(ev.get("origin_z", 0))
	var d := FxMath.length(dx, dz)
	if d <= f_start:
		return lvl
	if d >= f_end:
		return 0.0
	return lvl * float(f_end - d) / float(maxi(f_end - f_start, 1))

static func effective_haptic(ev: Dictionary, haptics_on: bool = true) -> String:
	if not haptics_on:
		return "none"
	if ev.has("haptic"):
		return String(ev["haptic"])
	var lvl := clampi(int(ev.get("shake", 0)), 0, 3)
	return AbilityCatalog.HAPTIC_LEVELS[lvl]

## La línea quieta estalla entera. La sacudida sale del cambio de estado, no de un tick suelto.
static func _ground_booms(prev: PackedInt64Array, cur: PackedInt64Array, out: Array, fr: int) -> void:
	for j in FightSim.HZ_MAX:
		var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
		if cur[q + FightSim.HZ_ON] == 0 or cur[q + FightSim.HZ_TYPE] != 2 or cur[q + FightSim.HZ_SPD] != 0:
			continue
		if prev[q + FightSim.HZ_DONE] != 0 or cur[q + FightSim.HZ_DONE] == 0:
			continue
		var owner := int(cur[q + FightSim.HZ_OWNER])
		out.append({
			"key": "%d:ground_boom:%d:%d" % [fr, owner, j],
			"frame": fr, "kind": "ground_boom", "player": owner, "shake": 2,
		})

static func _ev(fr: int, kind: String, p: int) -> Dictionary:
	return {"key": "%d:%s:%d" % [fr, kind, p], "frame": fr, "kind": kind, "player": p}
