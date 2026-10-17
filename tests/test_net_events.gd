extends SceneTree
## Fase 1: efectos derivados de eventos sin repetición al re-simular, y comprobación de params al empezar.
## godot --headless --path . -s res://tests/test_net_events.gd
var fails := 0
func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	var P := SimParams.defaults()
	var rates := {}
	for combo in [[50, 0], [100, 0], [200, 0], [50, 2], [100, 2], [200, 2]]:
		var rtt: int = combo[0]; var hold: int = combo[1]
		var fxs: Array[SimFx] = []
		var counts: Array[Dictionary] = [{}, {}]
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.seed_v = 3 + rtt
		h.bot_mask = 0x3FFF; h.bot_or = FightSim.IN_LOCK
		h.engine_factory = func() -> RbEngine:
			var e := FightEngine.new(P)
			var fx := SimFx.new(); fx.keep_frames = 1 << 30
			var idx := fxs.size()
			fx.hold_ticks = hold; fx.local_slot = idx
			fx.callback = func(ev: Dictionary) -> void:
				counts[idx][ev["key"]] = int(counts[idx].get(ev["key"], 0)) + 1
			e.fx = fx; fxs.append(fx)
			return e
		var r := h.run(1200)
		var ps := h.last_peers
		var upto := mini(ps[0].last_remote, ps[1].last_remote) - 1
		upto = mini(upto, mini(ps[0].frame, ps[1].frame) - 1)
		# referencia sin rollback con las entradas confirmadas
		var ref := FightEngine.new(P); var rfx := SimFx.new(); rfx.keep_frames = 1 << 30
		ref.fx = rfx
		var s := ref.initial()
		for t in upto + 1:
			ref.step(s, int(ps[0].local_in.get(t, 0)), int(ps[1].local_in.get(t, 0)))
		var refk := {}
		for k: String in rfx.fired: refk[k] = true
		var ok_all := true
		var missing := 0
		var dup := 0
		var spur := 0
		for i in 2:
			for k: String in counts[i]:
				if counts[i][k] > 1: dup += 1
			for k: String in refk:
				if not fxs[i].fired.has(k):
					ok_all = false
					missing += 1
			fxs[i].confirm(upto, refk)
			spur += fxs[i].spurious
		check(r["mismatches"] == 0, "%d ms/r%d: sin divergencia" % [rtt, hold])
		check(dup == 0, "%d ms/r%d: ningún efecto se repite al re-simular (bloqueados %d)" % [rtt, hold, fxs[0].duplicates_blocked + fxs[1].duplicates_blocked])
		check(refk.size() >= 15, "%d ms/r%d: la partida genera eventos de sobra (%d)" % [rtt, hold, refk.size()])
		check(ok_all, "%d ms/r%d: los %d eventos confirmados se mostraron en ambos pares (faltan %d)" % [rtt, hold, refk.size(), missing])
		var rate := 100.0 * spur / maxf(refk.size() * 2, 1)
		rates[combo] = rate
		print("      %d ms, retención %d: efectos mostrados de una predicción fallida: %d de %d (%.1f%%), cancelados antes de mostrarse %d" % [rtt, hold, spur, refk.size() * 2, rate, fxs[0].cancelled + fxs[1].cancelled])
	check(rates[[200, 2]] < rates[[200, 0]] and rates[[100, 2]] <= rates[[100, 0]], "retener 2 ticks reduce los efectos espurios (200 ms: %.1f%% → %.1f%%)" % [rates[[200, 0]], rates[[200, 2]]])
	# comprobación de params
	var hh := RbHarness.new()
	hh.engine_factory = func() -> RbEngine: return FightEngine.new(P)
	var ph := SimParams.params_checksum(P)
	hh.params_hash = [ph, ph]
	var r2 := hh.run(300)
	check(r2["mismatches"] == 0 and hh.last_peers[0].frame > 250, "mismo params_checksum: la partida avanza")
	var P2 := P.duplicate(true); P2[1]["hp"] = int(P2[1]["hp"]) + 1
	check(SimParams.params_checksum(P2) != ph, "params_checksum detecta un cambio de un valor")
	hh.params_hash = [ph, SimParams.params_checksum(P2)]
	hh.run(300)
	check(hh.last_peers[0].params_mismatch and hh.last_peers[1].params_mismatch and hh.last_peers[0].frame == 0, "params distintos: ambos pares se detienen sin simular")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
