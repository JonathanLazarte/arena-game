class_name EquipStats
## Ronda 19: estadísticas derivadas de combate al estilo de los «soulslike» (fórmulas propias):
## Ataque (AR) por arma = base + bono de atributos; Defensa plana (nivel y atributos);
## Absorción % por tipo (armadura, multiplicativa); Resistencias; Equilibrio; Carga de equipo.
## Todo se compara con la referencia del rol (nivel 1, reparto inicial, equipo inicial):
## a nivel 1 con el equipo inicial el combate es igual que antes.

const TYPES := ["fisico", "magico", "fuego", "rayo", "sagrado"]
const TYPE_NAMES := {"fisico": "Físico", "magico": "Mágico", "fuego": "Fuego", "rayo": "Rayo", "sagrado": "Sagrado"}
const RESISTS := ["robustez", "inmunidad", "concentracion", "vitalidad"]
const RESIST_NAMES := {"robustez": "Robustez", "inmunidad": "Inmunidad", "concentracion": "Concentración", "vitalidad": "Vitalidad"}
## Elemento de cada eikon (su daño usa la absorción de ese tipo).
const EIKON_ELEMENT := {"fenix": "fuego", "lobo": "magico", "grifo": "rayo", "golem": "fisico"}
const WEAPON_WEIGHT := {"espada_escudo": 6.0, "espada_larga": 5.0, "hacha_2m": 9.0, "lanza": 6.0, "dagas": 2.0, "arco": 3.0, "ballesta": 5.0}
## Umbrales de carga (fracción de la carga máxima).
const LIGHT_MAX := 0.3
const MEDIUM_MAX := 0.7
const LOAD_NAMES := {"ligero": "Ligero", "medio": "Medio", "pesado": "Pesado", "sobrecargado": "Sobrecargado"}
## Voltereta según la carga. dist = distancia, iframes = frames (30 fps) extra, rec = recuperación,
## regen = regeneración de aguante, move = velocidad de movimiento, roll = puede rodar.
const ROLL_BY_LOAD := {
	"ligero": {"dist": 1.15, "iframes": 0, "rec": 1.0, "regen": 1.0, "move": 1.0, "roll": true, "name": "Voltereta ligera (más lejos)"},
	"medio": {"dist": 1.0, "iframes": 0, "rec": 1.0, "regen": 1.0, "move": 1.0, "roll": true, "name": "Voltereta media"},
	"pesado": {"dist": 0.8, "iframes": -1, "rec": 1.6, "regen": 0.8, "move": 0.95, "roll": true, "name": "Voltereta pesada (corta y lenta)"},
	"sobrecargado": {"dist": 0.35, "iframes": -12, "rec": 1.8, "regen": 0.6, "move": 0.6, "roll": false, "name": "Sin voltereta (tropiezo)"},
}

static func weapon_weight(w: WeaponDef) -> float:
	return float(WEAPON_WEIGHT.get(w.id, 4.0)) if w else 0.0

static func load_class(ratio: float) -> String:
	if ratio < LIGHT_MAX: return "ligero"
	if ratio < MEDIUM_MAX: return "medio"
	if ratio < 1.0: return "pesado"
	return "sobrecargado"

## Defensa plana (por nivel y atributos).
static func defense(lv: int, a: Dictionary) -> float:
	return 20.0 + 1.0 * (lv - 1) + 0.2 * float(a.get("vitalidad", 10)) + 0.15 * float(a.get("aguante", 10)) + 0.15 * float(a.get("fuerza", 10))

## Multiplicador de defensa según la relación ataque/defensa (curva propia: 10 %..90 %).
static func defense_mult(attack: float, def: float) -> float:
	var r := attack / maxf(def, 1.0)
	return clampf(0.9 * r / (r + 0.45), 0.1, 0.9)

static func _soft(v: float) -> float:
	return minf(v, 40.0) + 0.4 * maxf(v - 40.0, 0.0)

static func absorption(armor: Dictionary) -> Dictionary:
	var out := {}
	for t: String in TYPES:
		var keep := 1.0
		for s: String in armor:
			var p: ArmorDef = armor[s]
			if p:
				keep *= 1.0 - float(p.absorption.get(t, 0.0))
		out[t] = 1.0 - keep
	return out

static func resists(lv: int, a: Dictionary, armor: Dictionary) -> Dictionary:
	var base := 40.0 + 1.5 * (lv - 1)
	var out := {"robustez": base + _soft(float(a.get("aguante", 10))), "inmunidad": base + _soft(float(a.get("vitalidad", 10))),
		"concentracion": base + _soft(float(a.get("concentracion", 10))), "vitalidad": base + _soft(float(a.get("vinculo", 10)))}
	for s: String in armor:
		var p: ArmorDef = armor[s]
		if p:
			for k: String in p.resist:
				out[k] = float(out.get(k, 0.0)) + float(p.resist[k])
	return out

