## Hornea clips del esqueleto humanoide44 (JSON del conversor propio) al esqueleto de cada
## personaje, con el mismo reapuntado por delta de orientación global que usa
## tools/bake_test_models.gd (el modelo conserva su propio esqueleto y pesos).
## Las pistas salen con los nombres FINALES que ve el juego: los huesos que el horneado KayKit
## renombra (hips, upperarm.l…) usan ese nombre; el resto conserva el del modelo.
##
## Uso (headless):
##   godot --headless --path . -s res://tools/rig/bake_humanoid44.gd                 # todos
##   ONLY=test_knight godot --headless --path . -s res://tools/rig/bake_humanoid44.gd
##   CONFIG=res://otra_config.json ...   (por defecto res://tools/rig/h44_targets.json)
## Ver docs/SKELETON_GUIDE.md.
extends SceneTree
class_name BakeH44

## El conversor deja el personaje mirando a +X con la izquierda en +Z (marco espejado respecto
## de glTF). Se pasa al marco del juego (mira a +Z, izquierda en +X) intercambiando X y Z.
const MIRROR := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
## Hereda la corrección de reposo del segmento padre (huesos sin cadena propia).
const INHERIT := {"Head": "Neck", "L_Hand": "L_Forearm", "R_Hand": "R_Forearm", "L_Toe0": "L_Foot", "R_Toe0": "R_Foot",
	"Spine2": "Spine1"}

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

static func mirror_xf(t: Transform3D) -> Transform3D:
	return Transform3D(MIRROR * t.basis * MIRROR, MIRROR * t.origin)

## Resuelve el mapa humanoide44 -> índice de hueso. Acepta el nombre exacto o con el sufijo
## numérico que agrega el export glTF de Sketchfab ("L UpperArm_39").
static func resolve_map(sk: Skeleton3D, map_path: String) -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var m: Dictionary = d.get("map", {})
	var strip: String = d.get("strip_prefix", "")
	var by_name := {}
	var re := RegEx.create_from_string("_\\d+$")
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		for key in [bn, re.sub(bn, ""), bn.trim_prefix(strip), re.sub(bn.trim_prefix(strip), "")]:
			if not by_name.has(key):
				by_name[key] = i
	var out := {}
	for h: String in m:
		var want: String = m[h]
		for key in [want, want.trim_prefix(strip)]:
			if by_name.has(key):
				out[h] = by_name[key]
				break
	return out

## Mapa humanoide44 -> nombre FINAL del hueso (el que ve el juego tras renombrar). Para tests.
static func resolve_map_for(sk_renamed: Skeleton3D, map_path: String, retarget_lib: String) -> Dictionary:
	var out := {}
	if map_path == "":
		return out
	var model: Node = null
	var lib := load(retarget_lib) as AnimationLibrary if retarget_lib != "" else null
	var kmap: Dictionary = lib.get_meta("bone_map", {}) if lib else {}
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var re := RegEx.create_from_string("_\\d+$")
	var inv := {}
	for k: String in kmap:
		inv[kmap[k]] = k
		inv[re.sub(String(kmap[k]), "")] = k
	for h: String in d.map:
		var want: String = d.map[h]
		if inv.has(want):
			out[h] = inv[want]
			continue
		for i in sk_renamed.get_bone_count():
			var bn := sk_renamed.get_bone_name(i)
			if bn == want or re.sub(bn, "") == want:
				out[h] = bn
				break
	return out

## Nombre con que el juego verá cada hueso tras KnightVisual._prepare_retarget.
static func final_names(sk: Skeleton3D, kaykit_map: Dictionary) -> PackedStringArray:
	var by_idx := {}
	for k: String in kaykit_map:
		var i := sk.find_bone(kaykit_map[k])
		if i >= 0:
			by_idx[i] = k
	var out: PackedStringArray = []
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if by_idx.has(i):
			out.append(by_idx[i])
		elif kaykit_map.has(bn) or bn.begins_with("handslot."):
			out.append(bn + "_orig")
		else:
			out.append(bn)
	return out

func _init() -> void:
	var cfg_path := OS.get_environment("CONFIG")
	if cfg_path == "":
		cfg_path = "res://tools/rig/h44_targets.json"
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
	var only := OS.get_environment("ONLY")
	var srcs := {}
	for clip: String in cfg.clips:
		var p: String = String(cfg.src_dir).path_join(cfg.clips[clip])
		if not FileAccess.file_exists(p):
			push_error("falta clip fuente " + p)
			continue
		var h := Humanoid44.load_json(p)
		if h:
			if not h.unknown_bones().is_empty():
				push_warning("%s: huesos fuera de humanoide44: %s" % [clip, h.unknown_bones()])
			srcs[clip] = h
	for t: Dictionary in cfg.targets:
		if only != "" and t.id != only:
			continue
		bake_target(t, srcs, float(cfg.get("fps", 30)))
	quit()

