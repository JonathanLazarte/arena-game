class_name Mount
extends CharacterBody3D
## Montura independiente del jinete. Cuando lleva jinete sigue su transform;
## sin jinete se queda cerca de donde la dejaron y pasea un poco.
## Ronda 14: las monturas son EIKONS montables (fénix, lobo, grifo).
## Fase 8: solo vista — SimWorld la coloca como títere según el estado de la sim (dueño, vida, jinete).

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
	# La altura de vuelo la pone SimWorld en la raíz. Subir el modelo otra vez dejaba al jinete colgando.
	model.position.y = 0.0
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
	tree.advance(0.0)
	_last_pos = global_position
	_measure_seat(sk)

## Altura real del lomo (solo vista). El punto de silla de los datos no siempre coincidía con la
## malla: con 1,3 m fijos el jinete quedaba hundido en el grifo (su lomo está a ~2,2 m) y, en
## monturas cuyo hueso Torso sí anima el lomo, no seguía el galope. Se mide una vez en reposo la
## cima de la malla bajo el punto de silla; la cadera queda SEAT_SINK por debajo (el cuerpo del
## chibi apoya en el lomo). En voladoras se respeta saddle_offset (las alas en reposo tapan el lomo).
var seat_fix: float = 0.0 ## corrección vertical del punto de silla (hueso + saddle_offset)
var seat_top: float = -1.0 ## altura de la cadera sobre la raíz (lomo − SEAT_SINK); -1 = sin medir
var _bone_seat := false ## el hueso Torso está en el lomo (no en el origen): la silla lo sigue

func _measure_seat(sk: Skeleton3D) -> void:
	var inv := global_transform.affine_inverse()
	var base := SADDLE_FALLBACK
	if sk and sk.find_bone(SADDLE_BONE) >= 0:
		var bt := sk.global_transform * sk.get_bone_global_rest(sk.find_bone(SADDLE_BONE))
		var bl := inv * bt.origin
		_bone_seat = bl.y > 0.3
		base = bl + data.saddle_offset if _bone_seat else Vector3(data.saddle_offset.x, SADDLE_FALLBACK.y, data.saddle_offset.z)
	var top := -INF
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := inv * m.global_transform
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				var p := xf * v
				if Vector2(p.x - base.x, p.z - base.z).length() < SEAT_R:
					top = maxf(top, p.y)
	if top > -INF and data.hover <= 0.0:
		seat_top = top - SEAT_SINK
		seat_fix = seat_top - base.y

## ¿La silla sigue al hueso del lomo? (voladoras, y monturas de suelo con Torso en el lomo)
func seat_follows_bone() -> bool:
	return saddle != null and (is_flying() or _bone_seat)

const SEAT_SINK := 0.15 ## la cadera del jinete queda esto por debajo de la cima del lomo
const SEAT_R := 0.2 ## radio horizontal donde se busca la cima del lomo

func _update_anim(delta: float) -> void:
	var d := MeshUtil.flat(global_position - _last_pos).length() / maxf(delta, 0.001)
	_last_pos = global_position
	speed_now = lerpf(speed_now, d, clampf(delta * 8.0, 0.0, 1.0))
	tree.set("parameters/blend_position", speed_now / maxf(data.speed, 0.1))

## Punto de la silla en el mundo (lomo del caballo, con el balanceo de la animación).
func saddle_position() -> Vector3:
	if saddle and saddle.is_inside_tree():
		return saddle.global_position + global_basis * (data.saddle_offset + Vector3(0, seat_fix, 0))
	# La raíz ya está a data.hover (SimWorld). No sumar el vuelo otra vez.
	return global_transform * (SADDLE_FALLBACK + Vector3(0, seat_fix, 0))

## Altura de la silla sobre la raíz para monturas que no vuelan (lomo medido en la malla).
func seat_height() -> float:
	return seat_top if seat_top > 0.0 else SADDLE_FALLBACK.y

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

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.0 + data.hover, 0)

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

## La vista lo llama al cerrar la ronda. La sim ya no tiene un reloj propio en la montura.
func expire() -> void:
	var r := rider
	rider = null
	if is_instance_valid(r) and r.mount_node == self:
		r.mount_node = null
		r.mounted = false
		if r.active_eikon == self:
			r.active_eikon = null
		r._apply_mount_visuals()
		r.mount_changed.emit(false)
	expired.emit(self)
	queue_free()

var puppet := false ## fase 8: la mueve la sim (SimWorld); sin lógica propia
## Fase 8: títere visual (SimWorld la coloca); sin lógica propia.
func _physics_process(delta: float) -> void:
	_update_anim(delta)
