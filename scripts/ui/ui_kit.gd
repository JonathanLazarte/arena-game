class_name UIKit
## Ronda 13: estilo inspirado en los menús de Final Fantasy. Paneles azul medianoche
## translúcidos con filos finos plateados/dorados y degradado suave, barra de selección
## con cursor, motivos de cristal, Cinzel (títulos) y Lato (texto), ambas OFL.
## Los nombres de color se mantienen por compatibilidad: ORANGE/YELLOW = oro,
## BLUE = medianoche, CYAN = cristal, GREEN = verde jade, RED = carmesí apagado.

const NAVY := Color(0.03, 0.06, 0.16)
const BLUE := Color(0.08, 0.16, 0.36)
const CYAN := Color(0.45, 0.78, 1.0) ## cristal
const ORANGE := Color(0.82, 0.68, 0.4) ## oro
const YELLOW := Color(0.95, 0.86, 0.6) ## oro claro
const RED := Color(0.78, 0.32, 0.36)
const GREEN := Color(0.45, 0.85, 0.7)
const SILVER := Color(0.78, 0.82, 0.9)
const TEXT := Color(0.94, 0.95, 1.0)
const MUTED := Color(0.66, 0.72, 0.84)
const OUTLINE := Color(0.0, 0.02, 0.08)
const PANEL_BG := Color(0.03, 0.07, 0.18, 0.82)

static var _display: Font
static var _body: Font
static var _bold: Font
static var _theme: Theme
static var _shard_tex: Texture2D

## Cinzel (OFL) para títulos.
static func display_font() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Cinzel.ttf")
		fv.variation_opentype = {"wght": 500}
		fv.spacing_glyph = 1
		_display = fv
	return _display

## Lato (OFL) para texto y botones.
static func body_font() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/Lato-Regular.ttf")
	return _body

static func bold_font() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Lato-Bold.ttf")
	return _bold

