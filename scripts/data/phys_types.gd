class_name PhysTypes
## Ronda 24: subtipos de daño físico (estándar, contundente, cortante, perforante) y su
## interacción con la armadura. El subtipo escala la ABSORCIÓN física de la armadura según su
## clase de peso (>1 = la armadura protege más contra ese subtipo, <1 = menos).
## Idea de ER (Fextralife «Damage Types»): lo contundente vence a la armadura pesada, lo cortante
## destroza a la ligera y lo perforante castiga los contraataques.

const TYPES := ["estandar", "contundente", "cortante", "perforante"]
const NAMES := {"estandar": "Estándar", "contundente": "Contundente", "cortante": "Cortante", "perforante": "Perforante"}
const ABSORB_MOD := {
	"ligero": {"estandar": 1.0, "contundente": 1.15, "cortante": 0.75, "perforante": 0.9},
	"medio": {"estandar": 1.0, "contundente": 1.0, "cortante": 1.0, "perforante": 0.9},
	"pesado": {"estandar": 1.0, "contundente": 0.7, "cortante": 1.25, "perforante": 1.1},
}
## Daño de equilibrio extra por subtipo (lo contundente tumba más).
const POISE_MOD := {"estandar": 1.0, "contundente": 1.15, "cortante": 0.95, "perforante": 1.0}
## Bonificación de contraataque por subtipo (golpear a quien está atacando).
const COUNTER_DMG := {"estandar": 1.15, "contundente": 1.15, "cortante": 1.15, "perforante": 1.25}
const COUNTER_POISE := 1.3

static func absorb_mod(armor_class: String, sub: String) -> float:
	return float(ABSORB_MOD.get(armor_class, ABSORB_MOD["medio"]).get(sub, 1.0))

## Subtipo de un golpe: el del ComboHit si lo define; las estocadas son perforantes; si no, el del arma.
static func of_hit(w: WeaponDef, hit: ComboHit) -> String:
	if hit != null:
		if hit.phys_type != "":
			return hit.phys_type
		if hit.direction == "estocada":
			return "perforante"
	return w.phys_type if w != null else "estandar"
