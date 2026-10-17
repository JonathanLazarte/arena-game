class_name Eikon
extends CharacterBody3D
## Invocación temporal que lucha junto a su dueño (eikons NO montables: el gólem). Es un objetivo dañable.
## Los eikons montables (fénix, lobo, grifo) son monturas: ver Mount y Fighter._summon_mount().

var data: EikonData
var team: int = 0
var owner_fighter: Fighter
var health: float = 60.0
var alive: bool = true
var hit_radius: float = 1.0
var life: float = 15.0
var attack_cd: float = 0.5
var _body: Node3D

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("eikon")
	health = data.max_health
	life = data.duration
	hit_radius = 0.9 * data.size
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.8 * data.size
	col.shape = sh
	col.position = Vector3(0, 0.8 * data.size, 0)
	add_child(col)
	_body = Node3D.new()
	_body.scale = Vector3.ONE * data.size
	add_child(_body)
	_build_model()

## Modelos Quaternius (CC0): lobo, dragón recoloreado como fénix y Giant
## (Ultimate Monsters) convertido en gólem de piedra: tinte gris roca y rocas
## de Quaternius enganchadas a hombros y espalda (BoneAttachment3D).
const MODELS := {
	EikonData.AttackKind.MELEE: ["res://assets/models/wolf_quaternius.glb", 0.55, "Gallop", "Idle", "Attack", 0.0],
	EikonData.AttackKind.RANGED: ["res://assets/models/dragon_quaternius.glb", 0.8, "CharacterArmature|Fast_Flying", "CharacterArmature|Flying_Idle", "CharacterArmature|Headbutt", 0.0],
}
const GA := "EnemyArmature|EnemyArmature|EnemyArmature|"
const GOLEM := ["res://assets/models/giant_quaternius.glb", 0.9, GA + "Walk", GA + "Idle", GA + "Attack", 0.0]
const ROCK := "res://assets/models/rock_large_quaternius.glb"
## [hueso, posición, escala, rotación Y] de cada roca del gólem (espacio del hueso)
const GOLEM_ROCKS := [["Arm.L", Vector3(-0.25, 0.25, 0.05), 1.0, 0.0], ["Arm.R", Vector3(0.25, 0.25, 0.05), 1.0, 1.7],
	["Body", Vector3(0, 0.9, 0.5), 1.5, 0.8], ["Body", Vector3(0.3, 0.4, 0.55), 0.9, 2.2],
	["Arm.L_end", Vector3(0, 0, 0), 0.6, 2.0], ["Arm.R_end", Vector3(0, 0, 0), 0.6, 3.1]]
const GOLEM_EYES := Vector3(0, 0.28, -0.42)
var _rocks: Array = []
var _skel: Skeleton3D
var preview: bool = false ## sin dueño ni IA (vistas previas)
var _ap: AnimationPlayer
var _anims: Array = []
var _attack_anim_t: float = 0.0

func _build_model() -> void:
	var cfg: Array = MODELS.get(data.attack_kind, GOLEM)
	var m := ResCache.scene(cfg[0]).instantiate() as Node3D
	m.basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * float(cfg[1]))
	m.position.y = cfg[5]
	_body.add_child(m)
	match data.attack_kind:
		EikonData.AttackKind.RANGED:
			AnimUtil.tint_surfaces(m, data.color, 0.75, 1.2) # fénix: tonos de fuego emisivos
		EikonData.AttackKind.MELEE:
			AnimUtil.tint_surfaces(m, data.color, 0.55)
		_:
			_add_golem_rocks(m)
	_ap = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anims = [cfg[2], cfg[3], cfg[4]]
	AnimUtil.set_loops(_ap, [cfg[2], cfg[3]])
	_ap.play(cfg[3])

func _add_golem_rocks(m: Node3D) -> void:
	var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	# Piedra: sin la textura de colores del gigante, gris con ruido y ojos de lava
	var stone := StandardMaterial3D.new()
	stone.albedo_color = data.color
	var noise := NoiseTexture2D.new()
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.08
	noise.color_ramp = Gradient.new()
	noise.color_ramp.set_color(0, Color(0.55, 0.55, 0.55))
	noise.color_ramp.set_color(1, Color(1, 1, 1))
	stone.albedo_texture = noise
	stone.uv1_triplanar = true
	stone.uv1_world_triplanar = true
	stone.uv1_scale = Vector3.ONE * 0.6
	stone.roughness = 1.0
	for mi in AnimUtil.meshes(m):
		mi.material_override = stone
	_skel = sk
	var rock_scene := ResCache.scene(ROCK)
	for r: Array in GOLEM_ROCKS:
		var rock := rock_scene.instantiate() as Node3D
		var dark := stone.duplicate() as StandardMaterial3D
		dark.albedo_color = data.color.darkened(0.3)
		for mi in AnimUtil.meshes(rock):
			mi.material_override = dark
		_add_follower(rock, r)
	var eyes := Node3D.new()
	for x: float in [-0.13, 0.13]:
		var e := MeshUtil.box(eyes, Vector3(0.16, 0.09, 0.08), Vector3(x, 0.0, 0.0), Color(1.0, 0.45, 0.1))
		e.material_override = MeshUtil.mat(Color(1.0, 0.45, 0.1), true)
	_add_follower(eyes, ["Head", GOLEM_EYES, 0.0, 0.0])
	_rocks[-1].append(true) # los ojos no se estiran
	_follow_bones()

## Las rocas no cuelgan del esqueleto (el rig de Quaternius va a escala 100):
## son hijas del gólem y cada frame se colocan en la posición del hueso, en metros.
func _add_follower(n: Node3D, r: Array) -> void:
	add_child(n)
	n.top_level = true
	n.global_basis = Basis.IDENTITY
	var len := 1.0
	for mi in AnimUtil.meshes(n):
		len = maxf(mi.get_aabb().get_longest_axis_size() * mi.global_basis.get_scale().x, 0.01)
	var sz := float(r[2]) * data.size
	var k := sz / len if sz > 0.0 else data.size
	_rocks.append([n, _skel.find_bone(r[0]), r[1], k, float(r[3])])

func _follow_bones() -> void:
	if _skel == null or not is_inside_tree():
		return
	var gb := global_basis.orthonormalized()
	for e: Array in _rocks:
		if e[1] < 0:
			continue
		var bp: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(e[1]).origin
		(e[0] as Node3D).global_transform = Transform3D(gb * Basis(Vector3.UP, e[4]) * Basis.from_scale((Vector3.ONE if e.size() > 5 else Vector3(1.0, 1.7, 1.0)) * float(e[3])),
			bp + gb * ((e[2] as Vector3) * data.size))

func _process(_delta: float) -> void:
	_follow_bones()

func _update_anim(delta: float, moving: bool) -> void:
	_attack_anim_t -= delta
	if _attack_anim_t > 0.0:
		return
	var want: String = _anims[0] if moving else _anims[1]
	if _ap.current_animation != want:
		_ap.play(want, 0.2)

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.0 * data.size, 0)

## Fase 8: títere visual (SimWorld lo coloca y anima); sin lógica de combate.
func _physics_process(delta: float) -> void:
	_update_anim(delta, false)
