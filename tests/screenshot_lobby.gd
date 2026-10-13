extends SceneTree
## Capturas de la ronda 11:
## godot --path . --rendering-driver opengl3 -s res://tests/screenshot_lobby.gd -- <ruta.png> <modo> [personaje] [pestaña]
## modo: lobby | first_run | results | arena | dash_strike | jump_aoe | mounted [eikon]
## lobby: [personaje] [pestaña] [eikon equipado]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "/workspace/out/lobby.png"
	var mode := args[1] if args.size() > 1 else "lobby"
	var gs := root.get_node("GameState")
	gs.save_path = "user://screenshot_loadout.cfg"
	gs.reset_defaults()
	if mode == "first_run":
		change_scene_to_file("res://scenes/first_run.tscn")
		await process_frame
		await process_frame
		current_scene.select(2)
		await create_timer(1.2).timeout
	elif mode == "arena":
		gs.choose_first_character("berserker")
		gs.from_lobby = true
		gs.random_rival = true
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var ar: Arena = current_scene
		ar.ai.enabled = false
		ar.player.dismount()
		ar.enemy.dismount()
		ar.enemy.global_position = ar.player.global_position + ar.player.facing * 3.0
		await create_timer(1.0).timeout
		var cam := Camera3D.new()
		ar.add_child(cam)
		var pp := ar.player.global_position
		cam.look_at_from_position(pp + ar.player.facing.cross(Vector3.UP) * 4.0 + Vector3(0, 2, 0) + ar.player.facing * 1.5, pp + ar.player.facing * 1.5 + Vector3(0, 1, 0))
		cam.current = true
		await create_timer(0.3).timeout
	elif mode == "run_back":
		# Ronda 15: correr hacia atrás fijado (sigue mirando al rival)
		gs.choose_first_character("caballero")
		gs.from_lobby = true
		gs.random_rival = false
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var ar: Arena = current_scene
		ar.ai.enabled = false
		ar.controller.set_physics_process(false)
		ar.time_left = 76.0
		var p := ar.player
		var e := ar.enemy
		await create_timer(0.8).timeout
		p.global_position = Vector3(0, 0, 3)
		p.facing = Vector3.FORWARD
		e.global_position = Vector3(0, 0, -1)
		e.facing = Vector3.BACK
		p.face_target = e
		p.move_input = (Vector3.BACK + Vector3.RIGHT * 0.25).normalized()
		p.want_sprint = true
		await create_timer(0.75).timeout
		var cam := Camera3D.new()
		ar.add_child(cam)
		var pp := p.global_position
		cam.look_at_from_position(pp + Vector3(5.5, 2.4, 2.5), pp + Vector3(0, 1.0, -2.2))
		cam.current = true
		await process_frame
		print("mirando al rival: ", p.facing.dot(MeshUtil.flat(e.global_position - p.global_position).normalized()), " sprint ", p.sprinting)
	elif mode in ["dash_strike", "jump_aoe", "mounted"]:
		# Ronda 14
		gs.choose_first_character("caballero" if mode != "jump_aoe" else "berserker")
		gs.owned_eikons.append_array(["lobo", "grifo"])
		gs.eikon_id = args[2] if args.size() > 2 else "fenix"
		gs.from_lobby = true
		gs.random_rival = false
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var ar: Arena = current_scene
		ar.ai.enabled = false
		ar.controller.set_physics_process(false)
		ar.time_left = 76.0
		var p := ar.player
		var e := ar.enemy
		await create_timer(0.8).timeout
		p.global_position = Vector3(0, 0, 8)
		p.facing = Vector3.FORWARD
		p.face_target = e
		var cam := Camera3D.new()
		ar.add_child(cam)
		cam.current = true
		if mode == "dash_strike":
			e.global_position = Vector3(0, 0, 1.5)
			e.facing = Vector3.BACK
			await physics_frame
			cam.look_at_from_position(Vector3(5.2, 1.9, 4.2), Vector3(0, 1.0, 4.4))
			p.move_input = Vector3.FORWARD
			p.dash()
			for i in 6:
				await physics_frame
			p.attack_light()
			var guard := 0
			while not (p.is_dash_striking() and p.atk_state == Fighter.Atk.WINDUP and p.atk_t > p.atk_dur * 0.85) and guard < 120:
				await physics_frame
				guard += 1
			p.move_input = Vector3.ZERO
			await process_frame
		elif mode == "jump_aoe":
			# El jugador (Berserker) usa el golpe sísmico y el rival lo salta
			e.global_position = Vector3(0, 0, 4.8)
			e.facing = Vector3.BACK
			await physics_frame
			cam.look_at_from_position(Vector3(8.0, 2.0, 9.5), Vector3(0, 0.9, 6.3))
			p.special()
			await create_timer(Fighter.SLAM_TELEGRAPH - 0.42).timeout
			e.jump()
			await create_timer(0.32).timeout
			print("aire: ", e.airborne, " y=", e.global_position.y)
		else:
			e.global_position = Vector3(5, 0, -4)
			p.meter = Fighter.METER_MAX
			p.summon()
			await create_timer(0.6).timeout
			p.move_input = Vector3.FORWARD.rotated(Vector3.UP, 0.4)
			p.want_sprint = true
			p.face_target = null
			await create_timer(0.7).timeout
			var pp := p.global_position
			cam.look_at_from_position(pp + p.facing.cross(Vector3.UP) * 6.0 + Vector3(0, 2.6, 0) + p.facing * 3.0, pp + Vector3(0, 1.6, 0) + p.facing * 0.5)
			await create_timer(0.15).timeout
			pp = p.global_position
			cam.look_at_from_position(pp + p.facing.cross(Vector3.UP) * 6.0 + Vector3(0, 2.6, 0) + p.facing * 3.0, pp + Vector3(0, 1.6, 0) + p.facing * 0.5)
			await process_frame
	elif mode == "results":
		gs.choose_first_character("berserker")
		gs.account_xp = 80
		gs.char_xp["berserker"] = 80
		gs.from_lobby = true
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var a: Arena = current_scene
		a.ai.enabled = false
		a.player.hits_landed = 14
		a.player.parries_landed = 2
		a.wins = [1, 2]
		a.state = "fight"
		a.wins[1] = 1
		a._on_fighter_died(a.player)
		a.wins = [2, 1]
		a.state = "fight"
		a.wins[0] = 1
		a._on_fighter_died(a.enemy)
		await create_timer(2.0).timeout
	else:
		var cid := args[2] if args.size() > 2 else "caballero"
		gs.choose_first_character(cid)
		gs.oro = 2400
		gs.account_xp = 900
		gs.char_xp[cid] = 900
		if args.size() > 4:
			gs.owned_eikons.append(args[4])
			gs.eikon_id = args[4]
		if args.size() > 3 and args[3] in ["Habilidades", "Personaje"]:
			gs.learn_skill(Progression.tree(cid)[0]["id"])
			gs.learn_skill(Progression.tree(cid)[1]["id"])
		change_scene_to_file("res://scenes/lobby.tscn")
		await process_frame
		await process_frame
		var lobby := current_scene
		lobby.spin_speed = 0.0
		lobby.pedestal.rotation.y = 0.4
		if args.size() > 3:
			lobby.set_tab(args[3])
		await create_timer(1.2).timeout
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
