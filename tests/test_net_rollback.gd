extends SceneTree
## Fase online 0: prototipo de rollback determinista (net/). Sin escena ni nodos de juego.
## godot --headless --path . -s res://tests/test_net_rollback.gd

var fails: int = 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _initialize() -> void:
	# 1) determinismo puro: misma secuencia de entradas -> mismo checksum; guardar/restaurar exacto
	var a := RbSim.initial()
	var b := RbSim.initial()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var ins: Array[int] = []
	for i in 600: ins.append(rng.randi() & 63)
	var snap := PackedInt64Array()
	for i in 600:
		if i == 300: snap = a.duplicate()
		RbSim.step(a, ins[i], ins[(i * 7) % 600])
		RbSim.step(b, ins[i], ins[(i * 7) % 600])
	check(RbSim.checksum(a) == RbSim.checksum(b), "simulación determinista (600 ticks)")
	for i in range(300, 600): RbSim.step(snap, ins[i], ins[(i * 7) % 600])
	check(snap == a, "restaurar estado y re-simular reproduce el mismo resultado")
	# 2) mecánicas mínimas: el ataque golpea de frente a corta distancia; la voltereta da invulnerabilidad
	var s := RbSim.initial()
	s[RbSim.FIELDS + RbSim.X] = -1800
	RbSim.step(s, RbSim.IN_ATK, 0)
	for i in 20: RbSim.step(s, RbSim.IN_ATK, 0)
	check(s[RbSim.FIELDS + RbSim.HP] == RbSim.HP_MAX - RbSim.ATK_DAMAGE, "golpe cuerpo a cuerpo hace daño una vez")
	s = RbSim.initial(); s[RbSim.FIELDS + RbSim.X] = -1800
	RbSim.step(s, RbSim.IN_ATK, 0)
	for i in 8: RbSim.step(s, 0, 0)
	RbSim.step(s, 0, RbSim.IN_ROLL | RbSim.IN_UP) # rueda en perpendicular justo antes del activo
	for i in 6: RbSim.step(s, 0, RbSim.IN_UP)
	check(s[RbSim.FIELDS + RbSim.HP] == RbSim.HP_MAX, "voltereta con i-frames esquiva el golpe")
	# 3) convergencia con red simulada
	for rtt in [0, 50, 100, 150, 200]:
		for sd in [1, 2, 3]:
			var h := RbHarness.new()
			h.rtt_ms = rtt; h.jitter_ms = 15.0; h.loss = 0.05; h.seed_v = sd
			var r := h.run(1500)
			check(r["mismatches"] == 0 and r["final_equal"] and r["common"] > 1400,
				"RTT %d ms semilla %d: %d ticks confirmados, 0 desincronías" % [rtt, sd, r["common"]])
	# 4) pérdida extrema y jitter alto
	var hx := RbHarness.new(); hx.rtt_ms = 150; hx.jitter_ms = 60; hx.loss = 0.25; hx.window = 12
	var rx := hx.run(1500)
	check(rx["mismatches"] == 0 and rx["final_equal"], "25 %% pérdida + 60 ms jitter converge (stall %.1f %%)" % rx["stall_pct"])
	# 4b) sin retardo de entrada, 200 ms y ventana corta: provoca detenciones (stall) y debe seguir sincronizado
	for sd in [5, 6]:
		var hs := RbHarness.new(); hs.rtt_ms = 220; hs.jitter_ms = 20; hs.delay = 0; hs.window = 6; hs.seed_v = sd
		var rs := hs.run(2000)
		check(rs["mismatches"] == 0 and rs["final_equal"] and rs["stall_pct"] > 0.0, "stall sin desincronía (stall %.1f %%)" % rs["stall_pct"])
	# 5) detección de desincronía: una alteración de 1 mm en un par se detecta por checksum
	var hc := RbHarness.new(); hc.rtt_ms = 100; hc.corrupt_at = 500
	var rc := hc.run(1000)
	check(rc["mismatches"] > 0, "desincronía inyectada detectada (%d ticks distintos)" % rc["mismatches"])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
