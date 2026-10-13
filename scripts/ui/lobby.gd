extends Node3D
## Lobby (estilo "sala" de Free Fire, en clave DARK FANTASY). Personaje en un pedestal,
## pestañas de equipamiento con bloqueos y compras con oro, árbol de habilidades,
## dificultad y botón JUGAR. Todo el texto en español.

## Ronda 14: sin pestaña Monturas (los eikons son las monturas).
## Ronda 19: pestaña Tienda (las compras se hacen aquí; las demás solo equipan lo que tienes).
## Ronda 20: pestañas Herrero y Ajustes; cada panel tiene «✕» (y Esc / Atrás) para cerrarlo.
const TABS := ["Personaje", "Armas", "Eikons", "Habilidades", "Herrero", "Tienda", "Inventario", "Ajustes"]
const SHOP_CATS := ["Armas", "Armaduras", "Eikons", "Materiales", "Artes"]
const BUS_NAMES := {"Master": "General", "Música": "Música", "Efectos": "Efectos", "UI": "Interfaz"}
const STAT_MAX := {"vida": 160.0, "estamina": 140.0, "velocidad": 1.3, "poise": 110.0, "dano": 1.4}
const KIND_NAME := {"weapon": "arma", "eikon": "eikon", "armor": "armadura"}

var gs: Node
var stage: ShowcaseStage
var pedestal: Node3D:
	get: return stage.pedestal
var preview: KnightVisual:
	get: return stage.preview
var spin_speed: float:
	get: return stage.spin_speed
	set(v): stage.spin_speed = v
