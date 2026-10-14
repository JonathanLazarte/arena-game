class_name CharSheet
extends Control
## Ronda 19: ficha del personaje (pestaña Personaje), estilo FF/«soulslike»: nivel, atributos
## (botón ATRIBUTOS bien visible), estadísticas derivadas y ranuras de equipo. Tocar una ranura
## abre un selector de lo que tienes con comparación (verde mejor / rojo peor).

signal attributes_requested
signal changed

const SLOTS := ["titulo", "arma", "arma2", "casco", "pecho", "guantes", "piernas", "eikon"]
const SLOT_NAMES := {"titulo": "Título", "arma": "Arma principal", "arma2": "Arma secundaria", "casco": "Casco", "pecho": "Pecho",
	"guantes": "Guantes", "piernas": "Piernas", "eikon": "Eikon",
	"anillo0": "Anillo 1", "anillo1": "Anillo 2", "talisman0": "Talismán 1", "talisman1": "Talismán 2", "talisman2": "Talismán 3"}
## Ronda 30: ranuras de accesorio (sin modelo 3D)
const TRINKET_SLOTS := ["anillo0", "anillo1", "talisman0", "talisman1", "talisman2"]

var gs: Node
var left: RichTextLabel
var stats: RichTextLabel
var slot_box: VBoxContainer
var attr_button: Button
var attr_dot: Control
var slot_buttons: Dictionary = {}
# Selector
var picker: Control
var picker_title: Label
var picker_list: VBoxContainer
var picker_diff: RichTextLabel
var picker_ok: Button
var picker_slot: String = ""
var picker_choice: String = ""

