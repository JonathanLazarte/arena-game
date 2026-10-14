class_name StunRules
## Ronda 31: aturdimiento ACUMULADO en 3 niveles (ver docs/design.md).
## Fuerza de un golpe = fuerza del personaje (Fuerza) + fuerza del arma + fuerza asignada al golpe.
## Habilidades mágicas: magia (Sabiduría) + fuerza asignada (por cada impacto de una ráfaga).
## Se acumula contra la ROBUSTEZ del defensor (= su equilibrio/poise, Aguante y armadura) durante
## WINDOW s desde el primer golpe recibido; al cerrarse la ventana se recupera del todo al instante.
## Ningún golpe aturde por sí solo: un impacto aporta como mucho SINGLE_HIT_CAP de la robustez.

const WINDOW := 3.0
## Umbrales (acumulado / robustez): tambaleo, aturdido, derribo.
const THRESHOLDS := [1.0, 1.6, 2.4]
const LEVEL_NAMES := ["", "Tambaleo", "Aturdido", "Derribo"]
const STAGGER_T := 0.35 ## tambaleo corto: se puede rodar para salir
const STUN_T := 0.9
const DOWN_T := 1.1 ## en el suelo
const GETUP_T := 0.8 ## levantándose (inmune al aturdimiento)
const IMMUNE_AFTER := 0.6 ## inmunidad extra tras levantarse
const GETUP_DMG_MULT := 0.85 ## daño recibido mientras dura la inmunidad tras un derribo
const SINGLE_HIT_CAP := 0.95
const HITSTUN_TO_FORCE := 40.0 ## golpes sin fuerza asignada: hitstun antiguo (s) x 40
const MAGIC_K := 0.1 ## poder mágico 100 -> 10 de fuerza
const AOE_FORCE := 40.0
const BOSS_FORCE := 60.0
const EIKON_K := 1.2 ## golpes de eikon: daño x 1,2
const COUNTER_K := 1.3 ## contraataque (golpeado mientras atacas)
## Fuerza propia de cada arma.
const WEAPON_FORCE := {"dagas": 4.0, "espada_escudo": 8.0, "espada_larga": 11.0, "lanza": 9.0, "hacha_2m": 14.0,
	"arco": 3.0, "ballesta": 6.0}
## Súper-armadura por defecto: el fuerte en su anticipación multiplica la robustez por (1 + x).
const HEAVY_RESIST := 1.0
const CHARGE_RESIST := 1.0 ## + hasta esto con la carga completa del fuerte
const DASH_JUMP_RESIST := 0.5

## Fuerza del personaje por Fuerza (rendimientos decrecientes).
static func str_force(fuerza: float) -> float:
	var segs := [[30.0, 0.6], [50.0, 0.3], [99.0, 0.1]]
	var t := 0.0
	var prev := 0.0
	for s: Array in segs:
		if fuerza <= prev:
			break
		t += (minf(fuerza, s[0]) - prev) * float(s[1])
		prev = s[0]
	return t

static func weapon_force(w: WeaponDef) -> float:
	if w == null:
		return 0.0
	if w.stun_force >= 0.0:
		return w.stun_force
	return float(WEAPON_FORCE.get(w.id, 6.0))

static func magic_force(magia: float) -> float:
	return magia * MAGIC_K

## Nivel (0..3) para una proporción acumulado/robustez.
static func level_for(ratio: float) -> int:
	var lv := 0
	for i in THRESHOLDS.size():
		if ratio >= float(THRESHOLDS[i]):
			lv = i + 1
	return lv
