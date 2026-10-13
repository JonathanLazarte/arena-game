class_name OrnatePanel
extends PanelContainer
## Panel con marco interior y adornos de esquina (rombos y volutas) dibujados a mano.

@export var ornament: Color = DarkUI.GOLD

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var inner := r.grow(-6)
	var c := Color(ornament, 0.55)
	draw_rect(inner, c, false, 1.0)
	for corner: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		var d := 7.0
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -d), corner + Vector2(d, 0), corner + Vector2(0, d), corner + Vector2(-d, 0)]), ornament)
		draw_line(corner + Vector2(sx * 10, 0), corner + Vector2(sx * 34, 0), ornament, 2.0)
		draw_line(corner + Vector2(0, sy * 10), corner + Vector2(0, sy * 34), ornament, 2.0)
		draw_arc(corner + Vector2(sx * 18, sy * 18), 8.0, 0.0, TAU, 12, Color(ornament, 0.35), 1.0)
	# Remate central superior
	var top := Vector2(size.x * 0.5, inner.position.y)
	draw_colored_polygon(PackedVector2Array([top + Vector2(-12, 0), top + Vector2(0, -6), top + Vector2(12, 0), top + Vector2(0, 6)]), DarkUI.BLOOD)
	draw_line(top + Vector2(-60, 0), top + Vector2(-16, 0), ornament, 1.5)
	draw_line(top + Vector2(16, 0), top + Vector2(60, 0), ornament, 1.5)
