extends SceneTree
## Esqueleto humanoide44 (docs/SKELETON_GUIDE.md): los personajes con h44_lib cargan la biblioteca
## "h44", sus pistas apuntan a huesos existentes, los huesos humanoide44 están mapeados, la pose
## sigue a la del clip fuente (si el JSON fuente está en assets_raw/) y las armas siguen enganchadas.
## godot --headless --path . -s res://tests/test_humanoid44.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

const IDS := ["caballero", "asesino", "test_knight_h44"]  # el último: re-rig real (Blender), fuera del roster
const CORE := ["Pelvis", "Spine", "Spine2", "Neck", "Head", "L_Clavicle", "L_UpperArm", "L_Forearm", "L_Hand",
	"R_Clavicle", "R_UpperArm", "R_Forearm", "R_Hand", "L_Thigh", "L_Calf", "L_Foot", "L_Toe0",
	"R_Thigh", "R_Calf", "R_Foot", "R_Toe0", "L_Finger1", "R_Finger1"]
const SEGS := [["L_UpperArm", "L_Forearm"], ["L_Forearm", "L_Hand"], ["R_UpperArm", "R_Forearm"], ["R_Forearm", "R_Hand"],
	["L_Thigh", "L_Calf"], ["L_Calf", "L_Foot"], ["R_Thigh", "R_Calf"], ["R_Calf", "R_Foot"], ["Pelvis", "Head"]]
const CFG := "res://tools/rig/h44_targets.json"

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	var maps := {}
	for t: Dictionary in cfg.targets:
		maps[t.out] = t.map
	for id: String in IDS:
		var cd: CharacterDef = Catalog.character(id) if id != "test_knight_h44" else load("res://resources/characters/test_knight_h44.tres")
		check(cd.id == id and cd.h44_lib != "" and ResourceLoader.exists(cd.h44_lib), "%s: h44_lib existe (%s)" % [id, cd.h44_lib])
		var v := KnightVisual.new()
		get_root().add_child(v)
		v.setup(Color.WHITE, cd)
		v.tree.active = false
		var sk := v.model.find_child("Skeleton3D", true, false) as Skeleton3D
		check(v.ap.has_animation_library(&"h44"), "%s: biblioteca h44 en el AnimationPlayer" % id)
		check(v.ap.has_animation("Idle") and v.ap.has_animation("mx/roll_f"), "%s: clips KayKit + mx siguen" % id)
		if id == "test_knight_h44":
			var miss := ["Spine1", "R_Elbow", "L_Elbow", "R_Hip", "face_root"].filter(func(b): return sk.find_bone(b) < 0)
			check(miss.is_empty(), "%s: el esqueleto del modelo ES humanoide44 (faltan %s)" % [id, miss])
		var lib := v.ap.get_animation_library(&"h44")
		var clips := lib.get_animation_list()
		check(clips.size() >= 1, "%s: %d clips humanoide44 %s" % [id, clips.size(), clips])
		# Pistas -> huesos existentes
		var bad := []
		var root := v.ap.get_node(v.ap.root_node)
		for c in clips:
			var a := lib.get_animation(c)
			for ti in a.get_track_count():
				var p := a.track_get_path(ti)
				var nd := root.get_node_or_null(NodePath(String(p.get_concatenated_names())))
				if not (nd is Skeleton3D) or (nd as Skeleton3D).find_bone(p.get_concatenated_subnames()) < 0:
					bad.append("%s:%s" % [c, p])
		check(bad.is_empty(), "%s: todas las pistas h44 resuelven a huesos %s" % [id, str(bad.slice(0, 5))])
		# Huesos humanoide44 mapeados al esqueleto (mapa + renombrado del juego)
		var mapped: Array = lib.get_meta("h44_map", [])
		var miss := []
		for b in CORE:
			if not b in mapped:
				miss.append(b)
		check(miss.is_empty(), "%s: huesos humanoide44 principales mapeados (%d/44) faltan %s" % [id, mapped.size(), str(miss)])
		# Fidelidad de pose contra el JSON fuente (si está disponible localmente)
		var src_dir: String = cfg.src_dir
		var worst := 0.0
		var worst_at := ""
		var tested := 0
		for c in clips:
			var fn: String = cfg.clips.get(String(c), "")
			var jp := src_dir.path_join(fn)
			if fn == "" or not FileAccess.file_exists(jp):
				continue
			var h := Humanoid44.load_json(jp)
			var hmap := BakeH44.resolve_map_for(sk, maps.get(cd.h44_lib, ""), cd.retarget_lib)
			for fr in [0, h.num_frames / 2, h.num_frames - 1]:
				v.ap.play("h44/" + String(c))
				v.ap.seek(fr / h.fps, true)
				var g := h.globals(fr)
				for s: Array in SEGS:
					if not (hmap.has(s[0]) and hmap.has(s[1])):
						continue
					var ds := BakeH44.mirror_xf(g[h.idx(s[1])]).origin - BakeH44.mirror_xf(g[h.idx(s[0])]).origin
					var mt := v.model.global_transform.affine_inverse() * sk.global_transform
					var dt := mt * sk.get_bone_global_pose(sk.find_bone(hmap[s[1]])).origin - mt * sk.get_bone_global_pose(sk.find_bone(hmap[s[0]])).origin
					var ang := rad_to_deg(ds.normalized().angle_to(dt.normalized()))
					tested += 1
					if ang > worst:
						worst = ang
						worst_at = "%s f%d %s>%s" % [c, fr, s[0], s[1]]
		if tested > 0:
			check(worst < 30.0, "%s: pose sigue al clip fuente, peor desvío %.1f° (%s, %d segmentos)" % [id, worst, worst_at, tested])
		else:
			print("SKIP  %s: sin JSON fuente en %s (comparación de pose omitida)" % [id, src_dir])
		# Armas: siguen enganchadas a la mano durante un clip h44
		v.ap.play("h44/" + String(clips[0]))
		v.ap.seek(lib.get_animation(clips[0]).length * 0.5, true)
		var ba := v.sword.get_parent()
		while ba != null and not (ba is BoneAttachment3D):
			ba = ba.get_parent()
		check(ba != null and sk.find_bone((ba as BoneAttachment3D).bone_name) >= 0, "%s: arma en BoneAttachment3D a un hueso existente (%s)" % [id, (ba as BoneAttachment3D).bone_name if ba else "-"])
		if ba:
			await process_frame
			var hand := sk.to_global(sk.get_bone_global_pose(sk.find_bone((ba as BoneAttachment3D).bone_name)).origin)
			check((ba as Node3D).global_position.distance_to(hand) < 0.05, "%s: el enganche sigue al hueso con el clip h44" % id)
		v.queue_free()
		await process_frame
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