var tab: String = "" ## ronda 19: ninguna pestaña al entrar (solo el escaparate)
var shop_cat: String = "Armas"
var right_panel: Control
var sheet: CharSheet
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
var close_button: Button
var smith_sel: String = "" ## arma elegida en el Herrero

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
	smith_sel = gs.weapon_id
	_refresh_all()
	var au := get_node_or_null("/root/Audio")
	if au:
		au.music("lobby") # ronda 20

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
		if (ev as InputEventKey).keycode == KEY_ESCAPE:
			close_top()
			get_viewport().set_input_as_handled()
			return
		if attr_screen.visible or sheet.picker.visible:
			return
		match (ev as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: play()
			KEY_1: set_difficulty("facil")
			KEY_2: set_difficulty("normal")
			KEY_3: set_difficulty("dificil")
			KEY_Q: _cycle_tab(-1)
			KEY_E, KEY_TAB: _cycle_tab(1)

## Ronda 20: Esc / Atrás cierra lo que esté encima: confirmación, Atributos, selector de equipo
## o la pestaña abierta (vuelve al escaparate sin pestaña). Devuelve lo que cerró.
func close_top() -> String:
	if modal.visible:
		close_modal()
		return "modal"
	if attr_screen.visible:
		attr_screen.close()
		return "Atributos"
	if sheet.picker.visible:
		sheet.picker.visible = false
		return "picker"
	if tab != "":
		var t := tab
		set_tab("")
		return t
	return ""

func _process(_d: float) -> void:
	if close_button:
		close_button.visible = tab != "" and not sheet.picker.visible

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and stage != null:
		close_top() # botón Atrás de Android

func _cycle_tab(d: int) -> void:
	var i := TABS.find(tab)
	if i < 0:
		i = -1 if d > 0 else 0
	set_tab(TABS[(i + d + TABS.size()) % TABS.size()])

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
		b.custom_minimum_size = Vector2(210, 54)
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
	right_panel = panel
	panel.name = "RightPanel"
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
	sheet = CharSheet.new()
	sheet.visible = false
	root_ui.add_child(sheet)
	sheet.build(gs)
	sheet.attributes_requested.connect(open_attributes)
	sheet.changed.connect(func() -> void: _refresh_all())
	close_button = UIKit.close_x(root_ui, Vector2(850 + 410 - 50, 82), "CloseX", func() -> void: set_tab(""))
	_build_modal()
	attr_screen = AttrScreen.new()
	attr_screen.visible = false
	root_ui.add_child(attr_screen)
	attr_screen.closed.connect(func(_c: bool) -> void: _refresh_all(false))

var attr_screen: AttrScreen

func open_attributes() -> void:
	attr_screen.open(gs)

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
		"armor": return Catalog.armor(id).display_name
		"set":
			for st: Dictionary in Catalog.armor_sets_for_sale():
				if st["set_id"] == id: return "Conjunto " + String(st["set_name"])
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

## Conjunto de armadura completo (las piezas que te falten).
func request_set_purchase(set_id: String) -> void:
	var st: Dictionary = {}
	for x: Dictionary in Catalog.armor_sets_for_sale():
		if x["set_id"] == set_id: st = x
	var price: int = gs.set_price(set_id)
	var nm := _item_name("set", set_id)
	if price <= 0:
		show_toast("Ya tienes " + nm)
	elif gs.account_level() < int(st["level"]):
		open_modal("Bloqueado", "%s requiere nivel de cuenta %d (tienes %d)." % [nm, st["level"], gs.account_level()], "Comprar", Callable(), false)
	elif gs.oro < price:
		open_modal("Oro insuficiente", "%s cuesta %d de oro y tienes %d." % [nm, price, gs.oro], "Comprar", Callable(), false)
	else:
		open_modal("Comprar", "¿Comprar %s (4 piezas) por %d de oro?\nTe quedarán %d de oro. Equípalo desde la ficha de Personaje." % [nm, price, gs.oro - price], "Comprar", confirm_set_purchase.bind(set_id))

func confirm_set_purchase(set_id: String) -> void:
	if gs.buy_set(set_id) == "ok":
		UIKit.sfx("confirm")
		UIKit.audio("purchase")
		show_toast("¡%s comprado!" % _item_name("set", set_id))
		_refresh_all(false)

func confirm_purchase(kind: String, id: String) -> void:
	if gs.buy(kind, id) != "ok":
		return
	UIKit.sfx("confirm")
	UIKit.audio("purchase")
	show_toast("¡%s desbloqueado!" % _item_name(kind, id))
	gs.save_loadout() # ronda 19: comprar no equipa (se equipa desde Personaje/Armas/Eikons)
	_refresh_all(false)

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
	if attr_screen: attr_screen.visible = false
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
	list_scroll.custom_minimum_size.y = 96.0 if tab == "Herrero" else 180.0
	tree_view.visible = tab == "Habilidades"
	right_panel.visible = tab != "" and tab != "Personaje"
	sheet.visible = tab == "Personaje"
	close_button.visible = tab != ""
	close_button.position = Vector2(262 + 1000 - 50, 82) if tab == "Personaje" else Vector2(850 + 410 - 50, 82)

	name_label.visible = tab != "Personaje"
	role_label.visible = tab != "Personaje"
	match tab:
		"Personaje":
			# Ronda 19: ficha completa (atributos, estadísticas y equipo)
			sheet.refresh()
		"Armas":
			for w in Catalog.weapons_for(cur):
				var own: bool = gs.is_unlocked("weapon", w.id)
				if not own:
					continue # ronda 19: se compran en la Tienda
				var wt: String = "%s  [%s]" % [w.display_name, Attributes.scaling_text(w)]
				if own and not Attributes.unmet(w, gs.char_attrs()).is_empty():
					wt += "  ⚠"
				_card(wt if own else "%s — %s" % [wt, _lock_text("weapon", w.id)], w.id == gs.weapon_id, not own, func() -> void:
					if own:
						gs.set_weapon(w.id)
						gs.save_loadout()
						_refresh_all()
					else:
						request_purchase("weapon", w.id))
			list_box.add_child(UIKit.label("Más armas en la Tienda.", 15, UIKit.MUTED))
			# Ronda 21: arte de arma intercambiable (colección)
			if WeaponArts.compatible(Catalog.weapon(gs.weapon_id)):
				var ab := UIKit.button("Arte: %s  ↻" % WeaponArts.name_of(gs.weapon_art()), 17, UIKit.BLUE)
				ab.name = "ArtBtn"
				ab.custom_minimum_size = Vector2(370, 42)
				ab.pressed.connect(func() -> void:
					gs.cycle_weapon_art()
					gs.save_loadout()
					_refresh_all(false))
				list_box.add_child(ab)
			var cw: WeaponDef = gs.eff_weapon(gs.weapon_id)
			detail.text = "[b]%s[/b]\n%s\nEscudo: %s · Combo: %d" % [cw.display_name, cw.description, "Sí" if cw.allows_shield else "No", cw.max_combo]
			# Ronda 18: escalado (S-E) y requisitos
			var at: Dictionary = gs.char_attrs()
			detail.text += "\n[color=#f2dc99]Escalado:[/color] %s\n[color=#f2dc99]Requisitos:[/color] %s" % [Attributes.scaling_text(cw), Attributes.req_text(cw)]
			var un := Attributes.unmet(cw, at)
			if not un.is_empty():
				detail.text += "\n[color=#ff8a7a]⚠ No cumples los requisitos: −30 %% de daño.[/color]"
			_stat("Bono atributos", Attributes.weapon_mult(cw, gs.character_id, at), 1.6, "x%.2f" % Attributes.weapon_mult(cw, gs.character_id, at))
			if cw.ranged:
				_stat("Daño flecha", cw.arrow_damage, 15.0, str(cw.arrow_damage))
			else:
				_stat("Alcance", cw.reach_foot, 3.0, "%.1f m" % cw.reach_foot)
				_stat("Daño", cw.light_damage, 22.0, "%d / %d" % [cw.light_damage, cw.heavy_damage])
				_stat("Velocidad", 1.0 / cw.light_windup, 1.0 / 0.25, "%.2f s" % cw.light_windup)
				_stat("Coste aguante", cw.light_stamina, 22.0, "%d / %d" % [cw.light_stamina, cw.heavy_stamina])
				var art := WeaponArts.art(gs.weapon_art())
				if not art.is_empty():
					detail.text += "\n[color=#f2dc99]Arte:[/color] %s — %s (%d Energía)%s" % [art["name"], art["desc"], int(art["cost"]), "" if cur.special_id == "" else " · tu Habilidad propia tiene prioridad"]
		"Eikons":
			for id: String in Catalog.EIKONS:
				var ed: EikonData = load(Catalog.EIKONS[id])
				var own: bool = gs.is_unlocked("eikon", id)
				if not own:
					continue
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
			_build_spell_slots()
		"Habilidades":
			tree_view.build(gs.character_id, gs.char_skills(), gs.skill_points())
			var cl := Progression.level_progress(int(gs.char_xp.get(gs.character_id, 0)))
			detail.text = "[b]Árbol de %s[/b] · Nivel %d\nPuntos disponibles: [color=#f2dc99]%d[/color] (1 por nivel del personaje). Toca un nodo para aprenderlo." % [cur.display_name, gs.char_level(), gs.skill_points()]
			_stat("XP personaje", cl.x, cl.y, "%d/%d" % [cl.x, cl.y])
		"Herrero":
			_build_smith(cur)
		"Ajustes":
			_build_settings()
		"Tienda":
			_build_shop(cur)
		"Inventario":
			var e2: EikonData = load(Catalog.EIKONS[gs.eikon_id])
			for ln: String in ["Personaje: %s (Nv %d)" % [cur.display_name, gs.char_level()], "Arma: " + gs.eff_weapon(gs.weapon_id).display_name,
					"Eikon: %s (%s)" % [e2.eikon_name, "montable" if e2.rideable else "compañero"], "Dificultad: " + Catalog.DIFFICULTY_NAMES[gs.difficulty],
					"Armas: %d · Eikons: %d · Piezas de armadura: %d" % [gs.owned_weapons.size(), gs.owned_eikons.size(), gs.owned_armor.size()],
					"Piedras: " + " · ".join(Smithing.STONES.map(func(sid: String) -> String: return "%s ×%d" % [Smithing.STONE_NAMES[sid].replace("Piedra de forja", "P."), gs.material(sid)]))]:
				list_box.add_child(UIKit.label(ln, 19))
			detail.text = "[b]Equipamiento actual[/b]\nSe guarda automáticamente en este dispositivo. El rival recibe un equipamiento aleatorio."

## Ronda 21: ranuras de hechizos de eikon (toca una ranura para cambiar de hechizo).
func _build_spell_slots() -> void:
	var sl: Array = gs.equipped_spells()
	list_box.add_child(UIKit.label("Hechizos de eikon · %d ranuras (Sabiduría/Devoción)" % sl.size(), 16, Color(0.95, 0.86, 0.6)))
	for i in sl.size():
		var b := UIKit.button("Ranura %d: %s  ↻" % [i + 1, EikonSpells.name_of(String(sl[i]))], 17, UIKit.BLUE)
		b.name = "Spell_%d" % i
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(370, 40)
		b.pressed.connect(func() -> void:
			gs.cycle_spell(i)
			gs.save_loadout()
			_refresh_all(false))
		list_box.add_child(b)
	var ad: Dictionary = Attributes.derived(gs.character_id, gs.char_attrs())
	var lines: Array = []
	for id in sl:
		if String(id) != "":
			var d := EikonSpells.spell(id)
			lines.append("%s: %s (%d Energía, x%.2f)" % [d["name"], d["desc"], int(d["cost"]), EikonSpells.power(id, ad)])
	detail.text += "\n[color=#f2dc99]Hechizos[/color] (a pie: X lanza, T cambia):\n" + ("\n".join(lines) if not lines.is_empty() else "Ninguno equipado.")

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

func _build_shop(cur: CharacterDef) -> void:
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 6)
	list_box.add_child(cats)
	for ct: String in SHOP_CATS:
		var b := UIKit.button(ct, 12, UIKit.ORANGE if ct == shop_cat else UIKit.BLUE)
		b.name = "Cat_" + ct
		b.custom_minimum_size = Vector2(64, 40)
		b.pressed.connect(func() -> void:
			shop_cat = ct
			_refresh_all(false))
		cats.add_child(b)
	match shop_cat:
		"Armas":
			for w in Catalog.weapons_for(cur):
				var own: bool = gs.is_unlocked("weapon", w.id)
				var b := _card("%s  [%s]%s" % [w.display_name, Attributes.scaling_text(w), "  ✔" if own else " — " + _lock_text("weapon", w.id)], false, not own, request_purchase.bind("weapon", w.id))
				b.name = "Buy_weapon_" + w.id
				b.disabled = own
			detail.text = "[b]Tienda · Armas[/b]\nArmas de tu personaje. Nivel de cuenta y oro. Equípalas en Armas o en la ficha."
		"Armaduras":
			for st: Dictionary in Catalog.armor_sets_for_sale():
				var price: int = gs.set_price(st["set_id"])
				var lvl_ok: bool = gs.account_level() >= int(st["level"])
				var t: String = "%s (%s)" % [st["set_name"], {"ligero": "ligera", "medio": "media", "pesado": "pesada"}.get(st["class"], "")]
				t += "  ✔" if price == 0 else (" — %d oro" % price if lvl_ok else " — Nivel %d" % st["level"])
				var b := _card(t, false, price > 0, request_set_purchase.bind(st["set_id"]))
				b.name = "Buy_set_" + String(st["set_id"])
				b.disabled = price == 0
			detail.text = "[b]Tienda · Armaduras[/b]\nConjuntos de 4 piezas (casco, pecho, guantes, piernas): peso, absorción, equilibrio y resistencias."
		"Eikons":
			for id: String in Catalog.EIKONS:
				var ed: EikonData = load(Catalog.EIKONS[id])
				var own: bool = gs.is_unlocked("eikon", id)
				var b := _card("%s%s" % [ed.eikon_name, "  ✔" if own else " — " + _lock_text("eikon", id)], false, not own, request_purchase.bind("eikon", id))
				b.name = "Buy_eikon_" + id
				b.disabled = own
			detail.text = "[b]Tienda · Eikons[/b]\nMontables y compañeros."
		"Materiales":
			for sid: String in Smithing.STONES:
				var lv_ok: bool = gs.account_level() >= int(Smithing.STONE_SHOP_LEVEL[sid])
				var t: String = "%s (tienes %d) — %s" % [Smithing.STONE_NAMES[sid], gs.material(sid), ("%d oro" % Smithing.STONE_PRICES[sid]) if lv_ok else "Nivel %d" % Smithing.STONE_SHOP_LEVEL[sid]]
				var b := _card(t, false, true, buy_stone.bind(sid))
				b.name = "Buy_stone_" + sid
			detail.text = "[b]Tienda · Materiales[/b]\nPiedras de forja para mejorar armas en el Herrero. También se ganan en cada partida (más si ganas)."
		"Artes":
			for aid: String in WeaponArts.ORDER:
				var a := WeaponArts.art(aid)
				var own: bool = aid in gs.owned_arts
				var b := _card("%s%s" % [a["name"], "  ✔" if own else " — %d oro" % int(a["price"])], false, not own, func() -> void:
					if gs.buy_art(aid):
						UIKit.audio("purchase")
					_refresh_all(false))
				b.name = "Buy_art_" + aid
				b.disabled = own
			detail.text = "[b]Tienda · Artes de arma[/b]\nTu colección: cambia el arte de cada arma cuerpo a cuerpo en la pestaña Armas."

