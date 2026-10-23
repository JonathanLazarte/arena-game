## RAMA test-models (solo pruebas privadas; NUNCA a master). Hornea, para cada modelo de prueba
## de terceros, las animaciones KayKit (Knight.glb) y la biblioteca Mixamo «mx» (lib_kaykit.res)
## reapuntadas a su esqueleto. Reapuntado por delta de orientación global por hueso, con
## corrección de pose de reposo (pose A -> pose T de KayKit) alineando la dirección de cada hueso.
## Las pistas usan los nombres KayKit: KnightVisual renombra los huesos del modelo al cargarlo.
## Uso: godot --headless --path . -s res://tools/bake_test_models.gd
extends SceneTree

const FPS := 15.0
## Clips KayKit que el juego no usa en ningún lado (ahorra ~40 % de tamaño en el APK).
const SKIP := ["1H_Ranged_Shooting", "2H_Ranged_Shooting", "Block", "Cheer", "Death_A_Pose", "Death_B", "Death_B_Pose",
	"Interact", "Jump_Full_Long", "Jump_Full_Short", "Lie_Idle", "Lie_Pose", "PickUp", "Running_B", "Sit_Chair_Down",
	"Sit_Chair_Idle", "Sit_Chair_StandUp", "Sit_Floor_Down", "Sit_Floor_Idle", "Sit_Floor_Pose", "Sit_Floor_StandUp",
	"Spellcast_Long", "Spellcast_Raise", "Spellcast_Shoot", "Spellcasting", "T-Pose", "Throw", "Unarmed_Idle",
	"Unarmed_Melee_Attack_Kick", "Unarmed_Melee_Attack_Punch_A", "Unarmed_Melee_Attack_Punch_B", "Unarmed_Pose",
	"Walking_B", "Walking_C"]
const HEAD_FRAC := 0.87 # altura del hueso de la cabeza / altura total (adulto realista)

const CHAIN := {"hips": "spine", "spine": "chest", "chest": "head",
	"upperarm.l": "lowerarm.l", "lowerarm.l": "hand.l", "upperarm.r": "lowerarm.r", "lowerarm.r": "hand.r",
	"upperleg.l": "lowerleg.l", "lowerleg.l": "foot.l", "foot.l": "toes.l",
	"upperleg.r": "lowerleg.r", "lowerleg.r": "foot.r", "foot.r": "toes.r"}
const INHERIT := {"head": "chest", "hand.l": "lowerarm.l", "hand.r": "lowerarm.r", "toes.l": "foot.l", "toes.r": "foot.r",
	"handslot.l": "hand.l", "handslot.r": "hand.r"}

static func _lr(m: Dictionary, l: Array, r: Array) -> Dictionary:
	var keys := ["upperarm", "lowerarm", "hand", "upperleg", "lowerleg", "foot", "toes"]
	for i in keys.size():
		m[keys[i] + ".l"] = l[i]
		m[keys[i] + ".r"] = r[i]
	return m

