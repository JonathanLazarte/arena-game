class_name Catalog
## Listas explícitas de definiciones (en builds exportados no se puede listar res:// con fiabilidad).

const CHARACTERS := ["res://resources/characters/caballero.tres", "res://resources/characters/arquero.tres",
	"res://resources/characters/berserker.tres", "res://resources/characters/paladin.tres", "res://resources/characters/asesino.tres"]
const WEAPONS := ["res://resources/weapons/espada_escudo.tres", "res://resources/weapons/espada_larga.tres",
	"res://resources/weapons/hacha_2m.tres", "res://resources/weapons/dagas.tres", "res://resources/weapons/lanza.tres",
	"res://resources/weapons/arco.tres"]
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