static func armor_defs(ids: Dictionary) -> Dictionary:
	var out := {}
	for s: String in Catalog.ARMOR_SLOTS:
		out[s] = Catalog.armor(String(ids.get(s, "")))
	return out

## Ataque (AR) de un arma: {base, bonus, total, sagrado, fisico, unmet}.
static func attack_rating(c: CharacterDef, w: WeaponDef, a: Dictionary, dano_mod: float = 1.0, equipped: bool = true) -> Dictionary:
	if w == null:
		return {"base": 0.0, "bonus": 0.0, "total": 0.0, "fisico": 0.0, "sagrado": 0.0, "unmet": []}
	var base := (w.arrow_damage if w.ranged else w.light_damage) * c.dano * dano_mod * w.upgrade_dmg_mult
	var total := base * Attributes.weapon_mult(w, c.id, a, equipped)
	var holy := 0.0
	var cdev: float = w.scaling.get("devocion", 0.0)
	if cdev > 0.0:
		var norm := 1.0
		for k: String in Attributes.SCALE_KEYS:
			norm += float(w.scaling.get(k, 0.0)) * Attributes.curve("escala", float(Attributes.start_for(c.id)[k]))
		holy = base * cdev * Attributes.curve("escala", float(a.get("devocion", 10))) / norm
	return {"base": base, "bonus": total - base, "total": total, "fisico": total - holy, "sagrado": holy, "unmet": Attributes.unmet(w, a)}

## Hoja completa (lo que muestra la ficha y usa el combate).
static func sheet(c: CharacterDef, lv: int, a: Dictionary, w: WeaponDef, w2: WeaponDef, armor: Dictionary) -> Dictionary:
	var ad := Attributes.derived(c.id, a)
	var weight := weapon_weight(w) + weapon_weight(w2)
	var apoise := 0.0
	for s: String in armor:
		var p: ArmorDef = armor[s]
		if p:
			weight += p.weight
			apoise += p.poise
	var cap: float = ad["carga"]
	var ratio := weight / maxf(cap, 1.0)
	var cls := load_class(ratio)
	return {"defensa": defense(lv, a), "absorcion": absorption(armor), "resist": resists(lv, a, armor),
		"armor_poise": apoise, "peso": weight, "carga_max": cap, "carga": ratio, "clase": cls, "roll": ROLL_BY_LOAD[cls]}

## Referencia del rol: nivel 1, reparto inicial y equipo inicial con su arma por defecto.
static func role_reference(c: CharacterDef) -> Dictionary:
	return sheet(c, 1, Attributes.start_for(c.id), Catalog.weapon(c.default_weapon), null, armor_defs(Catalog.starter_armor(c.id)))

## Daño recibido: ataque × multiplicador de defensa × (1 − absorción), relativo a la referencia.
static func incoming(amount: float, dtype: String, me: Dictionary, ref: Dictionary, sub: String = "") -> float:
	if amount <= 0.0:
		return amount
	var dm := defense_mult(amount, me["defensa"]) / defense_mult(amount, ref["defensa"])
	var am := float(me["absorcion"].get(dtype, 0.0))
	var ar := float(ref["absorcion"].get(dtype, 0.0))
	if dtype == "fisico" and sub != "":
		# Ronda 24: subtipo físico contra la clase de armadura (la referencia del rol usa el mismo subtipo)
		am = clampf(am * PhysTypes.absorb_mod(String(me.get("clase", "medio")), sub), 0.0, 0.9)
		ar = clampf(ar * PhysTypes.absorb_mod(String(ref.get("clase", "medio")), sub), 0.0, 0.9)
	var ab := (1.0 - am) / (1.0 - ar)
	return amount * dm * ab

## Multiplicador de una resistencia frente a la referencia (más = menos efecto), con topes.
static func resist_mult(k: String, me: Dictionary, ref: Dictionary) -> float:
	return clampf(1.0 - (float(me["resist"][k]) - float(ref["resist"][k])) / 400.0, 0.7, 1.15)

## Armadura del rival según su rol y nivel: equipo inicial; a nivel 3+ un conjunto acorde a su rol.
static func rival_armor(char_id: String, lv: int) -> Dictionary:
	var pref := {"caballero": "vigia", "paladin": "bastion", "berserker": "vigia", "arquero": "viento", "asesino": "ceniza"}
	var ids := Catalog.starter_armor(char_id)
	var sid: String = pref.get(char_id, "vigia")
	for p in Catalog.armors():
		if p.set_id == sid and p.level <= lv and lv >= 3:
			ids[p.slot] = p.id
	return ids
