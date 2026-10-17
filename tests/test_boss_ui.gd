extends SceneTree
## Fase 9: habilidades de jefe — icono y nombre propios, 3.ª del campeón oculta hasta la Fase II,
## y cambio de habilidad (IN_BOSS_NEXT) como flanco de entrada fiable bajo rollback.
## godot --headless --path . -s res://tests/test_boss_ui.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(boss: Array) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS["fenix"])
	f.set_boss_abilities(boss)
	root.add_child(f)
	return f

func _run() -> void:
	# --- iconos y nombres ---
	var digits := RegEx.create_from_string("[0-9]")
	for id: String in BossAbilities.all_ids():
		check(BossIcon.has_glyph(id), "%s: icono vectorial propio" % id)
		var sn := BossAbilities.short_name(id)
		check(sn != "" and digits.search(sn) == null and sn.length() <= 12, "%s: nombre corto «%s»" % [id, sn])
	var seen := {}
	for id: String in BossAbilities.all_ids():
		seen[BossAbilities.short_name(id)] = true
	check(seen.size() == BossAbilities.all_ids().size(), "nombres cortos distintos")
	# --- disponibilidad: el campeón guarda la 3.ª hasta la Fase II ---
	var A := _fighter(["estocada", "rafaga", "combo_falso"])
	var B := _fighter(["carga_area", "onda_rastrera", "lluvia_meteoros"])
	await process_frame
	var P := SimParams.bake(A, B)
	P[1]["boss_n"] = 2
	var eng := FightEngine.new(P, 1, true)
	var s := eng.initial()
	var view := SimView.new(A, B, null)
	view.params = P
	view.apply(s)
	check(B.avail_boss_ids() == ["carga_area", "onda_rastrera"], "antes de la Fase II: 2 habilidades visibles (%s)" % [B.avail_boss_ids()])
	var hud := HUD.new()
	root.add_child(hud)
	await process_frame
	hud.bind(A, B)
	hud.show_enemy_bosses = true
	hud._update_enemy_strip()
	check(hud.enemy_boss_strip.get_child_count() == 2 and hud.enemy_boss_strip.visible, "HUD del campeón: 2 iconos")
	# ciclar con la 3.ª bloqueada no la selecciona
	var sel := []
	for k in 6:
		eng.step(s, 0, FightSim.IN_BOSS_NEXT if k % 2 == 0 else 0)
		sel.append(s[FightSim.F_FIELDS + FightSim.AB_SEL])
	check(sel.max() <= 1, "▶ no llega a la 3.ª antes de la Fase II (%s)" % [sel])
	s[FightSim.F_FIELDS + FightSim.PH2] = 1
	view.apply(s)
	await process_frame
	hud._update_enemy_strip()
	await process_frame
	check(B.avail_boss_ids().size() == 3 and hud.enemy_boss_strip.get_child_count() == 3, "Fase II: aparece la 3.ª (%d iconos)" % hud.enemy_boss_strip.get_child_count())
	hud.queue_free()
	# --- flanco de cambio bajo rollback ---
	var P2 := SimParams.bake(A, A)
	A.queue_free(); B.queue_free()
	for rtt in [60, 160]:
		var taps := [30, 31, 32, 90, 150, 151, 210, 400, 401, 402, 403, 600, 650]
		var expected := 0
		var prev := false
		for t in 700:
			var on := t in taps
			if on and not prev:
				expected += 1
			prev = on
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.jitter_ms = 15.0; h.loss = 0.05; h.seed_v = 5 + rtt
		h.bot_mask = FightSim.IN_DIR_MASK | FightSim.IN_MOVE
		h.engine_factory = func() -> RbEngine: return FightEngine.new(P2, 9, true)
		h.input_fn = func(i: int, t: int, bot: int) -> int:
			return (bot | FightSim.IN_BOSS_NEXT) if (i == 0 and t in taps) else bot
		var r := h.run(700)
		var ps := h.last_peers
		var s0: PackedInt64Array = ps[0].state
		var s1: PackedInt64Array = ps[1].state
		check(r["mismatches"] == 0, "%d ms: sin desincronías" % rtt)
		check(s0[FightSim.AB_SEL] == expected % 3 and s1[FightSim.AB_SEL] == expected % 3, "%d ms: %d flancos → selección %d en ambos pares (%d / %d)" % [rtt, expected, expected % 3, s0[FightSim.AB_SEL], s1[FightSim.AB_SEL]])
		check(r["rollbacks_per_tick"] > 0.0, "%d ms: hubo rollbacks (%.2f/tick)" % [rtt, r["rollbacks_per_tick"]])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
