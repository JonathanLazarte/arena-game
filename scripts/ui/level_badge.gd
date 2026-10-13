class_name LevelBadge
extends Control
## Insignia de nivel: hexágono naranja con borde blanco y el número.

var level: int = 1

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6 + i * TAU / 6
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color.WHITE)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.84)
	draw_colored_polygon(inner, UIKit.ORANGE)
	draw_colored_polygon(PackedVector2Array([inner[4], inner[5], c + Vector2(r * 0.7, -r * 0.05), c + Vector2(-r * 0.7, -r * 0.05)]), Color(1, 1, 1, 0.2))
	var f := UIKit.display_font()
	var txt := str(level)
	var fs := int(r * 0.95)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string_outline(f, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UIKit.OUTLINE)
	draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
