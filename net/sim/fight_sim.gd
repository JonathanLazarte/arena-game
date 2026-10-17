class_name FightSim
extends RefCounted
## Simulación determinista online, reglas reducidas (espada+escudo y arco; sin monturas, eikons,
## magia ni habilidades de jefe). Estado = PackedInt64Array plano (guardar/cargar = duplicate()).
## Enteros en todo: µm, milésimas, ‰ y ticks a 60 Hz. Mismo orden de reglas que Fighter/FighterCombat.

# ---------------- Entrada (un int por jugador y tick) ----------------
const IN_DIR_MASK := 31        # bits 0-4: rumbo de movimiento en 32 pasos (mundo)
const IN_MOVE := 1 << 5        # hay movimiento
const IN_HALF := 1 << 6        # media inclinación del stick (andar lento)
const IN_ATK := 1 << 7         # ataque mantenido (toque = ligero, mantener = fuerte/carga; con arco tensa)
const IN_BLOCK := 1 << 8       # escudo mantenido
const IN_PARRY := 1 << 9
const IN_ROLL := 1 << 10
const IN_SPRINT := 1 << 11
const IN_SWAP := 1 << 12
const IN_LOCK := 1 << 13       # fijado al rival

static func make_input(dir32: int, move: bool, buttons: int) -> int:
	return (dir32 & IN_DIR_MASK) | (IN_MOVE if move else 0) | buttons

# ---------------- Estado ----------------
enum Atk { NONE, WINDUP, ACTIVE, RECOVERY }
enum Parry { NONE, ACTIVE, RECOVERY }
enum Shot { NONE, DRAW, RECOVER, RELOAD }
enum Act { NONE, LIGHT, HEAVY, PARRY, ROLL, SWAP, SHOOT }
enum Load { SWORD, BOW }

enum {
	X, Z, VX, VZ, FACE, HP, ST, ALIVE, EXH, SINCE_SPEND, SINCE_HIT, LOADOUT, SWAP_T,
	ATK_STATE, ATK_T, ATK_DUR, ATK_IDX, COMBO, CHARGE_T, ATK_LANDED, ATK_HIT, BUFFERED, ATK_GC,
	STEP_LEFT, STEP_TOTAL, DASH_DIR, ROLL_T, ROLL_DIR, ROLL_ATK_BUF, RBUF, BACKSTEP_T, DASH_CD,
	BLOCKING, GC_T, PARRY_STATE, PARRY_T, RIPOSTE_T,
	STUN, STAGGER_T, DOWN_T, STUN_IMM, STUN_ACC, STUN_WIN, STUN_LVL, LAST_LVL, KNOCKDOWNS,
	STANCE, STANCE_BROKEN_T, CRIT_T, CRIT_DONE, INVULN,
	SHOT_STATE, SHOT_T, SHOT_DUR, HOLD_T, BOW_CD, SHOT_CHARGED,
	PREV_IN, ATK_HOLD, HEAVY_FIRED, Q0, Q1, Q2, Q3, QA0, QA1, QA2, QA3, PREV_STUN, SPRINT_PM,
	BU0, BU1, BU2, SN0, SN1, SN2, LK0, LK1, LK2, PROC0, PROC1, PROC2, POISON_T, POISON_E, FROST_T,
	HITS, BLOCKS, PARRIES, DODGES, STAGGERS, STUNS, GUARD_BREAKS, STANCE_BREAKS, DMG_DEALT, CRITS, SHOTS,
	F_FIELDS
}
const P_BASE := 2 * F_FIELDS
enum { G_FRAME, G_FREEZE, G_RNG, G_HITSTOP_ON, G_WINS0, G_WINS1, G_ROUND, G_END_T, G_FIELDS }
## G_END_T: ticks desde que cayó un luchador en esta ronda (0 = ronda en curso). FightEngine reinicia la ronda.
const PROJ_BASE := P_BASE + G_FIELDS
const PROJ_MAX := 8
enum { PR_ON, PR_OWNER, PR_X, PR_Z, PR_Y, PR_VX, PR_VZ, PR_VY, PR_LIFE, PR_RAW, PR_FORCE, PR_DODGED, PR_FIELDS }
const SIZE := PROJ_BASE + PROJ_MAX * PR_FIELDS

const ARENA_R := 40000000     # µm (muro circular)
## Pilares de la arena (Arena._build_arena: 6 en el anillo de 23,8 m, a 30° + i·60°), en µm. Constantes
## precalculadas para no depender de sin/cos de coma flotante en cada plataforma.
const PILLARS := [11900000, 20611405, 23800000, 0, 11900000, -20611405, -11900000, -20611405, -23800000, 0, -11900000, 20611405]
const PILLAR_BODY_R := 1650000 # Fighter: radio de obstáculo 1,5 + cuerpo 0,45 − 0,3 de margen
const PILLAR_ARROW_R := 1500000 # Projectile: radio de obstáculo 1,5 m
const SEP_FOOT := 1600000     # µm (Fighter.SEPARATION_FOOT)
const STAMINA_ATK_SLOW_PM := 300
const HEAVY_HOLD := 24        # ticks (Fighter.HEAVY_HOLD 0,4 s)
const BLOCK_HOLD := 0         # el bit de escudo ya es "mantener" (el control táctil decide toque/mantener)
const BUFFER_WINDOW := 24     # ticks (PlayerController.BUFFER_WINDOW 0,4 s)
const CHAIN_MIN_RECOVERY := 18
const FINISHER_EXTRA := 18
const ROLL_CANCEL_PM := 500
const CHARGE_MAX := 36        # ticks (0,6 s)
const GC_WINDOW := 21         # 0,35 s
const STANCE_DELAY := 150     # 2,5 s
const STANCE_BREAK_T := 72    # 1,2 s
const CRIT_RANGE := 2600000
const CRIT_TIME := 48
const CRIT_HIT_AT := 27
const STUN_WINDOW := 180      # 3 s
const T_STAGGER := 21
const T_STUN := 54
const T_DOWN := 66
const T_GETUP := 48
const IMMUNE_AFTER := 36
const GETUP_DMG_PM := 850
const SINGLE_HIT_CAP_PM := 950
const THRESH_PM := [1000, 1600, 2400]
const HITSTOP_HEAVY := 5
const HITSTOP_PARRY := 4
const PARRY_EXPOSED_PM := 1250
const RIPOSTE_PM := 1800
const EXH_BLOCK_PM := 600
const CHARGE_BONUS_PM := 400
const STEP_WINDOW_PM := 450
const MAGNET := 1500000
const CONTACT_GAP := 800000
const COUNTER_POISE_PM := 1300
const COUNTER_FORCE_PM := 1300
const BLOCK_REGEN_PM := 500
const HIT_CENTER_Y := 1000000 # µm (Fighter.get_hit_center a pie)
const ARROW_Y0 := 1800000     # centro + 0,8 m
const FAN_COS := 4030         # cos(0,18 rad) ×4096 (abanico de la ballesta)
const FAN_SIN := 733
const HEAL_DELAY := 180       # 3 s sin golpes (pasiva de curación)
const FURIA_HP_PM := 400
# Estados (StatusFx): 0 sangrado, 1 veneno, 2 congelación. Acumulación en milésimas de punto.
const ST_DECAY_DELAY := 90    # tk(1,5 s): sin acumular antes de que baje la barra
const ST_DECAY_MILLI := 10000 # puntos/s ×1000, repartido exacto por ticks
const ST_PROC_LOCK := 90
const POISON_TICKS := 840     # 14 s
const POISON_DPS_MILLI := 2000
const FROST_TICKS := 720      # 12 s
const FROST_TAKEN_PM := 1150
const FROST_REGEN_PM := 600
const BLOCK_STATUS_PM := 300

