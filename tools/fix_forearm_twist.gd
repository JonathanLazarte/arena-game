extends SceneTree
## Pasa al antebrazo el giro de la mano alrededor del eje del antebrazo en una biblioteca ya
## reapuntada al rig KayKit (convención KayKit: sus clips nativos casi no giran la muñeca respecto
## al antebrazo, ≈ 2°; los reapuntados dejaban hasta 120-180° en la muñeca → brazos «torcidos»).
## La pose global de la muñeca/mano no cambia (solo cómo se reparte el giro), la del antebrazo
## gira sobre su propio eje (el codo y la muñeca no se mueven).
## godot --headless --path . -s res://tools/fix_forearm_twist.gd -- --lib res://assets/animations/mixamo/lib_kaykit.res [--frac 1.0] [--out <ruta>]
const TARGET := "res://assets/models/Knight.glb"

static func twist_angle(r: Quaternion, axis: Vector3) -> float:
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

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ua := OS.get_cmdline_user_args()
	var lib_path := ua[ua.find("--lib") + 1] if ua.has("--lib") else ""
	var frac := float(ua[ua.find("--frac") + 1]) if ua.has("--frac") else 1.0
	var out := ua[ua.find("--out") + 1] if ua.has("--out") else lib_path
	if lib_path == "":
		printerr("uso: -- --lib <biblioteca.res> [--frac 1.0] [--out ruta]"); quit(1); return
	var lib := load(lib_path) as AnimationLibrary
	var tgt: Node3D = load(TARGET).instantiate()
	root.add_child(tgt)
	var sk := tgt.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := AnimationPlayer.new()
	tgt.add_child(ap)
	ap.root_node = ap.get_path_to(tgt)
	var work := AnimationLibrary.new()
	for nm in lib.get_animation_list():
		work.add_animation(nm, (lib.get_animation(nm) as Animation).duplicate(true))
	ap.add_animation_library(&"w", work)
	await process_frame
	var before := 0.0
	var after := 0.0
	for nm in work.get_animation_list():
		var anim := work.get_animation(nm)
		for side: String in ["l", "r"]:
			var lb := "lowerarm." + side
			var wb := "wrist." + side
			var tl := anim.find_track(NodePath("Rig/Skeleton3D:" + lb), Animation.TYPE_ROTATION_3D)
			var tw := anim.find_track(NodePath("Rig/Skeleton3D:" + wb), Animation.TYPE_ROTATION_3D)
			if tl < 0 or tw < 0:
				continue
			var li := sk.find_bone(lb)
			var wi := sk.find_bone(wb)
			var pi := sk.get_bone_parent(li)
			var rl := sk.get_bone_global_rest(li).basis.get_rotation_quaternion()
			var rw := sk.get_bone_global_rest(wi).basis.get_rotation_quaternion()
			var times := {}
			for k in anim.track_get_key_count(tl): times[snappedf(anim.track_get_key_time(tl, k), 0.0001)] = true
			for k in anim.track_get_key_count(tw): times[snappedf(anim.track_get_key_time(tw, k), 0.0001)] = true
			var ts: Array = times.keys()
			ts.sort()
			var newl := {}
			var neww := {}
			for t: float in ts:
				ap.play(StringName("w/" + String(nm)))
				ap.seek(t, true)
				ap.pause()
				ap.advance(0)
				var gp := sk.get_bone_global_pose(pi)
				var gl := sk.get_bone_global_pose(li)
				var gw := sk.get_bone_global_pose(wi)
				var axis := (gw.origin - gl.origin).normalized()
				var dl := gl.basis.get_rotation_quaternion() * rl.inverse()
				var dw := gw.basis.get_rotation_quaternion() * rw.inverse()
				var th := twist_angle(dw * dl.inverse(), axis)
				before = maxf(before, absf(rad_to_deg(th)))
				after = maxf(after, absf(rad_to_deg(th * (1.0 - frac))))
				var ql := Quaternion(axis, th * frac) * gl.basis.get_rotation_quaternion()
				newl[t] = (gp.basis.get_rotation_quaternion().inverse() * ql).normalized()
				neww[t] = (ql.inverse() * gw.basis.get_rotation_quaternion()).normalized()
			# reescribe las dos pistas con las claves nuevas (después de muestrear todo el clip)
			for k in range(anim.track_get_key_count(tl) - 1, -1, -1): anim.track_remove_key(tl, k)
			for k in range(anim.track_get_key_count(tw) - 1, -1, -1): anim.track_remove_key(tw, k)
			for t: float in ts:
				anim.rotation_track_insert_key(tl, t, newl[t])
				anim.rotation_track_insert_key(tw, t, neww[t])
	ResourceSaver.save(work, out, ResourceSaver.FLAG_COMPRESS)
	print("[twist] %s: %d clips, giro muñeca/antebrazo máx %.0f° → %.0f° (frac %.2f) → %s" % [lib_path, work.get_animation_list().size(), before, after, frac, out])
	quit()
