extends SceneTree
## Ronda 21: capturas del HUD a pie (hechizos, Eikon listo) y montado (sin Parry ni Objetivo).
## godot --path . -s res://tests/screenshot_r21.gd -- <a_pie.png> <montado.png>

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var gs := root.get_node("GameState")
	gs.save_path = "user://shot_r21.cfg"
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	gs.owned_eikons = ["fenix", "lobo"]
	gs.spells = ["chispa", "aliento_helado"]
	gs.from_lobby = true
	gs.random_rival = false
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	await create_timer(3.3).timeout
	var p := arena.player
	arena.enemy.global_position = p.global_position + p.facing * 6.0
	p.meter = Fighter.METER_MAX
	await create_timer(0.2).timeout
	p.cast_spell()
	await create_timer(0.55).timeout
	root.get_viewport().get_texture().get_image().save_png(args[0])
	p.summon()
	await create_timer(1.5).timeout
	root.get_viewport().get_texture().get_image().save_png(args[1])
	print("saved")
	quit()
