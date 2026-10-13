class_name MenuCursor
extends Control
## Cursor de menú: punta de cristal plateada que apunta al elemento seleccionado y oscila apenas.

var _t: float = 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var dx := sin(_t * 4.0) * 2.0
	var h := size.y
	var pts := PackedVector2Array([Vector2(dx, 2), Vector2(dx + size.x, h * 0.5), Vector2(dx, h - 2), Vector2(dx + size.x * 0.3, h * 0.5)])
	draw_colored_polygon(pts, Color(0.92, 0.96, 1.0))
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[3]]), Color(0.7, 0.85, 1.0))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.35, 0.7), 1.2, true)
