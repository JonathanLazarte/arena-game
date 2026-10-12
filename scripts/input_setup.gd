extends Node
## Registra las acciones de entrada en tiempo de ejecución (teclado).

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack_sword": [KEY_J],
	"block": [KEY_K],
	"shoot_bow": [KEY_L],
	"summon": [KEY_E],
	"dash": [KEY_SPACE],
	"lock_on": [KEY_TAB, KEY_Q],
}

func _enter_tree() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
