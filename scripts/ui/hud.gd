class_name HUD
extends CanvasLayer
## HUD: barras de vida y eikon de ambos, rondas, mensajes, botones táctiles y pantalla final.

signal restart_requested
signal lobby_requested
signal menu_opened(open: bool) ## ronda 30
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

var level_up_label: Label
var swap_bar: ProgressBar
var _run_btn: TouchScreenButton
var _run_label: Label
var controller: PlayerController
var loadout_label: Label
var _player: Fighter
var _meter_full: bool = false
var _summon_btn: TouchScreenButton
var _special_btn: TouchScreenButton
var _summon_label: Label

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
	# Ronda 29: del rival solo se ve la vida (y sus estados): ni aguante ni barra de eikon
	e_meter.visible = false
	e_stamina.visible = false
	name_p = _label(root, "Jugador", Vector2(20, 84), 18)
	name_e = _label(root, "Rival", Vector2(1280 - 420, 52), 18)
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
	_touch_button("Eikon", "summon", Vector2(150, 400), 48, Color(1.0, 0.5, 0.1))
	_touch_button("Fijar", "lock_on", Vector2(1190, 345), 38, Color(1.0, 0.3, 0.3))
	_touch_button("Objetivo", "target_next", Vector2(1190, 255), 34, Color(0.95, 0.8, 0.35))
	_touch_button("Montar", "mount", Vector2(1060, 360), 36, Color(0.7, 0.5, 0.3))
	# Ronda 15: a pie es «Correr» (alternar); montado vuelve a ser «Galope» (mantener)
	_touch_button("Correr", "run_toggle", Vector2(790, 650), 40, Color(0.95, 0.9, 0.3))
	_touch_button("Parry", "parry", Vector2(925, 530), 40, Color(0.3, 0.9, 1.0))
	_touch_button("Dash", "dash", Vector2(920, 640), 42, Color(0.6, 0.9, 0.6))
	# Ronda 14: salto y habilidad del personaje
	_touch_button("Saltar", "jump", Vector2(805, 535), 40, Color(0.75, 0.85, 1.0))
	_touch_button("Habilidad", "special", Vector2(930, 415), 40, Color(1.0, 0.45, 0.25))
	# Ronda 21: magia de eikon (a pie)
	_touch_button("Hechizo", "spell", Vector2(800, 420), 40, Color(0.7, 0.5, 1.0))
	_touch_button("↻", "spell_next", Vector2(722, 360), 24, Color(0.7, 0.5, 1.0))
	# Ronda 25: habilidad de jefe
	_touch_button("Jefe", "boss", Vector2(840, 300), 38, Color(1.0, 0.3, 0.15))
	# Ronda 32: flecha para cambiar de habilidad de jefe (botón normal: se ve en PC y en Android)
	boss_next_btn = Button.new()
	boss_next_btn.name = "BossNext"
	boss_next_btn.text = "▶"
	boss_next_btn.tooltip_text = "Siguiente habilidad de jefe (N)"
	boss_next_btn.focus_mode = Control.FOCUS_NONE
	boss_next_btn.custom_minimum_size = Vector2(44, 44)
	boss_next_btn.position = Vector2(884, 278)
	boss_next_btn.add_theme_font_size_override("font_size", 22)
	boss_next_btn.pressed.connect(func() -> void:
		if _player:
			_player.cycle_boss())
	add_child(boss_next_btn)
	for l: Label in [round_label, timer_label, message]:
		l.add_theme_font_override("font", UIKit.display_font())
		l.add_theme_color_override("font_color", UIKit.TEXT)
		l.add_theme_color_override("font_outline_color", UIKit.OUTLINE)
		l.add_theme_constant_override("outline_size", 4)
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
	var o1 := UIKit.ornament_line(460)
	o1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(o1)
	end_label = UIKit.title("", 58)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_label)
	var o2 := UIKit.ornament_line(460)
	o2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(o2)
	results_box = VBoxContainer.new()
	results_box.name = "ResultsBox"
	results_box.add_theme_constant_override("separation", 4)
	vb.add_child(results_box)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var btn := UIKit.button("Revancha", 21)
	btn.custom_minimum_size = Vector2(190, 56)
	btn.pressed.connect(func() -> void: restart_requested.emit())
	hb.add_child(btn)
	var lb := UIKit.big_button("Volver al lobby", 22)
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
	var fill := UIKit.box(c, Color(0, 0, 0, 0), 0, 2, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	var bg := UIKit.box(Color(0.0, 0.03, 0.1, 0.6), Color(UIKit.SILVER, 0.7), 1, 2, 4)
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

var btns: Dictionary = {} ## ronda 21: acción -> TouchScreenButton
var btn_labels: Dictionary = {}
var boss_next_btn: Button

func _touch_button(text: String, action: String, center: Vector2, r: float, c: Color) -> void:
	var tb := TouchScreenButton.new()
	tb.name = "Btn_" + action
	btns[action] = tb
	if action == "summon":
		_summon_btn = tb
		tb.modulate = Color(1, 1, 1, 0.55)
	if action == "special":
		_special_btn = tb
	if action == "run_toggle":
		_run_btn = tb
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
	btn_labels[action] = l
	if action == "summon":
		_summon_label = l
	if action == "run_toggle":
		_run_label = l

class _Circle extends Node2D:
	var r: float = 40.0
	var c: Color = Color.WHITE
	func _draw() -> void:
		draw_circle(Vector2.ZERO, r, Color(c, 0.35))
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(c, 0.8), 3.0)

