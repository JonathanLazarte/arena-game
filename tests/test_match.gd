extends SceneTree
## Simula una partida IA vs IA acelerada para comprobar rondas y pantalla final.

func _initialize() -> void:
	_run()

func _run() -> void:
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.controller.enabled = false
	var ai2 := SimAI.new(0, load("res://resources/ai/hard.tres"), 5) # fase 8: el jugador también lo lleva SimAI
	var m := arena.sim_match
	m.input_override[0] = func(_t: int) -> int: return ai2.think(m.state, m.params)
	Engine.time_scale = 4.0
	var t := 0.0
	while arena.state != "over" and t < 300.0:
		await create_timer(1.0).timeout
		t += 1.0
		if int(t) % 20 == 0:
			print("t=%ds ronda=%d marcador=%s vida J=%.0f R=%.0f eikons=%d" % [int(t * 4), arena.round_num, arena.wins, arena.player.health, arena.enemy.health, int(m.state[FightSim.EK_T] > 0) + int(m.state[FightSim.F_FIELDS + FightSim.EK_T] > 0)])
	print("FIN state=%s marcador=%s panel=%s" % [arena.state, arena.wins, arena.hud.end_panel.visible])
	var finished := arena.state == "over" # se guarda antes de reiniciar (el reinicio cambia el estado)
	if finished:
		arena.hud.restart_requested.emit()
		await process_frame
		print("Reinicio: ronda=%d marcador=%s panel=%s" % [arena.round_num, arena.wins, arena.hud.end_panel.visible])
	quit(0 if finished else 1)
