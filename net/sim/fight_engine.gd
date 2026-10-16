class_name FightEngine
extends RbEngine
## Motor de rollback con las reglas de combate reducidas (FightSim).
var params: Array
var seed_v: int
var hitstop: bool
var gap_um: int = 6000000 ## separación inicial
func _init(p: Array = [], sd: int = 1, hs: bool = true) -> void:
	params = p if not p.is_empty() else SimParams.defaults()
	seed_v = sd
	hitstop = hs
func initial() -> PackedInt64Array:
	var s := FightSim.initial(params, seed_v, hitstop)
	s[FightSim.X] = -gap_um / 2
	s[FightSim.F_FIELDS + FightSim.X] = gap_um / 2
	return s
func step(s: PackedInt64Array, a: int, b: int) -> void:
	FightSim.step(s, params, a, b)
func checksum(s: PackedInt64Array) -> int:
	return FightSim.checksum(s)
