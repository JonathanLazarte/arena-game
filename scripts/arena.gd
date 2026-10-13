class_name Arena
extends Node3D
## Escena principal: construye la arena, los luchadores, la cámara, el HUD
## y gestiona las rondas (al mejor de 3).

const RADIUS := 42.0 ## x1.4 respecto a la v1 (30)
const PILLAR_RING := 23.8 ## 17 * 1.4
const SPAWN_DIST := 19.6 ## 14 * 1.4
const PROPS := "res://assets/props/"
const WINS_NEEDED := 2
const ROUND_TIME := 90.0
const EIKONS := ["res://resources/eikons/phoenix.tres", "res://resources/eikons/ice_wolf.tres", "res://resources/eikons/stone_golem.tres"]
const LEGACY_MOUNT := "res://resources/mounts/horse.tres"
## Ronda 14: los combates empiezan A PIE (las monturas son eikons que se invocan).
## Las pruebas antiguas de combate montado ponen esto a true antes de cargar la escena:
## cada luchador recibe entonces una montura neutral (caballo de pruebas) y empieza montado.
static var start_mounted: bool = false

var player: Fighter
var enemy: Fighter
var ai: AIController
var controller: PlayerController
var hud: HUD
var camera: Camera3D
var round_num: int = 1
var wins: Array[int] = [0, 0]
var state: String = "fight" ## fight / between / over
var time_left: float = ROUND_TIME
var shake: float = 0.0
var lock_marker: MeshInstance3D
var match_result: Dictionary = {}

func _ready() -> void:
	_build_environment()
	_build_arena()
	# Equipamiento: el del lobby (GameState) o el clásico si se carga la arena directamente (pruebas)
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.from_lobby:
		player = _make_fighter(gs.player_name, 0, Color(0.2, 0.4, 1.0), Catalog.EIKONS[gs.eikon_id],
			Catalog.character(gs.character_id), Catalog.weapon(gs.weapon_id), gs.char_skills())
	else:
		player = _make_fighter("Jugador", 0, Color(0.2, 0.4, 1.0), EIKONS[0])
	if gs and gs.random_rival:
		var r: Dictionary = gs.random_loadout()
		var rc: CharacterDef = r["character"]
		enemy = _make_fighter("Rival (%s)" % rc.display_name, 1, Color(0.85, 0.15, 0.15), r["eikon"], rc, r["weapon"])
	else:
		enemy = _make_fighter("Rival", 1, Color(0.85, 0.15, 0.15), EIKONS[1 + randi() % 2])
	player.opponent = enemy
	player.impact.connect(_on_impact)
	enemy.impact.connect(func(_s: float) -> void: pass)
	enemy.opponent = player
	camera = Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	hud = HUD.new()
	add_child(hud)
	hud.bind(player, enemy)
	hud.restart_requested.connect(restart_match)
	hud.lobby_requested.connect(func() -> void: UIKit.go("res://scenes/lobby.tscn"))
	controller = PlayerController.new()
	controller.me = player
	controller.camera = camera
	controller.joystick = hud.joystick
	add_child(controller)
	hud.controller = controller
	ai = AIController.new()
	ai.me = enemy
	if gs and gs.from_lobby:
		ai.profile = load(Catalog.DIFFICULTIES[gs.difficulty])
	add_child(ai)
	lock_marker = MeshUtil.sphere(self, 0.25, Vector3.ZERO, Color(1, 0.2, 0.2), true)
	start_round()

func _on_impact(strength: float) -> void:
	shake = maxf(shake, 0.35 * strength)

func _make_fighter(n: String, team: int, c: Color, eikon_path: String,
		cd: CharacterDef = null, wd: WeaponDef = null, sk: Array = []) -> Fighter:
	var f := Fighter.new()
	if cd:
		f.set_loadout_defs(cd, wd)
	f.set_skills(sk)
	f.display_name = n
	f.team = team
	f.color = c
	f.eikon = load(eikon_path)
	if start_mounted:
		f.mount = load(LEGACY_MOUNT)
		var m := Mount.new()
		m.data = f.mount
		add_child(m)
		add_child(f)
		f.owned_mount = m
		f.mount_on(m)
	else:
		add_child(f)
	f.died.connect(_on_fighter_died)
	return f

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Ronda 13: luz natural y legible. El sol queda alto y lateral, y una luz de relleno
	# opuesta (sin sombras) evita que los luchadores se vean negros a contraluz.
	sm.sky_top_color = Color(0.25, 0.45, 0.8)
	sm.sky_horizon_color = Color(0.7, 0.78, 0.88)
	sm.ground_horizon_color = Color(0.55, 0.6, 0.62)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.78, 0.9)
	e.fog_density = 0.0025
	env.environment = e
	add_child(env)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	add_child(fill)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -40, 0)
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.05
	add_child(sun)

