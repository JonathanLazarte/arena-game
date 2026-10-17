class_name NetLink
extends RefCounted
## Enlace UDP con el rival: sala por código en el relay (server/), golpe de NAT directo con
## respaldo por relay, o LAN/IP directa sin servidor. Mensajes de juego = Dictionary (var_to_bytes).
## Tipos de datagrama (byte 0): C/J/W/M/E/R/D/K/k/X/x con el relay (ver server/src/relay.ts);
## P/Q golpe de NAT (petición/respuesta), L/l saludo LAN, D datos.
const LAN_PORT := 47801
const DEFAULT_RELAY_PORT := 47800
const PUNCH_MS := 2000
const RETRY_MS := 300
const KEEPALIVE_MS := 2000
## Protocolo de juego (versión): viaja en C/J/Q y el relay rechaza otros («version»).
const GAME_PROTO := 5

enum St { IDLE, CONNECTING, WAITING, PUNCHING, CONNECTED, FAILED, CLOSED }
var state: St = St.IDLE
var error := ""
var mode := ""          ## "relay" | "lan_host" | "lan_guest"
var slot := -1          ## 0 anfitrión (jugador 0 en la sim), 1 invitado
var code := ""
var direct := false     ## true: datagramas directos al rival; false: a través del relay
var peer_left := false
var udp := PacketPeerUDP.new()
var relay_ip := ""
var relay_port := 0
var peer_ip := ""
var peer_port := 0
var last_recv_ms := 0
var inbox: Array[Dictionary] = []
var bytes_out := 0
var bytes_in := 0
## Red simulada (pruebas): retardo de salida en ms, variación y pérdida.
var sim_delay_ms := 0.0
var sim_jitter_ms := 0.0
var sim_loss := 0.0
var _rng := RandomNumberGenerator.new()
var _outq: Array = [] # [t_ms, bytes, ip, port]
var _ctl: PackedByteArray
var _retry_at := 0
var _punch_until := 0
var _keep_at := 0
var force_relay := false ## pruebas/diagnóstico: no intentar conexión directa
var join_wait_ms := 0
## Fase 5: emparejamiento rápido, región, reconexión con ficha de sesión, abandono.
var token := ""
var region := ""
var queue_pos := -1
var peer_abandoned := false
var reconnected := 0
var _reco_at := 0
var blackout := false ## pruebas: simula cortar la red (se descarta todo lo enviado y recibido)
## Diagnóstico LAN (panel online)
var bound_port := 0
var hellos_sent := 0
var hellos_recv := 0      ## anfitrión: saludos recibidos; invitado: respuestas recibidas
var lan_timeout_ms := 8000
var _lan_deadline := 0
var found_hosts: Dictionary = {} ## búsqueda LAN: "ip" -> {name, ms}
var host_name := ""
const DISCOVER_MS := 500 ## unirse antes de que exista la sala: reintentar este tiempo
var _join_deadline := 0

static func now_ms() -> int:
	return Time.get_ticks_msec()

# ---------------- arranque ----------------
func create_room(relay_host: String, port: int = DEFAULT_RELAY_PORT, want_code: String = "") -> void:
	if not _open(0): return
	if not _set_relay(relay_host, port): return
	mode = "relay"
	_ctl = _msg("C", {"v": GAME_PROTO, "code": want_code} if want_code != "" else {"v": GAME_PROTO})
	state = St.CONNECTING
	_retry_at = 0

func join_room(relay_host: String, port: int, room_code: String) -> void:
	if not _open(0): return
	if not _set_relay(relay_host, port): return
	mode = "relay"
	code = room_code.strip_edges().to_upper()
	_ctl = _msg("J", {"v": GAME_PROTO, "code": code})
	_join_deadline = now_ms() + join_wait_ms
	state = St.CONNECTING
	_retry_at = 0

## Partida rápida: cola del relay de la región elegida; al emparejar llega «M» como en join_room.
func quick_match(relay_host: String, port: int = DEFAULT_RELAY_PORT) -> void:
	if not _open(0): return
	if not _set_relay(relay_host, port): return
	mode = "relay"
	_ctl = _msg("Q", {"v": GAME_PROTO})
	state = St.CONNECTING
	_retry_at = 0

## Durante una partida sin noticias del rival: pedir al relay que nos re-asocie (nueva dirección
## o NAT renovado) con la ficha de sesión. A partir de aquí todo va por el relay.
func reconnect_tick() -> void:
	if mode != "relay" or token == "" or state == St.CLOSED or state == St.FAILED:
		return
	direct = false
	var t := now_ms()
	if t >= _reco_at:
		_reco_at = t + 1000
		_raw(_msg("B", {"code": code, "token": token}), relay_ip, relay_port, true)

func host_lan(port: int = LAN_PORT) -> void:
	if not _open(port): return
	mode = "lan_host"; slot = 0; direct = true
	state = St.WAITING

