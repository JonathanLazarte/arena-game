class_name Fighter
extends CharacterBody3D
## Jinete / personaje. Puede ir montado (usa los MountData de su Mount) o a pie
## (usa on_foot.tres). Los controladores (jugador/IA) rellenan move_input,
## want_block y want_sprint y llaman a sword()/shoot()/summon()/dash()/toggle_mount().
## Cualquier nodo en el grupo "damageable" con team, alive, hit_radius, take_hit()
## y get_hit_center() puede ser objetivo (eikons ahora, mobs en el futuro).

signal health_changed(value: float, max_value: float)
signal meter_changed(value: float)
signal stamina_changed(value: float, exhausted: bool)
signal died(fighter: Fighter)
signal summoned(eikon: Node3D)
signal impact(strength: float)
signal mount_changed(mounted: bool)
signal loadout_changed(loadout: int)
signal landed_hit(target: Node3D, result: String, target_was_open: bool)

const METER_MAX := 100.0
const GRAVITY := 20.0
const SWORD_DAMAGE := 12.0
const SWORD_RANGE_MOUNTED := 3.4
const SWORD_RANGE_FOOT := 2.2
const SWORD_HALF_ARC_MOUNTED := deg_to_rad(100.0) ## frente y lados
const SWORD_HALF_ARC_FOOT := deg_to_rad(70.0)
## Ataques estilo souls: anticipación (telegrafiada) -> frames activos -> recuperación vulnerable.
const LIGHT := {"windup": 0.45, "chain_windup": 0.45, "active": 0.12, "recovery": 0.6, "whiff": 0.3, "damage": 12.0, "stamina": 14.0}
const HEAVY := {"windup": 0.8, "chain_windup": 0.8, "active": 0.15, "recovery": 0.75, "whiff": 0.35, "damage": 26.0, "stamina": 28.0}
const MAX_COMBO := 3
const FINISHER_EXTRA_RECOVERY := 0.3 ## el último golpe del combo deja más expuesto
const CHAIN_MIN_RECOVERY := 0.3 ## un encadenado no se salta toda la recuperación
const ROLL_CANCEL_FRACTION := 0.5 ## voltereta/dash permitido en la 2.ª mitad de la recuperación
const HEAVY_HOLD := 0.4 ## mantener ataque este tiempo = ataque fuerte
const POISE_MAX := 50.0
const POISE_REGEN := 25.0
const SWAP_TIME := 2.0
const PARRY_STAGGER := 1.6
const RIPOSTE_MULT := 1.8
enum Atk { NONE, WINDUP, ACTIVE, RECOVERY }
enum Loadout { SWORD_SHIELD, BOW }
const BOW_COOLDOWN := 1.0
const PARRY_WINDOW := 0.3 ## escudo alzado como mucho este tiempo antes del golpe = parry
const BLOCK_REDUCTION := 0.2
const EXHAUSTED_BLOCK_REDUCTION := 0.6
const REVERSE_FACTOR := 0.5
const DASH_DAMAGE := 6.0
const DASH_KNOCKBACK := 16.0
const SEPARATION := 3.0
const SEPARATION_FOOT := 1.6
const MOUNT_REACH := 3.5
const HEAVY_HIT := 14.0 ## golpes de este daño o más pueden derribar
# Aguante (stamina)
const STAMINA_MAX := 100.0
const COST_DASH := 25.0
const COST_ROLL := 18.0
const COST_SWORD := 12.0
const COST_BOW := 6.0
const COST_BLOCKED_HIT := 10.0
const DRAIN_BLOCK := 15.0 ## por segundo
const DRAIN_SPRINT := 20.0 ## por segundo
const REGEN := 18.0
const REGEN_IDLE := 32.0
const REGEN_DELAY := 0.6
const EXHAUST_TIME := 1.5

## Sigue existiendo por compatibilidad: montura inicial.
@export var mount: MountData
@export var eikon: EikonData
var foot_stats: MountData = preload("res://resources/mounts/on_foot.tres")
var team: int = 0
var color: Color = Color(0.2, 0.4, 1.0)
var display_name: String = "Jugador"
var opponent: Fighter

