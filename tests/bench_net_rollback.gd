extends SceneTree
## Mide rollback por tick y coste de re-simulación a 50/100/150/200 ms de RTT.
## godot --headless --path . -s res://tests/bench_net_rollback.gd [-- <retardo> <ventana>]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var delay := int(args[0]) if args.size() > 0 else 2
	var window := int(args[1]) if args.size() > 1 else 8
	print("delay=%d window=%d jitter=15ms loss=2%%" % [delay, window])
	print("RTT | rb/tick | resimF/tick | avg len | max | stall%% | resim us avg | p99 | tick us avg")
	for rtt in [50, 100, 150, 200]:
		var h := RbHarness.new()
		h.rtt_ms = rtt; h.jitter_ms = 15.0; h.loss = 0.02; h.delay = delay; h.window = window; h.seed_v = 5
		var r := h.run(3600)
		print("%3d | %.2f | %.2f | %.1f | %d | %.1f | %.0f | %d | %.1f | desync=%d" % [rtt, r["rollbacks_per_tick"], r["resim_frames_per_tick"], r["avg_rollback_len"], r["max_rollback"], r["stall_pct"], r["resim_us_avg"], r["resim_us_p99"], r["tick_us_avg"], r["mismatches"]])
	quit()
