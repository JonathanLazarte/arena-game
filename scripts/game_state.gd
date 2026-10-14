extends Node
## Autoload "GameState": perfil local (jugador, oro, progresión, desbloqueos) y equipamiento,
## guardado en user:// con versión (v1 = ronda 10, v2 = ronda 11 con progresión,
## v3 = ronda 14: sin monturas; los eikons son las monturas,
## v4 = ronda 15: un único personaje por ranura; sin compra/cambio de personajes,
## v5 = ronda 18: atributos por ranura; los antiguos se reparten solos según rol y nivel,
## v6 = ronda 19: armadura (casco/pecho/guantes/piernas) y arma secundaria; se regala el equipo inicial del rol).

const SAVE_PATH := "user://loadout.cfg"
const SAVE_VERSION := 11 ## v11 = ronda 31: habilidades de jefe por personaje; v9 = ronda 29: varios personajes con nombre propio; v10 = ronda 30: anillos/talismanes y ficha (horas, victorias)
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
var weapon_up: Dictionary = {} ## ronda 20: id arma -> nivel de mejora (+0..+10)
var weapon_inf: Dictionary = {} ## ronda 20: id arma -> infusión ("" = normal)
var materials: Dictionary = {} ## ronda 20: id piedra -> cantidad
var smith_migrated: bool = false ## v<7: se regalaron piedras de bienvenida
var spells: Array = [] ## ronda 21: hechizos de eikon equipados (por ranura de personaje)
var owned_arts: Array = WeaponArts.STARTER.duplicate() ## ronda 21: colección de artes de arma
var art_eq: Dictionary = {} ## ronda 21: id arma -> id arte
var magic_migrated: bool = false ## v<8: se equipó el hechizo del eikon y la estocada impulsada
const SMITH_WELCOME := {"piedra_1": 3}
# --- Ronda 29: varios personajes ---
var char_names: Dictionary = {} ## id -> nombre que le puso el jugador
var other_slots: Dictionary = {} ## id -> equipo del personaje no activo (arma, arma 2, armadura, hechizos)
const NAME_MAX := 16
# --- Ronda 30: anillos/talismanes y ficha personal ---
var char_boss: Dictionary = {} ## ronda 31: personaje -> habilidades de jefe (máx. 3)
var owned_trinkets: Array = [] ## colección global (anillos y talismanes)
var rings_eq: Array = ["", ""] ## del personaje activo
var talismans_eq: Array = ["", "", ""]
var char_stats: Dictionary = {} ## id -> {"secs": float, "wins": int, "matches": int}
var char_titles: Dictionary = {} ## id -> título equipado (Titles)
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

## Ronda 30: RECURSOS DE PRUEBA. true = al cargar, el perfil recibe (una sola vez por perfil)
## mucho oro, cristales, piedras de forja y todos los accesorios. PONER EN false ANTES DE PUBLICAR.
## También se puede forzar con el argumento `-- --debug-grant` o desactivar con `-- --no-debug-grant`.
const DEBUG_GRANT := true
const DEBUG_GOLD := 500000
const DEBUG_GEMS := 5000
const DEBUG_STONES := {"piedra_1": 60, "piedra_2": 60, "piedra_3": 60, "piedra_antigua": 15}
var debug_granted: bool = false

static func debug_grant_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--no-debug-grant" in args:
		return false
	return DEBUG_GRANT or "--debug-grant" in args

## Entrega los recursos de prueba si aún no se dieron a este perfil. Devuelve si los dio.
func apply_debug_grant(force: bool = false) -> bool:
	if debug_granted and not force:
		return false
	oro = maxi(oro, DEBUG_GOLD)
	gemas = maxi(gemas, DEBUG_GEMS)
	for sid: String in DEBUG_STONES:
		materials[sid] = maxi(int(materials.get(sid, 0)), int(DEBUG_STONES[sid]))
	for id: String in Trinkets.RINGS.keys() + Trinkets.TALISMANS.keys():
		if not id in owned_trinkets:
			owned_trinkets.append(id)
	debug_granted = true
	save_loadout()
	return true

func _ready() -> void:
	load_loadout()
	# Las pruebas automáticas (tests/) cambian save_path y no deben recibir el regalo
	if debug_grant_enabled() and save_path == SAVE_PATH and not OS.get_cmdline_args().has("-s"):
		apply_debug_grant()

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
	return eff_weapon(weapon2_id) if w.id == weapon2_id and w.ranged != Catalog.weapon(weapon_id).ranged else null

# ---------------- Herrería (ronda 20) ----------------

