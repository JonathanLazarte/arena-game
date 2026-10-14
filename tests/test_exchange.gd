extends SceneTree
## Ronda 24: «El intercambio» — contraataque, subtipos físicos, contra de guardia, rotura de postura
## y crítico frontal; fuerte cargado, ataque corriendo y regeneración con guardia (fase 2); IA.
## godot --headless --path . -s res://tests/test_exchange.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func until(cond: Callable, max_t: float = 3.0) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await physics_frame
		t += 1.0 / 60.0
	return cond.call()

func fresh(p: Fighter, e: Fighter, d: float = 1.8) -> void:
	for f: Fighter in [p, e]:
		if f.mounted:
			f.dismount(false)
		if is_instance_valid(f.owned_mount) and f.owned_mount.is_free():
			f.owned_mount.global_position = Vector3(-18.0 if f == p else 18.0, 0.0, 18.0) # lejos: luchan a pie
		f._cancel_attack()
		f.stun = 0.0
		f.stamina = f.stamina_max
		f.health = f.max_health
		f.poise = 1e6 if f == e else f.poise_max
		f.stance = f.stance_max
		f.stance_broken_t = 0.0
		f.blocking = false
		f.want_block = false
		f.guard_counter_t = 0.0
		f.status_fx.reset()
		f.loadout = Fighter.Loadout.SWORD_SHIELD
		f.stance_breaks = 0
	e.global_position = p.global_position + p.facing * d
	e.facing = -p.facing
	await physics_frame

