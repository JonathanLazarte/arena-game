class_name WeaponArts
## Ronda 21: artes de arma (estilo Cenizas de guerra). Colección intercambiable: cada arma cuerpo a
## cuerpo lleva un arte equipado (Armas → «Arte»), se cambia cuando quieras entre las que poseés.
## Se activa con «Habilidad» (G) si tu personaje no tiene habilidad propia (el Berserker conserva
## el golpe sísmico). Cuesta Energía.

const DEFS := {
	"estocada_impulsada": {"name": "Estocada firme", "cost": 18.0, "cooldown": 5.0, "price": 0,
		"mult": 1.5, "desc": "Tajo frontal potente y concentrado en el lugar (x1,5) sin desplazamiento."},
	"torbellino": {"name": "Torbellino", "cost": 22.0, "cooldown": 7.0, "price": 300,
		"mult": 1.3, "radius": 3.0, "desc": "Giro de 360° estático que barre alrededor (x1,3) sin desplazamiento."},
}
const ORDER := ["estocada_impulsada", "torbellino"]
const STARTER := ["estocada_impulsada"]

static func art(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func name_of(id: String) -> String:
	return String(DEFS[id]["name"]) if DEFS.has(id) else "Ninguna"

static func compatible(w: WeaponDef) -> bool:
	return w != null and not w.ranged
