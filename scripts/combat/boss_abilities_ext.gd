class_name BossAbilitiesExt
extends RefCounted
## Ronda 32: habilidades de jefe ampliadas (diseño propio de jefes telegrafiados).
## Se consultan ANTES que BossAbilities: def(id) devuelve la definición de aquí y, si no existe,
## la de BossAbilities. Los tiempos están en segundos "de escritorio": Fighter.telegraph_k los
## alarga en móvil (windup, hits[i][0], flicker, vanish, stance, tele, warn, rise/lock/land).
##
## Tipos (los ejecuta Fighter._update_ext_ability):
##  timeline: lista de golpes hits = [[tiempo, mult_daño, fuerza_aturdimiento, velocidad_de_arremetida], ...]
##            opcionales: grab, abort_on_miss, miss_extra, grab_stun, hit_iframes, vanish, blink_dist, flicker, kind
##  wave:     onda rastrera (GroundWave): count, spread_deg, speed, range, width, warn
##  rain:     marcas de suelo en cadena (GroundAoE): mode "track" | "scatter", count, interval, radius, tele
##  breath:   cono continuo con ticks: duration, tick, range, arc, turn_deg, element
##  rage:     bufo temporal (daño, velocidad y súper-armadura; el aura roja avisa al rival)
##  counter:  postura de contragolpe: si le atacan en la ventana, no recibe daño y castiga
## Coste: cost_type "stamina" | "mana" | "health". dmg multiplica el daño fuerte del arma.
## Las fuerzas de aturdimiento son orientativas: ajústalas a la escala de StunRules.

