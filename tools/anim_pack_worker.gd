extends SceneTree
## Trabajador de tools/import_anim_pack.gd: corre DENTRO del proyecto temporal (no en el repo).
## Reapuntado por delta global (misma matemática que tools/retarget_kaykit.gd):
##   Ws = Apose_src · Grest_src⁻¹ ;  Apose_tgt = Ws · C · Grest_tgt
## C = rotación que lleva cada segmento del reposo KayKit al del reposo fuente (cadenas
## caderas-columna-cabeza, brazos, piernas); los huesos hoja la heredan. En los brazos C es la
## rotación completa entre marcos (dirección + rollo, con «roll_ref»: índice/meñique del modelo
## fuente frente a «target_across»), no solo la mínima entre direcciones. «forearm_twist» reparte
## el giro mano/antebrazo (rigs con huesos de giro dejan el antebrazo quieto y la mano girada).
## Reposo fuente = pose de bind del modelo del pack (si existe; arregla el giro de antebrazo/mano),
## llevada al espacio de los clips con «bind_axes». Si no hay modelo, se usa el frame 0.
## Root motion: el hueso raíz («root_bone») se ignora entero (con «root_keep_vertical» se conserva su altura); de la pelvis solo queda la altura
## (escalada por la relación de alturas de cadera); x/z quedan en el reposo KayKit.

var P: Dictionary
var roll_fix := {} ## hueso -> grados corregidos por rollo (diagnóstico)
var twist_max := [0.0, 0.0] ## giro mano/antebrazo máx. [fuente, que queda en la muñeca destino]
var fa_twist := 0.0
const MAX_ROLL_FIX := 45.0 ## más que esto = dedos del modelo mal identificados

## Marco ortonormal: X = dirección del hueso, Y = «b» sin su componente en X.
static func _frame(x: Vector3, b: Vector3) -> Basis:
	var y := (b - x * b.dot(x)).normalized()
	return Basis(x, y, x.cross(y))

## Ángulo con signo del giro de «r» alrededor de «axis» (descomposición swing-twist).
static func _twist_angle(r: Quaternion, axis: Vector3) -> float:
	var v := Vector3(r.x, r.y, r.z)
	var p := axis * v.dot(axis)
	var t := Quaternion(p.x, p.y, p.z, r.w)
	if t.length_squared() < 1e-12:
		return 0.0
	t = t.normalized()
	var ang := 2.0 * atan2(Vector3(t.x, t.y, t.z).length(), t.w)
	if Vector3(t.x, t.y, t.z).dot(axis) < 0.0:
		ang = -ang
	return wrapf(ang, -PI, PI)

static func q(b: Basis) -> Quaternion:
	return b.orthonormalized().get_rotation_quaternion()

static func grest(sk: Skeleton3D) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g.append((g[p] if p >= 0 else Transform3D.IDENTITY) * sk.get_bone_rest(i))
	return g

