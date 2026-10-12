class_name Fighter
extends CharacterBody3D
## Luchador montado. Los controladores (jugador/IA) rellenan move_input/want_block
## y llaman a sword()/shoot()/summon()/dash().
## Cualquier nodo en el grupo "damageable" con team, alive, take_hit() y
## get_hit_center() puede ser objetivo (eikons ahora, mobs en el futuro).

signal health_changed(value: float, max_value: float)
signal meter_changed(value: float)
signal died(fighter: Fighter)
signal summoned(eikon: Node3D)

const METER_MAX := 100.0
const GRAVITY := 20.0
const SWORD_DAMAGE := 12.0
const SWORD_RANGE := 3.6
const SWORD_COOLDOWN := 0.7
const SWORD_WINDUP := 0.18
const BOW_COOLDOWN := 1.0
const PARRY_WINDOW := 0.25
const BLOCK_REDUCTION := 0.2

@export var mount: MountData
@export var eikon: EikonData
var team: int = 0
var color: Color = Color(0.2, 0.4, 1.0)
var display_name: String = "Jugador"
var opponent: Fighter

var max_health: float = 100.0
var health: float = 100.0
var meter: float = 0.0
var alive: bool = true
var hit_radius: float = 1.3

# Entrada de los controladores
var move_input: Vector3 = Vector3.ZERO
var want_block: bool = false

var facing: Vector3 = Vector3.FORWARD
var speed: float = 0.0
var blocking: bool = false
var block_time: float = 0.0
var stun: float = 0.0
var sword_cd: float = 0.0
var sword_windup: float = -1.0
var bow_cd: float = 0.0
var dash_time: float = 0.0
var dash_cd: float = 0.0
var active_eikon: Node3D = null

var _sword_pivot: Node3D
var _shield: MeshInstance3D
var _rider: MeshInstance3D
var _flash: float = 0.0

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("fighter")
	if mount == null:
		mount = load("res://resources/mounts/horse.tres")
	max_health = 100.0 + mount.health_bonus
	health = max_health
	_build_visuals()

func _build_visuals() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 2.4, 2.4)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	add_child(col)
	var mc := mount.color
	MeshUtil.box(self, Vector3(0.9, 0.9, 2.0), Vector3(0, 1.3, 0), mc)
	MeshUtil.box(self, Vector3(0.5, 0.9, 0.6), Vector3(0, 1.9, -1.1), mc)
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.75, 0.75]:
			MeshUtil.cylinder(self, 0.1, 1.0, Vector3(x, 0.5, z), mc.darkened(0.3))
	_rider = MeshUtil.box(self, Vector3(0.6, 1.0, 0.45), Vector3(0, 2.3, 0.1), color)
	MeshUtil.sphere(self, 0.25, Vector3(0, 3.05, 0.1), Color(0.95, 0.8, 0.65))
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.45, 2.4, 0.0)
	add_child(_sword_pivot)
	MeshUtil.box(_sword_pivot, Vector3(0.08, 0.08, 1.4), Vector3(0, 0, -0.7), Color(0.85, 0.85, 0.9))
	_shield = MeshUtil.box(self, Vector3(0.1, 0.8, 0.8), Vector3(-0.5, 2.3, 0.0), color.darkened(0.3))

func _physics_process(delta: float) -> void:
	sword_cd = maxf(sword_cd - delta, 0.0)
	bow_cd = maxf(bow_cd - delta, 0.0)
	dash_cd = maxf(dash_cd - delta, 0.0)
	dash_time = maxf(dash_time - delta, 0.0)
	stun = maxf(stun - delta, 0.0)
	var inp := move_input
	if not alive or stun > 0.0:
		inp = Vector3.ZERO
	var wb := want_block and alive and stun <= 0.0
	if wb and not blocking:
		block_time = 0.0
	blocking = wb
	if blocking:
		block_time += delta
	if sword_windup > 0.0:
		sword_windup -= delta
		if sword_windup <= 0.0:
			_sword_strike()
	# Giro hacia la dirección deseada
	inp.y = 0.0
	var amount := minf(inp.length(), 1.0)
	if amount > 0.1:
		var ang := facing.signed_angle_to(inp.normalized(), Vector3.UP)
		var step := clampf(ang, -mount.turn_speed * delta, mount.turn_speed * delta)
		facing = facing.rotated(Vector3.UP, step).normalized()
	var target_speed := mount.speed * amount * (0.45 if blocking else 1.0)
	speed = move_toward(speed, target_speed, mount.acceleration * delta)
	var v := facing * speed
	if dash_time > 0.0:
		v = facing * mount.dash_speed
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	rotation.y = atan2(-facing.x, -facing.z)
	# Visuales
	_shield.position = Vector3(-0.25, 2.4, -0.55) if blocking else Vector3(-0.5, 2.3, 0.0)
	_shield.rotation.y = -PI / 2.0 if blocking else 0.0
	if _flash > 0.0:
		_flash -= delta
		(_rider.material_override as StandardMaterial3D).albedo_color = Color.WHITE if _flash > 0.0 else color
	if stun > 0.0:
		_rider.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2
	else:
		_rider.rotation.z = 0.0

