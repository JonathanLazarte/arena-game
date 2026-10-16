class_name ShowcaseStage
extends Node3D
## Escenario del lobby y de la primera elección: cielo crepuscular con estrellas y aurora,
## castillo en silueta, pedestal de piedra con runas y un cristal flotante que ilumina
## al personaje con luz azul; luz principal cálida para que el personaje se lea bien.

const PROPS := "res://assets/props/"
var pedestal: Node3D
var preview: KnightVisual
var camera: Camera3D
var crystal: Node3D
var crystal_light: OmniLight3D
var aurora: Array[MeshInstance3D] = []
var rune_mat: StandardMaterial3D
var spin_speed: float = 0.25
var cam_x: float = 0.9
var _t: float = 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.02, 0.03, 0.12)
	sm.sky_horizon_color = Color(0.32, 0.25, 0.5)
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.18, 0.16, 0.3)
	sm.ground_bottom_color = Color(0.02, 0.03, 0.06)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.75)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.fog_enabled = true
	e.fog_light_color = Color(0.2, 0.25, 0.45)
	e.fog_density = 0.02
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new() # luna azulada (contraluz suave)
	moon.rotation_degrees = Vector3(-35, 160, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.45
	add_child(moon)
	var key := SpotLight3D.new() # luz principal cálida desde delante: el personaje se lee bien
	key.name = "KeyLight"
	key.position = Vector3(1.8, 3.6, 4.0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 5.0
	key.spot_range = 12.0
	key.spot_angle = 26.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(0, 1.0, 0))
	var rim := OmniLight3D.new() # contraluz cristal
	rim.name = "RimLight"
	rim.position = Vector3(-0.8, 2.3, -1.4)
	rim.light_color = Color(0.45, 0.7, 1.0)
	rim.light_energy = 2.6
	rim.omni_range = 4.5
	add_child(rim)
	# Suelo de piedra azulada y pedestal con runas
	var fl := MeshUtil.box(self, Vector3(80, 0.2, 80), Vector3(0, -0.1, 0), Color(0.14, 0.16, 0.24))
	MeshUtil.own(fl).roughness = 0.6
	pedestal = Node3D.new()
	add_child(pedestal)
	_disc(pedestal, 1.35, 0.32, 0.16, Color(0.28, 0.3, 0.4), 0.0)
	_disc(pedestal, 1.24, 0.04, 0.34, UIKit.ORANGE.darkened(0.2), 0.0)
	rune_mat = _disc(pedestal, 1.05, 0.02, 0.365, Color(0.35, 0.6, 1.0), 1.2)
	# Cristal flotante sobre el pedestal (bipirámide hexagonal emisiva)
	crystal = Node3D.new()
	crystal.name = "Crystal"
	crystal.position = Vector3(0, 2.75, 0)
	add_child(crystal)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.45, 0.75, 1.0, 0.75)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.emission_enabled = true
	cmat.emission = Color(0.35, 0.65, 1.0)
	cmat.emission_energy_multiplier = 2.2
	cmat.metallic = 0.3
	cmat.roughness = 0.1
	for up: bool in [true, false]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 6
		cm.rings = 1
		cm.top_radius = 0.0 if up else 0.17
		cm.bottom_radius = 0.17 if up else 0.0
		cm.height = 0.42 if up else 0.22
		mi.mesh = cm
		mi.position.y = 0.21 if up else -0.11
		mi.material_override = cmat
		crystal.add_child(mi)
	crystal_light = OmniLight3D.new()
	crystal_light.light_color = Color(0.45, 0.72, 1.0)
	crystal_light.light_energy = 2.0
	crystal_light.omni_range = 4.0
	crystal.add_child(crystal_light)
	# Castillo en silueta contra el crepúsculo
	var dark := Color(0.32, 0.36, 0.5)
	for i in range(-4, 5):
		if i != 0:
			_prop("wall.glb", Vector3(i * 2.5, 0, -12.0), 0.0, 2.5, dark)
	_prop("gate.glb", Vector3(0, 0, -12.0), 0.0, 2.5, dark)
	for x: float in [-11.5, 11.5]:
		_prop("tower-hexagon-base.glb", Vector3(x, 0, -12.0), 0.0, 2.5, dark)
		_prop("tower-hexagon-mid.glb", Vector3(x, 2.5, -12.0), 0.0, 2.5, dark)
		_prop("tower-hexagon-top.glb", Vector3(x, 5.0, -12.0), 0.0, 2.5, dark)
	_stars()
	_aurora()
	_shards()
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(Vector3(cam_x, 1.95, 5.6), Vector3(cam_x, 1.25, 0), Vector3.UP)
	camera.current = true

func _disc(parent: Node3D, r: float, h: float, y: float, c: Color, glow: float) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 48
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.45
	m.metallic = 0.5 if glow == 0.0 and c.r > 0.5 else 0.1
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position.y = y
	parent.add_child(mi)
	return m

