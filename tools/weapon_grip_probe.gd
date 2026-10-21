extends SceneTree
## Ayuda para ajustar offsets: imprime AABB, origen y una sugerencia de grip de una malla de arma.
##   godot --headless --path . --script res://tools/weapon_grip_probe.gd -- <weapon_id | res://ruta.glb> [nodo]
## Supone que el arma es alargada: el eje más largo es la hoja/asta y la empuñadura está en el
## extremo «más angosto» (el de menos volumen). Es solo una sugerencia: revisá en el editor.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("uso: ... -- <weapon_id | res://arma.glb> [mesh_node]")
		quit(2)
		return
	var e: Dictionary = {}
	if args[0].begins_with("res://"):
		e = {"mesh": args[0], "mesh_node": args[1] if args.size() > 1 else ""}
	else:
		e = WeaponAttacher.entry(args[0])
	var n := WeaponAttacher.instance_mesh(e)
	if n == null:
		print("FALLÓ: no se pudo instanciar la malla de %s" % args[0])
		quit(1)
		return
	var aabb := _aabb(n, Transform3D.IDENTITY)
	var sz := aabb.size
	var ax := 0 if sz.x >= sz.y and sz.x >= sz.z else (1 if sz.y >= sz.z else 2)
	var names := ["X", "Y", "Z"]
	var lo := aabb.position[ax]
	var hi := aabb.end[ax]
	# extremo con menos vértices cerca = empuñadura (heurística por el ancho de los vértices)
	var w_lo := _width_near(n, ax, lo, (hi - lo) * 0.15)
	var w_hi := _width_near(n, ax, hi, (hi - lo) * 0.15)
	var grip_t := lo + (hi - lo) * 0.08 if w_lo <= w_hi else hi - (hi - lo) * 0.08
	var grip := aabb.get_center()
	grip[ax] = grip_t
	print("AABB pos=%s size=%s centro=%s" % [aabb.position, sz, aabb.get_center()])
	print("Origen (0,0,0) %s del AABB" % ("dentro" if aabb.grow(0.001).has_point(Vector3.ZERO) else "FUERA"))
	print("Eje largo: %s (%.3f). Empuñadura probable cerca de %s" % [names[ax], hi - lo, grip])
	print("Sugerencia offset.position (lleva la empuñadura al hueso): %s" % [_arr(-grip)])
	if ax != 1:
		print("Sugerencia rotation_degrees para dejar la hoja en +Y: %s" % [_arr(Vector3(0, 0, -90) if ax == 0 else Vector3(90, 0, 0))])
	n.free()
	quit(0)

func _arr(v: Vector3) -> String:
	return "[%.3f, %.3f, %.3f]" % [v.x, v.y, v.z]

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var t := xf * (n as Node3D).transform if n is Node3D else xf
	var out := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb(c, t)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out

func _width_near(n: Node, ax: int, at: float, band: float) -> float:
	var mi := WeaponAttacher.first_mesh(n)
	if mi == null or mi.mesh == null:
		return 0.0
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for s in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if absf(v[ax] - at) <= band:
				lo = lo.min(v)
				hi = hi.max(v)
	if lo == Vector3.INF:
		return 0.0
	var d := hi - lo
	d[ax] = 0
	return d.length()
