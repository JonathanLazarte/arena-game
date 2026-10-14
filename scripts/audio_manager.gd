extends Node
## Ronda 20: autoload "Audio". Buses Master/Música/Efectos/UI, música con fundido cruzado,
## efectos con variación de tono (2D y posicionales en 3D) y volúmenes persistentes (Ajustes).
## Audio provisional CC0 (ver CREDITS.md).

const BUSES := ["Master", "Música", "Efectos", "UI"]
const SETTINGS_PATH := "user://ajustes.cfg"
const MUSIC := {
	"lobby": "res://assets/audio/music/lobby_battle_theme_a.mp3",
	"combate1": "res://assets/audio/music/battle_hope.ogg",
	"combate2": "res://assets/audio/music/battle_final.ogg",
	"victoria": "res://assets/audio/music/stinger_victoria.ogg",
	"derrota": "res://assets/audio/music/stinger_derrota.ogg",
}
## nombre -> [variantes]
const SFX := {
	"swing_light": ["swing_light_1", "swing_light_2", "swing_light_3"],
	"swing_heavy": ["swing_heavy_6", "swing_heavy_9", "swing_heavy_12"],
	"whiff": ["whiff_1"],
	"hit_flesh": ["hit_flesh_0", "hit_flesh_1", "hit_flesh_2"],
	"hit_armor": ["hit_armor_0", "hit_armor_1", "hit_armor_2"],
	"block": ["block_0", "block_1", "block_2"],
	"guard_break": ["guard_break"], "parry": ["parry"],
	"roll": ["roll_1", "roll_2", "roll_3"], "step": ["step_0", "step_1", "step_2"],
	"jump": ["jump"], "land": ["land"],
	"bow_draw": ["bow_draw"], "bow_release": ["bow_release"], "xbow_fire": ["xbow_fire"], "xbow_reload": ["xbow_reload"],
	"arrow_hit": ["arrow_hit"], "eikon_summon": ["eikon_summon"],
	"eikon_fire": ["eikon_fire"], "eikon_ice": ["eikon_ice"], "eikon_wind": ["eikon_wind"], "eikon_slam": ["eikon_slam"],
	"hit_eikon": ["hit_eikon"],
	"status_sangrado": ["status_sangrado"], "status_veneno": ["status_veneno"], "status_congelacion": ["status_congelacion"],
	"purchase": ["purchase"], "smith": ["smith"],
}
const BASE_DB := {"step": -14.0, "whiff": -8.0, "roll": -6.0, "bow_draw": -6.0}

var volumes: Dictionary = {"Master": 0.9, "Música": 0.6, "Efectos": 0.85, "UI": 0.8}
var settings_path: String = SETTINGS_PATH
var played: Array = [] ## historial (pruebas)
var current_music: String = ""
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	_music_a = _mk_music()
	_music_b = _mk_music()
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "Música"
	add_child(_stinger)
	load_settings()

static func ensure_buses() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

func _mk_music() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Música"
	p.volume_db = -80.0
	add_child(p)
	return p

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

# ---------------- Volúmenes ----------------

func set_volume(bus: String, v: float, save: bool = true) -> void:
	v = clampf(v, 0.0, 1.0)
	volumes[bus] = v
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)
	if save:
		save_settings()

func get_volume(bus: String) -> float:
	return float(volumes.get(bus, 1.0))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	for b: String in BUSES:
		cfg.set_value("audio", b, volumes[b])
	cfg.set_value("control", "buffer", PlayerController.buffer_window) # ronda 23
	cfg.set_value("control", "cam_sens", CameraRig.sensitivity) # ronda 25
	cfg.set_value("control", "cam_invert", CameraRig.invert_y)
	cfg.set_value("control", "cam_capture", CameraRig.capture_mouse)
	cfg.save(settings_path)

