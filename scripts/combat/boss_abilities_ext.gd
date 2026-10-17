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
##            slam_always: el área del último golpe sale aunque el cuerpo no conecte
##  wave:     onda rastrera (GroundWave): count, spread_deg, speed, range, width, warn
##  rain:     marcas de suelo en cadena (GroundAoE): mode "track" | "scatter", count, interval, radius, tele
##            pillar: columna de luz durante el aviso
##  breath:   cono continuo con ticks: duration, tick, range, arc, turn_deg, element
##  rafaga:   tajo o orbe que persigue (mismo ejecutor que la ráfaga base; se puede reenviar al terminar)
##  rage:     bufo temporal (daño, velocidad y súper-armadura; el aura avisa al rival)
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
		"windup": 0.6, "count": 1, "interval": 0.0, "radius": 1.6, "tele": 1.1, "pillar": true,
		"force": 70.0, "knock": 9.0, "recovery": 1.4, "resist": 0.5,
	},
	# --- lote 2: patrones de jefe telegrafiados (nombres y números propios) ---
	"cuerno_embiste": {
		"tele_txt": "Se agacha con un cuerno de luz ámbar y arranca en línea recta.",
		"name": "Cuerno de Embiste", "desc": "Aviso largo y dos golpes: el primero cierra distancia, el segundo levanta. Imbloqueable. Rodá el segundo y castigá la recuperación.",
		"type": "timeline", "cost_type": "stamina", "cost": 28.0, "cd": 8.0,
		"dmg": 0.95, "color": Color(0.95, 0.72, 0.25), "kind": "jefe", "unblockable": true,
		"hits": [[1.05, 0.75, 26.0, 16.0], [1.45, 1.25, 44.0, 3.0]],
		"reach": 3.0, "arc": 48.0, "track": 160.0, "recovery": 1.05, "resist": 1.1,
	},
	"tajo_cruzado": {
		"tele_txt": "Dos destellos cruzados y una pausa antes de la estocada final.",
		"name": "Tajo Cruzado", "desc": "Dos cortes que se cruzan y una estocada. Se puede bloquear; el último golpe es el que aturde. Tras el tercero queda abierto.",
		"type": "timeline", "cost_type": "stamina", "cost": 32.0, "cd": 9.0,
		"dmg": 0.7, "color": Color(0.95, 0.9, 0.72), "kind": "melee",
		"hits": [[0.8, 1.0, 16.0, 4.0], [1.1, 1.0, 16.0, 4.0], [1.65, 1.7, 40.0, 8.0]],
		"reach": 3.1, "arc": 70.0, "track": 240.0, "recovery": 1.15, "resist": 0.6,
	},
	"zarpazo_sangre": {
		"tele_txt": "Un arco carmesí queda en el aire y estalla un instante después.",
		"name": "Zarpazo de Sangre", "desc": "Un zarpazo deja una marca que explota. Bloqueá el corte y salí del círculo antes del estallido, o rodá los dos.",
		"type": "timeline", "cost_type": "mana", "cost": 26.0, "cd": 8.0,
		"dmg": 0.85, "magic": true, "color": Color(0.78, 0.06, 0.12), "kind": "melee",
		"hits": [[0.75, 0.8, 14.0, 3.0], [1.35, 1.15, 36.0, 0.0]],
		"reach": 3.2, "arc": 60.0, "track": 200.0, "recovery": 0.95, "resist": 0.4,
		"slam_radius": 3.2, "slam_warn": 0.3, "slam_mult": 0.8, "slam_force": 32.0, "slam_on_last": true,
	},
	"barrido_cola": {
		"tele_txt": "El cuerpo se tuerce y un arco bajo recorre casi todo el alrededor.",
		"name": "Barrido de Cola", "desc": "Dos barridos muy anchos y lentos. Saltá o rodá hacia adentro; bloquearlos gasta mucho aguante. Al terminar, queda de espaldas.",
		"type": "timeline", "cost_type": "stamina", "cost": 26.0, "cd": 8.0,
		"dmg": 1.1, "color": Color(0.55, 0.42, 0.28), "kind": "melee",
		"hits": [[1.15, 1.0, 34.0, 0.0], [1.75, 1.1, 30.0, 2.0]],
		"reach": 4.4, "arc": 170.0, "track": 80.0, "recovery": 1.15, "resist": 0.9,
	},
	"daga_sagrada": {
		"tele_txt": "Una daga de luz sale primero; el brillo blanco del amague avisa el salto.",
		"name": "Daga Sagrada", "desc": "Un pinchazo corto y, tras el amague, una estocada que persigue. Imbloqueable. No rueces el primero: esperá el destello blanco.",
		"type": "timeline", "cost_type": "stamina", "cost": 24.0, "cd": 7.0,
		"dmg": 1.15, "color": Color(0.95, 0.86, 0.45), "kind": "jefe", "unblockable": true,
		"hits": [[0.55, 0.35, 8.0, 0.0], [1.4, 1.45, 46.0, 12.0]], "flicker": [0.45, 0.85],
		"reach": 3.2, "arc": 45.0, "track": 260.0, "recovery": 1.0, "resist": 0.7,
	},
	"estocada_negra": {
		"tele_txt": "La hoja se vuelve negra y roja y retrocede antes de clavarse.",
		"name": "Estocada Negra", "desc": "Una sola estocada larga, imbloqueable y con mucho aturdimiento. El aviso dura más de un segundo. Rodá hacia el costado y castigá.",
		"type": "timeline", "cost_type": "mana", "cost": 28.0, "cd": 10.0,
		"dmg": 1.55, "color": Color(0.42, 0.05, 0.08), "kind": "jefe", "unblockable": true,
		"hits": [[1.25, 1.0, 52.0, 11.0]],
		"reach": 4.2, "arc": 32.0, "track": 140.0, "recovery": 1.25, "resist": 0.8,
	},
	"flor_umbral": {
		"tele_txt": "Se eleva envuelto en pétalos oscuros; el círculo del suelo es el lugar de la flor.",
		"name": "Flor Umbral", "desc": "Paga vida, se lanza y hace florecer un área grande aunque el cuerpo no te toque. Corré en lateral en cuanto veas el círculo. Queda clavado al brotar.",
		"type": "timeline", "cost_type": "health", "cost": 16.0, "cd": 16.0,
		"dmg": 1.2, "color": Color(0.82, 0.12, 0.38), "kind": "jefe", "unblockable": true,
		"hits": [[1.7, 1.0, 38.0, 9.0]],
		"reach": 3.0, "arc": 80.0, "track": 200.0, "recovery": 1.45, "resist": 1.2,
		"slam_radius": 5.2, "slam_warn": 0.45, "slam_mult": 0.85, "slam_force": 36.0, "slam_on_last": true, "slam_always": true,
	},
	"presa_fauces": {
		"tele_txt": "Abre las fauces con brillo cobre y avanza para morder.",
		"name": "Presa de Fauces", "desc": "Mordisco imparable. Si conecta, te sujeta y remata. Si falla, se queda expuesto más tiempo. Rodá o saltá el avance.",
		"type": "timeline", "cost_type": "stamina", "cost": 26.0, "cd": 10.0,
		"dmg": 1.15, "color": Color(0.72, 0.28, 0.14), "kind": "jefe", "unblockable": true,
		"grab": true, "grab_stun": 1.25, "abort_on_miss": true, "miss_extra": 0.75,
		"hits": [[0.8, 0.3, 8.0, 7.0], [1.45, 1.45, 48.0, 0.0]],
		"reach": 2.3, "arc": 36.0, "track": 220.0, "recovery": 0.85, "resist": 0.5,
	},
	"giro_noble": {
		"tele_txt": "Se enrosca en una rueda gris y sale disparado hacia vos.",
		"name": "Rueda Noble", "desc": "Embestida rápida que gira para seguirte. Imbloqueable. Rodá a través cuando arranque; la recuperación es larga.",
		"type": "timeline", "cost_type": "stamina", "cost": 22.0, "cd": 7.0,
		"dmg": 1.05, "color": Color(0.55, 0.55, 0.62), "kind": "jefe", "unblockable": true,
		"hits": [[0.95, 1.0, 30.0, 18.0]],
		"reach": 2.5, "arc": 50.0, "track": 360.0, "recovery": 1.2, "resist": 1.4,
	},
	"danza_triple": {
		"tele_txt": "Se queda en puntas y el arma brilla en tres pulsos antes de cada ráfaga.",
		"name": "Danza Triple", "desc": "Tres ráfagas que cierran distancia y un remate. Imbloqueable, con un instante invulnerable en cada tajo. Corré hacia afuera en el primer pulso; al acabar está agotado.",
		"type": "timeline", "cost_type": "stamina", "cost": 42.0, "cd": 14.0,
		"dmg": 0.42, "color": Color(0.92, 0.72, 0.84), "kind": "jefe", "unblockable": true,
		"hit_iframes": true,
		"hits": [[0.85, 1.0, 8.0, 13.0], [1.2, 1.1, 10.0, 9.0], [1.55, 1.1, 10.0, 6.0], [2.15, 1.8, 26.0, 11.0]],
		"reach": 3.2, "arc": 80.0, "track": 320.0, "recovery": 1.4, "resist": 0.8,
	},
	"alas_picado": {
		"tele_txt": "Un par de alas de luz se abren; al plegarse, cae en picado.",
		"name": "Picado de Alas", "desc": "Se lanza desde arriba y golpea el suelo aunque no te alcance el cuerpo. El círculo aparece antes del impacto. Esquivá y pegá mientras se levanta.",
		"type": "timeline", "cost_type": "stamina", "cost": 30.0, "cd": 11.0,
		"dmg": 1.25, "color": Color(0.85, 0.68, 0.32), "kind": "jefe", "unblockable": true,
		"hits": [[1.35, 1.0, 46.0, 13.0]],
		"reach": 3.0, "arc": 55.0, "track": 180.0, "recovery": 1.15, "resist": 1.3,
		"slam_radius": 3.8, "slam_warn": 0.3, "slam_mult": 0.7, "slam_force": 40.0, "slam_on_last": true, "slam_always": true,
	},
	"garra_suelo": {
		"tele_txt": "Clava la mano en el suelo; una grieta ancha avanza hacia vos.",
		"name": "Garra de Suelo", "desc": "Una sola onda ancha y lenta. Saltala o rodá de costado. No persigue: la dirección queda fija al soltarse.",
		"type": "wave", "cost_type": "stamina", "cost": 24.0, "cd": 7.0,
		"dmg": 0.95, "color": Color(0.62, 0.5, 0.36),
		"windup": 0.85, "count": 1, "spread_deg": 0.0, "speed": 13.0, "range": 15.0, "width": 2.6, "warn": 0.5,
		"force": 48.0, "recovery": 0.9, "resist": 0.5,
	},
	"vendaval_hacha": {
		"tele_txt": "El hacha gira y suelta dos cortes de viento pálido.",
		"name": "Vendaval de Hacha", "desc": "Dos ondas rápidas en abanico estrecho. La línea del suelo muestra por dónde pasan. Rodá entre ellas o saltá.",
		"type": "wave", "cost_type": "stamina", "cost": 28.0, "cd": 9.0,
		"dmg": 0.75, "color": Color(0.7, 0.86, 0.95),
		"windup": 0.8, "count": 2, "spread_deg": 10.0, "speed": 17.0, "range": 17.0, "width": 2.0, "warn": 0.4,
		"force": 28.0, "recovery": 0.95, "resist": 0.6,
	},
	"anillo_fuego": {
		"tele_txt": "Un anillo violeta se enciende a sus pies y ocho llamaradas salen en todas direcciones.",
		"name": "Anillo de Fuego", "desc": "Ocho ondas cortas en círculo. Saltá en el momento del aviso o quedate pegado a su cuerpo, entre dos llamaradas. Después queda quieto.",
		"type": "wave", "cost_type": "mana", "cost": 30.0, "cd": 12.0,
		"dmg": 0.7, "color": Color(0.55, 0.22, 0.85),
		"windup": 1.0, "count": 8, "spread_deg": 45.0, "ring": true, "speed": 7.5, "range": 6.5, "width": 1.3, "warn": 0.55,
		"force": 22.0, "recovery": 1.05, "resist": 0.4,
	},
	"pisoton": {
		"tele_txt": "Levanta un pie con brillo ocre; al bajar, una onda baja y ancha sale al frente.",
		"name": "Pisotón", "desc": "Onda corta, muy ancha y con mucho aturdimiento. Saltala: es baja. El que la usa no se mueve y se puede interrumpir si le pegás antes.",
		"type": "wave", "cost_type": "stamina", "cost": 20.0, "cd": 6.0,
		"dmg": 0.85, "color": Color(0.74, 0.52, 0.26),
		"windup": 0.7, "count": 1, "spread_deg": 0.0, "speed": 10.0, "range": 9.0, "width": 4.2, "warn": 0.4,
		"force": 55.0, "recovery": 0.8, "resist": 0.8,
	},
	"lluvia_lanzas": {
		"tele_txt": "Cinco columnas doradas siguen tu posición, una detrás de otra.",
		"name": "Lluvia de Lanzas", "desc": "Cinco lanzas que marcan donde estás parado. No te quedes a intercambiar: cada una avisa antes de caer. El escudo aguanta una, no la seguidilla.",
		"type": "rain", "mode": "track", "cost_type": "mana", "cost": 28.0, "cd": 11.0,
		"dmg": 0.8, "magic": true, "color": Color(0.95, 0.88, 0.5), "pillar": true,
		"windup": 0.5, "count": 5, "interval": 0.42, "radius": 1.35, "tele": 0.75,
		"force": 32.0, "knock": 6.0, "recovery": 0.65, "resist": 0.3,
	},
	"flecha_grave": {
		"tele_txt": "Un círculo violeta grande se clava en el suelo bajo tus pies y se llena despacio.",
		"name": "Flecha Grave", "desc": "Una sola marca grande e imbloqueable, con aviso largo. En cuanto aparezca, rodá hacia afuera: no camines, el radio es ancho.",
		"type": "rain", "mode": "track", "cost_type": "mana", "cost": 24.0, "cd": 8.0,
		"dmg": 1.35, "magic": true, "color": Color(0.48, 0.28, 0.72), "unblockable": true,
		"windup": 0.7, "count": 1, "interval": 0.0, "radius": 2.6, "tele": 1.25,
		"force": 58.0, "knock": 11.0, "recovery": 0.9, "resist": 0.3,
	},
	"lluvia_sangre": {
		"tele_txt": "Alza la mano y llueven gotas carmesí: varias marcas chicas alrededor tuyo.",
		"name": "Lluvia de Sangre", "desc": "Seis charcos repartidos cerca de tu posición. Cada uno avisa poco. Leé el suelo y no ruedes siempre al mismo lado.",
		"type": "rain", "mode": "scatter", "cost_type": "mana", "cost": 32.0, "cd": 12.0,
		"dmg": 0.7, "magic": true, "color": Color(0.8, 0.08, 0.14),
		"windup": 0.65, "count": 6, "interval": 0.16, "radius": 1.7, "tele": 0.7, "scatter_r": 5.0,
		"force": 20.0, "knock": 4.0, "recovery": 0.75, "resist": 0.3,
	},
	"columnas_rayo": {
		"tele_txt": "Tres columnas celestes caen donde estabas, con una pausa entre cada una.",
		"name": "Columnas de Rayo", "desc": "Tres rayos que siguen tu sitio, más separados que la lluvia de lanzas. Movete al ver la columna: cuando se estrecha, ya cae.",
		"type": "rain", "mode": "track", "cost_type": "mana", "cost": 34.0, "cd": 13.0,
		"dmg": 1.05, "magic": true, "color": Color(0.62, 0.8, 1.0), "pillar": true,
		"windup": 0.55, "count": 3, "interval": 0.7, "radius": 2.1, "tele": 0.95,
		"force": 40.0, "knock": 8.0, "recovery": 0.85, "resist": 0.4,
	},
	"saeta_oscura": {
		"tele_txt": "La hoja suelta un tajo negro y rojo que curva hacia vos.",
		"name": "Saeta Oscura", "desc": "Un tajo que persigue despacio. El escudo deja pasar la mitad; la voltereta lo esquiva y el tajo sigue de largo. Podés lanzar otro al terminar, pagando de nuevo.",
		"type": "rafaga", "cost_type": "mana", "cost": 18.0, "cd": 6.0,
		"dmg": 0.9, "color": Color(0.55, 0.08, 0.12),
		"windup": 0.42, "count": 1, "speed": 16.0, "life": 2.2, "home_deg": 48.0, "home_pitch_deg": 14.0, "home_time": 1.6, "radius": 0.85, "recovery": 0.5,
		"force": 34.0, "resist": 0.3,
	},
	"orbe_lunar": {
		"tele_txt": "Un orbe pálido nace delante del arma y avanza girando muy poco.",
		"name": "Orbe Lunar", "desc": "Proyectil grande y lento, casi recto. Rodealo caminando; si estás encima, rodá. Duele más que la saeta y tarda en salir.",
		"type": "rafaga", "cost_type": "mana", "cost": 30.0, "cd": 10.0,
		"dmg": 1.25, "magic": true, "color": Color(0.75, 0.82, 1.0),
		"windup": 0.7, "count": 1, "speed": 11.0, "life": 3.0, "home_deg": 22.0, "home_pitch_deg": 8.0, "home_time": 2.2, "radius": 1.05, "recovery": 0.8,
		"force": 40.0, "resist": 0.4,
	},
	"aliento_rayo": {
		"tele_txt": "Echa la cabeza atrás con chispas celestes y sopla un cono fino.",
		"name": "Aliento de Rayo", "desc": "Cono estrecho y largo de rayo. El escudo no lo aguanta entero: salí por el costado. Gira despacio, así que un paso lateral alcanza.",
		"type": "breath", "cost_type": "mana", "cost": 32.0, "cd": 13.0,
		"dmg": 0.4, "magic": true, "color": Color(0.55, 0.78, 1.0), "element": "rayo",
		"windup": 0.75, "duration": 1.2, "tick": 0.25, "range": 9.0, "arc": 18.0, "turn_deg": 40.0,
		"force": 10.0, "recovery": 1.15, "resist": 0.8,
	},
	"aliento_escarcha": {
		"tele_txt": "Una niebla blanca le sale de la boca antes del soplido ancho.",
		"name": "Aliento de Escarcha", "desc": "Cono corto y ancho de hielo. No sirve un pasito: hay que salir del arco o ponerse a su espalda. Al cortar el soplo queda expuesto.",
		"type": "breath", "cost_type": "mana", "cost": 28.0, "cd": 12.0,
		"dmg": 0.38, "magic": true, "color": Color(0.72, 0.9, 1.0), "element": "hielo",
		"windup": 0.6, "duration": 1.3, "tick": 0.3, "range": 6.5, "arc": 42.0, "turn_deg": 50.0,
		"force": 8.0, "recovery": 1.0, "resist": 0.7,
	},
	"chorro_lava": {
		"tele_txt": "El suelo delante de él se pone naranja y luego brota un chorro bajo.",
		"name": "Chorro de Lava", "desc": "Cono corto, denso y lento de fuego. Duele por tick si te quedás. Saltá no sirve: es un cono a la altura del pecho. Rodá afuera.",
		"type": "breath", "cost_type": "mana", "cost": 34.0, "cd": 14.0,
		"dmg": 0.5, "magic": true, "color": Color(1.0, 0.38, 0.08), "element": "fuego",
		"windup": 0.8, "duration": 1.6, "tick": 0.28, "range": 5.5, "arc": 36.0, "turn_deg": 35.0,
		"force": 12.0, "recovery": 1.2, "resist": 1.0,
	},
	"grito_guerra": {
		"tele_txt": "Alza los brazos y un aura naranja lo envuelve al rugir.",
		"name": "Grito de Guerra", "desc": "Paga aguante: durante 5,5 s gana +30 % de daño, +15 % de velocidad y súper-armadura. Más corto que la Furia y no cuesta vida. El aura avisa: no intercambies de frente.",
		"type": "rage", "cost_type": "stamina", "cost": 26.0, "cd": 22.0,
		"dmg": 0.0, "color": Color(0.92, 0.55, 0.16),
		"windup": 0.55, "duration": 5.5, "recovery": 0.4, "resist": 1.5,
	},
	"guardia_reflejo": {
		"tele_txt": "Se queda quieto con un filo plateado. Si le pegás mientras brilla, devuelve el golpe.",
		"name": "Guardia Refleja", "desc": "Ventana más larga que la Postura y alcance más corto. Si le atacás, no recibe el golpe y castiga fuerte. Si no le pegás, la recuperación es larga: esperá o rodá el castigo.",
		"type": "counter", "cost_type": "stamina", "cost": 20.0, "cd": 9.0,
		"dmg": 1.0, "color": Color(0.72, 0.86, 1.0),
		"windup": 0.25, "stance": 1.6, "reach": 3.2, "cmult": 1.9, "cforce": 62.0,
		"recovery_hit": 0.35, "recovery_miss": 1.15, "resist": 2.0,
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
