class_name SimAI
extends RefCounted
## IA del rival sobre la sim determinista: cada tick lee el estado de FightSim y devuelve los bits de
## entrada del jugador `me` (como un mando). Es el port de AIController (mismas fases, perfiles de
## dificultad AIDifficulty y estilo de campeón). Toda su memoria vive aquí y su azar es un xorshift
## sembrado con la semilla de la partida: dada la misma secuencia de estados emite la misma entrada.
## No forma parte del netcode (online no hay IA), por eso puede decidir con float.

enum Phase { CIRCLE, COMMIT, RETREAT, REST, BREATHE }
const S := preload("res://net/sim/fight_sim.gd")
const DT := 1.0 / 60.0
const MAX_ORBIT := 1.15
const ARENA_LIMIT := 36.0 ## Arena.RADIUS − 4
const BOSS_DIST := 8.0 ## Fighter.BOSS_DIST
const BOSS_REACH := 2.2
const BOSS_SPEED := 26.0

var me := 1
var enabled := true
var profile: AIDifficulty = preload("res://resources/ai/easy.tres")
var champion_style: Dictionary = {}
var champion_phase_two := false
var rng: int = 0x2545F491
var phase: Phase = Phase.CIRCLE
var _phase_t := 2.0
var _orbit := 0.0
var _orbit_dir := 1.0
var _pref_dist := 7.5
var _swings := 0
var _dash_in := false
var _think := 0.0
var _block_hold := 0.0
var _since_breather := 0.0
var _breathe_wait := 0.0
var _breathe_orbit := 0.3
var _flee := false
var _react_t := -1.0
var _react_r := -1.0
var _reacted_id := -1
var _punish_t := 0.0
var _backstep_t := 0.0
var _started := false
var _crit_roll := -1.0
var _gc_roll := -1.0
var _delay_t := -1.0
var _boss_plan := -1
var _boss_dodge := false
var _boss_err := 0.0
var _boss_done := false
var _jump_err := 0.0
var _aoe_done := {}
var _rolled := {}
# lectura de flancos del rival (contadores que Fighter llevaba y la sim no)
var _opp_atk_starts := 0
var _opp_prev_atk := 0
var _opp_boss_uses := 0
var _opp_prev_bs := 0
# pruebas / estadística (mismos nombres que AIController)
var rest_time := 0.0
var breathers := 0
var breathe_time := 0.0
var dodges := 0
var parries_tried := 0
var aoe_jumps := 0
var aoe_seen := 0
var crits_tried := 0
var guard_counters_tried := 0
var delayed_attacks := 0
var boss_dodges := 0
var boss_used := 0
var ab_flee_frames := 0
var boss_by_id := {}
var slash_rolls := 0
var jump_dodges := 0
# salida de este tick
var _s: PackedInt64Array
var _P: Array
var _o := 0
var _q := 0
var _move := Vector3.ZERO
var _block := false
var _sprint := false
var _lock := true
var _taps := 0
var _pending := 0
var _prev_out := 0
var _atk_hold := 0 ## ticks que quedan manteniendo ataque (fuerte)
var _boss_want := -1
var _boss_want_t := 0

func _init(slot: int = 1, prof: AIDifficulty = null, seed_v: int = 1) -> void:
	me = slot
	if prof:
		profile = prof
	seed_rng(seed_v)