## Ronda 20: barras de acumulación de estados (HUD propio, del rival y sobre el rival).
var status_p: Dictionary = {}
var status_e: Dictionary = {}
var status_over: Dictionary = {}
var status_over_box: VBoxContainer
var _enemy: Fighter

func _status_rows(parent: Control, pos: Vector2, w: float, nm: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = nm
	box.position = pos
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var out := {"box": box}
	for k: String in StatusFx.TYPES:
		var row := HBoxContainer.new()
		row.name = "Row_" + k
		row.add_theme_constant_override("separation", 4)
		var l := UIKit.label(StatusFx.NAMES[k], 12, StatusFx.COLORS[k])
		l.custom_minimum_size = Vector2(78, 0)
		row.add_child(l)
		var b := ProgressBar.new()
		b.name = "Bar_" + k
		b.show_percentage = false
		b.custom_minimum_size = Vector2(w, 7)
		b.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = StatusFx.COLORS[k]
		b.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		b.add_theme_stylebox_override("background", bg)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		row.visible = false
		box.add_child(row)
		out[k] = row
	return out

func _update_status(rows: Dictionary, f: Fighter) -> void:
	if rows.is_empty() or f == null:
		return
	for k: String in StatusFx.TYPES:
		var row: HBoxContainer = rows[k]
		var fr := f.status_fraction(k)
		var active := (k == "veneno" and f.status_fx.poison_t > 0.0) or (k == "congelacion" and f.status_fx.frost_t > 0.0)
		row.visible = fr > 0.001 or active
		var b := row.get_child(1) as ProgressBar
		b.value = 1.0 if active else fr
		var secs := ceili(f.status_fx.poison_t if k == "veneno" else f.status_fx.frost_t) if active else -1
		if _changed(row, secs):
			(row.get_child(0) as Label).text = StatusFx.NAMES[k] + (" %ds" % secs if active else "")

## Ronda 26: ¿cambió la clave de lo que muestra `n`? (evita formatear cadenas cada fotograma)
var _keys: Dictionary = {}
func _changed(n: Object, key: Variant) -> bool:
	var id := n.get_instance_id()
	if _keys.has(id) and _keys[id] == key:
		return false
	_keys[id] = key
	return true

func _process(_d: float) -> void:
	if _player == null:
		return
	_update_status(status_p, _player)
	_update_status(status_e, _enemy)
	_update_status(status_over, _enemy)
	if status_over_box and is_instance_valid(_enemy):
		var cam := get_viewport().get_camera_3d()
		var head := _enemy.global_position + Vector3(0, 3.2 if _enemy.mounted else 2.5, 0)
		status_over_box.visible = cam != null and not cam.is_position_behind(head)
		if status_over_box.visible:
			status_over_box.position = cam.unproject_position(head) - Vector2(70, 30)
	swap_bar.visible = _player.is_swapping()
	swap_bar.value = _player.swap_progress()
	# Ronda 26: el texto solo se reconstruye si cambia lo que muestra
	var ek_on := is_instance_valid(_player.active_eikon)
	var lkey := [_player.is_swapping(), _player.loadout, _player.melee(), _player.ranged(), ceili(_player.eikon_time_left()) if ek_on else -1]
	if _changed(loadout_label, lkey):
		if _player.is_swapping():
			loadout_label.text = "Cambiando de arma..."
		else:
			loadout_label.text = _player.melee().display_name if _player.loadout == Fighter.Loadout.SWORD_SHIELD else _player.ranged().display_name
		# Eikon activo: tiempo restante; montado en él, el botón Eikon lanza su especial
		if ek_on:
			loadout_label.text += "   ·   %s %d s" % [_player.eikon.eikon_name, ceili(_player.eikon_time_left())]
	var riding_eikon := _player.mounted and _player.mount_node != null and _player.mount_node.eikon != null
	if _summon_label:
		if _changed(_summon_label, riding_eikon):
			_summon_label.text = "Especial" if riding_eikon else "Eikon"
		if riding_eikon:
			_summon_btn.modulate = Color(1.6, 1.4, 1.0) if _player.mount_node.special_cd <= 0.0 else Color(1, 1, 1, 0.55)
	if _run_btn:
		var on: bool = controller != null and controller.run_toggled
		_run_btn.action = "sprint" if _player.mounted else "run_toggle"
		if _changed(_run_label, [_player.mounted, on]):
			_run_label.text = "Galope" if _player.mounted else ("Correr ✔" if on else "Correr")
		_run_btn.modulate = Color(1.5, 1.4, 0.9) if (on or _player.sprinting) else Color.WHITE
	if _special_btn:
		# Ronda 22: Habilidad/Arte no se usan montado: se oculta
		_special_btn.visible = (_player.has_special() or _player.weapon_art_id != "") and joystick.visible and not _player.mounted
		var cd := _player.special_cd if _player.has_special() else _player.art_cd
		_special_btn.modulate = Color.WHITE if cd <= 0.0 else Color(1, 1, 1, 0.45)
		if not _player.has_special() and btn_labels.has("special") and _changed(btn_labels["special"], "Arte"):
			(btn_labels["special"] as Label).text = "Arte"
	_update_contextual_buttons()

## Ronda 21: botones según el contexto. Parry desaparece montado; «Objetivo» solo con 2+ objetivos;
## «Hechizo» solo a pie y con hechizos equipados.
func _update_contextual_buttons() -> void:
	var tv := joystick.visible
	(btns["parry"] as TouchScreenButton).visible = tv and not _player.mounted
	(btns["boss"] as TouchScreenButton).visible = tv and not _player.mounted
	if boss_next_btn:
		boss_next_btn.visible = not _player.mounted and _player.boss_ids.size() > 1
	# Ronda 31: sin recarga; habilidad seleccionada y su coste
	var bid := _player.selected_boss()
	(btns["boss"] as TouchScreenButton).modulate = Color.WHITE if bid != "" and _player.boss_cost_ok(bid) else Color(1, 1, 1, 0.45)
	if _changed(btn_labels["boss"], bid):
		(btn_labels["boss"] as Label).text = (String(BossAbilities.def(bid)["name"]).split(" ")[0] + "\n" + BossAbilities.cost_text(bid)) if bid != "" else "Jefe"
	# Eikon: solo cuando se puede invocar (o montado en tu eikon, para su especial)
	var riding := _player.mounted and _player.mount_node != null and _player.mount_node.eikon != null
	(btns["summon"] as TouchScreenButton).visible = tv and (_player.can_summon() or riding)
	if not riding and _player.can_summon():
		_summon_btn.modulate = Color(1.6, 1.4, 1.0)
	# Montar: solo con un eikon activo en la arena
	(btns["mount"] as TouchScreenButton).visible = tv and _player.has_active_eikon()
	(btns["target_next"] as TouchScreenButton).visible = tv and controller != null and controller.can_cycle_target()
	var magic := _player.has_spells() and not _player.mounted
	(btns["spell"] as TouchScreenButton).visible = tv and magic
	(btns["spell_next"] as TouchScreenButton).visible = tv and magic and _player.spells.filter(func(x) -> bool: return String(x) != "").size() > 1
	if magic:
		var id := _player.current_spell()
		var cd := _player.spell_cd_left()
		var csec := ceilf(cd) if cd > 0.0 else -1.0
		if _changed(btn_labels["spell"], [id, csec]):
			(btn_labels["spell"] as Label).text = (EikonSpells.name_of(id).split(" ")[0] + ("\n%.0f" % csec if cd > 0.0 else ""))
		(btns["spell"] as TouchScreenButton).modulate = Color.WHITE if _player.can_cast() else Color(1, 1, 1, 0.45)

func bind(player: Fighter, enemy: Fighter) -> void:
	_player = player
	_enemy = enemy
	status_p = _status_rows(root_control(), Vector2(20, 136), 150, "StatusPlayer")
	status_e = _status_rows(root_control(), Vector2(1280 - 420, 78), 150, "StatusEnemy")
	status_over = _status_rows(root_control(), Vector2.ZERO, 60, "StatusOverTarget")
	status_over_box = status_over["box"]
	_build_pause_menu() # ronda 30
	name_p.text = player.display_name
	name_e.text = enemy.display_name
	# Respuesta al pulsar Eikon (E / botón): antes no pasaba nada visible si el medidor no estaba lleno
	player.summon_failed.connect(_on_summon_failed)
	# Ronda 24: avisos del intercambio
	player.counter_landed.connect(func(_t: Node3D) -> void: show_message("¡Contraataque!", 0.5))
	player.critical_landed.connect(func(_t: Node3D, d: float) -> void: show_message("¡Crítico! %d" % int(d), 0.9))
	enemy.stance_broken.connect(func() -> void: show_message("¡Postura rota! Ataca de frente", 1.0))
	player.stance_broken.connect(func() -> void: show_message("¡Tu postura se rompió!", 0.9))
	player.summoned.connect(func(e: Node3D) -> void:
		var ed: EikonData = (e as Mount).eikon if e is Mount else (e as Eikon).data
		show_message(("¡%s! Montado (E: %s)" % [ed.eikon_name, ed.special_name]) if ed.rideable else "¡%s invocado!" % ed.eikon_name, 1.2))
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
		sb.max_value = f.stamina_max
		sb.value = f.stamina
		f.stamina_changed.connect(func(v: float, ex: bool) -> void:
			sb.value = v
			sb.modulate = Color(1, 0.4, 0.4) if ex else Color.WHITE)

	# Ronda 18: barra de Energía (Concentración) para las habilidades (Golpe sísmico)
	if player.has_special() or player.has_spells() or player.weapon_art_id != "":
		energy_bar = _bar(root_control(), Vector2(20, 82), Color(0.62, 0.45, 1.0), 6)
		energy_bar.name = "EnergyBar"
		energy_bar.max_value = player.energy_max
		energy_bar.value = player.energy
		player.energy_changed.connect(func(v: float, m: float) -> void:
			energy_bar.max_value = m
			energy_bar.value = v)

var energy_bar: ProgressBar
func root_control() -> Control:
	return p_health.get_parent()

func _on_summon_failed(reason: String) -> void:
	if reason == "meter":
		show_message("Eikon: medidor al %d %%" % int(_player.meter), 0.8)
	elif reason == "active":
		show_message("El eikon ya está luchando" if not _player.eikon.rideable else "Tu eikon te espera: F para montar", 0.8)
	elif reason == "busy":
		show_message("Termina la acción para invocar", 0.8)
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
	# Pantalla de victoria al estilo Final Fantasy: estandarte "VICTORIA" y filas EXP / Oro
	end_label.text = "VICTORIA" if won else "DERROTA"
	end_label.add_theme_color_override("font_color", UIKit.YELLOW if won else UIKit.MUTED)
	for c in results_box.get_children():
		c.queue_free()
	level_up_label = null
	if not res.is_empty():
		results_box.add_child(_row("", "EXP", "Oro", UIKit.MUTED, 15))
		for l: Array in res["lines"]:
			results_box.add_child(_row(l[0], "+%d" % l[1], ("+%d" % l[2]) if l[2] > 0 else "—", UIKit.TEXT, 18))
		if absf(float(res["mult"]) - 1.0) > 0.01:
			results_box.add_child(_row("Dificultad", "×%.1f" % res["mult"], "×%.1f" % res["mult"], UIKit.MUTED, 16))
		if int(res["level_bonus"]) > 0:
			results_box.add_child(_row("Bonificación de nivel", "", "+%d" % res["level_bonus"], UIKit.MUTED, 16))
		var sep := UIKit.ornament_line(440)
		sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		results_box.add_child(sep)
		var tot := UIKit.title("EXP obtenida  %d      Oro obtenido  %d" % [res["xp"], res["gold"]], 22, UIKit.YELLOW)
		tot.name = "Total"
		tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_box.add_child(tot)
		var stn: Dictionary = res.get("stones", {})
		if not stn.is_empty():
			var parts: Array = []
			for sid: String in stn:
				parts.append("%d× %s" % [stn[sid], Smithing.STONE_NAMES[sid]])
			results_box.add_child(_row("Materiales", "", ", ".join(parts), UIKit.CYAN, 15))
		var lp := Progression.level_progress(int(res["account_xp"]))
		var lvl := _row("Nivel %d" % res["account_after"], "", "Siguiente: %d" % (lp.y - lp.x), UIKit.TEXT, 16)
		results_box.add_child(lvl)
		var bar := ProgressBar.new()
		bar.name = "XPBar"
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(440, 8)
		bar.max_value = lp.y
		var lp0 := Progression.level_progress(int(res["account_xp_before"]))
		bar.value = lp0.x if res["account_before"] == res["account_after"] else 0
		results_box.add_child(bar)
		bar.create_tween().tween_property(bar, "value", float(lp.x), 1.4).set_delay(0.6).set_trans(Tween.TRANS_SINE)
		var ups: Array[String] = []
		if res["account_after"] > res["account_before"]:
			ups.append("Nivel de cuenta %d alcanzado" % res["account_after"])
		if res["char_after"] > res["char_before"]:
			ups.append("%s · nivel %d · +%d habilidad" % [Catalog.character(res["character"]).display_name, res["char_after"], res["char_after"] - res["char_before"]])
		if not ups.is_empty():
			level_up_label = UIKit.title("\n".join(ups), 19, UIKit.CYAN)
			level_up_label.name = "LevelUp"
			level_up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			level_up_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			level_up_label.custom_minimum_size = Vector2(460, 0)
			results_box.add_child(level_up_label)
			UIKit.sfx("levelup")
	end_panel.visible = true
	set_touch_visible(false)
	end_panel.size = Vector2(540, 0)
	end_panel.reset_size()
	await get_tree().process_frame
	end_panel.reset_size()
	end_panel.position = Vector2((1280 - end_panel.size.x) * 0.5, maxf((720 - end_panel.size.y) * 0.5, 10))
	UIKit.pop_in(end_panel, 0.0)
	if won:
		var sh := UIKit.crystal_shards(self, 30, Rect2(end_panel.position.x, end_panel.position.y + end_panel.size.y, end_panel.size.x, 10))
		sh.name = "VictoryShards"

## Fila de la tabla de resultados: concepto a la izquierda, EXP y oro alineados a la derecha.
func _row(a: String, xp: String, gold: String, c: Color, fs: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	var la := UIKit.label(a, fs, c)
	la.custom_minimum_size = Vector2(250, 0)
	h.add_child(la)
	for t: String in [xp, gold]:
		var l := UIKit.label(t, fs, c if t != "" and c == UIKit.TEXT else c)
		l.custom_minimum_size = Vector2(95, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return h




# ---------------- Ronda 30: menú de pausa SIN pausa ----------------
## Esc (o ≡ en Android) abre el menú. El juego NO se detiene (es 1v1 en tiempo real, como en los
## soulslike): mientras está abierto tu personaje se queda quieto y en guardia.
var pause_menu: Control
var pause_settings: VBoxContainer
var menu_button: Button

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.name = "PauseMenu"
	pause_menu.visible = false
	pause_menu.size = Vector2(1280, 720)
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control().add_child(pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.08, 0.35)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(440, 150)
	p.custom_minimum_size = Vector2(400, 0)
	pause_menu.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.title("MENÚ", 28, UIKit.YELLOW))
	v.add_child(UIKit.label("El combate sigue: tu personaje se cubre", 14, UIKit.MUTED))
	for it: Array in [["Continuar", "PauseContinue", close_pause], ["Ajustes", "PauseSettings", func() -> void: pause_settings.visible = not pause_settings.visible],
			["Salir al lobby", "PauseExit", func() -> void:
				close_pause()
				lobby_requested.emit()]]:
		var b := UIKit.button(it[0], 20)
		b.name = it[1]
		b.custom_minimum_size = Vector2(380, 50)
		b.pressed.connect(it[2])
		v.add_child(b)
	pause_settings = VBoxContainer.new()
	pause_settings.name = "PauseSettingsBox"
	pause_settings.visible = false
	v.add_child(pause_settings)
	var au := get_node_or_null("/root/Audio")
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Cámara", 16))
	var cs := HSlider.new()
	cs.name = "PauseCamSens"
	cs.min_value = 0.2
	cs.max_value = 3.0
	cs.step = 0.1
	cs.value = CameraRig.sensitivity
	cs.custom_minimum_size = Vector2(260, 30)
	cs.value_changed.connect(func(x: float) -> void:
		CameraRig.sensitivity = x
		if au: au.save_settings())
	row.add_child(cs)
	pause_settings.add_child(row)
	var vrow := HBoxContainer.new()
	vrow.add_child(UIKit.label("Volumen", 16))
	var vs := HSlider.new()
	vs.name = "PauseVolume"
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = au.get_volume("Master") if au else 1.0
	vs.custom_minimum_size = Vector2(260, 30)
	vs.value_changed.connect(func(x: float) -> void:
		if au: au.set_volume("Master", x))
	vrow.add_child(vs)
	pause_settings.add_child(vrow)
	var inv := CheckBox.new()
	inv.name = "PauseInvertY"
	inv.text = "Invertir Y"
	inv.button_pressed = CameraRig.invert_y
	inv.toggled.connect(func(on: bool) -> void:
		CameraRig.invert_y = on
		if au: au.save_settings())
	pause_settings.add_child(inv)
	menu_button = UIKit.button("≡", 22)
	menu_button.name = "MenuButton"
	menu_button.position = Vector2(1280 - 56, 100)
	menu_button.custom_minimum_size = Vector2(44, 44)
	menu_button.pressed.connect(toggle_pause)
	root_control().add_child(menu_button)

func is_pause_open() -> bool:
	return pause_menu != null and pause_menu.visible

func toggle_pause() -> void:
	if is_pause_open():
		close_pause()
	else:
		open_pause()

func open_pause() -> void:
	if pause_menu == null or end_panel.visible:
		return
	pause_menu.visible = true
	pause_settings.visible = false
	if controller:
		controller.menu_hold = true
	menu_opened.emit(true)

func close_pause() -> void:
	if pause_menu == null:
		return
	pause_menu.visible = false
	if controller:
		controller.menu_hold = false
	menu_opened.emit(false)
