extends Node3D
## Primera ejecución: "ELIGE TU DESTINO". Presenta los 5 roles (modelo, descripción y
## estadísticas) y pide confirmación. Solo el elegido queda desbloqueado.

var gs: Node
var stage: DarkStage
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
	stage = DarkStage.new()
	stage.cam_x = -0.2
	add_child(stage)
	stage.spin_speed = 0.25
	_build_ui()
	select(0)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	DarkUI.vignette(ui, 0.9)
	DarkUI.embers_2d(ui, 45)
	root_ui = Control.new()
	root_ui.theme = DarkUI.theme()
	root_ui.size = Vector2(1280, 720)
	ui.add_child(root_ui)
	var t := DarkUI.title("ELIGE TU DESTINO", 56)
	t.position = Vector2(0, 18)
	t.size = Vector2(1280, 70)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(t)
	var sub := DarkUI.label("Solo un campeón responderá a tu llamada. Los demás tendrán que ganarse con oro.", 20, DarkUI.ASH)
	sub.position = Vector2(0, 88)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_ui.add_child(sub)
	# Ficha del rol (izquierda)
	var p := DarkUI.panel()
	p.position = Vector2(30, 140)
	p.custom_minimum_size = Vector2(400, 400)
	p.size = Vector2(400, 400)
	root_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	name_label = DarkUI.title("", 40)
	v.add_child(name_label)
	role_label = DarkUI.label("", 20, DarkUI.BLOOD.lightened(0.35))
	v.add_child(role_label)
	desc = RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.custom_minimum_size = Vector2(370, 120)
	v.add_child(desc)
	stats_box = VBoxContainer.new()
	v.add_child(stats_box)
	# Flechas y fila de roles
	var prev := DarkUI.button("◀", 30)
	prev.name = "Prev"
	prev.position = Vector2(470, 300)
	prev.custom_minimum_size = Vector2(60, 70)
	prev.pressed.connect(func() -> void: select(index - 1))
	root_ui.add_child(prev)
	var nxt := DarkUI.button("▶", 30)
	nxt.name = "Next"
	nxt.position = Vector2(820, 300)
	nxt.custom_minimum_size = Vector2(60, 70)
	nxt.pressed.connect(func() -> void: select(index + 1))
	root_ui.add_child(nxt)
	var row := HBoxContainer.new()
	row.position = Vector2(30, 600)
	row.add_theme_constant_override("separation", 10)
	root_ui.add_child(row)
	for i in chars.size():
		var b := DarkUI.button(chars[i].display_name, 19)
		b.name = "Role_" + chars[i].id
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 64)
		b.pressed.connect(select.bind(i))
		row.add_child(b)
		role_buttons.append(b)
	confirm_button = DarkUI.big_button("SELLAR PACTO", 34)
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
	dim.color = Color(0, 0, 0, 0.75)
	dim.size = Vector2(1280, 720)
	modal.add_child(dim)
	var mp := DarkUI.panel()
	mp.position = Vector2(360, 210)
	mp.custom_minimum_size = Vector2(560, 280)
	mp.size = Vector2(560, 280)
	modal.add_child(mp)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 16)
	mp.add_child(mv)
	var mt := DarkUI.title("¿Sellar el pacto?", 32)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	modal_text = DarkUI.label("", 19)
	modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_text.custom_minimum_size = Vector2(520, 0)
	modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(modal_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	mv.add_child(h)
	accept_button = DarkUI.big_button("Jurar lealtad", 22)
	accept_button.name = "Aceptar"
	accept_button.custom_minimum_size = Vector2(220, 54)
	accept_button.pressed.connect(accept)
	h.add_child(accept_button)
	var back := DarkUI.button("Volver", 20)
	back.name = "Volver"
	back.custom_minimum_size = Vector2(160, 54)
	back.pressed.connect(func() -> void: modal.visible = false)
	h.add_child(back)

func select(i: int) -> void:
	index = (i + chars.size()) % chars.size()
	var c := chars[index]
	stage.show_character(c, Catalog.weapon(c.default_weapon))
	stage.pedestal.rotation.y = 0.0
	name_label.text = c.display_name
	role_label.text = c.role
	desc.text = "%s\n\n[color=#c9a35a]Pasiva · %s:[/color] %s\n[color=#8f8a85]Arma: %s[/color]" % [c.description, c.passive_name, c.passive_desc, Catalog.weapon(c.default_weapon).display_name]
	for ch in stats_box.get_children():
		ch.queue_free()
	stats_box.add_child(DarkUI.stat_row("Vida", c.vida, 140.0, str(int(c.vida))))
	stats_box.add_child(DarkUI.stat_row("Estamina", c.estamina, 120.0, str(int(c.estamina))))
	stats_box.add_child(DarkUI.stat_row("Velocidad", c.velocidad, 1.25, "x%.2f" % c.velocidad))
	stats_box.add_child(DarkUI.stat_row("Poise", c.poise, 90.0, str(int(c.poise))))
	stats_box.add_child(DarkUI.stat_row("Daño", c.dano, 1.25, "x%.2f" % c.dano))
	for k in role_buttons.size():
		role_buttons[k].button_pressed = k == index
	name_label.modulate.a = 0.0
	name_label.create_tween().tween_property(name_label, "modulate:a", 1.0, 0.25)

func selected() -> CharacterDef:
	return chars[index]

func confirm_choice() -> void:
	var c := selected()
	modal_text.text = "%s será tu único campeón al empezar. Los otros cuatro se desbloquean con oro en el lobby." % c.display_name
	modal.visible = true

func accept() -> void:
	modal.visible = false
	gs.choose_first_character(selected().id)
	DarkUI.sfx("levelup")
	DarkUI.go("res://scenes/lobby.tscn", 0.6)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_LEFT, KEY_A: select(index - 1)
			KEY_RIGHT, KEY_D: select(index + 1)
			KEY_ENTER, KEY_KP_ENTER:
				if modal.visible: accept()
				else: confirm_choice()
			KEY_ESCAPE: modal.visible = false