func join_lan(ip: String, port: int = LAN_PORT) -> void:
	if not _open(0): return
	var addr := ip if ip.is_valid_ip_address() else IP.resolve_hostname(ip, IP.TYPE_IPV4)
	if addr == "":
		_fail("no se encuentra %s" % ip); return
	mode = "lan_guest"; slot = 1; direct = true
	peer_ip = addr; peer_port = port
	_ctl = PackedByteArray([0x4C]) # 'L'
	_lan_deadline = now_ms() + lan_timeout_ms
	state = St.CONNECTING
	_retry_at = 0

## Busca anfitriones LAN por difusión (sin escribir IP). Rellena found_hosts al llegar respuestas.
func discover_lan(port: int = LAN_PORT) -> void:
	if not _open(0): return
	udp.set_broadcast_enabled(true)
	mode = "lan_search"
	_disc_port = port
	state = St.CONNECTING
	_retry_at = 0
var _disc_port := LAN_PORT

func close() -> void:
	if state == St.CONNECTED or state == St.WAITING or state == St.PUNCHING:
		if mode == "relay" and relay_ip != "":
			_raw(PackedByteArray([0x58]), relay_ip, relay_port, true) # 'X'
	udp.close()
	state = St.CLOSED

## Direcciones LAN de este equipo (para mostrar al anfitrión).
## Primero las de wifi/LAN domésticas (192.168, 10.), luego 172.16-31; fuera puentes de
## contenedores/VM típicos (172.17.x docker0, 192.168.122.x libvirt), que confunden al escribir la IP.
static func lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for pref in ["192.168.", "10.", "172."]:
		for a in IP.get_local_addresses():
			if not a.begins_with(pref) or a in out or a.contains(":"):
				continue
			if pref == "172.":
				var o2 := int(a.split(".")[1])
				if o2 < 16 or o2 > 31 or o2 == 17: continue
			if a.begins_with("192.168.122."): continue
			out.append(a)
	return out

## ¿Comparte /24 con alguna dirección local? (aviso de «otra red» en el panel)
static func same_subnet(ip: String) -> bool:
	var p := ip.rsplit(".", true, 1)[0] + "."
	for a in IP.get_local_addresses():
		if a.begins_with(p): return true
	return false

func _open(port: int) -> bool:
	udp.close()
	_rng.randomize()
	var e := udp.bind(port, "0.0.0.0") # todas las interfaces IPv4
	if e != OK:
		_fail("port_busy:%d" % port); return false
	bound_port = udp.get_local_port()
	hellos_sent = 0; hellos_recv = 0
	last_recv_ms = now_ms()
	return true

func _set_relay(host: String, port: int) -> bool:
	relay_ip = host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	relay_port = port
	if relay_ip == "":
		_fail("no se encuentra el servidor %s" % host); return false
	return true

func _fail(msg: String) -> void:
	error = msg
	state = St.FAILED

# ---------------- envío ----------------
func send_msg(d: Dictionary, urgent: bool = false) -> void:
	if state != St.CONNECTED and state != St.PUNCHING:
		return
	var body := var_to_bytes(d)
	if direct:
		var b := PackedByteArray([0x44]); b.append_array(body)
		_raw(b, peer_ip, peer_port, urgent)
	else:
		var r := PackedByteArray([0x52]); r.append_array(body)
		_raw(r, relay_ip, relay_port, urgent)

func _msg(t: String, d: Dictionary) -> PackedByteArray:
	var b := t.to_ascii_buffer()
	b.append_array(JSON.stringify(d).to_utf8_buffer())
	return b

func _raw(b: PackedByteArray, ip: String, port: int, now: bool = false) -> void:
	if blackout: return
	bytes_out += b.size()
	if now or (sim_delay_ms <= 0.0 and sim_loss <= 0.0):
		udp.set_dest_address(ip, port)
		udp.put_packet(b)
		return
	if _rng.randf() < sim_loss:
		return
	var t := now_ms() + int(maxf(0.0, sim_delay_ms + _rng.randf_range(-sim_jitter_ms, sim_jitter_ms)))
	_outq.append([t, b, ip, port])

# ---------------- bucle ----------------
func poll() -> void:
	if state == St.IDLE or state == St.CLOSED or state == St.FAILED:
		return
	var t := now_ms()
	if not _outq.is_empty():
		var keep: Array = []
		for q: Array in _outq:
			if t >= int(q[0]):
				udp.set_dest_address(q[2], q[3]); udp.put_packet(q[1])
			else:
				keep.append(q)
		_outq = keep
	while udp.get_available_packet_count() > 0:
		var b := udp.get_packet()
		if blackout: continue
		_on_packet(b, udp.get_packet_ip(), udp.get_packet_port())
	if state == St.CONNECTING and t >= _retry_at:
		_retry_at = t + RETRY_MS
		if mode == "lan_guest":
			_raw(_ctl, peer_ip, peer_port, true)
			hellos_sent += 1
			if t >= _lan_deadline:
				_fail("lan_timeout")
				return
		elif mode == "lan_search":
			_retry_at = t + DISCOVER_MS
			for bc in _broadcasts():
				_raw(PackedByteArray([0x53]), bc, _disc_port, true) # 'S'
			hellos_sent += 1
		else:
			_raw(_ctl, relay_ip, relay_port, true)
	if state == St.PUNCHING:
		if t >= _retry_at:
			_retry_at = t + 100
			_raw(PackedByteArray([0x50]), peer_ip, peer_port, true) # 'P'
		if t >= _punch_until:
			state = St.CONNECTED # sin respuesta directa: seguimos por el relay
	if mode == "relay" and relay_ip != "" and t >= _keep_at and (state == St.WAITING or state == St.CONNECTED or state == St.PUNCHING):
		_keep_at = t + KEEPALIVE_MS
		_raw(PackedByteArray([0x4B]), relay_ip, relay_port, true) # 'K'

