extends CanvasLayer
## Autoload "Fade": fundido a negro entre escenas.

var rect: ColorRect
var busy: bool = false

func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.color = Color(0.01, 0.02, 0.07, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.size = Vector2(1280, 720)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

func go(path: String, t: float = 0.3) -> void:
	if busy:
		return
	busy = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, t)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(rect, "color:a", 0.0, t)
	await tw2.finished
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
