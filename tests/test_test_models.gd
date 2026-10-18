extends SceneTree
## Rama test-models: los 5 personajes de prueba (modelos de terceros) cargan, se renombran a
## huesos KayKit y sus clips horneados siguen la pose del Caballero KayKit (direcciones de huesos).
## godot --headless --path . -s res://tests/test_test_models.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

const IDS := ["test_jane", "test_yoomi", "test_mita", "test_nightgown", "test_knight"]
const SEGS := [["upperarm.l", "lowerarm.l"], ["lowerarm.l", "hand.l"], ["upperarm.r", "lowerarm.r"], ["lowerarm.r", "hand.r"],
	["upperleg.l", "lowerleg.l"], ["lowerleg.l", "foot.l"], ["upperleg.r", "lowerleg.r"], ["lowerleg.r", "foot.r"], ["hips", "head"]]
const CLIPS := [["Idle", 0.5], ["1H_Melee_Attack_Chop", 0.4], ["Running_A", 0.2], ["Dodge_Forward", 0.2], ["mx/roll_f", 0.3], ["mx/sns_light0", 0.3], ["Death_A", 0.7]]

func _initialize() -> void:
	_run()

func _vis(cd: CharacterDef) -> KnightVisual:
	var v := KnightVisual.new()
	get_root().add_child(v)
	v.setup(Color.WHITE, cd)
	v.tree.active = false
	return v

func _dirs(v: KnightVisual, clip: String, t: float) -> Dictionary:
	v.ap.play(clip)
	v.ap.seek(t, true)
	var sk := v.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var out := {}
	for s: Array in SEGS:
		var a := v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(s[0])).origin))
		var b := v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(s[1])).origin))
		out[s[0] + ">" + s[1]] = (b - a).normalized()
	return out

func _run() -> void:
	await process_frame
	var ref := _vis(load("res://resources/characters/caballero.tres"))
	var ref_sword := ref.sword.global_transform.basis.get_scale().y
	for id: String in IDS:
		var cd := Catalog.character(id)
		check(cd.id == id and cd.display_name.begins_with("Prueba: "), "%s en el catálogo con nombre neutro (%s)" % [id, cd.display_name])
		check(Progression.req("character", id) == [1, 0], "%s se recluta gratis" % id)
		var v := _vis(cd)
		var sk := v.model.find_child("Skeleton3D", true, false) as Skeleton3D
		var missing := []
		for b in ["hips", "spine", "chest", "head", "hand.l", "hand.r", "handslot.l", "handslot.r", "foot.l", "foot.r", "toes.l", "lowerleg.r"]:
			if sk == null or sk.find_bone(b) < 0:
				missing.append(b)
		check(missing.is_empty(), "%s: huesos KayKit tras renombrar %s" % [id, str(missing)])
		check(v.ap.has_animation("Idle") and v.ap.has_animation("mx/roll_f") and v.tree != null, "%s: clips KayKit + mx y AnimationTree" % id)
		var worst := 0.0
		var worst_at := ""
		for c: Array in CLIPS:
			var dr := _dirs(ref, c[0], c[1])
			var dt := _dirs(v, c[0], c[1])
			for k: String in dr:
				var ang := rad_to_deg((dr[k] as Vector3).angle_to(dt[k]))
				if ang > worst:
					worst = ang
					worst_at = "%s %s" % [c[0], k]
		check(worst < 20.0, "%s: sigue la pose KayKit (peor desvío %.1f° en %s)" % [id, worst, worst_at])
		var sw := v.sword.global_transform.basis.get_scale().y
		check(absf(sw / ref_sword - KnightVisual.TEST_WEAPON_K) < 0.03, "%s: arma a escala realista (%.3f vs %.3f)" % [id, sw, ref_sword])
		var bad_binds := 0
		for mi in AnimUtil.meshes(v.model):
			if mi.skin:
				for b in mi.skin.get_bind_count():
					var bn := String(mi.skin.get_bind_name(b))
					if bn != "" and sk.find_bone(bn) < 0:
						bad_binds += 1
		check(bad_binds == 0, "%s: las pieles siguen enlazadas a huesos existentes (%d rotos)" % [id, bad_binds])
		var hs := v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("handslot.r")).origin))
		var hd := v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("hand.r")).origin))
		var att := v.sword.get_parent()
		while att != null and not att is BoneAttachment3D:
			att = att.get_parent()
		check(hs.distance_to(hd) < 0.25 and att != null and (att as BoneAttachment3D).bone_name == "handslot.r", "%s: el arma va en la mano derecha (handslot a %.2f de la mano)" % [id, hs.distance_to(hd)])
		var feet := v.lowest_body_y()
		check(feet > -0.5 and feet < 1.5, "%s: altura del cuerpo razonable (%.2f)" % [id, feet])
		v.free()
	ref.free()
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
