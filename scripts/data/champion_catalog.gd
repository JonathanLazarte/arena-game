class_name ChampionCatalog
## Ronda 35: perfiles fijos para la escalera de campeones.

const ORDER := ["vael", "lyra", "gorath", "nysera", "draven"]
const DEFS := {
	"vael": {"name": "Vael", "title": "el Verdugo de Ceniza", "character": "berserker", "weapon": "hacha_2m", "eikon": "fenix",
		"boss": ["presa_verdugo", "onda_rastrera", "furia_fase"], "spell": "chispa", "art": "estocada_impulsada", "phase2_summon": false, "seal": "brasa_negra",
		"style": {"distance": 4.8, "special": 0.9, "boss": 1.15, "commit": 1.15, "orbit": 0.85, "phase2": 1.2},
		"intro": "Un ejecutor brutal que castiga las pausas y cubre el suelo de brasas."},
	"lyra": {"name": "Lyra", "title": "Centinela Escarlata", "character": "paladin", "weapon": "espada_escudo", "eikon": "lobo",
		"boss": ["danza_cisne", "paso_espectral", "postura_contra"], "spell": "aliento_helado", "art": "torbellino", "phase2_summon": false, "seal": "juramento_escarlata",
		"style": {"distance": 5.4, "special": 0.9, "boss": 1.0, "commit": 0.9, "orbit": 1.2, "phase2": 1.1},
		"intro": "Una duelista defensiva que responde con parries, escarcha y cortes veloces."},
	"gorath": {"name": "Gorath", "title": "el Bastión de Piedra", "character": "caballero", "weapon": "lanza", "eikon": "golem",
		"boss": ["giro_martillo", "carga_area", "salto_caida"], "spell": "piel_de_piedra", "art": "estocada_impulsada", "phase2_summon": true, "seal": "corazon_petreo",
		"style": {"distance": 6.0, "special": 1.0, "boss": 0.9, "commit": 0.9, "orbit": 0.7, "phase2": 1.35},
		"intro": "Un guardián paciente que gana fuerza si lo dejas preparar sus golpes."},
	"nysera": {"name": "Nysera", "title": "la Cazadora del Vendaval", "character": "asesino", "weapon": "dagas", "eikon": "grifo",
		"boss": ["rafaga", "rayos_trazadores", "lluvia_meteoros"], "spell": "saeta_vendaval", "art": "torbellino", "phase2_summon": false, "seal": "nucleo_vendaval",
		"style": {"distance": 6.8, "special": 1.25, "boss": 1.1, "commit": 1.0, "orbit": 1.35, "phase2": 1.25},
		"intro": "Una adversaria veloz que alterna proyectiles y entradas por los flancos."},
	"draven": {"name": "Draven", "title": "el Heraldo del Fin", "character": "berserker", "weapon": "espada_larga", "eikon": "fenix",
		"boss": ["aliento_dragon", "combo_falso", "furia_fase"], "spell": "chispa", "art": "estocada_impulsada", "phase2_summon": false, "seal": "pacto_draconico",
		"style": {"distance": 5.0, "special": 1.1, "boss": 1.2, "commit": 1.1, "orbit": 1.0, "phase2": 1.4},
		"intro": "El último campeón mezcla presión cercana con un remate de área engañoso."},
}

static func at(index: int) -> Dictionary:
	if ORDER.is_empty():
		return {}
	return DEFS.get(ORDER[clampi(index, 0, ORDER.size() - 1)], {})

static func by_id(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func display_name(d: Dictionary) -> String:
	return "%s, %s" % [d.get("name", "Campeón"), d.get("title", "")]