## Malla de un prop de Kenney Castle Kit (CC0); incluye la transformación del nodo.
func _prop_mesh(file: String) -> Array:
	var n := (load(PROPS + file) as PackedScene).instantiate()
	var mi := n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var out := [mi.mesh, mi.transform]
	n.free()
	return out

## Muchas copias de un prop en un solo MultiMesh (barato en móvil).
func _prop_multi(file: String, xforms: Array[Transform3D]) -> void:
	var pm := _prop_mesh(file)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pm[0]
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] * (pm[1] as Transform3D))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

func _prop(file: String, xf: Transform3D) -> void:
	var n := (load(PROPS + file) as PackedScene).instantiate() as Node3D
	n.transform = xf
	add_child(n)

func _static_box(size: Vector3, pos: Vector3, c: Color, rot_y: float = 0.0, visual: bool = true) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = rot_y
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	sb.add_child(col)
	if visual:
		MeshUtil.box(sb, size, Vector3.ZERO, c)
	add_child(sb)

func _build_arena() -> void:
	# Suelo
	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(RADIUS * 2.5, 1.0, RADIUS * 2.5)
	fc.shape = fs
	fc.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fc)
	MeshUtil.cylinder(floor_body, RADIUS + 1.0, 0.2, Vector3(0, -0.1, 0), Color(0.34, 0.28, 0.21)) # tierra compactada (menos pálida)
	MeshUtil.cylinder(floor_body, 6.0, 0.22, Vector3(0, -0.09, 0), Color(0.28, 0.23, 0.17))
	add_child(floor_body)
	# Muro circular
	# Muro circular: colisión con cajas invisibles (igual que antes) y muro de Kenney en MultiMesh
	var segs := 56
	var seg_len := TAU * RADIUS / segs + 0.3
	var walls: Array[Transform3D] = []
	var studs: Array[Transform3D] = []
	for i in segs:
		var a := TAU * i / segs
		var p := Vector3(sin(a), 0, cos(a)) * (RADIUS + 0.6)
		_static_box(Vector3(seg_len, 4.0, 1.2), p + Vector3(0, 2.0, 0), Color.GRAY, a, false)
		var b := Basis(Vector3.UP, a)
		walls.append(Transform3D(b * Basis.from_scale(Vector3(seg_len, 3.2, 1.6)), p))
		if i % 4 == 0:
			var q := Vector3(sin(a + PI / segs), 0, cos(a + PI / segs)) * (RADIUS + 0.6)
			studs.append(Transform3D(Basis(Vector3.UP, a + PI / segs) * Basis.from_scale(Vector3(2.2, 3.6, 2.2)), q))
	_prop_multi("wall.glb", walls)
	_prop_multi("wall-pillar.glb", studs)
	# Decoración fuera del muro: estandartes, torres, balistas y rocas
	for i in 8:
		var a := TAU * i / 8 + PI / 8
		var p := Vector3(sin(a), 0, cos(a)) * (RADIUS + 0.2)
		_prop("flag-banner-long.glb", Transform3D(Basis(Vector3.UP, a + PI / 2) * Basis.from_scale(Vector3.ONE * 2.2), p + Vector3(0, 1.0, 0)))
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		var p := Vector3(sin(a), 0, cos(a)) * (RADIUS + 7.0)
		_prop("tower-hexagon-base.glb", Transform3D(Basis.from_scale(Vector3.ONE * 6.0), p))
		_prop("tower-hexagon-mid.glb", Transform3D(Basis.from_scale(Vector3.ONE * 6.0), p + Vector3(0, 7.86, 0)))
		_prop("tower-hexagon-top.glb", Transform3D(Basis.from_scale(Vector3.ONE * 6.0), p + Vector3(0, 10.62, 0)))
		_prop("flag.glb", Transform3D(Basis.from_scale(Vector3.ONE * 4.0), p + Vector3(0, 11.4, 0)))
	for i in 6:
		var a := TAU * i / 6
		var p := Vector3(sin(a), 0, cos(a)) * (RADIUS + 4.0)
		_prop("siege-ballista.glb" if i % 2 == 0 else "rocks-small.glb", Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3.ONE * 2.5), p + Vector3(0, 0.5, 0)))
	_prop("gate.glb", Transform3D(Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3.ONE * 5.0), Vector3(0, 0, RADIUS + 1.4)))
	_prop("gate.glb", Transform3D(Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3.ONE * 5.0), Vector3(0, 0, -RADIUS - 1.4)))
	# Pilares
	Projectile.obstacles.clear()
	Projectile.arena_radius = RADIUS
	for i in 6:
		var a := TAU * i / 6 + PI / 6
		var p := Vector3(sin(a), 0, cos(a)) * PILLAR_RING
		var sb := StaticBody3D.new()
		sb.position = p
		var col := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 1.3
		sh.height = 7.0
		col.shape = sh
		col.position = Vector3(0, 3.5, 0)
		sb.add_child(col)
		# Pilar visual: torre hexagonal de Kenney (base + 2 tramos + remate); radio ~1.3 como la colisión
		var k := 2.9
		_prop_at(sb, "tower-hexagon-base.glb", Vector3.ZERO, k)
		_prop_at(sb, "tower-hexagon-mid.glb", Vector3(0, 1.31 * k, 0), k)
		_prop_at(sb, "tower-hexagon-mid.glb", Vector3(0, (1.31 + 0.46) * k, 0), k)
		_prop_at(sb, "tower-hexagon-top.glb", Vector3(0, (1.31 + 0.92) * k, 0), k)
		MeshUtil.sphere(sb, 0.4, Vector3(0, 7.0, 0), Color(1.0, 0.6, 0.2), true)
		add_child(sb)
		Projectile.obstacles.append(Vector3(p.x, 1.5, p.z))

