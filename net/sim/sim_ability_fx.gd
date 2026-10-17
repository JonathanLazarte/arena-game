class_name SimAbilityFx
extends RefCounted
## Fase 9: efectos de las habilidades (los visuales completos del offline antiguo) dibujados a
## partir del ESTADO de la sim: brillo del arma por habilidad, aura de partículas de la estocada,
## burbuja del escudo de maná, desaparición del paso espectral, rastro de espada en los golpes de
## timeline, aliento de fuego, aura de furia, marcas de suelo (anillo + relleno + borde + destello),
## columna de la lanza celeste, ondas (línea de aviso + cresta) y proyectiles (media luna dorada de
## la ráfaga, orbes de hechizo y bolas de fuego del eikon con estela). Solo lee el estado.
const S = preload("res://net/sim/fight_sim.gd")
const A = preload("res://net/sim/sim_abilities.gd")
const AOE_RING := Color(1.0, 0.35, 0.15)
const AOE_FILL := Color(1.0, 0.55, 0.2)
const AOE_EDGE := Color(1.0, 0.4, 0.15)
const AOE_BOOM := Color(1.0, 0.85, 0.5)
const STOC := Color(1.0, 0.25, 0.1)
const GOLD := Color(1.0, 0.82, 0.3)
const FADE_T := 24 ## ticks que la marca sigue tras detonar (SimAbilities.hazards)

var fighters: Array[Fighter] = []
var parent: Node3D
# --- por luchador ---
var _glow_key: Array[String] = ["", ""]
var _act: Array[int] = [-1, -1] ## ranura de la activación en curso
var _act_t: Array[int] = [0, 0]
var _fired: Array[int] = [0, 0]
var _vanished: Array[bool] = [false, false]
var _rage: Array[bool] = [false, false]
var _countered: Array[bool] = [false, false]
var _cone_t: Array[int] = [0, 0]
var _rage_fx: Array = [null, null]
var _cone: Array = [null, null]
# --- marcas de suelo ---
var _hz: Array = [] ## Dictionary por ranura: root, ring, fill, edge, column, line, crest, r, id, t
# --- proyectiles ---
var _pr: Array = [] ## Dictionary por ranura: root, slash, orb, core, trail, r
## Para pruebas: lo que se ha disparado (bursts, trails) por luchador.
var bursts: Array[int] = [0, 0]
var trails: Array[int] = [0, 0]

func _init(a: Fighter, b: Fighter, p: Node3D) -> void:
	fighters = [a, b]
	parent = p

func apply(s: PackedInt64Array, P: Array) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in 2:
		_fighter_fx(s, P, i)
	_hazards(s, P)
	_projectiles(s)

static func ab_color(id: String) -> Color:
	return BossAbilities.color_of(id) if id != "" else Color.WHITE

static func _ab_of(P: Array, i: int, slot: int) -> Dictionary:
	if slot < 0 or i >= P.size():
		return {}
	var bs: Array = P[i].get("boss", [])
	return bs[slot] if slot < bs.size() else {}

