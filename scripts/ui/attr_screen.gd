class_name AttrScreen
extends Control
## Ronda 18: pantalla de atributos (pestaña Personaje). Reparto con +/−, vista previa de las
## estadísticas derivadas, confirmar y redistribuir (gratis por ahora).

signal closed(changed: bool)

var gs: Node
var pending: Dictionary = {}
var _value_labels: Dictionary = {}
var _minus: Dictionary = {}
var _plus: Dictionary = {}
var points_label: Label
var preview: RichTextLabel
var confirm_button: Button
var _changed := false

func open(game_state: Node) -> void:
	gs = game_state
	pending = gs.char_attrs().duplicate()
	_changed = false
	if get_child_count() == 0:
		_build()
	visible = true
	_refresh()
	UIKit.pop_in(get_child(1), 0.0, 0.5)

func _build() -> void:
	name = "AttrScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1280, 720)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.08, 0.72)
	dim.size = Vector2(1280, 720)
	add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(150, 50)
	p.size = Vector2(980, 620)
	p.custom_minimum_size = Vector2(980, 620)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UIKit.title("ATRIBUTOS", 32, UIKit.YELLOW))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	points_label = UIKit.title("", 24)
	points_label.name = "Points"
	head.add_child(points_label)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.custom_minimum_size = Vector2(520, 0)
	body.add_child(rows)
	for k: String in Attributes.KEYS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		rows.add_child(h)
		var nl := UIKit.label(Attributes.NAMES[k], 21)
		nl.custom_minimum_size = Vector2(170, 0)
		nl.tooltip_text = Attributes.DESC[k]
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(nl)
		var mb := UIKit.button("−", 22)
		mb.name = "Minus_" + k
		mb.custom_minimum_size = Vector2(52, 44)
		mb.pressed.connect(change.bind(k, -1))
		h.add_child(mb)
		_minus[k] = mb
		var vl := UIKit.title("", 24)
		vl.name = "Value_" + k
		vl.custom_minimum_size = Vector2(56, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(vl)
		_value_labels[k] = vl
		var pb := UIKit.button("+", 22)
		pb.name = "Plus_" + k
		pb.custom_minimum_size = Vector2(52, 44)
		pb.pressed.connect(change.bind(k, 1))
		h.add_child(pb)
		_plus[k] = pb
		var dl := UIKit.label(Attributes.DESC[k], 13, UIKit.MUTED)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(170, 0)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(dl)
	preview = RichTextLabel.new()
	preview.name = "Preview"
	preview.bbcode_enabled = true
	preview.custom_minimum_size = Vector2(400, 470)
	preview.add_theme_font_size_override("normal_font_size", 17)
	preview.add_theme_font_size_override("bold_font_size", 19)
	body.add_child(preview)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 20)
	v.add_child(foot)
	confirm_button = UIKit.big_button("Confirmar", 22)
	confirm_button.name = "AttrConfirm"
	confirm_button.custom_minimum_size = Vector2(200, 54)
	confirm_button.pressed.connect(confirm)
	foot.add_child(confirm_button)
	var rs := UIKit.button("Redistribuir (gratis)", 20)
	rs.name = "AttrRespec"
	rs.custom_minimum_size = Vector2(250, 54)
	rs.pressed.connect(respec)
	foot.add_child(rs)
	var cl := UIKit.button("Cerrar", 20)
	cl.name = "AttrClose"
	cl.custom_minimum_size = Vector2(160, 54)
	cl.pressed.connect(close)
	foot.add_child(cl)
	UIKit.close_x(self, Vector2(150 + 980 - 50, 58), "AttrX", close) # ronda 20

func free_points() -> int:
	return Attributes.free_points(gs.character_id, pending, gs.char_level())

func change(k: String, d: int) -> void:
	var start := Attributes.start_for(gs.character_id)
	var saved: Dictionary = gs.char_attrs()
	var nv := int(pending[k]) + d
	# No baja de lo ya confirmado (para bajar, «Redistribuir»).
	if nv < maxi(int(start[k]), int(saved[k])) or nv > Attributes.MAX_VALUE:
		return
	if d > 0 and free_points() <= 0:
		return
	pending[k] = nv
	_refresh()

func confirm() -> void:
	if gs.set_attrs(pending) == "ok":
		_changed = true
		UIKit.sfx("levelup")
	_refresh()

func respec() -> void:
	gs.respec()
	pending = gs.char_attrs().duplicate()
	_changed = true
	_refresh()