func _broadcasts() -> Array[String]:
	var out: Array[String] = ["255.255.255.255"]
	for a in lan_addresses():
		out.append(a.rsplit(".", true, 1)[0] + ".255")
	return out

func _on_packet(b: PackedByteArray, ip: String, port: int) -> void:
	if b.is_empty(): return
	bytes_in += b.size()
	var from_relay := ip == relay_ip and port == relay_port
	var from_peer := ip == peer_ip and port == peer_port
	var t := char(b[0])
	if from_relay:
		match t:
			"W":
				var j: Dictionary = _json(b)
				code = String(j.get("code", "")); slot = 0
				state = St.WAITING
			"M":
				var j: Dictionary = _json(b)
				slot = int(j.get("slot", 0)); code = String(j.get("code", code))
				token = String(j.get("token", token)); region = String(j.get("region", region))
				if int(j.get("re", 0)) == 1:
					reconnected += 1; direct = false
					last_recv_ms = now_ms()
					if state != St.CONNECTED and state != St.PUNCHING: state = St.CONNECTED
					return
				var pe := String(j.get("peer", "")).rsplit(":", true, 1)
				peer_ip = pe[0]; peer_port = int(pe[1])
				last_recv_ms = now_ms()
				state = St.CONNECTED if force_relay else St.PUNCHING
				_punch_until = now_ms() + PUNCH_MS
				_retry_at = 0
			"E":
				if String(_json(b).get("err", "")) == "no_room" and now_ms() < _join_deadline:
					return
				_fail(String(_json(b).get("err", "error")))
			"D":
				last_recv_ms = now_ms()
				_deliver(b)
			"x":
				peer_left = true
			"b":
				var pe2 := String(_json(b).get("peer", "")).rsplit(":", true, 1)
				if pe2.size() == 2:
					peer_ip = pe2[0]; peer_port = int(pe2[1])
				direct = false # el rival cambió de dirección: seguimos por el relay
			"F":
				peer_abandoned = true
			"q":
				queue_pos = int(_json(b).get("pos", 0))
				if state == St.CONNECTING: state = St.WAITING
			"k":
				pass
		return
	match t:
		"P":
			if from_peer and not force_relay: _raw(PackedByteArray([0x51]), ip, port, true) # 'Q'
		"Q":
			if from_peer and not direct:
				direct = true
				if state == St.PUNCHING: state = St.CONNECTED
		"S":
			if mode == "lan_host" and state == St.WAITING:
				var r := PackedByteArray([0x73]); r.append_array(host_name.to_utf8_buffer()) # 's' + nombre
				_raw(r, ip, port, true)
		"s":
			if mode == "lan_search":
				found_hosts[ip] = {"name": b.slice(1).get_string_from_utf8(), "ms": now_ms(), "port": port}
		"L":
			if mode == "lan_host":
				hellos_recv += 1
			if mode == "lan_host" and (state == St.WAITING or from_peer):
				peer_ip = ip; peer_port = port
				state = St.CONNECTED
				last_recv_ms = now_ms()
				_raw(PackedByteArray([0x6C]), ip, port, true) # 'l'
		"l":
			if mode == "lan_guest" and state == St.CONNECTING and port == peer_port and not from_peer:
				# respuesta desde otra interfaz del anfitrión (varias IPs): adoptamos la dirección real
				peer_ip = ip; from_peer = true
			if mode == "lan_guest" and from_peer:
				hellos_recv += 1
			if mode == "lan_guest" and from_peer and state == St.CONNECTING:
				state = St.CONNECTED
				last_recv_ms = now_ms()
		"D":
			if from_peer:
				last_recv_ms = now_ms()
				_deliver(b)

func _deliver(b: PackedByteArray) -> void:
	var v: Variant = bytes_to_var(b.slice(1))
	if v is Dictionary:
		inbox.append(v)

func _json(b: PackedByteArray) -> Dictionary:
	var v: Variant = JSON.parse_string(b.slice(1).get_string_from_utf8())
	return v if v is Dictionary else {}

func pending_out() -> int:
	return _outq.size()

func ready_to_play() -> bool:
	return state == St.CONNECTED or state == St.PUNCHING
