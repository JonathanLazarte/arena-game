extends Node3D
## Primera ejecución: "ELIGE TU DESTINO". Presenta los 5 roles (modelo, descripción y
## estadísticas) y pide confirmación. Solo el elegido queda desbloqueado.

var gs: Node
var stage: ShowcaseStage
var index: int = 0
var chars: Array[CharacterDef] = []
var root_ui: Control
var name_label: Label
var role_label: Label
var desc: RichTextLabel
var stats_box: VBoxContainer
var role_buttons: Array[Button] = []
var confirm_button: Button
var modal: Control
var modal_text: Label
var accept_button: Button

func _ready() -> void:
	gs = get_node("/root/GameState")
	chars = Catalog.characters()
	stage = ShowcaseStage.new()
	stage.cam_x = -0.2
	add_child(stage)
	stage.spin_speed = 0.25
	_build_ui()
	select(0)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	root_ui = Control.new()
	root_ui.theme = UIKit.theme()
	ui.move_child(UIKit.crystal_shards(ui, 26), 0)
	root_ui.size = Vector2(1280, 720)
	ui.add_child(root_ui)
	var t := UIKit.title("ELIGE TU DESTINO", 56, UIKit.YELLOW)
	t.position = Vector2(0, 18)
	t.size = Vector2(1280, 70)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(t)
	var orn := UIKit.ornament_line(520)
	orn.position = Vector2(380, 80)
	root_ui.add_child(orn)
	var sub := UIKit.label("Solo un héroe responderá a tu llamada. Los demás podrán unirse a cambio de oro.", 20, UIKit.MUTED)
	sub.position = Vector2(0, 98)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(sub)
	# Ficha del rol (izquierda)
	var p := UIKit.panel()
	p.position = Vector2(30, 140)
	p.custom_minimum_size = Vector2(400, 400)
	p.size = Vector2(400, 400)
	root_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	name_label = UIKit.title("", 40)
	v.add_child(name_label)
	role_label = UIKit.label("", 22, UIKit.YELLOW)
	v.add_child(role_label)
	desc = RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.custom_minimum_size = Vector2(370, 120)
	v.add_child(desc)
	stats_box = VBoxContainer.new()
	v.add_child(stats_box)
	# Flechas y fila de roles
	var prev := UIKit.button("◀", 30)
	prev.name = "Prev"
	prev.position = Vector2(470, 300)
	prev.custom_minimum_size = Vector2(60, 70)
	prev.pressed.connect(func() -> void: select(index - 1))
	root_ui.add_child(prev)
	var nxt := UIKit.button("▶", 30)
	nxt.name = "Next"
	nxt.position = Vector2(820, 300)
	nxt.custom_minimum_size = Vector2(60, 70)
	nxt.pressed.connect(func() -> void: select(index + 1))
	root_ui.add_child(nxt)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 610)
	row.add_theme_constant_override("separation", 10)
	root_ui.add_child(row)
	for i in chars.size():
		var b := UIKit.button(chars[i].display_name, 19)
		b.name = "Role_" + chars[i].id
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 64)
		b.pressed.connect(select.bind(i))
		row.add_child(b)
		role_buttons.append(b)
	confirm_button = UIKit.big_button("Elegir", 36)
	confirm_button.name = "Confirmar"
	confirm_button.position = Vector2(900, 586)
	confirm_button.size = Vector2(350, 92)
	confirm_button.pressed.connect(confirm_choice)
	root_ui.add_child(confirm_button)
	# Confirmación
	modal = Control.new()
	modal.name = "Modal"
	modal.size = Vector2(1280, 720)
	modal.visible = false
	root_ui.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.08, 0.65)
	dim.size = Vector2(1280, 720)
	modal.add_child(dim)
	var mp := UIKit.panel()
	mp.position = Vector2(360, 210)
	mp.custom_minimum_size = Vector2(560, 280)
	mp.size = Vector2(560, 280)
	modal.add_child(mp)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 16)
	mp.add_child(mv)
	var mt := UIKit.title("¿Confirmar elección?", 30, UIKit.YELLOW)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	modal_text = UIKit.label("", 19)
	modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_text.custom_minimum_size = Vector2(520, 0)
	modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(modal_text)
	# Ronda 29: nombre propio del personaje (obligatorio)
	name_input = LineEdit.new()
	name_input.name = "CharNameInput"
	name_input.max_length = 16
	name_input.placeholder_text = "Nombre del personaje"
	name_input.add_theme_font_size_override("font_size", 22)
	name_input.custom_minimum_size = Vector2(320, 44)
	name_input.text_changed.connect(func(t: String) -> void: accept_button.disabled = t.strip_edges() == "")
	name_input.text_submitted.connect(func(_t: String) -> void: accept())
	mv.add_child(name_input)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	mv.add_child(h)
	accept_button = UIKit.big_button("Confirmar", 22)
	accept_button.name = "Aceptar"
	accept_button.custom_minimum_size = Vector2(220, 54)
	accept_button.pressed.connect(accept)
	h.add_child(accept_button)
	var back := UIKit.button("Volver", 20)
	back.name = "Volver"
	back.custom_minimum_size = Vector2(160, 54)
	back.pressed.connect(func() -> void: modal.visible = false)
	h.add_child(back)