func _prop_at(parent: Node3D, file: String, pos: Vector3, k: float) -> void:
	var n := (load(PROPS + file) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.scale = Vector3.ONE * k
	parent.add_child(n)

func _physics_process(delta: float) -> void:
	if camera == null or player == null:
		return
	if state == "fight":
		time_left -= delta
		hud.timer_label.text = str(ceili(maxf(time_left, 0.0)))
		if time_left <= 0.0:
			# Tiempo agotado: pierde quien tenga menos vida (en %)
			var pl := player.health / player.max_health
			var en := enemy.health / enemy.max_health
			_on_fighter_died(enemy if pl >= en else player)
	var cam_target: Vector3
	var look: Vector3
	if player.face_target:
		# Lock-on: la cámara encuadra a ambos luchadores
		var d := MeshUtil.flat(player.face_target.global_position - player.global_position)
		var dist := d.length()
		var dn := d.normalized() if dist > 0.1 else player.facing
		cam_target = player.global_position - dn * (8.0 + clampf(dist * 0.15, 0.0, 5.0)) + Vector3(0, 5.0 + clampf(dist * 0.1, 0.0, 3.0), 0) + dn.cross(Vector3.UP) * 2.8 # sobre el hombro
		look = player.global_position.lerp(player.face_target.global_position, 0.5) + Vector3(0, 1.5, 0)
	else:
		var back := player.facing
		cam_target = player.global_position - back * 9.0 + Vector3(0, 5.0, 0)
		look = player.global_position + Vector3(0, 2.0, 0) + back * 4.0
	camera.global_position = camera.global_position.lerp(cam_target, clampf(delta * 4.0, 0.0, 1.0))
	if camera.global_position.distance_to(look) > 0.5:
		camera.look_at(look, Vector3.UP)
	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake
	lock_marker.visible = player.face_target != null
	if lock_marker.visible:
		lock_marker.global_position = player.face_target.global_position + Vector3(0, 3.9 + sin(Time.get_ticks_msec() * 0.006) * 0.1, 0)

func start_round(new_match: bool = false) -> void:
	for g: String in ["projectile", "ground_aoe"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	player.reset_for_round(Vector3(0, 0.2, SPAWN_DIST), Vector3.FORWARD, not new_match)
	enemy.reset_for_round(Vector3(0, 0.2, -SPAWN_DIST), Vector3.BACK, not new_match)
	camera.global_position = player.global_position + Vector3(0, 5, 9)
	state = "fight"
	time_left = ROUND_TIME
	controller.enabled = true
	_update_round_label()
	hud.show_message("Ronda %d - ¡Lucha!" % round_num, 1.2)

func _update_round_label() -> void:
	hud.round_label.text = "Ronda %d   %d - %d" % [round_num, wins[0], wins[1]]

func _on_fighter_died(f: Fighter) -> void:
	if state != "fight":
		return
	var winner := 1 if f == player else 0
	wins[winner] += 1
	_update_round_label()
	player.dismiss_eikon()
	enemy.dismiss_eikon()
	if wins[winner] >= WINS_NEEDED:
		state = "over"
		controller.enabled = false
		match_result = _award(winner == 0)
		hud.show_results(winner == 0, match_result)
		return
	state = "between"
	hud.show_message("Ronda para el %s" % ("Jugador" if winner == 0 else "Rival"), 2.0)
	round_num += 1
	get_tree().create_timer(2.5).timeout.connect(start_round)

## Recompensas de la partida (solo si se juega desde el lobby: las pruebas no tocan el perfil).
func _award(won: bool) -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.from_lobby:
		return {}
	return gs.apply_match_result({"won": won, "rounds": wins[0], "lost_rounds": wins[1], "hits": player.hits_landed,
		"parries": player.parries_landed, "difficulty": gs.difficulty})

func restart_match() -> void:
	player.hits_landed = 0
	player.parries_landed = 0
	wins = [0, 0]
	round_num = 1
	hud.end_panel.visible = false
	hud.set_touch_visible(true)
	start_round(true)
