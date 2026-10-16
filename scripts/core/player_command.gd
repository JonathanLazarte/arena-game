class_name PlayerCommand
extends RefCounted
## Representa todas las intenciones de entrada de un jugador en un fotograma dado.
## Se serializa y se envía por la red al servidor o al rival en PvP.

var move_vector: Vector2 = Vector2.ZERO
var attack_light_pressed: bool = false
var attack_heavy_held: bool = false
var block_pressed: bool = false
var roll_pressed: bool = false
var parry_pressed: bool = false
var jump_pressed: bool = false
var flask_pressed: bool = false
var target_index: int = -1

func to_dict() -> Dictionary:
	return {
		"mv": [move_vector.x, move_vector.y],
		"al": attack_light_pressed,
		"ah": attack_heavy_held,
		"bl": block_pressed,
		"rl": roll_pressed,
		"pr": parry_pressed,
		"jp": jump_pressed,
		"fh": flask_pressed,
		"ti": target_index
	}

static func from_dict(d: Dictionary) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	var mv: Array = d.get("mv", [0, 0])
	cmd.move_vector = Vector2(mv[0], mv[1])
	cmd.attack_light_pressed = d.get("al", false)
	cmd.attack_heavy_held = d.get("ah", false)
	cmd.block_pressed = d.get("bl", false)
	cmd.roll_pressed = d.get("rl", false)
	cmd.parry_pressed = d.get("pr", false)
	cmd.jump_pressed = d.get("jp", false)
	cmd.flask_pressed = d.get("fh", false)
	cmd.target_index = d.get("ti", -1)
	return cmd
