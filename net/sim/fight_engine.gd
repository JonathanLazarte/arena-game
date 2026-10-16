class_name FightEngine
extends RbEngine
## Motor de rollback con las reglas de combate reducidas (FightSim).
var params: Array
var seed_v: int
var hitstop: bool
var gap_um: int = 6000000 ## separación inicial
## Rondas en la sim (online): ROUND_GAP ticks tras una caída se reinicia desde `spawn`,
## conservando victorias; nadie reinicia fuera de step(), así que es seguro ante rollback.
var rounds := false
var wins_needed := 2
const ROUND_GAP := 150
var spawn: Array[int] = [] ## [x0, z0, face0, x1, z1, face1] µm / rumbo; vacío = gap_um
var fx: SimFx ## opcional: efectos deduplicados frente a re-simulación
func _init(p: Array = [], sd: int = 1, hs: bool = true) -> void:
	params = p if not p.is_empty() else SimParams.defaults()
	seed_v = sd
	hitstop = hs
func initial() -> PackedInt64Array:
	var s := FightSim.initial(params, seed_v, hitstop)
	if spawn.size() == 6:
		for i in 2:
			var o := i * FightSim.F_FIELDS
			s[o + FightSim.X] = spawn[i * 3]
			s[o + FightSim.Z] = spawn[i * 3 + 1]
			s[o + FightSim.FACE] = spawn[i * 3 + 2]
	else:
		s[FightSim.X] = -gap_um / 2
		s[FightSim.F_FIELDS + FightSim.X] = gap_um / 2
	return s

func match_over(s: PackedInt64Array) -> int: ## -1 en curso; si no, ganador
	for i in 2:
		if s[FightSim.P_BASE + FightSim.G_WINS0 + i] >= wins_needed:
			return i
	return -1

func _round_reset(s: PackedInt64Array) -> void:
	var g := FightSim.P_BASE
	if not rounds or s[g + FightSim.G_END_T] < ROUND_GAP or match_over(s) >= 0:
		return
	var n := initial()
	n[g + FightSim.G_WINS0] = s[g + FightSim.G_WINS0]
	n[g + FightSim.G_WINS1] = s[g + FightSim.G_WINS1]
	n[g + FightSim.G_ROUND] = s[g + FightSim.G_ROUND] + 1
	n[g + FightSim.G_FRAME] = s[g + FightSim.G_FRAME]
	n[g + FightSim.G_RNG] = s[g + FightSim.G_RNG]
	for i in s.size():
		s[i] = n[i]
func step(s: PackedInt64Array, a: int, b: int) -> void:
	if fx == null:
		FightSim.step(s, params, a, b)
		_round_reset(s)
		return
	var prev := s.duplicate()
	FightSim.step(s, params, a, b)
	_round_reset(s)
	if s[FightSim.P_BASE + FightSim.G_ROUND] == prev[FightSim.P_BASE + FightSim.G_ROUND]:
		fx.feed(SimEvents.diff(prev, s))
func checksum(s: PackedInt64Array) -> int:
	return FightSim.checksum(s)

func on_rollback(from_frame: int) -> void:
	if fx: fx.begin_resim(from_frame)
func after_tick(confirmed: int, frame: int) -> void:
	if fx: fx.flush(confirmed, frame)
