class_name AIController
extends Node
## IA del rival. Mantiene una distancia media DELANTE del jugador, lo rodea
## mirándolo, se compromete a atacar en ventanas (espada o dash + espada) y luego
## se retira. Nunca se solapa ni se queda pegado a la espalda.

enum Phase { CIRCLE, COMMIT, RETREAT }

var me: Fighter
var enabled: bool = true
var difficulty: float = 0.6 ## 0..1
var phase: Phase = Phase.CIRCLE
var _phase_t: float = 2.0
var _orbit: float = 0.0 ## ángulo respecto a la mirada del jugador (rad)
var _orbit_dir: float = 1.0
var _pref_dist: float = 7.5
var _swings: int = 0
var _dash_in: bool = false
var _think: float = 0.0
var _block_hold: float = 0.0

const MAX_ORBIT := 1.15

func _physics_process(delta: float) -> void:
	if me == null:
		return
	if not enabled or not me.alive or me.opponent == null or not me.opponent.alive:
		me.move_input = Vector3.ZERO
		me.want_block = false
		return
	var opp := me.opponent
	me.face_target = opp
	var to := MeshUtil.flat(opp.global_position - me.global_position)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else me.facing
	var side := dir.cross(Vector3.UP) * _orbit_dir
	_phase_t -= delta
	if _block_hold > 0.0:
		_block_hold -= delta
		me.want_block = true
		me.move_input = -dir * 0.3
		return
	me.want_block = false
	_think -= delta
	if _think <= 0.0:
		_think = 0.12
		if opp.is_attacking() and dist < 5.0 and randf() < difficulty * 0.6:
			_block_hold = 0.35
			return
		if _incoming_projectile() and randf() < difficulty * 0.5:
			_block_hold = 0.35
			return
		if me.meter >= Fighter.METER_MAX:
			me.summon()
		if phase == Phase.CIRCLE and dist > 7.0 and randf() < 0.1:
			me.shoot()
	var move := Vector3.ZERO
	# Ángulo de la IA respecto a la mirada del jugador (0 = justo delante)
	var rel_n := -dir
	var ang := opp.facing.signed_angle_to(rel_n, Vector3.UP)
	if absf(ang) > 1.3 and phase != Phase.RETREAT:
		# Detrás o muy lateral: rodear rápido hacia el frente manteniendo distancia
		phase = Phase.CIRCLE
		me.face_target = null # galopar de frente es más rápido que el strafe
		var tangent := rel_n.rotated(Vector3.UP, -signf(ang) * PI / 2.0)
		var radial := rel_n * clampf((5.0 - dist) / 3.0, -1.0, 1.0)
		me.move_input = (tangent + radial).limit_length(1.0)
		if absf(ang) > 1.9 and dist > 3.5 and me.dash_cd <= 0.0 and randf() < 0.08:
			me.dash() # dash lateral para recuperar el frente
		_orbit = clampf(ang, -MAX_ORBIT, MAX_ORBIT)
		_orbit_dir = -signf(ang)
		return
	match phase:
		Phase.CIRCLE:
			_orbit += _orbit_dir * delta * 0.7
			if absf(_orbit) > MAX_ORBIT:
				_orbit = clampf(_orbit, -MAX_ORBIT, MAX_ORBIT)
				_orbit_dir = -_orbit_dir
			var desired := opp.global_position + opp.facing.rotated(Vector3.UP, _orbit) * _pref_dist
			desired = _clamp_arena(desired)
			var dd := MeshUtil.flat(desired - me.global_position)
			move = dd.normalized() * clampf(dd.length() / 3.0, 0.0, 1.0)
			# Rodear en vez de atravesar al jugador
			if dist < _pref_dist * 0.8:
				move += side * 0.6 - dir * 0.4
			if _phase_t <= 0.0 and not _is_behind(opp):
				phase = Phase.COMMIT
				_phase_t = 2.5
				_swings = 1 + randi() % 3
				_dash_in = dist > 4.5 and randf() < 0.5
		Phase.COMMIT:
			move = dir if dist > 2.9 else side * 0.4
			if _dash_in and dist < 9.0 and dist > 3.5 and me.facing.dot(dir) > 0.85:
				me.move_input = dir
				me.dash()
				_dash_in = false
			if dist < Fighter.SWORD_RANGE and me.facing.dot(dir) > 0.6 and me.sword():
				_swings -= 1
			if _swings <= 0 or _phase_t <= 0.0 or me.stun > 0.0:
				phase = Phase.RETREAT
				_phase_t = 0.8 + randf() * 0.6
		Phase.RETREAT:
			var front := opp.global_position + opp.facing.rotated(Vector3.UP, clampf(ang, -0.6, 0.6)) * _pref_dist
			front = _clamp_arena(front)
			move = MeshUtil.flat(front - me.global_position).normalized() - dir * 0.5
			if _phase_t <= 0.0:
				phase = Phase.CIRCLE
				_phase_t = 1.5 + randf() * 1.5
				_pref_dist = randf_range(6.0, 9.0)
				_orbit = clampf(opp.facing.signed_angle_to(-dir, Vector3.UP), -MAX_ORBIT, MAX_ORBIT)
				if randf() < 0.3:
					_orbit_dir = -_orbit_dir
	# Separación extra fuera de la fase de ataque
	if phase != Phase.COMMIT and dist < 3.5:
		move -= dir * (3.5 - dist)
	me.move_input = move.limit_length(1.0)

func _clamp_arena(p: Vector3) -> Vector3:
	var f := MeshUtil.flat(p)
	return f.limit_length(Arena.RADIUS - 4.0)

func _is_behind(opp: Fighter) -> bool:
	var rel := MeshUtil.flat(me.global_position - opp.global_position)
	return rel.length() > 0.1 and opp.facing.dot(rel.normalized()) < -0.3

func _incoming_projectile() -> bool:
	for p in me.get_tree().get_nodes_in_group("projectile"):
		var pr := p as Projectile
		if pr and pr.team != me.team:
			var d := me.get_hit_center() - pr.global_position
			if d.length() < 12.0 and pr.direction.dot(d.normalized()) > 0.9:
				return true
	return false
