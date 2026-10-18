extends SceneTree
## Strafe corriendo: el clip lateral avanza de forma continua (sin reinicios) aunque la
## velocidad y la mirada tiemblen, y cada clip aparece una sola vez en el BlendSpace2D.
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("ok   " if c else "FAIL ") + msg)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _clip_of(n: AnimationNode) -> String:
	if n is AnimationNodeAnimation:
		return String((n as AnimationNodeAnimation).animation)
	if n is AnimationNodeBlendTree:
		return _clip_of((n as AnimationNodeBlendTree).get_node("anim"))
	return ""

func _run() -> void:
	var f := Fighter.new()
	root.add_child(f)
	await process_frame
	var kv: KnightVisual = f._kv
	var loco := (kv.tree.tree_root as AnimationNodeBlendTree).get_node("loco") as AnimationNodeBlendSpace2D
	var seen := {}
	var dup := ""
	for k in loco.get_blend_point_count():
		var c := _clip_of(loco.get_blend_point_node(k))
		if seen.has(c):
			dup = c
		seen[c] = true
	check(dup == "", "cada clip una sola vez en la locomoción (repetido: '%s')" % dup)
	check(loco.sync, "loco.sync: los clips sin peso no se congelan")
	var sp := f.stats().speed
	for side: float in [1.0, -1.0]:
		var nm := "Run_Strafe_L" if side > 0.0 else "Run_Strafe_R"
		var path := "parameters/loco/%s/anim/current_position" % nm
		var lpath := path.replace("current_position", "current_length")
		var last := -1.0
		var resets := 0
		var adv := 0.0
		for k in 300:
			# ruido de la vista online: velocidad con algo de avance/retroceso y mirada que oscila
			var a := 0.05 * sin(k * 1.3)
			f.facing = Vector3(sin(a), 0, cos(a))
			f.planar_vel = Vector3(side * 1.3 * sp, 0, (0.12 * sin(k * 2.1) + (0.4 if k % 37 == 0 else 0.0)) * sp)
			kv.update(f, 1.0 / 60.0)
			await physics_frame
			var p := float(kv.tree.get(path))
			var L := float(kv.tree.get(lpath))
			if k > 20 and last >= 0.0:
				var d := p - last
				if d < 0.0:
					d += L
					if last < L - 0.15 or p > 0.15:
						resets += 1
				adv += d
			last = p
		check(resets == 0, "%s: sin reinicios a mitad del ciclo (%d)" % [nm, resets])
		check(adv > 2.0, "%s: el clip avanza (%.2f s de clip en 280 cuadros)" % [nm, adv])
	print("FALLÓ %d" % fails if fails > 0 else "TODO OK")
	quit(1 if fails > 0 else 0)
