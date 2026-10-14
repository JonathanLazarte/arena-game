class_name Mount
extends CharacterBody3D
## Montura independiente del jinete. Cuando lleva jinete sigue su transform;
## sin jinete se queda cerca de donde la dejaron y pasea un poco.
## Ronda 14: las monturas son EIKONS montables (fénix, lobo, grifo). Una montura de eikon
## pertenece a su invocador (owner_fighter): solo él la monta, dura `life` segundos y al
## acabarse lo baja (sin derribo) y desaparece. Sin dueño (owner_fighter = null) es una
## montura neutral que cualquiera puede montar (solo pruebas antiguas / Arena.start_mounted).

var data: MountData
var rider: Fighter = null
var home: Vector3 = Vector3.ZERO
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _col: CollisionShape3D
var eikon: EikonData = null ## eikon del que sale esta montura (null = montura neutral)
var owner_fighter: Fighter = null
var life: float = INF ## s restantes (eikon); INF = permanente
var special_cd: float = 0.0
## Ronda 16: el eikon montable sin jinete es un COMPAÑERO de combate: tiene vida propia
## (EikonData.max_health), se puede fijar y golpear, y si cae se retira antes de tiempo.
var team: int = -1
var health: float = 0.0
var max_health: float = 0.0
var alive: bool = true
var hit_radius: float = 1.2
var attack_cd: float = 0.8
var recall_t: float = 0.0 ## (ronda 16; ya no se usa)
## Ronda 17: llamado con «Montar»: corre hacia el dueño (siguiéndolo) y lo monta al llegar.
var called: bool = false
const CALL_REACH := 2.2
var attacks_done: int = 0
var companion_target: Node3D = null
signal expired(m: Mount)

func _ready() -> void:
	add_to_group("mount")
	if eikon:
		add_to_group("eikon_mount")
		max_health = eikon.max_health * (float(owner_fighter.ad["eikon"]) if is_instance_valid(owner_fighter) else 1.0)
		health = max_health
		if is_instance_valid(owner_fighter):
			team = owner_fighter.team
		if rider == null:
			add_to_group("damageable")
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

const SADDLE_BONE := "Torso"
const SADDLE_FALLBACK := Vector3(0, 1.3, 0)
var saddle: BoneAttachment3D
var model: Node3D
var tree: AnimationTree
var _last_pos: Vector3
var speed_now: float = 0.0

## Caballo Quaternius (CC0). AnimationTree: BlendSpace1D Idle/Walk/Gallop por velocidad.
func _build_model() -> void:
	model = ResCache.scene(data.model_path).instantiate() as Node3D
	# El glTF mira a +Z: lo giramos para que mire a -Z (frente del juego)
	model.basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * data.model_scale)
	model.position.y = data.hover
	add_child(model)
	if data.tint:
		AnimUtil.tint_surfaces(model, data.color, 0.6 if data.hover > 0.0 else 0.5, 1.2 if data.hover > 0.0 else 0.0)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	AnimUtil.set_loops(ap, [data.anim_idle, data.anim_walk, data.anim_gallop])
	# Punto de silla: sigue al hueso del lomo, así el jinete sube y baja con el galope
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk and sk.find_bone(SADDLE_BONE) >= 0:
		saddle = BoneAttachment3D.new()
		saddle.name = "Saddle"
		saddle.bone_name = SADDLE_BONE
		sk.add_child(saddle)
	var bs := AnimationNodeBlendSpace1D.new()
	bs.add_blend_point(AnimUtil.anim_node(data.anim_idle), 0.0, -1, &"Idle")
	bs.add_blend_point(AnimUtil.anim_node(data.anim_walk), 0.3, -1, &"Walk")
	bs.add_blend_point(AnimUtil.anim_node(data.anim_gallop), 1.0, -1, &"Gallop")
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

## Punto de la silla en el mundo (lomo del caballo, con el balanceo de la animación).
func saddle_position() -> Vector3:
	if saddle and saddle.is_inside_tree():
		return saddle.global_position + global_basis * data.saddle_offset
	return global_transform * (SADDLE_FALLBACK + Vector3(0, data.hover, 0))

func is_free() -> bool:
	return rider == null

## ¿Puede montarla f? Las de eikon solo su dueño.
func can_ride(f: Fighter) -> bool:
	return is_free() and (owner_fighter == null or owner_fighter == f) and life > 0.0

func is_flying() -> bool:
	return data.hover > 0.0

## Tiempo de vida restante en [0, 1] (barra del HUD).
func life_fraction() -> float:
	return 1.0 if life == INF or eikon == null else clampf(life / eikon.duration, 0.0, 1.0)

## Se acaba la invocación: baja al jinete (sin aturdir) y desaparece.
func expire() -> void:
	if life <= -1.0:
		return
	life = -1.0
	if rider:
		rider.dismount(false)
	if is_instance_valid(owner_fighter) and owner_fighter.active_eikon == self:
		owner_fighter.active_eikon = null
		owner_fighter.owned_mount = null
	expired.emit(self)
	queue_free()

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.0 + data.hover, 0)

