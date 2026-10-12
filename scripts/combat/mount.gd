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
	_build_model()

const HORSE := preload("res://assets/models/horse_quaternius.glb")
const HORSE_SCALE := 0.62
var model: Node3D
var tree: AnimationTree
var _last_pos: Vector3
var speed_now: float = 0.0

## Caballo Quaternius (CC0). AnimationTree: BlendSpace1D Idle/Walk/Gallop por velocidad.
func _build_model() -> void:
	model = HORSE.instantiate() as Node3D
	# El glTF mira a +Z: lo giramos para que mire a -Z (frente del juego)
	model.basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * HORSE_SCALE)
	add_child(model)
	if data.mount_name != "Caballo":
		AnimUtil.tint_surfaces(model, data.color, 0.5)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	AnimUtil.set_loops(ap, ["Idle", "Walk", "Gallop"])
	var bs := AnimationNodeBlendSpace1D.new()
	bs.add_blend_point(AnimUtil.anim_node("Idle"), 0.0, -1, &"Idle")
	bs.add_blend_point(AnimUtil.anim_node("Walk"), 0.3, -1, &"Walk")
	bs.add_blend_point(AnimUtil.anim_node("Gallop"), 1.0, -1, &"Gallop")
	bs.min_space = 0.0
	bs.max_space = 1.3
	tree = AnimationTree.new()
	tree.tree_root = bs
	model.add_child(tree)
	tree.root_node = NodePath("..")
	tree.anim_player = tree.get_path_to(ap)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.active = true
	_last_pos = global_position

func _update_anim(delta: float) -> void:
	var d := MeshUtil.flat(global_position - _last_pos).length() / maxf(delta, 0.001)
	_last_pos = global_position
	speed_now = lerpf(speed_now, d, clampf(delta * 8.0, 0.0, 1.0))
	tree.set("parameters/blend_position", speed_now / maxf(data.speed, 0.1))

func is_free() -> bool:
	return rider == null

func set_rider(r: Fighter) -> void:
	rider = r
	_col.disabled = r != null
	if r == null:
		home = global_position
		_wander_t = 1.0

func _physics_process(delta: float) -> void:
	_update_anim(delta)
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
