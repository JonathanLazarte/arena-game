class_name AnimUtil
## Utilidades para modelos glTF importados (CC0): bucles, tintes y medidas.

static func set_loops(ap: AnimationPlayer, names: Array) -> void:
	for n: String in names:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR

static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out

## Recolorea cada superficie mezclando su color original con `c` (factor k).
static func tint_surfaces(root: Node, c: Color, k: float, emissive: float = 0.0) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for mi in meshes(root):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var m: StandardMaterial3D
			if src is StandardMaterial3D:
				m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.albedo_color = m.albedo_color.lerp(c, k)
			if emissive > 0.0:
				m.emission_enabled = true
				m.emission = m.albedo_color
				m.emission_energy_multiplier = emissive
			mi.set_surface_override_material(s, m)
			out.append(m)
	return out

static func anim_node(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a

## Animación con TimeScale en un BlendTree (para ajustar su duración por código).
static func scaled_anim(name: String) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("anim", anim_node(name))
	bt.add_node("ts", AnimationNodeTimeScale.new())
	bt.connect_node("ts", 0, "anim")
	bt.connect_node("output", 0, "ts")
	return bt
