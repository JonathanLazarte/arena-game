class_name WeaponDef
extends Resource
## Tipo de arma: alcance, daño, velocidad (anticipación), coste de aguante,
## escudo y moveset (animaciones de KayKit reutilizadas). Crea un .tres para añadir armas.

@export var id: String = "espada_escudo"
@export var display_name: String = "Espada y escudo"
@export_multiline var description: String = ""
@export var ranged: bool = false ## arco: dispara en vez de atacar cuerpo a cuerpo
@export var allows_shield: bool = true
# Alcance
@export var reach_foot: float = 2.2
@export var reach_mounted: float = 3.4
@export var half_arc_foot_deg: float = 70.0
@export var half_arc_mounted_deg: float = 100.0
# Ligero / fuerte
@export var light_damage: float = 12.0
@export var heavy_damage: float = 26.0
@export var light_windup: float = 0.45
@export var heavy_windup: float = 0.8
@export var light_active: float = 0.12
@export var heavy_active: float = 0.15
@export var light_recovery: float = 0.6
@export var heavy_recovery: float = 0.75
@export var light_stamina: float = 14.0
@export var heavy_stamina: float = 28.0
@export var max_combo: int = 3
@export var mounted_damage_mult: float = 1.0 ## lanza: más daño a caballo
@export var guard_break_mult: float = 1.0 ## aguante extra que quita al bloquearlo
@export var poise_damage_mult: float = 1.0
@export var no_shield_block_chip: float = 0.45 ## sin escudo se bloquea con el arma: pasa más daño
# Moveset (clips del rig de KayKit) y visual
@export var anim_light: PackedStringArray = PackedStringArray(["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop"])
@export var anim_heavy: String = "2H_Melee_Attack_Chop"
@export var anim_idle: String = "Idle"
## Mallas que se copian del glb indicado a la mano derecha / izquierda (vacío = ninguna)
@export var mesh_source: String = "res://assets/models/Knight.glb"
@export var mesh_right: String = "1H_Sword"
@export var mesh_left: String = ""
@export var procedural: String = "" ## "lanza" = malla generada por código
@export var arrow_damage: float = 8.0

## Diccionario de ataque con las mismas claves que Fighter.LIGHT / Fighter.HEAVY.
func attack(heavy: bool) -> Dictionary:
	if heavy:
		return {"windup": heavy_windup, "chain_windup": heavy_windup, "active": heavy_active, "recovery": heavy_recovery,
			"whiff": 0.35, "damage": heavy_damage, "stamina": heavy_stamina}
	return {"windup": light_windup, "chain_windup": light_windup, "active": light_active, "recovery": light_recovery,
		"whiff": 0.3, "damage": light_damage, "stamina": light_stamina}
