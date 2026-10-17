extends SceneTree
## Ronda 29: selector/nombres de personaje, suelo/muro/pilares garantizados, salto comprometido,
## orientación comprometida en el golpe, HUD del rival reducido y clips Mixamo en todos.
## godot --headless --path . -s res://tests/test_round29.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _run() -> void:
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 
	quit(fails)