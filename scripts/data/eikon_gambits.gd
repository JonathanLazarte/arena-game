class_name EikonGambits
extends RefCounted
## Sistema de Gambits para Eikons inspirado en FFXII y adaptado a móviles.
## Cada Eikon cuenta con 3 ranuras tácticas evaluadas en orden de prioridad (1 -> 2 -> 3):
## [ Condición ] ➔ [ Habilidad ]
## Si la condición se cumple y la habilidad no está en recarga, se ejecuta y el ciclo reinicia.
## Si ninguna ranura se cumple o están en recarga, el Eikon ejecuta su movimiento o ataque básico.

const COND_ALWAYS := "always"
const COND_OWNER_HP_50 := "owner_hp_lt_50"
const COND_OWNER_HP_30 := "owner_hp_lt_30"
const COND_ENEMY_HP_35 := "enemy_hp_lt_35"
const COND_ENEMY_CHARGING := "enemy_charging"
const COND_ENEMY_DIST_FAR := "enemy_dist_gt_8m"
const COND_ENEMY_DIST_NEAR := "enemy_dist_lt_3m"

const CONDITIONS := {
	COND_ALWAYS: "Siempre (por recarga)",
	COND_OWNER_HP_50: "Dueño: Vida < 50%",
	COND_OWNER_HP_30: "Dueño: Vida < 30%",
	COND_ENEMY_HP_35: "Rival: Vida < 35%",
	COND_ENEMY_CHARGING: "Rival: Cargando ataque",
	COND_ENEMY_DIST_FAR: "Rival: Lejos (> 8m)",
	COND_ENEMY_DIST_NEAR: "Rival: Cerca (< 3m)",
}

const COND_ORDER := [
	COND_OWNER_HP_50,
	COND_OWNER_HP_30,
	COND_ENEMY_HP_35,
	COND_ENEMY_CHARGING,
	COND_ENEMY_DIST_FAR,
	COND_ENEMY_DIST_NEAR,
	COND_ALWAYS,
]

const ACT_BASIC := "basic"
const ACT_SPECIAL := "special"
const ACT_SHIELD := "shield"
const ACT_DISRUPT := "disrupt"
const ACT_LEAP := "leap"

const ACTIONS := {
	ACT_BASIC: {"name": "Ataque básico", "cd": 1.0, "desc": "Ataque regular del eikon."},
	ACT_SPECIAL: {"name": "Ataque Especial", "cd": 4.5, "desc": "Habilidad icónica propia (Llamarada, Colmillo, etc.)."},
	ACT_SHIELD: {"name": "Escudo Protector", "cd": 12.0, "desc": "Otorga protección temporal al dueño."},
	ACT_DISRUPT: {"name": "Rugido Disruptor", "cd": 7.0, "desc": "Onda de choque que interrumpe ataques del rival."},
	ACT_LEAP: {"name": "Embestida / Remate", "cd": 5.0, "desc": "Cierre veloz de distancia con daño adicional."},
}

const ACT_ORDER := [
	ACT_BASIC,
	ACT_SPECIAL,
	ACT_SHIELD,
	ACT_DISRUPT,
	ACT_LEAP,
]

const MAX_SLOTS := 3

static func condition_name(cond_id: String) -> String:
	return String(CONDITIONS.get(cond_id, "Siempre (por recarga)"))

static func action_name(act_id: String) -> String:
	var a: Variant = ACTIONS.get(act_id, null)
	return String((a as Dictionary).get("name", act_id)) if a is Dictionary else "Ataque básico"

static func default_for(eikon_id: String) -> Array:
	match eikon_id:
		"fenix":
			return [
				{"cond": COND_OWNER_HP_50, "act": ACT_SHIELD},
				{"cond": COND_ENEMY_HP_35, "act": ACT_SPECIAL},
				{"cond": COND_ALWAYS, "act": ACT_BASIC},
			]
		"lobo":
			return [
				{"cond": COND_ENEMY_CHARGING, "act": ACT_DISRUPT},
				{"cond": COND_ENEMY_HP_35, "act": ACT_SPECIAL},
				{"cond": COND_ALWAYS, "act": ACT_LEAP},
			]
		"golem":
			return [
				{"cond": COND_OWNER_HP_50, "act": ACT_SHIELD},
				{"cond": COND_ENEMY_DIST_NEAR, "act": ACT_DISRUPT},
				{"cond": COND_ALWAYS, "act": ACT_BASIC},
			]
		"grifo":
			return [
				{"cond": COND_ENEMY_DIST_FAR, "act": ACT_SPECIAL},
				{"cond": COND_ENEMY_CHARGING, "act": ACT_DISRUPT},
				{"cond": COND_ALWAYS, "act": ACT_BASIC},
			]
		_:
			return [
				{"cond": COND_OWNER_HP_50, "act": ACT_SHIELD},
				{"cond": COND_ENEMY_HP_35, "act": ACT_SPECIAL},
				{"cond": COND_ALWAYS, "act": ACT_BASIC},
			]

## Valida y normaliza la lista de gambits garantizando 3 ranuras coherentes.
static func sanitize(list: Array, eikon_id: String = "fenix") -> Array:
	var defaults := default_for(eikon_id)
	var out: Array = []
	for i in MAX_SLOTS:
		var row: Dictionary = {}
		if i < list.size() and list[i] is Dictionary:
			var r: Dictionary = list[i]
			var c := String(r.get("cond", ""))
			var a := String(r.get("act", ""))
			row["cond"] = c if CONDITIONS.has(c) else String(defaults[i]["cond"])
			row["act"] = a if ACTIONS.has(a) else String(defaults[i]["act"])
		else:
			row = (defaults[i] as Dictionary).duplicate()
		out.append(row)
	return out

## Código numérico de condición para la simulación determinsita.
static func cond_to_int(cond: String) -> int:
	match cond:
		COND_ALWAYS: return 0
		COND_OWNER_HP_50: return 1
		COND_OWNER_HP_30: return 2
		COND_ENEMY_HP_35: return 3
		COND_ENEMY_CHARGING: return 4
		COND_ENEMY_DIST_FAR: return 5
		COND_ENEMY_DIST_NEAR: return 6
		_: return 0

## Código numérico de acción para la simulación determinsita.
static func act_to_int(act: String) -> int:
	match act:
		ACT_BASIC: return 0
		ACT_SPECIAL: return 1
		ACT_SHIELD: return 2
		ACT_DISRUPT: return 3
		ACT_LEAP: return 4
		_: return 0
