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
## Ronda 16: autoapuntado = SOLO APUNTAR. Al disparar se apunta a la posición actual del
## objetivo (ver Projectile.aim_dir) y el proyectil vuela RECTO, sin perseguir: correr de lado a
## distancia lo esquiva. Durante los i-frames de la voltereta lo atraviesa (take_hit = "dodge").
var aimed_at: Node3D = null ## a quién se apuntó al disparar (solo informativo)
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

## Dirección de disparo hacia `tgt` desde `origin`. lead (0..1) = fracción del adelanto
## perfecto según la velocidad actual del objetivo (0 = apunta a donde está ahora).
static func aim_dir(origin: Vector3, tgt: Node3D, speed: float, lead: float = 0.0) -> Vector3:
	var aim: Vector3 = tgt.get_hit_center()
	if lead > 0.0 and tgt is CharacterBody3D:
		var tv := MeshUtil.flat((tgt as CharacterBody3D).velocity)
		aim += tv * (origin.distance_to(aim) / maxf(speed, 1.0)) * lead
	return (aim - origin).normalized()