func _prop(file: String, pos: Vector3, rot: float, k: float, tint: Color) -> void:
	var n := (load(PROPS + file) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * k
	add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if src:
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = src.albedo_color * tint
			(mi as MeshInstance3D).material_override = m

## Estrellas: un único MultiMesh de puntos emisivos en una cúpula lejana (1 draw call).
func _stars() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.9, 0.93, 1.0)
	mat.disable_fog = true
	qm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = qm
	mm.instance_count = 260
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var az := rng.randf_range(-1.3, 1.3)
		var el := rng.randf_range(0.12, 0.9)
		var d := 40.0
		var p := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * d
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.6, 2.2)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stars"
	mmi.multimesh = mm
	add_child(mmi)

## Aurora: cintas translúcidas aditivas con degradado verde-azulado que ondulan despacio.
func _aurora() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.2, 0.9, 0.7, 0.0))
	g.add_point(0.5, Color(0.3, 0.95, 0.75, 0.45))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.5, 1.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	gt.width = 4
	gt.height = 64
	for i in 3:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(26, 7)
		mi.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = gt
		m.albedo_color = Color(1, 1, 1, 0.55 - i * 0.12)
		m.disable_fog = true
		mi.material_override = m
		mi.position = Vector3(-4 + i * 5, 13 + i * 1.5, -30 - i * 3)
		mi.rotation = Vector3(0.25, 0.2 - i * 0.25, 0.08 * (i - 1))
		mi.name = "Aurora%d" % i
		add_child(mi)
		aurora.append(mi)

## Esquirlas de cristal flotando alrededor del cristal y del pedestal.
func _shards() -> void:
	var p := CPUParticles3D.new()
	p.name = "Shards"
	p.position = Vector3(0, 1.5, 0)
	p.amount = 24
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector3.UP
	p.gravity = Vector3(0, 0.15, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = UIKit.shard_texture()
	qm.material = mat
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.8, 1.0, 0))
	g.add_point(0.3, Color(0.7, 0.9, 1.0, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.6, 1.0, 0))
	p.color_ramp = g
	add_child(p)

func show_character(cd: CharacterDef, wd: WeaponDef, locked: bool = false, offhand: WeaponDef = null, ranged_weapon: WeaponDef = null, shield_enabled: bool = true) -> void:
	if preview:
		preview.queue_free()
	preview = KnightVisual.new()
	preview.position.y = 0.38
	preview.scale = Vector3.ONE * 0.9
	preview.rotation.y = PI # el luchador mira a -Z; aquí, de cara a la cámara
	pedestal.add_child(preview)
	preview.setup(Color(0.35, 0.5, 0.9), cd, wd, offhand, ranged_weapon)
	preview.set_mounted(false, 1.0)
	preview.set_loadout(1 if wd.ranged else 0, shield_enabled)
	var gs := get_node_or_null("/root/GameState")
	if gs and not locked and gs.character_id == cd.id:
		preview.set_armor(gs.armor_pieces()) # ronda 19
	if locked:
		preview.set_tint(Color(0.08, 0.1, 0.2), false) # silueta si está bloqueado

## Ronda 14: en la pestaña Eikons se muestra el eikon equipado junto al pedestal.
var eikon_preview: Node3D
var _eikon_shown: EikonData
func show_eikon(ed: EikonData) -> void:
	if ed == _eikon_shown and (ed == null or is_instance_valid(eikon_preview)):
		return
	_eikon_shown = ed
	if is_instance_valid(eikon_preview):
		eikon_preview.queue_free()
	eikon_preview = null
	if ed == null:
		return
	if ed.rideable:
		var m := Mount.new()
		m.data = ed.ride
		eikon_preview = m
		add_child(m)
		m.set_physics_process(false)
		m.scale = Vector3.ONE * 0.85
	else:
		var e := Eikon.new()
		e.data = ed
		e.preview = true
		eikon_preview = e
		add_child(e)
		e.scale = Vector3.ONE * 0.7
	eikon_preview.name = "EikonPreview"
	eikon_preview.position = Vector3(-1.75, 0.0, -0.9)
	eikon_preview.rotation.y = deg_to_rad(-135.0) # de perfil, mirando hacia el pedestal

func _process(delta: float) -> void:
	_t += delta
	pedestal.rotation.y += spin_speed * delta
	crystal.rotation.y += delta * 0.8
	crystal.position.y = 2.75 + sin(_t * 1.4) * 0.08
	crystal_light.light_energy = 1.8 + sin(_t * 2.0) * 0.3
	rune_mat.emission_energy_multiplier = 1.0 + sin(_t * 1.6) * 0.3
	for i in aurora.size():
		aurora[i].position.x += sin(_t * 0.3 + i) * delta * 0.4
		(aurora[i].material_override as StandardMaterial3D).albedo_color.a = 0.4 + sin(_t * 0.5 + i * 2.0) * 0.15
