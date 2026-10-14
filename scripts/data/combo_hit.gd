class_name ComboHit
extends Resource
## Ronda 16: un golpe de la cadena de ataques básicos (combo de 3). Cada arma define su
## cadena en WeaponDef.combo; un personaje puede sustituir el remate (CharacterDef.combo_finisher).

@export var name: String = "Tajo"
## Clip de KayKit base. Si mirror = true se crea en Godot una versión espejada (izq.<->der.),
## así el 2.º golpe vuelve en la dirección contraria. then_anim (opcional) encadena un segundo clip
## dentro del mismo golpe (p. ej. golpe de escudo + estocada), cortando en `split`.
@export var anim: String = "1H_Melee_Attack_Slice_Horizontal"
@export var mirror: bool = false
## reverse = el clip se reproduce al revés (autorizado en Godot): el brazo del arma vuelve
## desde el final del tajo anterior en sentido contrario (revés). Para armas de una mano es
## mejor que el espejo, que pasaría el movimiento al brazo del escudo.
@export var reverse: bool = false
@export var then_anim: String = ""
@export var split: float = 0.45
## Dirección del tajo para leerla en pantalla/HUD: "der→izq", "izq→der", "vertical", "estocada", "giro".
@export var direction: String = "der→izq"
@export var damage: float = 12.0
@export var reach: float = 2.2 ## alcance a pie (montado se escala con reach_mounted/reach_foot del arma)
@export var arc_deg: float = 70.0 ## medio arco
@export var windup: float = 0.42
@export var active: float = 0.12
@export var recovery: float = 0.55
@export var stamina: float = 13.0
@export var phys_type: String = "" ## ronda 24: "" = el del arma (las estocadas, perforantes)
@export var poise_mult: float = 1.0 ## daño de poise relativo (el remate > 1)
@export var window: float = 0.45 ## s desde el fin del golpe en que se acepta la siguiente pulsación
@export var lunge: float = 0.0 ## m/s hacia delante durante el final de la anticipación y el golpe
@export var hop: float = 0.0 ## salto visual (m) del remate con salto
@export var finisher: bool = false
## Ronda 17: aturdimiento que causa al defensor. Golpes 1 y 2: corto (da tiempo a rodar antes del
## siguiente si no se es codicioso); remate: largo (tambaleo).
@export var hitstun: float = 0.3
## Ronda 31: fuerza de aturdimiento asignada al golpe (-1 = hitstun x StunRules.HITSTUN_TO_FORCE)
## y súper-armadura en su anticipación (la robustez se multiplica por 1 + stun_resist).
@export var stun_force: float = -1.0
@export var stun_resist: float = 0.0

func attack_dict() -> Dictionary:
	return {"windup": windup, "chain_windup": windup, "active": active, "recovery": recovery,
		"whiff": 0.25 if not finisher else 0.35, "damage": damage, "stamina": stamina}

## Nombre del clip ya autorizado en la biblioteca de animaciones.
func clip_name() -> String:
	if then_anim != "":
		return "Combo_%s_%s" % [anim, then_anim]
	return anim + ("_Mirror" if mirror else "") + ("_Reverse" if reverse else "")
