class_name RbHarness
extends RefCounted
## Banco de pruebas local: dos pares RbSession en el mismo proceso, red simulada con
## latencia (RTT), jitter y pérdida de paquetes (RNG con semilla, reproducible).
## Entradas de "bots" pseudoaleatorias con semilla y cambios frecuentes para forzar errores de predicción.

var rtt_ms := 100.0
var jitter_ms := 10.0
var loss := 0.02
var delay := 2
var window := 8
var seed_v := 1
var engine_factory: Callable = func() -> RbEngine: return RbEngine.new() ## motor por par
var bot_mask := 63 ## bits de entrada que pueden pulsar los bots
var bot_change := 0.25
var bot_or := 0 ## bits siempre pulsados (p. ej. fijado)
var last_peers: Array[RbSession] = [] ## pares de la última ejecución (para inspección en pruebas)
var params_hash := [0, 0] ## params_checksum de cada par (0 = sin comprobación)
var corrupt_at := -1 ## prueba negativa: altera el estado del par 1 en ese tick (simula una fuente no determinista)

func run(ticks: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var bots: Array[RandomNumberGenerator] = [RandomNumberGenerator.new(), RandomNumberGenerator.new()]
	bots[0].seed = seed_v * 31 + 1
	bots[1].seed = seed_v * 31 + 2
	var cur_in: Array[int] = [0, 0]
	var peers: Array[RbSession] = [RbSession.new(0, delay, window, engine_factory.call()), RbSession.new(1, delay, window, engine_factory.call())]
	last_peers = peers
	peers[0].params_hash = params_hash[0]
	peers[1].params_hash = params_hash[1]
	var wire: Array = [] # [deliver_ms, to, packet]
	var dt := 1000.0 / RbSim.TICK_HZ
	var step_usec := 0
	var steps := 0
	for k in ticks + 120: # 120 ticks extra sin entrada nueva para drenar
		var now := k * dt
		# entregar paquetes vencidos
		var keep: Array = []
		for w in wire:
			if w[0] <= now:
				peers[w[1]].receive_packet(w[2])
			else:
				keep.append(w)
		wire = keep
		for i in 2:
			var p := peers[i]
			if k < ticks and bots[i].randf() < bot_change: # cambia de intención ~cada 4 ticks
				cur_in[i] = (bots[i].randi() & bot_mask) | bot_or
			p.add_local_input(cur_in[i] if k < ticks else 0)
			var t0 := Time.get_ticks_usec()
			p.tick()
			if i == 1 and p.frame == corrupt_at:
				p.state[0] += 1
			step_usec += Time.get_ticks_usec() - t0
			steps += 1
			if rng.randf() >= loss:
				var lat := rtt_ms * 0.5 + rng.randf_range(-jitter_ms, jitter_ms)
				wire.append([now + maxf(lat, 1.0), 1 - i, p.make_packet(peers[1 - i].last_remote)])
	# comparar checksums de ticks confirmados en ambos
	var common := 0
	var mismatches := 0
	for t in peers[0].checksums:
		if peers[1].checksums.has(t):
			common += 1
			if peers[0].checksums[t] != peers[1].checksums[t]:
				mismatches += 1
	var all_us: Array[int] = []
	for p in peers:
		all_us.append_array(p.resim_usec)
	all_us.sort()
	var tot_rb := peers[0].rollbacks + peers[1].rollbacks
	var tot_rf := peers[0].resim_frames + peers[1].resim_frames
	return {
		"common": common, "mismatches": mismatches,
		"final_equal": peers[0].checksums.get(peers[0].frame - 60, -1) == peers[1].checksums.get(peers[0].frame - 60, -2),
		"frames": peers[0].frame,
		"rollbacks_per_tick": float(tot_rb) / float(2 * ticks),
		"resim_frames_per_tick": float(tot_rf) / float(2 * ticks),
		"avg_rollback_len": float(tot_rf) / maxf(tot_rb, 1),
		"max_rollback": maxi(peers[0].max_resim, peers[1].max_resim),
		"stall_pct": 100.0 * float(peers[0].stalls + peers[1].stalls) / float(2 * ticks),
		"resim_us_avg": (float(all_us.reduce(func(a, b): return a + b, 0)) / maxf(all_us.size(), 1)),
		"resim_us_p99": (all_us[int(all_us.size() * 0.99)] if all_us.size() > 0 else 0),
		"tick_us_avg": float(step_usec) / float(steps),
		"state": peers[0].state,
	}
