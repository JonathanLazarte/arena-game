class_name BossIcon
extends Control
## Fase 9: icono vectorial de cada habilidad de jefe (sin depender de glifos de la fuente,
## que en algunos dispositivos salían como cajas con números). Se dibuja con primitivas en _draw.

var id: String = "":
	set(v):
		id = v
		queue_redraw()
var locked: bool = false: ## habilidad aún no disponible (p. ej. la 3.ª del campeón antes de la Fase II)
	set(v):
		locked = v
		queue_redraw()
var active: bool = false: ## en curso (resaltado)
	set(v):
		active = v
		queue_redraw()
var ring: bool = true ## círculo de fondo

static func make(ability_id: String, px: float = 32.0) -> BossIcon:
	var b := BossIcon.new()
	b.id = ability_id
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## Formas conocidas (pruebas): cada habilidad equipable tiene la suya.
static func has_glyph(ability_id: String) -> bool:
	return GLYPHS.has(ability_id)

const GLYPHS := ["estocada", "carga_area", "rafaga", "escudo_mana", "combo_falso", "salto_caida",
	"tajo_retardado", "presa_verdugo", "giro_martillo", "danza_cisne", "paso_espectral", "onda_rastrera",
	"rayos_trazadores", "lluvia_meteoros", "aliento_dragon", "furia_fase", "postura_contra", "embate_sismico", "lanza_celeste",
	"cuerno_embiste", "tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada", "estocada_negra",
	"flor_umbral", "presa_fauces", "giro_noble", "danza_triple", "alas_picado",
	"garra_suelo", "vendaval_hacha", "anillo_fuego", "pisoton",
	"lluvia_lanzas", "flecha_grave", "lluvia_sangre", "columnas_rayo",
	"saeta_oscura", "orbe_lunar", "aliento_rayo", "aliento_escarcha", "chorro_lava",
	"grito_guerra", "guardia_reflejo"]

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := BossAbilities.color_of(id)
	if locked:
		c = Color(0.55, 0.55, 0.6)
	if ring:
		draw_circle(o + Vector2(s, s) * 0.5, s * 0.5, Color(0.04, 0.05, 0.1, 0.75))
		draw_arc(o + Vector2(s, s) * 0.5, s * 0.47, 0.0, TAU, 32, Color(c, 1.0 if active else 0.7), maxf(s * (0.08 if active else 0.05), 1.0), true)
	var w := maxf(s * 0.075, 1.5)
	# P(x, y) en coordenadas 0..1 del cuadro
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	if locked:
		# candado
		draw_rect(Rect2(P.call(0.33, 0.48), Vector2(0.34, 0.26) * s), c, true)
		draw_arc(P.call(0.5, 0.48), s * 0.12, PI, TAU, 12, c, w, true)
		return
	if _glyph_extra(id, P, s, c, w):
		return
	match id:
		"estocada":
			draw_line(P.call(0.2, 0.5), P.call(0.78, 0.5), c, w * 1.4, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.78, 0.42), P.call(0.9, 0.5), P.call(0.78, 0.58)]), c)
			draw_line(P.call(0.3, 0.38), P.call(0.3, 0.62), c, w, true)
			for y in [0.3, 0.7]:
				draw_line(P.call(0.12, y), P.call(0.4, y), Color(c, 0.6), w * 0.6, true)
		"carga_area":
			draw_arc(P.call(0.5, 0.5), s * 0.32, 0.0, TAU, 24, c, w, true)
			draw_arc(P.call(0.5, 0.5), s * 0.2, 0.0, TAU, 20, Color(c, 0.75), w * 0.8, true)
			draw_circle(P.call(0.5, 0.5), s * 0.07, c)
		"rafaga":
			draw_arc(P.call(0.42, 0.5), s * 0.28, -1.2, 1.2, 16, c, w * 1.6, true)
			draw_arc(P.call(0.3, 0.5), s * 0.28, -1.0, 1.0, 14, Color(c, 0.5), w * 0.8, true)
		"escudo_mana":
			draw_arc(P.call(0.5, 0.52), s * 0.32, 0.0, TAU, 24, c, w, true)
			draw_circle(P.call(0.5, 0.36), s * 0.07, c)
			draw_line(P.call(0.5, 0.44), P.call(0.5, 0.66), c, w, true)
		"combo_falso":
			for k in 3:
				var x := 0.26 + k * 0.17
				draw_line(P.call(x, 0.72), P.call(x + 0.16, 0.28), c, w, true)
			draw_circle(P.call(0.8, 0.72), s * 0.05, Color(c, 0.6))
		"salto_caida":
			draw_line(P.call(0.5, 0.18), P.call(0.5, 0.62), c, w * 1.2, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.36, 0.56), P.call(0.64, 0.56), P.call(0.5, 0.74)]), c)
			draw_line(P.call(0.22, 0.8), P.call(0.78, 0.8), c, w, true)
		"tajo_retardado":
			draw_line(P.call(0.22, 0.74), P.call(0.6, 0.3), c, w * 1.3, true)
			draw_arc(P.call(0.7, 0.66), s * 0.14, 0.0, TAU, 14, c, w * 0.7, true)
			draw_line(P.call(0.7, 0.66), P.call(0.7, 0.57), c, w * 0.6, true)
			draw_line(P.call(0.7, 0.66), P.call(0.77, 0.66), c, w * 0.6, true)
		"presa_verdugo":
			draw_line(P.call(0.2, 0.62), P.call(0.55, 0.62), c, w * 1.2, true)
			for y in [0.4, 0.55, 0.7]:
				draw_polyline(PackedVector2Array([P.call(0.55, 0.62), P.call(0.72, y - 0.06), P.call(0.8, y + 0.04)]), c, w * 0.8, true)
		"giro_martillo":
			draw_arc(P.call(0.5, 0.5), s * 0.28, 0.4, TAU - 0.3, 22, c, w, true)
			draw_rect(Rect2(P.call(0.66, 0.2), Vector2(0.16, 0.2) * s), c, true)
		"danza_cisne":
			for k in 3:
				draw_arc(P.call(0.3 + k * 0.08, 0.72), s * (0.42 - k * 0.1), -PI * 0.5, -0.1, 12, Color(c, 1.0 - k * 0.25), w * 0.8, true)
		"paso_espectral":
			draw_circle(P.call(0.3, 0.66), s * 0.07, Color(c, 0.45))
			draw_circle(P.call(0.46, 0.52), s * 0.07, Color(c, 0.7))
			draw_circle(P.call(0.64, 0.38), s * 0.09, c)
			draw_arc(P.call(0.64, 0.38), s * 0.17, 0.0, TAU, 14, Color(c, 0.6), w * 0.6, true)
		"onda_rastrera":
			var pts := PackedVector2Array()
			for k in 13:
				var x := 0.14 + k * 0.06
				pts.append(P.call(x, 0.55 + sin(k * 1.1) * 0.12))
			draw_polyline(pts, c, w, true)
			draw_line(P.call(0.14, 0.76), P.call(0.86, 0.76), Color(c, 0.5), w * 0.6, true)
		"rayos_trazadores":
			draw_polyline(PackedVector2Array([P.call(0.58, 0.14), P.call(0.38, 0.5), P.call(0.56, 0.5), P.call(0.4, 0.86)]), c, w * 1.2, true)
		"lluvia_meteoros":
			for m in [[0.3, 0.35], [0.55, 0.5], [0.72, 0.28]]:
				draw_line(P.call(m[0] - 0.14, m[1] - 0.14), P.call(m[0], m[1]), Color(c, 0.55), w * 0.7, true)
				draw_circle(P.call(m[0], m[1]), s * 0.07, c)
			draw_line(P.call(0.18, 0.8), P.call(0.82, 0.8), Color(c, 0.6), w * 0.6, true)
		"aliento_dragon":
			draw_colored_polygon(PackedVector2Array([P.call(0.18, 0.5), P.call(0.82, 0.26), P.call(0.86, 0.5), P.call(0.82, 0.74)]), Color(c, 0.8))
			draw_circle(P.call(0.2, 0.5), s * 0.07, c)
		"furia_fase":
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.14), P.call(0.66, 0.42), P.call(0.72, 0.66), P.call(0.5, 0.84),
				P.call(0.28, 0.66), P.call(0.36, 0.44), P.call(0.44, 0.54)]), c)
		"postura_contra":
			draw_polyline(PackedVector2Array([P.call(0.3, 0.22), P.call(0.7, 0.22), P.call(0.7, 0.52), P.call(0.5, 0.8), P.call(0.3, 0.52), P.call(0.3, 0.22)]), c, w, true)
			draw_arc(P.call(0.5, 0.48), s * 0.12, -PI * 0.9, PI * 0.4, 10, c, w * 0.7, true)
		"embate_sismico":
			draw_line(P.call(0.14, 0.62), P.call(0.86, 0.62), c, w, true)
			for k in 5:
				var a := PI + PI * (k + 0.5) / 5.0
				draw_line(P.call(0.5, 0.62), P.call(0.5, 0.62) + Vector2(cos(a), sin(a)) * s * 0.3, Color(c, 0.85), w * 0.7, true)
			draw_rect(Rect2(P.call(0.42, 0.66), Vector2(0.16, 0.14) * s), Color(c, 0.6), true)
		"lanza_celeste":
			draw_rect(Rect2(P.call(0.42, 0.12), Vector2(0.16, 0.62) * s), Color(c, 0.3), true)
			draw_line(P.call(0.5, 0.14), P.call(0.5, 0.7), c, w * 1.1, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.66), P.call(0.58, 0.66), P.call(0.5, 0.84)]), c)
		_:
			draw_circle(P.call(0.5, 0.5), s * 0.16, c)