static func snake(s: String) -> String:
	var o := ""
	for i in s.length():
		var c := s[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0 and s[i - 1] == s[i - 1].to_lower() and s[i - 1] != "_":
			o += "_"
		o += c.to_lower() if c.is_valid_identifier() or c.is_valid_int() else "_"
	return o.replace("__", "_").strip_edges()

func _init() -> void:
	P = JSON.parse_string(FileAccess.get_file_as_string("res://profile.json"))
	var only := ""
	var ua := OS.get_cmdline_user_args()
	if ua.has("--only"):
		only = ua[ua.find("--only") + 1]
	var tgt: Node = load("res://target.glb").instantiate()
	var tsk := tgt.find_child("Skeleton3D", true, false) as Skeleton3D
	var ok := true
	for ch: Dictionary in P.characters:
		if only != "" and ch.id != only:
			continue
		ok = _character(ch, tsk) and ok
	quit(0 if ok else 1)

func _character(ch: Dictionary, tsk: Skeleton3D) -> bool:
	var MAP: Dictionary = P.bone_map
	roll_fix = {}
	twist_max = [0.0, 0.0]
	fa_twist = float(P.get("forearm_twist", 0.0))
	var tg := grest(tsk)
	var ti := {}
	for k: String in MAP:
		ti[k] = tsk.find_bone(k)
		if ti[k] < 0:
			printerr("[anim] hueso destino inexistente ", k); return false
	# reposo fuente: bind del modelo
	var bind := {} # nombre -> Transform3D global (espacio clip)
	var model_path := "res://src/" + String(ch.get("model", "")).get_basename() + ".fbx"
	if ch.get("model", "") != "" and FileAccess.file_exists(model_path):
		var m: Node = load(model_path).instantiate()
		var msk := m.find_child("Skeleton3D", true, false) as Skeleton3D
		var ax: Array = P.get("bind_axes", [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
		var F := Transform3D(Basis(Vector3(ax[0][0], ax[0][1], ax[0][2]), Vector3(ax[1][0], ax[1][1], ax[1][2]), Vector3(ax[2][0], ax[2][1], ax[2][2])), Vector3.ZERO)
		var mg := grest(msk)
		for i in msk.get_bone_count():
			bind[msk.get_bone_name(i)] = F * mg[i]
		m.free()
		print("[anim] %s: reposo = bind de %s" % [ch.id, ch.model])
	else:
		print("[anim] %s: sin modelo, reposo = frame 0 de cada clip (giro ambiguo)" % ch.id)
	var lib := AnimationLibrary.new()
	var manifest: Array = []
	var skipped: Array = []
	var jobs: Array = [] # [nombre_salida, archivo]
	if ch.has("clips"):
		for k: String in ch.clips:
			jobs.append([k, String(ch.clips[k]) + ".fbx"])
	else:
		var files := DirAccess.get_files_at("res://src")
		files.sort()
		for f in files:
			if f.begins_with(String(ch.prefix) + "@") and f.to_lower().ends_with(".fbx"):
				jobs.append([snake(f.get_basename().split("@")[1]), f])
	for job: Array in jobs:
		var clip_name: String = job[0]
		var f: String = job[1]
		if not FileAccess.file_exists("res://src/" + f):
			skipped.append({"file": f, "why": "no está en --src"}); continue
		var scn = load("res://src/" + f)
		if scn == null:
			skipped.append({"file": f, "why": "no importa"}); continue
		var src: Node = scn.instantiate()
		var ssk := src.find_child("Skeleton3D", true, false) as Skeleton3D
		if ssk == null:
			ssk = _node_skeleton(src) # algunos FBX ignoran import_as_skeleton_bones: huesos como Node3D
		var sap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ssk == null or sap == null or sap.get_animation_list().is_empty():
			skipped.append({"file": f, "why": "sin esqueleto o sin animación"}); src.free(); continue
		var miss := MAP.values().filter(func(b): return ssk.find_bone(b) < 0)
		if not miss.is_empty():
			skipped.append({"file": f, "why": "faltan huesos %s" % [miss]}); src.free(); continue
		var anim := sap.get_animation(sap.get_animation_list()[0])
		var out := _retarget(anim, ssk, tsk, tg, ti, bind)
		out.loop_mode = Animation.LOOP_NONE
		for pat: String in P.get("loop_patterns", []):
			if clip_name.contains(pat):
				out.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip_name, out)
		manifest.append({"name": clip_name, "source": f.get_basename(), "length": snappedf(out.length, 0.001),
			"loop": out.loop_mode != Animation.LOOP_NONE, "slot": P.get("slots", {}).get(clip_name, "")})
		print("[anim] %s/%s  %.2fs loop=%s  (%s)" % [ch.id, clip_name, out.length, out.loop_mode != 0, f])
		src.free()
	print("[anim] %s: rollo corregido %s ; giro mano/antebrazo máx %.0f° → en muñeca %.0f° (forearm_twist %.2f)" % [ch.id, roll_fix, twist_max[0], twist_max[1], fa_twist])
	ResourceSaver.save(lib, "res://out_%s.res" % ch.id, ResourceSaver.FLAG_COMPRESS)
	var mf := FileAccess.open("res://out_%s.json" % ch.id, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"pack": P.pack, "character": ch.id, "fps": P.fps, "rest": "bind" if not bind.is_empty() else "frame0",
		"clips": manifest, "skipped": skipped}, "\t"))
	mf.close()
	print("[anim] %s: %d clips, %d saltados %s" % [ch.id, manifest.size(), skipped.size(), skipped])
	return true