static func initial(params: Array, seed_v: int = 1, hitstop: bool = true) -> PackedInt64Array:
	var s := PackedInt64Array()
	s.resize(SIZE)
	for i in 2:
		var o := i * F_FIELDS
		var p: Dictionary = params[i]
		s[o + X] = -3000000 if i == 0 else 3000000
		s[o + FACE] = 0 if i == 0 else 128
		s[o + HP] = p["hp"]
		s[o + ST] = p["st_max"]
		s[o + ALIVE] = 1
		s[o + ROLL_T] = -1
		s[o + CRIT_T] = -1
		s[o + ATK_HOLD] = -1
		s[o + STANCE] = p["stance_max"]
		s[o + SINCE_SPEND] = 1000
		s[o + SINCE_HIT] = 1000
		s[o + SN0] = 540; s[o + SN1] = 540; s[o + SN2] = 540
	s[P_BASE + G_RNG] = (seed_v * 2654435761 + 1) & 0x7FFFFFFF
	s[P_BASE + G_HITSTOP_ON] = 1 if hitstop else 0
	return s

static func frame(s: PackedInt64Array) -> int:
	return s[P_BASE + G_FRAME]

## RNG determinista (xorshift32) guardado en el estado; para reglas futuras con azar.
static func rng_next(s: PackedInt64Array) -> int:
	var x: int = s[P_BASE + G_RNG]
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	if x == 0:
		x = 1
	s[P_BASE + G_RNG] = x
	return x

static func checksum(s: PackedInt64Array) -> int:
	var h := 2166136261
	for v in s:
		var x: int = v & 0xFFFFFFFF
		var y: int = (v >> 32) & 0xFFFFFFFF
		h = ((h ^ x) * 16777619) & 0xFFFFFFFF
		h = ((h ^ y) * 16777619) & 0xFFFFFFFF
	return h

# ---------------- Paso ----------------
static func step(s: PackedInt64Array, params: Array, in0: int, in1: int) -> void:
	var g := P_BASE
	if s[g + G_FREEZE] > 0:
		s[g + G_FREEZE] -= 1 # hit-stop: todo congelado (las pulsaciones se conservan como flancos)
		s[g + G_FRAME] += 1
		if s[g + G_END_T] > 0:
			s[g + G_END_T] += 1
		return
	_control(s, params, 0, in0)
	_control(s, params, 1, in1)
	_update(s, params, 0, in0)
	_update(s, params, 1, in1)
	_projectiles(s, params)
	s[g + G_FRAME] += 1
	if s[g + G_END_T] > 0:
		s[g + G_END_T] += 1

# ---------------- Capa de control (PlayerController, determinista) ----------------
static func _control(s: PackedInt64Array, P: Array, i: int, inp: int) -> void:
	var o := i * F_FIELDS
	var prev: int = s[o + PREV_IN]
	var pressed := inp & ~prev
	var released := prev & ~inp
	s[o + PREV_IN] = inp
	# un golpe recibido vacía el búfer de acciones
	if s[o + STUN] > s[o + PREV_STUN]:
		for k in 4:
			s[o + Q0 + k] = 0
	s[o + PREV_STUN] = s[o + STUN]
	if pressed & IN_SWAP:
		_try(s, P, i, Act.SWAP)
	if s[o + LOADOUT] == Load.BOW:
		if pressed & IN_ATK:
			_try(s, P, i, Act.SHOOT)
		s[o + ATK_HOLD] = -1
	elif inp & IN_ATK:
		if s[o + ATK_HOLD] < 0:
			s[o + ATK_HOLD] = 0
			s[o + HEAVY_FIRED] = 0
		else:
			s[o + ATK_HOLD] += 1
		if s[o + ATK_HOLD] >= HEAVY_HOLD and s[o + HEAVY_FIRED] == 0:
			s[o + HEAVY_FIRED] = 1
			_try(s, P, i, Act.HEAVY)
	elif s[o + ATK_HOLD] >= 0:
		if s[o + HEAVY_FIRED] == 0:
			_try(s, P, i, Act.LIGHT)
		s[o + ATK_HOLD] = -1
	if pressed & IN_PARRY:
		_try(s, P, i, Act.PARRY)
	if pressed & IN_ROLL:
		_try(s, P, i, Act.ROLL)
	# búfer: envejece, caduca y reintenta la cabeza
	for k in 4:
		if s[o + Q0 + k] != 0:
			s[o + QA0 + k] += 1
	while s[o + Q0] != 0 and s[o + QA0] > BUFFER_WINDOW:
		_qpop(s, o)
	if s[o + Q0] != 0 and _do(s, P, i, s[o + Q0], true):
		_qpop(s, o)

static func _qpop(s: PackedInt64Array, o: int) -> void:
	for k in 3:
		s[o + Q0 + k] = s[o + Q0 + k + 1]
		s[o + QA0 + k] = s[o + QA0 + k + 1]
	s[o + Q3] = 0
	s[o + QA3] = 0

static func _try(s: PackedInt64Array, P: Array, i: int, a: int) -> void:
	var o := i * F_FIELDS
	if s[o + Q0] == 0 and _do(s, P, i, a, false):
		return
	if P[i].get("buffer", BUFFER_WINDOW) <= 0:
		return # sin búfer de acciones (pruebas de paridad contra la API de Fighter)
	for k in 4:
		if s[o + Q0 + k] == a:
			return
	for k in 4:
		if s[o + Q0 + k] == 0:
			s[o + Q0 + k] = a
			s[o + QA0 + k] = 0
			return

static func _do(s: PackedInt64Array, P: Array, i: int, a: int, retry: bool) -> bool:
	var o := i * F_FIELDS
	match a:
		Act.LIGHT: return _request_attack(s, P, i, false) or s[o + BUFFERED] != 0
		Act.HEAVY: return _request_attack(s, P, i, true)
		Act.PARRY: return _parry(s, P, i)
		Act.SHOOT: return _shoot(s, P, i)
		Act.SWAP: return _swap(s, P, i)
		Act.ROLL:
			if retry and s[o + ATK_STATE] == Atk.WINDUP:
				return false
			return _dash(s, P, i)
	return false

# ---------------- Utilidades ----------------
static func _opp(i: int) -> int:
	return (1 - i) * F_FIELDS

static func _can_act(s: PackedInt64Array, o: int) -> bool:
	return s[o + ALIVE] != 0 and s[o + STUN] <= 0 and s[o + CRIT_T] < 0

static func _spend(s: PackedInt64Array, P: Array, i: int, v: int) -> void:
	var o := i * F_FIELDS
	s[o + ST] = maxi(s[o + ST] - v, 0)
	s[o + SINCE_SPEND] = 0
	if s[o + ST] <= 0 and s[o + EXH] <= 0:
		s[o + EXH] = P[i]["exhaust"]

static func _atk(P: Array, i: int, s: PackedInt64Array) -> Dictionary:
	return P[i]["atk"][s[i * F_FIELDS + ATK_IDX]]

static func _dist_to_opp(s: PackedInt64Array, i: int) -> int:
	var o := i * F_FIELDS
	var b := _opp(i)
	return FxMath.length(s[b + X] - s[o + X], s[b + Z] - s[o + Z])

static func _dir_to_opp(s: PackedInt64Array, i: int) -> int:
	var o := i * F_FIELDS
	var b := _opp(i)
	return FxMath.dir_of(s[b + X] - s[o + X], s[b + Z] - s[o + Z], s[o + FACE])

## ¿b está delante de a? (producto escalar > 0)
static func _in_front(s: PackedInt64Array, a: int, b: int, min_dot: int = 0) -> bool:
	var dx: int = s[b + X] - s[a + X]
	var dz: int = s[b + Z] - s[a + Z]
	var l := FxMath.length(dx, dz)
	if l < 100000:
		return true
	var f: int = s[a + FACE]
	return (dx * FxMath.COS[f] + dz * FxMath.SIN[f]) > min_dot * l

