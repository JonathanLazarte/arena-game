extends SceneTree
## Ronda 20: botón «✕» y Esc/Atrás en todos los paneles del lobby, AudioManager (buses,
## música con fundido, efectos con variación de tono, 3D en la arena) y Ajustes persistentes.
## godot --headless --path . -s res://tests/test_ui_audio.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var au := root.get_node("Audio")
	# --- Buses ---
	for b: String in ["Master", "Música", "Efectos", "UI"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s" % b)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Música")) == &"Master", "Música envía a Master")
	var sfx_node := root.get_node("Sfx")
	check((sfx_node._players["click"] as AudioStreamPlayer).bus == &"UI", "los sonidos de interfaz van por el bus UI")
	# --- Persistencia de Ajustes ---
	au.settings_path = "user://test_ajustes.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(au.settings_path))
	au.set_volume("Música", 0.25)
	au.set_volume("Efectos", 0.5)
	au.set_volume("UI", 0.0)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Música")) - linear_to_db(0.25)) < 0.01, "el volumen se aplica al bus (%.1f dB)" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Música")))
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "volumen 0 silencia el bus")
	var cfg := ConfigFile.new()
	check(cfg.load(au.settings_path) == OK and is_equal_approx(float(cfg.get_value("audio", "Música")), 0.25), "se guarda en user://")
	au.volumes["Música"] = 1.0
	au.volumes["Efectos"] = 1.0
	au.load_settings()
	check(is_equal_approx(au.get_volume("Música"), 0.25) and is_equal_approx(au.get_volume("Efectos"), 0.5) and is_equal_approx(au.get_volume("UI"), 0.0), "al cargar se recuperan los volúmenes")
	au.set_volume("UI", 0.8)
	# --- Recursos de audio ---
	for k: String in au.MUSIC:
		check(ResourceLoader.exists(au.MUSIC[k]), "música %s" % k)
	var missing: Array = []
	for k: String in au.SFX:
		for v: String in au.SFX[k]:
			if not ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % v):
				missing.append(v)
	check(missing.is_empty(), "todos los efectos existen %s" % [missing])
	check(FileAccess.get_file_as_string("res://CREDITS.md").contains("CC0") and FileAccess.get_file_as_string("res://CREDITS.md").contains("battle-theme-a"), "CREDITS con fuentes y licencias de audio")
	# --- Lobby: cierre de todos los paneles ---
	gs.save_path = "user://test_ui_audio.cfg"
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	await process_frame
	check(au.current_music == "lobby", "música del lobby")
	var x := lobby.find_child("CloseX", true, false) as Button
	check(x != null and not x.visible, "sin pestaña no hay ✕")
	for t: String in ["Personaje", "Armas", "Eikons", "Habilidades", "Herrero", "Tienda", "Inventario", "Ajustes"]:
		check(t in lobby.TABS, "pestaña %s" % t)
		lobby.set_tab(t)
		await process_frame
		var rp: Rect2 = lobby.sheet.get_global_rect() if t == "Personaje" else lobby.right_panel.get_global_rect()
		var xr := x.get_global_rect()
		check(x.visible and rp.encloses(Rect2(xr.position + Vector2(2, 2), Vector2(4, 4))) and xr.position.x > rp.position.x + rp.size.x - 70 and xr.position.y < rp.position.y + 30, "%s: ✕ arriba a la derecha del panel" % t)
		x.pressed.emit()
		await process_frame
		check(lobby.tab == "" and not lobby.right_panel.visible and not lobby.sheet.visible, "%s: ✕ vuelve al escaparate sin pestaña" % t)
		lobby.set_tab(t)
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		root.push_input(ev)
		await process_frame
		check(lobby.tab == "", "%s: Esc la cierra" % t)
	# Atributos y selector de equipo (encima de la ficha)
	lobby.set_tab("Personaje")
	lobby.open_attributes()
	await process_frame
	var ax := lobby.attr_screen.find_child("AttrX", true, false) as Button
	check(ax != null and ax.visible, "Atributos: ✕")
	ax.pressed.emit()
	check(not lobby.attr_screen.visible and lobby.tab == "Personaje", "Atributos: ✕ vuelve a la ficha")
	lobby.open_attributes()
	check(lobby.close_top() == "Atributos" and not lobby.attr_screen.visible, "Atributos: Esc/Atrás la cierra")
	lobby.sheet.open_picker("pecho")
	await process_frame
	check(not x.visible, "con el selector abierto se oculta la ✕ de la ficha")
	var px := lobby.sheet.find_child("PickerX", true, false) as Button
	px.pressed.emit()
	check(not lobby.sheet.picker.visible, "selector de equipo: ✕")
	lobby.sheet.open_picker("pecho")
	check(lobby.close_top() == "picker" and lobby.close_top() == "Personaje" and lobby.tab == "", "Esc cierra primero el selector y luego la ficha")
	lobby._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(lobby.tab == "", "Atrás de Android sin panel no rompe nada")
	lobby.set_tab("Inventario")
	lobby._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(lobby.tab == "", "Atrás de Android cierra la pestaña")
	# Ajustes: sliders reales
	lobby.set_tab("Ajustes")
	await process_frame
	var sl := lobby.find_child("Vol_Música", true, false) as HSlider
	check(sl != null and is_equal_approx(sl.value, 0.25), "Ajustes muestra el volumen guardado")
	sl.value = 0.7
	var c3 := ConfigFile.new()
	c3.load(au.settings_path)
	check(is_equal_approx(au.get_volume("Música"), 0.7) and is_equal_approx(float(c3.get_value("audio", "Música")), 0.7), "mover el slider cambia y guarda el volumen")
	for b: String in ["Master", "Efectos", "UI"]:
		check(lobby.find_child("Vol_" + b, true, false) != null, "slider %s" % b)
	# --- Arena: música de combate y efectos ---
	gs.from_lobby = true
	gs.random_rival = false
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.time_left = 1.0e9
	check(au.current_music in ["combate1", "combate2"], "fundido a música de combate (%s)" % au.current_music)
	await create_timer(3.2).timeout
	var p := arena.player
	var e := arena.enemy
	au.played.clear()
	p.attack_light()
	await create_timer(0.1).timeout
	check(au.count("swing_light") >= 1, "tajo ligero suena")
	p._cancel_attack()
	e.poise = 1e6
	e.take_hit(5.0, p, "melee")
	e.stun = 0.0
	check(au.count("hit_flesh") + au.count("hit_armor") >= 1, "golpe en carne/armadura")
	e.blocking = true
	e.facing = (p.global_position - e.global_position).normalized()
	e.take_hit(5.0, p, "melee")
	check(au.count("block") >= 1, "bloqueo")
	e.blocking = false
	p.stamina = p.stamina_max
	p.dash()
	check(au.count("roll") >= 1, "voltereta")
	await create_timer(1.0).timeout
	var n3d := 0
	for c in arena.get_children():
		if c is AudioStreamPlayer3D:
			n3d += 1
	au.sfx3d("parry", Vector3.ZERO)
	var found := false
	for c in arena.get_children():
		if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).bus == &"Efectos":
			found = true
	check(found, "efectos posicionales 3D (AudioStreamPlayer3D, bus Efectos)")
	var pitches: Array = []
	for i in 6:
		au.sfx3d("step", Vector3.ZERO)
	for c in arena.get_children():
		if c is AudioStreamPlayer3D:
			pitches.append(snappedf((c as AudioStreamPlayer3D).pitch_scale, 0.001))
	var uniq := {}
	for v in pitches:
		uniq[v] = true
	check(uniq.size() >= 3, "variación de tono aleatoria (%d tonos distintos)" % uniq.size())
	au.stinger("victoria")
	check(au.played.has("stinger:victoria") and au.current_music == "", "ráfaga de victoria (baja la música)")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