var max_health: float = 100.0
var health: float = 100.0
var meter: float = 0.0
var stamina: float = STAMINA_MAX
var exhausted: float = 0.0
var alive: bool = true
var hit_radius: float = 1.3
## Probabilidad de derribo al recibir un dash / golpe fuerte estando montado.
var knockoff_chance_dash: float = 0.5
var knockoff_chance_heavy: float = 0.6

# Entrada de los controladores
var move_input: Vector3 = Vector3.ZERO
var want_block: bool = false
var want_sprint: bool = false

var facing: Vector3 = Vector3.FORWARD
var face_target: Node3D = null ## lock-on
var planar_vel: Vector3 = Vector3.ZERO
var dash_dir: Vector3 = Vector3.FORWARD
var invuln: float = 0.0
var knock: Vector3 = Vector3.ZERO
var reversing: bool = false
var sprinting: bool = false
var blocking: bool = false
var block_time: float = 0.0
var stun: float = 0.0
var atk_state: Atk = Atk.NONE
var atk_heavy: bool = false
var atk_t: float = 0.0
var atk_dur: float = 0.0
var combo: int = 0
var attacks_started: int = 0
var _atk_landed: bool = false
var _atk_hit: Array[Node3D] = []
var _buffered: bool = false
var poise: float = POISE_MAX
var _since_hit: float = 10.0
var riposte_t: float = 0.0 ## tras sufrir un parry: recibe daño extra
var loadout: Loadout = Loadout.SWORD_SHIELD
var swap_t: float = 0.0
var bow_cd: float = 0.0
var dash_time: float = 0.0
var dash_cd: float = 0.0
var active_eikon: Node3D = null

var mounted: bool = false
var mount_node: Mount = null ## montura actual (si está montado)
var owned_mount: Mount = null ## su montura (para volver a montar)

var _since_spend: float = 10.0
var _dash_hit: bool = false
var _rider_root: Node3D
var _sword_pivot: Node3D
var _blade: MeshInstance3D
var _bow: MeshInstance3D
var _blade_mat: StandardMaterial3D
var _shield: MeshInstance3D
var _body: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _col_shape: BoxShape3D
var _col: CollisionShape3D
var _flash: float = 0.0

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("fighter")
	max_health = 100.0 + (mount.health_bonus if mount else 0.0)
	health = max_health
	_build_visuals()
	_apply_mount_visuals()

func stats() -> MountData:
	return mount_node.data if mounted and mount_node else foot_stats

func sword_range() -> float:
	return SWORD_RANGE_MOUNTED if mounted else SWORD_RANGE_FOOT

func sword_half_arc() -> float:
	return SWORD_HALF_ARC_MOUNTED if mounted else SWORD_HALF_ARC_FOOT

func is_exhausted() -> bool:
	return exhausted > 0.0

func _build_visuals() -> void:
	_col = CollisionShape3D.new()
	_col_shape = BoxShape3D.new()
	_col.shape = _col_shape
	add_child(_col)
	_rider_root = Node3D.new()
	add_child(_rider_root)
	_body = MeshUtil.box(_rider_root, Vector3(0.6, 1.0, 0.45), Vector3(0, 1.0, 0.1), color)
	MeshUtil.sphere(_rider_root, 0.25, Vector3(0, 1.75, 0.1), Color(0.95, 0.8, 0.65))
	for x: float in [-0.15, 0.15]:
		_legs.append(MeshUtil.box(_rider_root, Vector3(0.2, 0.55, 0.25), Vector3(x, 0.27, 0.1), color.darkened(0.4)))
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.45, 1.1, 0.0)
	_rider_root.add_child(_sword_pivot)
	_blade = MeshUtil.box(_sword_pivot, Vector3(0.1, 0.1, 1.0), Vector3(0, 0, -0.5), Color(0.85, 0.85, 0.95))
	MeshUtil.box(_sword_pivot, Vector3(0.4, 0.08, 0.08), Vector3(0, 0, 0), Color(0.6, 0.5, 0.2)) # guarda
	_blade_mat = _blade.material_override as StandardMaterial3D
	_bow = MeshUtil.box(_rider_root, Vector3(0.08, 1.5, 0.12), Vector3(-0.45, 1.15, -0.2), Color(0.5, 0.3, 0.12))
	_bow.visible = false
	_shield = MeshUtil.box(_rider_root, Vector3(0.1, 0.8, 0.8), Vector3(-0.5, 1.0, 0.0), color.darkened(0.3))

