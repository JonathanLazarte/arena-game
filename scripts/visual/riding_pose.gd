class_name RidingPose
extends SkeletonModifier3D
## Postura de jinete a horcajadas. Parte de Sit_Chair_Pose (KayKit, CC0) y,
## después del AnimationTree, abre los muslos hacia los flancos del caballo,
## los baja un poco y deja las espinillas colgando con los pies en los estribos.
## Los ángulos son en espacio del esqueleto (el caballero mira a +Z).

@export var thigh_spread_deg: float = 38.0 ## apertura lateral de cada muslo
@export var thigh_drop_deg: float = 38.0 ## cuánto baja el muslo desde la horizontal de la silla
@export var shin_back_deg: float = 12.0 ## la espinilla cuelga casi vertical, algo hacia atrás
@export var foot_out_deg: float = 15.0 ## punta del pie hacia fuera
var amount: float = 0.0 ## 0 = pose original, 1 = a horcajadas
var knee_gap: float = 0.0 ## separación lateral de las rodillas tras el último ajuste (pruebas)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if amount > 0.001:
		_apply(sk)
	var kl := sk.find_bone("lowerleg.l")
	var kr := sk.find_bone("lowerleg.r")
	if kl >= 0 and kr >= 0:
		knee_gap = absf(sk.get_bone_global_pose(kl).origin.x - sk.get_bone_global_pose(kr).origin.x) * sk.global_basis.get_scale().x

func _apply(sk: Skeleton3D) -> void:
	for side: String in ["l", "r"]:
		var s := 1.0 if side == "l" else -1.0 # el lado izquierdo del caballero está en +X
		var thigh := sk.find_bone("upperleg." + side)
		var shin := sk.find_bone("lowerleg." + side)
		var foot := sk.find_bone("foot." + side)
		if thigh < 0 or shin < 0:
			continue
		# Muslo (en la silla apunta hacia delante): bajar (giro sobre X) y abrir hacia fuera (giro sobre Y)
		var rot := Basis(Vector3.UP, deg_to_rad(thigh_spread_deg) * s * amount) \
			* Basis(Vector3.RIGHT, deg_to_rad(thigh_drop_deg) * amount)
		_rotate_global(sk, thigh, rot)
		# Espinilla: que cuelgue vertical (calcula el giro que lleva su dirección a "abajo y algo atrás")
		var g := sk.get_bone_global_pose(shin)
		var tip := sk.get_bone_global_pose(foot).origin if foot >= 0 else g.origin + g.basis.y
		var cur := (tip - g.origin).normalized()
		var want := Vector3(0.08 * s, -1.0, -tan(deg_to_rad(shin_back_deg))).normalized()
		if cur.length() > 0.5:
			var q := Quaternion(cur, cur.slerp(want, amount).normalized())
			_rotate_global(sk, shin, Basis(q))
		if foot >= 0:
			_rotate_global(sk, foot, Basis(Vector3.UP, deg_to_rad(foot_out_deg) * s * amount))

## Gira un hueso alrededor de su propio origen con una rotación en espacio del esqueleto.
func _rotate_global(sk: Skeleton3D, bone: int, rot: Basis) -> void:
	var g := sk.get_bone_global_pose(bone)
	var ng := Transform3D(rot * g.basis, g.origin)
	var parent := sk.get_bone_parent(bone)
	var local := ng if parent < 0 else sk.get_bone_global_pose(parent).affine_inverse() * ng
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
