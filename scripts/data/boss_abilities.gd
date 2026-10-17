class_name BossAbilities
## Ronda 31/34: habilidades de jefe. Máx. 3 equipadas por personaje (pestaña «Jefe»). Sin tiempos de
## recarga: cada una cuesta aguante, maná (Energía) o vida (no se puede usar si te dejaría a 0).
## Consulta primero BossAbilitiesExt y luego las 6 base.

const MAX_EQUIPPED := 3
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

const DEFS := {
	"estocada": {"name": "Estocada de jefe", "cost_type": "stamina", "cost": 30.0, "unblockable": true, "home_time": 0.15, "dmg": 1.6, "force": 60.0, "resist": 99.0, "magic": false,
		"windup": 1.6, "dist": 12.0, "speed": 30.0, "reach": 1.8, "home_deg": 140.0, "range": 12.0,
		"desc": "Carga 1,6 s siguiendo al objetivo (invulnerable) y sale disparada 12 m; solo corrige la dirección en los primeros 0,15 s de la embestida. Imbloqueable: rueda justo antes del impacto o apártate cuando ya salió.",
		"tele": "Hoja roja que se enciende y sonido que sube."},
	"carga_area": {"name": "Carga en área", "cost_type": "mana", "cost": 35.0, "dmg": 1.4, "force": 45.0, "resist": 4.0, "magic": true,
		"windup": 2.2, "radius": 7.5, "recovery": 0.6, "range": 3.5,
		"desc": "Inmóvil, acumula energía 2,2 s con robustez x5 y estalla en un amplio radio de 7,5 m. Huye o córtala; no te quedes pegando.",
		"tele": "Anillo azul en el suelo que se llena; pose de grito."},
	"rafaga": {"name": "Ráfaga espectral", "cost_type": "mana", "cost": 10.0, "dmg": 0.55, "force": 14.0, "resist": 0.5, "magic": true, "light": true,
		"windup": 0.36, "count": 1, "speed": 20.0, "life": 2.5, "home_deg": 60.0, "home_pitch_deg": 24.0, "home_time": 2.5, "radius": 0.8, "recovery": 0.5, "range": 20.0,
		"desc": "Cada pulsación emite un tajo espectral dorado y consume 10 de maná. Puedes volver a pulsar al terminar la animación, sin recarga adicional. Persigue girando hasta 60°/s en horizontal y 24°/s en vertical a 20 m/s. Si te rebasa, sigue de largo.",
		"tele": "La hoja se vuelve dorada; cada orden libera un tajo en media luna."},
	"escudo_mana": {"name": "Escudo de maná", "cost_type": "mana", "cost": 25.0, "dmg": 0.0, "force": 0.0, "resist": 99.0, "magic": true,
		"windup": 0.1, "active": 1.5, "range": 0.0,
		"desc": "1,5 s de invulnerabilidad TOTAL (daño y aturdimiento). Te mueves despacio y no atacas.",
		"tele": "Burbuja cian alrededor del personaje."},
	"combo_falso": {"name": "Combo de la pausa falsa", "cost_type": "stamina", "cost": 38.0, "dmg": 1.0, "force": 0.0, "resist": 0.3, "magic": false, "light": true,
		"hits": [[0.55, 0.75, 34.0], [0.55, 0.8, 36.0], [0.55, 0.9, 40.0], [1.65, 1.35, 48.0]], "stage_windup": 0.55, "variant_windup": 0.5, "final_stage_time": 1.65, "chain_window": 1.15, "recovery": 0.75, "reach": 2.4, "strike_radius": 4.0, "variation_reach": 6.5, "range": 9.0,
		"lunge_speed": 12.0, "lunge_time": 0.42, "lunge_dist": 5.0, "lunge_stop_dist": 2.2, "turn_deg": 360.0,
		"final_leap_time": 0.9, "final_leap_height": 3.2, "final_rise_time": 0.34, "final_apex_hold": 0.22,
		"final_fall_time": 0.34, "final_retreat_speed": 1.8,
		"slam_radius": 4.5, "slam_warn": 0.25, "slam_mult": 0.7, "slam_force": 48.0,
		"desc": "Pulsa la habilidad para encadenar cada uno de tres tajos de barrido que persiguen al objetivo. Tras el tercero, vuelve a pulsar para saltar y caer con un remate de área, o elige Estocada para cambiar el remate. El primer impacto tambalea; cada golpe consume parte del coste total.",
		"tele": "Hoja dorada; tras el tercer golpe puedes elegir remate. El salto falso pausa brevemente en el aire."},
	"salto_caida": {"name": "Salto con caída", "cost_type": "health", "cost": 15.0, "dmg": 1.5, "force": 50.0, "resist": 99.0, "magic": false,
		"rise": 0.55, "lock": 1.25, "land": 1.65, "radius": 3.5, "height": 6.0, "recovery": 0.7, "range": 14.0,
		"desc": "Salta muy alto siguiendo al objetivo hasta 0,4 s antes de caer; entonces fija el punto y cae con golpe en área. Sin marca en el suelo: mira al rival en el aire y muévete o rueda cuando empiece a bajar.",
		"tele": "El rival se eleva y queda suspendido; empieza a bajar = muévete."},
}

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
	"grito_guerra": "Grito", "guardia_reflejo": "Reflejo"}
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
	return ORDER + EXT_ORDER

static func has(id: String) -> bool:
	return DEFS.has(id) or BossAbilitiesExt.DEFS.has(id)

static func def(id: String) -> Dictionary:
	if BossAbilitiesExt.DEFS.has(id):
		return BossAbilitiesExt.DEFS[id]
	return DEFS.get(id, {})

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
