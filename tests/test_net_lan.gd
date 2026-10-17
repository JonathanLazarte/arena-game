extends SceneTree
## LAN: diagnóstico, búsqueda por difusión, tiempo de espera, puerto ocupado, varias interfaces.
## godot --headless --path . -s res://tests/test_net_lan.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _pump(links: Array, ms: int, until: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for l: NetLink in links: l.poll()
		if until.call(): return
		OS.delay_msec(10)

func _run() -> void:
	var ips := NetLink.lan_addresses()
	print("      IPs locales: ", IP.get_local_addresses(), " -> LAN: ", ips)
	var bad := false
	for a in ips:
		if a.begins_with("172.17.") or a.begins_with("127.") or a.contains(":"): bad = true
	check(not bad, "las IPs mostradas excluyen loopback, IPv6 y puentes de contenedores (172.17.x)")
	# puerto ocupado
	var h := NetLink.new(); h.host_lan(47711)
	var h2 := NetLink.new(); h2.host_lan(47711)
	check(h.state == NetLink.St.WAITING and h.bound_port == 47711, "anfitrión escucha en 0.0.0.0:%d" % h.bound_port)
	check(h2.state == NetLink.St.FAILED and h2.error.begins_with("port_busy"), "puerto ocupado: error claro (%s)" % h2.error)
	# unirse por cada interfaz (no solo loopback)
	var targets: Array[String] = ["127.0.0.1"]
	targets.append_array(ips)
	for ip in targets:
		h.close(); h = NetLink.new(); h.host_lan(47712)
		var g := NetLink.new(); g.join_lan(ip, 47712)
		_pump([h, g], 3000, func() -> bool: return h.ready_to_play() and g.ready_to_play())
		check(h.ready_to_play() and g.ready_to_play() and g.hellos_sent >= 1 and g.hellos_recv >= 1 and h.hellos_recv >= 1, "unirse por %s: conectado (saludos %d enviados / %d respuestas)" % [ip, g.hellos_sent, g.hellos_recv])
		g.close()
	h.close()
	# búsqueda por difusión
	h = NetLink.new(); h.host_name = "Pollo"; h.host_lan(NetLink.LAN_PORT)
	var s := NetLink.new(); s.discover_lan()
	_pump([h, s], 3000, func() -> bool: return not s.found_hosts.is_empty())
	print("      encontrados: ", s.found_hosts)
	if ips.is_empty():
		print("      (sin interfaz LAN en este equipo: búsqueda no comprobable)")
	else:
		check(not s.found_hosts.is_empty() and String(s.found_hosts.values()[0]["name"]) == "Pollo", "búsqueda LAN: encuentra al anfitrión por difusión con su nombre")
	s.close(); h.close()
	# sin anfitrión: tiempo de espera con diagnóstico
	var g2 := NetLink.new(); g2.lan_timeout_ms = 1200; g2.join_lan("127.0.0.1", 47719)
	_pump([g2], 3000, func() -> bool: return g2.state == NetLink.St.FAILED)
	check(g2.state == NetLink.St.FAILED and g2.error == "lan_timeout" and g2.hellos_sent >= 3 and g2.hellos_recv == 0, "sin anfitrión: lan_timeout tras %d saludos sin respuesta" % g2.hellos_sent)
	check(NetLink.same_subnet("127.0.0.5") and not NetLink.same_subnet("203.0.113.9"), "aviso de otra red (comparación /24)")
	# panel: textos de diagnóstico
	var p := OnlinePanel.new(); p.go_scene = false; root.add_child(p)
	await process_frame
	p.host_lan()
	check(p.status_label.text.contains("0.0.0.0") and p.status_label.text.contains("ufw allow 47801/udp") and p.status_label.text.contains("firewall-cmd --add-port=47801/udp --permanent") and p.status_label.text.contains("Saludos recibidos"), "panel anfitrión: IP, puerto, interfaces, saludos y consejo de cortafuegos")
	p.cancel()
	var p2 := OnlinePanel.new(); p2.go_scene = false; root.add_child(p2)
	await process_frame
	p2.ip_edit.text = "127.0.0.1"
	p2.join_lan()
	p2.link.lan_timeout_ms = 0 # forzar el fin de espera
	p2.link._lan_deadline = 0
	for i in 30: await physics_frame
	check(p2.status_label.text.contains("sin respuesta") and p2.status_label.text.contains("cortafuegos") and p2.status_label.text.contains("aísle clientes"), "panel invitado: mensaje de tiempo agotado con causas probables")
	p2.cancel()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
