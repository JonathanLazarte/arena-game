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
	elif mode in ["fire_bow", "fire_xbow", "parthian"]:
		# Ronda 17
		gs.character_id = "arquero"
		gs.weapon_id = "ballesta" if mode == "fire_xbow" else "arco"
		gs.eikon_id = "lobo"
		Arena.start_mounted = false
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
		e.global_position = Vector3(-2, 0, -6)
		p.face_target = e
		var cam := Camera3D.new()
		ar.add_child(cam)
		if mode == "parthian":
			p.meter = Fighter.METER_MAX
			p.summon()
			await create_timer(0.5).timeout
			p.want_sprint = true
			for i in 70:
				p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized().rotated(Vector3.UP, 0.5)
				await physics_frame
			p.bow_cd = 0.0
			p.shoot()
			for i in 22:
				p.move_input = MeshUtil.flat(p.global_position - e.global_position).normalized().rotated(Vector3.UP, 0.5)
				await physics_frame
			var pp := p.global_position
			var side := p.facing.cross(Vector3.UP)
			cam.look_at_from_position(pp + side * 7.0 + Vector3(0, 3.0, 0) + p.facing * 2.0, pp + Vector3(0, 1.6, 0) - p.facing * 1.5)
			print("giro jinete: ", rad_to_deg(p.rider_yaw))
		else:
			await create_timer(1.6).timeout
			p.global_position = Vector3(0, 0, 8)
			p.facing = Vector3.FORWARD
			await physics_frame
			print("arma: ", p.weapon.id, " estado ", p.shot_state, " ok ", p.shoot())
			var target_state := Fighter.Shot.RELOAD if mode == "fire_xbow" else Fighter.Shot.DRAW
			var guard := 0
			while p.shot_state != target_state and guard < 200:
				await physics_frame
				guard += 1
			for i in (12 if mode == "fire_xbow" else 18):
				await physics_frame
			var pp := p.global_position
			cam.look_at_from_position(pp + Vector3(3.6, 2.0, 1.6), pp + Vector3(0, 1.1, -1.2))
		Engine.time_scale = 0.0
		cam.make_current()
		for i in 3:
			await process_frame
	elif mode in ["lock_eikon", "combo", "run_cam"]:
		# Ronda 16
		gs.choose_first_character("caballero")
		gs.from_lobby = true
		gs.random_rival = false
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var ar: Arena = current_scene
		ar.ai.enabled = false
		ar.time_left = 76.0
		var p := ar.player
		var e := ar.enemy
		await create_timer(0.8).timeout
		if mode == "lock_eikon":
			ar.controller.set_physics_process(false)
			p.global_position = Vector3(0, 0, 9)
			e.global_position = Vector3(1.5, 0, -2)
			e.eikon = load("res://resources/eikons/stone_golem.tres")
			e.meter = Fighter.METER_MAX
			e.summon()
			await physics_frame
			ar.controller.lock_on = true
			ar.controller.target = e
			p.face_target = ar.controller.cycle_target()
			await create_timer(0.6).timeout
			print("objetivo: ", p.face_target)
		elif mode == "combo":
			ar.controller.set_physics_process(false)
			var n := int(args[2]) if args.size() > 2 else 1
			p.global_position = Vector3(0, 0, 8)
			p.facing = Vector3.FORWARD
			e.global_position = Vector3(0, 0, 5.8)
			e.facing = Vector3.BACK
			e.max_health = 9999.0
			e.health = 9999.0
			p.face_target = e
			await physics_frame
			p.attack_light()
			var guard := 0
			while guard < 400:
				await physics_frame
				guard += 1
				e.stun = 0.0
				if p.atk_state == Fighter.Atk.RECOVERY and p.combo < n:
					p.attack_light()
				if p.combo == n and ((p.atk_state == Fighter.Atk.ACTIVE and p.atk_t > p.atk_dur * 0.5) or p.atk_state == Fighter.Atk.RECOVERY):
					break
			Engine.time_scale = 0.0 # congela la pose del golpe
			var cam := Camera3D.new()
			ar.add_child(cam)
			p.face_target = null
			cam.fov = 55.0
			cam.look_at_from_position(p.global_position + Vector3(5.8, 2.3, 1.2), p.global_position + Vector3(0, 0.9, -1.0))
			cam.make_current()
			var cl := CanvasLayer.new()
			cl.layer = 50
			ar.add_child(cl)
			var lb := Label.new()
			lb.text = "Golpe %d: %s (%s)" % [n, p.cur_hit.name if p.cur_hit else "?", p.cur_hit.direction if p.cur_hit else ""]
			lb.position = Vector3(380, 120, 0) if false else Vector2(380, 120)
			lb.add_theme_font_size_override("font_size", 34)
			lb.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
			lb.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.2))
			lb.add_theme_constant_override("outline_size", 8)
			cl.add_child(lb)
			for i in 3:
				await process_frame
		else:
			# Corre hacia atrás fijado: se gira hacia la cámara (control real)
			p.global_position = Vector3(0, 0, 2)
			e.global_position = Vector3(0, 0, -6)
			ar.controller.lock_on = true
			ar.controller.run_toggled = true
			Input.action_press("move_back")
			await create_timer(0.9).timeout
			print("mira hacia la cámara: ", p.facing.dot((ar.camera.global_position - p.global_position).normalized()))
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
	elif mode == "status":
		# Ronda 20: barras de acumulación en combate (HUD y sobre el rival), veneno y congelación
		gs.choose_first_character("asesino")
		gs.weapon_id = "dagas"
		gs.eikon_id = "lobo"
		Arena.start_mounted = false
		gs.from_lobby = true
		gs.random_rival = false
		change_scene_to_file("res://scenes/arena.tscn")
		await process_frame
		await process_frame
		var ar: Arena = current_scene
		ar.ai.enabled = false
		ar.controller.set_physics_process(false)
		ar.time_left = 71.0
		await create_timer(3.2).timeout
		var p := ar.player
		var e := ar.enemy
		p.global_position = Vector3(0, 0, 5)
		e.global_position = Vector3(0.8, 0, 1.2)
		p.facing = Vector3.FORWARD
		p.face_target = e
		e.facing = Vector3.BACK
		e.poise = 1e6
		e.take_hit(1.0, p, "melee")
		e.stun = 0.0
		e.add_status("veneno", 500.0)
		e.add_status("sangrado", 60.0)
		e.add_status("congelacion", 45.0)
		p.add_status("congelacion", 60.0)
		p.add_status("sangrado", 30.0)
		var cam := Camera3D.new()
		ar.add_child(cam)
		cam.look_at_from_position(Vector3(-1.5, 3.2, 9.5), Vector3(0.5, 1.2, 1.5))
		cam.current = true
		await create_timer(0.4).timeout
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
		if args.size() > 3 and args[3].begins_with("flow_"):
			# Ronda 19: flujo real con clics del ratón/táctil sobre los botones (no se abre por código)
			gs.char_xp[cid] = Progression.xp_at_level(5)
			gs.oro = 2400
			await create_timer(0.6).timeout
			var steps: Array = {"flow_sheet": ["Tab_Personaje"], "flow_attrs": ["Tab_Personaje", "AtributosButton"],
				"flow_picker": ["Tab_Personaje", "Slot_pecho"], "flow_shop": ["Tab_Tienda", "Cat_Armaduras"],
				"flow_smith": ["Tab_Herrero"], "flow_settings": ["Tab_Ajustes"], "flow_stones": ["Tab_Tienda", "Cat_Materiales"]}[args[3]]
			if args[3] == "flow_smith":
				gs.oro = 5000
				gs.add_material("piedra_1", 6)
				gs.upgrade_weapon(gs.weapon_id)
				gs.upgrade_weapon(gs.weapon_id)
				gs.infuse(gs.weapon_id, "sangrante")
			for nm: String in steps:
				var b := lobby.root_ui.find_child(nm, true, false) as Control
				var c := b.get_global_rect().get_center()
				for pressed in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = pressed
					ev.position = c
					ev.global_position = c
					root.push_input(ev)
					await process_frame
				await create_timer(0.5).timeout
			if args[3] == "flow_picker":
				var opts: Array = lobby.sheet.picker_list.get_children()
				if opts.size() > 0:
					lobby.sheet.select_option("")
		elif args.size() > 3 and args[3] == "Atributos":
			# Ronda 18: pantalla de atributos con cambios pendientes (vista previa)
			gs.char_xp[cid] = Progression.xp_at_level(7)
			var a0: Dictionary = gs.char_attrs().duplicate()
			a0["fuerza"] += 4
			a0["vitalidad"] += 2
			gs.set_attrs(a0)
			lobby.set_tab("Personaje")
			lobby.open_attributes()
			for k: String in ["fuerza", "fuerza", "aguante", "aguante", "destreza", "vinculo"]:
				lobby.attr_screen.change(k, 1)
		elif args.size() > 3:
			lobby.set_tab(args[3])
		await create_timer(1.2).timeout
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
