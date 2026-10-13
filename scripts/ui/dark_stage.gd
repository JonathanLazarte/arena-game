class_name DarkStage
extends Node3D
## Escenario 3D oscuro del lobby y de la primera elección: castillo en ruinas de noche,
## antorchas parpadeantes, niebla roja, brasas y un pedestal giratorio con el personaje.

const PROPS := "res://assets/props/"
var pedestal: Node3D
var preview: KnightVisual
var camera: Camera3D
var torches: Array[OmniLight3D] = []
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
	sm.sky_top_color = Color(0.02, 0.015, 0.03)
	sm.sky_horizon_color = Color(0.22, 0.04, 0.05)
	sm.ground_horizon_color = Color(0.12, 0.03, 0.03)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.26, 0.3)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.16, 0.04, 0.05)
	e.fog_density = 0.045
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new() # luna fría de contraluz
	moon.rotation_degrees = Vector3(-30, 150, 0)
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.35
	add_child(moon)
	var key := SpotLight3D.new() # foco cálido sobre el pedestal
	key.position = Vector3(1.6, 4.5, 3.2)
	key.light_color = Color(1.0, 0.72, 0.45)
	key.light_energy = 6.0
	key.spot_range = 10.0
	key.spot_angle = 28.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(0, 0.8, 0))
	var rim := OmniLight3D.new() # contraluz carmesí
	rim.position = Vector3(-1.2, 2.2, -1.5)
	rim.light_color = Color(0.9, 0.12, 0.1)
	rim.light_energy = 2.5
	rim.omni_range = 4.0
	add_child(rim)
	# Suelo de losas oscuras
	var fl := MeshUtil.box(self, Vector3(60, 0.2, 60), Vector3(0, -0.1, 0), Color(0.12, 0.1, 0.1))
	(fl.material_override as StandardMaterial3D).roughness = 0.85
	# Pedestal (piedra negra con aro de oro deslustrado y runa roja)
	pedestal = Node3D.new()
	add_child(pedestal)
	_disc(pedestal, 1.3, 0.3, 0.15, Color(0.1, 0.09, 0.1), 0.0)
	_disc(pedestal, 1.18, 0.06, 0.33, DarkUI.GOLD, 0.0)
	_disc(pedestal, 1.0, 0.02, 0.365, Color(0.22, 0.03, 0.04), 0.35)
	# Castillo oscuro
	var dark := Color(0.35, 0.3, 0.32)
	for i in range(-4, 5):
		if i != 0:
			_prop("wall.glb", Vector3(i * 2.5, 0, -10.0), 0.0, 2.5, dark)
	_prop("gate.glb", Vector3(0, 0, -10.0), 0.0, 2.5, dark)
	for x: float in [-11.5, 11.5]:
		_prop("tower-hexagon-base.glb", Vector3(x, 0, -10.0), 0.0, 2.5, dark)
		_prop("tower-hexagon-mid.glb", Vector3(x, 2.5, -10.0), 0.0, 2.5, dark)
		_prop("tower-hexagon-top.glb", Vector3(x, 5.0, -10.0), 0.0, 2.5, dark)
	_prop("rocks-small.glb", Vector3(-3.5, 0, -1.5), 0.6, 1.5, dark)
	_prop("siege-ballista.glb", Vector3(5.5, 0, -3.0), -0.6, 1.2, dark)
	# Antorchas (braseros) con luz parpadeante y fuego de partículas
	for p: Vector3 in [Vector3(-2.6, 0, -1.2), Vector3(3.8, 0, -1.6), Vector3(-6.0, 0, -8.5), Vector3(6.0, 0, -8.5)]:
		_torch(p)
	_embers_3d()
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(Vector3(cam_x, 1.9, 5.6), Vector3(cam_x, 1.15, 0), Vector3.UP)
	camera.current = true

func _disc(parent: Node3D, r: float, h: float, y: float, c: Color, glow: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 48
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7 if c == DarkUI.GOLD else 0.1
	m.roughness = 0.45
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position.y = y
	parent.add_child(mi)

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

func _torch(p: Vector3) -> void:
	var post := MeshUtil.box(self, Vector3(0.15, 1.6, 0.15), p + Vector3(0, 0.8, 0), Color(0.15, 0.1, 0.07))
	post.name = "Torch"
	MeshUtil.box(self, Vector3(0.4, 0.15, 0.4), p + Vector3(0, 1.62, 0), Color(0.2, 0.17, 0.15))
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 1.95, 0)
	l.light_color = Color(1.0, 0.5, 0.18)
	l.light_energy = 2.2
	l.omni_range = 5.5
	add_child(l)
	torches.append(l)
	var f := CPUParticles3D.new()
	f.position = p + Vector3(0, 1.72, 0)
	f.amount = 18
	f.lifetime = 0.6
	f.direction = Vector3.UP
	f.spread = 15.0
	f.gravity = Vector3(0, 1.5, 0)
	f.initial_velocity_min = 0.5
	f.initial_velocity_max = 1.1
	f.scale_amount_min = 0.5
	f.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	f.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(0.7, 0.05, 0.0, 0.0))
	f.color_ramp = g
	add_child(f)

func _embers_3d() -> void:
	var p := CPUParticles3D.new()
	p.name = "Embers3D"
	p.position = Vector3(0, 0.2, -2.0)
	p.amount = 60
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 0.2, 5)
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0.15, 0.25, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.6, 0.2, 0.0))
	g.add_point(0.2, Color(1.0, 0.45, 0.1, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.0, 0.0, 0.0))
	p.color_ramp = g
	add_child(p)

func show_character(cd: CharacterDef, wd: WeaponDef, locked: bool = false) -> void:
	if preview:
		preview.queue_free()
	preview = KnightVisual.new()
	preview.position.y = 0.38
	preview.scale = Vector3.ONE * 0.9
	preview.rotation.y = PI # el luchador mira a -Z; aquí, de cara a la cámara
	pedestal.add_child(preview)
	preview.setup(Color(0.55, 0.12, 0.12), cd, wd)
	preview.set_mounted(false, 1.0)
	preview.set_loadout(1 if wd.ranged else 0)
	if locked:
		preview.set_tint(Color(0.15, 0.15, 0.2), false) # silueta apagada si está bloqueado

func _process(delta: float) -> void:
	_t += delta
	pedestal.rotation.y += spin_speed * delta
	for i in torches.size():
		torches[i].light_energy = 2.0 + sin(_t * 11.0 + i * 2.1) * 0.25 + sin(_t * 23.0 + i) * 0.15
