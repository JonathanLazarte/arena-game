class_name AIController
extends Node
## IA del luchador rival: acercarse, rodear, atacar, bloquear, disparar e invocar.

var me: Fighter
var enabled: bool = true
var difficulty: float = 0.6 ## 0..1
var _think: float = 0.0
var _strafe: float = 1.0
var _block_hold: float = 0.0
var _plan: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if me == null:
		return
	if not enabled or not me.alive or me.opponent == null or not me.opponent.alive:
		me.move_input = Vector3.ZERO
		me.want_block = false
		return
	var opp := me.opponent
	var to := MeshUtil.flat(opp.global_position - me.global_position)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else me.facing
	if _block_hold > 0.0:
		_block_hold -= delta
		me.want_block = true
		me.move_input = dir * 0.15
		return
	me.want_block = false
	_think -= delta
	if _think <= 0.0:
		_think = 0.15
		if randf() < 0.08:
			_strafe = -_strafe
		# Reacción defensiva
		if opp.is_attacking() and dist < 5.0 and randf() < difficulty * 0.7:
			_block_hold = 0.35
			return
		if _incoming_projectile() and randf() < difficulty * 0.6:
			_block_hold = 0.4
			return
		if me.meter >= Fighter.METER_MAX:
			me.summon()
		if dist > 9.0:
			_plan = dir.rotated(Vector3.UP, _strafe * 0.5)
			if randf() < 0.35:
				me.shoot()
			if dist > 18.0 and randf() < 0.1:
				me.dash()
		elif dist > 3.0:
			_plan = dir.rotated(Vector3.UP, _strafe * 0.15)
			if randf() < 0.05:
				me.dash()
		else:
			_plan = dir.rotated(Vector3.UP, _strafe * 0.7) * 0.5
		if dist < Fighter.SWORD_RANGE and me.facing.dot(dir) > 0.5 and randf() < 0.5 + difficulty * 0.4:
			me.sword()
	me.move_input = _plan

func _incoming_projectile() -> bool:
	for p in me.get_tree().get_nodes_in_group("projectile"):
		var pr := p as Projectile
		if pr and pr.team != me.team:
			var d := me.get_hit_center() - pr.global_position
			if d.length() < 12.0 and pr.direction.dot(d.normalized()) > 0.9:
				return true
	return false
