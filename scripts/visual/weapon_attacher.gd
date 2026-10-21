class_name WeaponAttacher
extends RefCounted
## Enganche de armas guiado por datos (data/weapons/weapons.json). Ver docs/WEAPON_GUIDE.md.
## Sirve para cualquier esqueleto: el hueso se resuelve por (1) override por personaje,
## (2) override por perfil de esqueleto, (3) `bone` explícito, (4) lista de nombres conocidos.
## Las entradas con `enabled: false` NO se usan en el juego (knight_visual sigue con su camino
## clásico); quedan documentadas y validadas hasta que se cargue una malla propia.

const PATH := "res://data/weapons/weapons.json"
const HANDS := ["right", "left", "both"]
const OFFSET_KEYS := ["position", "rotation_degrees", "scale"]
const ENTRY_KEYS := ["enabled", "mesh", "mesh_node", "hand", "bone", "bone_overrides", "offset",
	"second_grip", "notes"]

## Nombres de hueso de mano conocidos, en orden de preferencia.
const RIGHT_BONES := ["handslot.r", "HandR", "hand.r", "hand_r", "Hand_R", "Hand.R", "RightHand",
	"mixamorig_RightHand", "mixamorig:RightHand", "DEF-hand.R", "Bip01 R Hand", "Bip001 R Hand",
	"R_Hand", "wrist.r", "Wrist.R", "Fingers2R"]
const LEFT_BONES := ["handslot.l", "HandL", "hand.l", "hand_l", "Hand_L", "Hand.L", "LeftHand",
	"mixamorig_LeftHand", "mixamorig:LeftHand", "DEF-hand.L", "Bip01 L Hand", "Bip001 L Hand",
	"L_Hand", "wrist.l", "Wrist.L", "Fingers2L"]

static var _cache: Dictionary = {}
static var _cache_path: String = ""

static func load_db(path: String = PATH) -> Dictionary:
	if _cache_path == path and not _cache.is_empty():
		return _cache
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			d = v
	_cache = d
	_cache_path = path
	return d

static func clear_cache() -> void:
	_cache = {}
	_cache_path = ""

static func entry(weapon_id: String, path: String = PATH) -> Dictionary:
	var w: Variant = load_db(path).get("weapons", {})
	return (w as Dictionary).get(weapon_id, {}) if w is Dictionary else {}

## Entrada usable en el juego: habilitada y con malla existente.
static func active_entry(weapon_id: String, path: String = PATH) -> Dictionary:
	var e := entry(weapon_id, path)
	if e.is_empty() or not bool(e.get("enabled", false)):
		return {}
	var mesh := String(e.get("mesh", ""))
	if mesh == "" or not ResourceLoader.exists(mesh):
		return {}
	return e

## Perfil del esqueleto deducido por nombres de hueso.
static func skeleton_profile(sk: Skeleton3D) -> String:
	if sk == null:
		return ""
	if sk.find_bone("handslot.r") != -1 or sk.find_bone("HandR") != -1:
		return "kaykit"
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.begins_with("mixamorig"):
			return "mixamo"
		if n.begins_with("DEF-"):
			return "rigify"
		if n.begins_with("Bip0"):
			return "biped"
	if sk.find_bone("hand_r") != -1:
		return "ue"
	if sk.find_bone("RightHand") != -1:
		return "humanoid"
	return "unknown"

static func fallback_bones(hand: String) -> Array:
	return LEFT_BONES if hand == "left" else RIGHT_BONES

## Resuelve el hueso de una entrada para un esqueleto. Devuelve "" si no hay ninguno válido.
static func resolve_bone(sk: Skeleton3D, e: Dictionary, character_id: String = "") -> String:
	var cands: Array = []
	var ov: Variant = e.get("bone_overrides", {})
	if ov is Dictionary:
		if character_id != "" and (ov as Dictionary).has(character_id):
			cands.append(String(ov[character_id]))
		var prof := skeleton_profile(sk)
		if (ov as Dictionary).has(prof):
			cands.append(String(ov[prof]))
	if String(e.get("bone", "")) != "":
		cands.append(String(e["bone"]))
	cands.append_array(fallback_bones(String(e.get("hand", "right"))))
	for b: String in cands:
		if sk != null and sk.find_bone(b) != -1:
			return b
	return ""

static func _vec(v: Variant, def: Vector3) -> Vector3:
	if v is Array and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is float or v is int:
		return Vector3.ONE * float(v)
	return def

static func offset_transform(e: Dictionary) -> Transform3D:
	var o: Dictionary = e.get("offset", {}) if e.get("offset", {}) is Dictionary else {}
	var pos := _vec(o.get("position"), Vector3.ZERO)
	var rot := _vec(o.get("rotation_degrees"), Vector3.ZERO)
	var scl := _vec(o.get("scale"), Vector3.ONE)
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	return Transform3D(b.scaled(scl), pos)

