class_name StatusFx
extends RefCounted
## Ronda 20: estados alterados con acumulación al estilo Elden Ring. Cada golpe con estado suma
## puntos a una barra; al llenarse se dispara el efecto y la barra vuelve a 0. Las barras decaen
## solas tras un momento sin acumular. Umbral = 10 + resistencia (Robustez: sangrado y congelación;
## Inmunidad: veneno). Números propios (ver README para los valores de ER citados).

const TYPES := ["sangrado", "veneno", "congelacion"]
const NAMES := {"sangrado": "Sangrado", "veneno": "Veneno", "congelacion": "Congelación"}
const COLORS := {"sangrado": Color(0.85, 0.08, 0.12), "veneno": Color(0.45, 0.8, 0.15), "congelacion": Color(0.55, 0.85, 1.0)}
const RESIST := {"sangrado": "robustez", "veneno": "inmunidad", "congelacion": "robustez"}
const BASE_THRESHOLD := 10.0 ## umbral = 10 + resistencia (≈95-110 a nivel 1)
const DECAY_DELAY := 1.5 ## s sin acumular antes de que la barra baje
const DECAY := 10.0 ## puntos/s
const PROC_LOCK := 1.5 ## s tras un estallido sin acumular ese estado
const BLEED_PCT := 0.12 ## estallido: 12 % de la vida máxima + 6
const BLEED_FLAT := 6.0
const POISON_DPS := 2.0 ## daño por segundo
const POISON_TIME := 14.0
const FROST_PCT := 0.08
const FROST_FLAT := 4.0
const FROST_TIME := 12.0 ## debilitado:
const FROST_TAKEN := 1.15 ## +15 % daño recibido
const FROST_REGEN := 0.6 ## aguante se regenera al 60 %

var buildup: Dictionary = {"sangrado": 0.0, "veneno": 0.0, "congelacion": 0.0}
var since: Dictionary = {"sangrado": 9.0, "veneno": 9.0, "congelacion": 9.0}
var lock: Dictionary = {"sangrado": 0.0, "veneno": 0.0, "congelacion": 0.0}
var procs: Dictionary = {"sangrado": 0, "veneno": 0, "congelacion": 0}
var poison_t: float = 0.0
var frost_t: float = 0.0
var poison_dealt: float = 0.0

static func threshold_for(resist_value: float) -> float:
	return BASE_THRESHOLD + resist_value

func reset() -> void:
	for k: String in TYPES:
		buildup[k] = 0.0
		since[k] = 9.0
		lock[k] = 0.0
	poison_t = 0.0
	frost_t = 0.0

func fraction(k: String, thr: float) -> float:
	return clampf(float(buildup[k]) / maxf(thr, 1.0), 0.0, 1.0)

func damage_taken_mult() -> float:
	return FROST_TAKEN if frost_t > 0.0 else 1.0

func regen_mult() -> float:
	return FROST_REGEN if frost_t > 0.0 else 1.0

## Suma acumulación; devuelve true si se llenó la barra (el llamador aplica el estallido).
func add(k: String, amount: float, thr: float) -> bool:
	if not buildup.has(k) or amount <= 0.0 or float(lock[k]) > 0.0:
		return false
	buildup[k] = float(buildup[k]) + amount
	since[k] = 0.0
	if float(buildup[k]) >= thr:
		buildup[k] = 0.0
		lock[k] = PROC_LOCK
		procs[k] = int(procs[k]) + 1
		match k:
			"veneno": poison_t = POISON_TIME
			"congelacion": frost_t = FROST_TIME
		return true
	return false

## Avanza el tiempo; devuelve el daño de veneno de este paso.
func tick(delta: float) -> float:
	for k: String in TYPES:
		since[k] = float(since[k]) + delta
		lock[k] = maxf(float(lock[k]) - delta, 0.0)
		if float(since[k]) > DECAY_DELAY:
			buildup[k] = maxf(float(buildup[k]) - DECAY * delta, 0.0)
	frost_t = maxf(frost_t - delta, 0.0)
	if poison_t > 0.0:
		poison_t = maxf(poison_t - delta, 0.0)
		poison_dealt += POISON_DPS * delta
		return POISON_DPS * delta
	return 0.0
