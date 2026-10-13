class_name CharacterDef
extends Resource
## Personaje / rol: estadísticas base, pasiva, armas compatibles y modelo (KayKit Adventurers, CC0).

@export var id: String = "caballero"
@export var display_name: String = "Caballero"
@export var role: String = "Equilibrado"
@export_multiline var description: String = ""
# Estadísticas base (1.0 = Caballero)
@export var vida: float = 100.0
@export var estamina: float = 100.0
@export var velocidad: float = 1.0 ## multiplicador de velocidad a pie y montado
@export var poise: float = 50.0
@export var dano: float = 1.0 ## multiplicador de daño cuerpo a cuerpo
@export var guardia: float = 1.0 ## multiplicador del aguante que cuesta bloquear (menos = mejor guardia)
@export var roll_iframe_bonus: int = 0 ## frames (a 30 fps) extra de invulnerabilidad en la voltereta
@export var roll_cost_mult: float = 1.0
## Pasiva: "guardia_firme", "ojo_de_halcon", "furia", "luz_sanadora", "sombra"
@export var passive_id: String = "guardia_firme"
@export var passive_name: String = "Guardia firme"
@export_multiline var passive_desc: String = ""
@export var weapons: PackedStringArray = PackedStringArray(["espada_escudo"]) ## ids compatibles
@export var default_weapon: String = "espada_escudo"
# Modelo
@export var model_path: String = "res://assets/models/Knight.glb"
@export var texture_path: String = "res://assets/models/knight_texture.png"
@export var body_prefix: String = "Knight_" ## mallas del cuerpo; el resto (armas del glb) se ocultan
@export var shield_mesh: String = "Round_Shield" ## escudo de este personaje (si el arma lo permite)
@export var shield_source: String = "res://assets/models/Knight.glb"
@export var tint: Color = Color(1, 1, 1)
## Ronda 14: habilidad especial (tecla G / botón "Habilidad"). "golpe_sismico" = área en el suelo.
@export var special_id: String = ""
@export var special_name: String = ""
@export_multiline var special_desc: String = ""

func allows(weapon_id: String) -> bool:
	return weapons.has(weapon_id)
## Ronda 16: remate propio del personaje con un arma concreta (p. ej. Caballero: escudazo + estocada).
@export var combo_finisher: Resource = null
@export var combo_finisher_weapon: String = ""