## Solo se le puede golpear sin jinete (montado, los golpes van al jinete).
func take_hit(amount: float, _from: Node3D, _kind: String) -> String:
	if not alive or rider != null or eikon == null:
		return "none"
	health -= amount
	var au := get_node_or_null("/root/Audio")
	if au:
		au.sfx3d("hit_eikon", global_position)
	if health <= 0.0:
		alive = false
		expire()
	return "hit"

func is_companion() -> bool:
	return eikon != null and rider == null and alive

func set_rider(r: Fighter) -> void:
	rider = r
	_col.disabled = r != null
	if eikon:
		if r == null and alive and not is_in_group("damageable"):
			add_to_group("damageable")
		elif r != null and is_in_group("damageable"):
			remove_from_group("damageable")
	if r == null:
		home = global_position
		_wander_t = 1.0

func _physics_process(delta: float) -> void:
	_update_anim(delta)
	special_cd = maxf(special_cd - delta, 0.0)
	if life != INF and life > -1.0:
		life -= delta
		if life <= 0.0 or not is_instance_valid(owner_fighter) or not owner_fighter.alive:
			expire()
			return
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
	attack_cd -= delta
	recall_t = maxf(recall_t - delta, 0.0)
	if called:
		if is_instance_valid(owner_fighter) and owner_fighter.alive and not owner_fighter.mounted:
			_call_step(delta)
			return
		called = false
	if eikon and is_instance_valid(owner_fighter) and owner_fighter.alive and recall_t <= 0.0:
		companion_target = MeshUtil.companion_target(global_position, get_tree(), team)
		if companion_target:
			_companion_step(delta)
			return
	if is_instance_valid(owner_fighter) and owner_fighter.alive:
		# Eikon sin jinete: sigue de cerca a su dueño (para que pueda volver a montar)
		var to_o := MeshUtil.flat(owner_fighter.global_position - global_position)
		_wander_dir = to_o.normalized() * clampf((to_o.length() - 2.5) / 2.0, 0.0, 4.0) if to_o.length() > 2.5 else Vector3.ZERO
	var v := _wander_dir * 1.5
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if global_position.y < 0.0: global_position.y = 0.0 # ronda 29: nunca bajo el suelo
	if v.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), delta * 3.0)

## Modo ataque (compañero): persigue al objetivo y lo ataca con los datos de compañero del eikon.
func _companion_step(delta: float) -> void:
	var tgt := companion_target
	var d := MeshUtil.flat(tgt.global_position - global_position)
	var dist := d.length()
	var v := Vector3.ZERO
	if dist > eikon.attack_range * 0.8:
		v = d.normalized() * eikon.move_speed * 0.7
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if global_position.y < 0.0: global_position.y = 0.0 # ronda 29: nunca bajo el suelo
	if dist > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), delta * 6.0)
	if dist <= eikon.attack_range and attack_cd <= 0.0:
		attack_cd = eikon.attack_cooldown
		attacks_done += 1
		if eikon.attack_kind == EikonData.AttackKind.RANGED:
			var p := Projectile.new()
			p.team = team
			p.shooter = self
			p.kind = "eikon"
			p.damage = eikon.attack_damage * _bond()
			p.speed = 22.0
			p.radius = 0.7
			p.color = eikon.color
			var origin := get_hit_center() + Vector3(0, 0.4, 0)
			var lead: float = float(owner_fighter.get("aim_lead")) if is_instance_valid(owner_fighter) else 0.0
			p.direction = Projectile.aim_dir(origin, tgt, p.speed, lead)
			p.aimed_at = tgt
			get_parent().add_child(p)
			p.global_position = origin
		else:
			tgt.take_hit(eikon.attack_damage * _bond(), self, "eikon")
			if model:
				var tw := create_tween()
				tw.tween_property(model, "position:z", -0.5, 0.08).as_relative()
				tw.tween_property(model, "position:z", 0.5, 0.15).as_relative()

## Viene corriendo hacia la posición actual del dueño; al llegar (y si está libre) lo monta.
func _call_step(delta: float) -> void:
	var o := owner_fighter
	var d := MeshUtil.flat(o.global_position - global_position)
	var dist := d.length()
	var v := Vector3.ZERO
	if dist > CALL_REACH * 0.6:
		v = d.normalized() * maxf(data.speed, 10.0)
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if global_position.y < 0.0: global_position.y = 0.0 # ronda 29: nunca bajo el suelo
	if dist > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), delta * 8.0)
	if dist <= CALL_REACH and o.can_mount_now():
		called = false
		o.mount_on(self)

## Ronda 18: Vínculo del dueño (daño del eikon).
func _bond() -> float:
	return float(owner_fighter.ad["eikon"]) if is_instance_valid(owner_fighter) else 1.0