func configs() -> Array:
	return [
		{"id": "test_jane", "path": "res://assets/test_models/test_jane/jane.glb", "map": _lr(
			{"hips": "Hips_02", "spine": "Spine_033", "chest": "Chest_034", "head": "Head_036"},
			["Left arm_0136", "Left elbow_0138", "Left wrist_0141", "Left leg_014", "Left knee_015", "Left ankle_016", "Left toe_017"],
			["Right arm_0115", "Right elbow_0117", "Right wrist_0119", "Right leg_03", "Right knee_04", "Right ankle_05", "Right toe_06"])},
		{"id": "test_yoomi", "path": "res://assets/test_models/test_yoomi/yoomi.glb", "map": _lr(
			{"hips": "pelvis_03", "spine": "spine_02_05", "chest": "spine_04_07", "head": "head_011"},
			["upperarm_l_0140", "lowerarm_l_0141", "hand_l_0142", "thigh_l_0259", "calf_l_0260", "foot_l_0261", "ball_l_0262"],
			["upperarm_r_0161", "lowerarm_r_0183", "hand_r_0184", "thigh_r_0294", "calf_r_0295", "foot_r_0296", "ball_r_0297"])},
		{"id": "test_mita", "path": "res://assets/test_models/test_mita/mita.glb", "map": _lr(
			{"hips": "Hips_03", "spine": "Spine_062", "chest": "Chest_063", "head": "Head_1_093"},
			["Left_arm_065", "Left_elbow_066", "Left_wrist_067", "Left_leg_07", "Left_knee_08", "Left_ankle_010", "Left_toe_09"],
			["Right_arm_0141", "Right_elbow_0143", "Right_wrist_0142", "Right_leg_011", "Right_knee_012", "Right_ankle_013", "Right_toe_014"]),
			"rebind": {"Armature_02": "head"}}, # cara/pelo pesados a la raíz: se enganchan a la cabeza
		{"id": "test_nightgown", "path": "res://assets/test_models/test_nightgown/luna.fbx", "map": _lr(
			{"hips": "spine", "spine": "spine.002", "chest": "spine.003", "head": "spine.006"},
			["upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L", "foot.L", "toe.L"],
			["upper_arm.R", "forearm.R", "hand.R", "thigh.R", "shin.R", "foot.R", "toe.R"])},
		{"id": "test_knight", "path": "res://assets/test_models/test_knight/knight.glb", "map": _lr(
			{"hips": "Pelvis_203", "spine": "Spine_155", "chest": "Spine1_121", "head": "Head_94"},
			["L UpperArm_39", "L Forearm_36", "L Hand_34", "L Thigh_133", "L Calf_128", "L Foot_124", "L Toe0_122"],
			["R UpperArm_74", "R Forearm_71", "R Hand_69", "R Thigh_145", "R Calf_140", "R Foot_136", "R Toe0_134"]),
			"hide_bone": "R_weapon_66"}, # su propia arma (el juego pone la suya)
		# El mismo caballero re-rigueado a humanoide44 con tools/rig/rig_humanoid44.py (docs/SKELETON_GUIDE.md)
		{"id": "test_knight_h44", "path": "res://assets/test_models/test_knight_h44/knight_h44.glb", "map": _lr(
			{"hips": "Pelvis", "spine": "Spine", "chest": "Spine2", "head": "Head"},
			["L_UpperArm", "L_Forearm", "L_Hand", "L_Thigh", "L_Calf", "L_Foot", "L_Toe0"],
			["R_UpperArm", "R_Forearm", "R_Hand", "R_Thigh", "R_Calf", "R_Foot", "R_Toe0"]),
			"hide_bone": "x_R_weapon_66"},
	]

