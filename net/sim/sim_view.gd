class_name SimView
extends RefCounted
## Vuelca el estado de FightSim en los Fighter existentes (modo online: Fighter.sim_driven = true).
## Solo escribe campos que leen la animación (KnightVisual), el HUD y la cámara. Nunca al revés:
## la vista no influye en la simulación, así que se puede re-simular sin tocar nodos.
const S = preload("res://net/sim/fight_sim.gd")
var fighters: Array[Fighter] = []
var arrow_parent: Node3D
var _arrows: Array[MeshInstance3D] = []
## Suavizado visual (online): tras un rollback la posición dibujada no salta al estado corregido;
## guarda el error como desplazamiento y lo reduce SMOOTH_DECAY por tick. La sim no lo ve nunca.
var smooth := false
const SMOOTH_DECAY := 0.75
const SMOOTH_SNAP := 1.5 ## m: errores mayores se aplican de golpe (teletransporte real, reinicio de ronda)
var offsets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _prev_sim: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _prev_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

func _init(a: Fighter, b: Fighter, parent: Node3D = null) -> void:
	fighters = [a, b]
	arrow_parent = parent
	for f in fighters:
		f.sim_driven = true

func apply(s: PackedInt64Array, corrected: bool = false) -> void:
	for i in 2:
		_apply_fighter(fighters[i], s, i * S.F_FIELDS)
		if smooth:
			_smooth(i, s, corrected)
	_apply_arrows(s)

func _smooth(i: int, s: PackedInt64Array, corrected: bool) -> void:
	var o := i * S.F_FIELDS
	var sim := Vector3(s[o + S.X] / 1000000.0, 0.0, s[o + S.Z] / 1000000.0)
	var vel := Vector3(s[o + S.VX] / 1000000.0, 0.0, s[o + S.VZ] / 1000000.0)
	if corrected and _prev_sim[i] != Vector3.INF:
		offsets[i] += (_prev_sim[i] + _prev_vel[i]) - sim # lo que se iba a ver menos lo corregido
	if offsets[i].length() > SMOOTH_SNAP:
		offsets[i] = Vector3.ZERO
	offsets[i] *= SMOOTH_DECAY
	if offsets[i].length() < 0.002:
		offsets[i] = Vector3.ZERO
	_prev_sim[i] = sim
	_prev_vel[i] = vel
	var f := fighters[i]
	f.global_position = Vector3(sim.x + offsets[i].x, f.global_position.y, sim.z + offsets[i].z)

func _apply_fighter(f: Fighter, s: PackedInt64Array, o: int) -> void:
	var hz := 60.0
	f.global_position = Vector3(s[o + S.X] / 1000000.0, s[o + S.FY] / 1000000.0, s[o + S.Z] / 1000000.0)
	f.facing = Vector3(FxMath.COS[s[o + S.FACE]] / 4096.0, 0.0, FxMath.SIN[s[o + S.FACE]] / 4096.0)
	f.planar_vel = Vector3(s[o + S.VX] / 1000000.0 * hz, 0.0, s[o + S.VZ] / 1000000.0 * hz)
	f.velocity = f.planar_vel
	var hp := s[o + S.HP] / 1000.0
	if not is_equal_approx(hp, f.health):
		f.health = hp
		f.health_changed.emit(f.health, f.max_health)
	var st := s[o + S.ST] / 1000.0
	if not is_equal_approx(st, f.stamina):
		f.stamina = st
		f.stamina_changed.emit(f.stamina, s[o + S.EXH] > 0)
	var alive := s[o + S.ALIVE] != 0
	if f.alive and not alive:
		f.alive = false
		f.died.emit(f)
	f.alive = alive
	f.exhausted = s[o + S.EXH] / hz
	f.loadout = s[o + S.LOADOUT]
	f.swap_t = s[o + S.SWAP_T] / hz
	f.atk_state = s[o + S.ATK_STATE]
	f.atk_t = s[o + S.ATK_T] / hz
	f.atk_dur = s[o + S.ATK_DUR] / hz
	f.atk_heavy = s[o + S.ATK_IDX] == SimParams.A_HEAVY
	f.atk_dash = s[o + S.ATK_IDX] == SimParams.A_DASH
	f.atk_jump = s[o + S.ATK_IDX] == SimParams.A_JUMP and s[o + S.ATK_STATE] != S.Atk.NONE
	f.airborne = s[o + S.AIR] != 0
	f.land_t = s[o + S.LAND_T] / hz
	f.velocity.y = s[o + S.FVY] / 1000000.0 * hz
	f.combo = s[o + S.COMBO]
	f.cur_hit = f.combo_hit_for(f.combo) if f.atk_state != Fighter.Atk.NONE and s[o + S.ATK_IDX] < 3 else null
	f.charge_t = s[o + S.CHARGE_T] / hz
	f.roll_t = s[o + S.ROLL_T] / hz if s[o + S.ROLL_T] >= 0 else -1.0
	f.dash_dir = Vector3(FxMath.COS[s[o + S.ROLL_DIR]] / 4096.0, 0.0, FxMath.SIN[s[o + S.ROLL_DIR]] / 4096.0)
	f.backstep_t = s[o + S.BACKSTEP_T] / hz
	f.blocking = s[o + S.BLOCKING] != 0
	f.parry_state = s[o + S.PARRY_STATE]
	f.stun = s[o + S.STUN] / hz
	f.stagger_t = s[o + S.STAGGER_T] / hz
	f.down_t = s[o + S.DOWN_T] / hz
	f.last_stun_level = s[o + S.LAST_LVL]
	f.stance = s[o + S.STANCE] / 1000.0
	f.shot_state = s[o + S.SHOT_STATE]
	f.crit_t = s[o + S.CRIT_T] / hz if s[o + S.CRIT_T] >= 0 else -1.0

func _apply_arrows(s: PackedInt64Array) -> void:
	if arrow_parent == null:
		return
	while _arrows.size() < S.PROJ_MAX:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 1.0)
		m.mesh = bm
		m.visible = false
		arrow_parent.add_child(m)
		_arrows.append(m)
	for j in S.PROJ_MAX:
		var q := S.PROJ_BASE + j * S.PR_FIELDS
		var m := _arrows[j]
		m.visible = s[q + S.PR_ON] != 0
		if m.visible:
			m.global_position = Vector3(s[q + S.PR_X] / 1000000.0, s[q + S.PR_Y] / 1000000.0, s[q + S.PR_Z] / 1000000.0)
			m.rotation.y = atan2(-float(s[q + S.PR_VX]), -float(s[q + S.PR_VZ]))

## Arrastra la entrada local (PlayerCommand / acciones) al int de entrada de la sim.
## move_world: dirección en el mundo (ya relativa a la cámara); null = sin movimiento.
static func pack_input(move_world: Vector3, half: bool, atk: bool, block: bool, parry: bool, roll: bool, sprint: bool, swap: bool, lock: bool) -> int:
	var v := 0
	var flat := Vector2(move_world.x, move_world.z)
	if flat.length() > 0.2:
		var ang := atan2(flat.y, flat.x)
		v = (int(round(ang / TAU * 32.0)) & 31) | S.IN_MOVE | (S.IN_HALF if half else 0)
	if atk: v |= S.IN_ATK
	if block: v |= S.IN_BLOCK
	if parry: v |= S.IN_PARRY
	if roll: v |= S.IN_ROLL
	if sprint: v |= S.IN_SPRINT
	if swap: v |= S.IN_SWAP
	if lock: v |= S.IN_LOCK
	return v
