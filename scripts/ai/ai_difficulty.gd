class_name AIDifficulty
extends Resource
## Perfil de dificultad de la IA (easy / normal / hard).

@export var profile_name: String = "normal"
@export var level: int = 2
## Pausa en la fase de rodeo entre enfrentamientos (s): min + randf() * extra
@export var engage_pause_min: float = 1.5
@export var engage_pause_extra: float = 1.5
## Duración del rodeo inicial y velocidad angular del rodeo
@export var orbit_speed: float = 0.7
## Golpes máximos por compromiso (cadena)
@export var max_chain: int = 3
@export var heavy_chance: float = 0.25
## Agresividad: probabilidad de entrar con dash y aguante mínimo para comprometerse
@export var dash_in_chance: float = 0.5
@export var commit_min_stamina: float = 45.0
## Probabilidad de castigar la recuperación del jugador tras esquivar/parry
@export var punish_chance: float = 1.0
@export var dodge_chance: float = 0.42
@export var parry_chance: float = 0.15
@export var block_arrow_chance: float = 0.3
## Retraso de reacción ante un ataque telegrafiado (s)
@export var reaction_time: float = 0.0
## Intervalo entre decisiones (s)
@export var think_interval: float = 0.12
## Respiros: tras un intercambio (o si lleva mucho rato presionando) se aleja, rodea a distancia,
## recupera aguante o espera quieto. Duración aleatoria entre min y max (s).
@export var breather_chance: float = 0.35
@export var breather_min: float = 2.0
@export var breather_max: float = 4.0
@export var breather_dist: float = 11.0 ## distancia a la que se queda durante el respiro
@export var breather_interval: float = 14.0 ## si no ha respirado en este tiempo, fuerza un respiro
## Ronda 14: probabilidad de saltar un golpe de área en el suelo (anillo de aviso) que le va a alcanzar.
@export var jump_aoe_chance: float = 0.6
## Ronda 16: adelanto al disparar (0 = apunta a donde está el jugador ahora). Solo el difícil
## se adelanta, y solo a medias (0,5): correr de lado a distancia sigue esquivando.
@export var aim_lead: float = 0.0
## Probabilidad (por decisión) de usar la habilidad del personaje / el especial del eikon montado.
@export var special_chance: float = 0.3
## Ronda 24: «El intercambio».
@export var guard_counter_chance: float = 0.45 ## tras bloquear, contraataca con la contra de guardia
@export var crit_chance: float = 0.85 ## aprovecha la postura rota del jugador con un crítico
@export var stance_caution: float = 0.3 ## con la postura por debajo de esto, deja de presionar
## Fase 2: golpes retrasados (espera antes de soltar el primer golpe para romper el ritmo del parry).
@export var delay_chance: float = 0.35
@export var delay_max: float = 0.45
## Ronda 25: Estocada de jefe — probabilidad de usarla (por decisión, a media distancia) y de
## esquivarla a tiempo (error de tiempo ± s; más error = esquiva antes o tarde).
@export var boss_use_chance: float = 0.03
@export var boss_dodge_chance: float = 0.6
@export var boss_dodge_err: float = 0.12
