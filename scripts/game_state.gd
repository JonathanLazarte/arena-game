extends Node
## Autoload "GameState": perfil local (jugador, oro, progresión, desbloqueos) y equipamiento,
## guardado en user:// con versión (v1 = ronda 10, v2 = ronda 11 con progresión,
## v3 = ronda 14: sin monturas; los eikons son las monturas,
## v4 = ronda 15: un único personaje por ranura; sin compra/cambio de personajes,
## v5 = ronda 18: atributos por ranura; los antiguos se reparten solos según rol y nivel,
## v6 = ronda 19: armadura (casco/pecho/guantes/piernas) y arma secundaria; se regala el equipo inicial del rol).

const SAVE_PATH := "user://loadout.cfg"
const SAVE_VERSION := 6
## Ronda 15: ranuras de personaje. Hoy solo existe la ranura 0; un futuro selector
## multi-ranura al iniciar solo tiene que cambiar active_slot y llamar a load_loadout().
const MAX_SLOTS := 1
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
var attrs: Dictionary = {} ## ronda 18: id personaje -> {atributo: valor}
var attr_migrated: bool = false
# --- Ronda 19 ---
var owned_armor: Array = []
var armor_eq: Dictionary = {} ## slot -> id ("" = nada)
var weapon2_id: String = "" ## arma secundaria (la del otro tipo: cuerpo a cuerpo / a distancia)
var armor_migrated: bool = false ## ronda 18: se repartieron los atributos al migrar
var unlocked_chars: Array = [] ## v4: siempre [character_id] (el personaje de la ranura activa)
var active_slot: int = 0
var char_migration: Dictionary = {} ## ronda 15: personajes extra reembolsados al migrar
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

# ---------------- Ronda 18: atributos ----------------

func char_attrs(id: String = "") -> Dictionary:
	var cid := id if id != "" else character_id
	if not attrs.has(cid):
		attrs[cid] = Attributes.start_for(cid)
	return attrs[cid]

func attr_points(id: String = "") -> int:
	var cid := id if id != "" else character_id
	return Attributes.free_points(cid, char_attrs(cid), char_level(cid))

## Confirma un reparto nuevo (desde la pantalla de atributos). "ok" o "invalido".
func set_attrs(a: Dictionary) -> String:
	if not Attributes.valid(character_id, a, char_level()):
		return "invalido"
	attrs[character_id] = a.duplicate()
	save_loadout()
	return "ok"

## Redistribuir (gratis por ahora): vuelve al reparto inicial y devuelve todos los puntos.
func respec() -> void:
	attrs[character_id] = Attributes.start_for(character_id)
	save_loadout()

# ---------------- Ronda 19: equipo ----------------

func _give_starter_armor(cid: String) -> void:
	var st := Catalog.starter_armor(cid)
	for sl: String in st:
		if not st[sl] in owned_armor:
			owned_armor.append(st[sl])
		if String(armor_eq.get(sl, "")) == "":
			armor_eq[sl] = st[sl]

## Equipa una pieza (o "" para quitarla). Solo lo que tienes y de esa ranura.
func equip_armor(slot: String, id: String) -> bool:
	if not slot in Catalog.ARMOR_SLOTS:
		return false
	if id != "":
		var a := Catalog.armor(id)
		if a == null or a.slot != slot or not id in owned_armor:
			return false
	armor_eq[slot] = id
	save_loadout()
	return true

## Arma secundaria: del tipo contrario a la principal ("" = la de recambio).
func set_weapon2(id: String) -> bool:
	if id == "":
		weapon2_id = ""
		save_loadout()
		return true
	var w := Catalog.weapon(id)
	if w.id != id or not Catalog.character(character_id).allows(id) or not id in owned_weapons or w.ranged == Catalog.weapon(weapon_id).ranged:
		return false
	weapon2_id = id
	save_loadout()
	return true

func weapon2() -> WeaponDef:
	if weapon2_id == "":
		return null
	var w := Catalog.weapon(weapon2_id)
	return w if w.id == weapon2_id and w.ranged != Catalog.weapon(weapon_id).ranged else null

func armor_pieces() -> Dictionary:
	return EquipStats.armor_defs(armor_eq)

