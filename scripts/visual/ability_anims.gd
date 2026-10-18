class_name AbilityAnims
extends RefCounted
## Animación de habilidades de catálogo (solo vista). Lee data/animations/ability_anims.json:
## por habilidad y por paso, una lista de tramos {clip, keys [[tick, tiempo], …]}. El tiempo del
## clip sale SOLO del estado de la sim (paso = AB_FIRED, tick del paso = AB_T - 1): misma
## entrada → misma pose, así que el rollback no lo rompe. Ver docs/ABILITY_ANIMATION_GUIDE.md.

const PATH := "res://data/animations/ability_anims.json"
const MIRROR_LIB := &"abm" ## copias espejadas («mirror»: true) que arma KnightVisual

static var _data: Dictionary = {}
static var _step_ids: Dictionary = {} ## id habilidad → [id paso 0, id paso 1, …]

static func data() -> Dictionary:
	if _data.is_empty():
		var txt := FileAccess.get_file_as_string(PATH)
		var d: Variant = JSON.parse_string(txt) if txt != "" else null
		_data = d if d is Dictionary else {"libraries": {}, "abilities": {}}
	return _data

static func libraries() -> Dictionary:
	return data().get("libraries", {})

static func has(ab_id: String) -> bool:
	return (data().get("abilities", {}) as Dictionary).has(ab_id)

## Ids de los pasos en el orden del JSON de la habilidad (= índice AB_FIRED de SimCatalog).
static func step_ids(ab_id: String) -> Array:
	if _step_ids.has(ab_id):
		return _step_ids[ab_id]
	var out: Array = []
	var a: Dictionary = (data().get("abilities", {}) as Dictionary).get(ab_id, {})
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(a.get("file", ""))))
	if raw is Dictionary:
		for ab: Variant in (raw as Dictionary).get("abilities", []):
			if ab is Dictionary and String((ab as Dictionary).get("id", "")) == ab_id:
				for st: Variant in (ab as Dictionary).get("steps", []):
					out.append(String((st as Dictionary).get("id", "")))
	_step_ids[ab_id] = out
	return out

## Todos los tramos (para precargar espejos y validar).
static func segments(ab_id: String) -> Array:
	var out: Array = []
	var a: Dictionary = (data().get("abilities", {}) as Dictionary).get(ab_id, {})
	for k: String in (a.get("steps", {}) as Dictionary):
		out.append_array(a["steps"][k])
	return out

static func all_ids() -> Array:
	return (data().get("abilities", {}) as Dictionary).keys()

## Nombre del clip a reproducir (espejo → biblioteca abm).
static func clip_name(seg: Dictionary) -> String:
	var c := String(seg.get("clip", ""))
	return String(MIRROR_LIB) + "/" + c.replace("/", "__") if bool(seg.get("mirror", false)) else c

## Tiempo del clip en el tick t del paso: lineal por tramos entre las claves (fuera, se fija al
## extremo). Con «loop» {from, to, speed} repite [from, to) desde la última clave.
static func clip_time(seg: Dictionary, t: float, length: float) -> float:
	var keys: Array = seg.get("keys", [])
	if keys.is_empty():
		return 0.0
	var k: float = 1.0 if String(seg.get("unit", "s")) == "s" else length
	var lp: Variant = seg.get("loop", null)
	var last: Array = keys[keys.size() - 1]
	if lp is Dictionary and t > float(last[0]):
		var a := float((lp as Dictionary).get("from", 0.0)) * k
		var b := float((lp as Dictionary).get("to", 1.0)) * k
		var sp := float((lp as Dictionary).get("speed", 1.0))
		return a + fposmod((t - float(last[0])) / 60.0 * sp, maxf(b - a, 0.001))
	if t <= float(keys[0][0]):
		return float(keys[0][1]) * k
	for i in range(1, keys.size()):
		var p0: Array = keys[i - 1]
		var p1: Array = keys[i]
		if t <= float(p1[0]):
			var u := (t - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 0.0001)
			return lerpf(float(p0[1]), float(p1[1]), u) * k
	return float(last[1]) * k

## {seg, index} del tramo activo en (habilidad, paso, tick); {} si no hay animación propia.
## index sube con cada tramo/paso: KnightVisual alterna dos estados por paridad (fundido).
static func sample(ab_id: String, step: int, t: int) -> Dictionary:
	var a: Dictionary = (data().get("abilities", {}) as Dictionary).get(ab_id, {})
	if a.is_empty():
		return {}
	var ids := step_ids(ab_id)
	if step < 0 or step >= ids.size():
		return {}
	var segs: Array = (a.get("steps", {}) as Dictionary).get(ids[step], [])
	if segs.is_empty():
		return {}
	var pick := 0
	for i in range(1, segs.size()):
		var ks: Array = (segs[i] as Dictionary).get("keys", [[0, 0]])
		if t >= int(ks[0][0]):
			pick = i
	var base := 0
	for j in step:
		base += ((a.get("steps", {}) as Dictionary).get(ids[j], []) as Array).size()
	return {"seg": segs[pick], "index": base + pick}