func build(game_state: Node) -> void:
	gs = game_state
	name = "CharSheet"
	position = Vector2(262, 76)
	size = Vector2(1000, 456)
	var p := UIKit.panel()
	p.size = size
	p.custom_minimum_size = size
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	# Columna 1: personaje, atributos y botón
	var c1 := VBoxContainer.new()
	c1.custom_minimum_size = Vector2(300, 0)
	c1.add_theme_constant_override("separation", 6)
	h.add_child(c1)
	left = RichTextLabel.new()
	left.name = "Summary"
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(300, 340)
	left.add_theme_font_size_override("normal_font_size", 15)
	left.add_theme_font_size_override("bold_font_size", 18)
	c1.add_child(left)
	attr_button = UIKit.big_button("ATRIBUTOS", 26)
	attr_button.name = "AtributosButton"
	attr_button.custom_minimum_size = Vector2(300, 64)
	attr_button.pressed.connect(func() -> void: attributes_requested.emit())
	c1.add_child(attr_button)
	attr_dot = UIKit.notify_dot(attr_button)
	# Columna 2: estadísticas derivadas
	stats = RichTextLabel.new()
	stats.name = "Stats"
	stats.bbcode_enabled = true
	stats.custom_minimum_size = Vector2(330, 420)
	stats.add_theme_font_size_override("normal_font_size", 14)
	stats.add_theme_font_size_override("bold_font_size", 16)
	h.add_child(stats)
	# Columna 3: equipo
	slot_box = VBoxContainer.new()
	slot_box.custom_minimum_size = Vector2(320, 0)
	slot_box.add_theme_constant_override("separation", 5)
	h.add_child(slot_box)
	slot_box.add_child(UIKit.title("EQUIPO", 20, UIKit.YELLOW))
	for s: String in SLOTS:
		var b := UIKit.button("", 15)
		b.name = "Slot_" + s
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(320, 34)
		b.clip_text = true
		b.pressed.connect(open_picker.bind(s))
		slot_box.add_child(b)
		slot_buttons[s] = b
	# Ronda 30: anillos (2) y talismanes (3), botones compactos
	for row_slots: Array in [["anillo0", "anillo1"], ["talisman0", "talisman1", "talisman2"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		slot_box.add_child(row)
		for ts: String in row_slots:
			var tb := UIKit.button("", 12)
			tb.name = "Slot_" + ts
			tb.clip_text = true
			tb.custom_minimum_size = Vector2((320 - 4 * (row_slots.size() - 1)) / row_slots.size(), 36)
			tb.pressed.connect(open_picker.bind(ts))
			row.add_child(tb)
			slot_buttons[ts] = tb
	_build_picker()

static func trinket_slot(s: String) -> Array:
	return ["ring" if s.begins_with("anillo") else "talisman", int(s.right(1))]

func _build_picker() -> void:
	picker = Control.new()
	picker.name = "EquipPicker"
	picker.visible = false
	picker.position = -position
	picker.size = Vector2(1280, 720)
	add_child(picker)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.08, 0.7)
	dim.size = Vector2(1280, 720)
	picker.add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(200, 70)
	p.size = Vector2(880, 580)
	p.custom_minimum_size = p.size
	picker.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	picker_title = UIKit.title("", 28, UIKit.YELLOW)
	v.add_child(picker_title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(400, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(sc)
	picker_list = VBoxContainer.new()
	picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_list.add_theme_constant_override("separation", 6)
	sc.add_child(picker_list)
	picker_diff = RichTextLabel.new()
	picker_diff.name = "Diff"
	picker_diff.bbcode_enabled = true
	picker_diff.custom_minimum_size = Vector2(420, 420)
	picker_diff.add_theme_font_size_override("normal_font_size", 16)
	h.add_child(picker_diff)
	var f := HBoxContainer.new()
	f.alignment = BoxContainer.ALIGNMENT_CENTER
	f.add_theme_constant_override("separation", 20)
	v.add_child(f)
	picker_ok = UIKit.big_button("Equipar", 22)
	picker_ok.name = "PickerEquip"
	picker_ok.custom_minimum_size = Vector2(200, 54)
	picker_ok.pressed.connect(confirm_pick)
	f.add_child(picker_ok)
	var c := UIKit.button("Cancelar", 20)
	c.name = "PickerCancel"
	c.custom_minimum_size = Vector2(160, 54)
	c.pressed.connect(func() -> void: picker.visible = false)
	UIKit.close_x(picker, Vector2(200 + 880 - 50, 78), "PickerX", func() -> void: picker.visible = false) # ronda 20
	f.add_child(c)

# ---------------- Contenido ----------------

func _cur_id(s: String) -> String:
	match s:
		"arma": return gs.weapon_id
		"arma2": return gs.weapon2_id
		"eikon": return gs.eikon_id
		"titulo": return gs.title_id()
	if s in TRINKET_SLOTS:
		var ks := trinket_slot(s)
		return String((gs.rings_eq if ks[0] == "ring" else gs.talismans_eq)[ks[1]])
	return String(gs.armor_eq.get(s, ""))

func _item_name(s: String, id: String) -> String:
	if id == "":
		return "— (recambio)" if s == "arma2" else "— Nada —"
	match s:
		"arma", "arma2": return Catalog.weapon(id).display_name
		"eikon": return (load(Catalog.EIKONS[id]) as EikonData).eikon_name
	if s in TRINKET_SLOTS or s == "titulo":
		return String(Trinkets.def(id).get("name", id))
	var a := Catalog.armor(id)
	return a.display_name if a else id

## Opciones del selector: lo que tienes y vale para la ranura.
func options(s: String) -> Array:
	var out: Array = []
	var c := Catalog.character(gs.character_id)
	match s:
		"arma":
			for w in Catalog.weapons_for(c):
				if w.id in gs.owned_weapons: out.append(w.id)
		"arma2":
			out.append("")
			var main_r: bool = Catalog.weapon(gs.weapon_id).ranged
			for w in Catalog.weapons_for(c):
				if w.id in gs.owned_weapons and w.ranged != main_r: out.append(w.id)
		"eikon":
			for id: String in Catalog.EIKONS:
				if id in gs.owned_eikons: out.append(id)
		"titulo":
			out.append("")
			out.append_array(gs.earned_titles())
		"anillo0", "anillo1", "talisman0", "talisman1", "talisman2":
			out.append("")
			for id: String in gs.owned_trinkets:
				if Trinkets.kind(id) == trinket_slot(s)[0]: out.append(id)
		_:
			out.append("")
			for a in Catalog.armors():
				if a.slot == s and a.id in gs.owned_armor: out.append(a.id)
	return out

## Hoja que resultaría al equipar `id` en la ranura `s`.
func sheet_with(s: String, id: String) -> Dictionary:
	var c := Catalog.character(gs.character_id)
	var w := Catalog.weapon(gs.weapon_id)
	var w2: WeaponDef = gs.weapon2()
	var arm: Dictionary = gs.armor_eq.duplicate()
	match s:
		"arma":
			w = Catalog.weapon(id)
			if w2 and w2.ranged == w.ranged: w2 = null
		"arma2": w2 = Catalog.weapon(id) if id != "" else null
		"eikon", "titulo", "anillo0", "anillo1", "talisman0", "talisman1", "talisman2": pass
		_: arm[s] = id
	var sh := EquipStats.sheet(c, gs.char_level(), gs.char_attrs(), w, w2, EquipStats.armor_defs(arm))
	sh["ar"] = EquipStats.attack_rating(c, w, gs.char_attrs(), Progression.combine_mods(gs.char_skills())["dano"])
	sh["ar2"] = EquipStats.attack_rating(c, w2 if w2 else (Fighter.FALLBACK_BOW if not w.ranged else Fighter.FALLBACK_MELEE), gs.char_attrs(), 1.0, w2 != null)
	return sh

func open_picker(s: String) -> void:
	picker_slot = s
	picker_choice = _cur_id(s)
	picker_title.text = SLOT_NAMES[s]
	for ch in picker_list.get_children():
		ch.queue_free()
	for id: String in options(s):
		var b := UIKit.button(_item_name(s, id), 17, UIKit.ORANGE if id == _cur_id(s) else UIKit.BLUE)
		b.name = "Opt_" + (id if id != "" else "none")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(390, 44)
		b.pressed.connect(select_option.bind(id))
		picker_list.add_child(b)
	picker.visible = true
	_show_diff()

func select_option(id: String) -> void:
	picker_choice = id
	for b in picker_list.get_children():
		if b is Button:
			UIKit.button_styles(b, UIKit.ORANGE if String(b.name) == "Opt_" + (id if id != "" else "none") else UIKit.BLUE)
	_show_diff()

func _cmp(label: String, a: float, b: float, fmt: String, lower_better: bool = false) -> String:
	var sa := fmt % a
	var sb := fmt % b
	if sa == sb:
		return "%s: %s\n" % [label, sa]
	var good := (b < a) if lower_better else (b > a)
	return "%s: %s → [color=%s]%s[/color]\n" % [label, sa, "#9fe08a" if good else "#ff8a7a", sb]

## Comparación con lo equipado ahora.
func diff_text(s: String, id: String) -> String:
	var a := sheet_with(s, _cur_id(s))
	var b := sheet_with(s, id)
	var t := "[b]%s[/b]\n" % _item_name(s, id)
	if s.begins_with("arma"):
		var w := Catalog.weapon(id) if id != "" else null
		if w:
			t += "Escalado: %s · Requisitos: %s\n" % [Attributes.scaling_text(w), Attributes.req_text(w)]
			if not Attributes.unmet(w, gs.char_attrs()).is_empty():
				t += "[color=#ff8a7a]⚠ No cumples los requisitos (−30 %% de daño)[/color]\n"
		t += _cmp("Ataque principal", a["ar"]["total"], b["ar"]["total"], "%.1f")
		t += _cmp("Ataque secundario", a["ar2"]["total"], b["ar2"]["total"], "%.1f")
	if s == "titulo":
		t += String(Titles.def(id).get("desc", "Sin título.")) + "\n"
		for tid: String in Titles.ORDER:
			if not tid in gs.earned_titles():
				t += "[color=#8a93a8]🔒 %s — %s[/color]\n" % [Titles.def(tid)["name"], Titles.def(tid)["desc"]]
		return t
	if s in TRINKET_SLOTS:
		var td := Trinkets.def(id)
		t += String(td.get("desc", "Ranura vacía.")) + "\n"
		var ks := trinket_slot(s)
		var other := (gs.rings_eq if ks[0] == "ring" else gs.talismans_eq) as Array
		if id != "" and other.find(id) >= 0 and other.find(id) != ks[1]:
			t += "[color=#f2dc99]Ya está en otra ranura: se moverá aquí.[/color]\n"
		return t
	if s == "eikon":
		var ed: EikonData = load(Catalog.EIKONS[id])
		t += "%s\n%s · elemento %s" % [ed.description, "montable" if ed.rideable else "compañero", EquipStats.TYPE_NAMES[EquipStats.EIKON_ELEMENT.get(id, "fisico")]]
		return t
	var pa := Catalog.armor(id) if not s.begins_with("arma") else null
	if pa:
		t += "Peso %.1f · Equilibrio %.0f\n" % [pa.weight, pa.poise]
	for k: String in EquipStats.TYPES:
		t += _cmp("Absorción " + EquipStats.TYPE_NAMES[k], a["absorcion"][k] * 100.0, b["absorcion"][k] * 100.0, "%.1f %%")
	for k: String in EquipStats.RESISTS:
		t += _cmp(EquipStats.RESIST_NAMES[k], a["resist"][k], b["resist"][k], "%.0f")
	t += _cmp("Equilibrio (armadura)", a["armor_poise"], b["armor_poise"], "%.0f")
	t += _cmp("Carga", a["carga"] * 100.0, b["carga"] * 100.0, "%.0f %%", true)
	t += "Voltereta: %s → %s\n" % [EquipStats.LOAD_NAMES[a["clase"]], EquipStats.LOAD_NAMES[b["clase"]]]
	return t

func _show_diff() -> void:
	picker_diff.text = diff_text(picker_slot, picker_choice)
	picker_ok.disabled = picker_choice == _cur_id(picker_slot)

func confirm_pick() -> void:
	equip(picker_slot, picker_choice)
	picker.visible = false

func equip(s: String, id: String) -> bool:
	var ok := false
	match s:
		"arma":
			ok = gs.set_weapon(id)
			gs.save_loadout()
		"arma2": ok = gs.set_weapon2(id)
		"eikon":
			if id in gs.owned_eikons:
				gs.eikon_id = id
				gs.save_loadout()
				ok = true
		"titulo": ok = gs.set_title(id)
		"anillo0", "anillo1", "talisman0", "talisman1", "talisman2":
			var ks := trinket_slot(s)
			ok = gs.equip_trinket(ks[0], ks[1], id)
		_: ok = gs.equip_armor(s, id)
	if ok:
		UIKit.sfx("confirm")
		refresh()
		changed.emit()
	return ok

func refresh() -> void:
	var c := Catalog.character(gs.character_id)
	var at: Dictionary = gs.char_attrs()
	var ad := Attributes.derived(c.id, at)
	var m := Progression.combine_mods(gs.char_skills())
	var sh := sheet_with("eikon", gs.eikon_id)
	var pts: int = gs.attr_points()
	attr_button.text = "ATRIBUTOS  +%d" % pts if pts > 0 else "ATRIBUTOS"
	attr_dot.visible = pts > 0
	var cs: Dictionary = gs.char_stat()
	var t := "[b]%s[/b] · %s %s\n" % [gs.display_name_with_title(), c.display_name, c.role]
	t += "Jugado %s · Victorias %d / %d\n" % [gs.hours_text(cs["secs"]), cs["wins"], cs["matches"]]
	t += "[color=#f2dc99]Nivel %d[/color] · %d/%d XP\n" % [gs.char_level(),
		Progression.level_progress(int(gs.char_xp.get(c.id, 0))).x, Progression.level_progress(int(gs.char_xp.get(c.id, 0))).y]
	for k: String in Attributes.KEYS:
		t += "%s [b]%d[/b]%s" % [Attributes.NAMES[k], at[k], "\n" if Attributes.KEYS.find(k) % 2 == 1 else "   "]
	if pts > 0:
		t += "[color=#9fe08a]%d punto(s) de atributo sin repartir[/color]\n" % pts
	t += "\n[color=#f2dc99]Pasiva · %s:[/color] %s\n" % [c.passive_name, c.passive_desc]
	var learned: Array = []
	for sk: Dictionary in Progression.tree(c.id):
		if sk["id"] in gs.char_skills():
			learned.append(sk["name"])
	t += "[color=#f2dc99]Habilidades:[/color] %s (%d punto(s) libres)" % [", ".join(learned) if not learned.is_empty() else "ninguna", gs.skill_points()]
	left.text = t
	var s := "[b]ESTADÍSTICAS[/b]\n"
	s += "Vida %.0f · Energía %.0f · Estamina %.0f\n" % [c.vida + m["vida"] + ad["vida"], ad["energia_max"], c.estamina + m["estamina"] + ad["estamina"]]
	s += "Ataque (der.) %s: [b]%.0f[/b] + [color=#9fe08a]%.0f[/color]\n" % [Catalog.weapon(gs.weapon_id).display_name, sh["ar"]["base"], sh["ar"]["bonus"]]
	var w2n: String = gs.weapon2().display_name if gs.weapon2() else ("Arco (recambio)" if not Catalog.weapon(gs.weapon_id).ranged else "Dagas (recambio)")
	s += "Ataque (izq./dist.) %s: [b]%.0f[/b] + [color=#9fe08a]%.0f[/color]\n" % [w2n, sh["ar2"]["base"], sh["ar2"]["bonus"]]
	if sh["ar"]["sagrado"] > 0.05:
		s += "   (de ello sagrado %.1f)\n" % sh["ar"]["sagrado"]
	s += "Defensa: [b]%.0f[/b]\n[color=#f2dc99]Absorción[/color] " % sh["defensa"]
	var parts: Array = []
	for k: String in EquipStats.TYPES:
		parts.append("%s %.0f%%" % [EquipStats.TYPE_NAMES[k].substr(0, 3), sh["absorcion"][k] * 100.0])
	s += " · ".join(parts) + "\n[color=#f2dc99]Resistencias[/color] "
	parts = []
	for k: String in EquipStats.RESISTS:
		parts.append("%s %.0f" % [EquipStats.RESIST_NAMES[k], sh["resist"][k]])
	s += " · ".join(parts) + "\n"
	s += "Equilibrio: [b]%.0f[/b] (armadura %.0f)\n" % [c.poise + m["poise"] + ad["poise"] + sh["armor_poise"] - EquipStats.role_reference(c)["armor_poise"], sh["armor_poise"]]
	var pct: float = sh["carga"] * 100.0
	var col := "#9fe08a" if sh["clase"] in ["ligero", "medio"] else ("#f2dc99" if sh["clase"] == "pesado" else "#ff8a7a")
	s += "Carga de equipo: %.1f / %.1f ([color=%s]%.0f %% · %s[/color])\n" % [sh["peso"], sh["carga_max"], col, pct, EquipStats.LOAD_NAMES[sh["clase"]]]
	var filled := int(clampf(pct / 100.0, 0.0, 1.0) * 30.0)
	s += "[color=%s]%s[/color][color=#3a4660]%s[/color]\n" % [col, "█".repeat(filled), "█".repeat(30 - filled)]
	s += "%s\n" % sh["roll"]["name"]
	s += "Vel. de ataque: [b]%.0f %%[/b] (con Destreza)\n" % (ad["vel"] * 100.0) # ronda 31
	s += "Poder mágico %.0f · Curación %.0f %% · Eikon %.0f %%" % [ad["magia"], ad["curacion"] * 100.0, ad["eikon"] * 100.0]
	stats.text = s
	for sl: String in TRINKET_SLOTS:
		var nm := _item_name(sl, _cur_id(sl))
		(slot_buttons[sl] as Button).text = nm if _cur_id(sl) != "" else SLOT_NAMES[sl] + ": —"
		(slot_buttons[sl] as Button).tooltip_text = String(Trinkets.def(_cur_id(sl)).get("desc", ""))
	var tr: Array = gs.equipped_trinkets()
	if not tr.is_empty():
		var tn: Array = []
		for id: String in tr:
			tn.append(String(Trinkets.def(id)["name"]))
		s += "\n[color=#f2dc99]Accesorios:[/color] " + ", ".join(tn)
		stats.text = s
	for sl: String in SLOTS:
		(slot_buttons[sl] as Button).text = "%s:  %s" % [SLOT_NAMES[sl], _item_name(sl, _cur_id(sl))]
