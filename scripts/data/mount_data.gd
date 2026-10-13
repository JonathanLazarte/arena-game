class_name MountData
extends Resource
## Datos de una montura. Crea un nuevo .tres para añadir monturas (grifo, unicornio...).

@export var mount_name: String = "Caballo"
@export var speed: float = 14.0
@export var acceleration: float = 18.0
@export var turn_speed: float = 3.2 ## rad/s
@export var dash_speed: float = 30.0
@export var dash_duration: float = 0.3
@export var dash_cooldown: float = 1.5
@export var dash_iframes: float = 0.2 ## invulnerabilidad del dash/rodar
@export var sprint_multiplier: float = 1.45 ## galope (mantener Shift)
@export var max_health: float = 0.0 ## 0 = la montura no recibe daño (opcional)
@export var health_bonus: float = 0.0
@export var jump_velocity: float = 8.0 ## reservado para futuras versiones
@export var can_fly: bool = false ## reservado para futuras versiones
@export var color: Color = Color(0.45, 0.3, 0.18)
# --- Ronda 14: las monturas son eikons montables. Modelo y animaciones de cada uno. ---
@export var model_path: String = "res://assets/models/horse_quaternius.glb"
@export var model_scale: float = 0.62
@export var anim_idle: String = "Idle"
@export var anim_walk: String = "Walk"
@export var anim_gallop: String = "Gallop"
@export var tint: bool = false ## teñir el modelo con color
@export var hover: float = 0.0 ## altura de vuelo (fénix): el jinete no toca el suelo
@export var saddle_offset: Vector3 = Vector3(0, 0.25, -0.4)
