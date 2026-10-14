class_name Smithing
## Ronda 20: herrería. Mejora +0..+10 (daño base y escalado) con oro y Piedras de forja
## por niveles, e infusiones (Pesado, Afilado, Sangrante, Venenoso, Gélido).
## Valores propios (inspirados en las Smithing Stones de Elden Ring: 3 piedras por nivel de
## piedra y un nivel final con piedra antigua; ver README).

const MAX_LEVEL := 10
## Ronda 30: el nivel de mejora es el «grabado» del arma (+1, +2...). Desde +5 la hoja brilla.
const GLOW_LEVEL := 5

## Color del brillo del grabado (más intenso cuanto más alto); negro = sin brillo.
static func engraving_glow(lvl: int) -> Color:
	if lvl < GLOW_LEVEL:
		return Color.BLACK
	var k := 0.35 + 0.65 * float(lvl - GLOW_LEVEL) / float(MAX_LEVEL - GLOW_LEVEL)
	return Color(0.55, 0.75, 1.0) * k
const DMG_PER_LEVEL := 0.06 ## +6 % de daño base por nivel (+10 = +60 %)
const SCALE_PER_LEVEL := 0.04 ## +4 % de los coeficientes de escalado por nivel
const STONES := ["piedra_1", "piedra_2", "piedra_3", "piedra_antigua"]
const STONE_NAMES := {"piedra_1": "Piedra de forja I", "piedra_2": "Piedra de forja II",
	"piedra_3": "Piedra de forja III", "piedra_antigua": "Piedra de forja antigua"}
const STONE_PRICES := {"piedra_1": 150, "piedra_2": 350, "piedra_3": 700, "piedra_antigua": 2000}
const STONE_SHOP_LEVEL := {"piedra_1": 1, "piedra_2": 3, "piedra_3": 5, "piedra_antigua": 8}
const INFUSE_GOLD := 500
const INFUSIONS := {
	"": {"name": "Normal", "suffix": "", "dmg": 1.0, "scale": {}, "status": {}},
	"pesado": {"name": "Pesado", "suffix": " pesada", "dmg": 1.04, "scale": {"fuerza": [1.4, 0.3], "destreza": [0.3, 0.0]}, "status": {}},
	"afilado": {"name": "Afilado", "suffix": " afilada", "dmg": 1.0, "scale": {"destreza": [1.4, 0.3], "fuerza": [0.4, 0.0]}, "status": {}},
	"sangrante": {"name": "Sangrante", "suffix": " sangrante", "dmg": 0.92, "scale": {}, "status": {"sangrado": 20.0}},
	"venenoso": {"name": "Venenoso", "suffix": " venenosa", "dmg": 0.92, "scale": {}, "status": {"veneno": 22.0}},
	"gelido": {"name": "Gélido", "suffix": " gélida", "dmg": 0.92, "scale": {}, "status": {"congelacion": 20.0}},
}
const INFUSION_ORDER := ["", "pesado", "afilado", "sangrante", "venenoso", "gelido"]

## Piedra necesaria para pasar a `next` (+1..+3 I, +4..+6 II, +7..+9 III, +10 antigua).
static func stone_for(next: int) -> String:
	if next >= MAX_LEVEL:
		return "piedra_antigua"
	return STONES[clampi((next - 1) / 3, 0, 2)]

static func stone_count(next: int) -> int:
	return 1 if next >= MAX_LEVEL else 1 + (next - 1) % 3

static func gold_cost(next: int) -> int:
	return 100 * next + 20 * next * next

static func cost(next: int) -> Dictionary:
	return {"oro": gold_cost(next), "piedra": stone_for(next), "n": stone_count(next)}

## Copia del arma con nivel e infusión aplicados (+0 normal devuelve el recurso tal cual).
static func effective(w: WeaponDef, lvl: int, inf: String = "") -> WeaponDef:
	if w == null or (lvl <= 0 and inf == ""):
		return w
	lvl = clampi(lvl, 0, MAX_LEVEL)
	var info: Dictionary = INFUSIONS.get(inf, INFUSIONS[""])
	var e: WeaponDef = w.duplicate()
	e.upgrade_level = lvl
	e.infusion = inf if INFUSIONS.has(inf) else ""
	e.upgrade_dmg_mult = (1.0 + DMG_PER_LEVEL * lvl) * float(info["dmg"])
	var sc: Dictionary = {}
	for k: String in w.scaling:
		sc[k] = float(w.scaling[k])
	for k: String in info["scale"]:
		var mk: Array = info["scale"][k]
		sc[k] = float(sc.get(k, 0.0)) * float(mk[0]) + float(mk[1])
	for k: String in sc:
		sc[k] = snappedf(float(sc[k]) * (1.0 + SCALE_PER_LEVEL * lvl), 0.01)
	e.scaling = sc
	var st: Dictionary = {}
	for k: String in w.status:
		st[k] = float(w.status[k]) * (1.0 + 0.03 * lvl)
	for k: String in info["status"]:
		st[k] = float(st.get(k, 0.0)) + float(info["status"][k]) * (1.0 + 0.04 * lvl)
	e.status = st
	e.display_name = display_name(w, lvl, inf)
	return e

static func display_name(w: WeaponDef, lvl: int, inf: String) -> String:
	var n := w.display_name
	if inf != "" and INFUSIONS.has(inf):
		n += String(INFUSIONS[inf]["suffix"])
	if lvl > 0:
		n += " +%d" % lvl
	return n

## Nivel de mejora del rival según su nivel de personaje.
static func rival_level(char_level: int) -> int:
	return clampi((char_level - 1) / 2, 0, MAX_LEVEL)

## Piedras de recompensa de una partida.
static func match_reward(won: bool, char_level: int) -> Dictionary:
	var r := {"piedra_1": 2 if won else 1}
	if won and char_level >= 4:
		r["piedra_2"] = 1
	if won and char_level >= 7:
		r["piedra_3"] = 1
	return r
