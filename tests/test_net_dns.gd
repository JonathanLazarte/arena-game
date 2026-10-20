extends SceneTree
## El DNS del relay, de la LAN y de las regiones no bloquea: va por la cola y poll espera.
## Una IP numérica se usa al momento. godot --headless --path . -s res://tests/test_net_dns.gd
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _until(ms: int, cond: Callable, tick: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		tick.call()
		if cond.call():
			return true
		await process_frame
	tick.call()
	return cond.call()

func _run() -> void:
	var ip := NetLink.new()
	ip.create_room("127.0.0.1", 47991)
	check(ip.relay_ip == "127.0.0.1" and ip._dns_id < 0 and ip.state == NetLink.St.CONNECTING, "IP numérica del relay, sin cola")
	ip.close()
	var lan := NetLink.new()
	lan.join_lan("127.0.0.1", 47992)
	check(lan.peer_ip == "127.0.0.1" and lan._dns_id < 0 and lan.state == NetLink.St.CONNECTING, "IP numérica de LAN, sin cola")
	lan.close()
	var host := NetLink.new()
	host.relay_timeout_ms = 4000
	host.create_room("localhost", 47993)
	var armed: int = host._relay_deadline
	check(host.relay_ip == "" and host._dns_id >= 0 and host.state == NetLink.St.CONNECTING and host.error == "", "localhost entra en la cola y no manda todavía")
	host.relay_timeout_ms = 9000
	var ok := await _until(3000, func() -> bool: return host.relay_ip != "", func() -> void: host.poll())
	check(ok and host.relay_ip == "127.0.0.1" and host._dns_id < 0, "localhost resuelve a 127.0.0.1 (%s)" % host.relay_ip)
	check(host._relay_deadline > armed, "al resolver, el plazo de 5 s del relay vuelve a empezar")
	host.close()
	var bad := NetLink.new()
	bad.relay_timeout_ms = 2000
	bad.create_room("no-existe.invalid", 47994)
	var failed := await _until(2500, func() -> bool: return bad.state == NetLink.St.FAILED, func() -> void: bad.poll())
	check(failed and bad.error == "relay_dns:no-existe.invalid", "nombre imposible: %s" % bad.error)
	bad.close()
	var guest := NetLink.new()
	guest.join_lan("localhost", 47995)
	check(guest.peer_ip == "" and guest._dns_id >= 0, "unirse por nombre espera a poll")
	var lan_ok := await _until(3000, func() -> bool: return guest.peer_ip != "", func() -> void: guest.poll())
	check(lan_ok and guest.peer_ip == "127.0.0.1" and guest.error == "", "LAN localhost → %s" % guest.peer_ip)
	guest.close()
	var missing := NetLink.new()
	missing.lan_timeout_ms = 400
	missing.join_lan("tampoco.invalid", 47996)
	var miss := await _until(1200, func() -> bool: return missing.state == NetLink.St.FAILED, func() -> void: missing.poll())
	check(miss and missing.error == "no se encuentra tampoco.invalid", "LAN sin nombre: %s" % missing.error)
	missing.close()
	var leaked := false
	for _i in 40:
		var q := NetLink.new()
		q.create_room("localhost", 1)
		if q._dns_id < 0:
			leaked = true
		q.close()
	check(not leaked, "close libera la cola de 32")
	var rg := NetRegions.new()
	rg.start("casa=localhost:47997", 2000)
	var rg_ok := await _until(3000, func() -> bool: return String(rg.servers[0]["ip"]) != "", func() -> void: rg.poll())
	check(rg_ok and String(rg.servers[0]["ip"]) == "127.0.0.1" and not rg.servers[0].has("dns"), "región localhost resuelve antes de mandar")
	rg.poll()
	var slow := NetRegions.new()
	slow.start("nada=no-existe.invalid:47998", 300)
	await _frames(8)
	var cut := await _until(800, func() -> bool: return slow.done, func() -> void: slow.poll())
	check(cut and String(slow.servers[0]["ip"]) == "" and not slow.servers[0].has("dns"), "el plazo corta una región que no resuelve")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