func _run() -> void:
	await process_frame
	# --- Datos ---
	check(Catalog.weapon("lanza").phys_type == "perforante" and Catalog.weapon("hacha_2m").phys_type == "contundente" and Catalog.weapon("dagas").phys_type == "cortante", "subtipos físicos por arma")
	var spear := Catalog.weapon("lanza")
	var thrust := false
	for h in spear.combo:
		thrust = thrust or PhysTypes.of_hit(spear, h) == "perforante"
	check(thrust, "las estocadas son perforantes")
	check(PhysTypes.absorb_mod("pesado", "contundente") < 1.0 and PhysTypes.absorb_mod("pesado", "cortante") > 1.0 and PhysTypes.absorb_mod("ligero", "cortante") < 1.0, "contundente vence a la pesada; cortante rebota en la pesada y destroza la ligera")
	var heavy_eq := {"defensa": 100.0, "absorcion": {"fisico": 0.3}, "clase": "pesado"}
	var ref := {"defensa": 100.0, "absorcion": {"fisico": 0.1}, "clase": "medio"}
	var d_std := EquipStats.incoming(20.0, "fisico", heavy_eq, ref, "estandar")
	var d_str := EquipStats.incoming(20.0, "fisico", heavy_eq, ref, "contundente")
	var d_sla := EquipStats.incoming(20.0, "fisico", heavy_eq, ref, "cortante")
	check(d_str > d_std and d_sla < d_std, "contra armadura pesada: contundente %.1f > estándar %.1f > cortante %.1f" % [d_str, d_std, d_sla])
	check(is_equal_approx(EquipStats.incoming(20.0, "fisico", ref, ref, "cortante"), 20.0), "con la armadura de referencia el nivel 1 no cambia")
	# --- Arena ---
	Arena.start_mounted = false
	Arena.hitstop_enabled = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.controller.set_physics_process(false)
	arena.time_left = 1.0e9
	await create_timer(3.2).timeout
	var p := arena.player
	var e := arena.enemy
	# 1. Contraataque
	await fresh(p, e)
	var base := e.health
	e.take_hit(10.0, p, "melee")
	var normal := base - e.health
	await fresh(p, e)
	var okh := e.attack_heavy() # en anticipación
	await physics_frame
	var pz := e.poise
	base = e.health
	e.take_hit(10.0, p, "melee")
	var ch := base - e.health
	check(is_equal_approx(ch, normal * 1.15) and p.counter_hits == 1, "contraataque: x1,15 de daño (%.2f vs %.2f)" % [ch, normal])
	await fresh(p, e)
	e.poise_max = 1.0e5 # ronda 31: se mide la fuerza acumulada (stun_acc)
	e._reset_stun_meter()
	e.take_hit(10.0, p, "melee")
	var pn := e.stun_acc
	await fresh(p, e)
	e.poise_max = 1.0e5
	e._reset_stun_meter()
	e.attack_heavy()
	await physics_frame
	e.take_hit(10.0, p, "melee")
	var pc := e.stun_acc
	check(pc > pn * 1.25, "contraataque: x1,3 de equilibrio (y x1,15 del daño): %.1f vs %.1f" % [pc, pn])
	# 2. Contra de guardia
	await fresh(p, e)
	p.want_block = true
	await physics_frame
	await physics_frame
	check(p.blocking, "jugador con guardia alzada")
	var r := p.take_hit(10.0, e, "melee")
	check(r == "block" and p.guard_counter_t > 0.0, "bloqueo abre la ventana de contra de guardia")
	p.want_block = false
	p.stun = 0.0
	await physics_frame
	check(p.attack_light() and p.atk_gc and p.atk_heavy, "atacar en la ventana = contra de guardia (fuerte)")
	var gc_wind := p.atk_dur
	check(gc_wind < Catalog.weapon(p.melee().id).heavy_windup * 0.75 / p.attr_speed() + 0.01 or gc_wind < 0.5, "sale más rápido que un fuerte (%.2f s)" % gc_wind)
	var st0 := p.stun
	p.take_hit(5.0, e, "melee")
	check(p.atk_state == Fighter.Atk.WINDUP and p.atk_gc, "súper-armadura: no se interrumpe")
	p.stun = st0
	await fresh(p, e)
	p.want_block = true
	await physics_frame
	await physics_frame
	p.take_hit(10.0, e, "melee")
	p.want_block = false
	await create_timer(0.45).timeout
	p.stun = 0.0
	check(p.attack_light() and not p.atk_gc, "pasados 0,35 s ya no es contra de guardia")
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	# 3. Rotura de postura + crítico frontal
	await fresh(p, e)
	e.poise = e.poise_max
	var hits := 0
	while e.stance_broken_t <= 0.0 and hits < 30:
		e.take_hit(10.0, p, "melee")
		hits += 1
		if e.stance_broken_t > 0.0:
			break
		e.stun = 0.0
		e.stun_immune_t = 0.0 # ronda 31: sin inmunidad de derribo para medir la postura
		e.down_t = 0.0
		e._reset_stun_meter()
	check(e.stance_broken_t > 0.0 and hits > 3, "postura rota tras %d golpes (x%.1f del equilibrio)" % [hits, Fighter.STANCE_MULT])
	await physics_frame
	check(e.stun > 1.0 and e.stance_breaks == 1, "rival expuesto ~1,2 s (%.2f, %d)" % [e.stun, e.stance_breaks])
	e.global_position = p.global_position + p.facing * 1.6
	e.facing = -p.facing
	p.stun = 0.0
	p._cancel_attack()
	await physics_frame
	e.health = e.max_health
	var hp := e.health
	check(p.crit_candidate() == e and p.attack_light() and p.is_criticalling(), "atacar de frente = crítico")
	check(p.invuln > 0.0, "invulnerable durante el crítico")
	check(p.take_hit(10.0, e, "melee") == "dodge", "los golpes no lo tocan durante la animación")
	await until(func() -> bool: return not p.is_criticalling())
	var cd := hp - e.health
	var exp_d := EquipStats.incoming(p.melee().heavy_damage * p.damage_mult() * Fighter.CRIT_MULT, "fisico", e.eq, e.eq_ref, p.melee().phys_type)
	check(p.crits == 1 and absf(cd - exp_d) < 0.5, "crítico x2,2 del fuerte (%.1f, esperado %.1f)" % [cd, exp_d])
	await fresh(p, e)
	e.stance_broken_t = 1.0
	e.stun = 1.0
	e.facing = p.facing # de espaldas a mí
	await physics_frame
	check(p.crit_candidate() == null, "no hay crítico frontal desde la espalda")
	await fresh(p, e)
	# Postura se recupera
	e.stance = 10.0
	e._since_hit = 0.0
	await create_timer(Fighter.STANCE_DELAY + 0.6).timeout
	check(e.stance > 10.0, "la postura se recupera tras %.1f s sin golpes" % Fighter.STANCE_DELAY)
	# 4. Fase 2: fuerte cargado
	await fresh(p, e, 1.8)
	e.poise = 1e6
	p.want_charge = false
	p.attack_heavy()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	var hp_a := e.health
	await fresh(p, e, 1.8)
	e.health = hp_a
	var h_before := e.health
	await fresh(p, e, 1.8)
	var hb := e.health
	p.want_charge = false
	p.attack_heavy()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY)
	var dmg_plain := hb - e.health
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	await fresh(p, e, 1.8)
	hb = e.health
	p.want_charge = true
	p.attack_heavy()
	await until(func() -> bool: return p.atk_state == Fighter.Atk.RECOVERY, 4.0)
	p.want_charge = false
	var dmg_charged := hb - e.health
	check(p.charge_t > 0.5 and dmg_charged > dmg_plain * 1.3, "fuerte cargado: más daño (%.1f vs %.1f)" % [dmg_charged, dmg_plain])
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	# 5. Ataque corriendo
	await fresh(p, e, 5.0)
	p.move_input = p.facing
	p.want_sprint = true
	await create_timer(0.4).timeout
	check(p.sprinting, "corriendo")
	p.attack_light()
	check(p.running_attacks == 1 and p.atk_dash, "ataque corriendo = embestida")
	p.move_input = Vector3.ZERO
	p.want_sprint = false
	await until(func() -> bool: return p.atk_state == Fighter.Atk.NONE)
	# 6. Regeneración con guardia alzada
	await fresh(p, e, 6.0)
	p.stamina = 20.0
	p._since_spend = 5.0
	await create_timer(0.5).timeout
	var free_regen := p.stamina - 20.0
	p.stamina = 20.0
	p.want_block = true
	await physics_frame
	p._since_spend = 5.0
	await create_timer(0.5).timeout
	var blk_regen := p.stamina - 20.0
	p.want_block = false
	check(blk_regen < free_regen * 0.7, "guardia alzada: regenera la mitad (%.1f vs %.1f)" % [blk_regen, free_regen])
	# 7. IA: crítico sobre el jugador con la postura rota y contra de guardia
	arena.ai.profile = load("res://resources/ai/hard.tres")
	arena.ai.enabled = true
	await fresh(p, e, 3.0)
	e.poise = e.poise_max
	p.stance = 1.0
	p.poise = 1.0
	p.take_hit(5.0, e, "melee")
	check(p.stance_broken_t > 0.0, "jugador con la postura rota")
	await until(func() -> bool: return e.crits > 0, 2.0)
	check(e.crits > 0 and arena.ai.crits_tried > 0, "la IA aprovecha la postura rota con un crítico")
	await until(func() -> bool: return not e.is_criticalling())
	p.health = p.max_health
	await create_timer(1.0).timeout
	var gct := 0
	for i in 6:
		await fresh(p, e, 1.8)
		e.want_block = true
		arena.ai._block_hold = 0.6
		await physics_frame
		await physics_frame
		if e.blocking:
			e.take_hit(8.0, p, "melee")
		await create_timer(0.3).timeout
		gct = e.guard_counters
		if gct > 0:
			break
	check(gct > 0, "la IA usa la contra de guardia tras bloquear")
	arena.ai.enabled = false
	check(arena.ai.profile.delay_chance > 0.0, "la IA tiene golpes retrasados (perfil)")
	Arena.hitstop_enabled = true
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(1 if fails > 0 else 0)