## Puntos rojos: hay habilidades por aprender o algo que ya se puede comprar.
func _update_dots() -> void:
	dots["Habilidades"].visible = gs.skill_points() > 0
	dots["Personaje"].visible = gs.attr_points() > 0
	var can_w := false
	for w in Catalog.weapons_for(Catalog.character(gs.character_id)):
		can_w = can_w or gs.can_buy("weapon", w.id) == "ok"
	dots["Armas"].visible = false
	var can_e := false
	for id: String in Catalog.EIKONS:
		can_e = can_e or gs.can_buy("eikon", id) == "ok"
	dots["Eikons"].visible = false
	dots["Tienda"].visible = can_w or can_e

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

func buy_stone(sid: String) -> void:
	match gs.buy_stone(sid):
		"ok":
			UIKit.audio("purchase")
			show_toast("+1 " + Smithing.STONE_NAMES[sid])
		"nivel":
			show_toast("Requiere nivel de cuenta %d" % Smithing.STONE_SHOP_LEVEL[sid])
		"oro":
			show_toast("Oro insuficiente")
	_refresh_all(false)

# ---------------- Herrero (ronda 20) ----------------

func _ar_of(w: WeaponDef) -> float:
	return float(EquipStats.attack_rating(Catalog.character(gs.character_id), w, gs.char_attrs())["total"])