## Hoja de estadísticas del personaje equipado.
func sheet() -> Dictionary:
	return EquipStats.sheet(Catalog.character(character_id), char_level(), char_attrs(), Catalog.weapon(weapon_id), weapon2(), armor_pieces())

## Compra todas las piezas que faltan de un conjunto. "ok", "ya", "nivel" u "oro".
func buy_set(set_id: String) -> String:
	var missing: Array = []
	var price := 0
	var lv := 1
	for a in Catalog.armors():
		if a.set_id == set_id and a.price > 0 and not a.id in owned_armor:
			missing.append(a.id)
			price += a.price
			lv = maxi(lv, a.level)
	if missing.is_empty():
		return "ya"
	if account_level() < lv:
		return "nivel"
	if oro < price:
		return "oro"
	oro -= price
	owned_armor.append_array(missing)
	save_loadout()
	return "ok"

func set_price(set_id: String) -> int:
	var price := 0
	for a in Catalog.armors():
		if a.set_id == set_id and a.price > 0 and not a.id in owned_armor:
			price += a.price
	return price

func is_unlocked(kind: String, id: String) -> bool:
	match kind:
		"character": return id in unlocked_chars
		"weapon": return id in owned_weapons
		"eikon": return id in owned_eikons
		"armor": return id in owned_armor
	return false

## "ok" si se puede comprar, si no el motivo: "ya", "nivel", "oro".
func can_buy(kind: String, id: String) -> String:
	if is_unlocked(kind, id):
		return "ya"
	if kind == "character":
		return "no_venta" # ronda 15: los personajes no se compran
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
	if not attrs.has(id):
		attrs[id] = Attributes.start_for(id)
	_give_starter_armor(id)

func buy(kind: String, id: String) -> String:
	var r := can_buy(kind, id)
	if r != "ok":
		return r
	oro -= int(Progression.req(kind, id)[1])
	match kind:
		"character": _unlock_char(id)
		"weapon": owned_weapons.append(id)
		"eikon": owned_eikons.append(id)
		"armor": owned_armor.append(id)
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
## Ronda 15: tras la primera elección el personaje queda fijo.
func set_character(id: String) -> bool:
	if first_run_done and id != character_id:
		return false
	character_id = id
	var c := Catalog.character(id)
	if not c.allows(weapon_id) or (first_run_done and not weapon_id in owned_weapons):
		weapon_id = c.default_weapon
	return true

## Datos de la ranura activa (lo que se guarda por personaje).
func slot_data() -> Dictionary:
	return {"character_id": character_id, "weapon_id": weapon_id,
		"xp": int(char_xp.get(character_id, 0)), "skills": char_skills(), "attrs": char_attrs(),
		"armor": armor_eq, "weapon2": weapon2_id}

