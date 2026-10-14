extends SceneTree
## Ronda 28: animaciones Mixamo reapuntadas al rig KayKit y conectadas a los estados del juego.
## godot --headless --path . -s res://tests/test_round28.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1
func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var lib := load("res://assets/animations/mixamo/lib_kaykit.res") as AnimationLibrary
	check(lib != null and lib.get_animation_list().size() >= 24, "biblioteca KayKit reapuntada (%d clips)" % lib.get_animation_list().size())
	var moved := []
	var bad_path := []
	var knight: Node = (load("res://assets/models/Knight.glb") as PackedScene).instantiate()
	var sk := knight.find_child("Skeleton3D", true, false) as Skeleton3D
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		for t in a.get_track_count():
			var p := a.track_get_path(t)
			if String(p.get_concatenated_names()) != "Rig/Skeleton3D" or sk.find_bone(String(p.get_concatenated_subnames())) < 0:
				bad_path.append(n + ":" + str(p))
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var d := a.position_track_interpolate(t, a.length) - a.position_track_interpolate(t, 0.0)
				if Vector2(d.x, d.z).length() > 0.001:
					moved.append(n)
	knight.free()
	check(bad_path.is_empty(), "pistas sobre huesos KayKit %s" % str(bad_path.slice(0, 2)))
	check(moved.is_empty(), "sin desplazamiento horizontal de caderas (el juego mueve al luchador) %s" % str(moved))
	# Por personaje/arma
	for pair: Array in [["caballero", "espada_escudo"], ["caballero", "espada_larga"], ["berserker", "hacha_2m"], ["asesino", "dagas"], ["caballero", "lanza"], ["arquero", "arco"]]:
		var c := Catalog.character(pair[0])
		var w := Catalog.weapon(pair[1])
		if c == null or w == null:
			continue
		var kv := KnightVisual.new()
		root.add_child(kv)
		kv.setup(Color.WHITE, c, w)
		var ok: bool = kv.states["dodge_f"] == "mx/roll_f" and kv.states["boss_charge"] == "mx/boss_charge" and kv.states["cast"] == "mx/cast"
		for s: String in kv.states:
			ok = ok and kv.ap.has_animation(kv.states[s])
		var mw := w if not w.ranged else Catalog.weapon("dagas")
		var t: Dictionary = KnightVisual.MX_WEAPON.get(mw.id, {})
		if t.has("light0"):
			ok = ok and kv.states["light0"] == "mx/" + t["light0"] and kv.states["heavy"] == "mx/" + t["heavy"]
		if w.ranged:
			ok = ok and kv.states["aim"] == w.anim_aim # el arquero conserva sus clips KayKit
		check(ok, "%s + %s: clips Mixamo donde tocan, el resto KayKit" % pair)
		kv.queue_free()
	# En combate: carga de jefe, rotura de postura y hechizo usan sus estados
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1e9
	await create_timer(3.3).timeout
	var p := arena.player
	var e := arena.enemy
	e.global_position = p.global_position + Vector3(0, 0, -12)
	p.face_target = e
	await physics_frame
	p.boss_skill()
	await create_timer(0.3).timeout
	check(p._kv.state == "boss_charge", "Estocada de jefe: carga -> boss_charge (%s)" % p._kv.state)
	var seen_lunge := false
	for i in 150:
		await physics_frame
		seen_lunge = seen_lunge or p._kv.state == "boss_lunge"
	check(seen_lunge, "Estocada de jefe: embestida -> boss_lunge")
	await create_timer(2.0).timeout
	e.stance = 0.5
	e.take_hit(1.0, p, "melee")
	e.stance = 0.0
	e.stance_broken_t = Fighter.STANCE_BREAK_TIME
	e.stun = Fighter.STANCE_BREAK_TIME
	for i in 4: await physics_frame
	check(e._kv.state == "stance_break", "rotura de postura -> stance_break (%s)" % e._kv.state)
	e.stance_broken_t = 0.0
	e.stun = 0.0
	p.cast_t = 0.4
	for i in 2: await physics_frame
	check(p._kv.state == "cast", "hechizo -> cast (%s)" % p._kv.state)
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
