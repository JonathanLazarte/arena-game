class_name BossAbilities
## Fachada de las habilidades de jefe. Máx. 3 equipadas por personaje (pestaña «Jefe»).
## Nombres, costes, códice y números de compilación salen de data/abilities/catalog.json
## (`source`). Hoja Escarlata y Elden siguen en sus catálogos.

const MAX_EQUIPPED := 3
const EldenCatalog = preload("res://scripts/data/elden_catalog.gd")
const DEFAULT := ["estocada"]
const ORDER := ["estocada", "carga_area", "rafaga", "escudo_mana", "combo_falso", "salto_caida"]
const EXT_ORDER := [
	"tajo_retardado", "presa_verdugo", "giro_martillo", "danza_cisne", "paso_espectral",
	"onda_rastrera", "rayos_trazadores", "lluvia_meteoros", "aliento_dragon", "furia_fase", "postura_contra",
	"embate_sismico", "lanza_celeste",
	"cuerno_embiste", "tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada", "estocada_negra",
	"flor_umbral", "presa_fauces", "giro_noble", "danza_triple", "alas_picado",
	"garra_suelo", "vendaval_hacha", "anillo_fuego", "pisoton",
	"lluvia_lanzas", "flecha_grave", "lluvia_sangre", "columnas_rayo",
	"saeta_oscura", "orbe_lunar",
	"aliento_rayo", "aliento_escarcha", "chorro_lava",
	"grito_guerra", "guardia_reflejo",
]
const COST_NAMES := {"stamina": "aguante", "mana": "maná", "health": "vida"}
const CATALOG_PATH := "res://data/abilities/catalog.json"

static var _source: Dictionary = {}
static var _origin: Dictionary = {}
static var _weapons: Dictionary = {}
static var _loaded := false

## Fase 9: nombre corto para botones/HUD y color propio de cada habilidad (icono BossIcon).
const SHORT := {"estocada": "Estocada", "carga_area": "Carga", "rafaga": "Ráfaga", "escudo_mana": "Escudo",
	"combo_falso": "Pausa falsa", "salto_caida": "Caída", "tajo_retardado": "Tajo lento", "presa_verdugo": "Presa",
	"giro_martillo": "Giro", "danza_cisne": "Danza", "paso_espectral": "Paso", "onda_rastrera": "Onda",
	"rayos_trazadores": "Rayos", "lluvia_meteoros": "Meteoros", "aliento_dragon": "Aliento", "furia_fase": "Furia",
	"postura_contra": "Contragolpe", "embate_sismico": "Embate", "lanza_celeste": "Lanza",
	"cuerno_embiste": "Cuerno", "tajo_cruzado": "Cruzado", "zarpazo_sangre": "Zarpazo",
	"barrido_cola": "Cola", "daga_sagrada": "Daga", "estocada_negra": "Tajo negro",
	"flor_umbral": "Flor", "presa_fauces": "Fauces", "giro_noble": "Rueda",
	"danza_triple": "Triple", "alas_picado": "Picado", "garra_suelo": "Garra",
	"vendaval_hacha": "Vendaval", "anillo_fuego": "Anillo", "pisoton": "Pisotón",
	"lluvia_lanzas": "Lluvia", "flecha_grave": "Flecha", "lluvia_sangre": "Sangre",
	"columnas_rayo": "Columnas", "saeta_oscura": "Saeta", "orbe_lunar": "Orbe",
	"aliento_rayo": "Fulgor", "aliento_escarcha": "Escarcha", "chorro_lava": "Lava",
	"grito_guerra": "Grito", "guardia_reflejo": "Reflejo",
	"trazos_hoja": "Trazos", "danza_garza": "Garza", "caida_hoja": "Clavada",
	"floracion_escarlata": "Floración",
	"martillo_alba": "Alba", "lanza_veredicto": "Veredicto", "triptico_sagrado": "Tríptico",
	"danza_espirales": "Espirales", "estocada_penetrante": "Penetrante", "floracion_purpurea": "Purpúrea",
	"pisoton_telurico": "Telúrico", "presa_del_coloso": "Coloso", "hendedura_cataclismica": "Hendedura"}
const BASE_COLORS := {"estocada": Color(1.0, 0.3, 0.12), "carga_area": Color(0.3, 0.6, 1.0), "rafaga": Color(1.0, 0.82, 0.3),
	"escudo_mana": Color(0.3, 1.0, 1.0), "combo_falso": Color(1.0, 0.8, 0.25), "salto_caida": Color(1.0, 0.25, 0.15)}

static func short_name(id: String) -> String:
	if SHORT.has(id):
		return String(SHORT[id])
	var d := def(id)
	return String(d.get("name", id)).split(" ")[0] if not d.is_empty() else id

