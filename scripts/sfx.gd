extends Node
## Autoload "Sfx": sonidos de interfaz (Kenney UI Audio, CC0).

const SOUNDS := {"click": "res://assets/sfx/click3.ogg", "hover": "res://assets/sfx/rollover2.ogg",
	"confirm": "res://assets/sfx/switch7.ogg", "levelup": "res://assets/sfx/switch33.ogg"}
var _players: Dictionary = {}
var played: Array = [] ## historial (pruebas)

func _ready() -> void:
	AudioMgrBuses.ensure()
	for k: String in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load(SOUNDS[k])
		p.volume_db = -10.0 if k == "hover" else -4.0
		p.bus = "UI" # ronda 20: bus de interfaz (Ajustes)
		add_child(p)
		_players[k] = p

func play(name: String) -> void:
	played.append(name)
	if played.size() > 50:
		played.pop_front()
	var p: AudioStreamPlayer = _players.get(name)
	if p:
		p.play()
