class_name GroundWave
extends Node3D

var team: int = 0
var source: Node3D
var direction: Vector3 = Vector3.FORWARD
var speed: float = 15.0
var max_range: float = 16.0
var width: float = 1.8
var damage: float = 18.0
var stun_force: float = StunRules.AOE_FORCE
var warn: float = 0.45
var knock: float = 6.0
var travelled: float = 0.0
var t: float = 0.0
var hit_list: Array = []
var results: Dictionary = {}
var _crest: MeshInstance3D
var _line: MeshInstance3D

static func spawn(parent: Node, src: Node3D, tm: int, origin: Vector3, dir: Vector3, spd: float, rng: float, w: float, dmg: float, force: float, warn_t: float) -> GroundWave:
	var a := GroundWave.new()
	a.source = src
	a.team = tm
	a.direction = MeshUtil.flat(dir).normalized()
	a.speed = spd
	a.max_range = rng
	a.width = w
	a.damage = dmg
	a.stun_force = force
	a.warn = warn_t
	parent.add_child(a)
	a.global_position = Vector3(origin.x, 0.0, origin.z)
	return a

func _ready() -> void:
	add_to_group("ground_wave")
	rotation.y = atan2(-direction.x, -direction.z)
	_line = MeshUtil.box(self, Vector3(width, 0.02, max_range), Vector3(0, 0.05, -max_range * 0.5), Color(1.0, 0.3, 0.15))
	_line.transparency = 0.7
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crest = MeshUtil.box(self, Vector3(width, 0.9, 0.5), Vector3(0, 0.45, 0), Color(1.0, 0.45, 0.1))
	_crest.material_override = MeshUtil.mat(Color(1.0, 0.45, 0.1), true)
	_crest.visible = false

func _physics_process(delta: float) -> void:
	t += delta
	if t < warn:
		_line.transparency = lerpf(0.8, 0.35, t / maxf(warn, 0.01))
		return
	if not _crest.visible:
		_crest.visible = true
		_line.visible = false
	var step := speed * delta
	global_position += direction * step
	travelled += step
	var p := global_position
	if travelled >= max_range or Vector2(p.x, p.z).length() > Projectile.arena_radius:
		queue_free()
		return
	for o in Projectile.obstacles:
		if Vector2(p.x - o.x, p.z - o.z).length() < o.y:
			queue_free()
			return
	var side_dir := direction.cross(Vector3.UP)
	for n in MeshUtil.enemies_of(get_tree(), team):
		if n in hit_list:
			continue
		var rel := MeshUtil.flat(n.global_position - p)
		var hr: float = n.get("hit_radius") if n.get("hit_radius") != null else 0.75
		if absf(rel.dot(direction)) > 0.6 + hr * 0.5 + step:
			continue
		if absf(rel.dot(side_dir)) > width * 0.5 + hr * 0.5:
			continue
		hit_list.append(n)
		if not GroundAoE.grounded(n):
			results[n] = "air"
			if n is Fighter:
				(n as Fighter).aoe_jumped += 1
			continue
		if n is Fighter:
			(n as Fighter).incoming_stun_force = stun_force
		var res: String = n.take_hit(damage, source if is_instance_valid(source) else self, "aoe")
		if n is Fighter:
			(n as Fighter).incoming_stun_force = -1.0
		results[n] = res
		if res == "hit" and n is Fighter:
			var f := n as Fighter
			f.apply_knockback(direction * knock, false)
