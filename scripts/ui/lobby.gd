extends Node3D
## Lobby (estilo "sala" de Free Fire, en clave DARK FANTASY). Personaje en un pedestal,
## pestañas de equipamiento con bloqueos y compras con oro, árbol de habilidades,
## dificultad y botón JUGAR. Todo el texto en español.

## Ronda 14: sin pestaña Monturas (los eikons son las monturas).
const TABS := ["Personaje", "Armas", "Eikons", "Habilidades", "Inventario"]
const STAT_MAX := {"vida": 160.0, "estamina": 140.0, "velocidad": 1.3, "poise": 110.0, "dano": 1.4}
const KIND_NAME := {"weapon": "arma", "eikon": "eikon"}

var gs: Node
var stage: ShowcaseStage
var pedestal: Node3D:
	get: return stage.pedestal
var preview: KnightVisual:
	get: return stage.preview
var spin_speed: float:
	get: return stage.spin_speed
	set(v): stage.spin_speed = v
var tab: String = "Personaje"
var ui: CanvasLayer
var root_ui: Control
var tab_buttons: Dictionary = {}
var diff_buttons: Dictionary = {}
var list_box: VBoxContainer
var list_scroll: ScrollContainer
var tree_view: SkillTreeView
var detail: RichTextLabel
var stats_box: VBoxContainer
var name_label: Label
var role_label: Label
var oro_label: Label
var level_label: Label
var level_badge: LevelBadge
var gem_label: Label
var dots: Dictionary = {} ## pestaña -> punto de notificación
var xp_bar: ProgressBar
var play_button: Button
var modal: Control
var modal_title: Label
var modal_text: Label
var modal_ok: Button
var _modal_cb: Callable
var toast: Label
var view_char: String = "" ## personaje que se está viendo (puede estar bloqueado)

func _ready() -> void:
	gs = get_node("/root/GameState")
	gs.from_lobby = false
	if not gs.first_run_done:
		# Primera vez: antes del lobby hay que elegir el rol
		get_tree().change_scene_to_file.call_deferred("res://scenes/first_run.tscn")
		return
	stage = ShowcaseStage.new()
	add_child(stage)
	_build_ui()
	view_char = gs.character_id
	_refresh_all()

