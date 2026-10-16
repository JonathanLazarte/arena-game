extends Node
## Registra las acciones de entrada en tiempo de ejecución (teclado).

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack_sword": [KEY_J],
	"left_hand": [KEY_K, KEY_Q],
	"summon": [KEY_E],
	"dash": [KEY_C, KEY_L],
	"jump": [KEY_SPACE], ## Ronda 14: Espacio = saltar (el dash pasa a C / L)
	"special": [KEY_G], ## habilidad del personaje
	"lock_on": [KEY_TAB],
	"target_next": [KEY_Z], ## Ronda 16: cambiar objetivo (también rueda del ratón y botón «Objetivo»)
	"mount": [KEY_F],
	"sprint": [KEY_SHIFT], ## mantener: correr a pie / galope montado
	"run_toggle": [KEY_V, KEY_CAPSLOCK], ## Ronda 15: alternar correr a pie (táctil: «Correr»)
	"swap_weapon": [KEY_R],
	"spell": [KEY_X], ## Ronda 21: lanzar hechizo de eikon (a pie)
	"spell_next": [KEY_T],
	"boss": [KEY_B],
	"boss_variation": [KEY_M],
	"boss_next": [KEY_N], ## Ronda 31: siguiente habilidad de jefe equipada ## Ronda 25: habilidad de jefe (Estocada de jefe) ## Ronda 21: siguiente ranura de hechizo
	"flask": [KEY_H], ## Frasco de curación
}

func _enter_tree() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
