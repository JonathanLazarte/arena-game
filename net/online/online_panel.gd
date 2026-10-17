class_name OnlinePanel
extends Control
## Menú online del lobby: Crear sala / Unirse con código (relay) y LAN (misma wifi, sin servidor).
## Cuando el saludo termina deja la partida en NetMatch.current y abre la arena.
const CFG := "user://online.cfg"
const ARENA := "res://scenes/arena.tscn"
var relay_edit: LineEdit
var code_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var buttons: Array[Button] = []
var link: NetLink
var m: NetMatch
var go_scene := true ## pruebas: no cambiar de escena

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel("Online")
	p.position = Vector2(340, 110)
	p.custom_minimum_size = Vector2(600, 480)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.title("Jugar online", 28, UIKit.YELLOW))
	v.add_child(UIKit.label("Servidores relay por región (sa=host:47800, us=host2:47800):", 15))
	relay_edit = _edit(v, "sa=mi-relay.example.com:47800")
	var row0 := HBoxContainer.new(); v.add_child(row0)
	_btn(row0, "Partida rápida", quick_match)
	_btn(row0, "Medir ping / región", ping_regions)
	var row := HBoxContainer.new(); v.add_child(row)
	_btn(row, "Crear sala", create_room)
	code_edit = _edit(row, "CÓDIGO")
	code_edit.custom_minimum_size.x = 150
	_btn(row, "Unirse con código", join_room)
	v.add_child(UIKit.label("Misma wifi (sin servidor):", 15))
	var row2 := HBoxContainer.new(); v.add_child(row2)
	_btn(row2, "LAN: crear", host_lan)
	ip_edit = _edit(row2, "IP del anfitrión (192.168.x.x)")
	ip_edit.custom_minimum_size.x = 220
	_btn(row2, "LAN: unirse", join_lan)
	_btn(row2, "Buscar", search_lan)
	status_label = UIKit.label("", 17, UIKit.TEXT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(560, 90)
	v.add_child(status_label)
	_btn(v, "Cerrar", cancel)
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		relay_edit.text = String(cf.get_value("online", "relay", ""))
		ip_edit.text = String(cf.get_value("online", "lan_ip", ""))

func _edit(parent: Control, ph: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = ph
	e.custom_minimum_size = Vector2(300, 40)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e

func _btn(parent: Control, t: String, cb: Callable) -> Button:
	var b := UIKit.button(t, 17)
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(cb)
	parent.add_child(b)
	buttons.append(b)
	return b

func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("online", "relay", relay_edit.text.strip_edges())
	cf.set_value("online", "lan_ip", ip_edit.text.strip_edges())
	cf.save(CFG)

var regions: NetRegions
var _quick_after_ping := false
var chosen := {} ## servidor elegido por ping (o el primero)

const NO_RELAY_TEXT := "No hay servidor relay configurado: la partida rápida y las salas con código lo necesitan. Juega por LAN (misma wifi: «LAN: crear» / «LAN: unirse») o despliega un relay (server/DEPLOY.md) y escribe aquí su dirección."
const RELAY_HINT := " Mientras tanto juega por LAN (misma wifi) o despliega un relay siguiendo server/DEPLOY.md."

func _relay() -> Array:
	var t := relay_edit.text.strip_edges()
	if t == "":
		status_label.text = NO_RELAY_TEXT
		return []
	if not chosen.is_empty() and t.contains(String(chosen["host"])):
		return [chosen["host"], chosen["port"]]
	var l := NetRegions.parse(t)
	return [l[0]["host"], l[0]["port"]]

func ping_regions(then_quick: bool = false) -> void:
	if relay_edit.text.strip_edges() == "":
		_relay(); return
	_save()
	regions = NetRegions.new(); regions.start(relay_edit.text)
	_quick_after_ping = then_quick
	status_label.text = "Midiendo ping a %d servidor(es)…" % regions.servers.size()

func quick_match() -> void:
	if chosen.is_empty() and NetRegions.parse(relay_edit.text).size() > 1:
		ping_regions(true); return
	var r := _relay()
	if r.is_empty(): return
	_new_link(); link.quick_match(r[0], r[1])
	status_label.text = "Buscando rival en %s…" % r[0]

func _new_link() -> void:
	if link: link.close()
	link = NetLink.new()
	m = null
	_save()

func create_room() -> void:
	var r := _relay()
	if r.is_empty(): return
	_new_link(); link.create_room(r[0], r[1])
	status_label.text = "Creando sala…"

func join_room() -> void:
	var r := _relay()
	if r.is_empty(): return
	if code_edit.text.strip_edges() == "":
		status_label.text = "Escribe el código de la sala."; return
	_new_link(); link.join_room(r[0], r[1], code_edit.text)
	status_label.text = "Buscando sala %s…" % code_edit.text.to_upper()

func host_lan() -> void:
	_new_link()
	link.host_name = _my_name()
	link.host_lan()
	if link.state == NetLink.St.FAILED:
		return
	status_label.text = _host_text()

func _my_name() -> String:
	var gs := get_node_or_null("/root/GameState")
	return String(gs.display_name_with_title()) if gs else "Anfitrión"

func _host_text() -> String:
	var ips := NetLink.lan_addresses()
	return "Esperando rival en la misma wifi. Tu IP: %s (UDP %d, escuchando en todas las interfaces 0.0.0.0)\nSaludos recibidos: %d. Si el rival no conecta: permite UDP %d en el cortafuegos de este equipo (Fedora/firewalld: sudo firewall-cmd --add-port=%d/udp --permanent && sudo firewall-cmd --reload; Ubuntu/ufw: sudo ufw allow %d/udp) y desactiva el «aislamiento de clientes» del router." % [
		", ".join(ips) if not ips.is_empty() else "? (sin red local)", link.bound_port, link.hellos_recv, NetLink.LAN_PORT, NetLink.LAN_PORT, NetLink.LAN_PORT]

## Busca anfitriones en la wifi por difusión y rellena la IP sola.
func search_lan() -> void:
	_new_link(); link.discover_lan()
	_search_until = Time.get_ticks_msec() + 3000
	status_label.text = "Buscando partidas en la wifi…"
var _search_until := 0

func join_lan() -> void:
	if ip_edit.text.strip_edges() == "":
		status_label.text = "Escribe la IP que muestra el anfitrión."; return
	var ip := ip_edit.text.strip_edges()
	_new_link(); link.join_lan(ip)
	if link.state == NetLink.St.FAILED:
		return
	_lan_warn = "" if NetLink.same_subnet(ip) else "\nAviso: %s no está en tu misma red (tus IPs: %s)." % [ip, ", ".join(NetLink.lan_addresses())]
	status_label.text = "Conectando con %s…%s" % [ip, _lan_warn]
var _lan_warn := ""

func cancel() -> void:
	if link: link.close()
	link = null; m = null
	queue_free()

func _physics_process(_d: float) -> void:
	if regions:
		regions.poll()
		if regions.done:
			var b := regions.best()
			status_label.text = "Ping: %s.%s" % [regions.summary(), " Elegido: %s." % b["name"] if not b.is_empty() else " Ningún servidor relay respondió." + RELAY_HINT]
			chosen = b
			regions = null
			if _quick_after_ping and not b.is_empty():
				quick_match()
	if link == null:
		return
	if m == null:
		link.poll()
		if link.mode == "lan_search":
			if not link.found_hosts.is_empty():
				var ip: String = link.found_hosts.keys()[0]
				ip_edit.text = ip
				status_label.text = "Encontrada: %s (%s). Pulsa «LAN: unirse»." % [ip, link.found_hosts[ip]["name"]]
				_save(); link.close(); link = null
			elif Time.get_ticks_msec() > _search_until:
				status_label.text = "No se encontró ninguna partida LAN. ¿El anfitrión pulsó «LAN: crear»? Algunas redes bloquean la difusión: escribe su IP a mano."
				link.close(); link = null
			return
		if link.mode == "lan_host" and link.state == NetLink.St.WAITING:
			status_label.text = _host_text()
		elif link.mode == "lan_guest" and link.state == NetLink.St.CONNECTING:
			status_label.text = "Conectando con %s:%d desde 0.0.0.0:%d… saludos enviados %d, respuestas %d%s" % [link.peer_ip, link.peer_port, link.bound_port, link.hellos_sent, link.hellos_recv, _lan_warn]
		match link.state:
			NetLink.St.WAITING:
				if link.mode == "relay" and link.queue_pos >= 0:
					status_label.text = "En cola de partida rápida (%s)… esperando rival." % (link.region if link.region != "" else "relay")
				elif link.mode == "relay":
					status_label.text = "Sala creada. Código: %s\nCompártelo con tu rival." % link.code
			NetLink.St.FAILED:
				status_label.text = "Error: %s" % _err(link.error)
				link = null
				return
		if link.ready_to_play():
			m = NetMatch.new(link)
			m.local_loadout = NetLoadout.from_game_state(get_node_or_null("/root/GameState"))
			status_label.text = "Rival encontrado. Midiendo latencia…"
		return
	if m.prelude_step():
		status_label.text = "¡A luchar! (%d ms, retardo %d)" % [int(m.rtt_ms), m.input_delay]
		NetMatch.current = m
		var l := link
		link = null
		if go_scene:
			UIKit.go(ARENA)
		l = l
	elif m.status != "":
		status_label.text = "Error: %s" % _err(m.status)
		link.close(); link = null; m = null

func _err(e: String) -> String:
	if e == "relay_unreachable":
		return "el servidor relay %s no responde (%d s sin respuesta). ¿Está desplegado y con UDP %d abierto?%s" % [link.relay_ip if link else "", (link.relay_timeout_ms if link else 5000) / 1000, NetLink.DEFAULT_RELAY_PORT, RELAY_HINT]
	if e.begins_with("relay_dns:"):
		return "no se encuentra el servidor relay «%s» (DNS).%s" % [e.get_slice(":", 1), RELAY_HINT]
	if e.begins_with("port_busy"):
		return "el puerto UDP %s está ocupado (¿otra copia del juego abierta?)" % e.get_slice(":", 1)
	if e == "lan_timeout" and link:
		return "sin respuesta de %s:%d tras %d saludos. Comprueba: misma wifi (no la de invitados), la IP correcta (la que muestra el anfitrión), cortafuegos del anfitrión con UDP %d permitido (Fedora/firewalld: sudo firewall-cmd --add-port=%d/udp --permanent && sudo firewall-cmd --reload; Ubuntu/ufw: sudo ufw allow %d/udp; Windows: permitir el juego en redes privadas) y que el router no aísle clientes." % [link.peer_ip, link.peer_port, link.hellos_sent, NetLink.LAN_PORT, NetLink.LAN_PORT, NetLink.LAN_PORT]
	return {"no_room": "no existe esa sala", "room_full": "la sala está llena", "code_taken": "código en uso",
		"version": "versión distinta del juego (actualiza la app)", "busy": "servidor lleno, prueba más tarde",
		"bad_token": "sesión caducada", "reconnect_failed": "no se pudo reconectar", "disconnected": "sin respuesta del rival"}.get(e, e)