func _unhandled_input(ev: InputEvent) -> void:
	if stage == null:
		return
	if ev is InputEventScreenDrag:
		stage.pedestal.rotation.y += (ev as InputEventScreenDrag).relative.x * 0.01
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		stage.pedestal.rotation.y += (ev as InputEventMouseMotion).relative.x * 0.01
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if modal.visible:
			match (ev as InputEventKey).keycode:
				KEY_ENTER, KEY_KP_ENTER: _modal_accept()
				KEY_ESCAPE: close_modal()
			return
		match (ev as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: play()
			KEY_1: set_difficulty("facil")
			KEY_2: set_difficulty("normal")
			KEY_3: set_difficulty("dificil")
			KEY_Q: _cycle_tab(-1)
			KEY_E, KEY_TAB: _cycle_tab(1)

func _cycle_tab(d: int) -> void:
	set_tab(TABS[(TABS.find(tab) + d + TABS.size()) % TABS.size()])

# ---------------- Interfaz ----------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	root_ui = Control.new()
	root_ui.theme = UIKit.theme()
	root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.size = Vector2(1280, 720)
	root_ui.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.add_child(root_ui)
	# Barra superior
	var top := PanelContainer.new()
	top.size = Vector2(1280, 62)
	var tsb := UIKit.box(Color(0.02, 0.05, 0.14, 0.7), Color(UIKit.ORANGE, 0.6), 0, 0, 10)
	tsb.border_width_bottom = 1
	top.add_theme_stylebox_override("panel", tsb)
	root_ui.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	top.add_child(hb)
	# Insignia de nivel (hexágono naranja con el número)
	level_badge = LevelBadge.new()
	level_badge.name = "LevelBadge"
	level_badge.custom_minimum_size = Vector2(46, 46)
	hb.add_child(level_badge)
	var name_edit := LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.text = gs.player_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(func(t: String) -> void:
		gs.player_name = t.strip_edges() if t.strip_edges() != "" else "Jugador"
		gs.save_loadout())
	hb.add_child(name_edit)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	level_label = UIKit.label("", 14, UIKit.MUTED)
	level_label.name = "AccountLevel"
	lv.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(170, 12)
	lv.add_child(xp_bar)
	hb.add_child(lv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(UIKit.title("ARENA DE EIKONS", 28, UIKit.YELLOW))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp2)
	oro_label = UIKit.title("", 22)
	oro_label.name = "Oro"
	hb.add_child(UIKit.currency_pill("oro", oro_label))
	gem_label = UIKit.title("", 22)
	gem_label.name = "Cristales" # moneda de muestra (solo se muestra)
	hb.add_child(UIKit.currency_pill("gema", gem_label))
	# Pestañas
	var tabs := VBoxContainer.new()
	tabs.position = Vector2(44, 84)
	tabs.add_theme_constant_override("separation", 8)
	root_ui.add_child(tabs)
	for t: String in TABS:
		var b := UIKit.button(t, 21)
		b.name = "Tab_" + t
		b.custom_minimum_size = Vector2(210, 58)
		b.toggle_mode = true
		b.pressed.connect(set_tab.bind(t))
		tabs.add_child(b)
		tab_buttons[t] = b
		var d := UIKit.notify_dot(b)
		d.visible = false
		dots[t] = d
	# Nombre bajo el pedestal
	name_label = UIKit.title("", 38)
	name_label.position = Vector2(250, 556)
	name_label.size = Vector2(580, 50)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(name_label)
	role_label = UIKit.label("", 19, UIKit.MUTED)
	role_label.position = Vector2(250, 606)
	role_label.size = Vector2(580, 30)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(role_label)
	# Panel derecho
	var panel := UIKit.panel()
	panel.position = Vector2(850, 76)
	panel.size = Vector2(410, 456)
	panel.custom_minimum_size = Vector2(410, 456)
	root_ui.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(380, 180)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	list_scroll.add_child(list_box)
	tree_view = SkillTreeView.new()
	tree_view.name = "SkillTree"
	tree_view.custom_minimum_size = Vector2(380, 230)
	tree_view.size = Vector2(380, 230)
	tree_view.node_pressed.connect(_on_skill_pressed)
	pv.add_child(tree_view)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.custom_minimum_size = Vector2(380, 60)
	pv.add_child(detail)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 2)
	pv.add_child(stats_box)
	# Dificultad
	var dh := HBoxContainer.new()
	dh.position = Vector2(850, 542)
	dh.add_theme_constant_override("separation", 8)
	root_ui.add_child(dh)
	for d: String in Catalog.DIFFICULTY_NAMES:
		var b := UIKit.button(Catalog.DIFFICULTY_NAMES[d], 19)
		b.name = "Diff_" + d
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(131, 46)
		b.pressed.connect(set_difficulty.bind(d))
		dh.add_child(b)
		diff_buttons[d] = b
	play_button = UIKit.big_button("JUGAR", 46)
	play_button.name = "Jugar"
	play_button.position = Vector2(850, 600)
	play_button.size = Vector2(410, 100)
	play_button.pressed.connect(play)
	root_ui.add_child(play_button)
	ui.move_child(UIKit.crystal_shards(ui, 18), 0)
	var hint := UIKit.label("Arrastra para girar · Q/E pestañas · 1-3 dificultad · Enter jugar", 14, UIKit.TEXT)
	hint.position = Vector2(20, 692)
	root_ui.add_child(hint)
	toast = UIKit.title("", 24, UIKit.YELLOW)
	toast.position = Vector2(250, 90)
	toast.size = Vector2(580, 40)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	root_ui.add_child(toast)
	_build_modal()

