class_name GroundAoE
extends Node3D
## Ronda 14: golpe de área EN EL SUELO. Primero se ve un anillo de aviso (telegrafía) que se
## va llenando; al detonar daña a todos los enemigos dentro del radio que estén TOCANDO EL SUELO.
## Quien esté en el aire (saltando, o montado en el fénix, que vuela) no recibe nada.
## La voltereta con i-frames también lo evita (take_hit devuelve "dodge"); el escudo deja pasar
## el 50 % (como un ataque de eikon). Úsalo así:
##   GroundAoE.spawn(parent, owner, team, centro, radio, aviso_s, daño)

## Altura (m) sobre el suelo por debajo de la cual un objetivo cuenta como "en el suelo".
const GROUND_HEIGHT := 0.35

var team: int = 0
var source: Node3D ## quien lo lanza (para take_hit)
var radius: float = 5.0
var telegraph: float = 0.6 ## s de aviso antes de detonar
var damage: float = 20.0
var stun_time: float = 0.5 ## (ronda 31: sin uso; ver stun_force)
var stun_force: float = StunRules.AOE_FORCE ## ronda 31: fuerza acumulada
var knock: float = 9.0
var hidden: bool = false ## ronda 32: sin anillo de aviso (salto con caída)
var t: float = 0.0
var detonated: bool = false
## Resultados por objetivo al detonar (pruebas / IA): nodo -> "hit", "block", "dodge", "air".
var results: Dictionary = {}
var _fill: MeshInstance3D
var _ring: MeshInstance3D
var _fill_mat: StandardMaterial3D

static func spawn(parent: Node, src: Node3D, tm: int, center: Vector3, r: float, warn: float, dmg: float, hide: bool = false) -> GroundAoE:
	var a := GroundAoE.new()
	a.hidden = hide
	a.source = src
	a.team = tm
	a.radius = r
	a.telegraph = warn
	a.damage = dmg
	parent.add_child(a)
	a.global_position = Vector3(center.x, 0.0, center.z)
	return a

func _ready() -> void:
	add_to_group("ground_aoe")
	if hidden:
		return
	# Anillo exterior fijo (borde del área) + disco interior que crece hasta el borde = cuenta atrás
	_ring = _disc(radius, 0.04, Color(1.0, 0.35, 0.15), 0.35)
	_fill = _disc(radius, 0.05, Color(1.0, 0.55, 0.2), 0.55)
	_fill_mat = _fill.material_override as StandardMaterial3D
	_fill.scale = Vector3(0.05, 1, 0.05)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.12
	tm.outer_radius = radius
	tm.rings = 48
	edge.mesh = tm
	edge.position.y = 0.06
	edge.scale = Vector3(1, 0.15, 1)
	edge.material_override = MeshUtil.mat(Color(1.0, 0.4, 0.15), true)
	add_child(edge)

func _disc(r: float, y: float, c: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.radial_segments = 48
	mi.mesh = cm
	mi.position.y = y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Tiempo que falta para detonar (s).
func time_left() -> float:
	return maxf(telegraph - t, 0.0)

func contains(p: Vector3) -> bool:
	return MeshUtil.flat(p - global_position).length() <= radius

## ¿Este objetivo cuenta como "en el suelo"? Usa is_grounded() si lo tiene (Fighter).
static func grounded(n: Node3D) -> bool:
	if n.has_method("is_grounded"):
		return n.is_grounded()
	return n.global_position.y < GROUND_HEIGHT

func _physics_process(delta: float) -> void:
	t += delta
	if not detonated:
		var k := clampf(t / maxf(telegraph, 0.01), 0.0, 1.0)
		if _fill:
			_fill.scale = Vector3(k, 1, k)
		if t >= telegraph:
			_detonate()
	else:
		if _fill_mat:
			_fill_mat.albedo_color.a = maxf(_fill_mat.albedo_color.a - delta * 2.5, 0.0)
		if t >= telegraph + 0.4:
			queue_free()

func _detonate() -> void:
	detonated = true
	var au := get_node_or_null("/root/Audio")
	if au:
		au.sfx3d("eikon_slam", global_position)
	if _fill:
		_fill.scale = Vector3.ONE
		_fill_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	for n in MeshUtil.enemies_of(get_tree(), team):
		if not contains(n.global_position):
			continue
		if not grounded(n):
			results[n] = "air" # saltó (o vuela): el golpe al suelo no le alcanza
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
			var away := MeshUtil.flat(f.global_position - global_position)
			f.apply_knockback((away.normalized() if away.length() > 0.1 else f.facing) * knock, false)
	if is_instance_valid(source) and source is Fighter:
		(source as Fighter).impact.emit(1.0)
