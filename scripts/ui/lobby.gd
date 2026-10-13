extends Node3D
## Lobby principal (estilo "sala" de Free Fire, simplificado). Personaje en un pedestal
## giratorio, pestañas de equipamiento, dificultad y botón JUGAR. Todo el texto en español.

const PROPS := "res://assets/props/"
const TABS := ["Personajes", "Armas", "Eikons", "Monturas", "Inventario"]
const GOLD := Color(0.95, 0.78, 0.35)
const STAT_MAX := {"vida": 140.0, "estamina": 120.0, "velocidad": 1.25, "poise": 90.0, "dano": 1.25}

var gs: Node
var pedestal: Node3D
var preview: KnightVisual
var tab: String = "Personajes"
var ui: CanvasLayer
var tab_buttons: Dictionary = {}
var diff_buttons: Dictionary = {}
var list_box: VBoxContainer
var detail: RichTextLabel
var stats_box: VBoxContainer
var name_label: Label
var role_label: Label
var oro_label: Label
var play_button: Button
var spin_speed: float = 0.35

func _ready() -> void:
	gs = get_node("/root/GameState")
	gs.from_lobby = false
	_build_world()
	_build_ui()
	_refresh_all()

# ---------------- Mundo 3D ----------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.12, 0.12, 0.3)
	sm.sky_horizon_color = Color(0.95, 0.55, 0.3)
	sm.ground_bottom_color = Color(0.1, 0.08, 0.07)
	sm.ground_horizon_color = Color(0.5, 0.35, 0.25)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.45, 0.35)
	e.fog_density = 0.02
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.shadow_enabled = true
	add_child(sun)
	var key := OmniLight3D.new() # foco cálido sobre el pedestal
	key.position = Vector3(1.2, 3.0, 2.5)
	key.light_color = Color(1.0, 0.8, 0.55)
	key.light_energy = 2.0
	key.omni_range = 8.0
	add_child(key)
	# Suelo de piedra
	MeshUtil.box(self, Vector3(60, 0.2, 60), Vector3(0, -0.1, 0), Color(0.32, 0.28, 0.25))
	# Pedestal giratorio (dos discos con borde dorado)
	pedestal = Node3D.new()
	add_child(pedestal)
	_disc(pedestal, 1.3, 0.3, 0.15, Color(0.35, 0.33, 0.38))
	_disc(pedestal, 1.15, 0.08, 0.34, GOLD)
	# Fondo: murallas y torres del castillo (Kenney Castle Kit, CC0)
	for i in range(-4, 5):
		if i != 0:
			_prop("wall.glb", Vector3(i * 2.5, 0, -10.0), 0.0, 2.5)
	_prop("gate.glb", Vector3(0, 0, -10.0), 0.0, 2.5)
	for x: float in [-11.5, 11.5]:
		_prop("tower-hexagon-base.glb", Vector3(x, 0, -10.0), 0.0, 2.5)
		_prop("tower-hexagon-mid.glb", Vector3(x, 2.5, -10.0), 0.0, 2.5)
		_prop("tower-hexagon-top.glb", Vector3(x, 5.0, -10.0), 0.0, 2.5)
	_prop("rocks-small.glb", Vector3(-3.5, 0, -1.5), 0.6, 1.5)
	_prop("siege-ballista.glb", Vector3(5.5, 0, -3.0), -0.6, 1.2)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 1.9, 5.6), Vector3(0.9, 1.15, 0), Vector3.UP)
	cam.current = true