# ---------------- luchadores ----------------
func _fighter_fx(s: PackedInt64Array, P: Array, i: int) -> void:
	var f := fighters[i]
	if not is_instance_valid(f) or not f.is_inside_tree():
		return
	var o := i * S.F_FIELDS
	var slot: int = s[o + S.AB_SLOT]
	var ab := _ab_of(P, i, slot)
	var id := String(ab.get("id", ""))
	var typ := int(ab.get("type", -1))
	var steps_timeline := typ == A.T_STEPS and int(ab.get("family", -1)) == A.T_TIMELINE
	var fl: int = s[o + S.AB_FL]
	var t: int = s[o + S.AB_T]
	# activación nueva: otra ranura o el reloj vuelve atrás
	if slot != _act[i] or t < _act_t[i]:
		_act[i] = slot
		_fired[i] = 0
		_countered[i] = false
		if _vanished[i]:
			_set_vanished(f, i, false, id)
	_act_t[i] = t
	var bs_ph: int = s[o + S.BS_PH]
	# --- brillo del arma + aura de la estocada ---
	var key := ""
	var col := Color.BLACK
	if s[o + S.ALIVE] != 0 and (bs_ph == 1 or bs_ph == 2):
		key = "estocada"
		col = STOC
	elif s[o + S.ALIVE] != 0 and id != "":
		key = id
		col = ab_color(id)
		if (typ == A.T_TIMELINE or steps_timeline) and (fl & A.FL_FLICK0) != 0 and (fl & A.FL_FLICK1) == 0:
			key = id + ":flick"
			col = Color.WHITE
	if key != _glow_key[i]:
		_glow_key[i] = key
		if f._kv:
			f._kv.set_glow(key != "", col)
	_estocada_fx(s, P, f, i, bs_ph)
	# --- burbuja del escudo de maná ---
	var want_bubble := id == "escudo_mana" and s[o + S.ALIVE] != 0
	if want_bubble and not is_instance_valid(f.ab_bubble):
		f.ab_bubble = MeshUtil.sphere(f, 1.3, Vector3(0, 1.0, 0), Color(0.3, 1.0, 1.0, 0.25), true)
		var bm := MeshUtil._new_mat(Color(0.3, 1.0, 1.0, 0.22), true)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.emission_energy_multiplier = 0.6
		f.ab_bubble.material_override = bm
		f.ab_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not want_bubble and is_instance_valid(f.ab_bubble):
		f.ab_bubble.queue_free()
		f.ab_bubble = null
	# --- paso espectral: desaparece y reaparece con estallido ---
	var van := slot >= 0 and (fl & A.FL_VANISHED) != 0
	if van != _vanished[i]:
		_set_vanished(f, i, van, id)
	# --- golpes de timeline: rastro de espada del color de la habilidad ---
	var fired: int = s[o + S.AB_FIRED]
	if slot >= 0 and fired > _fired[i]:
		if (typ == A.T_TIMELINE or steps_timeline) and f._kv:
			f._kv.flash_sword_trail(Color(1.0, 0.22, 0.12) if id == "presa_verdugo" else ab_color(id))
			trails[i] += 1
		elif typ == A.T_CATALOG and f._kv:
			f._kv.flash_sword_trail(ab_color(id))
			trails[i] += 1
		elif typ == A.T_BREATH:
			_burst(f, i, ab_color(id))
			_cone_t[i] = 20
	_fired[i] = fired if slot >= 0 else 0
	_breath_cone(s, ab, f, i)
	# --- contragolpe: destello azul al activarse ---
	var ctr := slot >= 0 and typ == A.T_COUNTER and (fl & A.FL_COUNTERED) != 0
	if ctr and not _countered[i]:
		_burst(f, i, Color(0.4, 0.7, 1.0))
	_countered[i] = ctr
	# --- furia: estallido rojo al empezar y aura roja mientras dura ---
	var rage: bool = s[o + S.RAGE_T] > 0 and s[o + S.ALIVE] != 0
	if rage and not _rage[i]:
		_burst(f, i, Color(0.95, 0.15, 0.1))
	_rage[i] = rage
	_rage_aura(f, i, rage)

func _set_vanished(f: Fighter, i: int, on: bool, id: String) -> void:
	_vanished[i] = on
	if f._rider_root:
		f._rider_root.visible = not on
	_burst(f, i, ab_color(id) if id != "" else Color(0.7, 0.4, 1.0))

func _burst(f: Fighter, i: int, c: Color) -> void:
	bursts[i] += 1
	f._burst_particles(c)

func _estocada_fx(s: PackedInt64Array, P: Array, f: Fighter, i: int, ph: int) -> void:
	var o := i * S.F_FIELDS
	var on := (ph == 1 or ph == 2) and s[o + S.ALIVE] != 0
	if on and f._boss_fx == null:
		var p := CPUParticles3D.new()
		p.amount = 40
		p.lifetime = 0.5
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.6
		p.gravity = Vector3(0, 2.0, 0)
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.8
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.45, 0.15)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.1)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var qm := QuadMesh.new()
		qm.size = Vector2(0.12, 0.12)
		qm.material = m
		p.mesh = qm
		f.add_child(p)
		p.position = Vector3(0.5, 1.2, -0.6)
		f._boss_fx = p
	if f._boss_fx == null:
		return
	if f._boss_fx.emitting != on:
		f._boss_fx.emitting = on
	if f._blade_mat:
		f._blade_mat.emission_enabled = on
		if on:
			f._blade_mat.emission = STOC
	if not on:
		return
	var charge := 1
	for ab: Dictionary in P[i].get("boss", []):
		if int(ab.get("type", -1)) == A.T_ESTOCADA:
			charge = maxi(int(ab.get("charge", 1)), 1)
	var k := clampf(float(s[o + S.BS_T]) / charge, 0.0, 1.0) if ph == 1 else 1.0
	f._boss_fx.scale_amount_min = lerpf(0.3, 1.4, k)
	f._boss_fx.scale_amount_max = lerpf(0.5, 2.2, k)
	if f._blade_mat:
		f._blade_mat.emission_energy_multiplier = lerpf(0.5, 6.0, k)

