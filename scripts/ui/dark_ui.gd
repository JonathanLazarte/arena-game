class_name DarkUI
## Ronda 11: estilo DARK FANTASY compartido (paleta, fuentes, paneles ornamentados,
## botones con animación y sonido, viñeta y brasas).

const BLACK := Color(0.035, 0.03, 0.035)
const CRIMSON := Color(0.42, 0.04, 0.06)
const BLOOD := Color(0.62, 0.07, 0.08)
const GOLD := Color(0.74, 0.6, 0.34) ## oro deslustrado
const GOLD_BRIGHT := Color(0.92, 0.78, 0.46)
const ASH := Color(0.62, 0.59, 0.56)
const BONE := Color(0.88, 0.84, 0.76)
const PANEL_BG := Color(0.06, 0.035, 0.04, 0.92)

static var _display: Font
static var _body: Font
static var _theme: Theme

## Cinzel (OFL) en negrita para títulos.
static func display_font() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Cinzel.ttf")
		fv.variation_opentype = {"wght": 700}
		_display = fv
	return _display

## IM Fell English (OFL) para el texto.
static func body_font() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/IMFellEnglish.ttf")
	return _body

static func box(bg: Color, border: Color = GOLD, bw: int = 2, radius: int = 3, shadow: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 2 # esquinas biseladas
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = shadow
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", BONE)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 4)
	# Botones: carmesí oscuro con marco de oro deslustrado
	t.set_font("font", "Button", display_font())
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", GOLD_BRIGHT)
	t.set_color("font_disabled_color", "Button", ASH.darkened(0.4))
	t.set_color("font_outline_color", "Button", Color.BLACK)
	t.set_constant("outline_size", "Button", 4)
	t.set_stylebox("normal", "Button", box(Color(0.1, 0.05, 0.06, 0.92), GOLD.darkened(0.35), 2, 3, 6))
	t.set_stylebox("hover", "Button", box(Color(0.24, 0.05, 0.07, 0.96), GOLD, 2, 3, 8))
	t.set_stylebox("pressed", "Button", box(Color(0.42, 0.06, 0.08, 1.0), GOLD_BRIGHT, 2, 3, 4))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD_BRIGHT, 2, 3, 0))
	t.set_stylebox("disabled", "Button", box(Color(0.06, 0.05, 0.05, 0.85), ASH.darkened(0.6), 2, 3, 0))
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, GOLD.darkened(0.2), 2, 3, 14))
	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.03, 0.03, 0.9), GOLD.darkened(0.5), 1, 2, 0))
	t.set_color("font_color", "LineEdit", GOLD_BRIGHT)
	t.set_font("font", "LineEdit", display_font())
	var fill := box(BLOOD, Color(0, 0, 0, 0), 0, 2, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	t.set_stylebox("fill", "ProgressBar", fill)
	var bg := box(Color(0.02, 0.02, 0.02, 0.9), GOLD.darkened(0.55), 1, 2, 0)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font("bold_font", "RichTextLabel", display_font())
	t.set_color("default_color", "RichTextLabel", BONE)
	_theme = t
	return t

## Título en Cinzel dorado.
static func title(text: String, size: int, c: Color = GOLD_BRIGHT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.0))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l

static func label(text: String, size: int = 18, c: Color = BONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l

## Botón con animación (crece al pasar, se hunde al pulsar) y sonidos.
static func button(text: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	juice(b)
	return b

static func juice(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	var tw_to := func(k: float, d: float) -> void:
		if not b.is_inside_tree():
			return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * k, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			tw_to.call(1.05, 0.12)
			DarkUI.sfx("hover"))
	b.mouse_exited.connect(func() -> void: tw_to.call(1.0, 0.12))
	b.button_down.connect(func() -> void: tw_to.call(0.94, 0.06))
	b.button_up.connect(func() -> void: tw_to.call(1.0, 0.15))
	b.pressed.connect(func() -> void: DarkUI.sfx("click"))

## Botón principal: rojo sangre con borde dorado y brillo pulsante.
static func big_button(text: String, size: int = 44) -> Button:
	var b := button(text, size)
	b.add_theme_stylebox_override("normal", box(Color(0.45, 0.04, 0.06), GOLD, 3, 4, 16))
	b.add_theme_stylebox_override("hover", box(Color(0.6, 0.06, 0.08), GOLD_BRIGHT, 3, 4, 20))
	b.add_theme_stylebox_override("pressed", box(Color(0.3, 0.02, 0.04), GOLD_BRIGHT, 3, 4, 6))
	b.add_theme_color_override("font_color", GOLD_BRIGHT)
	b.add_theme_constant_override("outline_size", 8)
	return b

## Panel ornamentado (marco doble y adornos en las esquinas).
static func panel() -> PanelContainer:
	var p := OrnatePanel.new()
	return p

## Viñeta a pantalla completa (no bloquea la entrada).
static func vignette(parent: Node, strength: float = 0.75) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Vignette"
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.size = Vector2(1280, 720)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.75;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(0.02, 0.0, 0.0, v * strength);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("strength", strength)
	r.material = m
	parent.add_child(r)
	return r

## Brasas 2D que suben (CPUParticles2D: barato y compatible con móvil).
static func embers_2d(parent: Node, amount: int = 40) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Embers"
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.position = Vector2(640, 740)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 10)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(8, -6)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.15, 0.0))
	g.add_point(0.15, Color(1.0, 0.5, 0.1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.05, 0.02, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	return p

## Barra de estadística con etiqueta y valor.
static func stat_row(label_text: String, v: float, vmax: float, txt: String, w: float = 170) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(label_text, 16, ASH)
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = vmax
	bar.value = v
	bar.custom_minimum_size = Vector2(w, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(label("  " + txt, 16, BONE))
	return h

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