func _disc(parent: Node3D, r: float, h: float, y: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.5 if c == GOLD else 0.0
	m.roughness = 0.4
	mi.material_override = m
	mi.position.y = y
	parent.add_child(mi)

func _prop(file: String, pos: Vector3, rot: float, k: float) -> void:
	var n := (load(PROPS + file) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * k
	add_child(n)

func _rebuild_preview() -> void:
	if preview:
		preview.queue_free()
	preview = KnightVisual.new()
	preview.position.y = 0.38
	preview.scale = Vector3.ONE * 0.9
	preview.rotation.y = PI # el luchador mira a -Z; en el lobby, de cara a la cámara
	pedestal.add_child(preview)
	var w := Catalog.weapon(gs.weapon_id)
	preview.setup(Color(0.25, 0.45, 1.0), Catalog.character(gs.character_id), w)
	preview.set_mounted(false, 1.0)
	preview.set_loadout(1 if w.ranged else 0)

func _process(delta: float) -> void:
	pedestal.rotation.y += spin_speed * delta

func _unhandled_input(ev: InputEvent) -> void:
	# Arrastrar con el dedo o el ratón gira el pedestal
	if ev is InputEventScreenDrag:
		pedestal.rotation.y += (ev as InputEventScreenDrag).relative.x * 0.01
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		pedestal.rotation.y += (ev as InputEventMouseMotion).relative.x * 0.01
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				play()
			KEY_1: set_difficulty("facil")
			KEY_2: set_difficulty("normal")
			KEY_3: set_difficulty("dificil")
			KEY_Q: _cycle_tab(-1)
			KEY_E, KEY_TAB: _cycle_tab(1)

func _cycle_tab(d: int) -> void:
	set_tab(TABS[(TABS.find(tab) + d + TABS.size()) % TABS.size()])

# ---------------- Interfaz ----------------

func _style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _button(text: String, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _style(Color(0.1, 0.1, 0.16, 0.85), Color(0.5, 0.42, 0.25)))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.18, 0.25, 0.95), GOLD))
	b.add_theme_stylebox_override("pressed", _style(Color(0.45, 0.33, 0.12, 0.95), GOLD))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_ALL
	return b

func _label(text: String, size: int, c: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.add_child(root)
	# Barra superior
	var top := PanelContainer.new()
	top.position = Vector2(0, 0)
	top.size = Vector2(1280, 60)
	top.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.1, 0.8), Color(0, 0, 0, 0), 0))
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	top.add_child(hb)
	var avatar := _label("⚔", 30, GOLD)
	hb.add_child(avatar)
	var name_edit := LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.text = gs.player_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(240, 0)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text_changed.connect(func(t: String) -> void:
		gs.player_name = t.strip_edges() if t.strip_edges() != "" else "Jugador"
		gs.save_loadout())
	hb.add_child(name_edit)
	hb.add_child(_label("Nivel 1", 18, Color(0.75, 0.75, 0.85)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	hb.add_child(_label("ARENA DE EIKONS", 26, GOLD))
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer2)
	oro_label = _label("", 24, GOLD)
	oro_label.name = "Oro"
	hb.add_child(oro_label)
	# Pestañas (columna izquierda)
	var tabs := VBoxContainer.new()
	tabs.position = Vector2(20, 84)
	tabs.size = Vector2(210, 400)
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	for t: String in TABS:
		var b := _button(t, 24)
		b.name = "Tab_" + t
		b.custom_minimum_size = Vector2(210, 62)
		b.toggle_mode = true
		b.pressed.connect(set_tab.bind(t))
		tabs.add_child(b)
		tab_buttons[t] = b
	# Nombre y rol bajo el pedestal
	name_label = _label("", 34, Color.WHITE)
	name_label.position = Vector2(250, 560)
	name_label.size = Vector2(560, 44)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_label)
	role_label = _label("", 20, GOLD)
	role_label.position = Vector2(250, 604)
	role_label.size = Vector2(560, 30)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(role_label)
	# Panel derecho: lista + detalle + barras
	var panel := PanelContainer.new()
	panel.position = Vector2(850, 76)
	panel.size = Vector2(410, 452)
	panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.06, 0.1, 0.82), Color(0.5, 0.42, 0.25)))
	root.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 196)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.custom_minimum_size = Vector2(380, 70)
	detail.add_theme_font_size_override("normal_font_size", 16)
	detail.add_theme_font_size_override("bold_font_size", 17)
	pv.add_child(detail)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 2)
	pv.add_child(stats_box)
	# Dificultad
	var dh := HBoxContainer.new()
	dh.position = Vector2(850, 540)
	dh.add_theme_constant_override("separation", 8)
	root.add_child(dh)
	for d: String in Catalog.DIFFICULTY_NAMES:
		var b := _button(Catalog.DIFFICULTY_NAMES[d], 20)
		b.name = "Diff_" + d
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(131, 48)
		b.pressed.connect(set_difficulty.bind(d))
		dh.add_child(b)
		diff_buttons[d] = b
	# JUGAR
	play_button = _button("JUGAR", 46)
	play_button.name = "Jugar"
	play_button.position = Vector2(850, 600)
	play_button.size = Vector2(410, 100)
	play_button.add_theme_stylebox_override("normal", _style(Color(0.85, 0.55, 0.1), Color(1, 0.9, 0.5), 14))
	play_button.add_theme_stylebox_override("hover", _style(Color(0.95, 0.65, 0.15), Color.WHITE, 14))
	play_button.add_theme_stylebox_override("pressed", _style(Color(0.7, 0.4, 0.05), Color.WHITE, 14))
	play_button.add_theme_color_override("font_color", Color.WHITE)
	play_button.add_theme_color_override("font_outline_color", Color(0.3, 0.15, 0))
	play_button.add_theme_constant_override("outline_size", 6)
	play_button.pressed.connect(play)
	root.add_child(play_button)
	var hint := _label("Arrastra para girar · Q/E pestañas · 1-3 dificultad · Enter jugar", 14, Color(0.8, 0.8, 0.85))
	hint.position = Vector2(20, 690)
	root.add_child(hint)

