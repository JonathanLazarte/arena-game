class_name AIController
extends Node
## IA del rival. Mantiene una distancia media DELANTE del jugador, lo rodea
## mirándolo, se compromete a atacar en ventanas (espada o dash + espada) y luego
## se retira. Nunca se solapa ni se queda pegado a la espalda.

enum Phase { CIRCLE, COMMIT, RETREAT, REST, BREATHE }

var me: Fighter
var enabled: bool = true
## Perfil de dificultad (por defecto el rival es nivel 1 "easy").
var profile: AIDifficulty = preload("res://resources/ai/easy.tres")
var _react_t: float = -1.0 ## reacción pendiente (retraso de reacción)
var _react_r: float = -1.0
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
var rest_time: float = 0.0 ## tiempo total descansando (para pruebas)
var breathers: int = 0 ## respiros empezados (pruebas)
var breathe_time: float = 0.0 ## tiempo total en respiros (pruebas)
var _since_breather: float = 0.0
var _breathe_wait: float = 0.0 ## sub-fase: quieto esperando
var _breathe_orbit: float = 0.3
var _flee: bool = false
# Lectura de ataques / castigo
var dodges: int = 0 ## esquivas a ataques telegrafiados (para pruebas)
var parries_tried: int = 0
var punish_hits: int = 0 ## golpes acertados mientras el jugador estaba en recuperación/aturdido
var _reacted_id: int = -1
var _punish_t: float = 0.0
var _backstep_t: float = 0.0
var _started: bool = false
var _connected: bool = false
var aoe_jumps: int = 0 ## saltos para esquivar golpes de área (pruebas)
var aoe_seen: int = 0
var _aoe_done: Dictionary = {}

func _on_landed(_t: Node3D, res: String, was_open: bool) -> void:
	if res == "hit" and was_open:
		punish_hits += 1

