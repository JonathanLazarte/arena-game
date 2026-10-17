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
var _hz: Array[MeshInstance3D] = []
var _hz_fill: Array[MeshInstance3D] = []
var _pr: Array[MeshInstance3D] = []

func _init(a: Fighter, b: Fighter, p: Node3D) -> void:
	fighters = [a, b]
	parent = p

func apply(s: PackedInt64Array, P: Array) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in 2:
		_apply_pet(s, P, i)
	_apply_hazards(s)
	_apply_projectiles(s)

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
	var mounted := s[o + S.MOUNTED] != 0
	if n is Mount:
		var m: Mount = n
		m.life = s[o + S.EK_T] / 60.0
		m.special_cd = s[o + S.EK_SPC] / 60.0
		var x := (s[o + S.X] if mounted else s[o + S.EK_X]) / 1.0e6
		var z := (s[o + S.Z] if mounted else s[o + S.EK_Z]) / 1.0e6
		m.global_position = Vector3(x, m.data.hover if m.data else 0.0, z)
		if mounted:
			m.rotation.y = atan2(-f.facing.x, -f.facing.z)
		else:
			var to := MeshUtil.flat(fighters[1 - i].global_position - m.global_position)
			if to.length() > 0.1:
				m.rotation.y = atan2(-to.x, -to.z)
		if mounted != f.mounted:
			f.mounted = mounted
			f.mount_node = m if mounted else null
			m.rider = f if mounted else null
			f._apply_mount_visuals()
			f.mount_changed.emit(mounted)
		f.mount_stance = s[o + S.MSTANCE] / 1000.0
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

static func _disc(parent_n: Node3D, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.04
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	parent_n.add_child(mi)
	return mi

func _apply_hazards(s: PackedInt64Array) -> void:
	while _hz.size() < S.HZ_MAX:
		_hz.append(_disc(parent, Color(1.0, 0.25, 0.1, 0.28)))
		_hz_fill.append(_disc(parent, Color(1.0, 0.45, 0.1, 0.5)))
	for j in S.HZ_MAX:
		var q := S.HZ_BASE + j * S.HZ_FIELDS
		var ring := _hz[j]
		var fill := _hz_fill[j]
		var on := s[q + S.HZ_ON] != 0
		ring.visible = on
		fill.visible = on
		if not on:
			continue
		var pos := Vector3(s[q + S.HZ_X] / 1.0e6, 0.05, s[q + S.HZ_Z] / 1.0e6)
		if s[q + S.HZ_TYPE] == 1:
			var r := maxf(s[q + S.HZ_R] / 1.0e6, 0.1)
			ring.global_position = pos
			ring.scale = Vector3(r, 1.0, r)
			ring.rotation = Vector3.ZERO
			var k := clampf(float(s[q + S.HZ_T]) / maxf(s[q + S.HZ_WARN], 1.0), 0.0, 1.0)
			if s[q + S.HZ_DONE] != 0:
				k = 1.0
				(fill.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.85, 0.4, 0.7)
			else:
				(fill.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.45, 0.1, 0.5)
			fill.global_position = pos + Vector3(0, 0.01, 0)
			fill.scale = Vector3(r * k, 1.0, r * k)
			fill.rotation = Vector3.ZERO
		else:
			# onda rastrera: franja que avanza (ancho HZ_W)
			var w := maxf(s[q + S.HZ_W] / 1.0e6, 0.5)
			var dir := Vector3(s[q + S.HZ_DX], 0, s[q + S.HZ_DZ]) / float(FxMath.ONE)
			ring.global_position = pos
			ring.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
			ring.scale = Vector3(w * 0.5, 6.0, 0.6)
			fill.visible = false

func _apply_projectiles(s: PackedInt64Array) -> void:
	while _pr.size() < S.PROJ_MAX:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		mi.material_override = m
		mi.visible = false
		parent.add_child(mi)
		_pr.append(mi)
	for j in S.PROJ_MAX:
		var q := S.PROJ_BASE + j * S.PR_FIELDS
		var mi := _pr[j]
		# las flechas (kind 0) las dibuja SimView; aquí tajos, hechizos y ataques de eikon
		mi.visible = s[q + S.PR_ON] != 0 and s[q + S.PR_KIND] != 0
		if not mi.visible:
			continue
		var r := clampf(s[q + S.PR_R] / 1.0e6, 0.15, 1.2)
		mi.global_position = Vector3(s[q + S.PR_X], s[q + S.PR_Y], s[q + S.PR_Z]) / 1.0e6
		mi.scale = Vector3.ONE * r
		var c := Color(0.6, 0.85, 1.0)
		match int(s[q + S.PR_KIND]):
			1: c = Color(0.85, 0.5, 1.0)
			2: c = Color(1.0, 0.55, 0.2)
			3: c = Color(1.0, 0.3, 0.1)
		var m: StandardMaterial3D = mi.material_override
		m.albedo_color = c
		m.emission = c