func _status_text(w: WeaponDef) -> String:
	var parts: Array = []
	for k: String in w.status:
		parts.append("%s %d" % [StatusFx.NAMES[k], roundi(float(w.status[k]))])
	return " · ".join(parts) if not parts.is_empty() else "—"

func _build_smith(cur: CharacterDef) -> void:
	if not smith_sel in gs.owned_weapons or not cur.allows(smith_sel):
		smith_sel = gs.weapon_id
	for w in Catalog.weapons_for(cur):
		if not gs.is_unlocked("weapon", w.id):
			continue
		var ew: WeaponDef = gs.eff_weapon(w.id)
		var b := _card(ew.display_name, w.id == smith_sel, false, func() -> void:
			smith_sel = w.id
			_refresh_all(false), false)
		b.name = "Smith_" + w.id
	var base: WeaponDef = Catalog.weapon(smith_sel)
	var lv: int = gs.weapon_level(smith_sel)
	var inf: String = gs.weapon_infusion(smith_sel)
	var now := Smithing.effective(base, lv, inf)
	var nxt := Smithing.effective(base, mini(lv + 1, Smithing.MAX_LEVEL), inf)
	var ar0 := _ar_of(now)
	var ar1 := _ar_of(nxt)
	var t := "[b]%s[/b] · Infusión: %s\n" % [now.display_name, Smithing.INFUSIONS[inf]["name"]]
	if lv >= Smithing.MAX_LEVEL:
		t += "Ataque [color=#f2dc99]%d[/color] · Mejora máxima (+%d)\n" % [roundi(ar0), lv]
	else:
		var c := Smithing.cost(lv + 1)
		t += "Ataque [color=#f2dc99]%d[/color] → [color=#7dff8a]%d[/color] (+%d → +%d)\n" % [roundi(ar0), roundi(ar1), lv, lv + 1]
		t += "Escalado %s → %s\n" % [Attributes.scaling_text(now), Attributes.scaling_text(nxt)]
		t += "Coste: %d oro + %d× %s (tienes %d)\n" % [c["oro"], c["n"], Smithing.STONE_NAMES[c["piedra"]], gs.material(c["piedra"])]
	t += "Estado: %s" % _status_text(now)
	detail.text = t
	var up := UIKit.big_button("Mejorar" if lv < Smithing.MAX_LEVEL else "Máximo", 20)
	up.name = "SmithUpgrade"
	up.custom_minimum_size = Vector2(380, 46)
	up.disabled = gs.can_upgrade(smith_sel) != "ok"
	up.pressed.connect(upgrade_selected)
	stats_box.add_child(up)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	stats_box.add_child(g)
	for k: String in Smithing.INFUSION_ORDER:
		var ib := UIKit.button(Smithing.INFUSIONS[k]["name"], 15, UIKit.ORANGE if k == inf else UIKit.BLUE)
		ib.name = "Inf_" + (k if k != "" else "normal")
		ib.custom_minimum_size = Vector2(124, 36)
		ib.tooltip_text = "Infusión %s (%s)" % [Smithing.INFUSIONS[k]["name"], "gratis" if k == "" else "%d oro" % Smithing.INFUSE_GOLD]
		ib.pressed.connect(infuse_selected.bind(k))
		g.add_child(ib)

