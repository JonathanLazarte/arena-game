class_name NotifyDot
extends Control
## Punto rojo de notificación (late suavemente).

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var r := 8.0 + sin(_t * 5.0) * 0.8
	draw_circle(size * 0.5, r + 2.0, Color.WHITE)
	draw_circle(size * 0.5, r, Color(0.95, 0.15, 0.2))
