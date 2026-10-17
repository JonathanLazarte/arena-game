extends SceneTree
## Fase 4: habilidades de jefe (las 13 + estocada), magia, eikons/monturas y presas bajo rollback a
## 100/200 ms con entradas aleatorias que incluyen los botones nuevos: 0 desincronías.
## godot --headless --path . -s res://tests/test_net_abilities.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _fighter(boss: Array, spells: Array, eikon: String) -> Fighter:
	var f := Fighter.new()
	f.eikon = load(Catalog.EIKONS[eikon])
	f.set_magic(spells, "")
	f.set_boss_abilities(boss)
	root.add_child(f)
	return f

func _run() -> void:
	var ids: Array = BossAbilities.all_ids()
	check(ids.size() >= 13, "%d habilidades de jefe" % ids.size())
	var eks := ["fenix", "lobo", "golem", "grifo"]
	var spells := EikonSpells.DEFS.keys()
	var tot := {"starts": 0, "spells": 0, "summons": 0, "grabs": 0, "hits": 0}
	var k := 0
	for g in range(0, ids.size(), 3):
		var A := _fighter(ids.slice(g, g + 3), spells.slice(0, 4), eks[k % eks.size()])
		var B := _fighter(ids.slice((g + 3) % ids.size(), (g + 3) % ids.size() + 3), spells.slice(1, 5), eks[(k + 1) % eks.size()])
		await process_frame
		var P := SimParams.bake(A, B)
		for i in 2: P[i]["meter0"] = 100000 # eikon disponible desde el principio
		A.queue_free(); B.queue_free()
		var rtt := 100 if k % 2 == 0 else 200
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.jitter_ms = 15.0; h.loss = 0.03; h.seed_v = 11 + k
		h.bot_mask = 0xFFFFF & ~FightSim.IN_SWAP & ~FightSim.IN_BLOCK; h.bot_or = FightSim.IN_LOCK; h.bot_change = 0.2
		h.engine_factory = func() -> RbEngine: var e := FightEngine.new(P, 9, true); e.gap_um = 3000000; return e
		var r := h.run(1500)
		var s: PackedInt64Array = r["state"]
		var c := {"starts": 0, "spells": 0, "summons": 0, "grabs": 0, "hits": 0}
		for i in 2:
			var o := i * FightSim.F_FIELDS
			c["starts"] += s[o + FightSim.AB_STARTS]; c["spells"] += s[o + FightSim.SPELLS]
			c["summons"] += s[o + FightSim.SUMMONS]; c["grabs"] += s[o + FightSim.GRABS]; c["hits"] += s[o + FightSim.AB_HITS]
		for key in c: tot[key] += c[key]
		check(r["mismatches"] == 0 and r["final_equal"] and r["common"] > 1300,
			"%s vs %s, RTT %d: 0 desincronías (%d confirmados) %s" % [str(ids.slice(g, g + 3)), eks[k % eks.size()], rtt, r["common"], str(c)])
		k += 1
	check(tot["starts"] > 0 and tot["spells"] > 0 and tot["summons"] > 0, "se usaron habilidades, hechizos e invocaciones: %s" % str(tot))
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
