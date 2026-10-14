class_name Attributes
## Ronda 18: atributos del personaje (inspirados en el sistema de 8 atributos de los «soulslike»,
## con nombres y fórmulas propias). Cada atributo da rendimientos decrecientes por tramos
## (umbrales blandos). Todos los bonos son RELATIVOS al reparto inicial del rol: a nivel 1
## el luchador es idéntico al de antes (equilibrio de la ronda 17).

const KEYS := ["vitalidad", "concentracion", "aguante", "fuerza", "destreza", "sabiduria", "devocion", "vinculo"]
const NAMES := {"vitalidad": "Vitalidad", "concentracion": "Concentración", "aguante": "Aguante", "fuerza": "Fuerza",
	"destreza": "Destreza", "sabiduria": "Sabiduría", "devocion": "Devoción", "vinculo": "Vínculo"}
const SHORT := {"vitalidad": "VIT", "concentracion": "CON", "aguante": "AGU", "fuerza": "FUE",
	"destreza": "DES", "sabiduria": "SAB", "devocion": "DEV", "vinculo": "VIN"}
const DESC := {
	"vitalidad": "Vida máxima, Defensa e Inmunidad.",
	"concentracion": "Energía máxima y su regeneración (Golpe sísmico) y la resistencia Concentración.",
	"aguante": "Estamina, equilibrio (poise), carga y robustez: menos aturdimiento recibido, guardia más firme.",
	"fuerza": "Daño de armas de Fuerza, daño al equilibrio y a la guardia, y aturdimiento infligido.",
	"destreza": "Daño de armas de Destreza, velocidad de ataque y disparo, voltereta más barata y con más invulnerabilidad.",
	"sabiduria": "Poder mágico (para futuros hechizos).",
	"devocion": "Curación, resistencia sagrada (eikons y áreas) y daño sagrado de armas con Devoción.",
	"vinculo": "Afinidad con el eikon: su daño y su vida, ganancia del medidor y la resistencia Vitalidad.",
}
const MIN_VALUE := 6
const MAX_VALUE := 60
const POINTS_PER_LEVEL := 2

## Reparto inicial por rol (suma 80).
const START := {
	"caballero": {"vitalidad": 12, "concentracion": 10, "aguante": 12, "fuerza": 12, "destreza": 10, "sabiduria": 8, "devocion": 8, "vinculo": 8},
	"arquero": {"vitalidad": 9, "concentracion": 10, "aguante": 11, "fuerza": 8, "destreza": 16, "sabiduria": 9, "devocion": 7, "vinculo": 10},
	"berserker": {"vitalidad": 13, "concentracion": 9, "aguante": 11, "fuerza": 16, "destreza": 8, "sabiduria": 7, "devocion": 7, "vinculo": 9},
	"paladin": {"vitalidad": 13, "concentracion": 10, "aguante": 10, "fuerza": 11, "destreza": 8, "sabiduria": 7, "devocion": 14, "vinculo": 7},
	"asesino": {"vitalidad": 9, "concentracion": 10, "aguante": 10, "fuerza": 8, "destreza": 16, "sabiduria": 10, "devocion": 7, "vinculo": 10},
}
## Prioridad de reparto automático (migración y rival): se reparte en este ciclo.
const AUTO := {
	"caballero": ["vitalidad", "fuerza", "aguante", "destreza", "vitalidad", "fuerza", "aguante", "concentracion"],
	"arquero": ["destreza", "aguante", "destreza", "vitalidad", "destreza", "vinculo", "aguante", "vitalidad"],
	"berserker": ["fuerza", "vitalidad", "fuerza", "aguante", "fuerza", "concentracion", "vitalidad", "aguante"],
	"paladin": ["devocion", "vitalidad", "fuerza", "devocion", "vitalidad", "aguante", "devocion", "vitalidad"],
	"asesino": ["destreza", "aguante", "destreza", "vitalidad", "destreza", "vinculo", "destreza", "aguante"],
}

