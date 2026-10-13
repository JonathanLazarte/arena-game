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
var kind: String = "arrow" ## "arrow" (el escudo la anula) o "eikon" (el escudo deja pasar un 50 %)
## Ronda 14: autoapuntado con giro LIMITADO. El proyectil persigue a `target` girando como
## mucho turn_rate rad/s, así que un dash/voltereta lateral bien medido le hace fallar:
## - durante los i-frames lo atraviesa (take_hit = "dodge") y sigue de largo;
## - una vez que lo ha rebasado (o lo esquivó) deja de perseguirlo: no da la vuelta;
## - si te apartas pronto, gira y te alcanza (mal medido = te da).
var target: Node3D = null
var turn_rate: float = 1.6 ## rad/s
var homing_min_dist: float = 2.5 ## por debajo de esta distancia ya no corrige (no "gira en el sitio")
var lost: bool = false ## dejó de perseguir (rebasado o esquivado)
var dodged_by: Array = [] ## objetivos que lo esquivaron con i-frames (no les vuelve a golpear)

func _ready() -> void:
	add_to_group("projectile")
	if kind == "eikon":
		# Bola de fuego visible (antes era una varilla fina como una flecha)
		var core := MeshUtil.sphere(self, 0.35, Vector3.ZERO, color)
		core.material_override = MeshUtil.mat(color.lightened(0.3), true)
		var trail := MeshUtil.box(self, Vector3(0.3, 0.3, 1.2), Vector3(0, 0, 0.6), color)
		trail.material_override = MeshUtil.mat(color, true)
		trail.transparency = 0.5
	else:
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
	_home(delta)
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
		if t in dodged_by:
			continue
		if p.distance_to(t.get_hit_center()) < radius + t.hit_radius:
			var res: String = t.take_hit(damage, shooter, kind)
			if res == "dodge":
				dodged_by.append(t) # lo atraviesa durante los i-frames y sigue de largo
				if t == target:
					lost = true
				continue
			if res == "parry":
				# Reflejo: la flecha cambia de bando
				direction = -direction
				team = t.team
				shooter = t
				target = null # el reflejo no persigue
				life = 2.0
				_orient()
				return
			if res == "hit" and shooter is Fighter and is_instance_valid(shooter):
				(shooter as Fighter).add_meter(8.0)
			queue_free()
			return

func _home(delta: float) -> void:
	if lost or not is_instance_valid(target) or not bool(target.get("alive")):
		return
	var to: Vector3 = target.get_hit_center() - global_position
	var d := to.length()
	if d < 0.01:
		return
	if direction.dot(to / d) < 0.0:
		lost = true # ya lo rebasó: sigue recto
		return
	if d < homing_min_dist:
		return
	var want := to / d
	var ang := direction.angle_to(want)
	if ang < 0.0001:
		return
	var axis := direction.cross(want)
	if axis.length() < 0.0001:
		return
	direction = direction.rotated(axis.normalized(), minf(ang, turn_rate * delta)).normalized()
	_orient()
