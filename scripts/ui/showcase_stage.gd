class_name ShowcaseStage
extends Node3D
## Escaparate 3D del lobby y de la primera elección: día soleado, castillo claro,
## pedestal con aro de luz, contraluz brillante, rayos de luz y destellos.

const PROPS := "res://assets/props/"
var pedestal: Node3D
var preview: KnightVisual
var camera: Camera3D
var rays: Array[MeshInstance3D] = []
var ring_mat: StandardMaterial3D
var spin_speed: float = 0.3
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
	sm.sky_top_color = Color(0.2, 0.5, 0.95)
	sm.sky_horizon_color = Color(0.7, 0.88, 1.0)
	sm.ground_horizon_color = Color(0.65, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.35, 0.5, 0.35)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	e.glow_enabled = true
	e.glow_intensity = 0.25
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var rim := OmniLight3D.new() # contraluz brillante (perfila al personaje)
	rim.name = "RimLight"
	rim.position = Vector3(-0.6, 2.4, -1.4)
	rim.light_color = Color(0.6, 0.9, 1.0)
	rim.light_energy = 2.2
	rim.omni_range = 4.5
	add_child(rim)
	var rim2 := OmniLight3D.new()
	rim2.position = Vector3(1.4, 2.0, -1.2)
	rim2.light_color = Color(1.0, 0.85, 0.5)
	rim2.light_energy = 1.6
	rim2.omni_range = 4.0
	add_child(rim2)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.8, 1.6, 3.0)
	fill.light_energy = 0.5
	fill.omni_range = 6.0
	add_child(fill)
	# Césped y explanada
	MeshUtil.box(self, Vector3(80, 0.2, 80), Vector3(0, -0.1, 0), Color(0.42, 0.7, 0.35))
	MeshUtil.cylinder(self, 3.2, 0.05, Vector3(0, 0.02, 0), Color(0.7, 0.68, 0.62))
	# Pedestal: base azul, aro de luz cian y tapa blanca
	pedestal = Node3D.new()
	add_child(pedestal)
	_disc(pedestal, 1.35, 0.3, 0.15, Color(0.15, 0.35, 0.75), 0.0)
	ring_mat = _disc(pedestal, 1.25, 0.08, 0.33, Color(0.3, 0.9, 1.0), 2.5)
	_disc(pedestal, 1.12, 0.04, 0.38, Color(0.75, 0.82, 0.92), 0.0)
	# Castillo claro al fondo
	for i in range(-4, 5):
		if i != 0:
			_prop("wall.glb", Vector3(i * 2.5, 0, -11.0), 0.0, 2.5)
	_prop("gate.glb", Vector3(0, 0, -11.0), 0.0, 2.5)
	for x: float in [-11.5, 11.5]:
		_prop("tower-hexagon-base.glb", Vector3(x, 0, -11.0), 0.0, 2.5)
		_prop("tower-hexagon-mid.glb", Vector3(x, 2.5, -11.0), 0.0, 2.5)
		_prop("tower-hexagon-top.glb", Vector3(x, 5.0, -11.0), 0.0, 2.5)
	_prop("flag.glb", Vector3(-4.5, 0, -6.0), 0.0, 1.6)
	_prop("flag.glb", Vector3(5.0, 0, -6.0), 0.0, 1.6)
	_prop("rocks-small.glb", Vector3(-3.8, 0, -1.8), 0.6, 1.4)
	_rays()
	_sparkles()
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(Vector3(cam_x, 1.9, 5.6), Vector3(cam_x, 1.15, 0), Vector3.UP)
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
	m.roughness = 0.35
	m.metallic = 0.2
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position.y = y
	parent.add_child(mi)
	return m

func _prop(file: String, pos: Vector3, rot: float, k: float) -> void:
	var n := (load(PROPS + file) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * k
	add_child(n)

## Rayos de luz: planos aditivos detrás del pedestal que giran despacio (baratos: sin volumétricos).
func _rays() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.95, 0.7, 0.08)
	var pivot := Node3D.new()
	pivot.name = "Rays"
	pivot.position = Vector3(0, 1.4, -2.2)
	add_child(pivot)
	for i in 8:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 9.0)
		qm.center_offset = Vector3(0, 4.5, 0)
		mi.mesh = qm
		mi.material_override = mat
		mi.rotation.z = TAU * i / 8.0
		pivot.add_child(mi)
		rays.append(mi)

func _sparkles() -> void:
	var p := CPUParticles3D.new()
	p.name = "Sparkles"
	p.position = Vector3(0, 1.2, 0)
	p.amount = 28
	p.lifetime = 2.5
	p.preprocess = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.4
	p.direction = Vector3.UP
	p.gravity = Vector3(0, 0.3, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1.0, 0.95, 0.6, 1))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.9, 1.0, 0))
	p.color_ramp = g
	add_child(p)

func show_character(cd: CharacterDef, wd: WeaponDef, locked: bool = false) -> void:
	if preview:
		preview.queue_free()
	preview = KnightVisual.new()
	preview.position.y = 0.4
	preview.scale = Vector3.ONE * 0.9
	preview.rotation.y = PI # el luchador mira a -Z; aquí, de cara a la cámara
	pedestal.add_child(preview)
	preview.setup(Color(0.3, 0.55, 1.0), cd, wd)
	preview.set_mounted(false, 1.0)
	preview.set_loadout(1 if wd.ranged else 0)
	if locked:
		preview.set_tint(Color(0.1, 0.12, 0.2), false) # silueta si está bloqueado
	# Pop-in: el personaje aparece con un rebote
	preview.scale = Vector3.ONE * 0.5
	preview.create_tween().tween_property(preview, "scale", Vector3.ONE * 0.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	_t += delta
	pedestal.rotation.y += spin_speed * delta
	if rays.size() > 0:
		rays[0].get_parent().rotation.z = _t * 0.12
	if ring_mat:
		ring_mat.emission_energy_multiplier = 1.3 + sin(_t * 3.0) * 0.4
