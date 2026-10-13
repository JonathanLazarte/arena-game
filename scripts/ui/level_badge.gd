class_name LevelBadge
extends Control
## Insignia de nivel: anillo plateado con filo dorado, "Nv" y el número en Cinzel.

var level: int = 1

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, Color(0.02, 0.05, 0.15, 0.85))
	draw_arc(c, r - 1.0, 0, TAU, 40, Color(UIKit.ORANGE, 0.9), 1.5, true)
	draw_arc(c, r - 4.0, 0, TAU, 40, Color(UIKit.SILVER, 0.45), 1.0, true)
	var f := UIKit.display_font()
	var txt := str(level)
	var fs := int(r * 0.85)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, c + Vector2(-w * 0.5, fs * 0.55), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.YELLOW)
	var sf := UIKit.body_font()
	var sw := sf.get_string_size("NV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(sf, c + Vector2(-sw * 0.5, -r * 0.35), "NV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIKit.MUTED)
