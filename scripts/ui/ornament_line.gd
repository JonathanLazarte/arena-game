class_name OrnamentLine
extends Control
## Filo dorado horizontal que se desvanece en los extremos, con un motivo rúnico central.

func _draw() -> void:
	var y := size.y * 0.5
	var cx := size.x * 0.5
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := 1.0 - absf(t0 - 0.5) * 2.0
		draw_line(Vector2(size.x * t0, y), Vector2(size.x * t1, y), Color(UIKit.ORANGE, a * 0.9), 1.0)
	var pts := PackedVector2Array([Vector2(cx, y - 6), Vector2(cx + 5, y), Vector2(cx, y + 6), Vector2(cx - 5, y)])
	draw_colored_polygon(pts, Color(UIKit.YELLOW, 0.95))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(UIKit.ORANGE, 0.9), 1.0)
	draw_circle(Vector2(cx, y), 1.5, Color(1.0, 0.95, 0.85))
