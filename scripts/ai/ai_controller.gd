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
## Ronda 24
var _crit_roll: float = -1.0
var _gc_roll: float = -1.0
var _delay_t: float = -1.0
var crits_tried: int = 0
var guard_counters_tried: int = 0
var delayed_attacks: int = 0
## Ronda 25
var _boss_plan: int = -1
var _boss_dodge: bool = false
var _boss_err: float = 0.0
var _boss_done: bool = false
var boss_dodges: int = 0
var boss_used: int = 0

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
	# --- Ronda 25: Estocada de jefe del jugador: no atacar al invulnerable; esquivar a tiempo ---
	if opp.boss_phase == Fighter.Boss.CHARGE or opp.boss_phase == Fighter.Boss.LUNGE:
		if _boss_plan != opp.boss_uses:
			_boss_plan = opp.boss_uses
			_boss_dodge = randf() < profile.boss_dodge_chance
			_boss_err = randf_range(-profile.boss_dodge_err, profile.boss_dodge_err)
			_boss_done = false
		me.want_block = false
		var eta := opp.boss_charge_left() + maxf(dist - Fighter.BOSS_REACH, 0.0) / Fighter.BOSS_SPEED
		if _boss_dodge and not _boss_done and dist < Fighter.BOSS_DIST + 3.0 and eta <= 0.22 + _boss_err:
			var side_d := opp.boss_dir.cross(Vector3.UP)
			if side_d.dot(me.global_position - opp.global_position) < 0.0:
				side_d = -side_d
			me.move_input = side_d
			if me.dash():
				_boss_done = true
				boss_dodges += 1
				_punish_t = 2.5 # castiga la recuperación
			return
		me.move_input = Vector3.ZERO if dist < 9.0 else dir * 0.4
		if me.atk_state == Fighter.Atk.NONE:
			return
	# --- Ronda 32: ráfaga: rodar cada tajo justo antes de que llegue ---
	if _roll_slash():
		return
	# --- Ronda 32: salto con caída sin marca: al verle empezar a bajar, alejarse; rodar al aterrizar ---
	if opp.ab_id == "salto_caida" and opp.ab_air:
		var sd := BossAbilities.def("salto_caida")
		var land_in := float(sd["land"]) - opp.ab_t
		if opp.ab_locked:
			me.want_block = false
			var away2 := MeshUtil.flat(me.global_position - opp.global_position)
			var fl := (away2.normalized() if away2.length() > 0.2 else side)
			if land_in <= 0.22 + _jump_err:
				me.move_input = (fl + side * 0.5).normalized()
				if me.dash():
					jump_dodges += 1
			else:
				me.want_sprint = true
				me.move_input = (side + fl * 0.3).normalized()
			return
		_jump_err = randf_range(-0.06, 0.06)
	# --- Ronda 31: huir de la carga en área ---
	if opp.ab_id == "carga_area":
		var c: Vector3 = opp.global_position
		var rad := float(BossAbilities.def(opp.ab_id)["radius"])
		var away := MeshUtil.flat(me.global_position - c)
		if away.length() < rad + 1.5:
			ab_flee_frames += 1
			me.want_block = false
			me.want_sprint = true
			me.move_input = away.normalized() if away.length() > 0.2 else side
			return
	# --- Ronda 24: crítico frontal si el jugador tiene la postura rota ---
	if opp.stance_broken_t <= 0.0:
		_crit_roll = -1.0
	elif sword_mode and not me.mounted and not opp.mounted and dist < 7.0:
		if _crit_roll < 0.0:
			_crit_roll = randf()
		if _crit_roll < profile.crit_chance:
			var spot := opp.global_position + opp.facing * 1.4
			var to_spot := MeshUtil.flat(spot - me.global_position)
			me.want_block = false
			me.move_input = to_spot.normalized() if to_spot.length() > 0.4 else Vector3.ZERO
			if me.crit_candidate() == opp and me.atk_state == Fighter.Atk.NONE:
				crits_tried += 1
				me.attack_light()
			return
	# --- Contra de guardia tras bloquear ---
	if me.guard_counter_t <= 0.0:
		_gc_roll = -1.0
	elif sword_mode and not me.mounted and dist < reach + 0.6:
		if _gc_roll < 0.0:
			_gc_roll = randf()
			if _gc_roll < profile.guard_counter_chance:
				_block_hold = 0.0
				me.want_block = false
				var okg := me.attack_heavy()
				if okg:
					guard_counters_tried += 1
				return
	# --- Postura baja: deja de presionar ---
	if phase == Phase.COMMIT and me.stance_fraction() < profile.stance_caution and me.atk_state == Fighter.Atk.NONE:
		phase = Phase.RETREAT
		_phase_t = 1.0
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
		# Ronda 25: Estocada de jefe a media distancia
		if not me.mounted and _try_boss(dist, dir, opp):
			boss_used += 1
			return
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
				_delay_t = -1.0
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
					# Fase 2: a veces retrasa el primer golpe (rompe el ritmo del parry)
					if _delay_t < 0.0:
						_delay_t = randf() * profile.delay_max if randf() < profile.delay_chance else 0.0
						if _delay_t > 0.0:
							delayed_attacks += 1
					_delay_t -= get_physics_process_delta_time()
					if _delay_t <= 0.0:
						var ok := me.attack_heavy() if randf() < profile.heavy_chance else me.attack_light()
						_started = ok
						_delay_t = -1.0
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
		if a == null or a.detonated or a.hidden or a.team == me.team or _aoe_done.has(a.get_instance_id()):
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


