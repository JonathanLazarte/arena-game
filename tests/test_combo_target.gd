extends SceneTree
## Ronda 16: combo de 3 golpes por arma/personaje, cambio de objetivo + anillo, eikons con vida
## y eikons sin jinete como compañeros de ataque. godot --headless --path . -s res://tests/test_combo_target.gd

var fails: int = 0
var arena: Arena
var p: Fighter
var e: Fighter

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func _place(dist: float) -> void:
	p.move_input = Vector3.ZERO
	e.move_input = Vector3.ZERO
	await wait(0.3)
	p.global_position = Vector3(0, 0, 8)
	p.facing = Vector3.FORWARD
	p.face_target = e
	p.stamina = p.stamina_max
	e.global_position = Vector3(0, 0, 8 - dist)
	e.facing = Vector3.BACK
	e.want_block = false
	e.stun = 0.0
	e.poise_max = 10000.0 # sin romper la poise: se mide el daño de poise de cada golpe
	e.poise = e.poise_max
	await physics_frame

## Encadena los 3 golpes pulsando una vez por golpe (dentro de la ventana).
func _chain(n: int) -> Dictionary:
	p.combo_log.clear()
	var dmg: Array[float] = []
	var poise_d: Array[float] = []
	var anims: Array[String] = []
	var h0 := e.health
	var po0 := e.poise
	p.attack_light()
	var last := 0
	for i in 240:
		await physics_frame
		e.stun = 0.0
		e.stance = e.stance_max # ronda 24: se mide el equilibrio, no la postura
		if p.combo != last and p.atk_state != Fighter.Atk.NONE:
			last = p.combo
			if p._kv.state.begins_with("light"):
				anims.append(p._kv.states[p._kv.state])
		if p.atk_state == Fighter.Atk.RECOVERY and p.combo < n and p.atk_t > 0.05:
			p.attack_light()
		if e.health < h0:
			dmg.append(h0 - e.health)
			poise_d.append(po0 - e.poise if e.poise <= po0 else po0 + (e.poise_max - e.poise))
			h0 = e.health
			e.poise = e.poise_max
			po0 = e.poise
		if p.atk_state == Fighter.Atk.NONE and i > 10:
			break
	return {"log": p.combo_log.duplicate(), "dmg": dmg, "poise": poise_d, "anims": anims}

