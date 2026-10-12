class_name Arena
extends Node3D
## Escena principal: construye la arena, los luchadores, la cámara, el HUD
## y gestiona las rondas (al mejor de 3).

const RADIUS := 30.0
const WINS_NEEDED := 2
const ROUND_TIME := 90.0
const EIKONS := ["res://resources/eikons/phoenix.tres", "res://resources/eikons/ice_wolf.tres", "res://resources/eikons/stone_golem.tres"]

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

func _ready() -> void:
	_build_environment()
	_build_arena()
	player = _make_fighter("Jugador", 0, Color(0.2, 0.4, 1.0), "res://resources/mounts/horse.tres", EIKONS[0])
	enemy = _make_fighter("Rival", 1, Color(0.85, 0.15, 0.15), "res://resources/mounts/horse.tres", EIKONS[1 + randi() % 2])
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
	controller = PlayerController.new()
	controller.me = player
	controller.camera = camera
	controller.joystick = hud.joystick
	add_child(controller)
	ai = AIController.new()
	ai.me = enemy
	add_child(ai)
	lock_marker = MeshUtil.sphere(self, 0.25, Vector3.ZERO, Color(1, 0.2, 0.2), true)
	start_round()

func _on_impact(strength: float) -> void:
	shake = maxf(shake, 0.35 * strength)

func _make_fighter(n: String, team: int, c: Color, mount_path: String, eikon_path: String) -> Fighter:
	var f := Fighter.new()
	f.display_name = n
	f.team = team
	f.color = c
	f.mount = load(mount_path)
	f.eikon = load(eikon_path)
	add_child(f)
	f.died.connect(_on_fighter_died)
	return f

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.3, 0.55)
	sm.sky_horizon_color = Color(0.9, 0.6, 0.4)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

func _static_box(size: Vector3, pos: Vector3, c: Color, rot_y: float = 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = rot_y
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	sb.add_child(col)
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
	MeshUtil.cylinder(floor_body, RADIUS + 1.0, 0.2, Vector3(0, -0.1, 0), Color(0.62, 0.52, 0.38))
	MeshUtil.cylinder(floor_body, 6.0, 0.22, Vector3(0, -0.09, 0), Color(0.5, 0.4, 0.3))
	add_child(floor_body)
	# Muro circular
	var segs := 40
	var seg_len := TAU * RADIUS / segs + 0.3
	for i in segs:
		var a := TAU * i / segs
		var p := Vector3(sin(a), 0, cos(a)) * (RADIUS + 0.6)
		_static_box(Vector3(seg_len, 4.0, 1.2), p + Vector3(0, 2.0, 0), Color(0.45, 0.42, 0.4) if i % 2 == 0 else Color(0.5, 0.47, 0.44), a)
	# Pilares
	Projectile.obstacles.clear()
	Projectile.arena_radius = RADIUS
	for i in 6:
		var a := TAU * i / 6 + PI / 6
		var p := Vector3(sin(a), 0, cos(a)) * 17.0
		var sb := StaticBody3D.new()
		sb.position = p
		var col := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 1.3
		sh.height = 7.0
		col.shape = sh
		col.position = Vector3(0, 3.5, 0)
		sb.add_child(col)
		MeshUtil.cylinder(sb, 1.3, 7.0, Vector3(0, 3.5, 0), Color(0.7, 0.68, 0.62))
		MeshUtil.sphere(sb, 0.4, Vector3(0, 7.4, 0), Color(1.0, 0.6, 0.2), true)
		add_child(sb)
		Projectile.obstacles.append(Vector3(p.x, 1.5, p.z))

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

func start_round() -> void:
	for n in get_tree().get_nodes_in_group("projectile"):
		n.queue_free()
	player.reset_for_round(Vector3(0, 0.2, 14), Vector3.FORWARD)
	enemy.reset_for_round(Vector3(0, 0.2, -14), Vector3.BACK)
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
		hud.end_label.text = "¡VICTORIA!" if winner == 0 else "DERROTA"
		hud.end_panel.visible = true
		return
	state = "between"
	hud.show_message("Ronda para el %s" % ("Jugador" if winner == 0 else "Rival"), 2.0)
	round_num += 1
	get_tree().create_timer(2.5).timeout.connect(start_round)

func restart_match() -> void:
	wins = [0, 0]
	round_num = 1
	hud.end_panel.visible = false
	start_round()