## Curvas por tramos: [[hasta, ganancia por punto], ...] (el último tramo continúa).
const CURVES := {
	"vida": [[25, 4.0], [40, 2.0], [60, 0.6]],          # Vitalidad
	"defensa": [[30, 0.004], [50, 0.0015], [60, 0.0005]], # Vitalidad (fracción de daño físico)
	"estamina": [[25, 2.5], [40, 1.2], [60, 0.4]],       # Aguante
	"poise": [[30, 1.5], [50, 0.6], [60, 0.2]],          # Aguante
	"robustez": [[30, 0.012], [50, 0.005], [60, 0.002]], # Aguante (menos aturdimiento recibido)
	"guardia": [[30, 0.008], [50, 0.003], [60, 0.001]],  # Aguante (menos aguante al bloquear)
	"carga": [[25, 1.6], [60, 1.0], [99, 0.5]],          # Aguante (solo informativo)
	"energia": [[25, 3.0], [40, 1.5], [60, 0.5]],        # Concentración
	"energia_regen": [[30, 0.25], [50, 0.1], [60, 0.03]],# Concentración
	"escala": [[20, 0.02], [40, 0.01], [60, 0.004]],     # Fuerza/Destreza/Sabiduría/Devoción (daño de arma)
	"impacto": [[30, 0.015], [50, 0.006], [60, 0.002]],  # Fuerza: equilibrio/guardia
	"aturdir": [[30, 0.01], [50, 0.004], [60, 0.001]],   # Fuerza: aturdimiento infligido
	"velocidad": [[25, 0.008], [40, 0.005], [60, 0.003]],# Destreza (r31: tope +25 %, cuesta más)
	"voltereta": [[30, 0.008], [50, 0.003], [60, 0.001]],# Destreza: coste de voltereta
	"iframes": [[30, 0.07], [50, 0.03], [60, 0.01]],     # Destreza: frames (a 30 fps) de invulnerabilidad
	"magia": [[30, 4.0], [50, 2.0], [60, 0.5]],          # Sabiduría
	"curacion": [[25, 0.03], [40, 0.012], [60, 0.004]],  # Devoción
	"sagrado": [[30, 0.005], [50, 0.002], [60, 0.0005]], # Devoción (resistencia a eikon/área)
	"eikon": [[25, 0.02], [40, 0.008], [60, 0.003]],     # Vínculo: daño y vida del eikon
	"medidor": [[25, 0.015], [40, 0.006], [60, 0.002]],  # Vínculo: ganancia de medidor
}

## Integral de la curva desde 0 hasta v.
static func curve(name: String, v: float) -> float:
	var segs: Array = CURVES[name]
	var total := 0.0
	var prev := 0.0
	for s: Array in segs:
		var top: float = s[0]
		if v <= prev:
			break
		total += (minf(v, top) - prev) * float(s[1])
		prev = top
	if v > prev:
		total += (v - prev) * float(segs[-1][1])
	return total

## Ganancia relativa al reparto inicial (0 a nivel 1).
static func rel(name: String, cur: float, start: float) -> float:
	return curve(name, cur) - curve(name, start)

static func start_for(char_id: String) -> Dictionary:
	return (START.get(char_id, START["caballero"]) as Dictionary).duplicate()

static func total(a: Dictionary) -> int:
	var t := 0
	for k in KEYS:
		t += int(a.get(k, 0))
	return t

static func points_for_level(lv: int) -> int:
	return maxi(lv - 1, 0) * POINTS_PER_LEVEL

## Puntos sin gastar de un reparto a un nivel.
static func free_points(char_id: String, a: Dictionary, lv: int) -> int:
	return points_for_level(lv) - (total(a) - total(start_for(char_id)))

## ¿Reparto válido (no baja del inicial ni pasa del máximo ni de los puntos)?
static func valid(char_id: String, a: Dictionary, lv: int) -> bool:
	var s := start_for(char_id)
	for k in KEYS:
		var v := int(a.get(k, -1))
		if v < int(s[k]) or v > MAX_VALUE:
			return false
	return free_points(char_id, a, lv) >= 0

## Reparto automático por rol para un nivel (migración v5 y rival).
static func auto_allocate(char_id: String, lv: int) -> Dictionary:
	var a := start_for(char_id)
	var order: Array = AUTO.get(char_id, AUTO["caballero"])
	var n := points_for_level(lv)
	var i := 0
	var guard := 0
	while n > 0 and guard < 1000:
		var k: String = order[i % order.size()]
		i += 1
		guard += 1
		if int(a[k]) < MAX_VALUE:
			a[k] = int(a[k]) + 1
			n -= 1
	return a