const DEFS := {
	"tajo_retardado": {
		"tele_txt": "Hoja ámbar alzada que parpadea en blanco a mitad (el amague) antes del golpe tardío.", "name": "Tajo Retardado", "desc": "Alza el arma, finge y golpea tarde. Imparable: no rueces por reflejo.",
		"type": "timeline", "cost_type": "stamina", "cost": 24.0, "cd": 6.0,
		"dmg": 1.5, "color": Color(1.0, 0.8, 0.3), "kind": "jefe", "unblockable": true,
		"hits": [[1.25, 1.0, 40.0, 7.0]], "flicker": [0.5, 0.85],
		"reach": 3.0, "arc": 55.0, "track": 220.0, "recovery": 0.9, "resist": 0.8,
		"slam_radius": 4.5, "slam_warn": 0.35, "slam_mult": 0.65, "slam_force": 40.0, "slam_on_last": true,
	},
	"presa_verdugo": {
		"tele_txt": "Brazo extendido y brillo rojo sangre; avanza en línea recta para agarrar.", "name": "Presa del Verdugo", "desc": "Agarre imparable. Se esquiva rodando o saltando; si falla, queda expuesto.",
		"type": "timeline", "cost_type": "stamina", "cost": 28.0, "cd": 9.0,
		"dmg": 1.2, "color": Color(0.85, 0.1, 0.1), "kind": "jefe", "unblockable": true,
		"grab": true, "grab_stun": 1.1, "abort_on_miss": true, "miss_extra": 0.7,
		"hits": [[0.9, 0.35, 10.0, 9.0], [1.65, 1.4, 45.0, 0.0]],
		"reach": 2.4, "arc": 40.0, "track": 300.0, "recovery": 0.8, "resist": 0.5,
	},
	"giro_martillo": {
		"tele_txt": "Brillo naranja y el cuerpo se tuerce hacia atrás antes del barrido circular.", "name": "Giro Devastador", "desc": "Barrido de 360° con súper-armadura. Sal del alcance o rueda a través.",
		"type": "timeline", "cost_type": "stamina", "cost": 30.0, "cd": 10.0,
		"dmg": 1.3, "color": Color(1.0, 0.5, 0.1), "kind": "jefe", "unblockable": true,
		"hits": [[1.0, 1.0, 35.0, 0.0], [1.45, 1.2, 35.0, 0.0]],
		"reach": 3.6, "arc": 180.0, "track": 120.0, "recovery": 1.0, "resist": 1.5,
		"slam_radius": 4.2, "slam_warn": 0.2, "slam_mult": 0.75, "slam_force": 42.0, "slam_on_last": true,
	},
	"danza_cisne": {
		"tele_txt": "Brillo rosa y pasos de puntillas; cada tajo deja un destello.", "name": "Danza del Cisne", "desc": "Ráfaga de 6 tajos con i-frames breves. Un parry la corta; al acabar, muy castigable.",
		"type": "timeline", "cost_type": "stamina", "cost": 40.0, "cd": 14.0,
		"dmg": 0.4, "color": Color(0.95, 0.3, 0.5), "kind": "melee", "unblockable": false,
		"hit_iframes": true,
		"hits": [[0.7, 1.0, 8.0, 6.0], [1.0, 1.0, 8.0, 6.0], [1.3, 1.0, 8.0, 6.0],
			[1.6, 1.2, 10.0, 6.0], [2.0, 1.2, 10.0, 7.0], [2.6, 2.2, 30.0, 9.0]],
		"reach": 3.0, "arc": 70.0, "track": 300.0, "recovery": 1.3, "resist": 0.7,
	},
	"paso_espectral": {
		"tele_txt": "Estallido violeta y desaparece; reaparece con otro estallido a tu espalda.", "name": "Paso Espectral", "desc": "Desaparece (invulnerable), reaparece a tu espalda y golpea.",
		"type": "timeline", "cost_type": "mana", "cost": 25.0, "cd": 10.0,
		"dmg": 1.4, "color": Color(0.7, 0.4, 1.0), "kind": "jefe", "unblockable": true,
		"vanish": 0.4, "blink_dist": 2.4,
		"hits": [[1.05, 1.0, 35.0, 0.0]],
		"reach": 3.0, "arc": 60.0, "track": 360.0, "recovery": 0.9, "resist": 0.6,
	},
	"onda_rastrera": {
		"tele_txt": "Golpe al suelo naranja; las ondas muestran su trayectoria antes de avanzar.", "name": "Onda Rastrera", "desc": "Tres ondas recorren el suelo. Salta o rueda; ves su trayectoria antes.",
		"type": "wave", "cost_type": "stamina", "cost": 24.0, "cd": 7.0,
		"dmg": 0.8, "color": Color(1.0, 0.45, 0.1),
		"windup": 0.7, "count": 3, "spread_deg": 18.0, "speed": 15.0, "range": 16.0, "width": 1.8, "warn": 0.45,
		"force": 30.0, "recovery": 0.8, "resist": 0.4,
	},
	"rayos_trazadores": {
		"tele_txt": "Brillo celeste; círculos azules siguen tu posición antes de cada rayo.", "name": "Rayos Trazadores", "desc": "Marca tu posición y cae un rayo tras otro. No te quedes quieto.",
		"type": "rain", "mode": "track", "cost_type": "mana", "cost": 25.0, "cd": 11.0,
		"dmg": 0.9, "magic": true, "color": Color(0.4, 0.8, 1.0),
		"windup": 0.5, "count": 4, "interval": 0.55, "radius": 2.0, "tele": 0.8,
		"force": 30.0, "knock": 6.0, "recovery": 0.5, "resist": 0.3,
	},
	"lluvia_meteoros": {
		"tele_txt": "Brillo carmesí y marcas rojas repartidas por la zona.", "name": "Lluvia de Meteoros", "desc": "Marcas por toda la zona; cada una avisa 1 s. Lee el suelo.",
		"type": "rain", "mode": "scatter", "cost_type": "mana", "cost": 35.0, "cd": 18.0,
		"dmg": 0.8, "magic": true, "color": Color(0.85, 0.12, 0.25),
		"windup": 0.8, "count": 7, "interval": 0.22, "radius": 2.4, "tele": 1.0, "scatter_r": 7.5,
		"force": 25.0, "knock": 7.0, "recovery": 0.7, "resist": 0.3,
	},
	"aliento_dragon": {
		"tele_txt": "Brillo ígneo y cabeza echada atrás antes de soplar el cono de fuego.", "name": "Aliento de Dragón", "desc": "Cono de fuego sostenido que gira despacio. El escudo no lo aguanta: sal del cono.",
		"type": "breath", "cost_type": "mana", "cost": 30.0, "cd": 14.0,
		"dmg": 0.45, "magic": true, "color": Color(1.0, 0.4, 0.05), "element": "fuego",
		"windup": 0.7, "duration": 1.5, "tick": 0.3, "range": 7.5, "arc": 28.0, "turn_deg": 70.0,
		"force": 8.0, "recovery": 1.1, "resist": 1.0,
	},
	"furia_fase": {
		"tele_txt": "Estallido rojo y aura roja persistente.", "name": "Furia de Fase", "desc": "Pagas vida: +30 % daño, +15 % velocidad y súper-armadura 9 s. Aura roja.",
		"type": "rage", "cost_type": "health", "cost": 20.0, "cd": 30.0,
		"dmg": 0.0, "color": Color(0.9, 0.1, 0.1),
		"windup": 0.5, "duration": 9.0, "recovery": 0.3, "resist": 2.0,
	},
	"postura_contra": {
		"tele_txt": "Brillo azul acero y guardia quieta; no le ataques mientras brille.", "name": "Postura de Contragolpe", "desc": "Si le atacas en la ventana, no recibe daño y te castiga. Paciencia o esquiva.",
		"type": "counter", "cost_type": "stamina", "cost": 22.0, "cd": 8.0,
		"dmg": 1.0, "color": Color(0.4, 0.6, 1.0),
		"windup": 0.3, "stance": 1.2, "reach": 4.0, "cmult": 1.6, "cforce": 55.0,
		"recovery_hit": 0.4, "recovery_miss": 1.0, "resist": 2.0,
	},
	"embate_sismico": {
		"tele_txt": "Brillo marrón y alza el arma con ambas manos; al caer, ocho grietas salen en anillo.",
		"name": "Embate Sísmico", "desc": "Golpe al suelo que lanza ondas en las 8 direcciones. Salta o rueda entre ellas; tras el golpe queda clavado.",
		"type": "wave", "cost_type": "health", "cost": 18.0, "cd": 12.0,
		"dmg": 0.9, "color": Color(0.6, 0.4, 0.2),
		"windup": 1.1, "count": 8, "spread_deg": 45.0, "ring": true, "speed": 11.0, "range": 11.0, "width": 1.6, "warn": 0.5,
		"force": 45.0, "recovery": 1.3, "resist": 1.0,
	},
	"lanza_celeste": {
		"tele_txt": "Columna de luz blanca sobre ti que se estrecha; la lanza cae cuando desaparece.",
		"name": "Lanza Celeste", "desc": "Fija tu posición y cae una lanza de luz que aturde mucho. Muévete al ver la columna; el lanzador queda expuesto.",
		"type": "rain", "mode": "track", "cost_type": "mana", "cost": 30.0, "cd": 12.0,
		"dmg": 1.6, "magic": true, "color": Color(0.95, 0.95, 1.0), "unblockable": true,
		"windup": 0.6, "count": 1, "interval": 0.0, "radius": 1.6, "tele": 1.1,
		"force": 70.0, "knock": 9.0, "recovery": 1.4, "resist": 0.5,
	},
}

static func has(id: String) -> bool:
	return DEFS.has(id) or BossAbilities.DEFS.has(id)

static func def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return BossAbilities.def(id)

## Ids nuevos (para menús y progresión).
static func ids() -> Array:
	return DEFS.keys()
