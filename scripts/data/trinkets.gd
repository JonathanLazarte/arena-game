class_name Trinkets
## Ronda 30: anillos y talismanes. Equipables sin modelo 3D (2 ranuras de anillo, 3 de talismán).
## Nombres propios del juego. Efectos (se combinan multiplicando o sumando):
##   dmg_<subtipo> / dmg_todo: multiplicador de daño cuerpo a cuerpo según el subtipo físico del arma
##   poise: equilibrio extra · parry_stamina: aguante recuperado al desviar con éxito
##   roll_iframes: fotogramas de invulnerabilidad extra en la voltereta
##   stamina_cost: multiplicador del gasto de aguante · eikon_rate: multiplicador del medidor de eikon

const RING_SLOTS := 2
const TALISMAN_SLOTS := 3

const RINGS := {
	"filo_hendido": {"name": "Anillo del Filo Hendido", "desc": "+12 % de daño cortante.", "price": 900, "level": 1, "fx": {"dmg_cortante": 1.12}},
	"martillo_sordo": {"name": "Sortija del Martillo Sordo", "desc": "+12 % de daño contundente.", "price": 900, "level": 1, "fx": {"dmg_contundente": 1.12}},
	"aguijon": {"name": "Aro del Aguijón", "desc": "+12 % de daño perforante.", "price": 900, "level": 1, "fx": {"dmg_perforante": 1.12}},
	"filo_llano": {"name": "Anillo del Filo Llano", "desc": "+10 % de daño estándar.", "price": 800, "level": 1, "fx": {"dmg_estandar": 1.10}},
	"raiz_firme": {"name": "Anillo de Raíz Firme", "desc": "+15 de equilibrio.", "price": 1200, "level": 2, "fx": {"poise": 15.0}},
	"cefiro": {"name": "Sortija del Céfiro", "desc": "+2 fotogramas de invulnerabilidad en la voltereta.", "price": 1500, "level": 3, "fx": {"roll_iframes": 2}},
}

const TALISMANS := {
	"eco_templado": {"name": "Talismán del Eco Templado", "desc": "Desviar con éxito devuelve 18 de aguante.", "price": 1000, "level": 1, "fx": {"parry_stamina": 18.0}},
	"aliento_largo": {"name": "Amuleto del Aliento Largo", "desc": "−12 % de gasto de aguante.", "price": 1300, "level": 2, "fx": {"stamina_cost": 0.88}},
	"lazo_eikonico": {"name": "Talismán del Lazo Eikónico", "desc": "El medidor de eikon se llena un 20 % más rápido.", "price": 1100, "level": 1, "fx": {"eikon_rate": 1.2}},
	"paso_ligero": {"name": "Amuleto del Paso Ligero", "desc": "+1 fotograma de invulnerabilidad y −8 % de aguante.", "price": 1400, "level": 3, "fx": {"roll_iframes": 1, "stamina_cost": 0.92}},
	"brasa_furiosa": {"name": "Talismán de la Brasa Furiosa", "desc": "+6 % de todo el daño cuerpo a cuerpo.", "price": 1600, "level": 4, "fx": {"dmg_todo": 1.06}},
	"muralla": {"name": "Amuleto de la Muralla", "desc": "+10 de equilibrio y −5 % de aguante.", "price": 1200, "level": 2, "fx": {"poise": 10.0, "stamina_cost": 0.95}},
}

const ADDITIVE := ["poise", "parry_stamina", "roll_iframes"]

static func def(id: String) -> Dictionary:
	return RINGS.get(id, TALISMANS.get(id, Titles.def(id))) # ronda 30: el título también suma efectos

static func kind(id: String) -> String:
	return "ring" if RINGS.has(id) else ("talisman" if TALISMANS.has(id) else "")

static func neutral() -> Dictionary:
	return {"poise": 0.0, "parry_stamina": 0.0, "roll_iframes": 0, "stamina_cost": 1.0, "eikon_rate": 1.0,
		"dmg_todo": 1.0, "dmg_estandar": 1.0, "dmg_cortante": 1.0, "dmg_contundente": 1.0, "dmg_perforante": 1.0}

## Efectos combinados de una lista de ids equipados (anillos + talismanes).
static func combine(ids: Array) -> Dictionary:
	var out := neutral()
	for id in ids:
		var fx: Dictionary = def(String(id)).get("fx", {})
		for k: String in fx:
			if k in ADDITIVE:
				out[k] = out[k] + fx[k]
			else:
				out[k] = float(out[k]) * float(fx[k])
	return out

## Multiplicador de daño para un subtipo físico.
static func dmg_mult(fx: Dictionary, phys: String) -> float:
	return float(fx.get("dmg_todo", 1.0)) * float(fx.get("dmg_" + phys, 1.0))
