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