func set_weapon(id: String) -> bool:
	if not Catalog.character(character_id).allows(id) or (first_run_done and not id in owned_weapons):
		return false
	weapon_id = id
	if weapon2() == null:
		weapon2_id = ""
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
	for k: String in ["eikon_id", "difficulty"]:
		cfg.set_value("loadout", k, get(k))
	cfg.set_value("meta", "active_slot", active_slot)
	var sd := slot_data()
	for k: String in sd:
		cfg.set_value("slot_%d" % active_slot, k, sd[k])
	cfg.set_value("progreso", "first_run_done", first_run_done)
	cfg.set_value("progreso", "account_xp", account_xp)
	cfg.set_value("progreso", "owned_weapons", owned_weapons)
	cfg.set_value("progreso", "owned_eikons", owned_eikons)
	cfg.set_value("progreso", "owned_armor", owned_armor)
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
	active_slot = clampi(int(cfg.get_value("meta", "active_slot", 0)), 0, MAX_SLOTS - 1)
	var sec := "slot_%d" % active_slot
	if ver >= 4:
		character_id = cfg.get_value(sec, "character_id", character_id)
		weapon_id = cfg.get_value(sec, "weapon_id", weapon_id)
	char_migration = {}
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
		if ver >= 4:
			char_xp = {character_id: int(cfg.get_value(sec, "xp", 0))}
			skills = {character_id: cfg.get_value(sec, "skills", [])}
			if ver >= 6:
				armor_eq = cfg.get_value(sec, "armor", {})
				weapon2_id = cfg.get_value(sec, "weapon2", "")
			if ver >= 5:
				attrs = {character_id: cfg.get_value(sec, "attrs", Attributes.start_for(character_id))}
			unlocked_chars = [character_id] if first_run_done else []
		else:
			char_xp = cfg.get_value("progreso", "char_xp", {})
			skills = cfg.get_value("progreso", "skills", {})
			unlocked_chars = cfg.get_value("progreso", "unlocked_chars", [])
		owned_weapons = cfg.get_value("progreso", "owned_weapons", [])
		owned_eikons = cfg.get_value("progreso", "owned_eikons", ["fenix"])
		owned_armor = cfg.get_value("progreso", "owned_armor", [])
		if ver < 3:
			migrated_from = ver
			old_mounts = cfg.get_value("progreso", "owned_mounts", ["caballo"])
			old_mounts.append(String(cfg.get_value("loadout", "mount_id", "caballo")))
		if ver < 4 and migrated_from == 0:
			migrated_from = ver
	if migrated_from > 0 and migrated_from < 3:
		_migrate_mounts(old_mounts)
	if first_run_done and unlocked_chars.is_empty():
		_unlock_char(character_id)
	if first_run_done and not character_id in unlocked_chars:
		character_id = String(unlocked_chars[0])
	if migrated_from > 0 and ver < 4:
		_migrate_characters()
	armor_migrated = false
	if ver < 6 and first_run_done:
		_give_starter_armor(character_id) # v<6: se regala el equipo inicial del rol
		armor_migrated = true
		if migrated_from == 0:
			migrated_from = ver
	attr_migrated = false
	if ver < 5:
		_migrate_attrs()
		if migrated_from == 0:
			migrated_from = ver
	set_character(character_id)
	if first_run_done and not eikon_id in owned_eikons: eikon_id = "fenix"
	if migrated_from > 0:
		save_loadout()

## v<5 -> v5: los personajes existentes reciben atributos según su nivel, repartidos por rol.
func _migrate_attrs() -> void:
	attrs = {}
	for c in char_xp:
		attrs[String(c)] = Attributes.auto_allocate(String(c), char_level(String(c)))
	attr_migrated = true

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

## v2/v3 -> v4: se conserva solo el personaje seleccionado (con su XP y habilidades);
## se devuelve el oro de los personajes extra comprados. El primero fue gratis, así que
## el seleccionado nunca se reembolsa (aunque no fuera el primero elegido).
func _migrate_characters() -> void:
	var extra: Array = []
	var refund := 0
	for c in unlocked_chars:
		var id := String(c)
		if id != character_id and not id in extra:
			extra.append(id)
	# Se reembolsan todos los extra (no se guardaba cuál fue gratis; lo más justo para el jugador).
	for id: String in extra:
		refund += int(Progression.LEGACY_CHARACTER_PRICE.get(id, 0))
	oro += refund
	unlocked_chars = [character_id] if first_run_done else []
	char_xp = {character_id: int(char_xp.get(character_id, 0))} if first_run_done else {}
	skills = {character_id: skills.get(character_id, [])} if first_run_done else {}
	char_migration = {"removed": extra, "refund": refund}

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
	attrs = {}
	attr_migrated = false
	owned_armor = []
	armor_eq = {}
	weapon2_id = ""
	armor_migrated = false
	unlocked_chars = []
	owned_weapons = []
	owned_eikons = ["fenix"]
	mount_migration = {}
	char_migration = {}
	active_slot = 0
	last_result = {}

## Equipamiento aleatorio coherente para el rival.
static func random_loadout() -> Dictionary:
	var cs := Catalog.characters()
	var c: CharacterDef = cs[randi() % cs.size()]
	var ws := Catalog.weapons_for(c).filter(func(w: WeaponDef) -> bool: return not w.ranged) # la IA lucha cuerpo a cuerpo
	var es: Array = Catalog.EIKONS.values()
	return {"character": c, "weapon": ws[randi() % ws.size()], "eikon": es[randi() % es.size()]}