## Instancia la malla de la entrada (escena entera o un nodo `mesh_node` dentro de ella).
static func instance_mesh(e: Dictionary) -> Node3D:
	var path := String(e.get("mesh", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		return mi
	if not res is PackedScene:
		return null
	var inst := (res as PackedScene).instantiate()
	var node_name := String(e.get("mesh_node", ""))
	if node_name == "":
		return inst as Node3D
	var mi := inst.find_child(node_name, true, false) as MeshInstance3D
	var out: MeshInstance3D = null
	if mi:
		out = MeshInstance3D.new()
		out.name = node_name
		out.mesh = mi.mesh
		for s in mi.get_surface_override_material_count():
			out.set_surface_override_material(s, mi.get_active_material(s))
	inst.free()
	return out

## Crea BoneAttachment3D > «grip» (offset) > malla. Devuelve el BoneAttachment3D o null.
## Si hay `second_grip`, agrega un Marker3D «SecondGrip» (punto para la otra mano / IK futura).
static func attach(sk: Skeleton3D, weapon_id: String, e: Dictionary, character_id: String = "") -> BoneAttachment3D:
	if sk == null or e.is_empty():
		return null
	var bone := resolve_bone(sk, e, character_id)
	if bone == "":
		push_warning("WeaponAttacher: «%s» sin hueso de mano válido en el esqueleto" % weapon_id)
		return null
	var m := instance_mesh(e)
	if m == null:
		return null
	var att := BoneAttachment3D.new()
	att.name = weapon_id + "_slot"
	att.bone_name = bone
	att.set_meta("weapon_id", weapon_id)
	sk.add_child(att)
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.transform = offset_transform(e)
	att.add_child(grip)
	grip.add_child(m)
	var sg: Variant = e.get("second_grip", null)
	if sg is Dictionary:
		var mk := Marker3D.new()
		mk.name = "SecondGrip"
		mk.position = _vec((sg as Dictionary).get("position"), Vector3.ZERO)
		grip.add_child(mk)
	return att

## Primer MeshInstance3D bajo un nodo (para tintes/escala del código existente).
static func first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := first_mesh(c)
		if r:
			return r
	return null

## Valida la base de datos. Devuelve {"errors": [...], "warnings": [...]}.
static func validate(db: Dictionary, known_ids: Array = []) -> Dictionary:
	var errs: Array = []
	var warns: Array = []
	if not db.get("weapons") is Dictionary:
		errs.append("falta el objeto «weapons»")
		return {"errors": errs, "warnings": warns}
	var ws: Dictionary = db["weapons"]
	for id: String in ws:
		var p := "weapons.%s" % id
		if not ws[id] is Dictionary:
			errs.append(p + ": tiene que ser un objeto")
			continue
		var e: Dictionary = ws[id]
		if not known_ids.is_empty() and not known_ids.has(id):
			errs.append(p + ": id de arma inexistente (no está en Catalog.WEAPONS)")
		for k: String in e:
			if not ENTRY_KEYS.has(k):
				warns.append("%s.%s: campo desconocido" % [p, k])
		if e.has("enabled") and not e["enabled"] is bool:
			errs.append(p + ".enabled: tiene que ser true/false")
		var mesh: Variant = e.get("mesh", "")
		if not mesh is String:
			errs.append(p + ".mesh: tiene que ser texto")
		elif mesh != "":
			if not String(mesh).begins_with("res://"):
				errs.append(p + ".mesh: tiene que empezar con res://")
			elif not ResourceLoader.exists(mesh):
				errs.append(p + ".mesh: no existe «%s»" % mesh)
			elif String(e.get("mesh_node", "")) != "" and instance_mesh(e) == null:
				errs.append(p + ".mesh_node: no hay MeshInstance3D «%s» en %s" % [e["mesh_node"], mesh])
		elif bool(e.get("enabled", false)):
			errs.append(p + ": enabled=true sin mesh")
		if not HANDS.has(String(e.get("hand", "right"))):
			errs.append(p + ".hand: tiene que ser right/left/both")
		if e.has("bone") and not e["bone"] is String:
			errs.append(p + ".bone: tiene que ser texto")
		if e.has("bone_overrides"):
			if not e["bone_overrides"] is Dictionary:
				errs.append(p + ".bone_overrides: tiene que ser un objeto")
			else:
				for k: String in e["bone_overrides"]:
					if not e["bone_overrides"][k] is String or String(e["bone_overrides"][k]) == "":
						errs.append("%s.bone_overrides.%s: hueso vacío o no texto" % [p, k])
		var o: Variant = e.get("offset", {})
		if not o is Dictionary:
			errs.append(p + ".offset: tiene que ser un objeto")
		else:
			for k: String in o:
				if not OFFSET_KEYS.has(k):
					errs.append("%s.offset.%s: campo desconocido" % [p, k])
				elif not _is_vec3(o[k], k == "scale"):
					errs.append("%s.offset.%s: tiene que ser [x, y, z] numérico" % [p, k])
			if o.has("scale"):
				var s := _vec(o["scale"], Vector3.ONE)
				if s.x <= 0 or s.y <= 0 or s.z <= 0:
					errs.append(p + ".offset.scale: tiene que ser > 0")
		var sg: Variant = e.get("second_grip", null)
		if sg != null:
			if not sg is Dictionary or not _is_vec3((sg as Dictionary).get("position"), false):
				errs.append(p + ".second_grip: tiene que ser {\"position\": [x, y, z]}")
			elif String(e.get("hand", "right")) != "both":
				warns.append(p + ".second_grip: solo tiene sentido con hand «both»")
	return {"errors": errs, "warnings": warns}

static func _is_vec3(v: Variant, allow_scalar: bool) -> bool:
	if allow_scalar and (v is float or v is int):
		return true
	if not v is Array or (v as Array).size() != 3:
		return false
	for x: Variant in v:
		if not (x is float or x is int):
			return false
	return true