func is_attacking() -> bool:
	return sword_windup > 0.0

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)

func add_meter(v: float) -> void:
	meter = clampf(meter + v, 0.0, METER_MAX)
	meter_changed.emit(meter)

func _can_act() -> bool:
	return alive and stun <= 0.0

func sword() -> bool:
	if not _can_act() or sword_cd > 0.0 or blocking:
		return false
	sword_cd = SWORD_COOLDOWN
	sword_windup = SWORD_WINDUP
	# Apuntado suave hacia el enemigo cercano
	var tgt := MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt and global_position.distance_to(tgt.global_position) < SWORD_RANGE + 1.5:
		var d := MeshUtil.flat(tgt.global_position - global_position)
		if d.length() > 0.1 and facing.dot(d.normalized()) > 0.0:
			facing = d.normalized()
	var tw := create_tween()
	_sword_pivot.rotation = Vector3(0, 0.9, 0)
	tw.tween_property(_sword_pivot, "rotation", Vector3(0, -1.2, 0), SWORD_WINDUP + 0.1)
	tw.tween_property(_sword_pivot, "rotation", Vector3.ZERO, 0.2)
	return true

func _sword_strike() -> void:
	if not alive:
		return
	for t in MeshUtil.enemies_of(get_tree(), team):
		var d := MeshUtil.flat(t.global_position - global_position)
		if d.length() < SWORD_RANGE + t.hit_radius * 0.5 and (d.length() < 0.5 or facing.dot(d.normalized()) > 0.3):
			var res: String = t.take_hit(SWORD_DAMAGE, self, "melee")
			if res == "hit":
				add_meter(12.0)
			elif res == "block":
				add_meter(3.0)

func shoot() -> bool:
	if not _can_act() or bow_cd > 0.0 or blocking:
		return false
	bow_cd = BOW_COOLDOWN
	var origin := global_position + Vector3(0, 2.4, 0) + facing * 1.4
	var dir := facing
	var tgt := MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
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

func dash() -> bool:
	if not _can_act() or dash_cd > 0.0:
		return false
	dash_cd = mount.dash_cooldown
	dash_time = mount.dash_duration
	return true

func summon() -> bool:
	if not _can_act() or eikon == null or meter < METER_MAX:
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
	sword_windup = -1.0

## Devuelve "hit", "block", "parry" o "none".
func take_hit(amount: float, from: Node3D, _kind: String) -> String:
	if not alive:
		return "none"
	var frontal := true
	if is_instance_valid(from):
		var d := MeshUtil.flat(from.global_position - global_position)
		if d.length() > 0.1:
			frontal = facing.dot(d.normalized()) > 0.0
	if blocking and frontal:
		if block_time <= PARRY_WINDOW:
			if from is Fighter and _kind == "melee":
				(from as Fighter).apply_stun(1.0)
			add_meter(15.0)
			return "parry"
		_damage(amount * BLOCK_REDUCTION)
		add_meter(3.0)
		return "block"
	_damage(amount)
	add_meter(5.0)
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
	global_position = pos
	facing = face.normalized()
	rotation.y = atan2(-facing.x, -facing.z)
	velocity = Vector3.ZERO
	speed = 0.0
	health = max_health
	meter = 0.0
	alive = true
	stun = 0.0
	sword_windup = -1.0
	sword_cd = 0.0
	bow_cd = 0.0
	dash_cd = 0.0
	health_changed.emit(health, max_health)
	meter_changed.emit(meter)