# ---------------- Acciones (Fighter / FighterCombat) ----------------
static func _parry(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * F_FIELDS
	if s[o + LOADOUT] != Load.SWORD or not _can_act(s, o) or s[o + SWAP_T] > 0 or s[o + ROLL_T] >= 0:
		return false
	if s[o + ATK_STATE] != Atk.NONE or s[o + PARRY_STATE] != Parry.NONE or s[o + ST] <= 0:
		return false
	s[o + PARRY_STATE] = Parry.ACTIVE
	s[o + PARRY_T] = 0
	s[o + BLOCKING] = 0
	_spend(s, P, i, P[i]["cost_parry"])
	return true

static func _swap(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * F_FIELDS
	if s[o + ALIVE] == 0 or P[i]["has_bow"] == 0 or s[o + SWAP_T] > 0 or s[o + ATK_STATE] != Atk.NONE or s[o + STUN] > 0:
		return false
	s[o + SWAP_T] = P[i]["swap_t"]
	s[o + BLOCKING] = 0
	return true

static func _crit_candidate(s: PackedInt64Array, i: int) -> bool:
	var b := _opp(i)
	if s[b + STANCE_BROKEN_T] <= 0 or s[b + ALIVE] == 0:
		return false
	if _dist_to_opp(s, i) > CRIT_RANGE:
		return false
	return _in_front(s, b, i * F_FIELDS, 819) # target.facing · d >= 0,2

static func _request_attack(s: PackedInt64Array, P: Array, i: int, heavy: bool) -> bool:
	var o := i * F_FIELDS
	if s[o + BACKSTEP_T] > 0 and s[o + LOADOUT] == Load.SWORD:
		return false # (la estocada tras el paso atrás queda fuera del ruleset reducido)
	if s[o + ROLL_T] >= 0 and s[o + LOADOUT] == Load.SWORD and s[o + ALIVE] != 0 and s[o + ROLL_T] < P[i]["roll_if_end"]:
		s[o + ROLL_ATK_BUF] = 1
		return false
	if s[o + LOADOUT] != Load.SWORD or not _can_act(s, o) or s[o + SWAP_T] > 0 or s[o + PARRY_STATE] != Parry.NONE or s[o + ROLL_T] >= 0:
		return false
	if s[o + ATK_STATE] == Atk.NONE and s[o + ST] > 0:
		if _crit_candidate(s, i):
			_start_crit(s, P, i)
			return true
		if s[o + GC_T] > 0:
			s[o + GC_T] = 0
			s[o + BLOCKING] = 0
			s[o + COMBO] = P[i]["max_combo"]
			_start_attack(s, P, i, SimParams.A_HEAVY, false)
			s[o + ATK_GC] = 1
			var ga: Dictionary = P[i]["atk"][SimParams.A_HEAVY]
			s[o + ATK_DUR] = ga["gc_windup"] if ga.has("gc_windup") else s[o + ATK_DUR] * P[i]["gc_pm"] / 1000
			return true
		if (s[o + PREV_IN] & IN_SPRINT) and not heavy and (s[o + PREV_IN] & IN_MOVE) and not (s[o + PREV_IN] & IN_HALF) and s[o + SPRINT_PM] > 0:
			s[o + DASH_DIR] = ((s[o + PREV_IN] & IN_DIR_MASK) * 8) & 255
			_start_attack(s, P, i, SimParams.A_DASH, false)
			return true
	if s[o + ATK_STATE] != Atk.NONE:
		var a: Dictionary = _atk(P, i, s)
		var in_window: bool = s[o + ATK_STATE] != Atk.RECOVERY or a["window"] < 0 or s[o + ATK_IDX] >= 3 or s[o + ATK_T] <= a["window"]
		if not heavy and s[o + ATK_IDX] < 3 and s[o + COMBO] < P[i]["max_combo"] and in_window and (s[o + ATK_STATE] != Atk.WINDUP or s[o + ATK_T] * 2 > s[o + ATK_DUR]):
			s[o + BUFFERED] = 1
		return false
	if s[o + BLOCKING] != 0 or s[o + ST] <= 0:
		return false
	s[o + COMBO] = 1
	_start_attack(s, P, i, SimParams.A_HEAVY if heavy else 0, false)
	return true

static func _start_attack(s: PackedInt64Array, P: Array, i: int, idx: int, chained: bool) -> void:
	var o := i * F_FIELDS
	if idx < 3:
		idx = clampi(s[o + COMBO] - 1, 0, 2)
	s[o + ATK_IDX] = idx
	s[o + ATK_GC] = 0
	s[o + CHARGE_T] = 0
	var a: Dictionary = P[i]["atk"][idx]
	s[o + STEP_TOTAL] = a["step"]
	s[o + STEP_LEFT] = a["step"]
	s[o + ATK_STATE] = Atk.WINDUP
	s[o + ATK_T] = 0
	s[o + ATK_DUR] = a["windup"]
	s[o + ATK_LANDED] = 0
	s[o + ATK_HIT] = 0
	s[o + BUFFERED] = 0
	_spend(s, P, i, a["stamina"])
	# encararse al rival si está a tiro (fijado: siempre; sin fijar: solo si está delante)
	var b := _opp(i)
	if s[b + ALIVE] != 0 and _dist_to_opp(s, i) < a["reach"] + 1500000:
		var locked := (s[o + PREV_IN] & IN_LOCK) != 0
		if _dist_to_opp(s, i) > 100000 and (locked or _in_front(s, o, b)):
			s[o + FACE] = _dir_to_opp(s, i)

static func _cancel_attack(s: PackedInt64Array, o: int) -> void:
	s[o + ATK_STATE] = Atk.NONE
	s[o + COMBO] = 0
	s[o + BUFFERED] = 0
	s[o + ATK_GC] = 0

static func _start_crit(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * F_FIELDS
	var b := _opp(i)
	s[o + CRIT_T] = 0
	s[o + CRIT_DONE] = 0
	s[o + INVULN] = CRIT_TIME
	s[o + BLOCKING] = 0
	s[o + FACE] = _dir_to_opp(s, i)
	s[b + STANCE_BROKEN_T] = 0
	s[b + STUN] = maxi(s[b + STUN], CRIT_TIME + 18)
	s[b + BLOCKING] = 0
	_spend(s, P, i, P[i]["cost_parry"])

static func _dash(s: PackedInt64Array, P: Array, i: int) -> bool:
	var ok := _dash_now(s, P, i)
	var o := i * F_FIELDS
	if not ok and s[o + ALIVE] != 0:
		s[o + RBUF] = P[i]["roll_buffer"]
	elif ok:
		s[o + RBUF] = 0
	return ok

static func _dash_now(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * F_FIELDS
	# tambaleo corto: rodar lo cancela
	if s[o + STAGGER_T] > 0 and s[o + STUN] <= s[o + STAGGER_T] and s[o + DOWN_T] <= 0:
		s[o + STUN] = 0
		s[o + STAGGER_T] = 0
	if not _can_act(s, o) or s[o + DASH_CD] > 0 or s[o + ST] <= 0 or s[o + PARRY_STATE] != Parry.NONE or s[o + ROLL_T] >= 0:
		return false
	if s[o + ATK_STATE] != Atk.NONE:
		if s[o + ATK_STATE] == Atk.RECOVERY and s[o + ATK_T] * 1000 >= s[o + ATK_DUR] * ROLL_CANCEL_PM:
			_cancel_attack(s, o)
		else:
			return false
	var inp: int = s[o + PREV_IN]
	if not (inp & IN_MOVE):
		s[o + BACKSTEP_T] = P[i]["backstep_t"]
		s[o + DASH_CD] = maxi(P[i]["dash_cd"], P[i]["backstep_t"])
		_spend(s, P, i, P[i]["cost_backstep"])
		return true
	s[o + ROLL_DIR] = ((inp & IN_DIR_MASK) * 8) & 255
	s[o + FACE] = s[o + ROLL_DIR]
	s[o + ROLL_T] = 0
	s[o + DASH_CD] = maxi(P[i]["dash_cd"], P[i]["roll_total"])
	s[o + INVULN] = 0
	_spend(s, P, i, P[i]["cost_roll"])
	return true

static func _shoot(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * F_FIELDS
	if s[o + LOADOUT] != Load.BOW or s[o + SWAP_T] > 0 or s[o + ATK_STATE] != Atk.NONE or s[o + SHOT_STATE] != Shot.NONE:
		return false
	if not _can_act(s, o) or s[o + BOW_CD] > 0 or s[o + ST] <= 0 or s[o + ROLL_T] >= 0:
		return false
	_spend(s, P, i, P[i]["cost_bow"])
	s[o + SHOT_STATE] = Shot.DRAW
	s[o + SHOT_T] = 0
	s[o + SHOT_DUR] = P[i]["bow_draw"]
	return true

static func _apply_stun(s: PackedInt64Array, o: int, t: int) -> void:
	if s[o + STUN_IMM] > 0:
		return
	s[o + STUN] = maxi(s[o + STUN], t)
	if s[o + ATK_STATE] != Atk.NONE:
		_cancel_attack(s, o)

static func _robust_eff(s: PackedInt64Array, P: Array, i: int) -> int:
	var o := i * F_FIELDS
	var r: int = P[i]["robust"]
	var resist := 0
	if s[o + ATK_STATE] == Atk.WINDUP:
		var a: Dictionary = _atk(P, i, s)
		resist = a["resist_pm"]
		if s[o + ATK_IDX] == SimParams.A_HEAVY:
			resist += 1000 * s[o + CHARGE_T] / CHARGE_MAX
	elif s[o + ATK_STATE] == Atk.ACTIVE and s[o + ATK_IDX] == SimParams.A_HEAVY:
		resist = _atk(P, i, s)["resist_pm"] / 2
	return r * (1000 + resist) / 1000

static func _add_stun_force(s: PackedInt64Array, P: Array, i: int, force: int) -> int:
	var o := i * F_FIELDS
	if force <= 0 or s[o + ALIVE] == 0 or s[o + STUN_IMM] > 0 or s[o + INVULN] > 0:
		return 0
	if s[o + STUN_WIN] <= 0:
		s[o + STUN_ACC] = 0
		s[o + STUN_LVL] = 0
		s[o + STUN_WIN] = STUN_WINDOW
	var r := _robust_eff(s, P, i)
	s[o + STUN_ACC] += mini(force, r * SINGLE_HIT_CAP_PM / 1000)
	var ratio: int = s[o + STUN_ACC] * 1000 / maxi(r, 1)
	var lv := 0
	for k in 3:
		if ratio >= THRESH_PM[k]:
			lv = k + 1
	if lv <= s[o + STUN_LVL]:
		return 0
	s[o + STUN_LVL] = lv
	s[o + LAST_LVL] = lv
	match lv:
		1:
			s[o + STAGGERS] += 1
			_apply_stun(s, o, T_STAGGER)
			s[o + STAGGER_T] = T_STAGGER
		2:
			s[o + STUNS] += 1
			s[o + STAGGER_T] = 0
			_apply_stun(s, o, T_STUN)
		3:
			s[o + KNOCKDOWNS] += 1
			s[o + STAGGER_T] = 0
			s[o + BLOCKING] = 0
			_apply_stun(s, o, T_DOWN + T_GETUP)
			s[o + DOWN_T] = T_DOWN + T_GETUP
			s[o + STUN_IMM] = T_DOWN + T_GETUP + IMMUNE_AFTER
			_reset_stun(s, o)
	return lv

static func _reset_stun(s: PackedInt64Array, o: int) -> void:
	s[o + STUN_ACC] = 0
	s[o + STUN_WIN] = 0
	s[o + STUN_LVL] = 0

static func _damage(s: PackedInt64Array, a: int, b: int, amount: int) -> void:
	var dealt := mini(amount, s[b + HP])
	s[b + HP] -= dealt
	s[a + DMG_DEALT] += dealt
	if s[b + HP] <= 0:
		s[b + ALIVE] = 0
		if s[P_BASE + G_END_T] == 0:
			s[P_BASE + G_END_T] = 1
			s[P_BASE + G_WINS0 + a / F_FIELDS] += 1

## take_hit. kind: 0 cuerpo a cuerpo, 1 flecha, 2 crítico. raw = daño bruto (bloqueo), fin = tras defensa.
## Devuelve 0 nada, 1 golpe, 2 bloqueo, 3 parry, 4 esquiva.
## Daño tras la defensa del defensor: tabla horneada de EquipStats.incoming (no lineal) interpolada.
static func _incoming(P: Array, d: int, sub: int, amount: int) -> int:
	var tabs: Array = P[d].get("def_tab", [])
	if tabs.is_empty() or amount <= 0:
		return amount
	var t: PackedInt32Array = tabs[sub]
	var i := amount / 1000
	var r: int
	if i >= t.size() - 1:
		r = t[t.size() - 1]
	else:
		r = t[i] + (t[i + 1] - t[i]) * (amount % 1000) / 1000
	return amount * r / 1000000

## Acumulación de estado en el defensor (Fighter.add_status). k: 0 sangrado, 1 veneno, 2 congelación.
static func _add_status(s: PackedInt64Array, P: Array, att: int, k: int, amount: int) -> void:
	var d := 1 - att
	var b := d * F_FIELDS
	if s[b + ALIVE] == 0 or amount <= 0 or s[b + LK0 + k] > 0:
		return
	s[b + BU0 + k] += amount
	s[b + SN0 + k] = 0
	if s[b + BU0 + k] < int(P[d].get("st_thr", [70000, 70000, 70000])[k]):
		return
	s[b + BU0 + k] = 0
	s[b + LK0 + k] = ST_PROC_LOCK
	s[b + PROC0 + k] += 1
	match k:
		0: _damage(s, att * F_FIELDS, b, P[d].get("bleed_dmg", 18000))
		1: s[b + POISON_T] = POISON_TICKS; s[b + POISON_E] = 0
		2:
			s[b + FROST_T] = FROST_TICKS
			_damage(s, att * F_FIELDS, b, P[d].get("frost_dmg", 12000))

static func _hit_status(s: PackedInt64Array, P: Array, att: int, kind: int, pm_v: int) -> void:
	if kind == 2:
		return
	var st: Array = P[att].get("st_arrow" if kind == 1 else "st_melee", [])
	for k in st.size():
		if int(st[k]) > 0:
			_add_status(s, P, att, k, int(st[k]) * pm_v / 1000)

## Avance de estados por tick (StatusFx.tick): decaimiento, bloqueos, veneno y congelación.
static func _status_tick(s: PackedInt64Array, i: int) -> void:
	var o := i * F_FIELDS
	if s[o + ALIVE] == 0:
		return
	for k in 3:
		s[o + SN0 + k] += 1
		if s[o + LK0 + k] > 0: s[o + LK0 + k] -= 1
		var n: int = s[o + SN0 + k] - ST_DECAY_DELAY - 1
		if n >= 0 and s[o + BU0 + k] > 0:
			s[o + BU0 + k] = maxi(0, s[o + BU0 + k] - ((ST_DECAY_MILLI * (n + 1)) / 60 - (ST_DECAY_MILLI * n) / 60))
	if s[o + FROST_T] > 0: s[o + FROST_T] -= 1
	if s[o + POISON_T] > 0:
		s[o + POISON_T] -= 1
		var e: int = s[o + POISON_E]
		s[o + POISON_E] = e + 1
		_damage(s, (1 - i) * F_FIELDS, o, (POISON_DPS_MILLI * (e + 1)) / 60 - (POISON_DPS_MILLI * e) / 60)

static func _in_pillar(x: int, z: int, r: int) -> bool:
	for k in 6:
		if FxMath.length(x - PILLARS[k * 2], z - PILLARS[k * 2 + 1]) < r:
			return true
	return false

static func _take_hit(s: PackedInt64Array, P: Array, att: int, kind: int, raw: int, sub: int, force: int, pd_pm: int, counter_pm: int, block_cost: int) -> int:
	var d := 1 - att
	var a := att * F_FIELDS
	var b := d * F_FIELDS
	if s[b + ALIVE] == 0:
		return 0
	if s[b + INVULN] > 0:
		return 4
	var rt: int = s[b + ROLL_T]
	if rt >= P[d]["roll_start"] and rt < P[d]["roll_if_end"]:
		s[b + DODGES] += 1
		return 4
	var frontal := _in_front(s, b, a)
	if s[b + PARRY_STATE] == Parry.ACTIVE and frontal and kind != 2:
		if kind == 0:
			_apply_stun(s, a, P[d]["parry_stagger"])
			s[a + RIPOSTE_T] = P[d]["parry_stagger"]
		s[b + PARRIES] += 1
		s[b + PARRY_STATE] = Parry.NONE
		if P[d].get("parry_stamina", 0) > 0:
			s[b + ST] = mini(s[b + ST] + P[d]["parry_stamina"], P[d]["st_max"])
		if s[P_BASE + G_HITSTOP_ON] != 0:
			s[P_BASE + G_FREEZE] = maxi(s[P_BASE + G_FREEZE], HITSTOP_PARRY)
		return 3
	var mult := 1000
	if s[b + PARRY_STATE] == Parry.RECOVERY:
		mult = PARRY_EXPOSED_PM
	if s[b + BLOCKING] != 0 and frontal and kind != 2:
		s[b + BLOCKS] += 1
		if kind == 1:
			_spend(s, P, d, P[att]["arrow_block_cost"])
			_hit_status(s, P, att, kind, BLOCK_STATUS_PM)
		else:
			s[b + GC_T] = GC_WINDOW
			var chip: int = EXH_BLOCK_PM if s[b + EXH] > 0 else P[d]["chip_pm"]
			_damage(s, a, b, raw * mult / 1000 * chip / 1000)
			_hit_status(s, P, att, kind, BLOCK_STATUS_PM)
			_spend(s, P, d, block_cost)
		if s[b + ST] <= 0:
			s[b + GUARD_BREAKS] += 1
			s[b + BLOCKING] = 0
			_apply_stun(s, b, P[d]["guard_break_t"])
		return 2
	if s[b + RIPOSTE_T] > 0 and kind == 0:
		mult = mult * RIPOSTE_PM / 1000
		s[b + RIPOSTE_T] = 0
	var counter := kind != 2 and (s[b + ATK_STATE] == Atk.WINDUP or s[b + ATK_STATE] == Atk.ACTIVE)
	if counter:
		mult = mult * counter_pm / 1000
	var amount := raw * mult / 1000
	var el: int = P[att].get("elem_arrow" if kind == 1 else "elem_melee", 0) if kind != 2 else 0
	if el > 0:
		amount = _incoming(P, d, sub, amount / 2) + _incoming(P, d, el, amount - amount / 2) # infusión: mitad física, mitad elemental
	else:
		amount = _incoming(P, d, sub, amount)
	if s[b + FROST_T] > 0:
		amount = amount * FROST_TAKEN_PM / 1000
	if s[b + STUN_IMM] > 0 and s[b + KNOCKDOWNS] > 0:
		amount = amount * GETUP_DMG_PM / 1000
	_damage(s, a, b, amount)
	_hit_status(s, P, att, kind, 1000)
	s[b + SINCE_HIT] = 0
	var pd := amount * pd_pm / 1000
	if counter:
		pd = pd * COUNTER_POISE_PM / 1000
		force = force * COUNTER_FORCE_PM / 1000
	if kind != 2:
		s[b + STANCE] -= pd
	if s[b + STANCE] <= 0 and s[b + ALIVE] != 0:
		s[b + STANCE] = P[d]["stance_max"]
		s[b + STANCE_BROKEN_T] = STANCE_BREAK_T
		s[b + STANCE_BREAKS] += 1
		s[b + BLOCKING] = 0
		_cancel_attack(s, b)
		_reset_stun(s, b)
		_apply_stun(s, b, STANCE_BREAK_T)
		return 1
	if kind != 2:
		_add_stun_force(s, P, d, force)
	return 1

# ---------------- Actualización del luchador (Fighter._physics_process) ----------------
static func _update(s: PackedInt64Array, P: Array, i: int, inp: int) -> void:
	var o := i * F_FIELDS
	var p: Dictionary = P[i]
	if s[o + RIPOSTE_T] > 0: s[o + RIPOSTE_T] -= 1
	s[o + SINCE_HIT] += 1
	if s[o + STAGGER_T] > 0: s[o + STAGGER_T] -= 1
	if s[o + DOWN_T] > 0: s[o + DOWN_T] -= 1
	if s[o + STUN_IMM] > 0: s[o + STUN_IMM] -= 1
	if s[o + STUN_WIN] > 0:
		s[o + STUN_WIN] -= 1
		if s[o + STUN_WIN] <= 0:
			_reset_stun(s, o)
	_status_tick(s, i)
	if p.get("heal_tick", 0) > 0 and s[o + ALIVE] != 0 and s[o + SINCE_HIT] > HEAL_DELAY and s[o + HP] < p["hp"]:
		s[o + HP] = mini(s[o + HP] + p["heal_tick"], p["hp"])
	if s[o + SWAP_T] > 0:
		s[o + SWAP_T] -= 1
		if s[o + SWAP_T] <= 0:
			s[o + LOADOUT] = Load.BOW if s[o + LOADOUT] == Load.SWORD else Load.SWORD
	_update_attack(s, P, i, inp)
	if s[o + RBUF] > 0:
		s[o + RBUF] -= 1
		if _dash_now(s, P, i):
			s[o + RBUF] = 0
	# parry
	if s[o + PARRY_STATE] != Parry.NONE:
		s[o + PARRY_T] += 1
		if s[o + PARRY_STATE] == Parry.ACTIVE and s[o + PARRY_T] >= p["parry_window"]:
			s[o + PARRY_STATE] = Parry.RECOVERY
			s[o + PARRY_T] = 0
		elif s[o + PARRY_STATE] == Parry.RECOVERY and s[o + PARRY_T] >= p["parry_recovery"]:
			s[o + PARRY_STATE] = Parry.NONE
	if s[o + BOW_CD] > 0: s[o + BOW_CD] -= 1
	_update_shot(s, P, i, inp)
	if s[o + DASH_CD] > 0: s[o + DASH_CD] -= 1
	# intercambio: contra de guardia, postura, crítico
	if s[o + GC_T] > 0: s[o + GC_T] -= 1
	if s[o + STANCE_BROKEN_T] > 0: s[o + STANCE_BROKEN_T] -= 1
	if s[o + SINCE_HIT] > STANCE_DELAY:
		s[o + STANCE] = mini(s[o + STANCE] + p["stance_regen"], p["stance_max"])
	if s[o + CRIT_T] >= 0:
		s[o + CRIT_T] += 1
		if s[o + CRIT_DONE] == 0 and s[o + CRIT_T] >= CRIT_HIT_AT:
			s[o + CRIT_DONE] = 1
			if s[_opp(i) + ALIVE] != 0:
				_take_hit(s, P, i, 2, p["crit_raw"], p["crit_sub"], 0, 0, 1000, 0)
				s[o + CRITS] += 1
				if s[P_BASE + G_HITSTOP_ON] != 0:
					s[P_BASE + G_FREEZE] = maxi(s[P_BASE + G_FREEZE], 7)
		if s[o + CRIT_T] >= CRIT_TIME:
			s[o + CRIT_T] = -1
	if s[o + BACKSTEP_T] > 0: s[o + BACKSTEP_T] -= 1
	if s[o + ROLL_T] >= 0:
		s[o + ROLL_T] += 1
		if s[o + ROLL_ATK_BUF] != 0 and s[o + ROLL_T] >= p["roll_if_end"] and s[o + ALIVE] != 0 and s[o + STUN] <= 0:
			s[o + ROLL_T] = -1
			s[o + ROLL_ATK_BUF] = 0
			s[o + DASH_DIR] = s[o + FACE]
			_start_attack(s, P, i, SimParams.A_DASH, false)
		elif s[o + ROLL_T] >= p["roll_total"] or s[o + ALIVE] == 0:
			s[o + ROLL_T] = -1
			s[o + ROLL_ATK_BUF] = 0
	if s[o + STUN] > 0: s[o + STUN] -= 1
	if s[o + INVULN] > 0: s[o + INVULN] -= 1
	_move(s, P, i, inp)

static func _update_attack(s: PackedInt64Array, P: Array, i: int, inp: int) -> void:
	var o := i * F_FIELDS
	if s[o + ATK_STATE] == Atk.NONE:
		return
	s[o + ATK_T] += 1
	var a: Dictionary = _atk(P, i, s)
	match s[o + ATK_STATE]:
		Atk.WINDUP:
			if s[o + ATK_IDX] == SimParams.A_HEAVY and s[o + ATK_GC] == 0 and (inp & IN_ATK) and s[o + ATK_T] >= s[o + ATK_DUR] and s[o + CHARGE_T] < CHARGE_MAX and s[o + ST] > 0:
				s[o + CHARGE_T] += 1
				s[o + ATK_T] = s[o + ATK_DUR] - 1
				return
			if s[o + ATK_T] >= s[o + ATK_DUR]:
				s[o + ATK_STATE] = Atk.ACTIVE
				s[o + ATK_T] = 0
				s[o + ATK_DUR] = a["active"]
				_strike(s, P, i, a)
		Atk.ACTIVE:
			_strike(s, P, i, a)
			if s[o + ATK_T] >= s[o + ATK_DUR]:
				s[o + ATK_STATE] = Atk.RECOVERY
				s[o + ATK_T] = 0
				s[o + ATK_DUR] = _rec_dur(a, s[o + ATK_LANDED] != 0, s[o + COMBO] >= P[i]["max_combo"])
		Atk.RECOVERY:
			if s[o + BUFFERED] != 0 and s[o + COMBO] < P[i]["max_combo"] and s[o + ATK_T] >= CHAIN_MIN_RECOVERY and s[o + ST] > 0 and s[o + EXH] <= 0 and s[o + STUN] <= 0:
				s[o + COMBO] += 1
				_start_attack(s, P, i, 0, true)
				return
			if s[o + ATK_T] >= s[o + ATK_DUR]:
				_cancel_attack(s, o)

static func _rec_dur(a: Dictionary, landed: bool, finisher: bool) -> int:
	if a.has("rec_hit"):
		if finisher:
			return a["rec_hit_fin"] if landed else a["rec_whiff_fin"]
		return a["rec_hit"] if landed else a["rec_whiff"]
	return a["recovery"] + (0 if landed else a["whiff"]) + (FINISHER_EXTRA if finisher else 0)

static func _strike(s: PackedInt64Array, P: Array, i: int, a: Dictionary) -> void:
	var o := i * F_FIELDS
	var b := _opp(i)
	if s[o + ALIVE] == 0 or s[o + ATK_HIT] != 0 or s[b + ALIVE] == 0:
		return
	# in_sword_arc: d - hr/2 <= alcance y dentro del semiarco
	var dx: int = s[b + X] - s[o + X]
	var dz: int = s[b + Z] - s[o + Z]
	var l := FxMath.length(dx, dz)
	if l - P[1 - i]["hit_radius"] / 2 > a["reach"]:
		return
	if l >= 500000:
		var f: int = s[o + FACE]
		if (dx * FxMath.COS[f] + dz * FxMath.SIN[f]) < a["cos_arc"] * l:
			return
	s[o + ATK_HIT] = 1
	var was_open: bool = s[b + STUN] > 0 or s[b + ATK_STATE] == Atk.RECOVERY
	var heavy := s[o + ATK_IDX] == SimParams.A_HEAVY
	var ck := 1000 + CHARGE_BONUS_PM * s[o + CHARGE_T] / CHARGE_MAX
	var gc_k := 2000 if s[o + ATK_GC] != 0 else 1000
	var force: int = a["force"]
	if heavy:
		force = force * (1000 + 500 * s[o + CHARGE_T] / CHARGE_MAX) / 1000
	var raw: int = a["raw"] * ck / 1000
	if P[i].get("furia_pm", 0) > 0 and s[o + HP] * 1000 < P[i]["hp"] * FURIA_HP_PM:
		raw = raw * (1000 + P[i]["furia_pm"]) / 1000
	var res := _take_hit(s, P, i, 0, raw, a["sub"], force, a["pd_pm"] * ck / 1000 * gc_k / 1000, a["counter_pm"], a["block_cost"])
	if res == 1 or res == 2 or res == 3:
		s[o + ATK_LANDED] = 1
	if res == 1:
		s[o + HITS] += 1
		if (heavy or was_open) and s[P_BASE + G_HITSTOP_ON] != 0:
			s[P_BASE + G_FREEZE] = maxi(s[P_BASE + G_FREEZE], HITSTOP_HEAVY)

static func _update_shot(s: PackedInt64Array, P: Array, i: int, inp: int) -> void:
	var o := i * F_FIELDS
	var p: Dictionary = P[i]
	if s[o + SHOT_STATE] == Shot.NONE:
		return
	if s[o + STUN] > 0 and s[o + SHOT_STATE] == Shot.DRAW:
		s[o + SHOT_STATE] = Shot.NONE
		s[o + BOW_CD] = 12
		return
	s[o + SHOT_T] += 1
	if s[o + SHOT_T] < s[o + SHOT_DUR]:
		s[o + HOLD_T] = 0
		return
	if s[o + SHOT_STATE] == Shot.DRAW and (inp & IN_ATK):
		s[o + HOLD_T] += 1
		return
	s[o + SHOT_T] = 0
	match s[o + SHOT_STATE]:
		Shot.DRAW:
			var ch: bool = s[o + HOLD_T] >= p["bow_hold"]
			s[o + SHOT_CHARGED] = 1 if ch else 0
			s[o + HOLD_T] = 0
			_release(s, P, i, ch)
			s[o + SHOT_STATE] = Shot.RECOVER
			s[o + SHOT_DUR] = p["bow_recovery_ch"] if ch else p["bow_recovery"]
		Shot.RECOVER:
			if p["bow_reload"] > 0:
				s[o + SHOT_STATE] = Shot.RELOAD
				s[o + SHOT_DUR] = p["bow_reload"]
			else:
				s[o + SHOT_STATE] = Shot.NONE
				s[o + BOW_CD] = p["bow_cd"]
		Shot.RELOAD:
			s[o + SHOT_STATE] = Shot.NONE
			s[o + BOW_CD] = p["bow_cd"]

static func _release(s: PackedInt64Array, P: Array, i: int, charged: bool) -> void:
	var o := i * F_FIELDS
	var b := _opp(i)
	var p: Dictionary = P[i]
	var f: int = s[o + FACE]
	var ox: int = s[o + X] + FxMath.COS[f] * 1400000 / FxMath.ONE
	var oz: int = s[o + Z] + FxMath.SIN[f] * 1400000 / FxMath.ONE
	var spd: int = p["arrow_speed_ch"] if charged else p["arrow_speed"]
	# dirección 3D: hacia el centro del rival (con adelanto) si no está detrás; si no, al frente
	var dx: int = FxMath.COS[f]
	var dz: int = FxMath.SIN[f]
	var dy := 0
	var unit := FxMath.ONE
	var tx: int = s[b + X] - ox
	var tz: int = s[b + Z] - oz
	var ty := HIT_CENTER_Y - ARROW_Y0
	var hl := FxMath.length(tx, tz)
	if s[b + ALIVE] != 0 and (hl == 0 or (tx * FxMath.COS[f] + tz * FxMath.SIN[f]) > -819 * hl):
		var l3 := FxMath.isqrt(tx * tx + tz * tz + ty * ty)
		var lead: int = p.get("aim_lead_pm", 0)
		if lead > 0 and spd > 0:
			tx += s[b + VX] * l3 / spd * lead / 1000
			tz += s[b + VZ] * l3 / spd * lead / 1000
		var l := maxi(FxMath.isqrt(tx * tx + tz * tz + ty * ty), 1)
		dx = tx; dz = tz; dy = ty; unit = l
	var n: int = p["arrow_n_ch"] if charged else 1
	s[o + SHOTS] += n
	for k in n:
		var slot := -1
		for j in PROJ_MAX:
			if s[PROJ_BASE + j * PR_FIELDS + PR_ON] == 0:
				slot = j
				break
		if slot < 0:
			return # piscina llena: el disparo se pierde (8 flechas vivas como máximo)
		var rx := dx
		var rz := dz
		if n > 1 and k != 1: # abanico: gira ±0,18 rad alrededor del eje vertical
			var sg := k - 1
			rx = (dx * FAN_COS - sg * dz * FAN_SIN) / FxMath.ONE
			rz = (sg * dx * FAN_SIN + dz * FAN_COS) / FxMath.ONE
		var q := PROJ_BASE + slot * PR_FIELDS
		s[q + PR_ON] = 1
		s[q + PR_OWNER] = i
		s[q + PR_X] = ox
		s[q + PR_Z] = oz
		s[q + PR_Y] = ARROW_Y0
		s[q + PR_VX] = rx * spd / unit
		s[q + PR_VZ] = rz * spd / unit
		s[q + PR_VY] = dy * spd / unit
		s[q + PR_LIFE] = p["arrow_life"]
		s[q + PR_RAW] = p["arrow_raw_ch"] if charged and p.has("arrow_raw_ch") else p["arrow_raw"]
		s[q + PR_FORCE] = p["arrow_force_ch"] if charged else p["arrow_force"]
		s[q + PR_DODGED] = 0

static func _projectiles(s: PackedInt64Array, P: Array) -> void:
	for j in PROJ_MAX:
		var q := PROJ_BASE + j * PR_FIELDS
		if s[q + PR_ON] == 0:
			continue
		s[q + PR_X] += s[q + PR_VX]
		s[q + PR_Z] += s[q + PR_VZ]
		s[q + PR_Y] += s[q + PR_VY]
		s[q + PR_LIFE] -= 1
		if s[q + PR_LIFE] <= 0 or FxMath.length(s[q + PR_X], s[q + PR_Z]) > ARENA_R + 2000000 or s[q + PR_Y] < -1000000:
			s[q + PR_ON] = 0
			continue
		if P[0].get("pillars", 0) != 0 and _in_pillar(s[q + PR_X], s[q + PR_Z], PILLAR_ARROW_R):
			s[q + PR_ON] = 0
			continue
		if s[q + PR_DODGED] != 0:
			continue
		var owner: int = s[q + PR_OWNER]
		var b := _opp(owner)
		if s[b + ALIVE] == 0:
			continue
		var ex: int = s[q + PR_X] - s[b + X]
		var ez: int = s[q + PR_Z] - s[b + Z]
		var ey: int = s[q + PR_Y] - HIT_CENTER_Y
		var r: int = P[owner]["arrow_radius"] + P[1 - owner]["hit_radius"]
		if ex * ex + ez * ez + ey * ey < r * r:
			var res := _take_hit(s, P, owner, 1, s[q + PR_RAW], 0, s[q + PR_FORCE], 2000, P[owner]["counter_arrow_pm"], 0)
			if res == 4:
				s[q + PR_DODGED] = 1
				continue
			if res == 3: # reflejo: invierte la dirección y cambia de bando
				s[q + PR_VX] = -s[q + PR_VX]
				s[q + PR_VZ] = -s[q + PR_VZ]
				s[q + PR_VY] = -s[q + PR_VY]
				s[q + PR_OWNER] = 1 - owner
				s[q + PR_LIFE] = P[owner].get("arrow_reflect_life", 120)
				continue
			s[q + PR_ON] = 0 # (hits_landed offline solo cuenta cuerpo a cuerpo)

static func _move(s: PackedInt64Array, P: Array, i: int, inp: int) -> void:
	var o := i * F_FIELDS
	var p: Dictionary = P[i]
	var b := _opp(i)
	var moving := (inp & IN_MOVE) != 0
	if s[o + ALIVE] == 0 or s[o + STUN] > 0 or s[o + CRIT_T] >= 0:
		moving = false
	var want_block: bool = (inp & IN_BLOCK) != 0 # sin escudo el control local no envía IN_BLOCK
	var wb: bool = want_block and s[o + ALIVE] != 0 and s[o + STUN] <= 0 and s[o + ROLL_T] < 0 and s[o + BACKSTEP_T] <= 0 and s[o + LOADOUT] == Load.SWORD and s[o + SWAP_T] <= 0 and s[o + ATK_STATE] == Atk.NONE and s[o + PARRY_STATE] == Parry.NONE
	s[o + BLOCKING] = 1 if wb else 0
	if wb:
		_spend(s, P, i, p["drain_block"])
	var amount_pm := 0
	if moving:
		amount_pm = 500 if (inp & IN_HALF) else 1000
	var mdir := ((inp & IN_DIR_MASK) * 8) & 255
	var tvx := 0
	var tvz := 0
	var locked := (inp & IN_LOCK) != 0 and s[b + ALIVE] != 0
	var turning_locked: bool = s[o + ATK_STATE] == Atk.ACTIVE or s[o + ATK_STATE] == Atk.RECOVERY
	var turn: int = 0 if turning_locked else p["turn"]
	var sprint_req: bool = (inp & IN_SPRINT) != 0 and amount_pm > 300 and s[o + EXH] <= 0 and not wb and s[o + ST] > 0 and s[o + SHOT_STATE] == Shot.NONE
	var spd: int = p["speed"]
	if locked:
		s[o + FACE] = FxMath.turn_toward(s[o + FACE], _dir_to_opp(s, i), turn * 18 / 10)
		if amount_pm > 0:
			var fdot: int = (FxMath.COS[mdir] * FxMath.COS[s[o + FACE]] + FxMath.SIN[mdir] * FxMath.SIN[s[o + FACE]]) / FxMath.ONE # ×4096
			var k: int
			if sprint_req:
				k = (3686 + (410 * fdot) / FxMath.ONE) if fdot >= 0 else (3686 - (3686 - 3277) * (-fdot) / FxMath.ONE)
			else:
				k = (3277 + (819 * fdot) / FxMath.ONE) if fdot >= 0 else (3277 - (3277 - 2048) * (-fdot) / FxMath.ONE)
			var v := spd * amount_pm / 1000 * k / FxMath.ONE
			tvx = FxMath.COS[mdir] * v / FxMath.ONE
			tvz = FxMath.SIN[mdir] * v / FxMath.ONE
	elif amount_pm > 0:
		s[o + FACE] = FxMath.turn_toward(s[o + FACE], mdir, turn)
		var v2 := spd * amount_pm / 1000
		tvx = FxMath.COS[s[o + FACE]] * v2 / FxMath.ONE
		tvz = FxMath.SIN[s[o + FACE]] * v2 / FxMath.ONE
	# carrera (rampa lineal en lugar de la suavizado exponencial)
	var sp_pm: int = s[o + SPRINT_PM]
	sp_pm = mini(sp_pm + 120, 1000) if sprint_req else maxi(sp_pm - 60, 0)
	s[o + SPRINT_PM] = sp_pm
	var mul: int = 1000 + (p["sprint_pm"] - 1000) * sp_pm / 1000
	if sprint_req:
		_spend(s, P, i, p["drain_sprint"])
	if wb: mul = mul * 450 / 1000
	if s[o + EXH] > 0: mul = mul * 600 / 1000
	if s[o + ATK_STATE] != Atk.NONE: mul = mul * STAMINA_ATK_SLOW_PM / 1000
	if s[o + SHOT_STATE] == Shot.DRAW:
		mul = 0
		s[o + VX] = 0
		s[o + VZ] = 0
	elif s[o + SHOT_STATE] == Shot.RECOVER:
		mul = mul * p["bow_slow_pm"] / 1000
	tvx = tvx * mul / 1000
	tvz = tvz * mul / 1000
	# aguante
	s[o + SINCE_SPEND] += 1
	if s[o + EXH] > 0: s[o + EXH] -= 1
	if s[o + SINCE_SPEND] >= p["regen_delay"] and s[o + ST] < p["st_max"]:
		var rg: int = p["regen_idle"] if amount_pm < 300 else p["regen"]
		if wb: rg = rg * BLOCK_REGEN_PM / 1000
		if s[o + FROST_T] > 0: rg = rg * FROST_REGEN_PM / 1000
		s[o + ST] = mini(s[o + ST] + rg, p["st_max"])
	# aceleración (move_toward)
	if s[o + ROLL_T] < 0:
		var acc: int = p["acc"]
		var cur := FxMath.length(s[o + VX], s[o + VZ])
		if FxMath.length(tvx, tvz) < cur - 1666:
			acc = p["brake"]
		elif sp_pm > 0:
			acc = p["acc_sprint"]
		var dvx: int = tvx - s[o + VX]
		var dvz: int = tvz - s[o + VZ]
		var dl := FxMath.length(dvx, dvz)
		if dl <= acc:
			s[o + VX] = tvx
			s[o + VZ] = tvz
		else:
			s[o + VX] += dvx * acc / dl
			s[o + VZ] += dvz * acc / dl
	var vx: int = s[o + VX]
	var vz: int = s[o + VZ]
	var a_idx: int = s[o + ATK_IDX]
	var atk_st: int = s[o + ATK_STATE]
	if a_idx == SimParams.A_DASH and (atk_st == Atk.WINDUP or atk_st == Atk.ACTIVE):
		var lv: int = p["atk"][SimParams.A_DASH]["lunge"]
		vx = FxMath.COS[s[o + DASH_DIR]] * lv / FxMath.ONE
		vz = FxMath.SIN[s[o + DASH_DIR]] * lv / FxMath.ONE
		s[o + VX] = vx / 2
		s[o + VZ] = vz / 2
	elif s[o + STEP_LEFT] > 0 and (atk_st == Atk.WINDUP or atk_st == Atk.ACTIVE) and a_idx != SimParams.A_DASH:
		var st_v := _step(s, P, i)
		vx = st_v.x
		vz = st_v.y
		if st_v != Vector2i.ZERO:
			s[o + VX] = 0
			s[o + VZ] = 0
	elif s[o + BACKSTEP_T] > 0:
		var bf := (s[o + FACE] + 128) & 255
		vx = FxMath.COS[bf] * p["backstep_v"] / FxMath.ONE
		vz = FxMath.SIN[bf] * p["backstep_v"] / FxMath.ONE
		s[o + VX] = vx
		s[o + VZ] = vz
	elif s[o + ROLL_T] >= 0:
		var rt: int = s[o + ROLL_T]
		var fast: int = p["roll_fast"]
		var rv: int
		if rt <= fast:
			rv = p["roll_dist"] / fast
		else:
			var rec: int = maxi(p["roll_total"] - fast, 1)
			rv = maxi(2 * p["roll_drift"] * (rec - (rt - fast)) / (rec * rec), 0)
		vx = FxMath.COS[s[o + ROLL_DIR]] * rv / FxMath.ONE
		vz = FxMath.SIN[s[o + ROLL_DIR]] * rv / FxMath.ONE
	# separación blanda (v += dir * (min - d) * 8 por segundo)
	var sx: int = s[o + X] - s[b + X]
	var sz: int = s[o + Z] - s[b + Z]
	var sl := FxMath.length(sx, sz)
	if sl < SEP_FOOT:
		var push := (SEP_FOOT - sl) * 8 / 60
		if sl > 10000:
			vx += sx * push / sl
			vz += sz * push / sl
		else:
			var pf := (s[o + FACE] + 64) & 255
			vx += FxMath.COS[pf] * push / FxMath.ONE
			vz += FxMath.SIN[pf] * push / FxMath.ONE
	s[o + X] += vx
	s[o + Z] += vz
	var r := FxMath.length(s[o + X], s[o + Z])
	var lim := ARENA_R - 450000
	if r > lim:
		s[o + X] = s[o + X] * lim / r
		s[o + Z] = s[o + Z] * lim / r
	if P[i].get("pillars", 0) != 0:
		for k in 6:
			var dx: int = s[o + X] - PILLARS[k * 2]
			var dz: int = s[o + Z] - PILLARS[k * 2 + 1]
			var dl := FxMath.length(dx, dz)
			if dl < PILLAR_BODY_R:
				if dl < 1000:
					var pf := s[o + FACE]
					dx = FxMath.COS[pf]; dz = FxMath.SIN[pf]; dl = FxMath.ONE
				s[o + X] = PILLARS[k * 2] + dx * PILLAR_BODY_R / dl
				s[o + Z] = PILLARS[k * 2 + 1] + dz * PILLAR_BODY_R / dl

## Paso adelante del ataque: reparte step_total de forma lineal en la ventana (último 45 % de la
## anticipación + golpe), imantado al rival y sin atravesarlo (se detiene a hit_radius + 0,8 m).
static func _step(s: PackedInt64Array, P: Array, i: int) -> Vector2i:
	var o := i * F_FIELDS
	var b := _opp(i)
	var a: Dictionary = _atk(P, i, s)
	var st: int = s[o + ATK_STATE]
	var dur: int = s[o + ATK_DUR]
	var in_win := st == Atk.ACTIVE or (st == Atk.WINDUP and s[o + ATK_T] * 1000 >= dur * (1000 - STEP_WINDOW_PM))
	if not in_win:
		return Vector2i.ZERO
	if st == Atk.WINDUP and s[o + ATK_IDX] == SimParams.A_HEAVY and s[o + CHARGE_T] > 0:
		return Vector2i.ZERO
	var win: int = maxi(a["windup"] * STEP_WINDOW_PM / 1000 + a["active"], 3)
	var total: int = s[o + STEP_TOTAL]
	var mv := mini(total / win + 1, s[o + STEP_LEFT])
	if st == Atk.ACTIVE and s[o + ATK_T] + 1 >= dur:
		mv = s[o + STEP_LEFT]
	var dir: int = s[o + FACE]
	if s[b + ALIVE] != 0:
		var dl := _dist_to_opp(s, i)
		if dl < total + a["reach"] + MAGNET and dl > 100000 and _in_front(s, o, b, 1229):
			dir = _dir_to_opp(s, i)
			s[o + FACE] = dir
			var contact: int = dl - (P[1 - i]["hit_radius"] + CONTACT_GAP)
			mv = mini(mv, maxi(contact, 0))
	s[o + STEP_LEFT] = maxi(s[o + STEP_LEFT] - mv, 0) if mv > 0 else 0
	if mv <= 0:
		return Vector2i.ZERO
	return Vector2i(FxMath.COS[dir] * mv / FxMath.ONE, FxMath.SIN[dir] * mv / FxMath.ONE)
