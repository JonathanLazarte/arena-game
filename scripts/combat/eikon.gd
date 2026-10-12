class_name Eikon
extends CharacterBody3D
## Invocación temporal que lucha junto a su dueño. Es un objetivo dañable.

var data: EikonData
var team: int = 0
var owner_fighter: Fighter
var health: float = 60.0
var alive: bool = true
var hit_radius: float = 1.0
var life: float = 15.0
var attack_cd: float = 0.5
var _body: Node3D
var _ring: MeshInstance3D

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

## Modelos Quaternius (CC0): lobo, dragón recoloreado como fénix y Goleling
## (marcador provisional del gólem: es un monstruo volador, sin clip de andar).
const MODELS := {
	EikonData.AttackKind.MELEE: ["res://assets/models/wolf_quaternius.glb", 0.55, "Gallop", "Idle", "Attack", 0.0],
	EikonData.AttackKind.RANGED: ["res://assets/models/dragon_quaternius.glb", 0.8, "CharacterArmature|Fast_Flying", "CharacterArmature|Flying_Idle", "CharacterArmature|Headbutt", 0.0],
}
const GOLEM := ["res://assets/models/goleling_evolved_quaternius.glb", 1.1, "CharacterArmature|Fast_Flying", "CharacterArmature|Flying_Idle", "CharacterArmature|Punch", 0.3]
var _ap: AnimationPlayer
var _anims: Array = []
var _attack_anim_t: float = 0.0

func _build_model() -> void:
	var cfg: Array = MODELS.get(data.attack_kind, GOLEM)
	var m := (load(cfg[0]) as PackedScene).instantiate() as Node3D
	m.basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * float(cfg[1]))
	m.position.y = cfg[5]
	_body.add_child(m)
	match data.attack_kind:
		EikonData.AttackKind.RANGED:
			AnimUtil.tint_surfaces(m, data.color, 0.75, 1.2) # fénix: tonos de fuego emisivos
		EikonData.AttackKind.MELEE:
			AnimUtil.tint_surfaces(m, data.color, 0.55)
		_:
			AnimUtil.tint_surfaces(m, data.color, 0.7)
	_ap = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anims = [cfg[2], cfg[3], cfg[4]]
	AnimUtil.set_loops(_ap, [cfg[2], cfg[3]])
	_ap.play(cfg[3])

func _update_anim(delta: float, moving: bool) -> void:
	_attack_anim_t -= delta
	if _attack_anim_t > 0.0:
		return
	var want: String = _anims[0] if moving else _anims[1]
	if _ap.current_animation != want:
		_ap.play(want, 0.2)

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.0 * data.size, 0)

func take_hit(amount: float, _from: Node3D, _kind: String) -> String:
	if not alive:
		return "none"
	health -= amount
	if health <= 0.0:
		_dismiss()
	return "hit"

func _dismiss() -> void:
	alive = false
	if is_instance_valid(owner_fighter) and owner_fighter.active_eikon == self:
		owner_fighter.active_eikon = null
	queue_free()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	life -= delta
	attack_cd -= delta
	if life <= 0.0 or not is_instance_valid(owner_fighter) or not owner_fighter.alive:
		_dismiss()
		return
	var tgt := MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	var v := Vector3.ZERO
	if tgt:
		var d := MeshUtil.flat(tgt.global_position - global_position)
		var dist := d.length()
		if dist > 0.1:
			rotation.y = atan2(-d.x, -d.z)
		if dist > data.attack_range * 0.8:
			v = d.normalized() * data.move_speed
		if dist <= data.attack_range and attack_cd <= 0.0:
			attack_cd = data.attack_cooldown
			_attack(tgt)
	velocity.x = v.x
	velocity.z = v.z
	if data.flying:
		velocity.y = (2.5 + sin(Time.get_ticks_msec() * 0.003) * 0.3 - global_position.y) * 3.0
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 20.0 * delta
	move_and_slide()
	_update_anim(delta, v.length() > 0.5)
	if _ring and is_instance_valid(_ring):
		_ring.scale += Vector3.ONE * delta * 6.0

func _attack(tgt: Node3D) -> void:
	_ap.play(_anims[2], 0.1)
	_attack_anim_t = minf(_ap.get_animation(_anims[2]).length, data.attack_cooldown)
	match data.attack_kind:
		EikonData.AttackKind.MELEE:
			tgt.take_hit(data.attack_damage, self, "eikon")
			var tw := create_tween()
			tw.tween_property(_body, "position", Vector3(0, 0, -0.6), 0.08)
			tw.tween_property(_body, "position", Vector3.ZERO, 0.15)
		EikonData.AttackKind.RANGED:
			var p := Projectile.new()
			p.team = team
			p.shooter = self
			p.damage = data.attack_damage
			p.speed = 22.0
			p.color = data.color
			p.radius = 0.7
			var origin := get_hit_center()
			p.direction = (tgt.get_hit_center() - origin).normalized()
			get_parent().add_child(p)
			p.global_position = origin
		_:
			for t in MeshUtil.enemies_of(get_tree(), team):
				if MeshUtil.flat(t.global_position - global_position).length() <= data.attack_range:
					t.take_hit(data.attack_damage, self, "eikon")
			if is_instance_valid(_ring):
				_ring.queue_free()
			_ring = MeshUtil.cylinder(self, 1.0, 0.1, Vector3(0, 0.1, 0), data.color.lightened(0.3))
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				if is_instance_valid(_ring):
					_ring.queue_free())
