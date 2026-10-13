class_name EikonData
extends Resource
## Datos de un eikon (invocación). Crea un nuevo .tres para añadir eikons.

enum AttackKind { MELEE, RANGED, AREA }

@export var eikon_name: String = "Eikon"
@export var color: Color = Color.WHITE
@export var max_health: float = 60.0
@export var duration: float = 15.0
@export var move_speed: float = 10.0
@export var attack_kind: AttackKind = AttackKind.MELEE
@export var attack_damage: float = 6.0
@export var attack_range: float = 2.5
@export var attack_cooldown: float = 1.0
@export var size: float = 1.0
@export var flying: bool = false
# --- Ronda 14: eikons = monturas ---
@export var id: String = ""
## Montable: al invocarlo aparece ensillado y el dueño monta (F baja/sube). Si no,
## es un compañero con IA que lucha a pie a tu lado durante `duration`.
@export var rideable: bool = false
@export var ride: MountData ## estadísticas al montarlo
## Ataque especial montado (tecla E / botón Eikon mientras lo montas): "llamarada", "colmillo", "vendaval".
@export var special_id: String = ""
@export var special_name: String = ""
@export var special_cooldown: float = 3.0
@export var special_damage: float = 10.0
@export_multiline var description: String = ""