static func rel_xf(nd: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = nd
	while c != top and c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

static func q(b: Basis) -> Quaternion:
	return b.orthonormalized().get_rotation_quaternion()

func _init() -> void:
	var only := OS.get_environment("ONLY")
	var src_scene: Node3D = (load("res://assets/models/Knight.glb") as PackedScene).instantiate()
	var ssk := src_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var sap := src_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var mx: AnimationLibrary = load("res://assets/animations/mixamo/lib_kaykit.res")
	# Altura de referencia KayKit: AABB de las mallas del cuerpo (sin armas/escudos/casco)
	var kay_h := 0.0
	for mi: MeshInstance3D in src_scene.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.contains("Shield") or n.contains("Sword") or n.contains("Helmet") or n.contains("Cape"):
			continue
		kay_h = maxf(kay_h, (rel_xf(mi, src_scene) * mi.get_aabb()).end.y)
	print("KayKit altura cuerpo ", kay_h)
	var ns := ssk.get_bone_count()
	var s_rest: Array[Transform3D] = []
	var s_grest: Array[Transform3D] = []
	var s_xf := rel_xf(ssk, src_scene)
	for i in ns:
		s_rest.append(ssk.get_bone_rest(i))
		var p := ssk.get_bone_parent(i)
		s_grest.append((s_grest[p] if p >= 0 else s_xf) * s_rest[i])
	var s_idx := {}
	for i in ns:
		s_idx[ssk.get_bone_name(i)] = i
	for cfg: Dictionary in configs():
		if only != "" and cfg.id != only:
			continue
		_bake(cfg, src_scene, ssk, sap, mx, s_rest, s_grest, s_idx, kay_h)
	src_scene.free()
	quit()

func _bake(cfg: Dictionary, src_scene: Node3D, ssk: Skeleton3D, sap: AnimationPlayer, mx: AnimationLibrary,
		s_rest: Array[Transform3D], s_grest: Array[Transform3D], s_idx: Dictionary, kay_h: float) -> void:
	var t0 := Time.get_ticks_msec()
	var model: Node3D = (load(cfg.path) as PackedScene).instantiate()
	var tsk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var map: Dictionary = cfg.map
	var tidx := {}
	for k: String in map:
		var i := tsk.find_bone(map[k])
		assert(i >= 0, "%s: falta hueso %s" % [cfg.id, map[k]])
		tidx[k] = i
	var kt := rel_xf(tsk, model)
	var kscale := kt.basis.get_scale().x
	# Escala de ajuste: altura estimada desde el hueso de la cabeza
	var t_grest_k: Array[Transform3D] = [] # espacio del esqueleto
	for i in tsk.get_bone_count():
		var p := tsk.get_bone_parent(i)
		t_grest_k.append((t_grest_k[p] if p >= 0 else Transform3D.IDENTITY) * tsk.get_bone_rest(i))
	var head_y := (kt * t_grest_k[tidx.head]).origin.y
	var fit := kay_h / (head_y / HEAD_FRAC)
	var F := Transform3D(Basis.from_scale(Vector3.ONE * fit)) * kt
	var gt_f := func(i: int) -> Transform3D: return F * t_grest_k[i]
	# Rotaciones de reposo globales (espacio de ajuste) y corrección de pose por hueso
	var keys: Array = map.keys()
	keys.append_array(["handslot.l", "handslot.r"])
	var gtq := {}
	var pos_f := {}
	for k: String in map:
		gtq[k] = q((gt_f.call(tidx[k]) as Transform3D).basis)
		pos_f[k] = (gt_f.call(tidx[k]) as Transform3D).origin
	var cq := {}
	for k: String in map:
		if CHAIN.has(k):
			var dt: Vector3 = (pos_f[CHAIN[k]] - pos_f[k]).normalized()
			var ds: Vector3 = (s_grest[s_idx[CHAIN[k]]].origin - s_grest[s_idx[k]].origin).normalized()
			cq[k] = Quaternion(dt, ds)
	for k: String in INHERIT:
		if map.has(k):
			cq[k] = cq.get(INHERIT[k], Quaternion.IDENTITY)
	# Huesos añadidos handslot.l/r: reposo tal que su orientación «virtual» = la de KayKit
	var handslot := {}
	var arm_ratio: float = (pos_f["hand.l"] - pos_f["upperarm.l"]).length() / (s_grest[s_idx["hand.l"]].origin - s_grest[s_idx["upperarm.l"]].origin).length()
	for side: String in ["l", "r"]:
		var hk := "hand." + side
		var sk_name := "handslot." + side
		var c: Quaternion = cq[hk]
		var rot := c.inverse() * q(s_grest[s_idx[sk_name]].basis)
		var off: Vector3 = c.inverse() * (s_grest[s_idx[sk_name]].origin - s_grest[s_idx[hk]].origin) * arm_ratio
		var xf_f := Transform3D(Basis(rot), pos_f[hk] + off)
		var xk := F.affine_inverse() * xf_f
		xk.basis = xk.basis.orthonormalized()
		var local := t_grest_k[tidx[hk]].affine_inverse() * xk
		local.basis = local.basis.orthonormalized()
		handslot[sk_name] = local
		gtq[sk_name] = rot
		cq[sk_name] = c
	# Orden por profundidad y padre efectivo de cada hueso mapeado
	var t_of := {} # índice destino -> clave KayKit
	for k: String in map:
		t_of[tidx[k]] = k
	var depth := func(i: int) -> int:
		var d := 0
		var p := tsk.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = tsk.get_bone_parent(p)
		return d
	var order: Array = map.keys()
	order.sort_custom(func(a, b): return depth.call(tidx[a]) < depth.call(tidx[b]))
	order.append_array(["handslot.l", "handslot.r"])
	var par_info := {} # k -> [ancestro mapeado o "", rotación constante de cadena]
	for k: String in order:
		if not map.has(k):
			par_info[k] = ["hand." + k.substr(9), Quaternion.IDENTITY]
			continue
		var chain := Quaternion.IDENTITY
		var cur := tsk.get_bone_parent(tidx[k])
		while cur >= 0 and not t_of.has(cur):
			chain = q(tsk.get_bone_rest(cur).basis) * chain
			cur = tsk.get_bone_parent(cur)
		if cur >= 0:
			par_info[k] = [t_of[cur], chain]
		else:
			par_info[k] = ["", q(kt.basis) * chain] # sin ancestro mapeado: reposo global
	var hip_parent := tsk.get_bone_parent(tidx.hips)
	var hip_parent_k := t_grest_k[hip_parent] if hip_parent >= 0 else Transform3D.IDENTITY
	var hip_ratio: float = pos_f.hips.y / s_grest[s_idx.hips].origin.y
	var skel_path := String(model.get_path_to(tsk))
	var sgq := {}
	for k: String in keys:
		sgq[k] = q(s_grest[s_idx[k]].basis)
	var ns := ssk.get_bone_count()
	var bake_anim := func(src: Animation) -> Animation:
		var tracks := {}
		for ti in src.get_track_count():
			var ty := src.track_get_type(ti)
			if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
				continue
			var bn := String(src.track_get_path(ti).get_concatenated_subnames())
			if s_idx.has(bn):
				tracks[str(s_idx[bn]) + ":" + str(ty)] = ti
		var dst := Animation.new()
		dst.length = src.length
		dst.loop_mode = src.loop_mode
		var rt := {}
		for k: String in order:
			rt[k] = dst.add_track(Animation.TYPE_ROTATION_3D)
			dst.track_set_path(rt[k], NodePath(skel_path + ":" + k))
		var pt := dst.add_track(Animation.TYPE_POSITION_3D)
		dst.track_set_path(pt, NodePath(skel_path + ":hips"))
		var n := maxi(1, int(ceil(src.length * FPS)))
		for fi in n + 1:
			var t := minf(src.length, fi / FPS)
			var g: Array[Transform3D] = []
			g.resize(ns)
			for i in ns:
				var r := s_rest[i]
				var kr = tracks.get(str(i) + ":" + str(Animation.TYPE_ROTATION_3D))
				var kp = tracks.get(str(i) + ":" + str(Animation.TYPE_POSITION_3D))
				var b := r.basis
				var o := r.origin
				if kr != null:
					b = Basis(src.rotation_track_interpolate(kr, t))
				if kp != null:
					o = src.position_track_interpolate(kp, t)
				var p := ssk.get_bone_parent(i)
				g[i] = (g[p] if p >= 0 else Transform3D.IDENTITY) * Transform3D(b, o)
			var at := {}
			for k: String in order:
				var ws: Quaternion = q(g[s_idx[k]].basis) * (sgq[k] as Quaternion).inverse()
				at[k] = ws * (cq.get(k, Quaternion.IDENTITY) as Quaternion) * (gtq[k] as Quaternion)
				var pi: Array = par_info[k]
				var ap: Quaternion = (at[pi[0]] as Quaternion) * (pi[1] as Quaternion) if pi[0] != "" else pi[1]
				dst.rotation_track_insert_key(rt[k], t, (ap.inverse() * (at[k] as Quaternion)).normalized())
			var hp: Vector3 = pos_f.hips + (g[s_idx.hips].origin - s_grest[s_idx.hips].origin) * hip_ratio
			var hk := hip_parent_k.affine_inverse() * (F.affine_inverse() * hp)
			dst.position_track_insert_key(pt, t, hk)
		return dst
	var lib := AnimationLibrary.new()
	for a in sap.get_animation_list():
		if String(a) in SKIP:
			continue
		lib.add_animation(a, bake_anim.call(sap.get_animation(a)))
	var mlib := AnimationLibrary.new()
	for a in mx.get_animation_list():
		mlib.add_animation(a, bake_anim.call(mx.get_animation(a)))
	# Mallas a ocultar (arma propia) o a reenganchar (pesadas por completo a un hueso raíz)
	var hide := []
	var rebind := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := {}
		var tot := 0.0
		for i in bones.size():
			var bn := String(mi.skin.get_bind_name(bones[i]))
			if mi.skin.get_bind_bone(bones[i]) >= 0:
				bn = tsk.get_bone_name(mi.skin.get_bind_bone(bones[i]))
			per[bn] = per.get(bn, 0.0) + wts[i]
			tot += wts[i]
		if cfg.has("hide_bone") and per.get(cfg.hide_bone, 0.0) > 0.5 * tot:
			hide.append(String(mi.name))
		for fb: String in cfg.get("rebind", {}):
			if per.get(fb, 0.0) > 0.95 * tot:
				rebind[String(mi.name)] = [fb, cfg.rebind[fb]]
	lib.set_meta("hide_meshes", hide)
	lib.set_meta("rebind", rebind)
	print("  ocultas ", hide, " reenganchadas ", rebind.keys())
	lib.set_meta("mx", mlib)
	lib.set_meta("bone_map", map)
	lib.set_meta("handslot", handslot)
	lib.set_meta("fit_scale", fit)
	lib.set_meta("att_scale", fit * kscale)
	lib.set_meta("skeleton_path", skel_path)
	var out := "res://assets/test_models/%s/%s_anims.res" % [cfg.id, cfg.id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("%s: fit %.3f att %.3f head_y %.2f clips %d+%d -> %s err %d (%d ms)" % [cfg.id, fit, fit * kscale, head_y,
		lib.get_animation_list().size(), mlib.get_animation_list().size(), out, err, Time.get_ticks_msec() - t0])
	model.free()