## Esqueleto equivalente a una jerarquía de Node3D (reposo = transform de cada nodo).
func _node_skeleton(src: Node) -> Skeleton3D:
	var top := src.get_node_or_null(String(P.get("root_bone", "")))
	if top == null or not top is Node3D:
		return null
	var sk := Skeleton3D.new()
	var stack: Array = [[top, -1]]
	while not stack.is_empty():
		var it: Array = stack.pop_front()
		var nd := it[0] as Node3D
		var i := sk.get_bone_count()
		sk.add_bone(nd.name)
		sk.set_bone_parent(i, it[1])
		sk.set_bone_rest(i, nd.transform)
		for c in nd.get_children():
			if c is Node3D and not c is MeshInstance3D:
				stack.append([c, i])
	src.add_child(sk)
	return sk

func _retarget(anim: Animation, ssk: Skeleton3D, tsk: Skeleton3D, tg: Array[Transform3D], ti: Dictionary, bind: Dictionary) -> Animation:
	var MAP: Dictionary = P.bone_map
	var CHAIN: Dictionary = P.chain
	var INHERIT: Dictionary = P.get("inherit", {})
	var root_bone := String(P.get("root_bone", ""))
	var keep_y := bool(P.get("root_keep_vertical", false))
	var sg0 := grest(ssk)
	var sg := {} # clave KayKit -> reposo global fuente
	for k: String in MAP:
		var bn := String(MAP[k])
		sg[k] = bind[bn] if bind.has(bn) else sg0[ssk.find_bone(bn)]
	var cq := {}
	for k: String in CHAIN:
		var dt: Vector3 = (tg[ti[CHAIN[k]]].origin - tg[ti[k]].origin).normalized()
		var ds: Vector3 = ((sg[CHAIN[k]] as Transform3D).origin - (sg[k] as Transform3D).origin).normalized()
		cq[k] = Quaternion(dt, ds)
	# Rollo (giro alrededor del hueso): la rotación mínima entre direcciones no fija el giro.
	# «roll_ref» da, por lado, [índice, meñique] del rig fuente: el eje «a través de la palma»
	# del reposo fuente debe coincidir con «target_across» (KayKit en T: palmas abajo, índice a +Z).
	# C pasa a ser la rotación completa entre los dos marcos (dirección + ese eje) en todo el brazo.
	var RR: Dictionary = P.get("roll_ref", {})
	var ta: Array = P.get("target_across", [0, 0, 1])
	var across_t := Vector3(ta[0], ta[1], ta[2]).normalized()
	var srest := func(bn: String) -> Transform3D:
		return bind[bn] if bind.has(bn) else sg0[ssk.find_bone(bn)]
	for side: String in RR:
		var a_s: Vector3 = ((srest.call(RR[side][0]) as Transform3D).origin - (srest.call(RR[side][1]) as Transform3D).origin).normalized()
		for k: String in ["upperarm." + side, "lowerarm." + side]:
			var dt: Vector3 = (tg[ti[CHAIN[k]]].origin - tg[ti[k]].origin).normalized()
			var ds: Vector3 = ((sg[CHAIN[k]] as Transform3D).origin - (sg[k] as Transform3D).origin).normalized()
			var full: Quaternion = q(_frame(ds, a_s) * _frame(dt, across_t).inverse())
			var fix := rad_to_deg(((cq[k] as Quaternion).inverse() * full).get_angle())
			if fix > 180.0:
				fix = 360.0 - fix
			if fix > MAX_ROLL_FIX:
				# referencia de dedos poco fiable en este modelo: se queda la rotación mínima
				roll_fix[k] = "omitido %.0f°" % fix
				continue
			roll_fix[k] = snappedf(fix, 0.1)
			cq[k] = full
	for k: String in INHERIT:
		cq[k] = cq[INHERIT[k]]
	var tracks := {}
	for t in anim.get_track_count():
		var tp := anim.track_get_path(t)
		var bn := String(tp.get_concatenated_subnames()) if tp.get_subname_count() > 0 else String(tp.get_name(tp.get_name_count() - 1))
		tracks[bn + str(anim.track_get_type(t))] = t
	var order: Array = MAP.keys()
	var depth := func(i: int) -> int:
		var d := 0
		while tsk.get_bone_parent(i) >= 0:
			i = tsk.get_bone_parent(i); d += 1
		return d
	order.sort_custom(func(a, b): return depth.call(ti[a]) < depth.call(ti[b]))
	# cadena constante de huesos KayKit no mapeados entre cada hueso y su padre mapeado
	var pchain := {}
	var pkey := {}
	for k: String in order:
		var p := tsk.get_bone_parent(ti[k])
		var c := Quaternion.IDENTITY
		while p >= 0 and not MAP.has(tsk.get_bone_name(p)):
			c = q(tsk.get_bone_rest(p).basis) * c; p = tsk.get_bone_parent(p)
		pchain[k] = c
		pkey[k] = tsk.get_bone_name(p) if p >= 0 else ""
	var out := Animation.new()
	out.length = anim.length
	var rt := {}
	for k: String in order:
		rt[k] = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt[k], NodePath("Rig/Skeleton3D:" + k))
	var pt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, NodePath("Rig/Skeleton3D:hips"))
	var hips_rest: Transform3D = sg.hips
	var ratio: float = tg[ti.hips].origin.y / maxf(0.01, hips_rest.origin.y)
	var fps := float(P.get("fps", 30))
	var n := int(ceil(anim.length * fps))
	var sidx := {}
	for k: String in MAP:
		sidx[k] = ssk.find_bone(MAP[k])
	for fi in n + 1:
		var tt := minf(anim.length, fi / fps)
		var g: Array[Transform3D] = []
		for i in ssk.get_bone_count():
			var r := ssk.get_bone_rest(i)
			var b := r.basis
			var o := r.origin
			var nm := ssk.get_bone_name(i)
			if nm == root_bone and keep_y and tracks.has(nm + str(Animation.TYPE_POSITION_3D)):
				# packs que suben/bajan el cuerpo con la raíz (saltos, agacharse): solo se conserva la altura
				o.y = anim.position_track_interpolate(tracks[nm + str(Animation.TYPE_POSITION_3D)], tt).y
			elif nm != root_bone: # el hueso raíz (root motion) se descarta entero
				var kr := nm + str(Animation.TYPE_ROTATION_3D)
				var kp := nm + str(Animation.TYPE_POSITION_3D)
				if tracks.has(kr): b = Basis(anim.rotation_track_interpolate(tracks[kr], tt))
				if tracks.has(kp): o = anim.position_track_interpolate(tracks[kp], tt)
			var p := ssk.get_bone_parent(i)
			g.append((g[p] if p >= 0 else Transform3D.IDENTITY) * Transform3D(b, o))
		var at := {}
		var wsd := {}
		for k: String in order:
			var ws: Quaternion = q(g[sidx[k]].basis) * q((sg[k] as Transform3D).basis).inverse()
			wsd[k] = ws
			at[k] = ws * cq.get(k, Quaternion.IDENTITY) * q(tg[ti[k]].basis)
		# Reparto del giro del antebrazo: en rigs con huesos de giro (UE) el antebrazo principal no
		# gira y todo el giro queda en la mano; el rig KayKit lo lleva en el antebrazo (sus clips
		# nativos: muñeca/antebrazo ≈ 2°), así que la mano «retorcida» sobre un antebrazo quieto se ve
		# como brazos torcidos. «forearm_twist» = fracción del giro mano/antebrazo (alrededor del eje
		# del antebrazo) que pasa al antebrazo destino (1 = convención KayKit).
		for side: String in ["l", "r"]:
			var lk := "lowerarm." + side
			var wk := "wrist." + side
			if not at.has(lk) or not at.has(wk):
				continue
			var d: Vector3 = ((wsd[lk] as Quaternion) * (cq[lk] as Quaternion)) * (tg[ti[wk]].origin - tg[ti[lk]].origin).normalized()
			var rel: Quaternion = (wsd[wk] as Quaternion) * (wsd[lk] as Quaternion).inverse()
			var th := _twist_angle(rel, d)
			var moved := th * fa_twist
			if absf(moved) > 0.0001:
				at[lk] = Quaternion(d, moved) * (at[lk] as Quaternion)
			twist_max[0] = maxf(twist_max[0], absf(rad_to_deg(th)))
			twist_max[1] = maxf(twist_max[1], absf(rad_to_deg(th - moved)))
		for k: String in order:
			var ap: Quaternion = (at[pkey[k]] as Quaternion) * pchain[k] if pkey[k] != "" else pchain[k]
			out.rotation_track_insert_key(rt[k], tt, (ap.inverse() * at[k]).normalized())
		var hp := tg[ti.hips].origin
		hp.y += (g[sidx.hips].origin.y - hips_rest.origin.y) * ratio
		out.position_track_insert_key(pt, tt, hp)
	return out
