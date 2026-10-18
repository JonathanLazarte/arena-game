extends SceneTree
## Bibliotecas convertidas con tools/import_anim_pack.gd (assets/animations/*.manifest.json):
## cargan, tienen tantos clips como el manifiesto, sin traslación de raíz (caderas fijas en x/z,
## ninguna pista sobre «root») y todas las pistas apuntan a huesos del rig KayKit.
## godot --headless --path . -s res://tests/test_anim_pack.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	var kay: Node = (load("res://assets/models/Knight.glb") as PackedScene).instantiate()
	var sk := kay.find_child("Skeleton3D", true, false) as Skeleton3D
	var hips_rest := sk.get_bone_global_rest(sk.find_bone("hips")).origin
	var n := 0
	for f in DirAccess.get_files_at("res://assets/animations"):
		if not f.ends_with(".manifest.json"):
			continue
		n += 1
		var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/" + f))
		var res_path := "res://assets/animations/" + f.trim_suffix(".manifest.json") + ".res"
		var lib := load(res_path) as AnimationLibrary
		check(lib != null, "%s carga" % res_path)
		if lib == null:
			continue
		check(lib.get_animation_list().size() == man.clips.size() and man.clips.size() > 0, "%s: %d clips (manifiesto %d)" % [f, lib.get_animation_list().size(), man.clips.size()])
		var bad_root := 0
		var bad_path := 0
		var bad_loop := 0
		var max_xz := 0.0
		for c: Dictionary in man.clips:
			var a := lib.get_animation(c.name)
			if a == null:
				bad_path += 1; continue
			if (a.loop_mode != Animation.LOOP_NONE) != bool(c.loop):
				bad_loop += 1
			for t in a.get_track_count():
				var bn := String(a.track_get_path(t).get_concatenated_subnames())
				if sk.find_bone(bn) < 0:
					bad_path += 1
				if bn == "root":
					bad_root += 1
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
					if bn != "hips":
						bad_root += 1
					for k in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, k)
						max_xz = maxf(max_xz, Vector2(v.x - hips_rest.x, v.z - hips_rest.z).length())
		check(bad_path == 0, "%s: pistas sobre huesos KayKit (%d malas)" % [f, bad_path])
		check(bad_root == 0 and max_xz < 0.001, "%s: sin traslación de raíz (desvío x/z caderas %.4f m)" % [f, max_xz])
		check(bad_loop == 0, "%s: bucles como en el manifiesto" % f)
	check(n > 0, "hay al menos una biblioteca convertida (%d)" % n)
	# perfiles con lista explícita de clips: la biblioteca trae exactamente esos nombres
	for pf in DirAccess.get_files_at("res://tools/anim_profiles"):
		var prof = JSON.parse_string(FileAccess.get_file_as_string("res://tools/anim_profiles/" + pf))
		if typeof(prof) != TYPE_DICTIONARY:
			continue
		for ch: Dictionary in prof.get("characters", []):
			if not ch.has("clips") or not ResourceLoader.exists(String(ch.out)):
				continue
			var lib := load(String(ch.out)) as AnimationLibrary
			var want: Array = (ch.clips as Dictionary).keys()
			var have: Array = Array(lib.get_animation_list()).map(func(x): return String(x))
			want.sort(); have.sort()
			check(want == have, "%s/%s: clips del perfil (%d) = biblioteca (%d)" % [pf, ch.id, want.size(), have.size()])
	# raíz que lleva la altura (root_keep_vertical): el salto mueve las caderas en y
	if ResourceLoader.exists("res://assets/animations/doublel_one_hand.res"):
		var j := (load("res://assets/animations/doublel_one_hand.res") as AnimationLibrary).get_animation("jump")
		var lo := 9.0
		var hi := -9.0
		for t in j.get_track_count():
			if j.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in j.track_get_key_count(t):
					var y: float = j.track_get_key_value(t, k).y
					lo = minf(lo, y); hi = maxf(hi, y)
		check(hi - lo > 0.05, "doublel jump: altura de caderas varía (%.2f m)" % (hi - lo))
	kay.free()
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
