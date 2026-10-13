extends Node
## Autoload "GameState": perfil local (jugador, oro, progresión, desbloqueos) y equipamiento,
## guardado en user:// con versión (v1 = ronda 10, v2 = ronda 11 con progresión,
## v3 = ronda 14: sin monturas; los eikons son las monturas).

const SAVE_PATH := "user://loadout.cfg"
const SAVE_VERSION := 3
var save_path: String = SAVE_PATH ## las pruebas usan otra ruta
var player_name: String = "Jugador"
var oro: int = Progression.START_GOLD
var gemas: int = 50 ## moneda premium de muestra (ronda 12: solo se muestra)
var character_id: String = "caballero"
var weapon_id: String = "espada_escudo"
var eikon_id: String = "fenix"
var difficulty: String = "facil"
# --- Ronda 11 ---
var first_run_done: bool = false ## ya eligió su primer personaje
var account_xp: int = 0
var char_xp: Dictionary = {} ## id -> XP total del personaje
var skills: Dictionary = {} ## id personaje -> Array de ids de habilidad
var unlocked_chars: Array = []
var owned_weapons: Array = []
var owned_eikons: Array = ["fenix"]
## Ronda 14: resumen de la migración de monturas (eikons concedidos y oro devuelto).
var mount_migration: Dictionary = {}
var migrated_from: int = 0 ## versión de la que se migró al cargar (0 = ninguna)
var last_result: Dictionary = {} ## resultado de la última partida (pantalla de resultados)
## Rival: si es true (al jugar desde el lobby) recibe un equipamiento aleatorio; si no, el de siempre.
var random_rival: bool = false
var from_lobby: bool = false

func _ready() -> void:
	load_loadout()

# ---------------- Consultas ----------------

func account_level() -> int:
	return Progression.level_for_xp(account_xp)

func char_level(id: String = "") -> int:
	return Progression.level_for_xp(int(char_xp.get(id if id != "" else character_id, 0)))

func char_skills(id: String = "") -> Array:
	return skills.get(id if id != "" else character_id, [])

func skill_points(id: String = "") -> int:
	var cid := id if id != "" else character_id
	var spent := 0
	for s in char_skills(cid):
		spent += int(Progression.skill(String(s)).get("cost", 0))
	return Progression.skill_points_for_level(char_level(cid)) - spent

func is_unlocked(kind: String, id: String) -> bool:
	match kind:
		"character": return id in unlocked_chars
		"weapon": return id in owned_weapons
		"eikon": return id in owned_eikons
	return false

## "ok" si se puede comprar, si no el motivo: "ya", "nivel", "oro".
func can_buy(kind: String, id: String) -> String:
	if is_unlocked(kind, id):
		return "ya"
	var r := Progression.req(kind, id)
	if account_level() < int(r[0]):
		return "nivel"
	if oro < int(r[1]):
		return "oro"
	return "ok"

# ---------------- Acciones ----------------

## Primera vez: el rol elegido queda desbloqueado (gratis) con su arma.
func choose_first_character(id: String) -> void:
	_unlock_char(id)
	character_id = id
	weapon_id = Catalog.character(id).default_weapon
	first_run_done = true
	save_loadout()

func _unlock_char(id: String) -> void:
	if not id in unlocked_chars:
		unlocked_chars.append(id)
	var dw := Catalog.character(id).default_weapon
	if not dw in owned_weapons:
		owned_weapons.append(dw)
	if not char_xp.has(id):
		char_xp[id] = 0

func buy(kind: String, id: String) -> String:
	var r := can_buy(kind, id)
	if r != "ok":
		return r
	oro -= int(Progression.req(kind, id)[1])
	match kind:
		"character": _unlock_char(id)
		"weapon": owned_weapons.append(id)
		"eikon": owned_eikons.append(id)
	save_loadout()
	return "ok"

