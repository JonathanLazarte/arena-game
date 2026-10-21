extends SceneTree
## Enganche de armas guiado por datos (data/weapons/weapons.json + WeaponAttacher).
var fails: int = 0
func _initialize() -> void:
	_run()
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _sk(names: Array) -> Skeleton3D:
	var sk := Skeleton3D.new()
	for n: String in names:
		sk.add_bone(n)
	return sk

func _run() -> void:
	WeaponAttacher.clear_cache()
	var db := WeaponAttacher.load_db()
	check(db.get("weapons") is Dictionary, "weapons.json carga")
	var ids: Array = []
	for w in Catalog.weapons():
		ids.append(w.id)
		check((db["weapons"] as Dictionary).has(w.id), "entrada para %s" % w.id)
	var r := WeaponAttacher.validate(db, ids)
	check((r["errors"] as Array).is_empty(), "weapons.json sin errores %s" % [r["errors"]])
	# Todas deshabilitadas: el juego sigue con el camino clásico
	for id: String in ids:
		check(WeaponAttacher.active_entry(id).is_empty(), "%s sin enganche por datos (comportamiento actual)" % id)

	# Validador detecta errores
	var bad := {"weapons": {"x": {"mesh": "res://no/existe.glb", "hand": "middle",
		"offset": {"position": [0, 1], "scale": [0, 1, 1], "foo": 1}, "bone_overrides": {"mixamo": ""},
		"second_grip": {"position": "a"}}}}
	var br := WeaponAttacher.validate(bad, ids)
	var txt := "\n".join(br["errors"])
	for frag in ["inexistente", "no existe", ".hand", "offset.position", "offset.scale", "offset.foo", "bone_overrides.mixamo", "second_grip"]:
		check(txt.contains(frag), "validador detecta «%s»" % frag)
	check(not (WeaponAttacher.validate({}, [])["errors"] as Array).is_empty(), "validador: falta «weapons»")

	# Resolución de huesos para varios esqueletos
	var e := {"hand": "right"}
	var cases := {"kaykit": ["root", "handslot.r", "hand.r"], "mixamo": ["mixamorig_Hips", "mixamorig_RightHand"],
		"ue": ["pelvis", "hand_r"], "rigify": ["DEF-spine", "DEF-hand.R"], "humanoid": ["Hips", "RightHand"]}
	var expect := {"kaykit": "handslot.r", "mixamo": "mixamorig_RightHand", "ue": "hand_r", "rigify": "DEF-hand.R", "humanoid": "RightHand"}
	for prof: String in cases:
		var sk := _sk(cases[prof])
		check(WeaponAttacher.skeleton_profile(sk) == prof, "perfil %s" % prof)
		check(WeaponAttacher.resolve_bone(sk, e) == expect[prof], "hueso derecho en %s" % prof)
		sk.free()
	var skl := _sk(["Hand.L", "Hand.R"])
	check(WeaponAttacher.resolve_bone(skl, {"hand": "left"}) == "Hand.L", "mano izquierda Hand.L")
	check(WeaponAttacher.resolve_bone(skl, {"hand": "right", "bone": "nope"}) == "Hand.R", "bone inexistente cae a la lista")
	skl.free()
	var sko := _sk(["mixamorig_RightHand", "Sword_Bone", "Other"])
	var eo := {"hand": "right", "bone_overrides": {"mixamo": "Sword_Bone", "heroe": "Other"}}
	check(WeaponAttacher.resolve_bone(sko, eo) == "Sword_Bone", "override por perfil")
	check(WeaponAttacher.resolve_bone(sko, eo, "heroe") == "Other", "override por personaje gana")
	sko.free()
	var skn := _sk(["Hips"])
	check(WeaponAttacher.resolve_bone(skn, e) == "", "sin mano -> vacío")
	check(WeaponAttacher.attach(skn, "x", {"mesh": "res://assets/models/Knight.glb", "mesh_node": "1H_Sword"}) == null, "attach sin mano -> null")
	skn.free()

	# Offset
	var t := WeaponAttacher.offset_transform({"offset": {"position": [0, 0.1, 0], "rotation_degrees": [0, 0, 90], "scale": 2}})
	check(t.origin.is_equal_approx(Vector3(0, 0.1, 0)), "offset posición")
	check(is_equal_approx(t.basis.get_scale().x, 2.0), "offset escala escalar")
	check((t.basis * Vector3.UP).normalized().is_equal_approx(Vector3(-1, 0, 0)), "offset rotación Z 90°")

	# Enganche real con una malla existente (nodo dentro de un .glb KayKit)
	var sk := _sk(["mixamorig_Hips", "mixamorig_RightHand"])
	root.add_child(sk)
	var ent := {"enabled": true, "mesh": "res://assets/models/Knight.glb", "mesh_node": "1H_Sword", "hand": "both",
		"offset": {"position": [0, 0.05, 0]}, "second_grip": {"position": [0, -0.2, 0]}}
	var att := WeaponAttacher.attach(sk, "espada_test", ent)
	check(att != null and att.bone_name == "mixamorig_RightHand", "BoneAttachment3D en mixamorig_RightHand")
	check(att != null and WeaponAttacher.first_mesh(att) != null and WeaponAttacher.first_mesh(att).mesh != null, "malla instanciada")
	check(att != null and att.get_node("Grip").position.is_equal_approx(Vector3(0, 0.05, 0)), "offset aplicado")
	check(att != null and att.has_node("Grip/SecondGrip"), "punto de segunda mano")
	sk.free()

	# Hook en KnightVisual: habilitar una entrada en memoria y verificar que se usa
	var kd := WeaponAttacher.load_db()
	var orig: Dictionary = (kd["weapons"]["espada_larga"] as Dictionary).duplicate(true)
	kd["weapons"]["espada_larga"]["enabled"] = true
	var kv := KnightVisual.new()
	root.add_child(kv)
	kv.setup(Color.BLUE, Catalog.character("caballero"), Catalog.weapon("espada_larga"))
	var p := kv.sword.get_parent()
	while p and not p is BoneAttachment3D:
		p = p.get_parent()
	check(p != null and p.has_meta("weapon_id") and p.get_meta("weapon_id") == "espada_larga", "KnightVisual usa weapons.json si enabled")
	kv.free()
	kd["weapons"]["espada_larga"] = orig
	var kv2 := KnightVisual.new()
	root.add_child(kv2)
	kv2.setup(Color.BLUE, Catalog.character("caballero"), Catalog.weapon("espada_larga"))
	var p2 := kv2.sword.get_parent()
	while p2 and not p2 is BoneAttachment3D:
		p2 = p2.get_parent()
	check(p2 != null and not p2.has_meta("weapon_id"), "deshabilitada: camino clásico")
	kv2.free()
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
