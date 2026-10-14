extends SceneTree
## Ronda 27: las animaciones Mixamo importadas apuntan al esqueleto humanoide de Godot
## (%GeneralSkeleton + SkeletonProfileHumanoid) y se reproducen en un esqueleto humanoide genérico.
## godot --headless --path . -s res://tests/test_mixamo_anims.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var prof := SkeletonProfileHumanoid.new()
	var all := load("res://assets/animations/mixamo/lib_mixamo_all.res") as AnimationLibrary
	check(all != null and all.get_animation_list().size() == 99, "biblioteca completa: %d animaciones" % (all.get_animation_list().size() if all else 0))
	var bad := []
	for n in all.get_animation_list():
		var a := all.get_animation(n)
		if a.get_track_count() < 20:
			bad.append(n)
		for t in a.get_track_count():
			var p := str(a.track_get_path(t))
			if not p.begins_with("%GeneralSkeleton:") or prof.find_bone(p.get_slice(":", 1)) < 0:
				bad.append(n + " " + p)
				break
	check(bad.is_empty(), "todas las pistas son huesos humanoides %s" % str(bad.slice(0, 3)))
	check(all.get_animation("greatsword_idle").loop_mode == Animation.LOOP_LINEAR and all.get_animation("greatsword_slash").loop_mode == Animation.LOOP_NONE, "reposos en bucle, ataques sin bucle")
	for g in ["paladin", "greatsword", "akai", "xbot", "magic"]:
		check(load("res://assets/animations/mixamo/lib_%s.res" % g) is AnimationLibrary, "biblioteca lib_%s" % g)
	# Esqueleto humanoide genérico construido con el perfil (como el de un modelo propio reapuntado)
	var root := Node3D.new()
	get_root().add_child(root)
	var sk := Skeleton3D.new()
	sk.name = "GeneralSkeleton"
	root.add_child(sk)
	sk.unique_name_in_owner = true
	sk.owner = root
	for i in prof.bone_size:
		sk.add_bone(prof.get_bone_name(i))
	for i in prof.bone_size:
		var par := prof.get_bone_parent(i)
		if par != &"":
			sk.set_bone_parent(i, prof.find_bone(par))
		sk.set_bone_rest(i, prof.get_reference_pose(i))
	sk.reset_bone_poses()
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	ap.owner = root
	ap.add_animation_library("mx", all)
	var arm := sk.find_bone("RightUpperArm")
	var before := sk.get_bone_pose_rotation(arm)
	ap.play("mx/greatsword_slash")
	ap.advance(0.6)
	var after := sk.get_bone_pose_rotation(arm)
	check(not before.is_equal_approx(after), "se reproduce en un esqueleto humanoide genérico (el brazo se mueve)")
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