static func bake_target(t: Dictionary, srcs: Dictionary, fps: float) -> void:
	var model: Node3D = (load(t.model) as PackedScene).instantiate()
	var kaykit_map := {}
	var skel_path := ""
	if t.get("retarget_lib", "") != "" and ResourceLoader.exists(t.retarget_lib):
		var rl := load(t.retarget_lib) as AnimationLibrary
		kaykit_map = rl.get_meta("bone_map", {})
		skel_path = rl.get_meta("skeleton_path", "")
	var tsk := model.get_node_or_null(NodePath(skel_path)) as Skeleton3D if skel_path != "" else null
	if tsk == null:
		tsk = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		skel_path = String(model.get_path_to(tsk))
	var hmap := resolve_map(tsk, t.map) # hueso h44 -> índice destino
	var fnames := final_names(tsk, kaykit_map)
	var kt := rel_xf(tsk, model)
	var nt := tsk.get_bone_count()
	var tg: Array[Transform3D] = [] # reposo global destino (espacio del modelo)
	for i in nt:
		var p := tsk.get_bone_parent(i)
		tg.append((tg[p] if p >= 0 else kt) * tsk.get_bone_rest(i))
	var lib := AnimationLibrary.new()
	var missing: PackedStringArray = []
	for b in Humanoid44.BONES:
		if not hmap.has(b):
			missing.append(b)
	for clip: String in srcs:
		var h: Humanoid44 = srcs[clip]
		var srest := h.globals(-1)
		for i in srest.size():
			srest[i] = mirror_xf(srest[i])
		# Corrección de reposo por segmento: lleva la dirección del hueso destino a la de la fuente.
		var C := {}
		for b: String in hmap:
			if Humanoid44.CHAIN.has(b) and hmap.has(Humanoid44.CHAIN[b]):
				var c: String = Humanoid44.CHAIN[b]
				var ds := srest[h.idx(c)].origin - srest[h.idx(b)].origin
				var dt := tg[hmap[c]].origin - tg[hmap[b]].origin
				if ds.length() > 1e-5 and dt.length() > 1e-5:
					C[b] = Quaternion(dt.normalized(), ds.normalized())
		for b: String in hmap:
			if not C.has(b):
				var up: String = INHERIT.get(b, "")
				if up == "" and b.contains("Finger"):
					up = b.substr(0, 2) + "Forearm"
				C[b] = C.get(up, Quaternion.IDENTITY)
		# Orden por profundidad en el destino y padre mapeado efectivo
		var t_of := {}
		for b: String in hmap:
			t_of[hmap[b]] = b
		var depth := func(i: int) -> int:
			var d := 0
			var p := tsk.get_bone_parent(i)
			while p >= 0:
				d += 1
				p = tsk.get_bone_parent(p)
			return d
		var order: Array = hmap.keys()
		order.sort_custom(func(a, b): return depth.call(hmap[a]) < depth.call(hmap[b]))
		var par := {}
		for b: String in order:
			var chain := Quaternion.IDENTITY
			var cur := tsk.get_bone_parent(hmap[b])
			while cur >= 0 and not t_of.has(cur):
				chain = q(tsk.get_bone_rest(cur).basis) * chain
				cur = tsk.get_bone_parent(cur)
			par[b] = [t_of[cur], chain] if cur >= 0 else ["", q(kt.basis) * chain]
		var hip_b := "Pelvis"
		var hip_ti: int = hmap.get(hip_b, -1)
		var ratio := 1.0
		if hip_ti >= 0:
			ratio = tg[hip_ti].origin.y / maxf(0.001, srest[h.idx(hip_b)].origin.y)
		var hip_parent := tsk.get_bone_parent(hip_ti) if hip_ti >= 0 else -1
		var hip_parent_g := tg[hip_parent] if hip_parent >= 0 else kt
		var anim := Animation.new()
		anim.length = h.duration
		var lc := clip.to_lower()
		if lc.contains("idle") or lc.contains("walk") or lc.contains("run") or lc.contains("loop"):
			anim.loop_mode = Animation.LOOP_LINEAR
		var rt := {}
		for b: String in order:
			rt[b] = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(rt[b], NodePath(skel_path + ":" + fnames[hmap[b]]))
		var pt := -1
		if hip_ti >= 0:
			pt = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pt, NodePath(skel_path + ":" + fnames[hip_ti]))
		var sgq := {}
		for b: String in hmap:
			sgq[b] = q(srest[h.idx(b)].basis)
		var n := maxi(1, int(round(h.duration * fps)))
		for fi in n + 1:
			var time := minf(h.duration, fi / fps)
			var g := h.globals(clampi(int(round(time * h.fps)), 0, h.num_frames - 1))
			var at := {}
			for b: String in order:
				var gb := mirror_xf(g[h.idx(b)])
				var ws: Quaternion = q(gb.basis) * (sgq[b] as Quaternion).inverse()
				at[b] = ws * (C[b] as Quaternion) * q(tg[hmap[b]].basis)
				var pi: Array = par[b]
				var ap: Quaternion = (at[pi[0]] as Quaternion) * (pi[1] as Quaternion) if pi[0] != "" else pi[1]
				anim.rotation_track_insert_key(rt[b], time, (ap.inverse() * (at[b] as Quaternion)).normalized())
			if pt >= 0:
				var dp := (mirror_xf(g[h.idx(hip_b)]).origin - srest[h.idx(hip_b)].origin) * ratio
				var hp := tg[hip_ti].origin + dp
				anim.position_track_insert_key(pt, time, hip_parent_g.affine_inverse() * hp)
		lib.add_animation(clip, anim)
	lib.set_meta("h44_map", hmap.keys())
	lib.set_meta("h44_missing", missing)
	lib.set_meta("skeleton_path", skel_path)
	var err := ResourceSaver.save(lib, t.out, ResourceSaver.FLAG_COMPRESS)
	print("%s: %d/%d huesos humanoide44 mapeados (sin mapear: %s), %d clips -> %s err %d" % [t.id, hmap.size(),
		Humanoid44.BONES.size(), ", ".join(missing), lib.get_animation_list().size(), t.out, err])
	model.free()