func _apply_mount_visuals() -> void:
	_rider_root.position.y = 1.3 if mounted else 0.0
	for l in _legs:
		l.visible = not mounted
	# Espada más larga montado (alcance real)
	var blade_len := 2.2 if mounted else 1.4
	(_blade.mesh as BoxMesh).size = Vector3(0.1, 0.1, blade_len)
	_blade.position = Vector3(0, 0, -blade_len * 0.5)
	if mounted:
		_col_shape.size = Vector3(1.2, 2.4, 2.4)
		_col.position = Vector3(0, 1.2, 0)
		hit_radius = 1.3
	else:
		_col_shape.size = Vector3(0.7, 1.9, 0.7)
		_col.position = Vector3(0, 0.95, 0)
		hit_radius = 0.75

# ---------------- Montar / desmontar ----------------

func mount_on(m: Mount) -> bool:
	if m == null or not m.is_free() or mounted:
		return false
	mounted = true
	mount_node = m
	m.set_rider(self)
	global_position = Vector3(m.global_position.x, global_position.y, m.global_position.z)
	_apply_mount_visuals()
	mount_changed.emit(true)
	return true

func dismount(forced: bool = false) -> void:
	if not mounted:
		return
	var m := mount_node
	mounted = false
	mount_node = null
	var side := facing.cross(Vector3.UP)
	m.global_position = global_position
	m.set_rider(null)
	global_position += side * -1.6 + Vector3(0, 0.1, 0)
	planar_vel = Vector3.ZERO
	dash_time = 0.0
	_apply_mount_visuals()
	if forced:
		apply_stun(0.6)
	mount_changed.emit(false)

func nearest_free_mount() -> Mount:
	var best: Mount = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("mount"):
		var m := n as Mount
		if m and m.is_free():
			var d := global_position.distance_to(m.global_position)
			if d < bd:
				bd = d
				best = m
	# Preferir la propia si está a la misma distancia aproximada
	if owned_mount and owned_mount.is_free() and global_position.distance_to(owned_mount.global_position) <= bd + 1.0:
		return owned_mount
	return best

func can_remount() -> bool:
	var m := nearest_free_mount()
	return m != null and global_position.distance_to(m.global_position) <= MOUNT_REACH

## Acción "Montar": monta si hay montura libre cerca, desmonta si va montado.
func toggle_mount() -> bool:
	if not alive or stun > 0.0 or atk_state != Atk.NONE or swap_t > 0.0:
		return false
	if mounted:
		dismount(false)
		return true
	if can_remount():
		return mount_on(nearest_free_mount())
	return false

# ---------------- Aguante ----------------

func spend_stamina(v: float) -> void:
	stamina = maxf(stamina - v, 0.0)
	_since_spend = 0.0
	if stamina <= 0.0 and exhausted <= 0.0:
		exhausted = EXHAUST_TIME
		sprinting = false
	stamina_changed.emit(stamina, exhausted > 0.0)

func _update_stamina(delta: float, idle: bool) -> void:
	_since_spend += delta
	if exhausted > 0.0:
		exhausted = maxf(exhausted - delta, 0.0)
	if _since_spend >= REGEN_DELAY and stamina < STAMINA_MAX:
		stamina = minf(stamina + (REGEN_IDLE if idle else REGEN) * delta, STAMINA_MAX)
		stamina_changed.emit(stamina, exhausted > 0.0)

# ---------------- Bucle principal ----------------

