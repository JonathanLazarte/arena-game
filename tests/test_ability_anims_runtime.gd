extends SceneTree
## Para cada personaje jugable (Catalog.characters(), con su arma por defecto): toda habilidad con
## entrada en data/animations/ability_anims.json resuelve a una animación existente en el
## AnimationPlayer de ESE personaje, y al lanzarla por la sim real (SimMatch → SimView) la vista
## entra en los estados ab0/ab1 con ese clip y la pose se mueve (no se queda en reposo).
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("ok   " if c else "FAIL ") + msg)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _hand_pos(kv: KnightVisual) -> Vector3:
	var sk := kv.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var i := sk.find_bone("hand.r")
	return sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO

func _run() -> void:
	var ids: Array = AbilityAnims.all_ids()
	check(ids.size() >= 2, "hay habilidades con animación propia: %s" % [ids])
	var chars := Catalog.characters()
	check(chars.size() >= 5, "personajes jugables: %d" % chars.size())
	for ci in chars.size():
		var cd: CharacterDef = chars[ci]
		for id: String in ids:
			var world := Node3D.new()
			root.add_child(world)
			var A := Fighter.new()
			A.eikon = load(Catalog.EIKONS["fenix"])
			A.character = cd
			A.set_boss_abilities([id])
			world.add_child(A)
			var B := Fighter.new()
			B.eikon = load(Catalog.EIKONS["lobo"])
			world.add_child(B)
			await process_frame
			var kv: KnightVisual = A._kv
			# 1) resolución estática: cada tramo → animación existente en este AnimationPlayer
			var missing: Array = []
			for seg: Dictionary in AbilityAnims.segments(id):
				var nm := AbilityAnims.clip_name(seg)
				if not kv.ap.has_animation(nm) and not kv.ap.has_animation(String(seg.get("fallback", ""))):
					missing.append(nm)
			check(missing.is_empty(), "%s/%s: todos los clips existen en su AnimationPlayer %s" % [cd.id, id, missing])
			# 2) en marcha por la sim real
			var P := SimParams.bake(A, B)
			var e := FightEngine.new(P, 3, true)
			e.gap_um = 5000000
			var s := e.initial()
			var view := SimView.new(A, B, world)
			view.params = P
			var fired := false
			var ab_frames := 0
			var clips := {}
			var p0 := Vector3.ZERO
			var moved := 0.0
			for t in 260:
				e.step(s, FightSim.IN_LOCK | (FightSim.IN_BOSS if t == 20 else 0), FightSim.IN_LOCK)
				view.apply(s)
				await physics_frame
				if t == 19:
					p0 = _hand_pos(kv)
				if A.ab_id == id:
					fired = true
					if kv.state in KnightVisual.AB_STATES:
						ab_frames += 1
						clips[String(kv._ab_smp.get("clip", ""))] = true
						moved = maxf(moved, _hand_pos(kv).distance_to(p0))
			check(fired, "%s/%s: la sim lanza la habilidad" % [cd.id, id])
			check(ab_frames > 20, "%s/%s: la vista usa los estados de habilidad (%d cuadros, clips %s)" % [cd.id, id, ab_frames, clips.keys()])
			check(moved > 0.05, "%s/%s: la pose se mueve respecto al reposo (mano %.2f m)" % [cd.id, id, moved])
			world.queue_free()
			await process_frame
	print("FALLÓ %d" % fails if fails > 0 else "TODO OK")
	quit(1 if fails > 0 else 0)
