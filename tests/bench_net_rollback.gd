extends SceneTree
## Mide rollback por tick y coste de re-simulación a 50/100/150/200 ms de RTT.
## godot --headless --path . -s res://tests/bench_net_rollback.gd [-- <retardo> <ventana>]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var delay := int(args[0]) if args.size() > 0 else 2
	var window := int(args[1]) if args.size() > 1 else 8
	var fight := args.size() > 2 and args[2] == "fight"
	print("delay=%d window=%d jitter=15ms loss=2%% sim=%s" % [delay, window, "FightSim" if fight else "RbSim"])
	print("RTT | rb/tick | resimF/tick | avg len | max | stall%% | resim us avg | p99 | tick us avg")
	for rtt in [50, 100, 150, 200]:
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.jitter_ms = 15.0; h.loss = 0.02; h.delay = delay; h.window = window; h.seed_v = 5
		if fight:
			h.bot_mask = 0x3FFF & ~FightSim.IN_SWAP & ~FightSim.IN_BLOCK; h.bot_or = FightSim.IN_LOCK
			h.engine_factory = func() -> RbEngine: var e := FightEngine.new(SimParams.defaults(), 9, true); e.gap_um = 2000000; return e
		var r := h.run(3600)
		print("%3d | %.2f | %.2f | %.1f | %d | %.1f | %.0f | %d | %.1f | desync=%d" % [rtt, r["rollbacks_per_tick"], r["resim_frames_per_tick"], r["avg_rollback_len"], r["max_rollback"], r["stall_pct"], r["resim_us_avg"], r["resim_us_p99"], r["tick_us_avg"], r["mismatches"]])
	if fight:
		var P := SimParams.defaults()
		var s := FightSim.initial(P)
		s[FightSim.X] = -1000000; s[FightSim.F_FIELDS + FightSim.X] = 1000000
		var rng := RandomNumberGenerator.new(); rng.seed = 2
		var t0 := Time.get_ticks_usec()
		for k in 20000:
			FightSim.step(s, P, (rng.randi() & 0x2FFF) | FightSim.IN_LOCK, (rng.randi() & 0x2FFF) | FightSim.IN_LOCK)
		var t1 := Time.get_ticks_usec()
		for k in 20000:
			var c := s.duplicate()
		var t2 := Time.get_ticks_usec()
		print("FightSim.step: %.1f us/tick | guardar estado (%d ints): %.2f us | checksum: %.1f us" % [(t1 - t0) / 20000.0, FightSim.SIZE, (t2 - t1) / 20000.0, _ck(s)])
	quit()

func _ck(s: PackedInt64Array) -> float:
	var t0 := Time.get_ticks_usec()
	for k in 2000: FightSim.checksum(s)
	return (Time.get_ticks_usec() - t0) / 2000.0
