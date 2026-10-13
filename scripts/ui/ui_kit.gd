class_name UIKit
## Ronda 12: estilo móvil comercial (tipo Free Fire). Colores vivos, fuente Lilita One (OFL),
## botones brillantes con bisel y sombra, paneles redondeados, iconos de moneda/gema,
## animaciones de aparición y destello.

const NAVY := Color(0.05, 0.12, 0.28) ## fondo de paneles
const BLUE := Color(0.1, 0.42, 0.85)
const CYAN := Color(0.2, 0.8, 1.0)
const ORANGE := Color(1.0, 0.55, 0.1)
const YELLOW := Color(1.0, 0.84, 0.15)
const RED := Color(0.95, 0.2, 0.25)
const GREEN := Color(0.3, 0.85, 0.35)
const TEXT := Color(1, 1, 1)
const MUTED := Color(0.72, 0.82, 0.95)
const OUTLINE := Color(0.03, 0.07, 0.18)
const PANEL_BG := Color(0.06, 0.2, 0.45, 0.9)

static var _font: Font
static var _theme: Theme

## Lilita One (OFL): fuente gruesa de títulos y botones.
static func display_font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _font

## Caja redondeada con bisel (borde inferior más grueso) y sombra.
static func box(bg: Color, border: Color = Color(1, 1, 1, 0.35), bw: int = 2, radius: int = 14, shadow: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	if bw > 0:
		sb.border_width_bottom = bw + 3 # bisel
		sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb

## Estilos de un botón de color (normal / encima / pulsado).
static func button_styles(b: Button, c: Color, radius: int = 14) -> void:
	b.add_theme_stylebox_override("normal", box(c, c.darkened(0.35), 2, radius, 6))
	b.add_theme_stylebox_override("hover", box(c.lightened(0.15), c.darkened(0.25), 2, radius, 8))
	var p := box(c.darkened(0.12), c.darkened(0.45), 2, radius, 2)
	p.border_width_bottom = 2 # al pulsar se "hunde" el bisel
	p.content_margin_top = 11
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.8), 2, radius, 0))
	b.add_theme_stylebox_override("disabled", box(Color(0.35, 0.4, 0.48), Color(0.25, 0.28, 0.33), 2, radius, 0))

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 19
	for k: String in ["Label", "Button", "LineEdit"]:
		t.set_font("font", k, display_font())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_constant("outline_size", "Label", 6)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.8, 0.82, 0.86))
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 6)
	var tb := Button.new()
	button_styles(tb, BLUE)
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(st, "Button", tb.get_theme_stylebox(st))
	tb.free()
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, Color(0.45, 0.8, 1.0, 0.9), 3, 20, 10))
	t.set_stylebox("normal", "LineEdit", box(Color(0.02, 0.1, 0.25, 0.85), Color(0.4, 0.75, 1.0, 0.7), 2, 12, 0))
	t.set_color("font_color", "LineEdit", TEXT)
	var fill := box(ORANGE, Color(0, 0, 0, 0), 0, 8, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	t.set_stylebox("fill", "ProgressBar", fill)
	var bg := box(Color(0.02, 0.06, 0.16, 0.85), Color(1, 1, 1, 0.3), 1, 8, 0)
	bg.border_width_bottom = 1
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font("bold_font", "RichTextLabel", display_font())
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", 4)
	_theme = t
	return t

static func title(text: String, size: int, c: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	return l

static func label(text: String, size: int = 18, c: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l

## Botón brillante: color con bisel, franja de brillo arriba, animación y sonido.
static func button(text: String, size: int = 20, c: Color = BLUE) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	button_styles(b, c)
	_gloss(b)
	juice(b)
	return b

## Franja blanca semitransparente en la mitad superior (efecto "glossy").
static func _gloss(b: Button) -> void:
	var g := Panel.new()
	g.name = "Gloss"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 30
	sb.corner_radius_bottom_right = 30
	g.add_theme_stylebox_override("panel", sb)
	b.add_child(g)
	g.show_behind_parent = false
	var fit := func() -> void:
		g.position = Vector2(4, 3)
		g.size = Vector2(maxf(b.size.x - 8, 0), b.size.y * 0.42)
	b.resized.connect(fit)
	fit.call()

static func juice(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	var tw_to := func(k: float, d: float) -> void:
		if not b.is_inside_tree():
			return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * k, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			tw_to.call(1.06, 0.12)
			sfx("hover"))
	b.mouse_exited.connect(func() -> void: tw_to.call(1.0, 0.12))
	b.button_down.connect(func() -> void: tw_to.call(0.92, 0.05))
	b.button_up.connect(func() -> void: tw_to.call(1.0, 0.18))
	b.pressed.connect(func() -> void: sfx("click"))

## Botón principal amarillo con destello que lo recorre.
static func big_button(text: String, size: int = 44, c: Color = YELLOW) -> Button:
	var b := button(text, size, c)
	b.add_theme_color_override("font_color", Color(0.25, 0.12, 0.0) if c == YELLOW else TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.25, 0.12, 0.0) if c == YELLOW else TEXT)
	b.add_theme_color_override("font_pressed_color", Color(0.25, 0.12, 0.0) if c == YELLOW else TEXT)
	b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9) if c == YELLOW else OUTLINE)
	b.add_theme_constant_override("outline_size", 4 if c == YELLOW else 8)
	button_styles(b, c, 18)
	shine(b)
	return b

