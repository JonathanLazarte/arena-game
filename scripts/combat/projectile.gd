class_name Projectile
extends Node3D
## Proyectil simple (flecha, bola de fuego). Detección por distancia, sin física.

static var obstacles: Array[Vector3] = [] ## centros de pilares (x, radio, z)
static var arena_radius: float = 42.0

var direction: Vector3 = Vector3.FORWARD
var speed: float = 32.0
var damage: float = 8.0
var team: int = 0
var shooter: Node3D
var color: Color = Color.WHITE
var life: float = 2.5
var radius: float = 0.5

func _ready() -> void:
	add_to_group("projectile")
	var m := MeshUtil.box(self, Vector3(0.08, 0.08, 1.0), Vector3.ZERO, color)
	m.material_override = MeshUtil.mat(color, true)

func _orient() -> void:
	if direction.length() > 0.01 and is_inside_tree():
		var up := Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + direction, up)

var _oriented := false

func _physics_process(delta: float) -> void:
	if not _oriented:
		_oriented = true
		_orient()
	global_position += direction * speed * delta
	life -= delta
	var p := global_position
	if life <= 0.0 or Vector2(p.x, p.z).length() > arena_radius or p.y < -1.0:
		queue_free()
		return
	for o in obstacles:
		if Vector2(p.x - o.x, p.z - o.z).length() < o.y:
			queue_free()
			return
	for t in MeshUtil.enemies_of(get_tree(), team):
		if p.distance_to(t.get_hit_center()) < radius + t.hit_radius:
			var res: String = t.take_hit(damage, shooter, "arrow")
			if res == "dodge":
				continue
			if res == "parry":
				# Reflejo: la flecha cambia de bando
				direction = -direction
				team = t.team
				shooter = t
				life = 2.0
				_orient()
				return
			if res == "hit" and shooter is Fighter and is_instance_valid(shooter):
				(shooter as Fighter).add_meter(8.0)
			queue_free()
			return