# ---------------- Ronda 31: habilidades de jefe de la IA ----------------
var ab_flee_frames: int = 0
var boss_by_id: Dictionary = {}

## Elige una habilidad equipada que tenga sentido a esta distancia y la usa (con probabilidad).
func _try_boss(dist: float, dir: Vector3, opp: Fighter) -> bool:
	if randf() >= profile.boss_use_chance:
		return false
	var ids: Array = me.boss_ids.duplicate()
	ids.shuffle()
	for id: String in ids:
		var ok := false
		match id:
			"estocada": ok = dist > 3.5 and dist < Fighter.BOSS_DIST + 1.0 and me.facing.dot(dir) > 0.5
			"carga_area": ok = dist < 3.5 and opp.atk_state == Fighter.Atk.NONE
			"rafaga": ok = dist > 6.0 and dist < 16.0
			"escudo_mana": ok = dist < 3.5 and opp.atk_state == Fighter.Atk.WINDUP
			"combo_falso": ok = dist < 2.6 and me.facing.dot(dir) > 0.6
			"salto_caida": ok = dist > 5.0 and dist < 14.0 and me.health > 40.0
		if ok and me.boss_skill(id):
			boss_by_id[id] = int(boss_by_id.get(id, 0)) + 1
			return true
	return false


# ---------------- Ronda 32 ----------------
var slash_rolls: int = 0
var jump_dodges: int = 0
var _jump_err: float = 0.0
var _rolled: Dictionary = {}

## Tajo de ráfaga que me persigue a punto de llegar: voltereta lateral (i-frames).
func _roll_slash() -> bool:
	for n in me.get_tree().get_nodes_in_group("projectile"):
		var pr := n as Projectile
		if pr == null or not pr.slash or pr.team == me.team or pr.home_target != me or me in pr.dodged_by:
			continue
		var d := me.get_hit_center() - pr.global_position
		var eta := (d.length() - pr.radius - me.hit_radius) / maxf(pr.speed, 1.0)
		if eta > 0.16 or _rolled.has(pr.get_instance_id()):
			continue
		if randf() > profile.boss_dodge_chance + 0.25:
			_rolled[pr.get_instance_id()] = true # esta vez no reacciona
			continue
		me.want_block = false
		me.move_input = MeshUtil.flat(pr.direction).cross(Vector3.UP).normalized()
		if me.dash():
			_rolled[pr.get_instance_id()] = true
			slash_rolls += 1
			return true
	return false
