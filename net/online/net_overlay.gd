class_name NetOverlay
extends CanvasLayer
## Panel de red en partida (F3 o botón «Red»): ping, retardo, rollback, sincronía, ruta, coste de sim.
var net: NetMatch
var label: Label
var toggle: Button
var shown := false
var _n := 0
var _bytes0 := 0
var _t0 := 0
var kbps := 0.0

func _init(m: NetMatch) -> void:
	net = m
	layer = 20

func _ready() -> void:
	toggle = Button.new()
	toggle.text = "Red"
	toggle.position = Vector2(1200, 8)
	toggle.size = Vector2(70, 34)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(func() -> void: set_shown(not shown))
	add_child(toggle)
	label = Label.new()
	label.position = Vector2(860, 46)
	label.size = Vector2(410, 220)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.visible = false
	add_child(label)
	_t0 = Time.get_ticks_msec()

func set_shown(v: bool) -> void:
	shown = v
	label.visible = v
	if v: refresh()

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("net_overlay"):
		set_shown(not shown)

func _physics_process(_d: float) -> void:
	_n += 1
	if shown and _n % 10 == 0:
		refresh()

func text() -> String:
	if net == null or net.session == null:
		return "Red: sin partida"
	var s := net.session
	var us: Array[int] = s.resim_usec
	var avg := 0.0
	for v in us: avg += v
	avg /= maxf(us.size(), 1)
	var t := Time.get_ticks_msec()
	if t - _t0 >= 1000:
		kbps = float(net.link.bytes_out + net.link.bytes_in - _bytes0) / float(t - _t0)
		_bytes0 = net.link.bytes_out + net.link.bytes_in
		_t0 = t
	var st := "OK" if net.status == "" else net.status
	if net.desync_frame >= 0 and net.desync_frame < (1 << 39): st = "DESINCRONÍA tick %d" % net.desync_frame
	return "\n".join([
		"Ping %d ms   ruta %s" % [int(net.rtt_ms), "directa" if net.link.direct else "relay"],
		"Retardo %d ticks (inicio %d, cambios %d)" % [s.input_delay, net.start_delay, net.delay_changes],
		"Rollback: último %d, máx %d, total %d" % [s.last_resim, s.max_resim, s.rollbacks],
		"Ventaja %.1f  saltos %d  esperas %d" % [net.adv_avg, net.sync_skips, s.stalls],
		"Sim: paso %.0f µs, re-sim media %.0f µs" % [s.step_usec, avg],
		"Holgura de parada +%d   %.1f kB/s" % [net.parry_lenience, kbps],
		"Tick %d / confirmado %d   estado %s" % [s.frame, net.confirmed_frame(), st],
	])

func refresh() -> void:
	label.text = text()
