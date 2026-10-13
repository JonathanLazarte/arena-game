class_name CurrencyIcon
extends Control
## Iconos dibujados: "oro" = moneda con canto grabado y estrella; "gema" = cristal azul
## (los "Cristales"); "star" se conserva por compatibilidad.

@export var kind: String = "oro"
@export var filled: bool = true

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	match kind:
		"oro":
			draw_circle(c, r, Color(0.55, 0.42, 0.18))
			draw_circle(c, r * 0.9, Color(0.86, 0.72, 0.42))
			draw_arc(c, r * 0.72, 0, TAU, 32, Color(0.55, 0.42, 0.18), 1.0, true)
			_star(c, r * 0.45, Color(0.98, 0.9, 0.65))
			draw_arc(c, r * 0.9, PI * 1.1, PI * 1.6, 12, Color(1, 1, 1, 0.6), 1.2, true)
		"gema":
			var top := c + Vector2(0, -r)
			var bot := c + Vector2(0, r)
			var l := c + Vector2(-r * 0.55, -r * 0.2)
			var rr := c + Vector2(r * 0.55, -r * 0.2)
			var l2 := c + Vector2(-r * 0.55, r * 0.35)
			var r2 := c + Vector2(r * 0.55, r * 0.35)
			draw_circle(c, r * 1.05, Color(0.4, 0.7, 1.0, 0.18))
			draw_colored_polygon(PackedVector2Array([top, rr, r2, bot, l2, l]), Color(0.3, 0.6, 1.0))
			draw_colored_polygon(PackedVector2Array([top, c + Vector2(0, r * 0.1), l2, l]), Color(0.65, 0.88, 1.0))
			draw_colored_polygon(PackedVector2Array([top, rr, c + Vector2(0, -r * 0.1)]), Color(0.9, 0.97, 1.0))
			draw_polyline(PackedVector2Array([top, rr, r2, bot, l2, l, top]), Color(0.85, 0.92, 1.0, 0.8), 1.0, true)
		"star":
			_star(c, r, Color(0.95, 0.86, 0.6) if filled else Color(0.2, 0.28, 0.45))

func _star(c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for i in 8:
		var a := -PI / 2 + i * PI / 4
		p.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.35))
	draw_colored_polygon(p, col)