func _run() -> void:
	seed(16)
	# --- Datos ---
	var ok_data := true
	for wid: String in ["espada_escudo", "espada_larga", "hacha_2m", "dagas", "lanza"]:
		var w: WeaponDef = load("res://resources/weapons/%s.tres" % wid)
		var hs: Array = w.combo
		if hs.size() != 3:
			ok_data = false
			continue
		var h1: ComboHit = hs[0]
		var h3: ComboHit = hs[2]
		if not (h3.finisher and h3.poise_mult > h1.poise_mult and h3.damage > h1.damage and h1.window > 0.0):
			ok_data = false
	check(ok_data, "las 5 armas cuerpo a cuerpo: 3 golpes, remate con más daño y poise")
	var ws: WeaponDef = load("res://resources/weapons/espada_escudo.tres")
	var cab: CharacterDef = load("res://resources/characters/caballero.tres")
	var pal: CharacterDef = load("res://resources/characters/paladin.tres")
	check(ws.combo_hit(2, cab).name == "Escudazo y estocada" and ws.combo_hit(2, pal).name == "Tajo descendente", "remate propio del Caballero (escudo + estocada); el Paladín usa el del arma")
	check((ws.combo[0] as ComboHit).direction != (ws.combo[1] as ComboHit).direction and (ws.combo[1] as ComboHit).reverse, "2.º golpe en sentido contrario (clip al revés)")
	# --- En la arena ---
	Arena.start_mounted = false
	var gs := root.get_node("GameState")
	gs.from_lobby = true
	gs.random_rival = false
	gs.character_id = "caballero"
	gs.weapon_id = "espada_escudo"
	gs.eikon_id = "fenix"
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene as Arena
	arena.time_left = 1.0e9
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	p = arena.player
	e = arena.enemy
	for f: Fighter in [p, e]:
		f.max_health = 5000.0
		f.health = 5000.0
		f.meter_passive = false
	await wait(0.8)
	# Clip del revés: la pose en t es la del original en L - t (mismo brazo, sentido contrario)
	var ap: AnimationPlayer = p._kv.ap
	var h2: ComboHit = p.combo_hit_for(2)
	var rev := ap.get_animation(h2.clip_name()) if ap.has_animation(h2.clip_name()) else null
	var src := ap.get_animation(h2.anim)
	var rok := false
	if rev:
		for i in src.get_track_count():
			if src.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(src.track_get_path(i)).ends_with("upperarm.r"):
				var ri := rev.find_track(src.track_get_path(i), Animation.TYPE_ROTATION_3D)
				if ri >= 0:
					rok = rev.rotation_track_interpolate(ri, 0.2).is_equal_approx(src.rotation_track_interpolate(i, src.length - 0.2))
	check(rok, "clip «%s» autorizado en Godot (tajo al revés con el brazo del arma)" % h2.clip_name())
	# Dagas: el 2.º golpe es el espejo (dos armas: izquierda <-> derecha)
	var dg: WeaponDef = load("res://resources/weapons/dagas.tres")
	var mclip := KnightVisual.author_combo_clip(ap, dg.combo[1])
	var mir := ap.get_animation(mclip) if ap.has_animation(mclip) else null
	var dsrc := ap.get_animation((dg.combo[1] as ComboHit).anim)
	var mok := false
	if mir and dsrc:
		for i in dsrc.get_track_count():
			if dsrc.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(dsrc.track_get_path(i)).ends_with("upperarm.l"):
				var mi := mir.find_track(NodePath(String(dsrc.track_get_path(i)).replace("upperarm.l", "upperarm.r")), Animation.TYPE_ROTATION_3D)
				if mi >= 0:
					var q: Quaternion = dsrc.rotation_track_interpolate(i, 0.3)
					mok = mir.rotation_track_interpolate(mi, 0.3).is_equal_approx(Quaternion(q.x, -q.y, -q.z, q.w))
	check(mok, "dagas: clip espejado «%s» (huesos .l/.r intercambiados)" % mclip)
	check(ap.has_animation(p.combo_hit_for(3).clip_name()), "clip encadenado del remate (%s)" % p.combo_hit_for(3).clip_name())
	await _place(1.8)
	var r := await _chain(3)
	check(r["log"] == ["Tajo horizontal", "Revés", "Escudazo y estocada"], "combo del Caballero: %s" % [r["log"]])
	check(r["dmg"].size() == 3, "los 3 golpes conectan (%s)" % [r["dmg"]])
	if r["dmg"].size() == 3:
		var hs3: Array = [p.combo_hit_for(1), p.combo_hit_for(2), p.combo_hit_for(3)]
		var dm_ok := true
		for i in 3:
			dm_ok = dm_ok and is_equal_approx(r["dmg"][i], (hs3[i] as ComboHit).damage * p.damage_mult())
		check(dm_ok, "cada golpe con su daño (%s)" % [r["dmg"]])
		check(r["poise"][2] / r["dmg"][2] > r["poise"][0] / r["dmg"][0] * 1.5, "el remate hace más daño de poise (%s)" % [r["poise"]])
	var uniq := {}
	for a: String in r["anims"]:
		uniq[a] = true
	check(r["anims"].size() == 3 and uniq.size() == 3, "una animación distinta por golpe (%s)" % [r["anims"]])
	# Ventana de entrada: pulsar tarde no encadena
	await _place(1.8)
	p.combo_log.clear()
	p.attack_light()
	var h1: ComboHit = p.combo_hit_for(1)
	while p.atk_state != Fighter.Atk.RECOVERY:
		await physics_frame
	while p.atk_t <= h1.window + 0.03 and p.atk_state == Fighter.Atk.RECOVERY:
		await physics_frame
	p.attack_light()
	await wait(0.6)
	check(p.combo_log.size() <= 2 and (p.combo_log.size() == 1 or p.combo_log[1] == h1.name), "fuera de la ventana no encadena (reinicia en el 1.º): %s" % [p.combo_log])
	await wait(1.0)
	# --- Cambio de objetivo + eikon enemigo con vida ---
	await _place(8.0)
	e.eikon = load("res://resources/eikons/stone_golem.tres")
	e.meter = Fighter.METER_MAX
	check(e.summon(), "el rival invoca al Gólem (compañero)")
	await physics_frame
	var gol: Node3D = e.active_eikon
	var pc := arena.controller
	var ts := pc.targets()
	check(ts.size() == 2 and ts[0] == e and gol in ts, "objetivos válidos: rival y su eikon (%d)" % ts.size())
	pc.lock_on = true
	pc.target = e
	check(pc.cycle_target() == gol, "cambiar objetivo pasa al eikon enemigo")
	p.face_target = pc.target
	await physics_frame
	await physics_frame
	check(arena.lock_ring.visible and MeshUtil.flat(arena.lock_ring.global_position - gol.global_position).length() < 0.5, "anillo de fijado en el eikon")
	check(pc.cycle_target() == e, "…y vuelve al rival")
	var gh: float = gol.health
	gol.take_hit(20.0, p, "melee")
	check(gol.health == gh - 20.0, "el eikon enemigo tiene vida y recibe daño (%.0f)" % gol.health)
	gol.take_hit(9999.0, p, "melee")
	await physics_frame
	check(not is_instance_valid(gol) or not gol.alive, "derrotado: se retira antes de tiempo")
	check(e.active_eikon == null or not is_instance_valid(e.active_eikon), "el rival puede volver a invocar")
	await physics_frame
	pc.target = gol if is_instance_valid(gol) else null
	pc._update_target(false)
	check(pc.target == e, "si el objetivo cae, el fijado vuelve al rival")
	# --- Eikon montable sin jinete = compañero que ataca ---
	await _place(10.0)
	e.eikon = load("res://resources/eikons/ice_wolf.tres")
	e.meter = Fighter.METER_MAX
	check(e.summon() and e.mounted, "el rival invoca y monta al lobo")
	var wolf: Mount = e.active_eikon
	check(not wolf.is_in_group("damageable"), "montado, el lobo no es objetivo (los golpes van al jinete)")
	e.toggle_mount()
	await physics_frame
	check(not e.mounted and wolf.is_companion() and wolf.is_in_group("damageable") and wolf.health == wolf.max_health, "desmontado: compañero con vida %.0f, fijable" % wolf.health)
	check(wolf in pc.targets(), "el lobo enemigo aparece en el ciclo de objetivos")
	var ph := p.health
	await wait(2.5)
	check(wolf.attacks_done > 0 and p.health < ph, "el lobo sin jinete ataca al jugador (%d ataques, -%.0f)" % [wolf.attacks_done, ph - p.health])
	# Prioriza eikons enemigos: el jugador invoca su Gólem
	p.eikon = load("res://resources/eikons/stone_golem.tres")
	p.meter = Fighter.METER_MAX
	p.stun = 0.0 # ronda 31: el lobo pudo derribarlo (acumulado)
	p.down_t = 0.0
	p.stun_immune_t = 0.0
	p.summon()
	await wait(0.3)
	check(wolf.companion_target == p.active_eikon, "el lobo prioriza al eikon enemigo (gólem)")
	var pg: Eikon = p.active_eikon
	await wait(0.5)
	check(is_instance_valid(pg) and MeshUtil.companion_target(pg.global_position, self, pg.team) == wolf, "el gólem del jugador también prioriza al eikon enemigo")
	# Volver a montar: el dueño pide «Montar» (lo llama) y monta al llegar
	e.global_position = wolf.global_position + Vector3(6, 0, 0)
	var mounted_back := false
	for i in 240:
		await physics_frame
		e.stamina = e.stamina_max
		if e.toggle_mount() and e.mounted:
			mounted_back = true
			break
	check(mounted_back and e.mount_node == wolf, "el dueño lo llama con «Montar» y vuelve a montarlo")
	check(not wolf.is_in_group("damageable"), "remontado deja de ser objetivo")
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
