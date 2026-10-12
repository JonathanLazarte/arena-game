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