func close() -> void:
	visible = false
	closed.emit(_changed)

func _fmt(cur: float, nxt: float, f: String, lower_better: bool = false) -> String:
	var a := f % cur
	var b := f % nxt
	if a == b:
		return a
	var good := (nxt < cur) if lower_better else (nxt > cur)
	return "%s → [color=%s]%s[/color]" % [a, "#9fe08a" if good else "#ff8a7a", b]

func _refresh() -> void:
	var saved: Dictionary = gs.char_attrs()
	var start := Attributes.start_for(gs.character_id)
	for k: String in Attributes.KEYS:
		(_value_labels[k] as Label).text = str(pending[k])
		(_value_labels[k] as Label).add_theme_color_override("font_color", UIKit.YELLOW if int(pending[k]) != int(saved[k]) else UIKit.TEXT)
		(_minus[k] as Button).disabled = int(pending[k]) <= maxi(int(start[k]), int(saved[k]))
		(_plus[k] as Button).disabled = free_points() <= 0 or int(pending[k]) >= Attributes.MAX_VALUE
	points_label.text = "Nivel %d · Puntos: %d" % [gs.char_level(), free_points()]
	confirm_button.disabled = pending == saved
	var c := Catalog.character(gs.character_id)
	var w := Catalog.weapon(gs.weapon_id)
	var a := Attributes.derived(c.id, saved)
	var b := Attributes.derived(c.id, pending)
	var t := "[b]Vista previa[/b]\n"
	t += "Vida: %s\n" % _fmt(c.vida + a["vida"], c.vida + b["vida"], "%.0f")
	t += "Defensa: %s\n" % _fmt(EquipStats.defense(gs.char_level(), saved), EquipStats.defense(gs.char_level(), pending), "%.1f")
	t += "Estamina: %s\n" % _fmt(c.estamina + a["estamina"], c.estamina + b["estamina"], "%.0f")
	t += "Equilibrio (poise): %s\n" % _fmt(c.poise + a["poise"], c.poise + b["poise"], "%.0f")
	t += "Robustez (aturdimiento recibido): %s\n" % _fmt(a["stun_taken"] * 100.0, b["stun_taken"] * 100.0, "%.0f %%", true)
	t += "Carga: %s\n" % _fmt(a["carga"], b["carga"], "%.1f")
	t += "Energía: %s · regen %s/s\n" % [_fmt(a["energia_max"], b["energia_max"], "%.0f"), _fmt(a["energia_regen"], b["energia_regen"], "%.1f")]
	t += "Daño de %s: %s\n" % [w.display_name, _fmt(Attributes.weapon_mult(w, c.id, saved) * 100.0, Attributes.weapon_mult(w, c.id, pending) * 100.0, "%.0f %%")]
	t += "Aturdimiento infligido: %s\n" % _fmt(a["stun_dealt"] * 100.0, b["stun_dealt"] * 100.0, "%.0f %%")
	t += "Daño a equilibrio/guardia: %s\n" % _fmt(a["impacto"] * 100.0, b["impacto"] * 100.0, "%.0f %%")
	t += "Vel. ataque/disparo: %s\n" % _fmt(a["vel"] * 100.0, b["vel"] * 100.0, "%.0f %%")
	t += "Voltereta: coste %s · i-frames %s\n" % [_fmt(a["roll_cost"] * 100.0, b["roll_cost"] * 100.0, "%.0f %%", true), _fmt(a["iframes"], b["iframes"], "%+d")]
	t += "Poder mágico: %s\n" % _fmt(a["magia"], b["magia"], "%.0f")
	t += "Curación: %s · res. sagrada %s\n" % [_fmt(a["curacion"] * 100.0, b["curacion"] * 100.0, "%.0f %%"), _fmt(a["sagrado"] * 100.0, b["sagrado"] * 100.0, "%+.1f %%")]
	t += "Eikon (daño/vida): %s · medidor %s\n" % [_fmt(a["eikon"] * 100.0, b["eikon"] * 100.0, "%.0f %%"), _fmt(a["medidor"] * 100.0, b["medidor"] * 100.0, "%.0f %%")]
	var un := Attributes.unmet(w, pending)
	if not un.is_empty():
		t += "[color=#ff8a7a]⚠ %s: requisitos sin cumplir (%s) → −30 %% de daño[/color]\n" % [w.display_name, Attributes.req_text(w)]
	preview.text = t
