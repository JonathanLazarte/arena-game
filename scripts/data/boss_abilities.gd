class_name BossAbilities
## Ronda 31: habilidades de jefe. Máx. 3 equipadas por personaje (pestaña «Jefe»). Sin tiempos de
## recarga: cada una cuesta aguante, maná (Energía) o vida (no se puede usar si te dejaría a 0).
## dmg = multiplicador del daño fuerte del arma (o del ligero, «light»); force = fuerza de
## aturdimiento asignada (se suma a Fuerza+arma o a la magia, ver StunRules); resist = súper-armadura
## (la robustez se multiplica por 1 + resist mientras dura); «tele» = cómo se reconoce.

const MAX_EQUIPPED := 3
const DEFAULT := ["estocada"]
const ORDER := ["estocada", "carga_area", "rafaga", "escudo_mana", "combo_falso", "salto_caida"]
const COST_NAMES := {"stamina": "aguante", "mana": "maná", "health": "vida"}

const DEFS := {
	"estocada": {"name": "Estocada de jefe", "cost_type": "stamina", "cost": 30.0, "dmg": 1.6, "force": 60.0, "resist": 99.0, "magic": false,
		"windup": 1.6, "dist": 12.0, "speed": 30.0, "reach": 1.8, "home_deg": 140.0, "range": 12.0,
		"desc": "Carga 1,6 s siguiendo al objetivo (invulnerable) y sale disparada 12 m corrigiendo la dirección. Caminar de lado NO la esquiva: hay que rodar justo antes del impacto.",
		"tele": "Hoja roja que se enciende y sonido que sube."},
	"carga_area": {"name": "Carga en área", "cost_type": "mana", "cost": 35.0, "dmg": 1.4, "force": 45.0, "resist": 4.0, "magic": true,
		"windup": 1.8, "radius": 4.5, "recovery": 0.6, "range": 3.5,
		"desc": "Inmóvil, acumula energía 1,8 s con robustez x5 (un combo fuerte la interrumpe) y estalla en 4,5 m. Huye o córtala; no te quedes pegando.",
		"tele": "Anillo azul en el suelo que se llena; pose de grito."},
	"rafaga": {"name": "Ráfaga de 3 cortes", "cost_type": "mana", "cost": 30.0, "dmg": 0.55, "force": 14.0, "resist": 0.5, "magic": true, "light": true,
		"windup": 0.55, "interval": 0.28, "count": 3, "speed": 18.0, "life": 1.5, "home_deg": 55.0, "home_time": 0.6, "recovery": 0.5, "range": 18.0,
		"desc": "Tres tajos mágicos desde la espada que persiguen un poco: caminando te alcanzan; corriendo a cierta distancia se esquivan. Cada tajo aturde con tu magia.",
		"tele": "La hoja se vuelve violeta y la espada se alza."},
	"escudo_mana": {"name": "Escudo de maná", "cost_type": "mana", "cost": 25.0, "dmg": 0.0, "force": 0.0, "resist": 99.0, "magic": true,
		"windup": 0.1, "active": 1.5, "range": 0.0,
		"desc": "1,5 s de invulnerabilidad TOTAL (daño y aturdimiento). Te mueves despacio y no atacas.",
		"tele": "Burbuja cian alrededor del personaje."},
	"combo_falso": {"name": "Combo de la pausa falsa", "cost_type": "stamina", "cost": 38.0, "dmg": 1.0, "force": 0.0, "resist": 0.3, "magic": false, "light": true,
		"hits": [[0.30, 0.7, 4.0], [0.62, 0.7, 4.0], [0.94, 0.9, 18.0], [1.75, 1.7, 45.0]], "recovery": 0.55, "reach": 2.4, "arc": 70.0, "range": 2.6,
		"desc": "Cuatro golpes: los dos primeros apenas aturden (no se abusa), el tercero sí y el cuarto llega tarde tras una pausa que invita a rodar antes de tiempo.",
		"tele": "Hoja dorada; tras el tercer golpe se queda alzada."},
	"salto_caida": {"name": "Salto con caída", "cost_type": "health", "cost": 15.0, "dmg": 1.5, "force": 50.0, "resist": 99.0, "magic": false,
		"rise": 0.55, "lock": 1.25, "land": 1.65, "radius": 3.5, "height": 6.0, "recovery": 0.7, "range": 14.0,
		"desc": "Salta muy alto; una marca en el suelo sigue al objetivo hasta 0,4 s antes de caer y queda fija. Al caer, golpe en área. Sal de la marca en cuanto se detenga.",
		"tele": "Marca roja en el suelo que deja de moverse antes del impacto."},
}

static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func cost_text(id: String) -> String:
	var d := def(id)
	return "%d %s" % [int(d.get("cost", 0)), COST_NAMES.get(String(d.get("cost_type", "")), "")]

## Ficha de enciclopedia (texto con BBCode).
static func codex(id: String) -> String:
	var d := def(id)
	if d.is_empty():
		return ""
	var t := "[b]%s[/b] · coste %s\n%s\n" % [d["name"], cost_text(id), d["desc"]]
	if float(d["dmg"]) > 0.0:
		t += "Daño: x%.2f del %s%s · " % [d["dmg"], "ligero" if d.get("light", false) else "fuerte", " (por tajo)" if id == "rafaga" else ""]
	if id == "combo_falso":
		var fs: Array = []
		for h: Array in d["hits"]:
			fs.append("%d" % int(h[2]))
		t += "Fuerza de aturdimiento por golpe: %s (+ Fuerza y arma)\n" % " / ".join(fs)
	elif float(d["force"]) > 0.0:
		t += "Fuerza de aturdimiento: %d + %s\n" % [int(d["force"]), "magia" if d["magic"] else "Fuerza y arma"]
	else:
		t += "\n"
	t += "Robustez durante la habilidad: %s\n" % ("inmune" if float(d["resist"]) >= 99.0 else "x%.1f" % (1.0 + float(d["resist"])))
	t += "Se reconoce: %s" % d["tele"]
	return t