## Desbloquea una habilidad del personaje actual. "ok", "ya", "req" o "puntos".
func learn_skill(sid: String) -> String:
	var s := Progression.skill(sid)
	if s.is_empty() or not Progression.tree(character_id).has(s):
		return "req"
	var mine: Array = char_skills().duplicate()
	if sid in mine:
		return "ya"
	if s["req"] != "" and not s["req"] in mine:
		return "req"
	if skill_points() < int(s["cost"]):
		return "puntos"
	mine.append(sid)
	skills[character_id] = mine
	save_loadout()
	return "ok"

## Elige personaje (si está desbloqueado) y, si el arma no es compatible o no es suya, su arma por defecto.
func set_character(id: String) -> bool:
	if first_run_done and not id in unlocked_chars:
		return false
	character_id = id
	var c := Catalog.character(id)
	if not c.allows(weapon_id) or (first_run_done and not weapon_id in owned_weapons):
		weapon_id = c.default_weapon
	return true

func set_weapon(id: String) -> bool:
	if not Catalog.character(character_id).allows(id) or (first_run_done and not id in owned_weapons):
		return false
	weapon_id = id
	return true

## Aplica el resultado de una partida. Devuelve el resumen para la pantalla de resultados.
func apply_match_result(stats: Dictionary) -> Dictionary:
	var rw := Progression.match_rewards(stats)
	var acc0 := account_level()
	var ch0 := char_level()
	var acc_xp0 := account_xp
	account_xp += int(rw["xp"])
	char_xp[character_id] = int(char_xp.get(character_id, 0)) + int(rw["xp"])
	var acc_up := account_level() - acc0
	var bonus := acc_up * Progression.GOLD_LEVEL_UP
	oro += int(rw["gold"]) + bonus
	last_result = {"won": stats.get("won", false), "perfect": stats.get("won", false) and int(stats.get("lost_rounds", 1)) == 0, "xp": rw["xp"], "gold": int(rw["gold"]) + bonus, "level_bonus": bonus,
		"lines": rw["lines"], "mult": rw["mult"], "account_before": acc0, "account_after": account_level(),
		"char_before": ch0, "char_after": char_level(), "account_xp_before": acc_xp0, "account_xp": account_xp,
		"character": character_id}
	save_loadout()
	return last_result

# ---------------- Guardado ----------------

func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("jugador", "nombre", player_name)
	cfg.set_value("jugador", "oro", oro)
	cfg.set_value("jugador", "gemas", gemas)
	for k: String in ["character_id", "weapon_id", "eikon_id", "difficulty"]:
		cfg.set_value("loadout", k, get(k))
	cfg.set_value("progreso", "first_run_done", first_run_done)
	cfg.set_value("progreso", "account_xp", account_xp)
	cfg.set_value("progreso", "char_xp", char_xp)
	cfg.set_value("progreso", "skills", skills)
	cfg.set_value("progreso", "unlocked_chars", unlocked_chars)
	cfg.set_value("progreso", "owned_weapons", owned_weapons)
	cfg.set_value("progreso", "owned_eikons", owned_eikons)
	cfg.save(save_path)

