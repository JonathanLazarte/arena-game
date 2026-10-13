class_name Catalog
## Listas explícitas de definiciones (en builds exportados no se puede listar res:// con fiabilidad).

const CHARACTERS := ["res://resources/characters/caballero.tres", "res://resources/characters/arquero.tres",
	"res://resources/characters/berserker.tres", "res://resources/characters/paladin.tres", "res://resources/characters/asesino.tres"]
const WEAPONS := ["res://resources/weapons/espada_escudo.tres", "res://resources/weapons/espada_larga.tres",
	"res://resources/weapons/hacha_2m.tres", "res://resources/weapons/dagas.tres", "res://resources/weapons/lanza.tres",
	"res://resources/weapons/arco.tres", "res://resources/weapons/ballesta.tres"]
## Ronda 19: piezas de armadura (casco, pecho, guantes, piernas) por conjunto.
const ARMOR := ["res://resources/armor/escudero_casco.tres", "res://resources/armor/escudero_pecho.tres", "res://resources/armor/escudero_guantes.tres", "res://resources/armor/escudero_piernas.tres", "res://resources/armor/explorador_casco.tres", "res://resources/armor/explorador_pecho.tres", "res://resources/armor/explorador_guantes.tres", "res://resources/armor/explorador_piernas.tres", "res://resources/armor/salvaje_casco.tres", "res://resources/armor/salvaje_pecho.tres", "res://resources/armor/salvaje_guantes.tres", "res://resources/armor/salvaje_piernas.tres", "res://resources/armor/novicio_casco.tres", "res://resources/armor/novicio_pecho.tres", "res://resources/armor/novicio_guantes.tres", "res://resources/armor/novicio_piernas.tres", "res://resources/armor/sombra_casco.tres", "res://resources/armor/sombra_pecho.tres", "res://resources/armor/sombra_guantes.tres", "res://resources/armor/sombra_piernas.tres", "res://resources/armor/viento_casco.tres", "res://resources/armor/viento_pecho.tres", "res://resources/armor/viento_guantes.tres", "res://resources/armor/viento_piernas.tres", "res://resources/armor/vigia_casco.tres", "res://resources/armor/vigia_pecho.tres", "res://resources/armor/vigia_guantes.tres", "res://resources/armor/vigia_piernas.tres", "res://resources/armor/ceniza_casco.tres", "res://resources/armor/ceniza_pecho.tres", "res://resources/armor/ceniza_guantes.tres", "res://resources/armor/ceniza_piernas.tres", "res://resources/armor/bastion_casco.tres", "res://resources/armor/bastion_pecho.tres", "res://resources/armor/bastion_guantes.tres", "res://resources/armor/bastion_piernas.tres"]
const ARMOR_SLOTS := ["casco", "pecho", "guantes", "piernas"]
const ARMOR_SLOT_NAMES := {"casco": "Casco", "pecho": "Pecho", "guantes": "Guantes", "piernas": "Piernas"}
## Ronda 14: los eikons son también las monturas (fénix, lobo y grifo se montan; el gólem lucha a tu lado).
const EIKONS := {"fenix": "res://resources/eikons/phoenix.tres", "lobo": "res://resources/eikons/ice_wolf.tres",
	"grifo": "res://resources/eikons/griffin.tres", "golem": "res://resources/eikons/stone_golem.tres"}
const DIFFICULTIES := {"facil": "res://resources/ai/easy.tres", "normal": "res://resources/ai/normal.tres", "dificil": "res://resources/ai/hard.tres"}
const DIFFICULTY_NAMES := {"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}

static func characters() -> Array[CharacterDef]:
	var out: Array[CharacterDef] = []
	for p: String in CHARACTERS:
		out.append(load(p) as CharacterDef)
	return out

static func weapons() -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	for p: String in WEAPONS:
		out.append(load(p) as WeaponDef)
	return out

static func character(id: String) -> CharacterDef:
	for c in characters():
		if c.id == id:
			return c
	return load(CHARACTERS[0])

static func weapon(id: String) -> WeaponDef:
	for w in weapons():
		if w.id == id:
			return w
	return load(WEAPONS[0])

static func weapons_for(c: CharacterDef) -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	for w in weapons():
		if c.allows(w.id):
			out.append(w)
	return out

static func armors() -> Array[ArmorDef]:
	var out: Array[ArmorDef] = []
	for p: String in ARMOR:
		out.append(load(p) as ArmorDef)
	return out

static func armor(id: String) -> ArmorDef:
	if id == "":
		return null
	for a in armors():
		if a.id == id:
			return a
	return null

## Equipo inicial de un rol: {slot: id}.
static func starter_armor(char_id: String) -> Dictionary:
	var out := {}
	for a in armors():
		if a.starter_for == char_id:
			out[a.slot] = a.id
	return out

## Conjuntos a la venta (orden de nivel): [{set_id, set_name, level, price, pieces: [ArmorDef]}].
static func armor_sets_for_sale() -> Array:
	var sets := {}
	var order: Array = []
	for a in armors():
		if a.price <= 0:
			continue
		if not sets.has(a.set_id):
			sets[a.set_id] = {"set_id": a.set_id, "set_name": a.set_name, "level": a.level, "price": 0, "pieces": [], "class": a.weight_class}
			order.append(a.set_id)
		sets[a.set_id]["pieces"].append(a)
		sets[a.set_id]["price"] += a.price
	var out: Array = []
	for k in order:
		out.append(sets[k])
	return out