func _physics_process(delta: float) -> void:
	riposte_t = maxf(riposte_t - delta, 0.0)
	_since_hit += delta
	if _since_hit > 1.5:
		poise = minf(poise + POISE_REGEN * delta, POISE_MAX)
	if swap_t > 0.0:
		swap_t -= delta
		if swap_t <= 0.0:
			swap_t = 0.0
			loadout = Loadout.BOW if loadout == Loadout.SWORD_SHIELD else Loadout.SWORD_SHIELD
			_apply_loadout_visuals()
			loadout_changed.emit(loadout)
	_update_attack(delta)
	bow_cd = maxf(bow_cd - delta, 0.0)
	dash_cd = maxf(dash_cd - delta, 0.0)
	dash_time = maxf(dash_time - delta, 0.0)
	stun = maxf(stun - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	var st := stats()
	var inp := move_input
	if not alive or stun > 0.0:
		inp = Vector3.ZERO
	var wb := want_block and alive and stun <= 0.0 and loadout == Loadout.SWORD_SHIELD and swap_t <= 0.0 and atk_state == Atk.NONE
	if wb and not blocking:
		block_time = 0.0
	blocking = wb
	if blocking:
		block_time += delta
		spend_stamina(DRAIN_BLOCK * delta)
	inp.y = 0.0
	var amount := minf(inp.length(), 1.0)
	var target_vel := Vector3.ZERO
	var turn := st.turn_speed * delta
	reversing = false
	if _lock_valid():
		var d := MeshUtil.flat(face_target.global_position - global_position)
		if d.length() > 0.1:
			facing = _turn_toward(facing, d.normalized(), turn * 1.8)
		if amount > 0.05:
			var dirn := inp.normalized()
			var fdot := dirn.dot(facing)
			var k := lerpf(0.8, 1.0, fdot) if fdot >= 0.0 else lerpf(0.8, REVERSE_FACTOR, -fdot)
			reversing = fdot < -0.6
			target_vel = dirn * st.speed * amount * k
	elif amount > 0.05:
		var dirn := inp.normalized()
		if dirn.dot(facing) < -0.6:
			reversing = true
			target_vel = -facing * st.speed * REVERSE_FACTOR * amount
		else:
			facing = _turn_toward(facing, dirn, turn)
			target_vel = facing * st.speed * amount
	# Galope / sprint
	sprinting = want_sprint and not reversing and amount > 0.3 and exhausted <= 0.0 and not blocking and stamina > 0.0
	if sprinting:
		target_vel *= st.sprint_multiplier
		spend_stamina(DRAIN_SPRINT * delta)
	if blocking:
		target_vel *= 0.45
	if exhausted > 0.0:
		target_vel *= 0.6
	if atk_state != Atk.NONE:
		target_vel *= 0.55 if mounted else 0.3 # compromiso: casi no te mueves al atacar
	_update_stamina(delta, amount < 0.3 or reversing)
	planar_vel = planar_vel.move_toward(target_vel, st.acceleration * delta)
	var v := planar_vel
	if dash_time > 0.0:
		v = dash_dir * st.dash_speed
		if mounted:
			_check_dash_hit()
	v += knock
	knock = knock.move_toward(Vector3.ZERO, 40.0 * delta)
	var my_sep := SEPARATION if mounted else SEPARATION_FOOT
	for n in get_tree().get_nodes_in_group("fighter"):
		if n != self:
			var other := n as Fighter
			var min_sep := maxf(my_sep, SEPARATION if other.mounted else SEPARATION_FOOT)
			var sep := MeshUtil.flat(global_position - other.global_position)
			var sl := sep.length()
			if sl < min_sep:
				v += (sep.normalized() if sl > 0.01 else facing.cross(Vector3.UP)) * (min_sep - sl) * 8.0
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	rotation.y = atan2(-facing.x, -facing.z)
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	# Visuales
	var sy := _rider_root.position.y
	_shield.position = Vector3(-0.25, 1.1, -0.55) if blocking else Vector3(-0.5, 1.0, 0.0)
	_shield.rotation.y = -PI / 2.0 if blocking else 0.0
	if _flash > 0.0:
		_flash -= delta
	var bc := color
	if _flash > 0.0:
		bc = Color.WHITE
	elif exhausted > 0.0:
		bc = color.lerp(Color(0.5, 0.5, 0.5), 0.6)
	(_body.material_override as StandardMaterial3D).albedo_color = bc
	if dash_time > 0.0 and not mounted:
		_rider_root.rotation.x = -TAU * (1.0 - dash_time / maxf(st.dash_duration, 0.01)) # voltereta
	else:
		_rider_root.rotation.x = 0.0
	_rider_root.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2 if stun > 0.0 else 0.0
	_rider_root.position.y = sy

func _lock_valid() -> bool:
	return is_instance_valid(face_target) and bool(face_target.get("alive"))

static func _turn_toward(from: Vector3, to: Vector3, max_step: float) -> Vector3:
	var ang := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(ang, -max_step, max_step)).normalized()