func upgrade_selected() -> String:
	var r: String = gs.upgrade_weapon(smith_sel)
	match r:
		"ok":
			UIKit.audio("smith")
			show_toast("¡%s!" % gs.eff_weapon(smith_sel).display_name)
		"oro": show_toast("Oro insuficiente")
		"piedra": show_toast("Faltan piedras de forja (Tienda · Materiales)")
		"max": show_toast("Mejora máxima")
	_refresh_all(false)
	return r

func infuse_selected(k: String) -> String:
	var r: String = gs.infuse(smith_sel, k)
	match r:
		"ok":
			UIKit.audio("smith")
			show_toast("Infusión: " + Smithing.INFUSIONS[k]["name"])
		"oro": show_toast("Oro insuficiente (%d)" % Smithing.INFUSE_GOLD)
	_refresh_all(false)
	return r

# ---------------- Ajustes (ronda 20) ----------------

func _build_settings() -> void:
	var au := get_node_or_null("/root/Audio")
	list_box.add_child(UIKit.title("Volumen", 22))
	for bus: String in BUS_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := UIKit.label(BUS_NAMES[bus], 18)
		l.custom_minimum_size = Vector2(100, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.name = "Vol_" + bus
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(200, 32)
		sl.value = au.get_volume(bus) if au else 1.0
		var pl := UIKit.label("%d %%" % roundi(sl.value * 100.0), 16, UIKit.MUTED)
		pl.custom_minimum_size = Vector2(56, 0)
		sl.value_changed.connect(func(v: float) -> void:
			if au:
				au.set_volume(bus, v)
			pl.text = "%d %%" % roundi(v * 100.0)
			if bus == "UI" or bus == "Efectos":
				UIKit.sfx("click"))
		row.add_child(sl)
		row.add_child(pl)
		list_box.add_child(row)
	# Ronda 23: búfer de entrada
	list_box.add_child(UIKit.title("Controles", 22))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	var bl := UIKit.label("Búfer", 18)
	bl.custom_minimum_size = Vector2(100, 0)
	brow.add_child(bl)
	var bs := HSlider.new()
	bs.name = "BufferWindow"
	bs.min_value = 0.1
	bs.max_value = 1.5
	bs.step = 0.05
	bs.custom_minimum_size = Vector2(200, 32)
	bs.value = PlayerController.buffer_window
	var bp := UIKit.label("%.2f s" % bs.value, 16, UIKit.MUTED)
	bp.custom_minimum_size = Vector2(56, 0)
	bs.value_changed.connect(func(v: float) -> void:
		if au:
			au.set_buffer_window(v)
		else:
			PlayerController.buffer_window = v
		bp.text = "%.2f s" % v)
	brow.add_child(bs)
	brow.add_child(bp)
	list_box.add_child(brow)
	var ct := list_box.get_child(list_box.get_child_count() - 2)
	list_box.move_child(ct, 0) # Controles arriba, a la vista
	list_box.move_child(brow, 1)
	detail.text = "[b]Ajustes[/b]\nBúfer: cuánto antes del final de una acción se guarda la siguiente pulsación (0,4 s por defecto).\nSe guardan en este dispositivo. Música y efectos provisionales (CC0, ver Créditos)."
