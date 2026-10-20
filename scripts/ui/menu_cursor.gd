class_name MenuCursor
extends Control
## Cursor de menú: chevron rúnico dorado que apunta al elemento seleccionado y oscila suavemente.

var _t: float = 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var dx := sin(_t * 3.5) * 1.5
	var h := size.y
	var pts := PackedVector2Array([Vector2(dx, 2), Vector2(dx + size.x, h * 0.5), Vector2(dx, h - 2), Vector2(dx + size.x * 0.35, h * 0.5)])
	draw_colored_polygon(pts, Color(UIKit.YELLOW, 0.95))
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[3]]), Color(UIKit.ORANGE, 0.9))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.15, 0.05, 0.9), 1.0, true)
