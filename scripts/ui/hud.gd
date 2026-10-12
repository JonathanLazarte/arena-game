class_name HUD
extends CanvasLayer
## HUD: barras de vida y eikon de ambos, rondas, mensajes, botones táctiles y pantalla final.

signal restart_requested

var joystick: TouchStick
var p_health: ProgressBar
var p_meter: ProgressBar
var e_health: ProgressBar
var e_meter: ProgressBar
var p_stamina: ProgressBar
var e_stamina: ProgressBar
var round_label: Label
var timer_label: Label
var message: Label
var end_panel: PanelContainer
var end_label: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	p_health = _bar(root, Vector2(20, 20), Color(0.2, 0.85, 0.3))
	p_meter = _bar(root, Vector2(20, 52), Color(1.0, 0.6, 0.1), 14)
	e_health = _bar(root, Vector2(1280 - 420, 20), Color(0.9, 0.2, 0.2))
	e_meter = _bar(root, Vector2(1280 - 420, 52), Color(0.4, 0.8, 1.0), 14)
	p_stamina = _bar(root, Vector2(20, 70), Color(0.95, 0.9, 0.3), 10)
	e_stamina = _bar(root, Vector2(1280 - 420, 70), Color(0.95, 0.9, 0.3), 10)
	_label(root, "Jugador", Vector2(20, 84), 18)
	_label(root, "Rival", Vector2(1280 - 420, 84), 18)
	round_label = _label(root, "Ronda 1   0 - 0", Vector2(540, 16), 24)
	round_label.size = Vector2(200, 30)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label = _label(root, "90", Vector2(610, 48), 30)
	timer_label.size = Vector2(60, 36)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message = _label(root, "", Vector2(240, 250), 48)
	message.size = Vector2(800, 80)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Controles táctiles
	joystick = TouchStick.new()
	joystick.position = Vector2(150, 570)
	add_child(joystick)
	_touch_button("Espada", "attack_sword", Vector2(1160, 600), 62, Color(0.85, 0.85, 0.9))
	_touch_button("Escudo", "block", Vector2(1030, 640), 52, Color(0.4, 0.5, 0.9))
	_touch_button("Arco", "shoot_bow", Vector2(1180, 465), 48, Color(0.8, 0.65, 0.3))
	_touch_button("Eikon", "summon", Vector2(1050, 500), 48, Color(1.0, 0.5, 0.1))
	_touch_button("Fijar", "lock_on", Vector2(1190, 345), 38, Color(1.0, 0.3, 0.3))
	_touch_button("Montar", "mount", Vector2(1060, 360), 36, Color(0.7, 0.5, 0.3))
	_touch_button("Galope", "sprint", Vector2(790, 650), 40, Color(0.95, 0.9, 0.3))
	_touch_button("Dash", "dash", Vector2(920, 640), 42, Color(0.6, 0.9, 0.6))
	# Panel final
	end_panel = PanelContainer.new()
	end_panel.position = Vector2(440, 220)
	end_panel.size = Vector2(400, 220)
	root.add_child(end_panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	end_panel.add_child(vb)
	end_label = Label.new()
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.add_theme_font_size_override("font_size", 40)
	vb.add_child(end_label)
	var btn := Button.new()
	btn.text = "Reiniciar"
	btn.add_theme_font_size_override("font_size", 28)
	btn.pressed.connect(func() -> void: restart_requested.emit())
	vb.add_child(btn)
	end_panel.visible = false

func _bar(parent: Control, pos: Vector2, c: Color, h: float = 26) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(400, h)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func _label(parent: Control, t: String, pos: Vector2, fs: int) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _touch_button(text: String, action: String, center: Vector2, r: float, c: Color) -> void:
	var tb := TouchScreenButton.new()
	var shape := CircleShape2D.new()
	shape.radius = r
	tb.shape = shape
	tb.shape_centered = true
	tb.action = action
	tb.position = center
	add_child(tb)
	var vis := _Circle.new()
	vis.r = r
	vis.c = c
	tb.add_child(vis)
	var l := Label.new()
	l.text = text
	l.size = Vector2(r * 2, 30)
	l.position = Vector2(-r, -14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	tb.add_child(l)

class _Circle extends Node2D:
	var r: float = 40.0
	var c: Color = Color.WHITE
	func _draw() -> void:
		draw_circle(Vector2.ZERO, r, Color(c, 0.35))
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(c, 0.8), 3.0)

func bind(player: Fighter, enemy: Fighter) -> void:
	for pair: Array in [[player, p_health, p_meter, p_stamina], [enemy, e_health, e_meter, e_stamina]]:
		var f: Fighter = pair[0]
		var hb: ProgressBar = pair[1]
		var mb: ProgressBar = pair[2]
		hb.max_value = f.max_health
		hb.value = f.health
		mb.max_value = Fighter.METER_MAX
		mb.value = f.meter
		f.health_changed.connect(func(v: float, m: float) -> void:
			hb.max_value = m
			hb.value = v)
		f.meter_changed.connect(func(v: float) -> void: mb.value = v)
		var sb: ProgressBar = pair[3]
		sb.max_value = Fighter.STAMINA_MAX
		sb.value = f.stamina
		f.stamina_changed.connect(func(v: float, ex: bool) -> void:
			sb.value = v
			sb.modulate = Color(1, 0.4, 0.4) if ex else Color.WHITE)

func show_message(t: String, secs: float = 2.0) -> void:
	message.text = t
	message.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(message, "modulate:a", 0.0, 0.4)