func weapon_level(id: String) -> int:
	return int(weapon_up.get(id, 0))

func weapon_infusion(id: String) -> String:
	return String(weapon_inf.get(id, ""))

## Arma con su mejora e infusión aplicadas.
func eff_weapon(id: String) -> WeaponDef:
	return Smithing.effective(Catalog.weapon(id), weapon_level(id), weapon_infusion(id))

func material(sid: String) -> int:
	return int(materials.get(sid, 0))

func add_material(sid: String, n: int) -> void:
	materials[sid] = material(sid) + n

## "ok", "no" (no es suya), "max", "oro" o "piedra".
func can_upgrade(id: String) -> String:
	if not id in owned_weapons:
		return "no"
	var nx := weapon_level(id) + 1
	if nx > Smithing.MAX_LEVEL:
		return "max"
	var c := Smithing.cost(nx)
	if oro < int(c["oro"]):
		return "oro"
	if material(c["piedra"]) < int(c["n"]):
		return "piedra"
	return "ok"

func upgrade_weapon(id: String) -> String:
	var r := can_upgrade(id)
	if r != "ok":
		return r
	var c := Smithing.cost(weapon_level(id) + 1)
	oro -= int(c["oro"])
	materials[c["piedra"]] = material(c["piedra"]) - int(c["n"])
	weapon_up[id] = weapon_level(id) + 1
	save_loadout()
	return "ok"

## Infusión: "ok", "no", "ya" u "oro". Volver a Normal es gratis.
func infuse(id: String, inf: String) -> String:
	if not id in owned_weapons or not Smithing.INFUSIONS.has(inf):
		return "no"
	if weapon_infusion(id) == inf:
		return "ya"
	var price := 0 if inf == "" else Smithing.INFUSE_GOLD
	if oro < price:
		return "oro"
	oro -= price
	weapon_inf[id] = inf
	save_loadout()
	return "ok"

## Compra una piedra en la Tienda: "ok", "nivel" u "oro".
func buy_stone(sid: String) -> String:
	if not Smithing.STONE_PRICES.has(sid):
		return "no"
	if account_level() < int(Smithing.STONE_SHOP_LEVEL[sid]):
		return "nivel"
	if oro < int(Smithing.STONE_PRICES[sid]):
		return "oro"
	oro -= int(Smithing.STONE_PRICES[sid])
	add_material(sid, 1)
	save_loadout()
	return "ok"

func armor_pieces() -> Dictionary:
	return EquipStats.armor_defs(armor_eq)

## Hoja de estadísticas del personaje equipado.
func sheet() -> Dictionary:
	return EquipStats.sheet(Catalog.character(character_id), char_level(), char_attrs(), eff_weapon(weapon_id), weapon2(), armor_pieces())

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
		"trinket": return id in owned_trinkets
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
func choose_first_character(id: String, nm: String = "") -> void:
	_unlock_char(id)
	set_char_name(id, nm)
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

## Ronda 29: nombre propio del personaje (si no tiene, el de la clase).
func char_name(id: String = "") -> String:
	var cid := id if id != "" else character_id
	var n: String = String(char_names.get(cid, ""))
	return n if n != "" else Catalog.character(cid).display_name

static func clean_name(nm: String) -> String:
	return nm.strip_edges().left(NAME_MAX)

func set_char_name(id: String, nm: String) -> void:
	var n := clean_name(nm)
	if n != "":
		char_names[id] = n

## Compra un personaje y le pone nombre (obligatorio). "ok", "nombre" o el motivo de can_buy.
func buy_character(id: String, nm: String) -> String:
	if clean_name(nm) == "":
		return "nombre"
	var r := buy("character", id)
	if r == "ok":
		set_char_name(id, nm)
		save_loadout()
	return r

## Ronda 29: cambia al personaje id (debe ser tuyo). Guarda el equipo del actual y recupera el suyo.
func switch_character(id: String) -> bool:
	if not id in unlocked_chars:
		return false
	if id == character_id:
		return true
	other_slots[character_id] = _gear()
	character_id = id
	var g: Dictionary = other_slots.get(id, {})
	other_slots.erase(id)
	var c := Catalog.character(id)
	weapon_id = String(g.get("weapon_id", c.default_weapon))
	weapon2_id = String(g.get("weapon2", ""))
	armor_eq = g.get("armor", {})
	spells = g.get("spells", [])
	rings_eq = _fit(g.get("rings", []), Trinkets.RING_SLOTS)
	talismans_eq = _fit(g.get("talismans", []), Trinkets.TALISMAN_SLOTS)
	if not c.allows(weapon_id) or not weapon_id in owned_weapons:
		weapon_id = c.default_weapon
	equipped_spells()
	save_loadout()
	return true

