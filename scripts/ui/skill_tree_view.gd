class_name SkillTreeView
extends Control
## Árbol de habilidades de un rol: nodos (botones) por niveles unidos con líneas.

signal node_pressed(skill_id: String)

var nodes: Dictionary = {} ## id -> Button
var _links: Array = [] ## [id_req, id]

func build(char_id: String, learned: Array, points: int) -> void:
	for c in get_children():
		c.queue_free()
	nodes.clear()
	_links.clear()
	var tree := Progression.tree(char_id)
	var depth := {}
	var rows: Dictionary = {}
	for s: Dictionary in tree:
		var d: int = 0 if s["req"] == "" else int(depth.get(s["req"], 0)) + 1
		depth[s["id"]] = d
		if not rows.has(d):
			rows[d] = []
		rows[d].append(s)
	var w := size.x if size.x > 0 else 380.0
	for d: int in rows:
		var row: Array = rows[d]
		for i in row.size():
			var s: Dictionary = row[i]
			var b := UIKit.button(s["name"], 15)
			b.name = "Skill_" + s["id"]
			b.custom_minimum_size = Vector2(178, 50)
			b.size = Vector2(178, 50)
			b.clip_text = true
			var x := (w - 178) * 0.5 if row.size() == 1 else 4.0 + (w - 186) * i / float(row.size() - 1)
			if d >= 2 and row.size() == 1 and nodes.has(s["req"]):
				x = (nodes[s["req"]] as Button).position.x # debajo de su requisito
			b.position = Vector2(x, 10 + d * 82)
			var have: bool = s["id"] in learned
			var avail: bool = not have and (s["req"] == "" or s["req"] in learned)
			if have:
				UIKit.button_styles(b, UIKit.ORANGE, 25)
				b.text = s["name"]
			elif avail:
				UIKit.button_styles(b, UIKit.GREEN if points >= int(s["cost"]) else UIKit.BLUE, 25)
				b.text = "%s (%d)" % [s["name"], s["cost"]]
				if points < int(s["cost"]):
					b.add_theme_color_override("font_color", UIKit.MUTED)
			else:
				UIKit.button_styles(b, Color(0.3, 0.36, 0.48), 4)
				b.add_theme_color_override("font_color", UIKit.MUTED)
			b.pressed.connect(func() -> void: node_pressed.emit(s["id"]))
			add_child(b)
			nodes[s["id"]] = b
			UIKit.pop_in(b, 0.06 * nodes.size(), 0.5)
			if s["req"] != "":
				_links.append([s["req"], s["id"]])
	queue_redraw()

func _draw() -> void:
	for l: Array in _links:
		if not nodes.has(l[0]) or not nodes.has(l[1]):
			continue
		var a: Button = nodes[l[0]]
		var b: Button = nodes[l[1]]
		var pa := a.position + Vector2(89, 50)
		var pb := b.position + Vector2(89, 0)
		draw_line(pa, pb, Color(UIKit.ORANGE, 0.7), 1.5, true)
		draw_colored_polygon(PackedVector2Array([pb + Vector2(0, -6), pb + Vector2(4, 0), pb + Vector2(0, 6), pb + Vector2(-4, 0)]), UIKit.CYAN)
