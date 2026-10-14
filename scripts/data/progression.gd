class_name Progression
## Ronda 11: progresión. Curva de XP, recompensas, precios y árboles de habilidad por rol.

const MAX_LEVEL := 30
const START_GOLD := 300 ## oro de una cuenta nueva

## XP necesaria para pasar del nivel n al n+1: 100·n^1.4 (redondeado a 10).
static func xp_to_next(n: int) -> int:
	return int(round(100.0 * pow(n, 1.4) / 10.0)) * 10

## Nivel alcanzado con una XP total.
static func level_for_xp(total: int) -> int:
	var lv := 1
	var need := xp_to_next(1)
	var t := total
	while t >= need and lv < MAX_LEVEL:
		t -= need
		lv += 1
		need = xp_to_next(lv)
	return lv

## XP acumulada al principio de un nivel.
static func xp_at_level(lv: int) -> int:
	var s := 0
	for i in range(1, lv):
		s += xp_to_next(i)
	return s

## [xp dentro del nivel, xp necesaria] para la barra.
static func level_progress(total: int) -> Vector2i:
	var lv := level_for_xp(total)
	if lv >= MAX_LEVEL:
		return Vector2i(1, 1)
	return Vector2i(total - xp_at_level(lv), xp_to_next(lv))

# ---------------- Recompensas de partida ----------------
const XP_WIN := 120
const XP_LOSS := 50
const XP_ROUND := 25
const XP_HIT := 3
const XP_HIT_CAP := 30 ## golpes que cuentan como máximo
const XP_PARRY := 10
const GOLD_WIN := 150
const GOLD_LOSS := 60
const GOLD_ROUND := 20
const GOLD_PARRY := 5
const GOLD_LEVEL_UP := 100 ## extra por cada nivel de cuenta ganado
const DIFF_MULT := {"facil": 0.8, "normal": 1.0, "dificil": 1.3}

## stats: {won: bool, rounds: int, hits: int, parries: int, difficulty: String}
static func match_rewards(stats: Dictionary) -> Dictionary:
	var k: float = DIFF_MULT.get(stats.get("difficulty", "normal"), 1.0)
	var won: bool = stats.get("won", false)
	var rounds: int = stats.get("rounds", 0)
	var hits: int = mini(stats.get("hits", 0), XP_HIT_CAP)
	var parries: int = stats.get("parries", 0)
	var lines: Array = []
	lines.append(["Victoria" if won else "Derrota", XP_WIN if won else XP_LOSS, GOLD_WIN if won else GOLD_LOSS])
	if rounds > 0:
		lines.append(["Rondas ganadas ×%d" % rounds, XP_ROUND * rounds, GOLD_ROUND * rounds])
	if hits > 0:
		lines.append(["Golpes ×%d" % hits, XP_HIT * hits, 0])
	if parries > 0:
		lines.append(["Parrys ×%d" % parries, XP_PARRY * parries, GOLD_PARRY * parries])
	var xp := 0
	var gold := 0
	for l: Array in lines:
		xp += l[1]
		gold += l[2]
	return {"xp": int(round(xp * k)), "gold": int(round(gold * k)), "lines": lines, "mult": k}

# ---------------- Precios y requisitos ----------------
## Ronda 15: los personajes ya no se compran. Precios antiguos, solo para reembolsar al migrar (v<4).
const LEGACY_CHARACTER_PRICE := {"caballero": 1200, "arquero": 1200, "berserker": 1500, "paladin": 1800, "asesino": 1800}
## Armas/eikons/monturas: nivel de cuenta mínimo + precio. Precio 0 = gratis al llegar al nivel.
const WEAPON_REQ := {"espada_escudo": [1, 0], "arco": [1, 0], "dagas": [1, 0], "hacha_2m": [1, 0],
	"espada_larga": [2, 350], "lanza": [4, 600], "ballesta": [3, 500]}
const EIKON_REQ := {"fenix": [1, 0], "lobo": [3, 800], "grifo": [5, 1200], "golem": [6, 1400]}
## Ronda 14 (guardado v3): monturas antiguas -> eikon equivalente, o se devuelve el oro.
const MOUNT_TO_EIKON := {"grifo": "grifo"}
const MOUNT_REFUND := {"unicornio": 500}

## Ronda 29: desbloquear otro personaje (nivel de cuenta, oro).
const CHAR_REQ := [3, 2500]

static func req(kind: String, id: String) -> Array:
	match kind:
		"character": return CHAR_REQ
		"weapon": return WEAPON_REQ.get(id, [1, 0])
		"eikon": return EIKON_REQ.get(id, [1, 0])
		"trinket":
			var t := Trinkets.def(id)
			return [int(t.get("level", 1)), int(t.get("price", 0))] if not t.is_empty() else [1, 0]
		"armor":
			var a := Catalog.armor(id)
			return [a.level, a.price] if a else [1, 0]
	return [1, 0]