func _build_modal() -> void:
	modal = Control.new()
	modal.name = "Modal"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.size = Vector2(1280, 720)
	modal.visible = false
	root_ui.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.08, 0.65)
	dim.size = Vector2(1280, 720)
	modal.add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(390, 220)
	p.custom_minimum_size = Vector2(500, 260)
	p.size = Vector2(500, 260)
	modal.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	modal_title = UIKit.title("", 30)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(modal_title)
	modal_text = UIKit.label("", 19)
	modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_text.custom_minimum_size = Vector2(460, 0)
	v.add_child(modal_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	modal_ok = UIKit.big_button("Confirmar", 22)
	modal_ok.name = "ModalOk"
	modal_ok.custom_minimum_size = Vector2(180, 52)
	modal_ok.pressed.connect(_modal_accept)
	h.add_child(modal_ok)
	var no := UIKit.button("Cancelar", 20)
	no.name = "ModalCancel"
	no.custom_minimum_size = Vector2(160, 52)
	no.pressed.connect(close_modal)
	h.add_child(no)

func open_modal(title_t: String, text: String, ok_text: String, cb: Callable, can_ok: bool = true) -> void:
	modal_title.text = title_t
	modal_text.text = text
	modal_ok.text = ok_text
	modal_ok.disabled = not can_ok
	_modal_cb = cb
	modal.visible = true
	UIKit.pop_in(modal.get_child(1), 0.0, 0.5)

func close_modal() -> void:
	modal.visible = false
	if view_char != gs.character_id:
		view_char = gs.character_id
		_refresh_all()

func _modal_accept() -> void:
	if modal_ok.disabled:
		return
	modal.visible = false
	if _modal_cb.is_valid():
		_modal_cb.call()

func show_toast(t: String) -> void:
	toast.text = t
	UIKit.pop_in(toast, 0.0, 0.4)
	var tw := toast.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)

# ---------------- Compras ----------------

func _item_name(kind: String, id: String) -> String:
	match kind:
		"character": return Catalog.character(id).display_name
		"weapon": return Catalog.weapon(id).display_name
		"eikon": return (load(Catalog.EIKONS[id]) as EikonData).eikon_name
	return id

func _lock_text(kind: String, id: String) -> String:
	var r := Progression.req(kind, id)
	if gs.account_level() < int(r[0]):
		return "Nivel %d" % r[0]
	return "%d oro" % r[1] if int(r[1]) > 0 else "Gratis"

## Abre la confirmación de compra (o explica por qué no se puede).
func request_purchase(kind: String, id: String) -> void:
	var r := Progression.req(kind, id)
	var nm := _item_name(kind, id)
	var why: String = gs.can_buy(kind, id)
	match why:
		"ok":
			var price_t := "%d de oro" % r[1] if int(r[1]) > 0 else "gratis"
			open_modal("Desbloquear", "¿Desbloquear %s (%s) por %s?\nTe quedarán %d de oro." % [nm, KIND_NAME[kind], price_t, gs.oro - int(r[1])],
				"Comprar", confirm_purchase.bind(kind, id))
		"nivel":
			open_modal("Bloqueado", "%s requiere nivel de cuenta %d (tienes %d). Gana partidas para subir." % [nm, r[0], gs.account_level()], "Comprar", Callable(), false)
		"oro":
			open_modal("Oro insuficiente", "%s cuesta %d de oro y tienes %d. Gana partidas para conseguir más." % [nm, r[1], gs.oro], "Comprar", Callable(), false)

func confirm_purchase(kind: String, id: String) -> void:
	if gs.buy(kind, id) != "ok":
		return
	UIKit.sfx("confirm")
	show_toast("¡%s desbloqueado!" % _item_name(kind, id))
	match kind:
		"weapon": gs.set_weapon(id)
		"eikon": gs.eikon_id = id
	gs.save_loadout()
	_refresh_all()