## Iconos del lote 2. Devuelve false si el id no es de este lote.
func _glyph_extra(ability_id: String, P: Callable, s: float, c: Color, w: float) -> bool:
	match ability_id:
		"cuerno_embiste":
			draw_polyline(PackedVector2Array([P.call(0.22, 0.72), P.call(0.42, 0.28), P.call(0.62, 0.48), P.call(0.84, 0.22)]), c, w * 1.2, true)
			draw_circle(P.call(0.84, 0.22), s * 0.05, c)
		"tajo_cruzado":
			draw_line(P.call(0.22, 0.28), P.call(0.78, 0.72), c, w, true)
			draw_line(P.call(0.22, 0.72), P.call(0.78, 0.28), c, w, true)
			draw_line(P.call(0.5, 0.5), P.call(0.86, 0.5), c, w * 1.2, true)
		"zarpazo_sangre":
			for y in [0.32, 0.5, 0.68]:
				draw_line(P.call(0.22, y + 0.08), P.call(0.58, y - 0.06), c, w, true)
			draw_arc(P.call(0.72, 0.55), s * 0.16, 0.0, TAU, 14, c, w * 0.7, true)
		"barrido_cola":
			draw_arc(P.call(0.5, 0.62), s * 0.32, PI * 0.15, PI * 0.85, 16, c, w * 1.3, true)
			draw_arc(P.call(0.5, 0.48), s * 0.28, PI * 1.15, PI * 1.85, 14, Color(c, 0.65), w, true)
		"daga_sagrada":
			draw_line(P.call(0.28, 0.72), P.call(0.48, 0.28), c, w, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.62, 0.22), P.call(0.78, 0.38), P.call(0.58, 0.42)]), c)
			draw_circle(P.call(0.7, 0.32), s * 0.04, Color(1, 1, 1, 0.85))
		"estocada_negra":
			draw_line(P.call(0.16, 0.5), P.call(0.78, 0.5), c, w * 1.5, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.72, 0.38), P.call(0.9, 0.5), P.call(0.72, 0.62)]), c)
		"flor_umbral":
			for k in 6:
				var a := TAU * k / 6.0
				var origin: Vector2 = P.call(0.5, 0.48)
				draw_line(origin, origin + Vector2(cos(a), sin(a)) * s * 0.28, c, w * 0.8, true)
			draw_circle(P.call(0.5, 0.48), s * 0.08, c)
		"presa_fauces":
			draw_arc(P.call(0.5, 0.42), s * 0.22, 0.15, PI - 0.15, 10, c, w, true)
			draw_arc(P.call(0.5, 0.62), s * 0.22, PI + 0.15, TAU - 0.15, 10, c, w, true)
			draw_line(P.call(0.38, 0.48), P.call(0.38, 0.58), c, w * 0.7, true)
			draw_line(P.call(0.62, 0.48), P.call(0.62, 0.58), c, w * 0.7, true)
		"giro_noble":
			draw_arc(P.call(0.48, 0.5), s * 0.26, 0.4, TAU - 0.2, 18, c, w, true)
			draw_circle(P.call(0.48, 0.5), s * 0.06, c)
		"danza_triple":
			for k in 3:
				draw_arc(P.call(0.28 + k * 0.16, 0.62), s * 0.22, -2.2, -0.4, 10, Color(c, 1.0 - k * 0.2), w, true)
		"alas_picado":
			draw_line(P.call(0.5, 0.22), P.call(0.18, 0.48), c, w, true)
			draw_line(P.call(0.5, 0.22), P.call(0.82, 0.48), c, w, true)
			draw_line(P.call(0.5, 0.22), P.call(0.5, 0.78), c, w * 1.2, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.4, 0.7), P.call(0.6, 0.7), P.call(0.5, 0.86)]), c)
		"garra_suelo":
			draw_line(P.call(0.2, 0.32), P.call(0.55, 0.55), c, w * 1.2, true)
			draw_line(P.call(0.18, 0.72), P.call(0.86, 0.72), c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.3, 0.72), P.call(0.42, 0.58), P.call(0.55, 0.72), P.call(0.7, 0.56), P.call(0.82, 0.72)]), c, w * 0.8, true)
		"vendaval_hacha":
			draw_arc(P.call(0.3, 0.55), s * 0.28, -1.1, 0.6, 12, c, w, true)
			draw_arc(P.call(0.42, 0.55), s * 0.28, -1.0, 0.7, 12, Color(c, 0.6), w * 0.8, true)
		"anillo_fuego":
			draw_arc(P.call(0.5, 0.5), s * 0.22, 0.0, TAU, 18, c, w, true)
			for k in 8:
				var a2 := TAU * k / 8.0
				var origin: Vector2 = P.call(0.5, 0.5)
				var p0 := origin + Vector2(cos(a2), sin(a2)) * s * 0.22
				draw_line(p0, p0 + Vector2(cos(a2), sin(a2)) * s * 0.12, c, w * 0.7, true)
		"pisoton":
			draw_rect(Rect2(P.call(0.32, 0.28), Vector2(0.36, 0.18) * s), c, true)
			draw_line(P.call(0.18, 0.68), P.call(0.82, 0.68), c, w * 1.3, true)
			draw_line(P.call(0.28, 0.78), P.call(0.72, 0.78), Color(c, 0.6), w, true)
		"lluvia_lanzas":
			for k in 3:
				var x := 0.28 + k * 0.18
				draw_line(P.call(x, 0.18), P.call(x, 0.62), c, w * 0.8, true)
				draw_colored_polygon(PackedVector2Array([P.call(x - 0.05, 0.58), P.call(x + 0.05, 0.58), P.call(x, 0.74)]), c)
		"flecha_grave":
			draw_arc(P.call(0.5, 0.58), s * 0.28, 0.0, TAU, 18, c, w, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.16), P.call(0.58, 0.16), P.call(0.5, 0.4)]), c)
		"lluvia_sangre":
			for m in [[0.3, 0.32], [0.52, 0.28], [0.72, 0.4], [0.4, 0.55], [0.64, 0.62]]:
				draw_circle(P.call(m[0], m[1]), s * 0.055, c)
			draw_line(P.call(0.2, 0.8), P.call(0.8, 0.8), Color(c, 0.55), w * 0.6, true)
		"columnas_rayo":
			for k in 3:
				var x2 := 0.28 + k * 0.2
				draw_rect(Rect2(P.call(x2 - 0.04, 0.16), Vector2(0.08, 0.62) * s), Color(c, 0.35), true)
				draw_line(P.call(x2, 0.14), P.call(x2, 0.8), c, w * 0.7, true)
		"saeta_oscura":
			draw_arc(P.call(0.4, 0.5), s * 0.26, -1.3, 1.1, 12, c, w * 1.4, true)
			draw_circle(P.call(0.72, 0.38), s * 0.05, c)
		"orbe_lunar":
			draw_arc(P.call(0.46, 0.5), s * 0.24, -1.2, 1.2, 16, c, w * 1.3, true)
			draw_circle(P.call(0.58, 0.5), s * 0.08, Color(c, 0.85))
		"aliento_rayo":
			draw_colored_polygon(PackedVector2Array([P.call(0.2, 0.5), P.call(0.86, 0.4), P.call(0.86, 0.6)]), Color(c, 0.85))
			draw_circle(P.call(0.22, 0.5), s * 0.06, c)
		"aliento_escarcha":
			draw_colored_polygon(PackedVector2Array([P.call(0.18, 0.5), P.call(0.78, 0.22), P.call(0.78, 0.78)]), Color(c, 0.75))
			draw_circle(P.call(0.2, 0.5), s * 0.06, c)
		"chorro_lava":
			draw_colored_polygon(PackedVector2Array([P.call(0.18, 0.42), P.call(0.84, 0.3), P.call(0.84, 0.7), P.call(0.18, 0.58)]), Color(c, 0.85))
		"grito_guerra":
			draw_arc(P.call(0.5, 0.58), s * 0.12, PI, TAU, 10, c, w, true)
			draw_arc(P.call(0.5, 0.58), s * 0.24, -2.4, -0.7, 10, Color(c, 0.8), w * 0.8, true)
			draw_arc(P.call(0.5, 0.58), s * 0.34, -2.2, -0.9, 10, Color(c, 0.5), w * 0.6, true)
		"guardia_reflejo":
			draw_polyline(PackedVector2Array([P.call(0.32, 0.24), P.call(0.68, 0.24), P.call(0.68, 0.55), P.call(0.5, 0.8), P.call(0.32, 0.55), P.call(0.32, 0.24)]), c, w, true)
			draw_line(P.call(0.4, 0.42), P.call(0.6, 0.42), c, w * 0.8, true)
			draw_line(P.call(0.5, 0.34), P.call(0.5, 0.52), c, w * 0.8, true)
		_:
			return false
	return true
