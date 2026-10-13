extends SceneTree
## Ronda 4: combate estilo souls, armas (espada+escudo O arco), parry de 1 s y lectura de la IA.
## godot --headless --path . -s res://tests/test_souls.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func wait(s: float) -> void:
	await create_timer(s).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	await physics_frame
	Input.action_release(action)

func idle(f: Fighter) -> void:
	while f.atk_state != Fighter.Atk.NONE or f.stun > 0.0:
		await physics_frame

func idle_atk(f: Fighter) -> void:
	while f.atk_state != Fighter.Atk.NONE:
		await physics_frame

func place(p: Fighter, e: Fighter, d: float) -> void:
	e.global_position = p.global_position + p.facing * d
	e.facing = -p.facing
	await physics_frame

func _run() -> void:
	Arena.start_mounted = true # combate montado clásico (ronda 14: por defecto se empieza a pie)
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	await process_frame
	var arena: Arena = current_scene as Arena
	arena.time_left = 1.0e9 # sin límite de tiempo de ronda durante la prueba
	seed(4)
	var p := arena.player
	var e := arena.enemy
	arena.ai.enabled = false
	e.knockoff_chance_dash = 0.0 # derribos aleatorios fuera de la prueba de fuerte
	e.knockoff_chance_heavy = 0.0
	p.knockoff_chance_dash = 0.0
	p.knockoff_chance_heavy = 0.0
	e.max_health = 2000.0
	e.health = 2000.0
	p.max_health = 2000.0
	p.health = 2000.0
	await wait(0.5)
	await place(p, e, 3.0)
	await wait(0.3)

	# --- 1. Compromiso: no se puede spamear ---
	var h0 := e.health
	var a0 := p.attacks_started
	var t := 0.0
	while t < 4.0:
		await tap("attack_sword")
		await wait(0.05)
		t += 0.1
		p.stamina = Fighter.STAMINA_MAX
	await idle(p)
	var dmg := h0 - e.health
	var old_dmg := 12.0 * floorf((4.0 - 0.18) / 0.7 + 1.0)
	check(dmg > 0.0 and dmg < old_dmg, "spam 4 s: daño %.0f < sistema antiguo %.0f (DPS menor)" % [dmg, old_dmg])
	check(p.attacks_started - a0 <= 5, "ataques iniciados en 4 s: %d (≤5, combos de máx. 3)" % (p.attacks_started - a0))
	# --- 2. Durante la anticipación/recuperación no hay otras acciones ---
	await wait(0.5)
	p.attack_light()
	await physics_frame
	Input.action_press("block")
	await physics_frame
	await physics_frame
	# Ronda 9: montado SÍ se puede hacer dash durante la anticipación (dash + ataque, ver test_dash_attack)
	var no_actions := not p.shoot() and not p.swap_loadout() and not p.toggle_mount() and not p.blocking
	Input.action_release("block")
	check(p.is_attacking() and no_actions, "en anticipación: sin arco, cambio, montar ni escudo")
	while not (p.in_recovery() and p.atk_t < p.atk_dur * 0.4):
		await physics_frame
	check(not p.dash(), "recuperación temprana: no se puede cancelar con dash")
	while not (p.in_recovery() and p.atk_t >= p.atk_dur * 0.5):
		await physics_frame
	check(p.dash(), "recuperación tardía: se puede cancelar con voltereta/dash")
	await idle(p)
	await wait(1.0)
	# --- 3. Fallar el golpe = recuperación más larga, castigable ---
	arena.controller.lock_on = false
	await physics_frame
	await place(p, e, 3.0)
	p.attack_light()
	while not p.in_recovery():
		await physics_frame
	var hit_rec := p.atk_dur
	await idle(p)
	await wait(0.3)
	e.global_position = p.global_position - p.facing * 3.2 # detrás: fuera del arco
	e.facing = p.facing.rotated(Vector3.UP, PI)
	e.face_target = p
	await idle(e)
	await physics_frame
	var opened := [false]
	var cb := func(_tt: Node3D, res: String, was_open: bool) -> void:
		if res == "hit" and was_open:
			opened[0] = true
	e.landed_hit.connect(cb)
	p.attack_light()
	while p.atk_state != Fighter.Atk.ACTIVE:
		await physics_frame
	e.attack_light()
	while not p.in_recovery():
		await physics_frame
	var whiff_rec := p.atk_dur
	while e.atk_state != Fighter.Atk.NONE:
		await physics_frame
	check(whiff_rec > hit_rec, "golpe fallado: recuperación %.2f s > acertado %.2f s" % [whiff_rec, hit_rec])
	await idle(e)
	await idle(p)
	check(opened[0], "el rival castiga la recuperación del golpe fallado")
	e.landed_hit.disconnect(cb)
	e.face_target = null
	arena.controller.lock_on = true
	await wait(0.5)
	# --- 4. Ataque fuerte (mantener) ---
	await place(p, e, 3.0)
	await wait(0.3)
	e.knockoff_chance_heavy = 1.0
	h0 = e.health
	var st0 := p.stamina
	Input.action_press("attack_sword")
	await wait(0.5)
	check(p.atk_heavy and p.is_attacking() and p.atk_dur >= 0.75, "mantener 0,4 s = ataque fuerte (anticipación %.2f s)" % p.atk_dur)
	var heavy_cost := st0 - p.stamina
	Input.action_release("attack_sword")
	await idle(p)
	check(h0 - e.health >= 25.0, "fuerte hace más daño (%.0f)" % (h0 - e.health))
	check(heavy_cost >= 27.0, "fuerte gasta más aguante (%.0f vs ligero %.0f)" % [heavy_cost, Fighter.LIGHT["stamina"]])
	check(not e.mounted, "fuerte puede derribar de la montura")
	e.knockoff_chance_heavy = 0.0
	await idle(e)
	e.global_position = e.owned_mount.global_position
	e.toggle_mount()
	await wait(0.6)
	# --- 5. Poise / intercambio: un golpe interrumpe el ligero del rival ---
	await place(p, e, 3.0)
	await wait(0.3)
	var ph := p.health
	p.attack_light()
	await wait(0.2)
	e.attack_light()
	await idle(p)
	await idle(e)
	check(is_equal_approx(p.health, ph), "golpear primero interrumpe el ataque ligero del rival (sin intercambio gratis)")
	await wait(0.8)
	# --- 6. Cambio de arma: 2 s sin atacar ni bloquear ---
	await tap("swap_weapon")
	var swap_ok := true
	var hud_ok := false
	var tt := 0.0
	Input.action_press("block")
	while tt < Fighter.SWAP_TIME - 0.05:
		await physics_frame
		tt += 1.0 / 60.0
		if p.attack_light() or p.shoot() or p.blocking:
			swap_ok = false
		if arena.hud.swap_bar.visible and arena.hud.swap_bar.value > 0.3:
			hud_ok = true
	Input.action_release("block")
	check(swap_ok and p.is_swapping(), "durante el cambio (~0,4 s) no se ataca, dispara ni bloquea")
	check(hud_ok, "HUD muestra progreso del cambio")
	await wait(0.3)
	check(p.loadout == Fighter.Loadout.BOW and p._bow.visible and not p._shield.visible, "tras el cambio: arco equipado (malla cambiada)")
	# --- 7. Modo arco: sin escudo ---
	Input.action_press("block")
	await wait(0.3)
	var blk := p.blocking
	var res := p.take_hit(5.0, e, "melee")
	Input.action_release("block")
	p.stun = 0.0 # ronda 17: el golpe aturde (hitstun); no es lo que se prueba aquí
	check(not blk and res == "hit", "en modo arco no hay bloqueo con escudo")
	check(not p.attack_light(), "en modo arco no hay espada")
	await tap("swap_weapon")
	await wait(Fighter.SWAP_TIME + 0.2)
	check(p.loadout == Fighter.Loadout.SWORD_SHIELD, "vuelta a espada + escudo")
	# --- 8. Parry dedicado (ventana 0,3 s + recuperación vulnerable) --- (ronda 21: solo a pie)
	if p.mounted:
		p.dismount(false)
	await wait(0.4)
	await place(p, e, 3.0)
	await wait(0.5)
	var results: Array[String] = []
	var cb2 := func(_tt: Node3D, r: String, _o: bool) -> void: results.append(r)
	e.landed_hit.connect(cb2)
	e.attack_light()
	await wait(0.25)
	var st_p := p.stamina
	await tap("parry") # ~0,2 s antes del impacto: dentro de la ventana de 0,3 s
	check(st_p - p.stamina >= Fighter.COST_PARRY - 1.0, "parry gasta aguante")
	await idle_atk(e)
	check(results.size() > 0 and results[-1] == "parry", "parry ~0,2 s antes del golpe = éxito (%s)" % str(results))
	check(p.parry_state == Fighter.Parry.NONE, "parry con éxito no deja recuperación")
	check(e.stun > 0.8 and e.riposte_t > 0.0, "parry aturde más al atacante (%.2f s)" % e.stun)
	h0 = e.health
	await physics_frame
	await physics_frame
	await idle(p)
	e.dismount(false) # a pie contra a pie (la espada a pie no alcanza a un jinete)
	e.global_position = p.global_position + p.facing * 1.5
	p.attack_light()
	await idle(p)
	check(h0 - e.health > Fighter.LIGHT["damage"] + 1.0, "riposte con daño extra (%.1f)" % (h0 - e.health))
	await idle(e)
	await idle_atk(p)
	e.owned_mount.global_position = e.global_position
	e.mount_on(e.owned_mount)
	await wait(0.5)
	await place(p, e, 3.0)
	var n_res := results.size()
	# El escudo ya no hace parry: alzarlo justo antes = bloqueo normal
	e.attack_light()
	await wait(0.3)
	Input.action_press("block")
	await idle_atk(e)
	Input.action_release("block")
	check(results.size() > n_res and results[-1] == "block", "escudo alzado justo antes = solo bloqueo (%s)" % results[-1])
	await idle(e)
	await wait(0.3)
	# Parry demasiado pronto: falla y queda expuesto (+25 % daño)
	ph = p.health
	await tap("parry")
	await wait(0.2)
	e.attack_light() # impacta ~0,65 s después del parry: ya en recuperación
	await idle_atk(e)
	var exposed_dmg := ph - p.health
	check(results[-1] == "hit" and absf(exposed_dmg - (e.combo_hit_for(1).damage if e.combo_hit_for(1) else Fighter.LIGHT["damage"]) * e.damage_mult() * Fighter.PARRY_EXPOSED_MULT) < 0.1, "parry fallido: expuesto, recibe +25%% (%.1f)" % exposed_dmg)
	await idle(e)
	await idle(p)
	await tap("parry")
	await wait(Fighter.PARRY_WINDOW + 0.05)
	Input.action_press("block")
	await physics_frame
	await physics_frame
	check(p.parry_state == Fighter.Parry.RECOVERY and not p.blocking and not p.attack_light() and not p.dash(), "recuperación de parry: sin bloqueo, ataque ni dash")
	Input.action_release("block")
	await wait(1.0)
	await tap("swap_weapon")
	await wait(Fighter.SWAP_TIME + 0.2)
	check(not p.parry(), "sin parry en modo arco")
	await tap("swap_weapon")
	await wait(Fighter.SWAP_TIME + 0.2)
	e.landed_hit.disconnect(cb2)
	for f: Fighter in [p, e]: # vuelve al combate montado clásico
		if not f.mounted and is_instance_valid(f.owned_mount):
			f.owned_mount.global_position = f.global_position
			f.mount_on(f.owned_mount)
	await wait(0.3)
	# --- 9. La IA lee ataques: esquiva y castiga; se compromete con los suyos ---
	await wait(0.5)
	arena.ai.enabled = true
	arena.ai.profile = load("res://resources/ai/normal.tres") # capacidades de lectura: perfil normal
	var e_attacked_recovery := false
	for i in 14:
		p.health = p.max_health
		p.stamina = Fighter.STAMINA_MAX
		await idle(p)
		await place(p, e, 3.0)
		await physics_frame
		p.attack_light() if i % 3 != 2 else p.attack_heavy()
		var w := 0.0
		while w < 2.0:
			await physics_frame
			w += 1.0 / 60.0
			if e.in_recovery():
				e_attacked_recovery = true
	print("IA: esquivas=%d parries=%d castigos=%d" % [arena.ai.dodges, arena.ai.parries_tried, arena.ai.punish_hits])
	check(arena.ai.dodges + arena.ai.parries_tried > 0, "la IA reacciona (esquiva o parry)")
	check(arena.ai.dodges > 0, "la IA esquiva ataques telegrafiados (%d)" % arena.ai.dodges)
	check(arena.ai.punish_hits > 0, "la IA castiga durante la recuperación (%d)" % arena.ai.punish_hits)
	check(e_attacked_recovery, "la IA también queda en recuperación tras sus ataques (castigable)")
	print("RESULT: %s (%d fallos)" % ["OK" if fails == 0 else "FALLO", fails])
	quit(fails)