func _gear() -> Dictionary:
	return {"weapon_id": weapon_id, "weapon2": weapon2_id, "armor": armor_eq.duplicate(), "spells": spells.duplicate(),
		"rings": rings_eq.duplicate(), "talismans": talismans_eq.duplicate()}

func buy(kind: String, id: String) -> String:
	var r := can_buy(kind, id)
	if r != "ok":
		return r
	oro -= int(Progression.req(kind, id)[1])
	match kind:
		"character":
			var keep: Dictionary = armor_eq.duplicate()
			armor_eq = {}
			_unlock_char(id) # equipo inicial de su rol para él, no para el actual
			other_slots[id] = {"weapon_id": Catalog.character(id).default_weapon, "weapon2": "", "armor": armor_eq.duplicate(), "spells": [], "rings": ["", ""], "talismans": ["", "", ""]}
			armor_eq = keep
		"weapon": owned_weapons.append(id)
		"eikon": owned_eikons.append(id)
		"trinket": owned_trinkets.append(id)
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
		"armor": armor_eq, "weapon2": weapon2_id, "spells": spells, "rings": rings_eq, "talismans": talismans_eq}

# ---------------- Ronda 21: magia de eikon y artes de arma ----------------

func spell_slots() -> int:
	return EikonSpells.slots_for(char_attrs())

func equipped_spells() -> Array:
	if spells.is_empty():
		spells = EikonSpells.default_for(eikon_id) # nunca configurado: el hechizo de tu eikon
	spells = EikonSpells.sanitize(spells, spell_slots(), owned_eikons)
	return spells

func set_spell(slot: int, id: String) -> bool:
	var cur := equipped_spells()
	if slot < 0 or slot >= cur.size():
		return false
	if id != "" and not id in EikonSpells.available(owned_eikons):
		return false
	var other := cur.find(id)
	if id != "" and other >= 0 and other != slot:
		cur[other] = cur[slot] # intercambio si ya estaba en otra ranura
	cur[slot] = id
	spells = cur
	return true

## Siguiente hechizo disponible para una ranura (botón del menú).
func cycle_spell(slot: int) -> String:
	var opts: Array = [""] + EikonSpells.available(owned_eikons)
	var cur := equipped_spells()
	if slot < 0 or slot >= cur.size():
		return ""
	var i := opts.find(cur[slot])
	set_spell(slot, String(opts[(i + 1) % opts.size()]))
	return String(spells[slot])

func weapon_art(wid: String = "") -> String:
	if wid == "": wid = weapon_id
	if not WeaponArts.compatible(Catalog.weapon(wid)):
		return ""
	var a := String(art_eq.get(wid, WeaponArts.STARTER[0]))
	return a if a in owned_arts else ""

func set_weapon_art(wid: String, aid: String) -> bool:
	if not WeaponArts.compatible(Catalog.weapon(wid)) or (aid != "" and not aid in owned_arts):
		return false
	art_eq[wid] = aid
	return true

func cycle_weapon_art(wid: String = "") -> String:
	if wid == "": wid = weapon_id
	var opts: Array = owned_arts.duplicate() + [""]
	var i := opts.find(weapon_art(wid))
	set_weapon_art(wid, String(opts[(i + 1) % opts.size()]))
	return weapon_art(wid)