func _check_dash_hit() -> void:
	if _dash_hit:
		return
	for t in MeshUtil.enemies_of(get_tree(), team):
		var d := MeshUtil.flat(t.global_position - global_position)
		if d.length() < 2.9 and (d.length() < 0.5 or dash_dir.dot(d.normalized()) > 0.3):
			_dash_hit = true
			var res: String = t.take_hit(DASH_DAMAGE, self, "dash")
			if res == "hit" or res == "block":
				if t.has_method("apply_knockback"):
					t.apply_knockback(dash_dir * DASH_KNOCKBACK * (0.5 if res == "block" else 1.0), res == "hit")
				if res == "hit":
					add_meter(6.0)
					if t is Fighter and (t as Fighter).mounted and randf() < (t as Fighter).knockoff_chance_dash:
						(t as Fighter).dismount(true)
				impact.emit(1.0)
				dash_time = minf(dash_time, 0.05)
			return

func apply_knockback(v: Vector3, stagger: bool = true) -> void:
	knock = MeshUtil.flat(v)
	if stagger:
		apply_stun(0.25)
	impact.emit(0.8)

## Telegrafía: true durante la anticipación de un ataque.
func is_attacking() -> bool:
	return atk_state == Atk.WINDUP

func is_swapping() -> bool:
	return swap_t > 0.0

func swap_progress() -> float:
	return 1.0 - swap_t / SWAP_TIME if swap_t > 0.0 else 0.0

func in_recovery() -> bool:
	return atk_state == Atk.RECOVERY

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.6 if mounted else 1.0, 0)

func add_meter(v: float) -> void:
	meter = clampf(meter + v, 0.0, METER_MAX)
	meter_changed.emit(meter)

func _can_act() -> bool:
	return alive and stun <= 0.0 and exhausted <= 0.0

## ¿Está t dentro del arco de la espada?
func in_sword_arc(t: Node3D) -> bool:
	var d := MeshUtil.flat(t.global_position - global_position)
	var hr: float = t.get("hit_radius")
	if d.length() - hr * 0.5 > sword_range():
		return false
	if d.length() < 0.5:
		return true
	return absf(facing.signed_angle_to(d.normalized(), Vector3.UP)) <= sword_half_arc()

## Compatibilidad: sword() = ataque ligero.
func sword() -> bool:
	return attack_light()

func attack_light() -> bool:
	return _request_attack(false)

func attack_heavy() -> bool:
	return _request_attack(true)

func _atk_data() -> Dictionary:
	return HEAVY if atk_heavy else LIGHT

func _request_attack(heavy: bool) -> bool:
	if loadout != Loadout.SWORD_SHIELD or not _can_act() or swap_t > 0.0:
		return false
	if atk_state != Atk.NONE:
		# Búfer de entrada para encadenar ligeros
		if not heavy and not atk_heavy and combo < MAX_COMBO and (atk_state != Atk.WINDUP or atk_t > atk_dur * 0.5):
			_buffered = true
		return false
	if blocking or stamina <= 0.0:
		return false
	combo = 1
	_start_attack(heavy, false)
	return true

func _start_attack(heavy: bool, chained: bool) -> void:
	atk_heavy = heavy
	var d := _atk_data()
	atk_state = Atk.WINDUP
	atk_t = 0.0
	atk_dur = d["chain_windup"] if chained else d["windup"]
	_atk_landed = false
	_atk_hit.clear()
	_buffered = false
	attacks_started += 1
	spend_stamina(d["stamina"])
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt and global_position.distance_to(tgt.global_position) < sword_range() + 1.5:
		var dd := MeshUtil.flat(tgt.global_position - global_position)
		if dd.length() > 0.1 and facing.dot(dd.normalized()) > 0.0:
			facing = dd.normalized()
	# Telegrafía: hoja alzada y brillante
	_sword_pivot.rotation = Vector3(1.4 if heavy else 1.0, sword_half_arc(), 0)
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1.0, 0.45, 0.1) if heavy else Color(1.0, 0.9, 0.4)
	_blade_mat.emission_energy_multiplier = 3.0

func _cancel_attack() -> void:
	atk_state = Atk.NONE
	combo = 0
	_buffered = false
	_blade_mat.emission_enabled = false
	_sword_pivot.rotation = Vector3.ZERO