# ---------------- Árboles de habilidad ----------------
## Cada rol: 4 nodos. "req" = nodo previo necesario. Coste en puntos de habilidad
## (1 punto por nivel del personaje a partir del 2). "mods" se suman en Fighter.
## Claves de mods: vida, estamina, poise (suman); velocidad, dano, block_cost, roll_cost (multiplican);
## parry_window (s, suma), roll_iframes (frames, suma), passive (potencia de la pasiva, suma a 1.0).
const TREES := {
	"caballero": [
		{"id": "cab_resistencia", "name": "Resistencia", "desc": "+15 de estamina.", "cost": 1, "req": "", "mods": {"estamina": 15.0}},
		{"id": "cab_parada", "name": "Parada experta", "desc": "Ventana de parry +0,06 s.", "cost": 1, "req": "cab_resistencia", "mods": {"parry_window": 0.06}},
		{"id": "cab_hierro", "name": "Guardia de hierro", "desc": "Guardia firme: −35 % de aguante al bloquear (antes −20 %).", "cost": 2, "req": "cab_resistencia", "mods": {"passive": 0.75}},
		{"id": "cab_veterano", "name": "Veterano", "desc": "+15 de vida.", "cost": 2, "req": "cab_parada", "mods": {"vida": 15.0}},
	],
	"arquero": [
		{"id": "arq_pies", "name": "Pies ligeros", "desc": "+6 % de velocidad.", "cost": 1, "req": "", "mods": {"velocidad": 1.06}},
		{"id": "arq_ojo", "name": "Ojo afilado", "desc": "Ojo de halcón: flechas +50 % (antes +30 %).", "cost": 1, "req": "arq_pies", "mods": {"passive": 0.67}},
		{"id": "arq_esquiva", "name": "Esquiva", "desc": "+2 frames de invulnerabilidad al rodar.", "cost": 2, "req": "arq_pies", "mods": {"roll_iframes": 2}},
		{"id": "arq_aguante", "name": "Aguante del cazador", "desc": "+15 de estamina.", "cost": 2, "req": "arq_ojo", "mods": {"estamina": 15.0}},
	],
	"berserker": [
		{"id": "ber_piel", "name": "Piel dura", "desc": "+20 de vida.", "cost": 1, "req": "", "mods": {"vida": 20.0}},
		{"id": "ber_furia", "name": "Furia ardiente", "desc": "Furia: +40 % de daño (antes +25 %).", "cost": 1, "req": "ber_piel", "mods": {"passive": 0.6}},
		{"id": "ber_roca", "name": "Inquebrantable", "desc": "+20 de equilibrio (poise).", "cost": 2, "req": "ber_piel", "mods": {"poise": 20.0}},
		{"id": "ber_brutal", "name": "Golpe brutal", "desc": "+8 % de daño cuerpo a cuerpo.", "cost": 2, "req": "ber_furia", "mods": {"dano": 1.08}},
	],
	"paladin": [
		{"id": "pal_fe", "name": "Fe", "desc": "+20 de vida.", "cost": 1, "req": "", "mods": {"vida": 20.0}},
		{"id": "pal_luz", "name": "Luz mayor", "desc": "Luz sanadora: 3,5 de vida/s (antes 2).", "cost": 1, "req": "pal_fe", "mods": {"passive": 0.75}},
		{"id": "pal_bastion", "name": "Bastión", "desc": "Bloquear cuesta un 15 % menos de aguante.", "cost": 2, "req": "pal_fe", "mods": {"block_cost": 0.85}},
		{"id": "pal_parada", "name": "Parada sagrada", "desc": "Ventana de parry +0,05 s.", "cost": 2, "req": "pal_luz", "mods": {"parry_window": 0.05}},
	],
	"asesino": [
		{"id": "ase_sigilo", "name": "Sigilo", "desc": "+2 frames de invulnerabilidad al rodar.", "cost": 1, "req": "", "mods": {"roll_iframes": 2}},
		{"id": "ase_filo", "name": "Filo envenenado", "desc": "+10 % de daño cuerpo a cuerpo.", "cost": 1, "req": "ase_sigilo", "mods": {"dano": 1.10}},
		{"id": "ase_paso", "name": "Paso de sombra", "desc": "La voltereta cuesta un 20 % menos.", "cost": 2, "req": "ase_sigilo", "mods": {"roll_cost": 0.8}},
		{"id": "ase_reflejos", "name": "Reflejos", "desc": "Ventana de parry +0,06 s.", "cost": 2, "req": "ase_filo", "mods": {"parry_window": 0.06}},
	],
}
const MULT_KEYS := ["velocidad", "dano", "block_cost", "roll_cost"]

static func tree(char_id: String) -> Array:
	return TREES.get(char_id, [])

static func skill(id: String) -> Dictionary:
	for t: Array in TREES.values():
		for s: Dictionary in t:
			if s["id"] == id:
				return s
	return {}

## Puntos de habilidad totales a un nivel de personaje.
static func skill_points_for_level(lv: int) -> int:
	return maxi(lv - 1, 0)

## Suma los modificadores de una lista de habilidades.
static func combine_mods(skills: Array) -> Dictionary:
	var m := {"vida": 0.0, "estamina": 0.0, "poise": 0.0, "velocidad": 1.0, "dano": 1.0, "block_cost": 1.0,
		"roll_cost": 1.0, "parry_window": 0.0, "roll_iframes": 0, "passive": 0.0}
	for id in skills:
		var s := skill(String(id))
		for k: String in s.get("mods", {}):
			if k in MULT_KEYS:
				m[k] = m[k] * s["mods"][k]
			else:
				m[k] = m[k] + s["mods"][k]
	return m
