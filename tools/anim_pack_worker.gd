extends SceneTree
## Trabajador de tools/import_anim_pack.gd: corre DENTRO del proyecto temporal (no en el repo).
## Reapuntado por delta global (misma matemática que tools/retarget_kaykit.gd):
##   Ws = Apose_src · Grest_src⁻¹ ;  Apose_tgt = Ws · C · Grest_tgt
## C = rotación mínima que lleva la dirección de cada segmento del reposo KayKit a la del reposo
## fuente (cadenas caderas-columna-cabeza, brazos, piernas); los huesos hoja la heredan.
## Reposo fuente = pose de bind del modelo del pack (si existe; arregla el giro de antebrazo/mano),
## llevada al espacio de los clips con «bind_axes». Si no hay modelo, se usa el frame 0.
## Root motion: el hueso raíz («root_bone») se ignora entero (con «root_keep_vertical» se conserva su altura); de la pelvis solo queda la altura
## (escalada por la relación de alturas de cadera); x/z quedan en el reposo KayKit.

var P: Dictionary

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
		for k: String in order:
			var ws: Quaternion = q(g[sidx[k]].basis) * q((sg[k] as Transform3D).basis).inverse()
			at[k] = ws * cq.get(k, Quaternion.IDENTITY) * q(tg[ti[k]].basis)
			var ap: Quaternion = (at[pkey[k]] as Quaternion) * pchain[k] if pkey[k] != "" else pchain[k]
			out.rotation_track_insert_key(rt[k], tt, (ap.inverse() * at[k]).normalized())
		var hp := tg[ti.hips].origin
		hp.y += (g[sidx.hips].origin.y - hips_rest.origin.y) * ratio
		out.position_track_insert_key(pt, tt, hp)
	return out