func _breath_cone(s: PackedInt64Array, ab: Dictionary, f: Fighter, i: int) -> void:
	if _cone_t[i] > 0:
		_cone_t[i] -= 1
	var on := _cone_t[i] > 0 and s[i * S.F_FIELDS + S.ALIVE] != 0 and int(ab.get("type", -1)) == A.T_BREATH
	if on and _cone[i] == null:
		var rng := float(ab.get("range", 7500000)) / 1.0e6
		var cos_arc := float(ab.get("cos_arc", 3617)) / float(FxMath.ONE)
		var half := acos(clampf(cos_arc, -1.0, 1.0))
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.15
		cm.bottom_radius = maxf(tan(half) * rng, 0.5)
		cm.height = rng
		cm.radial_segments = 24
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		var c := ab_color(String(ab.get("id", "aliento_dragon")))
		var m := MeshUtil._new_mat(Color(c, 0.35), true)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# el cilindro va en Y: se tumba hacia -Z (el frente del luchador) desde la boca
		mi.rotation = Vector3(PI / 2.0, 0, 0)
		mi.position = Vector3(0, 1.3, -0.6 - rng * 0.5)
		f.add_child(mi)
		_cone[i] = mi
	if _cone[i] != null and is_instance_valid(_cone[i]):
		(_cone[i] as MeshInstance3D).visible = on
		if on:
			var m2: StandardMaterial3D = (_cone[i] as MeshInstance3D).material_override
			m2.albedo_color.a = 0.15 + 0.25 * float(_cone_t[i]) / 20.0

func _rage_aura(f: Fighter, i: int, on: bool) -> void:
	if on and _rage_fx[i] == null:
		var p := CPUParticles3D.new()
		p.amount = 16
		p.lifetime = 0.9
		p.direction = Vector3.UP
		p.spread = 25.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.4
		p.gravity = Vector3.ZERO
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.55
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.95, 0.12, 0.08)
		mat.emission_enabled = true
		mat.emission = Color(0.95, 0.12, 0.08)
		m.material = mat
		p.mesh = m
		f.add_child(p)
		p.position = Vector3(0, 1.0, 0)
		_rage_fx[i] = p
	if _rage_fx[i] != null and is_instance_valid(_rage_fx[i]) and (_rage_fx[i] as CPUParticles3D).emitting != on:
		(_rage_fx[i] as CPUParticles3D).emitting = on

## Lo que se ve de cada luchador (pruebas).
func glow_key(i: int) -> String:
	return _glow_key[i]

func rage_on(i: int) -> bool:
	return _rage_fx[i] != null and (_rage_fx[i] as CPUParticles3D).emitting

func cone_on(i: int) -> bool:
	return _cone[i] != null and (_cone[i] as MeshInstance3D).visible

# ---------------- marcas de suelo y ondas ----------------
static func _disc_mi(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 48
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _new_hz() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	parent.add_child(root)
	var ring := _disc_mi(Color(AOE_RING, 0.35))
	ring.position.y = 0.04
	root.add_child(ring)
	var fill := _disc_mi(Color(AOE_FILL, 0.55))
	fill.position.y = 0.05
	root.add_child(fill)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.rings = 48
	edge.mesh = tm
	edge.position.y = 0.06
	edge.scale = Vector3(1, 0.15, 1)
	edge.material_override = MeshUtil._new_mat(AOE_EDGE, true)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)
	var column := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 1.0
	cy.bottom_radius = 1.0
	cy.height = 1.0
	cy.radial_segments = 24
	column.mesh = cy
	var cmat := MeshUtil._new_mat(Color(0.95, 0.95, 1.0, 0.35), true)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column.material_override = cmat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(column)
	# onda rastrera: línea de aviso (franja en el suelo) + cresta que avanza
	var line := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(1, 0.02, 1)
	line.mesh = lb
	var lmat := MeshUtil._new_mat(Color(1.0, 0.3, 0.15, 0.3), false)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = lmat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)
	var crest := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1, 0.9, 0.5)
	crest.mesh = cb
	crest.material_override = MeshUtil._new_mat(Color(1.0, 0.45, 0.1), true)
	crest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crest)
	return {"root": root, "ring": ring, "fill": fill, "edge": edge, "column": column, "line": line, "crest": crest,
		"r": -1.0, "id": "", "t": -1, "on": false}

