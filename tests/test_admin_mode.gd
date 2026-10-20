extends SceneTree

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	await process_frame
	print("=== RUNNING ADMIN MODE & COMBO TESTS ===")
	
	# 1. Test AdminMode toggle
	AdminMode.enabled = false
	check(not AdminMode.enabled, "AdminMode initially disabled")
	AdminMode.toggle()
	check(AdminMode.enabled, "AdminMode toggles to enabled")
	AdminMode.toggle()
	check(not AdminMode.enabled, "AdminMode toggles to disabled")
	
	# 2. Test SimMatch with AdminMode
	var dummy_parent = Node3D.new()
	root.add_child(dummy_parent)
	await process_frame
	
	var p_fighter := Fighter.new()
	var e_fighter := Fighter.new()
	var w := load("res://resources/weapons/espada_escudo.tres") as WeaponDef
	p_fighter.weapon = w
	e_fighter.weapon = w
	p_fighter.boss_ids = ["combo_falso"]
	e_fighter.boss_ids = ["combo_falso"]
	dummy_parent.add_child(p_fighter)
	dummy_parent.add_child(e_fighter)
	
	var sim = SimMatch.new()
	dummy_parent.add_child(sim)
	sim.setup(p_fighter, e_fighter, dummy_parent)
	sim.reset_round()
	sim.running = false
	sim.set_physics_process(false)
	
	check(p_fighter.boss_ids.size() == 1, "Player initial boss_ids size is 1")
	
	# Enable Admin Mode
	AdminMode.enabled = true
	sim.step_once()
	
	# Verify infinite resources on player
	var po := 0 * FightSim.F_FIELDS
	var eo := 1 * FightSim.F_FIELDS
	check(sim.state[po + FightSim.HP] == int(sim.params[0]["hp"]), "Player HP at max in AdminMode")
	check(sim.state[po + FightSim.ST] == int(sim.params[0]["st_max"]), "Player stamina at max in AdminMode")
	check(sim.state[po + FightSim.MANA] == int(sim.params[0]["mana_max"]), "Player mana at max in AdminMode")
	check(sim.state[po + FightSim.FLASKS] == 5, "Player flasks at 5 in AdminMode")
	check(sim.state[po + FightSim.METER] == 100000, "Player meter at max (eikon ready) in AdminMode")
	
	# Verify all abilities unlocked in Admin Mode
	check(p_fighter.boss_ids.size() == BossAbilities.all_ids().size(), "All %d boss abilities equipped in AdminMode" % BossAbilities.all_ids().size())
	check(sim.params[0]["boss"].size() == BossAbilities.all_ids().size(), "All %d boss abilities compiled in params" % BossAbilities.all_ids().size())
	
	# Test cycling and selecting abilities
	sim.select_boss_ability(10)
	check(sim.state[po + FightSim.AB_SEL] == 10, "Ability selection set to 10")
	sim.cycle_boss_prev()
	check(sim.state[po + FightSim.AB_SEL] == 9, "cycle_boss_prev went to 9")
	
	# Verify enemy immortality (drops HP on damage, but regenerates before death)
	var e_max_hp := int(sim.params[1]["hp"])
	sim.state[eo + FightSim.HP] = 20000 # drops below 30%
	sim.step_once()
	check(sim.state[eo + FightSim.HP] == e_max_hp, "Immortal enemy regenerates back to full HP (%d)" % e_max_hp)
	check(sim.state[eo + FightSim.ALIVE] == 1, "Immortal enemy alive status is 1")
	check(sim.state[FightSim.P_BASE + FightSim.G_END_T] == 0, "Round end timer reset to 0 (fight never ends)")
	
	# Test disabling AdminMode restores original setup
	AdminMode.enabled = false
	check(p_fighter.boss_ids.size() == 1, "Disabling AdminMode restores original 1 ability")
	check(sim.params[0]["boss"].size() == 1, "Disabling AdminMode restores original compiled params")
	
	# 3. Combo de habilidades (jefes mayores / Hoja Escarlata)
	# Equip an ability with branch: 'pisoton_telurico' y 'danza_espirales'
	p_fighter.boss_ids = ["pisoton_telurico", "danza_espirales"]
	sim.params[0]["boss"] = SimAbilities.compile_all(p_fighter)
	sim.params[0]["boss_n"] = p_fighter.boss_ids.size()
	sim.engine.params[0]["boss"] = sim.params[0]["boss"]
	sim.engine.params[0]["boss_n"] = p_fighter.boss_ids.size()
	sim.select_boss_ability(0)
	
	# Press ability to start it
	sim.state[po + FightSim.AB_SLOT] = 0
	sim.state[po + FightSim.AB_T] = 1
	sim.state[po + FightSim.AB_FIRED] = 0
	sim.state[po + FightSim.AB_FL] = SimAbilities.FL_CATALOG
	
	var cinfo: Dictionary = SimAbilities.combo_info(sim.state, sim.params, 0)
	check(cinfo.get("can_combo", false), "pisoton_telurico reports can_combo = true")
	check(cinfo.get("active", false), "combo_info active = true immediately from start of attack (buffer open)")
	check(is_equal_approx(float(cinfo.get("progress", 0.0)), 1.0), "pisoton_telurico progress is 1.0 before button touch")
	
	# Early buffer test: latch immediately at tick 2 (during windup)
	sim.state[po + FightSim.AB_T] = 2
	var latched_early := SimCatalog.latch(sim.state, sim.params, 0, false)
	check(latched_early, "SimCatalog.latch succeeds early during windup (buffered)")
	var cinfo_queued: Dictionary = SimAbilities.combo_info(sim.state, sim.params, 0)
	check(cinfo_queued.get("queued", false), "combo_info queued = true after early buffer")
	check(is_equal_approx(float(cinfo_queued.get("progress", 0.0)), 1.0), "pisoton_telurico progress updates immediately to 1.0 (full, 2-step combo) upon touching the button")
	
	# Test changing queued choice to variation (alt)
	var latched_var := SimCatalog.latch(sim.state, sim.params, 0, true)
	check(latched_var, "SimCatalog.latch switches queued choice to variation")
	check((sim.state[po + FightSim.AB_FL] & SimAbilities.FL_VARIANT) != 0, "FL_VARIANT set on player")
	
	# 4. Test Per-Slot Cooldowns (no global CD blocking other abilities)
	sim.state[po + FightSim.AB_SLOT] = -1 # Finish ability
	sim.state[po + FightSim.BCD_BASE + 0] = 300 # Slot 0 on cooldown (5s)
	sim.state[po + FightSim.BCD_BASE + 1] = 0   # Slot 1 is READY (0s)
	
	# Check Slot 0 cannot be used
	sim.select_boss_ability(0)
	check(not SimAbilities.can_use(sim.state, sim.params, 0, 0), "Slot 0 is blocked while its cooldown > 0")
	
	# Check Slot 1 CAN be used immediately! (Switching abilities is not locked by Slot 0)
	sim.select_boss_ability(1)
	check(SimAbilities.can_use(sim.state, sim.params, 0, 1), "Slot 1 CAN be used immediately despite Slot 0 on CD (no global CD)")
	check(sim.state[po + FightSim.BOSS_CD] == 0, "BOSS_CD reflects ready Slot 1 (0 ticks)")
	
	# In Admin Mode, even Slot 0 with CD can be used (CD bypassed)
	AdminMode.enabled = true
	sim.select_boss_ability(0)
	check(SimAbilities.can_use(sim.state, sim.params, 0, 0), "AdminMode allows using Slot 0 even with cooldown (bypassed)")
	AdminMode.enabled = false
	
	# 5. Check Static combo progress (Pausa Falsa style: 2-hit combo with 1st step gives 0.5)
	check(is_equal_approx(float(cinfo_queued.get("progress", 0.0)), 1.0), "pisoton_telurico static progress is exactly 1.0 (2-step combo, full)")

	# 6. Check cooldown starts on press and counts down
	sim.state[po + FightSim.BCD_BASE + 0] = 0
	sim.state[po + FightSim.AB_SLOT] = -1
	sim.select_boss_ability(0)
	var pressed := SimAbilities.press(sim.state, sim.params, 0)
	check(pressed, "SimAbilities.press succeeds for Slot 0")
	var initial_cd: int = sim.state[po + FightSim.BCD_BASE + 0]
	check(initial_cd > 0, "Slot 0 cooldown starts immediately on press (got %d ticks)" % initial_cd)
	# Update tick decrements the cooldown while ability is still running
	SimAbilities.update(sim.state, sim.params, 0)
	check(sim.state[po + FightSim.BCD_BASE + 0] == initial_cd - 1, "Slot 0 cooldown counts down each tick")

	# 7. Check Variation only allowed on steps with variation
	p_fighter.boss_ids = ["martillo_alba"] # Step 0: apertura (no alt), Step 1: segundo_golpe (has alt "Barrido")
	sim.params[0]["boss"] = SimAbilities.compile_all(p_fighter)
	sim.params[0]["boss_n"] = 1
	sim.engine.params[0]["boss"] = sim.params[0]["boss"]
	sim.engine.params[0]["boss_n"] = 1
	sim.select_boss_ability(0)
	sim.state[po + FightSim.AB_SLOT] = 0
	sim.state[po + FightSim.AB_FL] = SimAbilities.FL_CATALOG
	sim.state[po + FightSim.AB_T] = 5
	sim.state[po + FightSim.AB_FIRED] = 0 # Step 0: Apertura (no variation)
	check(not SimAbilities.alt_window(sim.state, sim.params, 0), "alt_window is false on Step 0 (no variation on this step)")
	check(not SimCatalog.latch(sim.state, sim.params, 0, true), "latch with alt fails on Step 0")
	sim.state[po + FightSim.AB_FIRED] = 1 # Step 1: Segundo golpe (has variation "Barrido")
	check(SimAbilities.alt_window(sim.state, sim.params, 0), "alt_window is true on Step 1 (variation available at this combo point)")
	check(SimCatalog.latch(sim.state, sim.params, 0, true), "latch with alt succeeds on Step 1")

	# 8. Check Salto con Caída elevation into the air
	p_fighter.boss_ids = ["salto_caida"]
	sim.params[0]["boss"] = SimAbilities.compile_all(p_fighter)
	sim.params[0]["boss_n"] = 1
	sim.engine.params[0]["boss"] = sim.params[0]["boss"]
	sim.engine.params[0]["boss_n"] = 1
	sim.select_boss_ability(0)
	sim.state[po + FightSim.AB_SLOT] = 0
	sim.state[po + FightSim.AB_FL] = 0
	sim.state[po + FightSim.AB_T] = 40 # Middle of jump: hover at apex
	var ab_salto: Dictionary = sim.params[0]["boss"][0]
	SimAbilities._salto(sim.state, sim.params, 0, ab_salto)
	check(sim.state[po + FightSim.FY] == 6000000, "salto_caida elevates to apex height (6,000,000 um / 6.0m)")
	check(sim.state[po + FightSim.AIR] == 1, "salto_caida sets AIR flag to 1")
	# Landing
	sim.state[po + FightSim.AB_T] = int(ab_salto["land"]) + 1
	SimAbilities._salto(sim.state, sim.params, 0, ab_salto)
	check(sim.state[po + FightSim.FY] == 0, "salto_caida resets FY to 0 upon landing")
	check(sim.state[po + FightSim.AIR] == 0, "salto_caida resets AIR to 0 upon landing")
	
	AdminMode.on_toggled = Callable()
	AdminMode.enabled = false
	dummy_parent.free()
	
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