func _update_attack(delta: float) -> void:
	if atk_state == Atk.NONE:
		return
	atk_t += delta
	var d := _atk_data()
	match atk_state:
		Atk.WINDUP:
			if atk_t >= atk_dur:
				atk_state = Atk.ACTIVE
				atk_t = 0.0
				atk_dur = d["active"]
				_blade_mat.emission_enabled = false
				var half := sword_half_arc()
				var tw := create_tween()
				tw.tween_property(_sword_pivot, "rotation", Vector3(0, -half, 0), atk_dur)
				var arc := MeshUtil.arc(self, 0.6, sword_range(), half, _rider_root.position.y + 1.0, Color(1, 0.6, 0.3) if atk_heavy else Color(1, 1, 0.85))
				var tw2 := arc.create_tween()
				tw2.tween_property(arc, "transparency", 1.0, 0.3)
				tw2.tween_callback(arc.queue_free)
				_strike_frame(d)
		Atk.ACTIVE:
			_strike_frame(d)
			if atk_t >= atk_dur:
				atk_state = Atk.RECOVERY
				atk_t = 0.0
				atk_dur = d["recovery"] + (0.0 if _atk_landed else d["whiff"])
				if combo >= MAX_COMBO:
					atk_dur += FINISHER_EXTRA_RECOVERY
		Atk.RECOVERY:
			if _buffered and combo < MAX_COMBO and atk_t >= CHAIN_MIN_RECOVERY and stamina > 0.0 and exhausted <= 0.0 and stun <= 0.0:
				combo += 1
				_start_attack(false, true)
				return
			if atk_t >= atk_dur:
				_cancel_attack()

func _strike_frame(d: Dictionary) -> void:
	if not alive:
		return
	for t in MeshUtil.enemies_of(get_tree(), team):
		if t in _atk_hit or not in_sword_arc(t):
			continue
		_atk_hit.append(t)
		var was_open: bool = t is Fighter and ((t as Fighter).in_recovery() or (t as Fighter).stun > 0.0)
		var res: String = t.take_hit(d["damage"], self, "melee")
		if res == "hit" or res == "block" or res == "parry":
			_atk_landed = true
		if res == "hit":
			add_meter(18.0 if atk_heavy else 12.0)
		elif res == "block":
			add_meter(3.0)
		landed_hit.emit(t, res, was_open)

# ---------------- Armas: espada+escudo O arco ----------------

func swap_loadout() -> bool:
	if not alive or swap_t > 0.0 or atk_state != Atk.NONE or stun > 0.0:
		return false
	swap_t = SWAP_TIME
	blocking = false
	_sword_pivot.visible = false
	_shield.visible = false
	_bow.visible = false
	return true

func _apply_loadout_visuals() -> void:
	var sw := loadout == Loadout.SWORD_SHIELD
	_sword_pivot.visible = sw
	_shield.visible = sw
	_bow.visible = not sw

func shoot() -> bool:
	if loadout != Loadout.BOW or swap_t > 0.0 or atk_state != Atk.NONE:
		return false
	if not _can_act() or bow_cd > 0.0 or stamina <= 0.0:
		return false
	bow_cd = BOW_COOLDOWN
	spend_stamina(COST_BOW)
	var origin := get_hit_center() + Vector3(0, 0.8, 0) + facing * 1.4
	var dir := facing
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var d: Vector3 = tgt.get_hit_center() - origin
		if MeshUtil.flat(d).normalized().dot(facing) > -0.2:
			dir = d.normalized()
	var p := Projectile.new()
	p.team = team
	p.shooter = self
	p.direction = dir
	p.damage = 8.0
	p.color = Color(0.9, 0.8, 0.5)
	get_parent().add_child(p)
	p.global_position = origin
	return true

## Dash montado / voltereta a pie.
func dash() -> bool:
	if not _can_act() or dash_cd > 0.0 or stamina <= 0.0:
		return false
	if atk_state != Atk.NONE:
		# Compromiso: solo se puede cancelar con voltereta al final de la recuperación
		if atk_state == Atk.RECOVERY and atk_t >= atk_dur * ROLL_CANCEL_FRACTION:
			_cancel_attack()
		else:
			return false
	var st := stats()
	dash_cd = st.dash_cooldown
	dash_time = st.dash_duration
	invuln = st.dash_iframes
	_dash_hit = false
	spend_stamina(COST_DASH if mounted else COST_ROLL)
	var mi := MeshUtil.flat(move_input)
	dash_dir = mi.normalized() if mi.length() > 0.2 else facing
	return true

