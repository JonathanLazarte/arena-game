class_name EldenCatalog
extends RefCounted
## Catálogo de jefes inspirados en Elden Ring (Radagon, Malenia, Godfrey)
## para el códice y la simulación por pasos determinista (T_CATALOG / SimCatalog).

const PATH := "res://data/abilities/bosses_elden_catalog.json"
static var _res: Dictionary = {}
static var _raw: Dictionary = {}
static var _ok := false

static func _load() -> void:
	if _ok:
		return
	_ok = true
	_res = AbilityCatalog.load_file(PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_raw = parsed
	if not bool(_res.get("ok", false)):
		push_error("EldenCatalog: %s" % AbilityCatalog.format_issues(_res))

static func _baked() -> Dictionary:
	_load()
	var b: Variant = _res.get("baked", null)
	return b if b is Dictionary else {}

static func ids() -> Array:
	var out: Array = []
	for a: Dictionary in _baked().get("abilities", []):
		out.append(String(a["id"]))
	return out

static func has(id: String) -> bool:
	return not ability(id).is_empty()

static func ability(id: String) -> Dictionary:
	var b := _baked()
	var idx: Variant = (b.get("ability_index", {}) as Dictionary).get(id, null)
	if idx == null:
		return {}
	var list: Array = b.get("abilities", [])
	var i := int(idx)
	if i < 0 or i >= list.size():
		return {}
	return list[i]

static func preset(id: String) -> Array:
	var b := _baked()
	var list: Array = b.get("abilities", [])
	for p: Dictionary in b.get("presets", []):
		if String(p.get("id", "")) != id:
			continue
		var out: Array = []
		for i: int in p.get("abilities", []):
			if i >= 0 and i < list.size():
				out.append(String((list[i] as Dictionary)["id"]))
		return out
	return []

static func all_presets() -> Dictionary:
	var out: Dictionary = {}
	var b := _baked()
	for p: Dictionary in b.get("presets", []):
		var pid := String(p.get("id", ""))
		out[pid] = preset(pid)
	return out

static func _raw_of(id: String) -> Dictionary:
	_load()
	for a: Variant in _raw.get("abilities", []):
		if a is Dictionary and String((a as Dictionary).get("id", "")) == id:
			return a
	return {}

static func _cost_of(a: Dictionary) -> Array:
	var c: Dictionary = a.get("cost", {})
	if int(c.get("health", 0)) > 0:
		return ["health", float(c["health"]) / 1000.0]
	if int(c.get("mana", 0)) > 0:
		return ["mana", float(c["mana"]) / 1000.0]
	return ["stamina", float(c.get("stamina", 0)) / 1000.0]

static func _tele(id: String) -> String:
	var a := _raw_of(id)
	var steps: Array = a.get("steps", [])
	if steps.is_empty() or not (steps[0] is Dictionary):
		return ""
	var tg: Variant = (steps[0] as Dictionary).get("telegraph", {})
	if tg is Dictionary:
		return String((tg as Dictionary).get("text", ""))
	return ""

static func _hint(id: String) -> String:
	var h: Variant = _raw_of(id).get("hint", {})
	if h is Dictionary:
		return String((h as Dictionary).get("text", ""))
	return ""

static func _color(a: Dictionary) -> Color:
	var steps: Array = a.get("steps", [])
	if steps.is_empty() or not (steps[0] is Dictionary):
		return Color(0.9, 0.85, 0.7)
	var tg: Variant = (steps[0] as Dictionary).get("telegraph", null)
	if tg is Dictionary:
		var hex := int((tg as Dictionary).get("color", 0))
		return Color(float((hex >> 16) & 255) / 255.0, float((hex >> 8) & 255) / 255.0, float(hex & 255) / 255.0)
	return Color(0.9, 0.85, 0.7)

static func view_def(id: String) -> Dictionary:
	var a := ability(id)
	if a.is_empty():
		return {}
	var ct: Array = _cost_of(a)
	return {
		"name": String(a.get("name", id)),
		"cost_type": String(ct[0]),
		"cost": float(ct[1]),
		"unblockable": false,
		"dmg": 0.0,
		"resist": 0.0,
		"cd": float(int(a.get("cooldown", 0))) / 60.0,
		"color": _color(a),
		"tele": _tele(id),
		"desc": _hint(id),
		"phase": int(a.get("unlock_phase", 1)),
	}

static func codex(id: String) -> String:
	var a := ability(id)
	if a.is_empty():
		return ""
	var v := view_def(id)
	var phase := int(v.get("phase", 1))
	var cn := {"stamina": "aguante", "mana": "maná", "health": "vida"}
	var coste := "%d %s" % [int(v["cost"]), cn.get(String(v["cost_type"]), "")]
	var t := "[b]%s[/b] · coste %s · recarga %.0f s" % [v["name"], coste, float(v["cd"])]
	if phase >= 2:
		t += " · Fase II del campeón"
	t += "\n%s\n" % String(v["desc"])
	var names: PackedStringArray = []
	for s: Dictionary in a.get("steps", []):
		names.append(String(s.get("id", "")))
	if not names.is_empty():
		t += "Pasos: %s.\n" % ", ".join(names)
	t += "Se reconoce: %s" % String(v["tele"])
	return t