func load_loadout() -> void:
	migrated_from = 0
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var ver: int = cfg.get_value("meta", "version", 1)
	player_name = cfg.get_value("jugador", "nombre", player_name)
	oro = cfg.get_value("jugador", "oro", oro)
	gemas = cfg.get_value("jugador", "gemas", 50)
	for k: String in ["character_id", "weapon_id", "eikon_id", "difficulty"]:
		set(k, cfg.get_value("loadout", k, get(k)))
	if not Catalog.EIKONS.has(eikon_id): eikon_id = "fenix"
	var old_mounts: Array = []
	mount_migration = {}
	if not Catalog.DIFFICULTIES.has(difficulty): difficulty = "facil"
	character_id = Catalog.character(character_id).id
	if ver < 2:
		_migrate_v1()
		old_mounts = ["caballo", String(cfg.get_value("loadout", "mount_id", "caballo"))]
	else:
		first_run_done = cfg.get_value("progreso", "first_run_done", false)
		account_xp = cfg.get_value("progreso", "account_xp", 0)
		char_xp = cfg.get_value("progreso", "char_xp", {})
		skills = cfg.get_value("progreso", "skills", {})
		unlocked_chars = cfg.get_value("progreso", "unlocked_chars", [])
		owned_weapons = cfg.get_value("progreso", "owned_weapons", [])
		owned_eikons = cfg.get_value("progreso", "owned_eikons", ["fenix"])
		if ver < 3:
			migrated_from = ver
			old_mounts = cfg.get_value("progreso", "owned_mounts", ["caballo"])
			old_mounts.append(String(cfg.get_value("loadout", "mount_id", "caballo")))
	if migrated_from > 0:
		_migrate_mounts(old_mounts)
	if first_run_done and unlocked_chars.is_empty():
		_unlock_char(character_id)
	if first_run_done and not character_id in unlocked_chars:
		character_id = String(unlocked_chars[0])
	set_character(character_id)
	if first_run_done and not eikon_id in owned_eikons: eikon_id = "fenix"
	if migrated_from > 0:
		save_loadout()

## v1 (ronda 10): sin progresión. Se conserva el personaje que usaba como desbloqueado,
## y también lo que tenía equipado (no se le quita nada); el oro se mantiene.
func _migrate_v1() -> void:
	migrated_from = 1
	first_run_done = true
	account_xp = 0
	char_xp = {}
	skills = {}
	unlocked_chars = []
	owned_weapons = []
	_unlock_char(character_id)
	if Catalog.character(character_id).allows(weapon_id) and not weapon_id in owned_weapons:
		owned_weapons.append(weapon_id)
	owned_eikons = ["fenix"]
	if eikon_id != "fenix": owned_eikons.append(eikon_id)

## v1/v2 -> v3: cada montura comprada pasa a ser su eikon equivalente (grifo) o se devuelve
## su precio en oro (unicornio). El caballo era gratis: desaparece sin compensación.
func _migrate_mounts(old: Array) -> void:
	var given: Array = []
	var refund := 0
	var seen: Array = []
	for m in old:
		var id := String(m)
		if id in seen:
			continue
		seen.append(id)
		if Progression.MOUNT_TO_EIKON.has(id):
			var eid: String = Progression.MOUNT_TO_EIKON[id]
			if not eid in owned_eikons:
				owned_eikons.append(eid)
				given.append(eid)
			else:
				refund += int(Progression.EIKON_REQ[eid][1]) # ya lo tenía: se devuelve el oro
		elif Progression.MOUNT_REFUND.has(id):
			refund += int(Progression.MOUNT_REFUND[id])
	oro += refund
	mount_migration = {"eikons": given, "refund": refund, "from": seen}

func reset_defaults() -> void:
	player_name = "Jugador"
	oro = Progression.START_GOLD
	gemas = 50
	character_id = "caballero"
	weapon_id = "espada_escudo"
	eikon_id = "fenix"
	difficulty = "facil"
	first_run_done = false
	account_xp = 0
	char_xp = {}
	skills = {}
	unlocked_chars = []
	owned_weapons = []
	owned_eikons = ["fenix"]
	mount_migration = {}
	last_result = {}

## Equipamiento aleatorio coherente para el rival.
static func random_loadout() -> Dictionary:
	var cs := Catalog.characters()
	var c: CharacterDef = cs[randi() % cs.size()]
	var ws := Catalog.weapons_for(c).filter(func(w: WeaponDef) -> bool: return not w.ranged) # la IA lucha cuerpo a cuerpo
	var es: Array = Catalog.EIKONS.values()
	return {"character": c, "weapon": ws[randi() % ws.size()], "eikon": es[randi() % es.size()]}
