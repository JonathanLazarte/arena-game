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
static func diff(prev: PackedInt64Array, cur: PackedInt64Array) -> Array:
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
		if prev[o + FightSim.ALIVE] != 0 and cur[o + FightSim.ALIVE] == 0:
			out.append(_ev(fr, "death", i))
	return out

static func _ev(fr: int, kind: String, p: int) -> Dictionary:
	return {"key": "%d:%s:%d" % [fr, kind, p], "frame": fr, "kind": kind, "player": p}