func _physics_process(delta: float) -> void:
	if me == null:
		return
	if not enabled or not me.alive or me.opponent == null or not me.opponent.alive:
		me.move_input = Vector3.ZERO
		me.want_block = false
		return
	var opp := me.opponent
	me.face_target = opp
	me.aim_lead = profile.aim_lead
	var to := MeshUtil.flat(opp.global_position - me.global_position)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else me.facing
	var side := dir.cross(Vector3.UP) * _orbit_dir
	_phase_t -= delta
	_since_breather += delta
	me.want_sprint = false
	if not _connected:
		_connected = true
		me.landed_hit.connect(_on_landed)
	# --- Golpe de área en el suelo que le va a alcanzar: a veces lo salta (o rueda fuera) ---
	if _avoid_aoe(dir):
		return
	# --- A pie: volver a montar (su eikon) cuando sea seguro, si no, luchar a pie ---
	if not me.mounted:
		var m := me.nearest_free_mount()
		if m:
			var md := me.global_position.distance_to(m.global_position)
			if md <= Fighter.MOUNT_REACH - 0.3:
				me.want_block = false
				me.toggle_mount()
				return
			if dist > 6.0 or md < 6.0 or opp.is_exhausted():
				me.face_target = null
				me.want_block = false
				me.want_sprint = me.stamina > 40.0
				me.move_input = MeshUtil.flat(m.global_position - me.global_position).normalized()
				return
	var sword_mode := me.loadout == Fighter.Loadout.SWORD_SHIELD
	var reach := me.sword_range()
	# --- Leer el ataque telegrafiado del jugador y reaccionar al final de su anticipación ---
	if opp.atk_state == Fighter.Atk.WINDUP and opp.attacks_started != _reacted_id \
			and dist < opp.sword_range() + 2.5 and opp.atk_dur - opp.atk_t < 0.3:
		_reacted_id = opp.attacks_started
		_react_t = profile.reaction_time
		_react_r = randf()
	if _react_t >= 0.0:
		_react_t -= delta
	if _react_t < 0.0 and _react_r >= 0.0 and opp.atk_state == Fighter.Atk.WINDUP and opp.attacks_started == _reacted_id:
		var r := _react_r
		_react_r = -1.0
		var punish := randf() < profile.punish_chance
		if r < profile.dodge_chance:
			dodges += 1
			_punish_t = 2.0 if punish else 0.0
			if me.dash_cd <= 0.0 and me.stamina > 20.0 and me.atk_state == Fighter.Atk.NONE:
				me.move_input = (-dir * 0.6 + side * 0.8).normalized()
				me.dash()
			else:
				_backstep_t = 0.5
		elif sword_mode and me.atk_state == Fighter.Atk.NONE and r < profile.dodge_chance + profile.parry_chance and me.stamina > 15.0:
			# Parry dedicado con el mismo riesgo que el jugador (si falla queda expuesto)
			if me.parry():
				parries_tried += 1
				_punish_t = 2.5 if punish else 0.0
	if _backstep_t > 0.0:
		_backstep_t -= delta
		me.want_block = false
		me.move_input = -dir
		return
	# --- Castigar la recuperación del jugador ---
	if _punish_t > 0.0 and _block_hold <= 0.0:
		_punish_t -= delta
		if sword_mode and (opp.in_recovery() or opp.stun > 0.0):
			me.want_block = false
			me.move_input = dir if dist > reach - 0.6 else Vector3.ZERO
			if dist < reach + 0.3 and me.atk_state == Fighter.Atk.NONE:
				if opp.stun > 0.9 and me.stamina > 30.0:
					me.attack_heavy()
				else:
					me.attack_light()
			elif me.atk_state != Fighter.Atk.NONE and me.combo < mini(2, profile.max_chain):
				me.attack_light() # búfer: encadenar un segundo golpe
			return
	if _block_hold > 0.0:
		_block_hold -= delta
		me.want_block = true
		me.move_input = -dir * 0.3
		return
	me.want_block = false
	_think -= delta
	if _think <= 0.0:
		_think = profile.think_interval
		if sword_mode and _incoming_projectile() and me.stamina > 15.0 and randf() < profile.block_arrow_chance:
			_block_hold = 0.35
			return
		if me.meter >= Fighter.METER_MAX and me.atk_state == Fighter.Atk.NONE:
			me.summon()
		_try_specials(dist, dir)
		# Cambio de armas por distancia (~0,4 s, igual que al jugador; se sigue moviendo)
		if not me.is_swapping() and me.atk_state == Fighter.Atk.NONE and phase != Phase.COMMIT:
			if sword_mode and dist > 17.0 and randf() < 0.05:
				me.swap_loadout()
			elif not sword_mode and (dist < 10.0 or _phase_t < -4.0) and randf() < 0.3:
				# Con arco no se queda eternamente a distancia: vuelve a la espada para entrar
				me.swap_loadout()
		if not sword_mode and phase == Phase.CIRCLE and dist > 6.0 and me.stamina > 30.0 and randf() < 0.3:
			me.shoot()
		# Poco aguante: retirarse a recuperar (pausas naturales), a veces huir
		if phase != Phase.REST and (me.stamina < 25.0 or me.is_exhausted()):
			phase = Phase.REST
			_phase_t = randf_range(1.5, 3.0)
			_flee = randf() < 0.25
	var move := Vector3.ZERO
	# Ángulo de la IA respecto a la mirada del jugador (0 = justo delante)
	var rel_n := -dir
	var ang := opp.facing.signed_angle_to(rel_n, Vector3.UP)
	if phase == Phase.BREATHE:
		breathe_time += delta
		_since_breather = 0.0
		# Alejarse hasta su distancia de respiro, luego rodear despacio o esperar quieto
		var radial := clampf((profile.breather_dist - dist) / 3.0, -0.5, 1.0)
		_breathe_wait -= delta
		if _breathe_wait <= 0.0 and randf() < delta * 0.5:
			_breathe_wait = randf_range(0.8, 2.0)
			_breathe_orbit = randf_range(0.2, 0.45) * (1.0 if randf() < 0.5 else -1.0)
		if _breathe_wait > 0.0 and radial < 0.2:
			move = Vector3.ZERO # espera mirando al jugador
		else:
			move = side * _breathe_orbit - dir * radial
		if _phase_t <= 0.0 and (me.stamina > 60.0 or _phase_t < -3.0):
			phase = Phase.CIRCLE
			_phase_t = 0.4 + randf() * 0.6
			_pref_dist = randf_range(6.0, 9.0)
		me.move_input = move.limit_length(0.8)
		return
	if phase == Phase.REST:
		rest_time += delta
		if _flee:
			move = -dir
		else:
			# Rodear despacio a distancia (cuenta como "parado" para regenerar rápido)
			move = (side * 0.25 - dir * clampf((12.0 - dist) / 4.0, 0.0, 0.25))
		if _phase_t <= 0.0 and me.stamina > 70.0:
			phase = Phase.CIRCLE
			_phase_t = 0.5 + randf()
		me.move_input = move.limit_length(1.0)
		return
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
			_orbit += _orbit_dir * delta * profile.orbit_speed
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
			if not me.mounted:
				_pref_dist = minf(_pref_dist, 4.5)
			if not sword_mode or me.is_swapping():
				_pref_dist = 13.0
			me.want_sprint = dist > 14.0 and me.stamina > 60.0
			if _since_breather > profile.breather_interval and dist > 4.0:
				_start_breather()
			elif _phase_t <= 0.0 and not _is_behind(opp) and me.stamina > profile.commit_min_stamina and sword_mode and not me.is_swapping():
				phase = Phase.COMMIT
				_phase_t = 2.5
				_swings = 1 + randi() % maxi(profile.max_chain, 1)
				_started = false
				_dash_in = dist > 4.5 and randf() < profile.dash_in_chance
		Phase.COMMIT:
			move = dir if dist > reach - 0.5 else side * 0.4
			if _dash_in and me.mounted and dist < 9.0 and dist > 3.5 and me.facing.dot(dir) > 0.85:
				me.move_input = dir
				me.dash()
				_dash_in = false
			# Se compromete con su ataque telegrafiado (el jugador puede castigar la recuperación)
			if me.atk_state == Fighter.Atk.NONE:
				if _started:
					_swings = 0
				elif dist < reach and me.facing.dot(dir) > 0.6:
					var ok := me.attack_heavy() if randf() < profile.heavy_chance else me.attack_light()
					_started = ok
			elif me.atk_state != Fighter.Atk.WINDUP and not me.atk_heavy and me.combo < _swings:
				me.attack_light() # búfer para encadenar
			if _swings <= 0 or _phase_t <= 0.0 or (me.stun > 0.0 and me.atk_state == Fighter.Atk.NONE):
				phase = Phase.RETREAT
				_phase_t = 0.8 + randf() * 0.6
		Phase.RETREAT:
			var front := opp.global_position + opp.facing.rotated(Vector3.UP, clampf(ang, -0.6, 0.6)) * _pref_dist
			front = _clamp_arena(front)
			move = MeshUtil.flat(front - me.global_position).normalized() - dir * 0.5
			if _phase_t <= 0.0 and randf() < profile.breather_chance:
				_start_breather()
			elif _phase_t <= 0.0:
				phase = Phase.CIRCLE
				_phase_t = profile.engage_pause_min + randf() * profile.engage_pause_extra
				_pref_dist = randf_range(6.0, 9.0)
				_orbit = clampf(opp.facing.signed_angle_to(-dir, Vector3.UP), -MAX_ORBIT, MAX_ORBIT)
				if randf() < 0.3:
					_orbit_dir = -_orbit_dir
	# Separación extra fuera de la fase de ataque
	var keep := 3.5 if me.mounted else 2.0
	if phase != Phase.COMMIT and dist < keep:
		move -= dir * (keep - dist)
	me.move_input = move.limit_length(1.0)