static func color_of(id: String) -> Color:
	if BASE_COLORS.has(id):
		return BASE_COLORS[id]
	var d := def(id)
	return d.get("color", Color(0.9, 0.85, 0.7)) if not d.is_empty() else Color(0.9, 0.85, 0.7)

static func all_ids() -> Array:
	return ORDER + EXT_ORDER + HojaCatalog.ids() + EldenCatalog.ids()

static func has(id: String) -> bool:
	_ensure()
	return _source.has(id) or HojaCatalog.has(id) or EldenCatalog.has(id)

## "boss" o "weapon". El programa numérico sigue en source; el origen es origin.
static func origin_of(id: String) -> String:
	_ensure()
	return String(_origin.get(id, "boss"))

static func requires_weapon(id: String) -> Array:
	_ensure()
	var w: Variant = _weapons.get(id, [])
	return (w as Array).duplicate() if w is Array else []

static func ids_of(origin: String) -> Array:
	var out: Array = []
	for id: String in all_ids():
		if origin_of(String(id)) == origin:
			out.append(id)
	return out

## Definición de compilación (tiempos en segundos). Sale de catalog.json → source.
## Hoja y Elden siguen en sus catálogos.
static func def(id: String) -> Dictionary:
	if HojaCatalog.has(id):
		return HojaCatalog.view_def(id)
	if EldenCatalog.has(id):
		return EldenCatalog.view_def(id)
	_ensure()
	return _source.get(id, {})

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("BossAbilities: no se pudo leer %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("BossAbilities: catálogo ilegible")
		return
	for a: Variant in (parsed as Dictionary).get("abilities", []):
		if not (a is Dictionary):
			continue
		var row: Dictionary = a
		var id := String(row.get("id", ""))
		if id == "":
			continue
		var org := String(row.get("origin", "boss"))
		_origin[id] = "weapon" if org == "weapon" else "boss"
		var req: Array = []
		for w: Variant in row.get("requires_weapon", []):
			if w is String and String(w) != "":
				req.append(String(w))
		_weapons[id] = req
		var src: Variant = row.get("source", null)
		if src is Dictionary:
			_source[id] = _restore(src)

static func _restore(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.size() == 1 and d.has("__color") and d["__color"] is Array:
			var c: Array = d["__color"]
			return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
		var out := {}
		for k: Variant in d.keys():
			out[k] = _restore(d[k])
		return out
	if v is Array:
		var arr: Array = []
		for x: Variant in v:
			arr.append(_restore(x))
		return arr
	return v

## Ronda 33: imbloqueable = el escudo no la para (daño tipo «jefe»).
static func is_unblockable(id: String) -> bool:
	var d := def(id)
	return bool(d.get("unblockable", false)) or (d.has("type") and String(d.get("kind", "")) == "jefe")

## Ronda 33: descripción del aviso (única por habilidad). En las de lluvia "tele" es un tiempo.
static func telegraph_text(id: String) -> String:
	var d := def(id)
	if d.has("tele_txt"):
		return String(d["tele_txt"])
	return String(d["tele"]) if d.get("tele") is String else ""

static func cost_text(id: String) -> String:
	var d := def(id)
	return "%d %s" % [int(d.get("cost", 0)), COST_NAMES.get(String(d.get("cost_type", "")), "")]

static func codex(id: String) -> String:
	if HojaCatalog.has(id):
		return HojaCatalog.codex(id)
	if EldenCatalog.has(id):
		return EldenCatalog.codex(id)
	var d := def(id)
	if d.is_empty():
		return ""
	var t := "[b]%s[/b] · coste %s\n%s\n" % [d["name"], cost_text(id), d["desc"]]
	if float(d.get("dmg", 0.0)) > 0.0:
		t += "Daño: x%.2f del %s%s · " % [float(d["dmg"]), "ligero" if d.get("light", false) else "fuerte", " (por tajo)" if id == "rafaga" else ""]
	if d.has("hits"):
		var fs: Array = []
		for h: Array in d["hits"]:
			fs.append("%d" % int(h[2]))
		t += "Fuerza de aturdimiento por golpe: %s (+ Fuerza y arma)\n" % " / ".join(fs)
	elif float(d.get("force", 0.0)) > 0.0:
		t += "Fuerza de aturdimiento: %d + %s\n" % [int(d["force"]), "magia" if d.get("magic", false) else "Fuerza y arma"]
	else:
		t += "\n"
	var res := float(d.get("resist", 0.0))
	t += "Robustez durante la habilidad: %s\n" % ("inmune" if res >= 99.0 else "x%.1f" % (1.0 + res))
	if is_unblockable(id):
		t += "[color=#ff8040]IMBLOQUEABLE[/color] · "
	if float(d.get("cd", 0.0)) > 0.0:
		t += "Recarga propia opcional: %.0f s · " % float(d["cd"])
	if telegraph_text(id) != "":
		t += "Se reconoce: %s" % telegraph_text(id)
	return t
