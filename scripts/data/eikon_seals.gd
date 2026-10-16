class_name EikonSeals
## Recompensas únicas del Duelo de Campeones. Un sello equipado modifica la invocación del Eikon.

const DEFS := {
	"brasa_negra": {"name": "Sello de la Brasa Negra", "desc": "+25 % de daño del Eikon invocado.", "fx": {"damage": 1.25}},
	"juramento_escarlata": {"name": "Sello del Juramento Escarlata", "desc": "+30 % de duración de la invocación.", "fx": {"duration": 1.3}},
	"corazon_petreo": {"name": "Sello del Corazón Pétreo", "desc": "+35 % de vida para el Eikon invocado.", "fx": {"health": 1.35}},
	"nucleo_vendaval": {"name": "Sello del Núcleo del Vendaval", "desc": "El Eikon ataca un 20 % más rápido.", "fx": {"cooldown": 0.8}},
	"pacto_draconico": {"name": "Sello del Pacto Dracónico", "desc": "+15 % de daño y +15 % de duración del Eikon.", "fx": {"damage": 1.15, "duration": 1.15}},
}
const ORDER := ["brasa_negra", "juramento_escarlata", "corazon_petreo", "nucleo_vendaval", "pacto_draconico"]

static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func name_of(id: String) -> String:
	return String(DEFS[id]["name"]) if DEFS.has(id) else "Sello desconocido"

static func apply_to(data: EikonData, id: String) -> EikonData:
	if data == null or not DEFS.has(id):
		return data
	var out := data.duplicate(true) as EikonData
	var fx: Dictionary = DEFS[id]["fx"]
	out.attack_damage *= float(fx.get("damage", 1.0))
	out.special_damage *= float(fx.get("damage", 1.0))
	out.duration *= float(fx.get("duration", 1.0))
	out.max_health *= float(fx.get("health", 1.0))
	out.attack_cooldown *= float(fx.get("cooldown", 1.0))
	return out
