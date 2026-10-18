extends SceneTree
## Conversor «clips externos -> biblioteca KayKit» (headless).
## Uso:
##   godot --headless --path . -s res://tools/import_anim_pack.gd -- \
##       --profile res://tools/anim_profiles/explosivellc_knight.json --src /workspace/animpacks/explosivellc [--only knight]
## Copia los FBX crudos (que NUNCA entran al repo) a un proyecto temporal en /tmp con
## nodes/import_as_skeleton_bones=true, los importa allí, y corre tools/anim_pack_worker.gd, que
## reapunta cada clip al esqueleto KayKit y escribe la AnimationLibrary (.res) + manifiesto (.json).
## Luego copia esos dos archivos a la ruta «out» del perfil dentro del repo.

func _init() -> void:
	var args := _args()
	if not args.has("profile") or not args.has("src"):
		printerr("uso: -- --profile <perfil.json> --src <carpeta con los FBX> [--only <id>]")
		quit(2); return
	var prof := load_profile(String(args.profile))
	if prof.is_empty():
		quit(2); return
	var src := String(args.src)
	var scratch := "/tmp/anim_pack_%s" % prof.get("pack", "pack")
	DirAccess.make_dir_recursive_absolute(scratch + "/src")
	var pg := FileAccess.open(scratch + "/project.godot", FileAccess.WRITE)
	pg.store_string("config_version=5\n\n[application]\nconfig/name=\"anim_pack_scratch\"\n")
	pg.close()
	# destino KayKit
	var tgt_res := String(prof.target)
	_copy(ProjectSettings.globalize_path(tgt_res), scratch + "/target.glb")
	var files := DirAccess.get_files_at(src)
	var n := 0
	for ch: Dictionary in prof.characters:
		if args.has("only") and ch.id != args.only:
			continue
		for f in files:
			var low := f.to_lower()
			if not (low.ends_with(".fbx")):
				continue
			if f.begins_with(String(ch.prefix) + "@") or f == String(ch.get("model", "")):
				var dn := f.get_basename() + ".fbx" # Godot solo importa la extensión en minúsculas
				_copy(src.path_join(f), scratch + "/src/" + dn)
				n += 1
	print("copiados %d FBX a %s" % [n, scratch])
	_copy(ProjectSettings.globalize_path("res://tools/anim_pack_worker.gd"), scratch + "/worker.gd")
	var pf := FileAccess.open(scratch + "/profile.json", FileAccess.WRITE) # perfil ya mezclado (extends)
	pf.store_string(JSON.stringify(prof, "\t"))
	pf.close()
	var godot := OS.get_executable_path()
	var out: Array = []
	# 1ª pasada: .import por defecto; luego se fuerzan huesos de esqueleto + fps y se reimporta
	var code := OS.execute(godot, ["--headless", "--path", scratch, "--import"], out, true)
	for f in DirAccess.get_files_at(scratch + "/src"):
		if f.ends_with(".fbx.import"):
			var p := scratch + "/src/" + f
			var t := FileAccess.get_file_as_string(p)
			t = t.replace("nodes/import_as_skeleton_bones=false", "nodes/import_as_skeleton_bones=true")
			t = t.replace("animation/fps=30", "animation/fps=%d" % int(prof.get("fps", 30)))
			var w := FileAccess.open(p, FileAccess.WRITE)
			w.store_string(t)
			w.close()
	code = OS.execute(godot, ["--headless", "--path", scratch, "--import"], out, true)
	print("import: ", code)
	out.clear()
	var wargs := ["--headless", "--path", scratch, "-s", "res://worker.gd", "--", "--profile", "res://profile.json"]
	if args.has("only"):
		wargs += ["--only", String(args.only)]
	code = OS.execute(godot, wargs, out, true)
	for l: String in String("".join(out)).split("\n"):
		if l.begins_with("[anim]"):
			print(l)
	if code != 0:
		printerr("worker falló (%d)" % code)
		quit(1); return
	for ch: Dictionary in prof.characters:
		if args.has("only") and ch.id != args.only:
			continue
		var dst := ProjectSettings.globalize_path(String(ch.out))
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		_copy(scratch + "/out_%s.res" % ch.id, dst)
		_copy(scratch + "/out_%s.json" % ch.id, dst.get_basename() + ".manifest.json")
		print("escrito ", ch.out)
	quit(0)

## Perfil JSON; admite "extends": "<otro perfil>" (se mezcla encima).
static func load_profile(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		printerr("perfil inválido: ", path)
		return {}
	if d.has("extends"):
		var base := load_profile(path.get_base_dir().path_join(String(d.extends)))
		base.merge(d, true)
		d = base
	return d

func _args() -> Dictionary:
	var a := OS.get_cmdline_user_args()
	var d := {}
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			d[a[i].substr(2)] = a[i + 1]; i += 2
		else:
			i += 1
	return d

func _copy(a: String, b: String) -> void:
	var e := DirAccess.copy_absolute(a, b)
	if e != OK:
		printerr("no se pudo copiar ", a, " -> ", b, " (", e, ")")
