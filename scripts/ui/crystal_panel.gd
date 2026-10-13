class_name CrystalPanel
extends PanelContainer
## Panel con degradado vertical suave, línea interior dorada fina y cristales en las esquinas.

static var _grad: GradientTexture2D

func _ready() -> void:
	resized.connect(queue_redraw)
	if _grad == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.25, 0.4, 0.8, 0.16))
		g.set_color(1, Color(0.0, 0.0, 0.05, 0.0))
		_grad = GradientTexture2D.new()
		_grad.gradient = g
		_grad.fill_from = Vector2(0, 0)
		_grad.fill_to = Vector2(0, 1)
		_grad.width = 4
		_grad.height = 64

func _draw() -> void:
	draw_texture_rect(_grad, Rect2(Vector2(2, 2), size - Vector2(4, 4)), false)
	var r := Rect2(Vector2.ZERO, size).grow(-5)
	draw_rect(r, Color(UIKit.ORANGE, 0.35), false, 1.0)
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var d := 5.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d * 1.4), c + Vector2(d, 0), c + Vector2(0, d * 1.4), c + Vector2(-d, 0)]), Color(0.6, 0.85, 1.0, 0.9))
