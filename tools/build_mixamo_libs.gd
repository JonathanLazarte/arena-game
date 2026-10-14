extends SceneTree
## Ronda 27: junta las animaciones Mixamo importadas (cada FBX = AnimationLibrary con un
## clip «mixamo_com», ya reapuntado al esqueleto humanoide %GeneralSkeleton) en una
## biblioteca por grupo, con nombres limpios y sin pistas que no sean de huesos.
## godot --headless --path . -s res://tools/build_mixamo_libs.gd
const ROOT := "res://assets/animations/mixamo/"
const GROUPS := ["paladin", "greatsword", "akai", "xbot", "magic"]

func _initialize() -> void:
	var prof := SkeletonProfileHumanoid.new()
	var all := AnimationLibrary.new()
	for g: String in GROUPS:
		var lib := AnimationLibrary.new()
		for f in DirAccess.get_files_at(ROOT + g):
			if not f.ends_with(".fbx"):
				continue
			var src := load(ROOT + g + "/" + f) as AnimationLibrary
			var a := (src.get_animation(src.get_animation_list()[0]) as Animation).duplicate(true) as Animation
			for t in range(a.get_track_count() - 1, -1, -1):
				var p := str(a.track_get_path(t))
				if not p.begins_with("%GeneralSkeleton:") or prof.find_bone(p.get_slice(":", 1)) < 0:
					a.remove_track(t)
			var n := f.get_basename().trim_prefix(g + "_")
			lib.add_animation(n, a)
			all.add_animation(g + "_" + n, a)
		print(g, ": ", lib.get_animation_list().size(), " -> ", ResourceSaver.save(lib, ROOT + "lib_%s.res" % g, ResourceSaver.FLAG_COMPRESS))
	print("todas: ", all.get_animation_list().size(), " -> ", ResourceSaver.save(all, ROOT + "lib_mixamo_all.res", ResourceSaver.FLAG_COMPRESS))
	quit()
