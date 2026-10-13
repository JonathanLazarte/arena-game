class_name ArmorDef
extends Resource
## Ronda 19: pieza de armadura (casco, pecho, guantes, piernas). Peso, absorción por tipo de
## daño (fracción 0-1, se combinan multiplicativamente), equilibrio y resistencias.

@export var id: String = ""
@export var display_name: String = ""
@export var slot: String = "pecho" ## casco | pecho | guantes | piernas
@export var set_id: String = ""
@export var set_name: String = ""
@export var weight: float = 3.0
@export var absorption: Dictionary = {} ## fisico, magico, fuego, rayo, sagrado
@export var poise: float = 0.0
@export var resist: Dictionary = {} ## robustez, inmunidad, concentracion, vitalidad
@export var tint: Color = Color(0.6, 0.6, 0.65)
@export var level: int = 1 ## nivel de cuenta para comprarla
@export var price: int = 0 ## 0 y starter_for != "" = equipo inicial de un rol (no se vende)
@export var starter_for: String = ""
@export var weight_class: String = "medio" ## ligero | medio | pesado (estética de la tienda)