func _on_skill_pressed(sid: String) -> void:
	var s := Progression.skill(sid)
	var have: bool = sid in gs.char_skills()
	if have:
		detail.text = "[b]%s[/b] (aprendida)\n%s" % [s["name"], s["desc"]]
		return
	var req_ok: bool = s["req"] == "" or s["req"] in gs.char_skills()
	var pts: int = gs.skill_points()
	var txt := "%s\nCoste: %d punto(s). Tienes %d." % [s["desc"], s["cost"], pts]
	if not req_ok:
		txt += "\nRequiere antes: %s." % Progression.skill(s["req"])["name"]
	open_modal(s["name"], txt, "Aprender", learn_skill.bind(sid), req_ok and pts >= int(s["cost"]))

func learn_skill(sid: String) -> void:
	if gs.learn_skill(sid) == "ok":
		UIKit.sfx("levelup")
		show_toast("Habilidad aprendida: " + Progression.skill(sid)["name"])
		_refresh_all(false)

# ---------------- Contenido ----------------

func set_tab(t: String) -> void:
	tab = t
	_refresh_all(false)

func set_difficulty(d: String) -> void:
	gs.difficulty = d
	gs.save_loadout()
	_refresh_all(false)

func _refresh_all(rebuild: bool = true) -> void:
	var c := Catalog.character(view_char)
	var locked: bool = not gs.is_unlocked("character", view_char)
	if rebuild:
		var w := Catalog.weapon(gs.weapon_id) if not locked else Catalog.weapon(c.default_weapon)
		stage.show_character(c, w, locked)
	stage.show_eikon(load(Catalog.EIKONS[gs.eikon_id]) if tab == "Eikons" else null)
	for t: String in tab_buttons:
		(tab_buttons[t] as Button).button_pressed = t == tab
	for d: String in diff_buttons:
		(diff_buttons[d] as Button).button_pressed = d == gs.difficulty
		UIKit.button_styles(diff_buttons[d], UIKit.ORANGE if d == gs.difficulty else UIKit.BLUE)
	oro_label.text = str(gs.oro)
	gem_label.text = str(gs.gemas)
	level_badge.level = gs.account_level()
	level_badge.queue_redraw()
	_update_dots()
	for t: String in tab_buttons:
		var tbn := tab_buttons[t] as Button
		UIKit.button_styles(tbn, UIKit.ORANGE if t == tab else UIKit.BLUE)
	var lp := Progression.level_progress(gs.account_xp)
	level_label.text = "%d/%d XP" % [lp.x, lp.y]
	xp_bar.max_value = lp.y
	xp_bar.value = lp.x
	var cur := Catalog.character(gs.character_id)
	name_label.text = c.display_name
	role_label.text = ("%s · Nivel %d · %s" % [c.role, gs.char_level(c.id), Catalog.weapon(gs.weapon_id).display_name]) if not locked else "%s · Bloqueado (%s)" % [c.role, _lock_text("character", c.id)]
	for ch in list_box.get_children():
		ch.queue_free()
	for ch in stats_box.get_children():
		ch.queue_free()
	list_scroll.visible = tab != "Habilidades"
	tree_view.visible = tab == "Habilidades"
	match tab:
		"Personaje":
			# Ronda 15: vista de TU personaje (fijo desde la primera partida): stats, árbol y pasiva.
			_card("%s — %s · Nv %d" % [c.display_name, c.role, gs.char_level()], true, false, func() -> void: pass)
			var item: Dictionary = Progression.CHARACTER_CHANGE_ITEM
			var cc := _card("%s — Próximamente" % item["name"], false, true, func() -> void:
				open_modal(item["name"], "Pronto podrás cambiar de personaje con este objeto de la tienda. Por ahora tu personaje es fijo y conserva su nivel y habilidades.", "Comprar", Callable(), false), false)
			cc.name = "CambioPersonaje"
			cc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
			_card("Pasiva · %s" % c.passive_name, false, false, func() -> void:
				detail.text = "[b]Pasiva · %s[/b]\n%s" % [c.passive_name, c.passive_desc])
			for sk: Dictionary in Progression.tree(c.id):
				var have: bool = sk["id"] in gs.char_skills()
				var sid: String = sk["id"]
				_card("%s %s" % ["✔" if have else "·", sk["name"]], false, false, func() -> void:
					set_tab("Habilidades")
					_on_skill_pressed(sid))
			detail.text = "[b]%s[/b]\n%s\n[color=#f2dc99]Pasiva · %s:[/color] %s" % [c.display_name, c.description, c.passive_name, c.passive_desc]
			var m := Progression.combine_mods(gs.char_skills(c.id))
			_stat("Vida", c.vida + m["vida"], STAT_MAX["vida"], str(int(c.vida + m["vida"])))
			_stat("Estamina", c.estamina + m["estamina"], STAT_MAX["estamina"], str(int(c.estamina + m["estamina"])))
			_stat("Velocidad", c.velocidad * m["velocidad"], STAT_MAX["velocidad"], "x%.2f" % (c.velocidad * m["velocidad"]))
			_stat("Poise", c.poise + m["poise"], STAT_MAX["poise"], str(int(c.poise + m["poise"])))
			_stat("Daño", c.dano * m["dano"], STAT_MAX["dano"], "x%.2f" % (c.dano * m["dano"]))
		"Armas":
			for w in Catalog.weapons_for(cur):
				var own: bool = gs.is_unlocked("weapon", w.id)
				_card(w.display_name if own else "%s — %s" % [w.display_name, _lock_text("weapon", w.id)], w.id == gs.weapon_id, not own, func() -> void:
					if own:
						gs.set_weapon(w.id)
						gs.save_loadout()
						_refresh_all()
					else:
						request_purchase("weapon", w.id))
			var cw := Catalog.weapon(gs.weapon_id)
			detail.text = "[b]%s[/b]\n%s\nEscudo: %s · Combo: %d" % [cw.display_name, cw.description, "Sí" if cw.allows_shield else "No", cw.max_combo]
			if cw.ranged:
				_stat("Daño flecha", cw.arrow_damage, 15.0, str(cw.arrow_damage))
			else:
				_stat("Alcance", cw.reach_foot, 3.0, "%.1f m" % cw.reach_foot)
				_stat("Daño", cw.light_damage, 22.0, "%d / %d" % [cw.light_damage, cw.heavy_damage])
				_stat("Velocidad", 1.0 / cw.light_windup, 1.0 / 0.25, "%.2f s" % cw.light_windup)
				_stat("Coste aguante", cw.light_stamina, 22.0, "%d / %d" % [cw.light_stamina, cw.heavy_stamina])
		"Eikons":
			for id: String in Catalog.EIKONS:
				var ed: EikonData = load(Catalog.EIKONS[id])
				var own: bool = gs.is_unlocked("eikon", id)
				var kind_t := "montable" if ed.rideable else "compañero"
				_card(("%s · %s" % [ed.eikon_name, kind_t]) if own else "%s — %s" % [ed.eikon_name, _lock_text("eikon", id)], id == gs.eikon_id, not own, func() -> void:
					if own:
						gs.eikon_id = id
						gs.save_loadout()
						_refresh_all(false)
					else:
						request_purchase("eikon", id))
			var e: EikonData = load(Catalog.EIKONS[gs.eikon_id])
			if e.rideable:
				detail.text = "[b]%s[/b] · [color=#a8ccff]Montable[/color]\n%s\nCon el medidor lleno (E) aparece ensillado y lo montas %d s. Especial (E montado): [color=#f2dc99]%s[/color]." % [e.eikon_name, e.description, e.duration, e.special_name]
				_stat("Velocidad", e.ride.speed, 18.0, "%.1f" % e.ride.speed)
				_stat("Giro", e.ride.turn_speed, 4.5, "%.1f" % e.ride.turn_speed)
				_stat("Dash", e.ride.dash_speed, 40.0, "%.0f" % e.ride.dash_speed)
				_stat("Especial", e.special_damage, 20.0, "%d · %.1f s" % [e.special_damage, e.special_cooldown])
			else:
				detail.text = "[b]%s[/b] · [color=#a8ccff]Compañero[/color]\n%s" % [e.eikon_name, e.description]
				_stat("Vida", e.max_health, 200.0, str(int(e.max_health)))
				_stat("Daño", e.attack_damage, 20.0, str(e.attack_damage))
				_stat("Alcance", e.attack_range, 12.0, "%.1f m" % e.attack_range)
		"Habilidades":
			tree_view.build(gs.character_id, gs.char_skills(), gs.skill_points())
			var cl := Progression.level_progress(int(gs.char_xp.get(gs.character_id, 0)))
			detail.text = "[b]Árbol de %s[/b] · Nivel %d\nPuntos disponibles: [color=#f2dc99]%d[/color] (1 por nivel del personaje). Toca un nodo para aprenderlo." % [cur.display_name, gs.char_level(), gs.skill_points()]
			_stat("XP personaje", cl.x, cl.y, "%d/%d" % [cl.x, cl.y])
		"Inventario":
			var e2: EikonData = load(Catalog.EIKONS[gs.eikon_id])
			for ln: String in ["Personaje: %s (Nv %d)" % [cur.display_name, gs.char_level()], "Arma: " + Catalog.weapon(gs.weapon_id).display_name,
					"Eikon: %s (%s)" % [e2.eikon_name, "montable" if e2.rideable else "compañero"], "Dificultad: " + Catalog.DIFFICULTY_NAMES[gs.difficulty],
					"Armas: %d · Eikons: %d" % [gs.owned_weapons.size(), gs.owned_eikons.size()], "Tienda: Cambio de personaje (Próximamente)"]:
				list_box.add_child(UIKit.label(ln, 19))
			detail.text = "[b]Equipamiento actual[/b]\nSe guarda automáticamente en este dispositivo. El rival recibe un equipamiento aleatorio."