func summon() -> bool:
	if not alive or stun > 0.0 or eikon == null or meter < METER_MAX:
		return false
	if is_instance_valid(active_eikon):
		return false
	var e := Eikon.new()
	e.data = eikon
	e.team = team
	e.owner_fighter = self
	get_parent().add_child(e)
	e.global_position = global_position + facing.cross(Vector3.UP) * 3.0 + Vector3(0, 0.2, 0)
	active_eikon = e
	meter = 0.0
	meter_changed.emit(meter)
	summoned.emit(e)
	return true

func apply_stun(t: float) -> void:
	stun = maxf(stun, t)
	if atk_state != Atk.NONE:
		_cancel_attack()

## Devuelve "hit", "block", "parry", "dodge" o "none".
func take_hit(amount: float, from: Node3D, _kind: String) -> String:
	if not alive:
		return "none"
	if invuln > 0.0:
		return "dodge"
	var frontal := true
	if is_instance_valid(from):
		var d := MeshUtil.flat(from.global_position - global_position)
		if d.length() > 0.1:
			frontal = facing.dot(d.normalized()) > 0.0
	if blocking and frontal:
		if block_time <= PARRY_WINDOW and exhausted <= 0.0:
			if from is Fighter and _kind == "melee":
				(from as Fighter).apply_stun(PARRY_STAGGER)
				(from as Fighter).riposte_t = PARRY_STAGGER
			add_meter(15.0)
			return "parry"
		_damage(amount * (EXHAUSTED_BLOCK_REDUCTION if exhausted > 0.0 else BLOCK_REDUCTION))
		spend_stamina(COST_BLOCKED_HIT)
		add_meter(3.0)
		return "block"
	if riposte_t > 0.0 and _kind == "melee":
		amount *= RIPOSTE_MULT # riposte tras parry
		riposte_t = 0.0
	_damage(amount)
	add_meter(5.0)
	if _kind == "melee":
		impact.emit(0.5)
	# Poise / hit-stun: intercambiar golpes no sale gratis
	_since_hit = 0.0
	poise -= amount * 2.0
	if poise <= 0.0:
		poise = POISE_MAX
		apply_stun(0.6 + (0.3 if amount >= HEAVY_HIT else 0.0))
	elif atk_state == Atk.WINDUP and not atk_heavy:
		apply_stun(0.2) # los ligeros se interrumpen; el fuerte tiene súper-armadura
	if mounted and alive and amount >= HEAVY_HIT and randf() < knockoff_chance_heavy:
		dismount(true)
	return "hit"

func _damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	_flash = 0.12
	health_changed.emit(health, max_health)
	if health <= 0.0 and alive:
		alive = false
		died.emit(self)

func dismiss_eikon() -> void:
	if is_instance_valid(active_eikon):
		active_eikon.queue_free()
	active_eikon = null

func reset_for_round(pos: Vector3, face: Vector3) -> void:
	dismiss_eikon()
	if not mounted and owned_mount:
		if not owned_mount.is_free() and owned_mount.rider:
			owned_mount.rider.dismount(false)
		owned_mount.global_position = pos
		mount_on(owned_mount)
	global_position = pos
	facing = face.normalized()
	rotation.y = atan2(-facing.x, -facing.z)
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	velocity = Vector3.ZERO
	planar_vel = Vector3.ZERO
	knock = Vector3.ZERO
	invuln = 0.0
	dash_time = 0.0
	health = max_health
	meter = 0.0
	stamina = STAMINA_MAX
	exhausted = 0.0
	alive = true
	stun = 0.0
	_cancel_attack()
	poise = POISE_MAX
	riposte_t = 0.0
	if swap_t > 0.0 or loadout != Loadout.SWORD_SHIELD:
		swap_t = 0.0
		loadout = Loadout.SWORD_SHIELD
		_apply_loadout_visuals()
		loadout_changed.emit(loadout)
	bow_cd = 0.0
	dash_cd = 0.0
	health_changed.emit(health, max_health)
	meter_changed.emit(meter)
	stamina_changed.emit(stamina, false)
