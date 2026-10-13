extends SceneTree
## Simula una partida IA vs IA acelerada para comprobar rondas y pantalla final.

func _initialize() -> void:
	_run()

func _run() -> void:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.controller.enabled = false
	var ai2 := AIController.new()
	ai2.me = arena.player
	arena.add_child(ai2)
	Engine.time_scale = 4.0
	var t := 0.0
	while arena.state != "over" and t < 300.0:
		await create_timer(1.0).timeout
		t += 1.0
		if int(t) % 20 == 0:
			print("t=%ds ronda=%d marcador=%s vida J=%.0f R=%.0f eikons=%d" % [int(t * 4), arena.round_num, arena.wins, arena.player.health, arena.enemy.health, get_nodes_in_group("eikon").size()])
	print("FIN state=%s marcador=%s panel=%s" % [arena.state, arena.wins, arena.hud.end_panel.visible])
	var finished := arena.state == "over" # se guarda antes de reiniciar (el reinicio cambia el estado)
	if finished:
		arena.hud.restart_requested.emit()
		await process_frame
		print("Reinicio: ronda=%d marcador=%s panel=%s" % [arena.round_num, arena.wins, arena.hud.end_panel.visible])
	quit(0 if finished else 1)
