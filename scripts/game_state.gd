extends Node
## Autoload "GameState": jugador local, oro de mentira y equipamiento (loadout) guardado en user://.

const SAVE_PATH := "user://loadout.cfg"
var save_path: String = SAVE_PATH ## las pruebas usan otra ruta
var player_name: String = "Jugador"
var oro: int = 1250 ## moneda de muestra (sin tienda todavía)
var character_id: String = "caballero"
var weapon_id: String = "espada_escudo"
var eikon_id: String = "fenix"
var mount_id: String = "caballo"
var difficulty: String = "facil"
## Rival: si es true (al jugar desde el lobby) recibe un equipamiento aleatorio; si no, el de siempre.
var random_rival: bool = false
var from_lobby: bool = false

func _ready() -> void:
	load_loadout()

## Elige personaje y, si el arma actual no es compatible, su arma por defecto.
func set_character(id: String) -> void:
	character_id = id
	var c := Catalog.character(id)
	if not c.allows(weapon_id):
		weapon_id = c.default_weapon

func set_weapon(id: String) -> bool:
	if not Catalog.character(character_id).allows(id):
		return false
	weapon_id = id
	return true

func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("jugador", "nombre", player_name)
	cfg.set_value("jugador", "oro", oro)
	for k: String in ["character_id", "weapon_id", "eikon_id", "mount_id", "difficulty"]:
		cfg.set_value("loadout", k, get(k))
	cfg.save(save_path)

func load_loadout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	player_name = cfg.get_value("jugador", "nombre", player_name)
	oro = cfg.get_value("jugador", "oro", oro)
	for k: String in ["character_id", "weapon_id", "eikon_id", "mount_id", "difficulty"]:
		set(k, cfg.get_value("loadout", k, get(k)))
	# Validar (un guardado viejo o editado a mano no rompe nada)
	if not Catalog.EIKONS.has(eikon_id): eikon_id = "fenix"
	if not Catalog.MOUNTS.has(mount_id): mount_id = "caballo"
	if not Catalog.DIFFICULTIES.has(difficulty): difficulty = "facil"
	set_character(Catalog.character(character_id).id)

func reset_defaults() -> void:
	player_name = "Jugador"
	oro = 1250
	character_id = "caballero"
	weapon_id = "espada_escudo"
	eikon_id = "fenix"
	mount_id = "caballo"
	difficulty = "facil"

## Equipamiento aleatorio coherente para el rival.
static func random_loadout() -> Dictionary:
	var cs := Catalog.characters()
	var c: CharacterDef = cs[randi() % cs.size()]
	var ws := Catalog.weapons_for(c).filter(func(w: WeaponDef) -> bool: return not w.ranged) # la IA lucha cuerpo a cuerpo
	return {"character": c, "weapon": ws[randi() % ws.size()], "eikon": Catalog.EIKONS.values()[randi() % 3],
		"mount": Catalog.MOUNTS.values()[randi() % 3]}
