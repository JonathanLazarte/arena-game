class_name MeshUtil
## Utilidades para crear arte de placeholder con primitivas.

## Ronda 26: materiales compartidos por (color, emisivo). ¡No modificar el devuelto!
## Quien vaya a cambiarlo debe usar own() (copia propia).
static var _mats: Dictionary = {}
static func mat(c: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := Vector2i(c.to_rgba32(), int(emissive))
	var cached: StandardMaterial3D = _mats.get(key)
	if cached:
		return cached
	var m := _new_mat(c, emissive)
	_mats[key] = m
	return m

## Copia propia del material de `mi` (para modificarlo sin tocar a los demás).
static func own(mi: GeometryInstance3D) -> StandardMaterial3D:
	var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mi.material_override = m
	return m

static func _new_mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, r: float, pos: Vector3, c: Color, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat(c, emissive)
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node3D, r: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

## Objetivos dañables enemigos (luchadores, eikons y, en el futuro, mobs).
static func enemies_of(tree: SceneTree, team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in tree.get_nodes_in_group("damageable"):
		if n is Node3D and n.team != team and n.alive:
			out.append(n)
	return out

## Ronda 16: objetivo de un eikon compañero: prioriza eikons enemigos (compañeros o monturas de
## eikon sin jinete); si no hay, el más cercano (normalmente el luchador rival).
static func companion_target(from: Vector3, tree: SceneTree, team: int) -> Node3D:
	var all := enemies_of(tree, team)
	var eik: Array[Node3D] = []
	for n in all:
		if n.is_in_group("eikon") or n.is_in_group("eikon_mount"):
			eik.append(n)
	return nearest(from, eik) if not eik.is_empty() else nearest(from, all)

static func nearest(from: Vector3, list: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in list:
		var d := from.distance_squared_to(n.global_position)
		if d < bd:
			bd = d
			best = n
	return best

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

## Abanico plano (arco de espada) centrado en -Z, de radio r y semiángulo half (rad).
static func arc(parent: Node3D, r_in: float, r_out: float, half: float, y: float, c: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var a0 := -half + 2.0 * half * i / n
		var a1 := -half + 2.0 * half * (i + 1) / n
		var p0 := Vector3(-sin(a0), 0, -cos(a0))
		var p1 := Vector3(-sin(a1), 0, -cos(a1))
		st.add_vertex(p0 * r_in + Vector3(0, y, 0))
		st.add_vertex(p0 * r_out + Vector3(0, y, 0))
		st.add_vertex(p1 * r_out + Vector3(0, y, 0))
		st.add_vertex(p0 * r_in + Vector3(0, y, 0))
		st.add_vertex(p1 * r_out + Vector3(0, y, 0))
		st.add_vertex(p1 * r_in + Vector3(0, y, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