func seed_rng(v: int) -> void:
	rng = (v * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF
	if rng == 0:
		rng = 0x2545F491

func configure_champion(champion: Dictionary) -> void:
	champion_style = (champion.get("style", {}) as Dictionary).duplicate()
	_pref_dist = float(champion_style.get("distance", 7.5))

func enter_champion_phase_two() -> void:
	champion_phase_two = true
	phase = Phase.COMMIT
	_phase_t = 3.0 * float(champion_style.get("phase2", 1.0))
	_started = false
	_swings = 2
	_dash_in = true

func reset_round() -> void:
	champion_phase_two = false
	phase = Phase.CIRCLE
	_phase_t = 2.0
	_aoe_done.clear(); _rolled.clear()
	_pending = 0; _atk_hold = 0; _boss_want = -1; _prev_out = 0
	_react_r = -1.0; _punish_t = 0.0; _backstep_t = 0.0; _block_hold = 0.0

# ---------------- azar determinista ----------------
func randf_() -> float:
	var x := rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	rng = x & 0xFFFFFFFF
	return float(rng) / 4294967296.0
func rr(a: float, b: float) -> float:
	return a + (b - a) * randf_()
func ri(n: int) -> int:
	return int(randf_() * n) % maxi(n, 1)

# ---------------- lectura del estado ----------------
func g(f: int) -> int: return _s[_o + f]
func og(f: int) -> int: return _s[_q + f]
func pos(o: int) -> Vector3: return Vector3(_s[o + S.X] / 1.0e6, 0, _s[o + S.Z] / 1.0e6)
static func head_vec(h: int) -> Vector3:
	var a := float(h & 255) / 256.0 * TAU
	return Vector3(cos(a), 0, sin(a))
func facing() -> Vector3: return head_vec(g(S.FACE))
func opp_facing() -> Vector3: return head_vec(og(S.FACE))
func stamina() -> float: return g(S.ST) / 1000.0
func health() -> float: return g(S.HP) / 1000.0
func max_health() -> float: return int(_P[me]["hp"]) / 1000.0
func mounted() -> bool: return g(S.MOUNTED) != 0
func sword_mode() -> bool: return g(S.LOADOUT) == S.Load.SWORD
func idle_atk() -> bool: return g(S.ATK_STATE) == S.Atk.NONE
func reach_of(o_i: int) -> float:
	var r := int(_P[o_i]["atk"][0]["reach"]) / 1.0e6
	if _s[o_i * S.F_FIELDS + S.MOUNTED] != 0:
		r *= int(_P[o_i].get("m_reach_pm", 1000)) / 1000.0
	return r
func can_act() -> bool: return S._can_act(_s, _o)
func boss_list(o_i: int) -> Array: return _P[o_i].get("boss", [])
func ab_cur(o: int, o_i: int) -> Dictionary:
	var k: int = _s[o + S.AB_SLOT]
	var b := boss_list(o_i)
	return b[k] if k >= 0 and k < b.size() else {}

# ---------------- botones ----------------
func tap(bit: int) -> void: _taps |= bit
func dash() -> bool:
	if g(S.DASH_CD) > 0 or g(S.ST) <= 0 or not can_act() or g(S.ROLL_T) >= 0:
		return false
	tap(S.IN_ROLL)
	return true
func jump() -> bool:
	if not can_act() or g(S.AIR) != 0 or mounted() and int(_P[me].get("m_jump", 0)) == 0:
		return false
	tap(S.IN_JUMP)
	return true
func parry() -> bool:
	if mounted() or not sword_mode() or not can_act() or g(S.PARRY_STATE) != S.Parry.NONE:
		return false
	tap(S.IN_PARRY)
	return true
func attack_light() -> bool:
	if not sword_mode() or not can_act() or _atk_hold > 0:
		return false
	tap(S.IN_ATK)
	return true
func attack_heavy() -> bool:
	if not sword_mode() or not can_act() or _atk_hold > 0 or g(S.ST) <= 0:
		return false
	_atk_hold = S.HEAVY_HOLD + 2
	return true
func shoot() -> bool:
	if sword_mode() or g(S.SHOT_STATE) != S.Shot.NONE or g(S.BOW_CD) > 0 or not can_act():
		return false
	tap(S.IN_ATK)
	return true
func swap_loadout() -> bool:
	if g(S.SWAP_T) > 0 or not can_act():
		return false
	tap(S.IN_SWAP)
	return true
func summon() -> bool:
	if g(S.METER) < S.METER_MAX or g(S.EK_T) > 0 or (_P[me].get("ek", {}) as Dictionary).is_empty():
		return false
	tap(S.IN_EIKON)
	return true
func can_cast() -> bool:
	var sp: Array = _P[me].get("spells", [])
	var k := g(S.SP_SEL)
	if k < 0 or k >= sp.size() or (sp[k] as Dictionary).is_empty():
		return false
	return can_act() and not mounted() and g(S.SCD0 + k) <= 0 and g(S.MANA) >= int(sp[k]["cost"]) and idle_atk()
func current_spell() -> Dictionary:
	var sp: Array = _P[me].get("spells", [])
	var k := g(S.SP_SEL)
	return sp[k] if k >= 0 and k < sp.size() else {}
func boss_skill(id: String) -> bool:
	var b := boss_list(me)
	for k in b.size():
		if String(b[k].get("id", "")) == id:
			if not SimAbilities.can_use(_s, _P, me, k):
				return false
			_boss_want = k
			_boss_want_t = 12
			return true
	return false

## Paso: estado → bits de entrada de este tick.
func think(s: PackedInt64Array, P: Array) -> int:
	_s = s; _P = P
	_o = me * S.F_FIELDS
	_q = (1 - me) * S.F_FIELDS
	_taps = _pending
	_pending = 0
	_block = false
	_sprint = false
	_lock = true
	if og(S.ATK_STATE) == S.Atk.WINDUP and _opp_prev_atk != S.Atk.WINDUP:
		_opp_atk_starts += 1
	_opp_prev_atk = og(S.ATK_STATE)
	if og(S.BS_PH) != 0 and _opp_prev_bs == 0:
		_opp_boss_uses += 1
	_opp_prev_bs = og(S.BS_PH)
	if not enabled or g(S.ALIVE) == 0 or og(S.ALIVE) == 0:
		_move = Vector3.ZERO
		_atk_hold = 0
		_boss_want = -1
		return _emit()
	_decide()
	return _emit()

func _emit() -> int:
	if _boss_want >= 0:
		_boss_want_t -= 1
		if g(S.AB_SEL) != _boss_want:
			tap(S.IN_BOSS_NEXT)
		else:
			tap(S.IN_BOSS)
			_boss_want = -1
		if _boss_want_t <= 0:
			_boss_want = -1
	var held := 0
	if _atk_hold > 0:
		_atk_hold -= 1
		if _atk_hold > 0:
			held |= S.IN_ATK
	# flancos: un botón pulsado el tick anterior se suelta ahora y se repite en el siguiente
	var t := _taps
	var again := t & _prev_out & ~S.IN_ATK
	if (t & S.IN_ATK) and (_prev_out & S.IN_ATK):
		again |= S.IN_ATK
	_pending = again
	t &= ~again
	var spd := _move.length()
	var v := SimView.pack_input(_move, spd < 0.6 and spd > 0.2, ((t | held) & S.IN_ATK) != 0, _block, false, false, _sprint, false, _lock)
	v |= t & ~S.IN_ATK
	v |= held
	_prev_out = v
	return v

func _decide() -> void:
	_catalog_alt()
	var mp := pos(_o)
	var op := pos(_q)
	var to := op - mp
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else facing()
	var side := dir.cross(Vector3.UP) * _orbit_dir
	var opp_i := 1 - me
	_phase_t -= DT
	_since_breather += DT
	if _avoid_aoe(mp):
		return
	# Normal y Difícil castigan el frasco (estocada o proyectil durante la animación)
	if og(S.FLASK_T) > 0 and profile.profile_name != "easy" and not mounted():
		if sword_mode() and dist > 3.0 and dist < BOSS_DIST + 1.0 and boss_skill("estocada"):
			boss_used += 1
			return
		if not sword_mode() and shoot():
			return
	# A pie: volver a montar su eikon
	var ek: Dictionary = _P[me].get("ek", {})
	if not mounted() and not ek.is_empty() and int(ek.get("ride", 0)) != 0 and g(S.EK_T) > 0:
		var mpos := Vector3(g(S.EK_X) / 1.0e6, 0, g(S.EK_Z) / 1.0e6)
		var md := mp.distance_to(mpos)
		if md <= SimMagic.MOUNT_REACH / 1.0e6 - 0.3:
			tap(S.IN_EIKON)
			return
		if dist > 6.0 or md < 6.0 or og(S.EXH) > 0:
			_lock = false
			_sprint = stamina() > 40.0
			_move = (mpos - mp).normalized()
			return
	var sm := sword_mode()
	var reach := reach_of(me)
	# Estocada de jefe del rival
	if og(S.BS_PH) == 1 or og(S.BS_PH) == 2:
		if _boss_plan != _opp_boss_uses:
			_boss_plan = _opp_boss_uses
			_boss_dodge = randf_() < profile.boss_dodge_chance
			_boss_err = rr(-profile.boss_dodge_err, profile.boss_dodge_err)
			_boss_done = false
		var ab := ab_cur(_q, opp_i)
		var left := 0.0
		if og(S.BS_PH) == 1:
			left = maxf(int(ab.get("charge", 0)) - og(S.BS_T), 0) * DT
		var eta := left + maxf(dist - BOSS_REACH, 0.0) / BOSS_SPEED
		if _boss_dodge and not _boss_done and dist < BOSS_DIST + 3.0 and eta <= 0.22 + _boss_err:
			var side_d := head_vec(og(S.BS_DIR)).cross(Vector3.UP)
			if side_d.dot(mp - op) < 0.0:
				side_d = -side_d
			_move = side_d
			if dash():
				_boss_done = true
				boss_dodges += 1
				_punish_t = 2.5
			return
		_move = Vector3.ZERO if dist < 9.0 else dir * 0.4
		if idle_atk():
			return
	if _roll_slash(mp):
		return
	var oab := ab_cur(_q, opp_i)
	var otype := int(oab.get("family", oab.get("type", -1)))
	# salto con caída: alejarse; rodar al aterrizar
	if otype == SimAbilities.T_SALTO and og(S.AB_AIR) != 0:
		var land_in := (int(oab["land"]) - og(S.AB_T)) * DT
		if og(S.AB_FL) & SimAbilities.FL_LOCKED:
			var away2 := mp - op
			var fl := away2.normalized() if away2.length() > 0.2 else side
			if land_in <= 0.22 + _jump_err:
				_move = (fl + side * 0.5).normalized()
				if dash():
					jump_dodges += 1
			else:
				_sprint = true
				_move = (side + fl * 0.3).normalized()
			return
		_jump_err = rr(-0.06, 0.06)
	# huir de la carga en área
	if otype == SimAbilities.T_CARGA:
		var away := mp - op
		if away.length() < int(oab["r"]) / 1.0e6 + 1.5:
			ab_flee_frames += 1
			_sprint = true
			_move = away.normalized() if away.length() > 0.2 else side
			return
	# crítico frontal si el rival tiene la postura rota
	if og(S.STANCE_BROKEN_T) <= 0:
		_crit_roll = -1.0
	elif sm and not mounted() and og(S.MOUNTED) == 0 and dist < 7.0:
		if _crit_roll < 0.0:
			_crit_roll = randf_()
		if _crit_roll < profile.crit_chance:
			var spot := op + opp_facing() * 1.4
			var to_spot := spot - mp
			_move = to_spot.normalized() if to_spot.length() > 0.4 else Vector3.ZERO
			if dist < S.CRIT_RANGE / 1.0e6 and facing().dot(dir) > 0.5 and idle_atk():
				if attack_light():
					crits_tried += 1
			return
	# contra de guardia tras bloquear
	if g(S.GC_T) <= 0:
		_gc_roll = -1.0
	elif sm and not mounted() and dist < reach + 0.6:
		if _gc_roll < 0.0:
			_gc_roll = randf_()
			if _gc_roll < profile.guard_counter_chance:
				_block_hold = 0.0
				if attack_heavy():
					guard_counters_tried += 1
				return
	# postura baja: deja de presionar
	if phase == Phase.COMMIT and g(S.STANCE) < profile.stance_caution * int(_P[me]["stance_max"]) and idle_atk():
		phase = Phase.RETREAT
		_phase_t = 1.0
	# leer el ataque telegrafiado del rival
	if og(S.ATK_STATE) == S.Atk.WINDUP and _opp_atk_starts != _reacted_id \
			and dist < reach_of(opp_i) + 2.5 and (og(S.ATK_DUR) - og(S.ATK_T)) * DT < 0.3:
		_reacted_id = _opp_atk_starts
		_react_t = profile.reaction_time
		_react_r = randf_()
	if _react_t >= 0.0:
		_react_t -= DT
	if _react_t < 0.0 and _react_r >= 0.0 and og(S.ATK_STATE) == S.Atk.WINDUP and _opp_atk_starts == _reacted_id:
		var r := _react_r
		_react_r = -1.0
		var punish := randf_() < profile.punish_chance
		if r < profile.dodge_chance:
			dodges += 1
			_punish_t = 2.0 if punish else 0.0
			if g(S.DASH_CD) <= 0 and stamina() > 20.0 and idle_atk():
				_move = (-dir * 0.6 + side * 0.8).normalized()
				dash()
				return
			else:
				_backstep_t = 0.5
		elif sm and idle_atk() and r < profile.dodge_chance + profile.parry_chance and stamina() > 15.0:
			if parry():
				parries_tried += 1
				_punish_t = 2.5 if punish else 0.0
	if _backstep_t > 0.0:
		_backstep_t -= DT
		_move = -dir
		return
	# castigar la recuperación del rival
	var o_rec := og(S.ATK_STATE) == S.Atk.RECOVERY or og(S.PARRY_STATE) == S.Parry.RECOVERY
	if _punish_t > 0.0 and _block_hold <= 0.0:
		_punish_t -= DT
		if sm and (o_rec or og(S.STUN) > 0):
			_move = dir if dist > reach - 0.6 else Vector3.ZERO
			if dist < reach + 0.3 and idle_atk():
				if og(S.STUN) > 54 and stamina() > 30.0:
					attack_heavy()
				else:
					attack_light()
			elif not idle_atk() and g(S.COMBO) < mini(2, profile.max_chain):
				attack_light()
			return
	if _block_hold > 0.0:
		_block_hold -= DT
		_block = true
		_move = -dir * 0.3
		return
	_think -= DT
	if _think <= 0.0:
		_think = profile.think_interval
		if sm and _incoming_projectile(mp) and stamina() > 15.0 and randf_() < profile.block_arrow_chance:
			_block_hold = 0.35
			return
		if g(S.METER) >= S.METER_MAX and idle_atk():
			summon()
		if _try_magic(dist, dir):
			return
		_try_specials(dist, dir)
		if not mounted() and _try_boss(dist, dir):
			boss_used += 1
			return
		if g(S.SWAP_T) <= 0 and idle_atk() and phase != Phase.COMMIT and int(_P[me].get("has_bow", 1)) != 0:
			if sm and dist > 17.0 and randf_() < 0.05:
				swap_loadout()
			elif not sm and (dist < 10.0 or _phase_t < -4.0) and randf_() < 0.3:
				swap_loadout()
		if not sm and phase == Phase.CIRCLE and dist > 6.0 and stamina() > 30.0 and randf_() < 0.3:
			shoot()
		if phase != Phase.REST and (stamina() < 25.0 or g(S.EXH) > 0):
			phase = Phase.REST
			_phase_t = rr(1.5, 3.0)
			_flee = randf_() < 0.25
	var move := Vector3.ZERO
	var rel_n := -dir
	var ang := opp_facing().signed_angle_to(rel_n, Vector3.UP)
	if phase == Phase.BREATHE:
		breathe_time += DT
		_since_breather = 0.0
		var radial := clampf((profile.breather_dist - dist) / 3.0, -0.5, 1.0)
		_breathe_wait -= DT
		if _breathe_wait <= 0.0 and randf_() < DT * 0.5:
			_breathe_wait = rr(0.8, 2.0)
			_breathe_orbit = rr(0.2, 0.45) * (1.0 if randf_() < 0.5 else -1.0)
		if _breathe_wait > 0.0 and radial < 0.2:
			move = Vector3.ZERO
		else:
			move = side * _breathe_orbit - dir * radial
		if _phase_t <= 0.0 and (stamina() > 60.0 or _phase_t < -3.0):
			phase = Phase.CIRCLE
			_phase_t = 0.4 + randf_() * 0.6
			_pref_dist = rr(6.0, 9.0)
		_move = move.limit_length(0.8)
		return
	if phase == Phase.REST:
		rest_time += DT
		if _flee:
			move = -dir
		else:
			move = side * 0.25 - dir * clampf((12.0 - dist) / 4.0, 0.0, 0.25)
		if _phase_t <= 0.0 and stamina() > 70.0:
			phase = Phase.CIRCLE
			_phase_t = 0.5 + randf_()
		_move = move.limit_length(1.0)
		return
	if absf(ang) > 1.3 and phase != Phase.RETREAT:
		phase = Phase.CIRCLE
		_lock = false
		var tangent := rel_n.rotated(Vector3.UP, -signf(ang) * PI / 2.0)
		var radial2 := rel_n * clampf((5.0 - dist) / 3.0, -1.0, 1.0)
		_move = (tangent + radial2).limit_length(1.0)
		if absf(ang) > 1.9 and dist > 3.5 and g(S.DASH_CD) <= 0 and randf_() < 0.08:
			dash()
		_orbit = clampf(ang, -MAX_ORBIT, MAX_ORBIT)
		_orbit_dir = -signf(ang)
		return
	match phase:
		Phase.CIRCLE:
			if not champion_style.is_empty():
				_pref_dist = float(champion_style.get("distance", _pref_dist))
			_orbit += _orbit_dir * DT * profile.orbit_speed * float(champion_style.get("orbit", 1.0))
			if absf(_orbit) > MAX_ORBIT:
				_orbit = clampf(_orbit, -MAX_ORBIT, MAX_ORBIT)
				_orbit_dir = -_orbit_dir
			var desired := (op + opp_facing().rotated(Vector3.UP, _orbit) * _pref_dist).limit_length(ARENA_LIMIT)
			var dd := desired - mp
			move = dd.normalized() * clampf(dd.length() / 3.0, 0.0, 1.0)
			if dist < _pref_dist * 0.8:
				move += side * 0.6 - dir * 0.4
			if not mounted():
				_pref_dist = minf(_pref_dist, 4.5)
			if not sm or g(S.SWAP_T) > 0:
				_pref_dist = 13.0
			_sprint = dist > 14.0 and stamina() > 60.0
			if _since_breather > profile.breather_interval and dist > 4.0:
				_start_breather()
			elif _phase_t <= 0.0 and not _is_behind(mp, op) and stamina() > profile.commit_min_stamina and sm and g(S.SWAP_T) <= 0:
				phase = Phase.COMMIT
				_delay_t = -1.0
				_phase_t = 2.5 * float(champion_style.get("commit", 1.0))
				_swings = 1 + ri(maxi(profile.max_chain, 1))
				_started = false
				_dash_in = dist > 4.5 and randf_() < profile.dash_in_chance
		Phase.COMMIT:
			move = dir if dist > reach - 0.5 else side * 0.4
			if _dash_in and mounted() and dist < 9.0 and dist > 3.5 and facing().dot(dir) > 0.85:
				_move = dir
				dash()
				_dash_in = false
			if idle_atk() and _atk_hold <= 0:
				if _started:
					_swings = 0
				elif dist < reach and facing().dot(dir) > 0.6:
					if _delay_t < 0.0:
						_delay_t = randf_() * profile.delay_max if randf_() < profile.delay_chance else 0.0
						if _delay_t > 0.0:
							delayed_attacks += 1
					_delay_t -= DT
					if _delay_t <= 0.0:
						var ok := attack_heavy() if randf_() < profile.heavy_chance else attack_light()
						_started = ok
						_delay_t = -1.0
			elif g(S.ATK_STATE) != S.Atk.WINDUP and g(S.ATK_IDX) != SimParams.A_HEAVY and g(S.COMBO) < _swings and _atk_hold <= 0:
				attack_light()
			if _swings <= 0 or _phase_t <= 0.0 or (g(S.STUN) > 0 and idle_atk()):
				phase = Phase.RETREAT
				_phase_t = 0.8 + randf_() * 0.6
		Phase.RETREAT:
			var front := (op + opp_facing().rotated(Vector3.UP, clampf(ang, -0.6, 0.6)) * _pref_dist).limit_length(ARENA_LIMIT)
			move = (front - mp).normalized() - dir * 0.5
			if _phase_t <= 0.0 and randf_() < profile.breather_chance:
				_start_breather()
			elif _phase_t <= 0.0:
				phase = Phase.CIRCLE
				_phase_t = profile.engage_pause_min + randf_() * profile.engage_pause_extra
				_pref_dist = rr(6.0, 9.0)
				_orbit = clampf(opp_facing().signed_angle_to(-dir, Vector3.UP), -MAX_ORBIT, MAX_ORBIT)
				if randf_() < 0.3:
					_orbit_dir = -_orbit_dir
	var keep := 3.5 if mounted() else 2.0
	if phase != Phase.COMMIT and dist < keep:
		move -= dir * (keep - dist)
	_move = move.limit_length(1.0)

func _start_breather() -> void:
	phase = Phase.BREATHE
	_phase_t = rr(profile.breather_min, profile.breather_max)
	_breathe_wait = rr(0.0, 1.0)
	_breathe_orbit = rr(0.2, 0.45) * (1.0 if randf_() < 0.5 else -1.0)
	_since_breather = 0.0
	breathers += 1

func _is_behind(mp: Vector3, op: Vector3) -> bool:
	var rel := mp - op
	return rel.length() > 0.1 and opp_facing().dot(rel.normalized()) < -0.3

func _incoming_projectile(mp: Vector3) -> bool:
	var c := mp + Vector3(0, S.HIT_CENTER_Y / 1.0e6, 0)
	for j in S.PROJ_MAX:
		var b := S.PROJ_BASE + j * S.PR_FIELDS
		if _s[b + S.PR_ON] == 0 or _s[b + S.PR_OWNER] == me:
			continue
		var p := Vector3(_s[b + S.PR_X], _s[b + S.PR_Y], _s[b + S.PR_Z]) / 1.0e6
		var v := Vector3(_s[b + S.PR_VX], _s[b + S.PR_VY], _s[b + S.PR_VZ])
		var d := c - p
		if d.length() < 12.0 and v.length() > 0.0 and v.normalized().dot(d.normalized()) > 0.9:
			return true
	return false

func _avoid_aoe(mp: Vector3) -> bool:
	var hr := int(_P[me]["hit_radius"]) / 1.0e6
	for j in S.HZ_MAX:
		var q := S.HZ_BASE + j * S.HZ_FIELDS
		if _s[q + S.HZ_ON] == 0:
			_aoe_done.erase(j) # hueco libre: la próxima marca aquí es otra
			continue
		if _s[q + S.HZ_OWNER] == me or _aoe_done.has(j):
			continue
		var key := j
		var hp := Vector3(_s[q + S.HZ_X] / 1.0e6, 0, _s[q + S.HZ_Z] / 1.0e6)
		var tag := 1
		if _s[q + S.HZ_TYPE] == 2:
			var dv := Vector3(_s[q + S.HZ_DX], 0, _s[q + S.HZ_DZ]) / float(FxMath.ONE)
			var rel := mp - hp
			var along := rel.dot(dv)
			var lat := absf(rel.dot(dv.cross(Vector3.UP)))
			if along > 0.0 and along < 6.0 and lat < _s[q + S.HZ_W] / 2.0e6 + hr + 0.5:
				_aoe_done[key] = tag
				if randf_() < profile.jump_aoe_chance and jump():
					aoe_jumps += 1
					return true
				_move = dv.cross(Vector3.UP).normalized()
				if dash():
					return true
		else:
			if _s[q + S.HZ_DONE] != 0:
				continue
			if mp.distance_to(hp) > _s[q + S.HZ_R] / 1.0e6 or (_s[q + S.HZ_WARN] - _s[q + S.HZ_T]) * DT > 0.3:
				continue
			_aoe_done[key] = tag
			aoe_seen += 1
			var r := randf_()
			if r < profile.jump_aoe_chance and jump():
				aoe_jumps += 1
				return true
			if r < profile.jump_aoe_chance + 0.15 and g(S.DASH_CD) <= 0 and not mounted():
				_move = (mp - hp).normalized()
				dash()
				return true
	return false

## Especial del eikon montado (golpe sísmico del personaje: IN_ART cuando la sim lo tenga).
func _try_specials(dist: float, dir: Vector3) -> void:
	if randf_() > minf(profile.special_chance * float(champion_style.get("special", 1.0)), 0.9):
		return
	var art: Dictionary = _P[me].get("art", {})
	if int(art.get("type", 0)) == 3 and g(S.ART_CD) <= 0 and not mounted() and dist < int(art["r"]) / 1.0e6 - 1.0 and stamina() > 35.0 and g(S.MANA) >= int(art["cost"]):
		tap(S.IN_ART)
		return
	var ek: Dictionary = _P[me].get("ek", {})
	if mounted() and not ek.is_empty() and g(S.EK_SPC) <= 0:
		match String(SimMagic.SPECIALS[int(ek.get("special", 0))]):
			"llamarada":
				if dist > 4.0 and dist < 18.0: tap(S.IN_EIKON)
			"colmillo":
				if dist < 4.2 and facing().dot(dir) > 0.6: tap(S.IN_EIKON)
			"vendaval":
				if dist < 5.0: tap(S.IN_EIKON)

func _try_magic(dist: float, dir: Vector3) -> bool:
	var sc := minf(profile.special_chance * (1.5 if champion_phase_two else 1.0) * float(champion_style.get("special", 1.0)), 0.8)
	if randf_() < sc and can_cast():
		var d := current_spell()
		var safe := dist > 5.0 or (og(S.ATK_STATE) != S.Atk.WINDUP and og(S.BS_PH) == 0)
		var useful := false
		match int(d.get("type", -1)):
			0: useful = dist > 5.0 and dist < 18.0
			1: useful = dist < int(d.get("range", 5500000)) / 1.0e6 and facing().dot(dir) > 0.55
			2: useful = health() < max_health() * 0.72 and dist < 9.0
		if safe and useful:
			tap(S.IN_SPELL)
			return true
	var art: Dictionary = _P[me].get("art", {})
	if not art.is_empty() and int(art["type"]) != 3 and randf_() < sc and g(S.ART_CD) <= 0 and g(S.MANA) >= int(art["cost"]) and can_act() and idle_atk():
		var ok := false
		match int(art["type"]):
			1: ok = dist > reach_of(me) + 0.8 and dist < 9.0 and facing().dot(dir) > 0.55
			2: ok = dist < 3.3
		if ok:
			tap(S.IN_ART)
			return true
	return false

func _try_boss(dist: float, dir: Vector3) -> bool:
	var use_chance := minf(profile.boss_use_chance * (2.5 if champion_phase_two else 1.0) * float(champion_style.get("boss", 1.0)), 0.45)
	if randf_() >= use_chance:
		return false
	var b := boss_list(me)
	var n := SimAbilities.boss_avail(_s, _P, me)
	var order: Array = range(n)
	for k in range(order.size() - 1, 0, -1):
		var j := ri(k + 1)
		var t: int = order[k]; order[k] = order[j]; order[j] = t
	var fd := facing().dot(dir)
	for k: int in order:
		var id := String(b[k].get("id", ""))
		var ok := false
		match id:
			"estocada": ok = dist > 3.5 and dist < BOSS_DIST + 1.0 and fd > 0.5
			"tajo_retardado", "presa_verdugo", "danza_cisne": ok = dist < 3.2 and fd > 0.6
			"giro_martillo": ok = dist < 3.5
			"paso_espectral": ok = dist > 3.5 and dist < 12.0
			"onda_rastrera", "rayos_trazadores", "lluvia_meteoros": ok = dist > 4.5 and dist < 15.0
			"embate_sismico": ok = dist < 8.0 and health() > 40.0
			"lanza_celeste": ok = dist > 5.0 and dist < 16.0
			"aliento_dragon": ok = dist > 2.5 and dist < 7.0 and fd > 0.5
			"furia_fase": ok = dist > 4.0 and health() > 50.0 and g(S.RAGE_T) <= 0
			"postura_contra": ok = dist < 3.5 and og(S.ATK_STATE) == S.Atk.WINDUP
			"carga_area": ok = dist < 3.5 and og(S.ATK_STATE) == S.Atk.NONE
			"rafaga": ok = dist > 6.0 and dist < 16.0
			"escudo_mana": ok = dist < 3.5 and og(S.ATK_STATE) == S.Atk.WINDUP
			"combo_falso": ok = dist < 9.0 and fd > 0.3
			"salto_caida": ok = dist > 5.0 and dist < 14.0 and health() > 40.0
			_: ok = _boss_situ(b[k], dist, fd)
		if ok and boss_skill(id):
			boss_by_id[id] = int(boss_by_id.get(id, 0)) + 1
			return true
	return false

## Habilidades del lote 2: por distancia. Si falta un id, el tipo decide.
func _boss_situ(ab: Dictionary, dist: float, fd: float) -> bool:
	var id := String(ab.get("id", ""))
	if id in ["cuerno_embiste", "giro_noble", "alas_picado", "estocada_negra"]:
		return dist > 2.0 and dist < 7.5 and fd > 0.35
	if id in ["tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada", "danza_triple", "flor_umbral"]:
		return dist < 4.4 and fd > 0.4
	if id == "presa_fauces":
		return dist < 2.6 and fd > 0.65
	if id in ["garra_suelo", "vendaval_hacha", "pisoton"]:
		return dist > 3.0 and dist < 12.0
	if id == "anillo_fuego":
		return dist < 5.5
	if id in ["lluvia_lanzas", "columnas_rayo", "lluvia_sangre", "flecha_grave"]:
		return dist > 4.0 and dist < 16.0
	if id in ["saeta_oscura", "orbe_lunar"]:
		return dist > 5.0 and dist < 16.0
	if id in ["aliento_rayo", "aliento_escarcha", "chorro_lava"]:
		return dist > 2.2 and dist < 8.0 and fd > 0.45
	if id == "grito_guerra":
		return dist > 3.5 and health() > 45.0 and g(S.RAGE_T) <= 0
	if id == "guardia_reflejo":
		return dist < 3.8 and og(S.ATK_STATE) == S.Atk.WINDUP
	match int(ab.get("type", -1)):
		SimAbilities.T_TIMELINE: return dist < 4.5 and fd > 0.4
		SimAbilities.T_WAVE: return dist > 2.5 and dist < 12.0
		SimAbilities.T_RAIN, SimAbilities.T_RAFAGA: return dist > 4.5 and dist < 16.0
		SimAbilities.T_BREATH: return dist > 2.0 and dist < 8.0 and fd > 0.4
		SimAbilities.T_RAGE: return g(S.RAGE_T) <= 0 and health() > 40.0
		SimAbilities.T_COUNTER: return dist < 3.8 and og(S.ATK_STATE) == S.Atk.WINDUP
		SimAbilities.T_CATALOG:
			if int(ab.get("phase", 1)) >= 2:
				var ph: Dictionary = _P[me].get("ph2", {})
				if not ph.is_empty() and g(S.PH2) == 0:
					return false
			var dmin := float(int(ab.get("rmin", 0))) / 1000000.0
			var dmax := float(int(ab.get("rmax", 0))) / 1000000.0
			return dist >= dmin and dist <= dmax
	return false

## En el primer tick de la ventana, a veces elige el remate alternativo (patada).
func _catalog_alt() -> void:
	var ab := ab_cur(_o, me)
	if int(ab.get("type", -1)) != SimAbilities.T_CATALOG:
		return
	var steps: Array = ab.get("steps", [])
	var si := g(S.AB_FIRED)
	if si < 0 or si >= steps.size():
		return
	var step: Dictionary = steps[si]
	if int(step.get("br0", -1)) < 0:
		return
	if g(S.AB_T) - 1 != int(step["br0"]):
		return
	if ri(100) < int(ab.get("balt", 0)):
		tap(S.IN_BOSS_VAR)

## Tajo de ráfaga que me persigue a punto de llegar: voltereta lateral.
func _roll_slash(mp: Vector3) -> bool:
	var c := mp + Vector3(0, S.HIT_CENTER_Y / 1.0e6, 0)
	var hr := int(_P[me]["hit_radius"]) / 1.0e6
	for j in S.PROJ_MAX:
		var b := S.PROJ_BASE + j * S.PR_FIELDS
		if _s[b + S.PR_ON] == 0:
			_rolled.erase(j)
			continue
		if _s[b + S.PR_OWNER] == me or _s[b + S.PR_KIND] != 1 or _rolled.has(j):
			continue
		var key := j
		var p := Vector3(_s[b + S.PR_X], _s[b + S.PR_Y], _s[b + S.PR_Z]) / 1.0e6
		var spd := maxf(Vector3(_s[b + S.PR_VX], _s[b + S.PR_VY], _s[b + S.PR_VZ]).length() / 1.0e6 * 60.0, 1.0)
		var eta := (c.distance_to(p) - _s[b + S.PR_R] / 1.0e6 - hr) / spd
		if eta > 0.16:
			continue
		if randf_() > profile.boss_dodge_chance + 0.25:
			_rolled[key] = 1
			continue
		var v := Vector3(_s[b + S.PR_VX], 0, _s[b + S.PR_VZ]).normalized()
		_move = v.cross(Vector3.UP).normalized()
		if dash():
			_rolled[key] = 1
			slash_rolls += 1
			return true
	return false