## Ronda 23: ventana del búfer de entrada (Ajustes → Controles).
func set_buffer_window(v: float, save: bool = true) -> void:
	PlayerController.buffer_window = clampf(v, 0.1, 1.5)
	if save:
		save_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for b: String in BUSES:
			volumes[b] = float(cfg.get_value("audio", b, volumes[b]))
		CameraRig.sensitivity = clampf(float(cfg.get_value("control", "cam_sens", 1.0)), 0.2, 3.0)
		CameraRig.invert_y = bool(cfg.get_value("control", "cam_invert", false))
		CameraRig.capture_mouse = bool(cfg.get_value("control", "cam_capture", false))
		PlayerController.buffer_window = clampf(float(cfg.get_value("control", "buffer", PlayerController.BUFFER_WINDOW)), 0.1, 1.5)
	for b: String in BUSES:
		set_volume(b, volumes[b], false)

# ---------------- Música ----------------

## Fundido cruzado a otra pista (en bucle).
func music(name: String, fade: float = 1.2) -> void:
	if name == current_music or not MUSIC.has(name):
		return
	current_music = name
	played.append("music:" + name)
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	var st := _stream(MUSIC[name])
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	_music_a.stream = st
	_music_a.volume_db = -40.0
	_music_a.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_a, "volume_db", 0.0, fade)
	tw.tween_property(_music_b, "volume_db", -60.0, fade)
	tw.chain().tween_callback(_music_b.stop)

func stop_music(fade: float = 0.8) -> void:
	current_music = ""
	var tw := create_tween()
	tw.tween_property(_music_a, "volume_db", -60.0, fade)
	tw.tween_callback(_music_a.stop)

## Ráfaga de victoria/derrota (la música baja mientras suena).
func stinger(name: String) -> void:
	played.append("stinger:" + name)
	stop_music(0.4)
	_stinger.stream = _stream(MUSIC.get(name, MUSIC["victoria"]))
	_stinger.play()

# ---------------- Efectos ----------------

func _pick(name: String) -> AudioStream:
	var vs: Array = SFX.get(name, [])
	if vs.is_empty():
		return null
	return _stream("res://assets/audio/sfx/%s.ogg" % vs[randi() % vs.size()])

## Efecto 2D (bus Efectos o UI) con variación de tono.
func sfx(name: String, bus: String = "Efectos", pitch_var: float = 0.08) -> void:
	played.append(name)
	if played.size() > 200:
		played.pop_front()
	var st := _pick(name)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = BASE_DB.get(name, 0.0)
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## Efecto posicional 3D en la escena actual.
func sfx3d(name: String, pos: Vector3, pitch_var: float = 0.08, db: float = 0.0) -> void:
	played.append(name)
	if played.size() > 200:
		played.pop_front()
	var st := _pick(name)
	var scene := get_tree().current_scene
	if st == null or scene == null or not scene is Node3D:
		return
	var p := _pool3d_get(scene)
	p.stream = st
	p.volume_db = BASE_DB.get(name, 0.0) + db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.global_position = pos
	p.play()

## Ronda 26: grupo de 8 reproductores 3D reutilizables por escena (antes uno nuevo por efecto).
## Si los 8 suenan a la vez se crea uno temporal como antes (no se corta ningún sonido).
const POOL3D := 8
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool_scene: Node = null

func _pool3d_get(scene: Node) -> AudioStreamPlayer3D:
	if _pool_scene != scene:
		_pool_scene = scene
		_pool3d.clear()
	for q in _pool3d:
		if is_instance_valid(q) and not q.playing:
			return q
	var p := AudioStreamPlayer3D.new()
	p.bus = "Efectos"
	p.unit_size = 12.0
	p.max_distance = 70.0
	scene.add_child(p)
	_pool3d = _pool3d.filter(func(q: AudioStreamPlayer3D) -> bool: return is_instance_valid(q))
	if _pool3d.size() < POOL3D:
		p.name = "Sfx3D_%d" % _pool3d.size()
		_pool3d.append(p)
	else:
		p.finished.connect(p.queue_free)
	return p

func count(name: String) -> int:
	return played.count(name)
