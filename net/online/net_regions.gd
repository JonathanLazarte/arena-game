class_name NetRegions
extends RefCounted
## Fase 5: lista de relays por región («sa=relay-sp.example:47800, us=...» o «host:port») y medición
## de ping con 'P'/'p' para elegir el más cercano. Sin servidores por defecto (no hay despliegue).
var servers: Array[Dictionary] = [] ## {name, host, port, ip, ms (-1 = sin respuesta), region}
var udp := PacketPeerUDP.new()
var _sent := 0
var _until := 0
var done := false
const ROUNDS := 4

static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in text.split(",", false):
		var p := part.strip_edges()
		if p == "": continue
		var name := ""
		if p.contains("="):
			name = p.get_slice("=", 0).strip_edges(); p = p.get_slice("=", 1).strip_edges()
		var hp := p.rsplit(":", true, 1)
		var port := int(hp[1]) if hp.size() == 2 else NetLink.DEFAULT_RELAY_PORT
		out.append({"name": name if name != "" else hp[0], "host": hp[0], "port": port, "ip": "", "ms": -1, "region": "", "samples": []})
	return out

func start(text: String, timeout_ms: int = 1500) -> void:
	_drop_lookups()
	servers = parse(text)
	udp.close(); udp.bind(0, "0.0.0.0")
	for s in servers:
		var host := String(s["host"])
		if host.is_valid_ip_address():
			s["ip"] = host
		else:
			s["ip"] = ""
			s["dns"] = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
	_sent = 0; done = servers.is_empty()
	_until = Time.get_ticks_msec() + timeout_ms

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for s in servers:
		if s.has("dns") and int(s["dns"]) >= 0:
			IP.erase_resolve_item(int(s["dns"]))
		s.erase("dns")

func _drop_lookups() -> void:
	for s in servers:
		if s.has("dns") and int(s["dns"]) >= 0:
			IP.erase_resolve_item(int(s["dns"]))
		s.erase("dns")

## true mientras algún nombre sigue en la cola.
func _dns_pending() -> bool:
	var waiting := false
	for s in servers:
		if not s.has("dns"):
			continue
		var id := int(s["dns"])
		if id < 0:
			s.erase("dns")
			continue
		var st := IP.get_resolve_item_status(id)
		if st == IP.RESOLVER_STATUS_NONE or st == IP.RESOLVER_STATUS_WAITING:
			waiting = true
			continue
		var addr := ""
		if st == IP.RESOLVER_STATUS_DONE:
			addr = IP.get_resolve_item_address(id)
		IP.erase_resolve_item(id)
		s.erase("dns")
		s["ip"] = addr
	return waiting

## Llamar cada fotograma hasta done. No manda UDP hasta resolver el nombre.
func poll() -> void:
	if done: return
	var t := Time.get_ticks_msec()
	if _dns_pending():
		if t >= _until:
			_drop_lookups()
			done = true
			udp.close()
		return
	if _sent < ROUNDS and t >= _until - 1500 + _sent * 150:
		_sent += 1
		for s in servers:
			if s["ip"] == "": continue
			udp.set_dest_address(s["ip"], s["port"])
			udp.put_packet(("P" + JSON.stringify({"t": t})).to_ascii_buffer())
	while udp.get_available_packet_count() > 0:
		var b := udp.get_packet(); var ip := udp.get_packet_ip(); var port := udp.get_packet_port()
		if b.size() < 2 or char(b[0]) != "p": continue
		var j: Variant = JSON.parse_string(b.slice(1).get_string_from_utf8())
		if not (j is Dictionary): continue
		for s in servers:
			if s["ip"] == ip and int(s["port"]) == port:
				s["samples"].append(t - int(j.get("t", t)))
				s["region"] = String(j.get("region", ""))
				var a: Array = s["samples"].duplicate(); a.sort()
				s["ms"] = int(a[0])
	if t >= _until:
		done = true; udp.close()

## Mejor servidor (menor ping con respuesta) o {} si ninguno respondió.
func best() -> Dictionary:
	var b := {}
	for s in servers:
		if int(s["ms"]) >= 0 and (b.is_empty() or int(s["ms"]) < int(b["ms"])): b = s
	return b

func summary() -> String:
	var parts: Array[String] = []
	for s in servers:
		parts.append("%s%s: %s" % [s["name"], " (" + String(s["region"]) + ")" if s["region"] != "" else "", "%d ms" % s["ms"] if int(s["ms"]) >= 0 else "sin respuesta"])
	return ", ".join(parts)
