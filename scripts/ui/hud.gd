class_name HUD
extends CanvasLayer
## HUD: barras de vida y eikon de ambos, rondas, mensajes, botones táctiles y pantalla final.

signal restart_requested
signal lobby_requested
var name_p: Label
var name_e: Label

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
var results_box: VBoxContainer
var stars_box: HBoxContainer
var stars: int = 0 ## estrellas de la última partida (0-3)
var coins_burst: int = 0 ## monedas lanzadas en la animación (pruebas)
var level_up_label: Label
var swap_bar: ProgressBar
var loadout_label: Label
var _player: Fighter
var _meter_full: bool = false
var _summon_btn: TouchScreenButton

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	p_health = _bar(root, Vector2(20, 20), UIKit.GREEN)
	p_meter = _bar(root, Vector2(20, 52), UIKit.ORANGE, 14)
	e_health = _bar(root, Vector2(1280 - 420, 20), UIKit.RED)
	e_meter = _bar(root, Vector2(1280 - 420, 52), UIKit.CYAN, 14)
	p_stamina = _bar(root, Vector2(20, 70), UIKit.YELLOW, 10)
	e_stamina = _bar(root, Vector2(1280 - 420, 70), UIKit.YELLOW, 10)
	name_p = _label(root, "Jugador", Vector2(20, 84), 18)
	name_e = _label(root, "Rival", Vector2(1280 - 420, 84), 18)
	loadout_label = _label(root, "Espada y escudo", Vector2(20, 108), 18)
	swap_bar = _bar(root, Vector2(20, 112), Color(0.8, 0.8, 1.0), 12)
	swap_bar.size = Vector2(250, 12)
	swap_bar.max_value = 1.0
	swap_bar.visible = false
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
	_touch_button("Atacar", "attack_sword", Vector2(1160, 600), 62, Color(0.85, 0.85, 0.9))
	_touch_button("Escudo", "block", Vector2(1030, 640), 52, Color(0.4, 0.5, 0.9))
	_touch_button("Cambiar", "swap_weapon", Vector2(1180, 465), 48, Color(0.8, 0.65, 0.3))
	_touch_button("Eikon", "summon", Vector2(1050, 500), 48, Color(1.0, 0.5, 0.1))
	_touch_button("Fijar", "lock_on", Vector2(1190, 345), 38, Color(1.0, 0.3, 0.3))
	_touch_button("Montar", "mount", Vector2(1060, 360), 36, Color(0.7, 0.5, 0.3))
	_touch_button("Galope", "sprint", Vector2(790, 650), 40, Color(0.95, 0.9, 0.3))
	_touch_button("Parry", "parry", Vector2(925, 530), 40, Color(0.3, 0.9, 1.0))
	_touch_button("Dash", "dash", Vector2(920, 640), 42, Color(0.6, 0.9, 0.6))
	for l: Label in [round_label, timer_label, message]:
		l.add_theme_font_override("font", UIKit.display_font())
		l.add_theme_color_override("font_color", UIKit.TEXT)
		l.add_theme_color_override("font_outline_color", UIKit.OUTLINE)
		l.add_theme_constant_override("outline_size", 8)
	# Panel final / pantalla de resultados
	end_panel = UIKit.panel()
	end_panel.name = "Results"
	end_panel.position = Vector2(390, 110)
	end_panel.custom_minimum_size = Vector2(500, 0)
	end_panel.size = Vector2(500, 200)
	root.add_child(end_panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	end_panel.add_child(vb)
	end_label = UIKit.title("", 54)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_label)
	stars_box = HBoxContainer.new()
	stars_box.name = "Stars"
	stars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_box.add_theme_constant_override("separation", 10)
	vb.add_child(stars_box)
	results_box = VBoxContainer.new()
	results_box.name = "ResultsBox"
	results_box.add_theme_constant_override("separation", 4)
	vb.add_child(results_box)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var btn := UIKit.button("Revancha", 24, UIKit.BLUE)
	btn.custom_minimum_size = Vector2(190, 56)
	btn.pressed.connect(func() -> void: restart_requested.emit())
	hb.add_child(btn)
	var lb := UIKit.big_button("Volver al lobby", 24, UIKit.YELLOW)
	lb.name = "LobbyButton"
	lb.custom_minimum_size = Vector2(230, 56)
	lb.pressed.connect(func() -> void: lobby_requested.emit())
	hb.add_child(lb)
	end_panel.visible = false

