class_name CurrencyIcon
extends Control
## Icono dibujado: "oro" = moneda dorada; "gema" = gema azul; "star" = estrella.

@export var kind: String = "oro"
@export var filled: bool = true

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	match kind:
		"oro":
			draw_circle(c + Vector2(0, 2), r, Color(0.55, 0.3, 0.0))
			draw_circle(c, r, Color(1.0, 0.78, 0.1))
			draw_circle(c, r * 0.72, Color(1.0, 0.88, 0.35))
			draw_arc(c, r * 0.72, 0, TAU, 24, Color(0.85, 0.55, 0.0), maxf(r * 0.12, 1.0))
			draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.38), Vector2(r * 0.24, r * 0.76)), Color(0.85, 0.55, 0.0))
			draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.15, Color(1, 1, 1, 0.8))
		"gema":
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.25), c + Vector2(0, r), c + Vector2(-r * 0.85, -r * 0.25)])
			draw_colored_polygon(pts, Color(0.2, 0.75, 1.0))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.25), c + Vector2(0, -r * 0.1), c + Vector2(-r * 0.85, -r * 0.25)]), Color(0.65, 0.95, 1.0))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.3, 0.6), maxf(r * 0.1, 1.0))
		"star":
			var p := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				p.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			draw_colored_polygon(p, Color(1.0, 0.82, 0.1) if filled else Color(0.15, 0.25, 0.45))
			p.append(p[0])
			draw_polyline(p, Color(0.55, 0.3, 0.0) if filled else Color(0.4, 0.55, 0.8), maxf(r * 0.08, 1.5))
