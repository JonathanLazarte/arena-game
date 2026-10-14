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
		"windup": 0.6, "interval": 0.9, "count": 3, "speed": 20.0, "life": 2.5, "home_deg": 60.0, "home_time": 2.5, "radius": 0.8, "recovery": 0.5, "range": 20.0,
		"desc": "Tres espectros de tajo dorados en diagonal, separados ~0,9 s. Persiguen girando 60°/s a 20 m/s: de cerca solo la voltereta los esquiva; a media distancia, correr de lado los deja atrás (no giran lo bastante). Si te rebasan, siguen de largo. Cada tajo aturde con tu magia.",
		"tele": "La hoja se vuelve dorada; tajos en media luna inclinada."},
	"escudo_mana": {"name": "Escudo de maná", "cost_type": "mana", "cost": 25.0, "dmg": 0.0, "force": 0.0, "resist": 99.0, "magic": true,
		"windup": 0.1, "active": 1.5, "range": 0.0,
		"desc": "1,5 s de invulnerabilidad TOTAL (daño y aturdimiento). Te mueves despacio y no atacas.",
		"tele": "Burbuja cian alrededor del personaje."},
	"combo_falso": {"name": "Combo de la pausa falsa", "cost_type": "stamina", "cost": 38.0, "dmg": 1.0, "force": 0.0, "resist": 0.3, "magic": false, "light": true,
		"hits": [[1.2, 0.8, 24.0], [4.2, 0.9, 24.0], [8.2, 1.7, 45.0]], "hit_windup": 1.2, "recovery": 0.8, "reach": 2.4, "arc": 70.0, "range": 5.0,
		"lunge_speed": 7.0, "lunge_time": 0.4, "turn_deg": 120.0,
		"desc": "Tres golpes lentos, cada uno avanza ~3 m hacia ti siguiéndote. Los dos primeros aturden como un golpe normal; el tercero llega tarde tras una pausa que invita a rodar antes de tiempo.",
		"tele": "Hoja dorada; tras el segundo golpe se queda alzada."},
	"salto_caida": {"name": "Salto con caída", "cost_type": "health", "cost": 15.0, "dmg": 1.5, "force": 50.0, "resist": 99.0, "magic": false,
		"rise": 0.55, "lock": 1.25, "land": 1.65, "radius": 3.5, "height": 6.0, "recovery": 0.7, "range": 14.0,
		"desc": "Salta muy alto siguiendo al objetivo hasta 0,4 s antes de caer; entonces fija el punto y cae con golpe en área. Sin marca en el suelo: mira al rival en el aire y muévete o rueda cuando empiece a bajar.",
		"tele": "El rival se eleva y queda suspendido; empieza a bajar = muévete."},
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