func _hazards(s: PackedInt64Array, P: Array) -> void:
	while _hz.size() < S.HZ_MAX:
		_hz.append(_new_hz())
	for j in S.HZ_MAX:
		var q := S.HZ_BASE + j * S.HZ_FIELDS
		var h: Dictionary = _hz[j]
		var root: Node3D = h["root"]
		var on := s[q + S.HZ_ON] != 0
		var t: int = s[q + S.HZ_T]
		if on and (not h["on"] or t < int(h["t"])):
			# marca nueva: la habilidad del dueño en este momento decide el estilo
			var ow: int = s[q + S.HZ_OWNER]
			var ab := _ab_of(P, ow, s[ow * S.F_FIELDS + S.AB_SLOT])
			h["id"] = String(ab.get("id", ""))
		h["on"] = on
		h["t"] = t
		root.visible = on and h["id"] != "salto_caida" # sin aviso: la única pista es verle en el aire
		if not root.visible:
			continue
		var id: String = h["id"]
		root.global_position = Vector3(s[q + S.HZ_X] / 1.0e6, 0.0, s[q + S.HZ_Z] / 1.0e6)
		var warn := maxi(int(s[q + S.HZ_WARN]), 1)
		var done := s[q + S.HZ_DONE] != 0
		var aoe := s[q + S.HZ_TYPE] == 1
		var ring: MeshInstance3D = h["ring"]
		var fill: MeshInstance3D = h["fill"]
		var edge: MeshInstance3D = h["edge"]
		var column: MeshInstance3D = h["column"]
		var line: MeshInstance3D = h["line"]
		var crest: MeshInstance3D = h["crest"]
		ring.visible = aoe
		fill.visible = aoe
		edge.visible = aoe
		column.visible = aoe and _pillar(id) and not done
		line.visible = not aoe and t < warn
		crest.visible = not aoe and t >= warn
		if aoe:
			root.rotation = Vector3.ZERO
			var r := maxf(s[q + S.HZ_R] / 1.0e6, 0.2)
			if not is_equal_approx(r, float(h["r"])):
				h["r"] = r
				var tm: TorusMesh = edge.mesh
				tm.inner_radius = maxf(r - 0.12, 0.05)
				tm.outer_radius = r
			var rain := _rain(id)
			var tint := ab_color(id) if rain else AOE_RING
			ring.scale = Vector3(r, 1, r)
			(ring.material_override as StandardMaterial3D).albedo_color = Color(tint, 0.35)
			(edge.material_override as StandardMaterial3D).albedo_color = tint if rain else AOE_EDGE
			var fm: StandardMaterial3D = fill.material_override
			if done:
				var a := 0.8 * (1.0 - clampf(float(t - warn) / FADE_T, 0.0, 1.0))
				fill.scale = Vector3(r, 1, r)
				fm.albedo_color = Color(AOE_BOOM, a)
			else:
				var k := clampf(float(t) / warn, 0.05, 1.0)
				fill.scale = Vector3(r * k, 1, r * k)
				fm.albedo_color = Color(ab_color(id).lerp(AOE_FILL, 0.4) if rain else AOE_FILL, 0.55)
			if column.visible:
				# columna de luz que se estrecha; la lanza cae cuando desaparece
				var k2 := clampf(float(t) / warn, 0.0, 1.0)
				var cr := lerpf(r, 0.15, k2)
				column.scale = Vector3(cr, 14.0, cr)
				column.position.y = 7.0
				(column.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.2, 0.55, k2)
		else:
			var dir := Vector3(s[q + S.HZ_DX], 0, s[q + S.HZ_DZ]) / float(FxMath.ONE)
			root.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
			var w := maxf(s[q + S.HZ_W] / 1.0e6, 0.5)
			var rng := maxf(s[q + S.HZ_RANGE] / 1.0e6, 1.0)
			var c := ab_color(id) if id != "" else Color(1.0, 0.45, 0.1)
			if line.visible:
				line.scale = Vector3(w, 1, rng)
				line.position = Vector3(0, 0.05, -rng * 0.5)
				(line.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.2, 0.65, float(t) / warn)
			if crest.visible:
				crest.scale = Vector3(w, 1, 1)
				crest.position = Vector3(0, 0.45, 0)
				var cm: StandardMaterial3D = crest.material_override
				cm.albedo_color = c
				cm.emission = c

static func _rain(id: String) -> bool:
	return String(BossAbilities.def(id).get("type", "")) == "rain"

static func _pillar(id: String) -> bool:
	return bool(BossAbilities.def(id).get("pillar", false))

func hazard_root(j: int) -> Node3D:
	return _hz[j]["root"] if j < _hz.size() else null

func hazard_part(j: int, part: String) -> MeshInstance3D:
	return _hz[j][part] if j < _hz.size() else null