## Destello diagonal que cruza el botón cada pocos segundos.
static func shine(b: Control) -> void:
	b.clip_contents = true
	var s := ColorRect.new()
	s.name = "Shine"
	s.color = Color(1, 1, 1, 0.45)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size = Vector2(36, 260)
	s.rotation = 0.45
	s.position = Vector2(-120, -80)
	b.add_child(s)
	var start := func() -> void:
		if not b.is_inside_tree():
			return
		var tw := b.create_tween().set_loops()
		tw.tween_property(s, "position:x", b.size.x + 120, 0.7).from(-120.0).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(2.0)
	if b.is_inside_tree():
		start.call()
	else:
		b.tree_entered.connect(start, CONNECT_ONE_SHOT)

## Panel redondeado grueso. header != "" añade una pestaña de título.
static func panel(header: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if header != "":
		var h := title(header, 22)
		h.name = "Header"
		p.set_meta("header", h)
	return p

## Aparece con rebote (escala + opacidad).
static func pop_in(c: CanvasItem, delay: float = 0.0, from: float = 0.6) -> void:
	if c is Control:
		var ctl := c as Control
		ctl.pivot_offset = ctl.size * 0.5
	c.scale = Vector2.ONE * from
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(delay)

## Barra de estadística redondeada con color.
static func stat_row(label_text: String, v: float, vmax: float, txt: String, w: float = 170, c: Color = ORANGE) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(label_text, 16, MUTED)
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = vmax
	bar.value = v
	bar.custom_minimum_size = Vector2(w, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := box(c, Color(0, 0, 0, 0), 0, 7, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	h.add_child(label("  " + txt, 16, TEXT))
	return h

## Fila de moneda: icono + cantidad dentro de una píldora con "+".
static func currency_pill(kind: String, amount_label: Label) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.02, 0.08, 0.22, 0.85), Color(1, 1, 1, 0.25), 2, 20, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var ic := CurrencyIcon.new()
	ic.kind = kind
	ic.custom_minimum_size = Vector2(28, 28)
	h.add_child(ic)
	amount_label.custom_minimum_size = Vector2(70, 0)
	h.add_child(amount_label)
	var plus := label("+", 20, GREEN)
	h.add_child(plus)
	return p

## Punto rojo de notificación en la esquina de un control.
static func notify_dot(parent: Control) -> Control:
	var d := NotifyDot.new()
	d.name = "Dot"
	d.size = Vector2(18, 18)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	var place := func() -> void: d.position = Vector2(parent.size.x - 12, -6)
	parent.resized.connect(place)
	place.call()
	return d

## Sonido de interfaz (autoload "Sfx"; se busca por ruta para no depender del orden de compilación).
static func sfx(name: String) -> void:
	var t := Engine.get_main_loop() as SceneTree
	var s := t.root.get_node_or_null("Sfx") if t else null
	if s:
		s.play(name)

## Cambio de escena con fundido (autoload "Fade"); sin él, cambio directo.
static func go(path: String, d: float = 0.3) -> void:
	var t := Engine.get_main_loop() as SceneTree
	var f := t.root.get_node_or_null("Fade")
	if f:
		f.go(path, d)
	else:
		t.change_scene_to_file(path)
