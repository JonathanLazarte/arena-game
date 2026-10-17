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
		_ab_events(prev, cur, P, out, fr, i)
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
	if int(ab.get("type", -1)) != SimAbilities.T_STEPS:
		return
	var evs: Array = ab.get("evs", [])
	var same := prev[o + FightSim.AB_SLOT] == slot and prev[o + FightSim.AB_LAST] == cur[o + FightSim.AB_LAST]
	var ts_prev := prev[o + FightSim.AB_T] - 1 if same else -1
	var ts := cur[o + FightSim.AB_T] - 1
	var code := int(cur[o + FightSim.AB_LAST])
	for ev: Dictionary in evs:
		var tick := int(ev.get("tick", 0))
		if ts_prev < tick and ts >= tick:
			var id := String(ev.get("id", ""))
			var step := int(ev.get("step", 0))
			out.append({
				"key": "%d:ab_ev:%d:%d:%d:%s" % [fr, i, code, step, id],
				"frame": fr, "kind": "ab_ev", "player": i,
			})

static func _ev(fr: int, kind: String, p: int) -> Dictionary:
	return {"key": "%d:%s:%d" % [fr, kind, p], "frame": fr, "kind": kind, "player": p}
