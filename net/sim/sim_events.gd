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
}

## Devuelve [{key, frame, kind, player}] del tick prev -> cur.
static func diff(prev: PackedInt64Array, cur: PackedInt64Array) -> Array:
	var out: Array = []
	var fr := FightSim.frame(prev)
	for i in 2:
		var o := i * FightSim.F_FIELDS
		for k: int in COUNTERS:
			if cur[o + k] > prev[o + k]:
				out.append(_ev(fr, COUNTERS[k], i))
		if prev[o + FightSim.ATK_STATE] != FightSim.Atk.WINDUP and cur[o + FightSim.ATK_STATE] == FightSim.Atk.WINDUP:
			out.append(_ev(fr, "swing", i))
		if prev[o + FightSim.ROLL_T] < 0 and cur[o + FightSim.ROLL_T] >= 0:
			out.append(_ev(fr, "roll", i))
		if cur[o + FightSim.HP] < prev[o + FightSim.HP]:
			out.append(_ev(fr, "hurt", i))
		if prev[o + FightSim.DOWN_T] <= 0 and cur[o + FightSim.DOWN_T] > 0:
			out.append(_ev(fr, "knockdown", i))
		if prev[o + FightSim.ALIVE] != 0 and cur[o + FightSim.ALIVE] == 0:
			out.append(_ev(fr, "death", i))
	return out

static func _ev(fr: int, kind: String, p: int) -> Dictionary:
	return {"key": "%d:%s:%d" % [fr, kind, p], "frame": fr, "kind": kind, "player": p}