## Respiro: varios segundos (aleatorios) sin presionar al jugador.
func _start_breather() -> void:
	phase = Phase.BREATHE
	_phase_t = randf_range(profile.breather_min, profile.breather_max)
	_breathe_wait = randf_range(0.0, 1.0)
	_breathe_orbit = randf_range(0.2, 0.45) * (1.0 if randf() < 0.5 else -1.0)
	_since_breather = 0.0
	breathers += 1

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

func _avoid_aoe(dir: Vector3) -> bool:
	for n in me.get_tree().get_nodes_in_group("ground_aoe"):
		var a := n as GroundAoE
		if a == null or a.detonated or a.team == me.team or _aoe_done.has(a.get_instance_id()):
			continue
		if not a.contains(me.global_position) or a.time_left() > 0.3:
			continue
		_aoe_done[a.get_instance_id()] = true
		aoe_seen += 1
		var r := randf()
		if r < profile.jump_aoe_chance and me.jump():
			aoe_jumps += 1
			return true
		if r < profile.jump_aoe_chance + 0.15 and me.dash_cd <= 0.0 and not me.mounted:
			me.move_input = MeshUtil.flat(me.global_position - a.global_position).normalized()
			me.dash() # voltereta: los i-frames también lo evitan
			return true
	return false

## Habilidad del personaje (golpe sísmico) y especial del eikon montado.
func _try_specials(dist: float, dir: Vector3) -> void:
	if randf() > profile.special_chance:
		return
	if me.has_special() and me.special_cd <= 0.0 and not me.mounted and dist < Fighter.SLAM_RADIUS - 1.0 and me.stamina > 35.0:
		me.special()
		return
	if me.mounted and me.mount_node and me.mount_node.eikon and me.mount_node.owner_fighter == me and me.mount_node.special_cd <= 0.0:
		match me.mount_node.eikon.special_id:
			"llamarada":
				if dist > 4.0 and dist < 18.0:
					me.eikon_special()
			"colmillo":
				if dist < 4.2 and me.facing.dot(dir) > 0.6:
					me.eikon_special()
			"vendaval":
				if dist < 5.0:
					me.eikon_special()