func buy_art(aid: String) -> bool:
	if not WeaponArts.DEFS.has(aid) or aid in owned_arts:
		return false
	var price := int(WeaponArts.DEFS[aid]["price"])
	if oro < price:
		return false
	oro -= price
	owned_arts.append(aid)
	save_loadout()
	return true

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
	var stones := Smithing.match_reward(bool(stats.get("won", false)), char_level())
	for sid: String in stones:
		add_material(sid, int(stones[sid]))
	record_match(bool(stats.get("won", false)), float(stats.get("secs", 0.0)))
	last_result = {"won": stats.get("won", false), "perfect": stats.get("won", false) and int(stats.get("lost_rounds", 1)) == 0, "xp": rw["xp"], "gold": int(rw["gold"]) + bonus, "level_bonus": bonus,
		"lines": rw["lines"], "mult": rw["mult"], "account_before": acc0, "account_after": account_level(),
		"char_before": ch0, "char_after": char_level(), "account_xp_before": acc_xp0, "account_xp": account_xp,
		"character": character_id, "stones": stones}
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
	cfg.set_value("herreria", "niveles", weapon_up)
	cfg.set_value("herreria", "infusiones", weapon_inf)
	cfg.set_value("herreria", "materiales", materials)
	cfg.set_value("artes", "coleccion", owned_arts)
	cfg.set_value("artes", "equipadas", art_eq)
	# Ronda 29: resto de personajes (nombres, XP, habilidades, atributos y su equipo)
	cfg.set_value("personajes", "nombres", char_names)
	cfg.set_value("personajes", "desbloqueados", unlocked_chars)
	var others := {}
	for id: String in unlocked_chars:
		if id != character_id:
			var g: Dictionary = other_slots.get(id, {}).duplicate()
			g["xp"] = int(char_xp.get(id, 0))
			g["skills"] = skills.get(id, [])
			g["attrs"] = attrs.get(id, Attributes.start_for(id))
			others[id] = g
	cfg.set_value("personajes", "otros", others)
	cfg.set_value("accesorios", "coleccion", owned_trinkets)
	cfg.set_value("jefe", "habilidades", char_boss)
	cfg.set_value("personajes", "fichas", char_stats)
	cfg.set_value("personajes", "titulos", char_titles)
	cfg.set_value("depuracion", "regalo_prueba", debug_granted)
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
	weapon_up = cfg.get_value("herreria", "niveles", {}) if ver >= 7 else {}
	weapon_inf = cfg.get_value("herreria", "infusiones", {}) if ver >= 7 else {}
	materials = cfg.get_value("herreria", "materiales", {}) if ver >= 7 else {}
	smith_migrated = false
	if ver < 7 and first_run_done:
		# v<7: armas a +0 sin infusión y piedras de bienvenida para probar la herrería
		for sid: String in SMITH_WELCOME:
			add_material(sid, int(SMITH_WELCOME[sid]))
		smith_migrated = true
		if migrated_from == 0:
			migrated_from = ver
	magic_migrated = false
	if ver >= 8:
		spells = cfg.get_value(sec, "spells", [])
		owned_arts = cfg.get_value("artes", "coleccion", WeaponArts.STARTER.duplicate())
		art_eq = cfg.get_value("artes", "equipadas", {})
	else:
		spells = []
		owned_arts = WeaponArts.STARTER.duplicate()
		art_eq = {}
		if first_run_done:
			magic_migrated = true
			if migrated_from == 0:
				migrated_from = ver
	char_names = {}
	other_slots = {}
	if ver >= 9:
		char_names = cfg.get_value("personajes", "nombres", {})
		var others: Dictionary = cfg.get_value("personajes", "otros", {})
		for id: String in cfg.get_value("personajes", "desbloqueados", []):
			if Catalog.character(id).id == id and not id in unlocked_chars:
				unlocked_chars.append(id)
		for id: String in others:
			if not id in unlocked_chars or id == character_id:
				continue
			var g: Dictionary = others[id]
			char_xp[id] = int(g.get("xp", 0))
			skills[id] = g.get("skills", [])
			attrs[id] = g.get("attrs", Attributes.start_for(id))
			other_slots[id] = {"weapon_id": g.get("weapon_id", Catalog.character(id).default_weapon), "weapon2": g.get("weapon2", ""), "armor": g.get("armor", {}), "spells": g.get("spells", []),
				"rings": _fit(g.get("rings", []), Trinkets.RING_SLOTS), "talismans": _fit(g.get("talismans", []), Trinkets.TALISMAN_SLOTS)}
	# Ronda 30 (v10): accesorios y ficha. Una partida v<10 empieza sin accesorios y con la ficha a cero.
	owned_trinkets = []
	rings_eq = ["", ""]
	talismans_eq = ["", "", ""]
	char_stats = {}
	char_titles = {}
	if ver >= 10:
		for id in cfg.get_value("accesorios", "coleccion", []):
			if Trinkets.kind(String(id)) != "" and not id in owned_trinkets:
				owned_trinkets.append(String(id))
		rings_eq = _fit(cfg.get_value(sec, "rings", []), Trinkets.RING_SLOTS)
		talismans_eq = _fit(cfg.get_value(sec, "talismans", []), Trinkets.TALISMAN_SLOTS)
		char_stats = cfg.get_value("personajes", "fichas", {})
		char_titles = cfg.get_value("personajes", "titulos", {})
	debug_granted = bool(cfg.get_value("depuracion", "regalo_prueba", false))
	char_boss = cfg.get_value("jefe", "habilidades", {}) # v<11: estocada por defecto

	attr_migrated = false
	if ver < 5:
		_migrate_attrs()
		if migrated_from == 0:
			migrated_from = ver
	set_character(character_id)
	if first_run_done and not eikon_id in owned_eikons: eikon_id = "fenix"
	if magic_migrated:
		spells = EikonSpells.default_for(eikon_id) # v<8: el hechizo de tu eikon en la ranura 1
	equipped_spells()
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
	debug_granted = false
	char_titles = {}
	owned_trinkets = []
	rings_eq = ["", ""]
	talismans_eq = ["", "", ""]
	char_stats = {}
	char_names = {}
	other_slots = {}
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
	weapon_up = {}
	weapon_inf = {}
	materials = {}
	smith_migrated = false
	spells = []
	owned_arts = WeaponArts.STARTER.duplicate()
	art_eq = {}
	magic_migrated = false
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