## Caja translúcida con filo fino.
static func box(bg: Color, border: Color = Color(SILVER, 0.45), bw: int = 1, radius: int = 4, shadow: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0.02, 0.1, 0.45)
	sb.shadow_size = shadow
	sb.anti_aliasing = true
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Barra de selección: degradado azul cristal que se desvanece hacia la derecha.
static func highlight_bar(alpha: float = 0.85) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.52, 0.9, alpha))
	g.set_color(1, Color(0.1, 0.2, 0.45, alpha * 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	var sb := StyleBoxTexture.new()
	sb.texture = gt
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Estilo de botón según su papel: ORANGE/YELLOW/RED = seleccionado (barra + cursor),
## GREEN = disponible (filo cristal), gris = apagado, el resto = normal.
static func button_styles(b: Button, c: Color, _radius: int = 4) -> void:
	var selected := c == ORANGE or c == YELLOW or c == RED
	var avail := c == GREEN
	var dim := not selected and not avail and c != BLUE and c != NAVY and c != CYAN
	b.set_meta("selected", selected)
	var normal: StyleBox
	if selected:
		normal = highlight_bar()
	elif avail:
		normal = box(Color(0.05, 0.12, 0.28, 0.7), Color(CYAN, 0.85), 1, 4, 10)
	elif dim:
		normal = box(Color(0.03, 0.05, 0.1, 0.55), Color(SILVER, 0.18), 1, 4, 0)
	else:
		normal = box(Color(0.04, 0.08, 0.2, 0.6), Color(SILVER, 0.3), 1, 4, 0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", highlight_bar(0.65) if not selected else highlight_bar(1.0))
	b.add_theme_stylebox_override("pressed", highlight_bar(1.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", box(Color(0.03, 0.05, 0.1, 0.5), Color(SILVER, 0.12), 1, 4, 0))
	b.add_theme_color_override("font_color", YELLOW if selected else (MUTED if dim else TEXT))
	var p := b.get_node_or_null("Cursor") as CanvasItem
	if p:
		p.visible = selected

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_constant("outline_size", "Label", 3)
	t.set_color("font_shadow_color", "Label", Color(0, 0.05, 0.2, 0.6))
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "Button", body_font())
	t.set_font_size("font_size", "Button", 19)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", YELLOW)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 3)
	var tb := Button.new()
	button_styles(tb, BLUE)
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(st, "Button", tb.get_theme_stylebox(st))
	tb.free()
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, Color(SILVER, 0.55), 1, 4, 14))
	t.set_stylebox("normal", "LineEdit", box(Color(0.02, 0.04, 0.12, 0.6), Color(SILVER, 0.35), 1, 3, 0))
	t.set_font("font", "LineEdit", display_font())
	t.set_color("font_color", "LineEdit", TEXT)
	var fill := box(CYAN, Color(0, 0, 0, 0), 0, 2, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	t.set_stylebox("fill", "ProgressBar", fill)
	var bg := box(Color(0.0, 0.02, 0.08, 0.7), Color(SILVER, 0.4), 1, 2, 0)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", display_font())
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", 2)
	_theme = t
	return t

## Título en Cinzel con brillo suave.
static func title(text: String, size: int, c: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.3, 0.8))
	l.add_theme_constant_override("outline_size", maxi(3, size / 12))
	l.add_theme_color_override("font_shadow_color", Color(0.3, 0.55, 1.0, 0.35)) # halo azul
	l.add_theme_constant_override("shadow_outline_size", maxi(4, size / 5))
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_offset_x", 0)
	return l

static func label(text: String, size: int = 18, c: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l

## Botón de menú: fila translúcida; seleccionado = barra degradada + cursor de cristal.
static func button(text: String, size: int = 19, c: Color = BLUE) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var cur := MenuCursor.new()
	cur.name = "Cursor"
	cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cur.size = Vector2(22, 18)
	cur.visible = false
	b.add_child(cur)
	b.resized.connect(func() -> void: cur.position = Vector2(-26, (b.size.y - 18) * 0.5))
	button_styles(b, c)
	juice(b)
	return b

## Reacción sobria: el cursor aparece al pasar y se oye un "tic"; sin rebotes.
static func juice(b: Button) -> void:
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		var cur := b.get_node_or_null("Cursor") as CanvasItem
		if cur:
			cur.visible = true
		sfx("hover"))
	b.mouse_exited.connect(func() -> void:
		var cur := b.get_node_or_null("Cursor") as CanvasItem
		if cur:
			cur.visible = b.get_meta("selected", false))
	b.pressed.connect(func() -> void: sfx("click"))

## Botón principal: marco dorado fino con resplandor de cristal y un brillo lento.
static func big_button(text: String, size: int = 40, c: Color = YELLOW) -> Button:
	var b := button(text, size, BLUE)
	b.add_theme_font_override("font", display_font())
	var n := box(Color(0.05, 0.12, 0.3, 0.85), Color(ORANGE, 0.9), 1, 4, 18)
	n.shadow_color = Color(0.3, 0.55, 1.0, 0.35)
	var h := box(Color(0.1, 0.22, 0.48, 0.92), Color(YELLOW, 1.0), 1, 4, 24)
	h.shadow_color = Color(0.4, 0.7, 1.0, 0.5)
	var p := box(Color(0.16, 0.3, 0.6, 0.95), Color(YELLOW, 1.0), 2, 4, 10)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	var fc := YELLOW if c == YELLOW else (GREEN if c == GREEN else TEXT)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	shine(b)
	return b

## Reflejo muy tenue que cruza el botón despacio.
static func shine(b: Control) -> void:
	b.clip_contents = true
	var s := ColorRect.new()
	s.name = "Shine"
	s.color = Color(0.7, 0.85, 1.0, 0.12)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size = Vector2(60, 300)
	s.rotation = 0.35
	s.position = Vector2(-140, -100)
	b.add_child(s)
	var start := func() -> void:
		if not b.is_inside_tree():
			return
		var tw := b.create_tween().set_loops()
		tw.tween_property(s, "position:x", b.size.x + 140, 1.8).from(-140.0).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(3.5)
	if b.is_inside_tree():
		start.call()
	else:
		b.tree_entered.connect(start, CONNECT_ONE_SHOT)

## Panel azul medianoche con filo plateado, línea dorada interior y cristales en las esquinas.
static func panel(_header: String = "") -> PanelContainer:
	return CrystalPanel.new()

## Entrada refinada: aparece deslizándose y con fundido (el parámetro "from" se ignora).
static func pop_in(c: CanvasItem, delay: float = 0.0, _from: float = 0.6) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(delay).set_trans(Tween.TRANS_SINE)
	if c is Control and not ((c as Control).get_parent() is Container):
		var ctl := c as Control
		var x := ctl.position.x
		ctl.position.x = x + 14
		c.create_tween().tween_property(ctl, "position:x", x, 0.4).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Fila de estadística: etiqueta, barra fina y valor.
static func stat_row(label_text: String, v: float, vmax: float, txt: String, w: float = 170, c: Color = CYAN) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(label_text, 16, MUTED)
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = vmax
	bar.value = v
	bar.custom_minimum_size = Vector2(w, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var g := Gradient.new()
	g.set_color(0, c.darkened(0.35))
	g.set_color(1, c.lightened(0.2))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	var fill := StyleBoxTexture.new()
	fill.texture = gt
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	h.add_child(label("  " + txt, 16, TEXT))
	return h

## Moneda: icono + cantidad (sin "+": sin tienda).
static func currency_pill(kind: String, amount_label: Label) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.02, 0.05, 0.14, 0.55), Color(SILVER, 0.3), 1, 14, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var ic := CurrencyIcon.new()
	ic.kind = kind
	ic.custom_minimum_size = Vector2(24, 26)
	h.add_child(ic)
	amount_label.custom_minimum_size = Vector2(64, 0)
	h.add_child(amount_label)
	return p

## Indicador de novedad: pequeño cristal azul que brilla.
static func notify_dot(parent: Control) -> Control:
	var d := NotifyDot.new()
	d.name = "Dot"
	d.size = Vector2(14, 20)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	var place := func() -> void: d.position = Vector2(parent.size.x - 22, (parent.size.y - 20) * 0.5)
	parent.resized.connect(place)
	place.call()
	return d

## Textura de esquirla de cristal (rombo alargado) generada en código.
static func shard_texture() -> Texture2D:
	if _shard_tex:
		return _shard_tex
	var img := Image.create(12, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		var w := (1.0 - absf(y - 11.5) / 12.0) * 6.0
		for x in 12:
			var d := absf(x - 5.5)
			if d <= w:
				var a := 1.0 - d / maxf(w, 0.01) * 0.6
				img.set_pixel(x, y, Color(0.8, 0.92, 1.0, a))
	_shard_tex = ImageTexture.create_from_image(img)
	return _shard_tex

## Esquirlas de cristal 2D que suben y se desvanecen (CPUParticles2D, barato en móvil).
static func crystal_shards(parent: Node, amount: int = 24, area: Rect2 = Rect2(0, 740, 1280, 10)) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Shards"
	p.texture = shard_texture()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = area.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = area.size * 0.5
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2(0, -4)
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 40.0
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.85, 1.0, 0.0))
	g.add_point(0.25, Color(0.7, 0.9, 1.0, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.7, 1.0, 0.0))
	p.color_ramp = g
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	parent.add_child(p)
	return p

## Línea ornamental: filo dorado que se desvanece en los extremos con un cristal central.
static func ornament_line(width: float = 420) -> Control:
	var o := OrnamentLine.new()
	o.custom_minimum_size = Vector2(width, 14)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return o

## Sonido de interfaz (autoload "Sfx").
static func sfx(name: String) -> void:
	var t := Engine.get_main_loop() as SceneTree
	var s := t.root.get_node_or_null("Sfx") if t else null
	if s:
		s.play(name)

## Cambio de escena con fundido (autoload "Fade"); sin él, cambio directo.
static func go(path: String, d: float = 0.35) -> void:
	var t := Engine.get_main_loop() as SceneTree
	var f := t.root.get_node_or_null("Fade")
	if f:
		f.go(path, d)
	else:
		t.change_scene_to_file(path)

## Ronda 20: botón de cierre «✕» (arriba a la derecha de cada panel).
static func close_x(parent: Node, pos: Vector2, nm: String, cb: Callable) -> Button:
	var b := button("✕", 22, RED)
	b.name = nm
	b.tooltip_text = "Cerrar (Esc)"
	b.custom_minimum_size = Vector2(42, 42)
	b.size = Vector2(42, 42)
	b.position = pos
	b.pressed.connect(func() -> void:
		sfx("click")
		cb.call())
	parent.add_child(b)
	return b

static func audio(name: String) -> void:
	var t := Engine.get_main_loop() as SceneTree
	var a := t.root.get_node_or_null("Audio") if t else null
	if a:
		a.sfx(name, "UI")
