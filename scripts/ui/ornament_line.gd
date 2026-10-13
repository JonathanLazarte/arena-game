class_name OrnamentLine
extends Control
## Filo dorado horizontal que se desvanece en los extremos, con un cristal en el centro.

func _draw() -> void:
	var y := size.y * 0.5
	var cx := size.x * 0.5
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := 1.0 - absf(t0 - 0.5) * 2.0
		draw_line(Vector2(size.x * t0, y), Vector2(size.x * t1, y), Color(UIKit.ORANGE, a * 0.9), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 7), Vector2(cx + 5, y), Vector2(cx, y + 7), Vector2(cx - 5, y)]), Color(0.65, 0.88, 1.0))