func set_tab(t: String) -> void:
	tab = t
	_refresh_all(false)

func set_difficulty(d: String) -> void:
	gs.difficulty = d
	gs.save_loadout()
	_refresh_all(false)

func _refresh_all(rebuild: bool = true) -> void:
	if rebuild:
		_rebuild_preview()
	for t: String in tab_buttons:
		(tab_buttons[t] as Button).button_pressed = t == tab
	for d: String in diff_buttons:
		(diff_buttons[d] as Button).button_pressed = d == gs.difficulty
	oro_label.text = "Oro: %d" % gs.oro
	var c := Catalog.character(gs.character_id)
	name_label.text = c.display_name
	role_label.text = "%s · %s" % [c.role, Catalog.weapon(gs.weapon_id).display_name]
	for ch in list_box.get_children():
		ch.queue_free()
	for ch in stats_box.get_children():
		ch.queue_free()
	match tab:
		"Personajes":
			for cd in Catalog.characters():
				_card("%s  —  %s" % [cd.display_name, cd.role], cd.id == gs.character_id, func() -> void:
					gs.set_character(cd.id)
					gs.save_loadout()
					_refresh_all())
			detail.text = "[b]%s[/b]\n%s\n[color=#f2c75a]Pasiva · %s:[/color] %s" % [c.display_name, c.description, c.passive_name, c.passive_desc]
			_stat("Vida", c.vida, STAT_MAX["vida"], str(int(c.vida)))
			_stat("Estamina", c.estamina, STAT_MAX["estamina"], str(int(c.estamina)))
			_stat("Velocidad", c.velocidad, STAT_MAX["velocidad"], "x%.2f" % c.velocidad)
			_stat("Poise", c.poise, STAT_MAX["poise"], str(int(c.poise)))
			_stat("Daño", c.dano, STAT_MAX["dano"], "x%.2f" % c.dano)
		"Armas":
			for w in Catalog.weapons_for(c):
				_card(w.display_name, w.id == gs.weapon_id, func() -> void:
					gs.set_weapon(w.id)
					gs.save_loadout()
					_refresh_all())
			var cw := Catalog.weapon(gs.weapon_id)
			var shield_txt := "Sí" if cw.allows_shield else "No"
			detail.text = "[b]%s[/b]\n%s\nEscudo: %s · Combo: %d" % [cw.display_name, cw.description, shield_txt, cw.max_combo]
			if cw.ranged:
				_stat("Daño flecha", cw.arrow_damage, 15.0, str(cw.arrow_damage))
			else:
				_stat("Alcance", cw.reach_foot, 3.0, "%.1f m" % cw.reach_foot)
				_stat("Daño", cw.light_damage, 22.0, "%d / %d" % [cw.light_damage, cw.heavy_damage])
				_stat("Velocidad", 1.0 / cw.light_windup, 1.0 / 0.25, "%.2f s" % cw.light_windup)
				_stat("Coste aguante", cw.light_stamina, 22.0, "%d / %d" % [cw.light_stamina, cw.heavy_stamina])
			var others := Catalog.weapons().filter(func(w: WeaponDef) -> bool: return not c.allows(w.id))
			if not others.is_empty():
				detail.text += "\n[color=#999999]No compatibles con %s: %s[/color]" % [c.display_name, ", ".join(others.map(func(w: WeaponDef) -> String: return w.display_name))]
		"Eikons":
			for id: String in Catalog.EIKONS:
				var ed: EikonData = load(Catalog.EIKONS[id])
				_card(ed.eikon_name, id == gs.eikon_id, func() -> void:
					gs.eikon_id = id
					gs.save_loadout()
					_refresh_all(false))
			var e: EikonData = load(Catalog.EIKONS[gs.eikon_id])
			detail.text = "[b]%s[/b]\nInvocación (medidor lleno). %s. Dura %d s." % [e.eikon_name, "Vuela" if e.flying else "Terrestre", e.duration]
			_stat("Vida", e.max_health, 200.0, str(int(e.max_health)))
			_stat("Daño", e.attack_damage, 20.0, str(e.attack_damage))
			_stat("Alcance", e.attack_range, 12.0, "%.1f m" % e.attack_range)
		"Monturas":
			for id: String in Catalog.MOUNTS:
				var md: MountData = load(Catalog.MOUNTS[id])
				_card(md.mount_name, id == gs.mount_id, func() -> void:
					gs.mount_id = id
					gs.save_loadout()
					_refresh_all(false))
			var m: MountData = load(Catalog.MOUNTS[gs.mount_id])
			detail.text = "[b]%s[/b]\n%s" % [m.mount_name, "+%d de vida al jinete." % m.health_bonus if m.health_bonus > 0 else "Montura de guerra."]
			_stat("Velocidad", m.speed, 18.0, "%.0f" % m.speed)
			_stat("Aceleración", m.acceleration, 24.0, "%.0f" % m.acceleration)
			_stat("Giro", m.turn_speed, 4.0, "%.1f" % m.turn_speed)
			_stat("Dash", m.dash_speed, 40.0, "%.0f" % m.dash_speed)
		"Inventario":
			var e2: EikonData = load(Catalog.EIKONS[gs.eikon_id])
			var m2: MountData = load(Catalog.MOUNTS[gs.mount_id])
			for line: String in ["Personaje: " + c.display_name, "Arma: " + Catalog.weapon(gs.weapon_id).display_name,
					"Eikon: " + e2.eikon_name, "Montura: " + m2.mount_name, "Dificultad: " + Catalog.DIFFICULTY_NAMES[gs.difficulty]]:
				list_box.add_child(_label(line, 20))
			detail.text = "[b]Equipamiento actual[/b]\nSe guarda automáticamente en este dispositivo. El rival recibe un equipamiento aleatorio."
			var reset := _button("Restablecer", 18)
			reset.pressed.connect(func() -> void:
				gs.reset_defaults()
				gs.save_loadout()
				_refresh_all())
			stats_box.add_child(reset)

func _card(text: String, selected: bool, cb: Callable) -> void:
	var b := _button(("✔ " if selected else "") + text, 19)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(370, 46)
	if selected:
		b.add_theme_stylebox_override("normal", _style(Color(0.4, 0.3, 0.1, 0.95), GOLD))
	b.pressed.connect(cb)
	list_box.add_child(b)

func _stat(label: String, v: float, vmax: float, txt: String) -> void:
	var h := HBoxContainer.new()
	var l := _label(label, 15)
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = vmax
	bar.value = v
	bar.custom_minimum_size = Vector2(170, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.25)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	h.add_child(bar)
	h.add_child(_label("  " + txt, 15, Color(0.85, 0.85, 0.9)))
	stats_box.add_child(h)

## Empieza la partida 1v1 con el equipamiento elegido (rival aleatorio).
func play() -> void:
	gs.from_lobby = true
	gs.random_rival = true
	gs.save_loadout()
	get_tree().change_scene_to_file("res://scenes/arena.tscn")