func _card(text: String, selected: bool, locked: bool, cb: Callable, coin: bool = true) -> Button:
	var b := UIKit.button(text, 18, UIKit.ORANGE if selected else (Color(0.3, 0.36, 0.48) if locked else UIKit.BLUE))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(370, 44)
	if locked and coin:
		var ic := CurrencyIcon.new() # candado-moneda: se compra con oro
		ic.kind = "oro"
		ic.size = Vector2(24, 24)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		b.resized.connect(func() -> void: ic.position = Vector2(b.size.x - 34, (b.size.y - 24) * 0.5))
	b.pressed.connect(cb)
	list_box.add_child(b)
	UIKit.pop_in(b, 0.03 * list_box.get_child_count(), 0.85)
	return b

## Puntos rojos: hay habilidades por aprender o algo que ya se puede comprar.
func _update_dots() -> void:
	dots["Habilidades"].visible = gs.skill_points() > 0
	dots["Personaje"].visible = false
	var can_w := false
	for w in Catalog.weapons_for(Catalog.character(gs.character_id)):
		can_w = can_w or gs.can_buy("weapon", w.id) == "ok"
	dots["Armas"].visible = can_w
	var can_e := false
	for id: String in Catalog.EIKONS:
		can_e = can_e or gs.can_buy("eikon", id) == "ok"
	dots["Eikons"].visible = can_e

func _stat(label_t: String, v: float, vmax: float, txt: String) -> void:
	stats_box.add_child(UIKit.stat_row(label_t, v, vmax, txt))

## Empieza la partida 1v1 con el equipamiento elegido (rival aleatorio).
func play() -> void:
	if modal.visible:
		return
	gs.from_lobby = true
	gs.random_rival = true
	gs.save_loadout()
	UIKit.sfx("confirm")
	UIKit.go("res://scenes/arena.tscn")