## Estadísticas derivadas (bonos relativos al reparto inicial del rol).
static func derived(char_id: String, a: Dictionary) -> Dictionary:
	var s := start_for(char_id)
	var g := func(k: String) -> float: return float(a.get(k, s[k]))
	var vit: float = g.call("vitalidad")
	var con: float = g.call("concentracion")
	var agu: float = g.call("aguante")
	var fue: float = g.call("fuerza")
	var des: float = g.call("destreza")
	var sab: float = g.call("sabiduria")
	var dev: float = g.call("devocion")
	var vin: float = g.call("vinculo")
	return {
		"vida": rel("vida", vit, s["vitalidad"]),
		"defensa": clampf(rel("defensa", vit, s["vitalidad"]), -0.1, 0.15),
		"estamina": rel("estamina", agu, s["aguante"]),
		"poise": rel("poise", agu, s["aguante"]),
		"stun_taken": clampf(1.0 - rel("robustez", agu, s["aguante"]), 0.6, 1.2),
		"guard_k": clampf(1.0 - rel("guardia", agu, s["aguante"]), 0.75, 1.15),
		"carga": 30.0 + curve("carga", agu),
		"energia_max": 50.0 + rel("energia", con, s["concentracion"]),
		"energia_regen": maxf(5.0 + rel("energia_regen", con, s["concentracion"]), 2.0),
		"impacto": clampf(1.0 + rel("impacto", fue, s["fuerza"]), 0.85, 1.5),
		"stun_dealt": clampf(1.0 + rel("aturdir", fue, s["fuerza"]), 0.9, 1.35),
		"vel": clampf(1.0 + rel("velocidad", des, s["destreza"]), 0.95, 1.25),
		"roll_cost": clampf(1.0 - rel("voltereta", des, s["destreza"]), 0.75, 1.1),
		"iframes": clampi(int(round(rel("iframes", des, s["destreza"]))), 0, 2),
		"magia": 100.0 + rel("magia", sab, s["sabiduria"]),
		"curacion": clampf(1.0 + rel("curacion", dev, s["devocion"]), 0.8, 1.8),
		"sagrado": clampf(rel("sagrado", dev, s["devocion"]), -0.05, 0.15),
		"eikon": clampf(1.0 + rel("eikon", vin, s["vinculo"]), 0.85, 1.7),
		"medidor": clampf(1.0 + rel("medidor", vin, s["vinculo"]), 0.9, 1.5),
	}

# ---------------- Escalado de armas ----------------
const SCALE_KEYS := ["fuerza", "destreza", "sabiduria", "devocion"]
const UNDER_REQ_MULT := 0.7 ## por debajo del requisito: −30 % de daño

static func grade(c: float) -> String:
	if c <= 0.0: return "-"
	if c > 1.7: return "S"
	if c >= 1.3: return "A"
	if c >= 0.9: return "B"
	if c >= 0.55: return "C"
	if c >= 0.25: return "D"
	return "E"

static func _sc(w: WeaponDef, a: Dictionary) -> float:
	var t := 0.0
	for k: String in SCALE_KEYS:
		t += w.scaling.get(k, 0.0) * curve("escala", float(a.get(k, 10)))
	return t

## Atributos que no llegan al requisito del arma.
static func unmet(w: WeaponDef, a: Dictionary) -> Array:
	var out: Array = []
	for k: String in w.requirements:
		if int(a.get(k, 0)) < int(w.requirements[k]):
			out.append(k)
	return out

## Multiplicador de daño del arma por atributos (1.0 con el reparto inicial del rol).
static func weapon_mult(w: WeaponDef, char_id: String, a: Dictionary, check_req: bool = true) -> float:
	var base := 1.0 + _sc(w, start_for(char_id))
	var k := (1.0 + _sc(w, a)) / base
	if check_req and not unmet(w, a).is_empty():
		k *= UNDER_REQ_MULT
	return k

## Texto «FUE B · DES D» del arma.
static func scaling_text(w: WeaponDef) -> String:
	var parts: Array = []
	for k: String in SCALE_KEYS:
		var c: float = w.scaling.get(k, 0.0)
		if c > 0.0:
			parts.append("%s %s" % [SHORT[k], grade(c)])
	return " · ".join(parts)

static func req_text(w: WeaponDef) -> String:
	var parts: Array = []
	for k: String in SCALE_KEYS:
		if w.requirements.has(k):
			parts.append("%s %d" % [SHORT[k], int(w.requirements[k])])
	return " · ".join(parts)