func select(i: int) -> void:
	index = (i + chars.size()) % chars.size()
	var c := chars[index]
	var main_weapon := c.default_weapon
	stage.show_character(c, Catalog.weapon(main_weapon))
	stage.pedestal.rotation.y = 0.0
	name_label.text = c.display_name
	role_label.text = c.role
	var gear_text := "Mano derecha: %s" % Catalog.weapon(main_weapon).display_name
	var ranged_default := "arco" if c.allows("arco") else ""
	if ranged_default != "":
		gear_text += " · Terciaria: %s" % Catalog.weapon(ranged_default).display_name
	var main_def := Catalog.weapon(main_weapon)
	if c.shield_mesh != "" and main_def.allows_shield and not main_def.two_handed:
		gear_text += " · Mano izquierda: escudo"
	desc.text = "%s\n\n[color=#f2dc99]Pasiva · %s:[/color] %s\n[color=#a8ccff]%s[/color]" % [c.description, c.passive_name, c.passive_desc, gear_text]
	for ch in stats_box.get_children():
		ch.queue_free()
	stats_box.add_child(UIKit.stat_row("Vida", c.vida, 140.0, str(int(c.vida)), 170, UIKit.GREEN))
	stats_box.add_child(UIKit.stat_row("Estamina", c.estamina, 120.0, str(int(c.estamina)), 170, UIKit.YELLOW))
	stats_box.add_child(UIKit.stat_row("Velocidad", c.velocidad, 1.25, "x%.2f" % c.velocidad, 170, UIKit.CYAN))
	stats_box.add_child(UIKit.stat_row("Poise", c.poise, 90.0, str(int(c.poise))))
	stats_box.add_child(UIKit.stat_row("Daño", c.dano, 1.25, "x%.2f" % c.dano, 170, UIKit.RED))
	for k in role_buttons.size():
		role_buttons[k].button_pressed = k == index
		UIKit.button_styles(role_buttons[k], UIKit.ORANGE if k == index else UIKit.BLUE)
	UIKit.pop_in(name_label, 0.0, 0.7)

func selected() -> CharacterDef:
	return chars[index]

func confirm_choice() -> void:
	var c := selected()
	modal_text.text = "%s será tu personaje inicial. Ponle nombre. Más adelante podrás reclutar a otros en el lobby (Reclutar)." % c.display_name
	name_input.text = ""
	accept_button.disabled = true
	modal.visible = true
	name_input.grab_focus.call_deferred()
	UIKit.pop_in(modal.get_child(1), 0.0, 0.5)

var name_input: LineEdit
func accept() -> void:
	if gs.clean_name(name_input.text) == "":
		return
	modal.visible = false
	gs.choose_first_character(selected().id, name_input.text)
	UIKit.sfx("levelup")
	UIKit.go("res://scenes/lobby.tscn", 0.6)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_LEFT, KEY_A: select(index - 1)
			KEY_RIGHT, KEY_D: select(index + 1)
			KEY_ENTER, KEY_KP_ENTER:
				if modal.visible: accept()
				else: confirm_choice()
			KEY_ESCAPE: modal.visible = false
