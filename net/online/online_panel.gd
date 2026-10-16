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
	v.add_child(UIKit.label("Servidor (relay) para salas por código:", 15))
	relay_edit = _edit(v, "mi-relay.example.com:47800")
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

func _relay() -> Array:
	var t := relay_edit.text.strip_edges()
	if t == "":
		status_label.text = "Escribe la dirección del servidor relay (ver docs/netcode.md) o usa LAN."
		return []
	var parts := t.rsplit(":", true, 1)
	return [parts[0], int(parts[1]) if parts.size() == 2 else NetLink.DEFAULT_RELAY_PORT]

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
	_new_link(); link.host_lan()
	var ips := NetLink.lan_addresses()
	status_label.text = "Esperando rival en la misma wifi. Tu IP: %s (puerto %d)" % [", ".join(ips) if not ips.is_empty() else "?", NetLink.LAN_PORT]

func join_lan() -> void:
	if ip_edit.text.strip_edges() == "":
		status_label.text = "Escribe la IP que muestra el anfitrión."; return
	_new_link(); link.join_lan(ip_edit.text.strip_edges())
	status_label.text = "Conectando con %s…" % ip_edit.text

func cancel() -> void:
	if link: link.close()
	link = null; m = null
	queue_free()

func _physics_process(_d: float) -> void:
	if link == null:
		return
	if m == null:
		link.poll()
		match link.state:
			NetLink.St.WAITING:
				if link.mode == "relay":
					status_label.text = "Sala creada. Código: %s\nCompártelo con tu rival." % link.code
			NetLink.St.FAILED:
				status_label.text = "Error: %s" % _err(link.error)
				link = null
				return
		if link.ready_to_play():
			m = NetMatch.new(link)
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
	return {"no_room": "no existe esa sala", "room_full": "la sala está llena", "code_taken": "código en uso",
		"version": "versión distinta del juego", "disconnected": "sin respuesta del rival"}.get(e, e)