func _bar(parent: Control, pos: Vector2, c: Color, h: float = 26) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(400, h)
	b.show_percentage = false
	var fill := UIKit.box(c, Color(0, 0, 0, 0), 0, 8, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	var bg := UIKit.box(Color(0.02, 0.08, 0.2, 0.75), Color(1, 1, 1, 0.8), 2, 8, 4)
	bg.border_width_bottom = 2
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
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

## Oculta/muestra los controles táctiles (no tapan la pantalla de resultados).
func set_touch_visible(v: bool) -> void:
	joystick.visible = v
	for c in get_children():
		if c is TouchScreenButton:
			(c as TouchScreenButton).visible = v

func _touch_button(text: String, action: String, center: Vector2, r: float, c: Color) -> void:
	var tb := TouchScreenButton.new()
	if action == "summon":
		_summon_btn = tb
		tb.modulate = Color(1, 1, 1, 0.55)
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

func _process(_d: float) -> void:
	if _player == null:
		return
	swap_bar.visible = _player.is_swapping()
	swap_bar.value = _player.swap_progress()
	if _player.is_swapping():
		loadout_label.text = "Cambiando de arma..."
	else:
		loadout_label.text = _player.melee().display_name if _player.loadout == Fighter.Loadout.SWORD_SHIELD else "Arco"

func bind(player: Fighter, enemy: Fighter) -> void:
	_player = player
	name_p.text = player.display_name
	name_e.text = enemy.display_name
	# Respuesta al pulsar Eikon (E / botón): antes no pasaba nada visible si el medidor no estaba lleno
	player.summon_failed.connect(_on_summon_failed)
	player.summoned.connect(func(e: Node3D) -> void:
		show_message("¡%s invocado!" % (e as Eikon).data.eikon_name, 1.0))
	player.meter_changed.connect(func(v: float) -> void:
		var full := v >= Fighter.METER_MAX
		if full and not _meter_full:
			show_message("¡Eikon listo! (E / botón Eikon)", 1.2)
		_meter_full = full
		if _summon_btn:
			_summon_btn.modulate = Color(1.6, 1.4, 1.0) if full else Color(1, 1, 1, 0.55))
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

func _on_summon_failed(reason: String) -> void:
	if reason == "meter":
		show_message("Eikon: medidor al %d %%" % int(_player.meter), 0.8)
	elif reason == "active":
		show_message("El eikon ya está luchando", 0.8)
	else:
		show_message("No puedes invocar aturdido", 0.8)

func show_message(t: String, secs: float = 2.0) -> void:
	message.text = t
	message.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(message, "modulate:a", 0.0, 0.4)

## Pantalla de resultados: desglose de XP y oro, barra de nivel y subidas de nivel.
func show_results(won: bool, res: Dictionary) -> void:
	end_label.text = "¡VICTORIA!" if won else "DERROTA"
	end_label.add_theme_color_override("font_color", UIKit.YELLOW if won else UIKit.MUTED)
	# Estrellas: victoria 2-0 = 3, victoria 2-1 = 2, derrota con alguna ronda = 1, si no 0
	var rounds: int = 0
	if not res.is_empty():
		for l: Array in res["lines"]:
			if String(l[0]).begins_with("Rondas"):
				rounds = int(String(l[0]).get_slice("×", 1))
	stars = (3 if rounds >= 2 and res.get("perfect", false) else 2) if won else (1 if rounds > 0 else 0)
	if won and res.is_empty():
		stars = 2
	for c in stars_box.get_children():
		c.queue_free()
	for i in 3:
		var st := CurrencyIcon.new()
		st.kind = "star"
		st.filled = i < stars
		st.custom_minimum_size = Vector2(64, 64) if i == 1 else Vector2(52, 52)
		stars_box.add_child(st)
		UIKit.pop_in(st, 0.3 + i * 0.2, 0.2)
	for c in results_box.get_children():
		c.queue_free()
	level_up_label = null
	if not res.is_empty():
		for l: Array in res["lines"]:
			var h := HBoxContainer.new()
			var a := UIKit.label(l[0], 19, UIKit.TEXT)
			a.custom_minimum_size = Vector2(230, 0)
			h.add_child(a)
			h.add_child(UIKit.label("+%d XP" % l[1], 19, UIKit.ORANGE))
			var g := UIKit.label("   +%d oro" % l[2] if l[2] > 0 else "", 19, UIKit.YELLOW)
			h.add_child(g)
			results_box.add_child(h)
		if absf(float(res["mult"]) - 1.0) > 0.01:
			results_box.add_child(UIKit.label("Dificultad ×%.1f" % res["mult"], 17, UIKit.MUTED))
		if int(res["level_bonus"]) > 0:
			results_box.add_child(UIKit.label("Bonus por subir de nivel: +%d oro" % res["level_bonus"], 17, UIKit.YELLOW))
		var tot := UIKit.title("Total: +%d XP · +%d oro" % [res["xp"], res["gold"]], 26, UIKit.YELLOW)
		tot.name = "Total"
		tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_box.add_child(tot)
		var lp := Progression.level_progress(int(res["account_xp"]))
		var bar := ProgressBar.new()
		bar.name = "XPBar"
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(440, 14)
		bar.max_value = lp.y
		var lp0 := Progression.level_progress(int(res["account_xp_before"]))
		bar.value = lp0.x if res["account_before"] == res["account_after"] else 0
		results_box.add_child(bar)
		bar.create_tween().tween_property(bar, "value", float(lp.x), 1.2).set_delay(0.3)
		results_box.add_child(UIKit.label("Nivel de cuenta %d · %d/%d XP" % [res["account_after"], lp.x, lp.y], 17, UIKit.MUTED))
		var ups: Array[String] = []
		if res["account_after"] > res["account_before"]:
			ups.append("¡Cuenta nivel %d!" % res["account_after"])
		if res["char_after"] > res["char_before"]:
			ups.append("¡%s nivel %d! +%d punto(s) de habilidad" % [Catalog.character(res["character"]).display_name, res["char_after"], res["char_after"] - res["char_before"]])
		if not ups.is_empty():
			level_up_label = UIKit.title(" · ".join(ups), 22, UIKit.GREEN)
			level_up_label.name = "LevelUp"
			level_up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			level_up_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			level_up_label.custom_minimum_size = Vector2(460, 0)
			results_box.add_child(level_up_label)
			var tw := level_up_label.create_tween().set_loops(4)
			tw.tween_property(level_up_label, "modulate", Color(1.4, 1.2, 0.8), 0.35)
			tw.tween_property(level_up_label, "modulate", Color.WHITE, 0.35)
			UIKit.sfx("levelup")
	end_panel.visible = true
	set_touch_visible(false)
	end_panel.size = Vector2(520, 0)
	end_panel.reset_size()
	await get_tree().process_frame
	end_panel.reset_size()
	end_panel.position = Vector2((1280 - end_panel.size.x) * 0.5, maxf((720 - end_panel.size.y) * 0.5, 10))
	UIKit.pop_in(end_panel, 0.0, 0.7)
	if not res.is_empty() and int(res["gold"]) > 0:
		_coin_burst(end_panel.position + end_panel.size * Vector2(0.5, 0.45), mini(8 + int(res["gold"]) / 20, 24))

## Lluvia de monedas que salen del centro y vuelan hacia el contador (arriba a la derecha).
func _coin_burst(from: Vector2, n: int) -> void:
	coins_burst = n
	for i in n:
		var c := CurrencyIcon.new()
		c.kind = "oro"
		c.size = Vector2(30, 30)
		c.position = from
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
		var a := randf() * TAU
		var mid := from + Vector2(cos(a), sin(a)) * randf_range(80, 200)
		var tw := c.create_tween()
		tw.tween_property(c, "position", mid, 0.4).set_delay(0.5 + i * 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", Vector2(1180, 10), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(c.queue_free)
		if i % 4 == 0:
			tw.tween_callback(func() -> void: UIKit.sfx("click"))

