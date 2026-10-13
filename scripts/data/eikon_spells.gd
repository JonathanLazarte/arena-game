class_name EikonSpells
## Ronda 21: magia de eikon. Cada eikon que poseés enseña hechizos; se equipan en ranuras
## (Personaje → Eikons → «Hechizos»). Las ranuras y la potencia escalan con Sabiduría (ofensivos)
## y Devoción (protecciones): los magos se apoyan más en los eikons.
## Solo se lanzan a pie (montado se usan los especiales del eikon montado).

const DEFS := {
	"chispa": {"name": "Chispa ígnea", "eikon": "fenix", "type": "proyectil", "element": "fuego",
		"damage": 9.0, "speed": 26.0, "cost": 14.0, "cooldown": 1.4, "cast": 0.35, "scale": "sabiduria",
		"desc": "Proyectil de fuego rápido."},
	"aliento_helado": {"name": "Aliento helado", "eikon": "lobo", "type": "cono", "element": "hielo",
		"damage": 6.0, "range": 5.5, "arc": 60.0, "status": {"congelacion": 30.0}, "cost": 20.0, "cooldown": 4.0, "cast": 0.45, "scale": "sabiduria",
		"desc": "Cono corto de escarcha que acumula Congelación."},
	"saeta_vendaval": {"name": "Saeta del vendaval", "eikon": "grifo", "type": "proyectil", "element": "rayo",
		"damage": 7.0, "speed": 40.0, "cost": 12.0, "cooldown": 1.1, "cast": 0.25, "scale": "sabiduria",
		"desc": "Saeta de viento muy veloz."},
	"piel_de_piedra": {"name": "Piel de piedra", "eikon": "golem", "type": "buff", "element": "fisico",
		"duration": 6.0, "reduction": 0.15, "poise": 1.5, "cost": 24.0, "cooldown": 12.0, "cast": 0.5, "scale": "devocion",
		"desc": "6 s: -15 % de daño recibido y +50 % de equilibrio."},
}
const ORDER := ["chispa", "aliento_helado", "saeta_vendaval", "piel_de_piedra"]
const MAX_SLOTS := 4

static func spell(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func name_of(id: String) -> String:
	return String(DEFS[id]["name"]) if DEFS.has(id) else "— vacía —"

## Ranuras: 2 base; +1 con Sabiduría o Devoción ≥ 18; +1 con ≥ 30 (máx. 4).
static func slots_for(attrs: Dictionary) -> int:
	var m := maxi(int(attrs.get("sabiduria", 0)), int(attrs.get("devocion", 0)))
	return mini(2 + (1 if m >= 18 else 0) + (1 if m >= 30 else 0), MAX_SLOTS)

## Hechizos que enseñan los eikons poseídos.
static func available(owned_eikons: Array) -> Array:
	var out: Array = []
	for id: String in ORDER:
		if String(DEFS[id]["eikon"]) in owned_eikons:
			out.append(id)
	return out

## Potencia: Sabiduría usa la curva «magia» (100 = x1), Devoción la de «curacion».
static func power(id: String, ad: Dictionary) -> float:
	var d := spell(id)
	if d.is_empty():
		return 1.0
	if String(d["scale"]) == "devocion":
		return float(ad.get("curacion", 1.0))
	return float(ad.get("magia", 100.0)) / 100.0

static func default_for(eikon_id: String) -> Array:
	for id: String in ORDER:
		if DEFS[id]["eikon"] == eikon_id:
			return [id]
	return []

## Normaliza la lista equipada: tamaño = ranuras, sin repetidos ni hechizos no disponibles.
static func sanitize(list: Array, n: int, owned_eikons: Array) -> Array:
	var av := available(owned_eikons)
	var out: Array = []
	for s in list:
		var id := String(s)
		if id != "" and id in av and not (id in out):
			out.append(id)
		else:
			out.append("")
	while out.size() < n:
		out.append("")
	out.resize(n)
	return out
