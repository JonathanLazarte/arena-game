class_name Mount
extends CharacterBody3D
## Montura independiente del jinete. Cuando lleva jinete sigue su transform;
## sin jinete se queda cerca de donde la dejaron y pasea un poco.
## Cualquier jinete (jugador, IA, futuros mobs) puede montar cualquier montura libre.

var data: MountData
var rider: Fighter = null
var home: Vector3 = Vector3.ZERO
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _col: CollisionShape3D

func _ready() -> void:
	add_to_group("mount")
	if data == null:
		data = load("res://resources/mounts/horse.tres")
	collision_layer = 4
	collision_mask = 1
	_col = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 1.8, 2.2)
	_col.shape = sh
	_col.position = Vector3(0, 0.9, 0)
	add_child(_col)
	var mc := data.color
	MeshUtil.box(self, Vector3(0.9, 0.9, 2.0), Vector3(0, 1.3, 0), mc)
	MeshUtil.box(self, Vector3(0.5, 0.9, 0.6), Vector3(0, 1.9, -1.1), mc)
	MeshUtil.box(self, Vector3(0.95, 0.15, 0.7), Vector3(0, 1.8, 0.1), Color(0.35, 0.15, 0.1)) # silla
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.75, 0.75]:
			MeshUtil.cylinder(self, 0.1, 1.0, Vector3(x, 0.5, z), mc.darkened(0.3))

func is_free() -> bool:
	return rider == null

func set_rider(r: Fighter) -> void:
	rider = r
	_col.disabled = r != null
	if r == null:
		home = global_position
		_wander_t = 1.0

func _physics_process(delta: float) -> void:
	if rider != null:
		return
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.5, 3.0)
		var to_home := MeshUtil.flat(home - global_position)
		if to_home.length() > 3.0:
			_wander_dir = to_home.normalized()
		elif randf() < 0.5:
			_wander_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		else:
			_wander_dir = Vector3.ZERO
	var v := _wander_dir * 1.5
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if v.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), delta * 3.0)
