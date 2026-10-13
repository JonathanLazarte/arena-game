class_name NotifyDot
extends Control
## Indicador de novedad: cristal azul que late con un halo suave.

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var k := 0.75 + sin(_t * 3.0) * 0.25
	draw_circle(c, 9.0, Color(0.4, 0.7, 1.0, 0.25 * k))
	var w := 5.0
	var h := 9.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, 0), c + Vector2(0, h), c + Vector2(-w, 0)]), Color(0.55, 0.85, 1.0, 0.7 + 0.3 * k))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, 0), c + Vector2(0, 0)]), Color(0.9, 0.97, 1.0, 0.9))