# ---------------- proyectiles ----------------
func _new_pr() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	parent.add_child(root)
	var slash := Node3D.new()
	slash.rotation.z = deg_to_rad(45.0)
	root.add_child(slash)
	var orb := Node3D.new()
	root.add_child(orb)
	var core := MeshUtil.sphere(orb, 0.35, Vector3.ZERO, Color.WHITE)
	core.material_override = MeshUtil._new_mat(Color.WHITE, true)
	var trail := MeshUtil.box(orb, Vector3(0.3, 0.3, 1.2), Vector3(0, 0, 0.6), Color.WHITE)
	trail.material_override = MeshUtil._new_mat(Color.WHITE, true)
	trail.transparency = 0.5
	for mi: MeshInstance3D in [core, trail]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root": root, "slash": slash, "orb": orb, "core": core, "trail": trail, "r": -1.0}

## Color del tajo: la habilidad que lo disparó (AB_LAST), para que saeta y orbe no salgan dorados.
static func _slash_color(s: PackedInt64Array, owner: int) -> Color:
	if owner < 0 or owner > 1:
		return GOLD
	var code: int = s[owner * S.F_FIELDS + S.AB_LAST]
	var ids := BossAbilities.all_ids()
	if code < 0 or code >= ids.size():
		return GOLD
	return ab_color(String(ids[code]))

## Media luna de 7 segmentos en el plano perpendicular al vuelo, inclinada en diagonal (Projectile antiguo).
static func _build_slash(piv: Node3D, radius: float, col: Color = GOLD) -> void:
	for c in piv.get_children():
		c.queue_free()
	for i in 7:
		var a := deg_to_rad(-60.0 + i * 20.0)
		var seg := MeshUtil.box(piv, Vector3(0.42, 0.07 + 0.05 * (1.0 - absf(i - 3) / 3.0), 0.12), Vector3(sin(a) * radius, cos(a) * radius - radius * 0.6, 0.0), col)
		seg.rotation.z = -a
		seg.material_override = MeshUtil.mat(col, true)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail := MeshUtil.box(piv, Vector3(radius * 1.4, 0.04, 0.9), Vector3(0, radius * 0.35, 0.45), col)
	trail.material_override = MeshUtil.mat(Color(col, 0.4), true)
	trail.transparency = 0.6
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _projectiles(s: PackedInt64Array) -> void:
	while _pr.size() < S.PROJ_MAX:
		_pr.append(_new_pr())
	for j in S.PROJ_MAX:
		var q := S.PROJ_BASE + j * S.PR_FIELDS
		var d: Dictionary = _pr[j]
		var root: Node3D = d["root"]
		var kind: int = s[q + S.PR_KIND]
		# las flechas (kind 0) las dibuja SimView
		root.visible = s[q + S.PR_ON] != 0 and kind != 0
		if not root.visible:
			d["was"] = false
			continue
		root.global_position = Vector3(s[q + S.PR_X], s[q + S.PR_Y], s[q + S.PR_Z]) / 1.0e6
		var v := Vector3(s[q + S.PR_VX], s[q + S.PR_VY], s[q + S.PR_VZ])
		if v.length_squared() > 1.0:
			var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
			root.look_at(root.global_position + v, up)
		var slash: Node3D = d["slash"]
		var orb: Node3D = d["orb"]
		var born := root.visible and not bool(d.get("was", false))
		d["was"] = root.visible
		slash.visible = kind == 1
		orb.visible = kind != 1
		if kind == 1:
			if born:
				d["scol"] = _slash_color(s, s[q + S.PR_OWNER])
				d["r"] = -1.0
			var r := clampf(s[q + S.PR_R] / 1.0e6, 0.3, 1.6)
			if not is_equal_approx(r, float(d["r"])):
				d["r"] = r
				_build_slash(slash, r, d.get("scol", GOLD))
		else:
			var c := Color(1.0, 0.55, 0.2)
			if kind == 2:
				c = Color(1.0, 0.55, 0.2) if s[q + S.PR_ELEM] == A.ELEM_FUEGO else Color(0.75, 0.9, 1.0)
			else:
				var ow: int = s[q + S.PR_OWNER]
				if ow >= 0 and ow < 2 and is_instance_valid(fighters[ow]) and fighters[ow].eikon:
					c = fighters[ow].eikon.color
			(d["core"] as MeshInstance3D).material_override.albedo_color = c.lightened(0.3)
			(d["core"] as MeshInstance3D).material_override.emission = c.lightened(0.3)
			(d["trail"] as MeshInstance3D).material_override.albedo_color = c
			(d["trail"] as MeshInstance3D).material_override.emission = c

func proj_root(j: int) -> Node3D:
	return _pr[j]["root"] if j < _pr.size() else null

func proj_part(j: int, part: String) -> Node3D:
	return _pr[j][part] if j < _pr.size() else null
