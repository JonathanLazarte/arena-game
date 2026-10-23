class_name SimWorld
extends RefCounted
## Fase 8: dibuja lo que la sim tiene fuera de los Fighter: eikons compañeros y monturas (nodos
## Eikon/Mount en modo títere, sin lógica), marcas de suelo y ondas (HZ_*) y proyectiles (PR_*).
## Solo lee el estado; nunca escribe en la simulación.
const S = preload("res://net/sim/fight_sim.gd")
var fighters: Array[Fighter] = []
var parent: Node3D
var _pets: Array = [null, null]
var _pet_cd: Array[int] = [0, 0]
var fx: SimAbilityFx ## fase 9: efectos de habilidades, marcas, ondas y proyectiles

func _init(a: Fighter, b: Fighter, p: Node3D) -> void:
	fighters = [a, b]
	parent = p
	fx = SimAbilityFx.new(a, b, p)

func apply(s: PackedInt64Array, P: Array) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in 2:
		_apply_pet(s, P, i)
	fx.apply(s, P)

func clear() -> void:
	for i in 2:
		_free_pet(i)

func _free_pet(i: int) -> void:
	var f := fighters[i]
	if f.mounted:
		f.mounted = false
		f.mount_node = null
		f._apply_mount_visuals()
		f.mount_changed.emit(false)
	if is_instance_valid(_pets[i]):
		(_pets[i] as Node).queue_free()
	_pets[i] = null
	f.active_eikon = null

func _apply_pet(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * S.F_FIELDS
	var f := fighters[i]
	var ek: Dictionary = P[i].get("ek", {})
	if s[o + S.EK_T] <= 0 or ek.is_empty() or f.eikon == null:
		if _pets[i] != null:
			_free_pet(i)
		return
	# dismiss_eikon (fin de ronda) libera el nodo en el mismo apply que lo dibujó. No revivirlo.
	if is_instance_valid(_pets[i]) and (_pets[i] as Node).is_queued_for_deletion():
		_pets[i] = null
		f.active_eikon = null
		if f.mounted:
			f.mounted = false
			f.mount_node = null
			f._apply_mount_visuals()
			f.mount_changed.emit(false)
		return
	var ride := int(ek.get("ride", 0)) != 0 and f.eikon.rideable and f.eikon.ride != null
	if _pets[i] == null or not is_instance_valid(_pets[i]):
		if ride:
			var m := Mount.new()
			m.data = f.eikon.ride
			m.eikon = f.eikon
			m.owner_fighter = f
			m.life = s[o + S.EK_T] / 60.0
			m.puppet = true
			parent.add_child(m)
			_pets[i] = m
		else:
			var e := Eikon.new()
			e.data = f.eikon
			e.team = f.team
			e.owner_fighter = f
			e.preview = true
			parent.add_child(e)
			_pets[i] = e
		_pet_cd[i] = s[o + S.EK_CD]
		f.active_eikon = _pets[i]
		var au := f.get_node_or_null("/root/Audio")
		if au:
			au.sfx3d("eikon_summon", f.global_position)
	var n: Node3D = _pets[i]
	var mounted := false
	if n is Mount:
		var m: Mount = n
		m.life = s[o + S.EK_T] / 60.0
		m.special_cd = s[o + S.EK_SPC] / 60.0
		var x := s[o + S.EK_X] / 1.0e6
		var z := s[o + S.EK_Z] / 1.0e6
		m.global_position = Vector3(x, m.data.hover if m.data else 0.0, z)
		var to := MeshUtil.flat(fighters[1 - i].global_position - m.global_position)
		if to.length() > 0.1:
			m.rotation.y = atan2(-to.x, -to.z)
		if f.mounted:
			f.mounted = false
			f.mount_node = null
			m.rider = null
			f._apply_mount_visuals()
			f.mount_changed.emit(false)
	else:
		var e: Eikon = n
		e.life = s[o + S.EK_T] / 60.0
		var y := 2.5 if e.data.flying else 0.0
		e.global_position = Vector3(s[o + S.EK_X] / 1.0e6, y, s[o + S.EK_Z] / 1.0e6)
		var to2 := MeshUtil.flat(fighters[1 - i].global_position - e.global_position)
		if to2.length() > 0.1:
			e.rotation.y = atan2(-to2.x, -to2.z)
		e._update_anim(1.0 / 60.0, false)
		if s[o + S.EK_CD] > _pet_cd[i] + 1 and e._ap and e._anims.size() > 2:
			e._ap.play(e._anims[2], 0.1) # ataque: la recarga se reinició
			e._attack_anim_t = 0.5
	_pet_cd[i] = s[o + S.EK_CD]
