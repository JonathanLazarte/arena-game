class_name CommandProcessor
extends Node

@export var is_local_player: bool = true

var remote_command: PlayerCommand = PlayerCommand.new()

## Genera el comando basado en los dispositivos locales (Teclado / Joystick táctil)
func poll_local_command() -> PlayerCommand:
	var cmd := PlayerCommand.new()
	if not is_local_player:
		return remote_command
	
	# Recolectar entradas usando las rutinas existentes de tu PlayerController
	var raw_v := PlayerController.shape_stick(Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0))
	cmd.move_vector = raw_v
	cmd.attack_light_pressed = Input.is_action_just_pressed("attack_sword")
	cmd.attack_heavy_held = Input.is_action_pressed("attack_sword")
	cmd.block_pressed = Input.is_action_pressed("block")
	cmd.roll_pressed = Input.is_action_just_pressed("dash")
	cmd.parry_pressed = Input.is_action_just_pressed("parry")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.flask_pressed = Input.is_action_just_pressed("flask")
	
	return cmd
