class_name WeaponDef
extends Resource
## Tipo de arma: alcance, daño, velocidad (anticipación), coste de aguante,
## escudo y moveset (animaciones de KayKit reutilizadas). Crea un .tres para añadir armas.

@export var id: String = "espada_escudo"
@export var display_name: String = "Espada y escudo"
@export_multiline var description: String = ""
@export var ranged: bool = false ## arco: dispara en vez de atacar cuerpo a cuerpo
@export var allows_shield: bool = true
@export var two_handed: bool = false ## requiere ambas manos; no admite objetos en la izquierda
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
## Ronda 17: disparo con compromiso (a pie). Montado no hay raíz ni lentitud, pero sí los tiempos.
@export var fire_draw: float = 0.5 ## tensar/apuntar: a pie, quieto
@export var fire_recovery: float = 0.4 ## tras soltar: a pie, andar a fire_slow
@export var fire_slow: float = 0.25
@export var fire_cooldown: float = 0.15 ## espera antes del siguiente disparo
@export var reload_time: float = 0.0 ## ballesta: recarga (sin disparar)
@export var reload_slow: float = 0.6
@export var projectile_speed: float = 32.0
@export var ranged_hitstun: float = 0.25
@export var anim_aim: String = "2H_Ranged_Aiming"
@export var anim_shoot: String = "2H_Ranged_Shoot"
@export var anim_reload: String = "2H_Ranged_Reload"
## Aturdimiento del ataque fuerte cuerpo a cuerpo (los del combo van en cada ComboHit.hitstun).
@export var heavy_hitstun: float = 0.6
## Ronda 18: escalado por atributo (coeficiente; letra S-E en Attributes.grade) y requisitos mínimos.
@export var scaling: Dictionary = {}
@export var requirements: Dictionary = {}
## Ronda 16: cadena de ataques básicos (3 golpes: ida, vuelta y remate). Vacío = ligero genérico.
@export var combo: Array[Resource] = []
## Ronda 20: acumulación de estado por golpe {"sangrado"/"veneno"/"congelacion": puntos}
@export var status: Dictionary = {}
## Ronda 20: herrería (las fija Smithing.effective en una copia; el recurso base va a +0)
@export var stun_force: float = -1.0 ## ronda 31: fuerza de aturdimiento propia (-1 = StunRules.WEAPON_FORCE)
@export var heavy_stun_resist: float = 1.0 ## ronda 31: súper-armadura del fuerte en su anticipación
@export var charged_shot: String = "" ## ronda 31 (arcos): "potente" o "triple" ("" = según el arma)
@export var phys_type: String = "estandar" ## ronda 24: subtipo físico (PhysTypes)
## Ronda 25: paso adelante de cada ataque (m), estilo ER: por arma y por golpe del combo.
@export var step_light: Array[float] = [0.9, 0.9, 1.2]
@export var step_heavy: float = 1.4
@export var upgrade_level: int = 0
@export var infusion: String = ""
@export var upgrade_dmg_mult: float = 1.0

func combo_hit(i: int, cdef: CharacterDef = null) -> ComboHit:
	if combo.is_empty():
		return null
	var idx := clampi(i, 0, combo.size() - 1)
	if cdef and cdef.combo_finisher and cdef.combo_finisher_weapon == id and idx == combo.size() - 1:
		return cdef.combo_finisher as ComboHit
	return combo[idx] as ComboHit

## Diccionario de ataque con las mismas claves que Fighter.LIGHT / Fighter.HEAVY.
func attack(heavy: bool) -> Dictionary:
	if heavy:
		return {"windup": heavy_windup, "chain_windup": heavy_windup, "active": heavy_active, "recovery": heavy_recovery,
			"whiff": 0.35, "damage": heavy_damage, "stamina": heavy_stamina}
	return {"windup": light_windup, "chain_windup": light_windup, "active": light_active, "recovery": light_recovery,
		"whiff": 0.3, "damage": light_damage, "stamina": light_stamina}
