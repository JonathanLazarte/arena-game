class_name BossAbilities
## Fachada de las habilidades de jefe. Máx. 4 equipadas por personaje (pestaña «Jefe»).
## Nombres, costes, códice y números de compilación salen de data/abilities/catalog.json
## (`source`). Hoja Escarlata y Elden siguen en sus catálogos.

const MAX_EQUIPPED := 4
const EldenCatalog = preload("res://scripts/data/elden_catalog.gd")
const ExtraCatalog = preload("res://scripts/data/extra_catalog.gd")
const DEFAULT := ["estocada"]
const ORDER := ["estocada", "carga_area", "rafaga", "escudo_mana", "combo_falso", "salto_caida"]
const EXT_ORDER := [
	"paso_espectral", "rayos_trazadores", "lluvia_meteoros", "aliento_dragon", "furia_fase", "postura_contra", "lanza_celeste", "zarpazo_sangre", "flor_umbral", "lluvia_lanzas", "flecha_grave", "lluvia_sangre", "columnas_rayo", "orbe_lunar", "aliento_rayo", "aliento_escarcha", "chorro_lava",
]
const COST_NAMES := {"stamina": "aguante", "mana": "maná", "health": "vida"}
const CATALOG_PATH := "res://data/abilities/catalog.json"

static var _source: Dictionary = {}
static var _origin: Dictionary = {}
static var _weapons: Dictionary = {}
static var _familias: Dictionary = {}
static var _spam: Dictionary = {}
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
	"cadena_mandobles": "Mandobles", "embestida_perforante": "Embestida", "carga_abisal": "Abisal",
	"tajo_deslizante": "Deslizante", "giros_dobles": "Giros", "triple_clavada": "Clavadas",
	"salto_estocada": "Zambullida", "voltereta_cuchilla": "Voltereta", "potenciar_filo": "Filo",
	"golpe_fisura": "Fisura",
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
	return ORDER + EXT_ORDER + HojaCatalog.ids() + EldenCatalog.ids() + ExtraCatalog.ids()

static func has(id: String) -> bool:
	_ensure()
	return _source.has(id) or HojaCatalog.has(id) or EldenCatalog.has(id) or ExtraCatalog.has(id)

## "boss" o "weapon". El programa numérico sigue en source; el origen es origin.
static func origin_of(id: String) -> String:
	_ensure()
	return String(_origin.get(id, "boss"))

static func requires_weapon(id: String) -> Array:
	_ensure()
	var w: Variant = _weapons.get(id, [])
	return (w as Array).duplicate() if w is Array else []

## Familia de animación (no el id del arma). Vacío = sin filtro (Hoja, Elden, Artorias, Fisura).
static func weapon_families(id: String) -> Array:
	_ensure()
	var f: Variant = _familias.get(id, [])
	return (f as Array).duplicate() if f is Array else []

## Familias de animación compatibles según el tipo de arma equipada.
static func families_of_weapon(weapon_id: String) -> Array:
	match weapon_id:
		"espada_escudo": return ["espada_ligera", "escudo"]
		"espada_larga": return ["espada_pesada"]
		"hacha_2m": return ["hacha", "espada_pesada", "martillo"]
		"dagas": return ["espada_ligera"]
		"lanza": return ["lanza"]
		"arco", "ballesta": return ["arco"]
		_: return ["espada_ligera"]

## Comprueba si una habilidad es compatible con las armas activas del personaje.
## Habilidades de origen «boss» son universales; las de origen «weapon» respetan las familias de armas.
static func is_family_compatible(ability_id: String, weapon_id: String, weapon2_id: String = "") -> bool:
	if origin_of(ability_id) == "boss":
		return true
	var fams := weapon_families(ability_id)
	if fams.is_empty() or "cualquiera" in fams or "magia" in fams or "bestia" in fams:
		return true
	var w1 := families_of_weapon(weapon_id)
	var w2 := families_of_weapon(weapon2_id) if weapon2_id != "" else []
	for f: String in fams:
		if f in w1 or f in w2:
			return true
	return false

## Repetir la misma habilidad se salta la recarga global. El bit de la sim sigue siendo rep_free.
static func spameable(id: String) -> bool:
	_ensure()
	return bool(_spam.get(id, false))

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
	if ExtraCatalog.has(id):
		return ExtraCatalog.view_def(id)
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
		var fams: Array = []
		for fam: Variant in row.get("familias", []):
			if fam is String and String(fam) != "":
				fams.append(String(fam))
		_familias[id] = fams
		## spameable es el nombre de autor. global_cd_on_repeat=false es el mismo bit, invertido.
		var spam := false
		if row.has("spameable"):
			spam = bool(row["spameable"])
		elif row.has("global_cd_on_repeat"):
			spam = not bool(row["global_cd_on_repeat"])
		_spam[id] = spam
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
	if ExtraCatalog.has(id):
		return ExtraCatalog.codex(id)
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
	var fams := weapon_families(id)
	if not fams.is_empty():
		t += "Familias: %s · " % ", ".join(PackedStringArray(fams))
	if telegraph_text(id) != "":
		t += "Se reconoce: %s" % telegraph_text(id)
	return t