# ---------------- Ronda 30: anillos, talismanes y ficha personal ----------------

## Ajusta una lista de ids a n ranuras: solo accesorios tuyos y del tipo correcto, sin repetir.
func _fit(ids: Array, n: int) -> Array:
	var out: Array = []
	var k := "ring" if n == Trinkets.RING_SLOTS else "talisman"
	for i in n:
		var id := String(ids[i]) if i < ids.size() else ""
		if id != "" and (Trinkets.kind(id) != k or id in out or not id in owned_trinkets):
			id = ""
		out.append(id)
	return out

## Equipa (o quita con id = "") un anillo/talismán en la ranura i. Si ya estaba en otra ranura, se mueve.
func equip_trinket(kind: String, i: int, id: String) -> bool:
	var arr: Array = rings_eq if kind == "ring" else talismans_eq
	if i < 0 or i >= arr.size():
		return false
	if id != "" and (Trinkets.kind(id) != kind or not id in owned_trinkets):
		return false
	var j := arr.find(id) if id != "" else -1
	if j >= 0:
		arr[j] = ""
	arr[i] = id
	save_loadout()
	return true

func equipped_trinkets() -> Array:
	var out: Array = []
	if title_id() != "":
		out.append(title_id()) # ronda 30: el título suma su bonificación pequeña
	for id in rings_eq + talismans_eq:
		if String(id) != "":
			out.append(String(id))
	return out

func char_stat(id: String = "") -> Dictionary:
	var d: Dictionary = char_stats.get(id if id != "" else character_id, {})
	return {"secs": float(d.get("secs", 0.0)), "wins": int(d.get("wins", 0)), "matches": int(d.get("matches", 0))}

func record_match(won: bool, secs: float) -> void:
	var d := char_stat()
	d["secs"] += maxf(secs, 0.0)
	d["matches"] += 1
	if won:
		d["wins"] += 1
	char_stats[character_id] = d

static func hours_text(secs: float) -> String:
	var m := int(secs / 60.0)
	return "%d h %02d min" % [m / 60, m % 60]

## Títulos ganados por el personaje activo (o id).
func earned_titles(id: String = "") -> Array:
	var cid := id if id != "" else character_id
	var st := char_stat(cid)
	st["level"] = char_level(cid)
	var out: Array = []
	for t: String in Titles.ORDER:
		if Titles.earned(t, st):
			out.append(t)
	return out

func title_id(id: String = "") -> String:
	var cid := id if id != "" else character_id
	var t := String(char_titles.get(cid, ""))
	return t if t in earned_titles(cid) else ""

func set_title(t: String) -> bool:
	if t != "" and not t in earned_titles():
		return false
	char_titles[character_id] = t
	save_loadout()
	return true

## Nombre con el título: «Ragnar · Vencedor».
func display_name_with_title(id: String = "") -> String:
	var t := title_id(id)
	return char_name(id) + ("  «%s»" % Titles.def(t)["name"] if t != "" else "")


# ---------------- Ronda 31: habilidades de jefe ----------------
func boss_abilities(cid: String = "") -> Array:
	if cid == "":
		cid = character_id
	var a: Array = char_boss.get(cid, BossAbilities.DEFAULT)
	return a.duplicate()

## Equipa/quita una habilidad (máx. 3, mínimo 1). Devuelve si cambió.
func toggle_boss_ability(id: String) -> bool:
	if not BossAbilities.DEFS.has(id):
		return false
	var a := boss_abilities()
	if id in a:
		if a.size() <= 1:
			return false
		a.erase(id)
	else:
		if a.size() >= BossAbilities.MAX_EQUIPPED:
			return false
		a.append(id)
	char_boss[character_id] = a
	return true
