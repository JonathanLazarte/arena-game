class_name AbilityCatalog
extends RefCounted
## Cargador + validador + horneado del catálogo de habilidades (docs/abilities_guide.md).
## NO ejecuta habilidades ni lo usa todavía la sim: es la base para el futuro motor genérico de pasos.
##
## load_file(path) / load_text(text) / load_data(dict) -> {ok, errors, warnings, baked, hash}
##   errors/warnings: [{path, rule, message}] con rutas tipo abilities[3].steps[1].hitboxes[0].shape.radius_m
##   baked: estructura de solo lectura en enteros / punto fijo (mismas convenciones que SimParams:
##   vida/daño/fuerza en milésimas, distancias µm, velocidades µm/tick, ‰, ticks, rumbos 0..255,
##   giros en mili-rumbos/tick, arcos como coseno ×FxMath.ONE). ids → índices enteros, -1 = fin.
##   hash: FNV-1a 32 bits de var_to_str(baked) (estable entre plataformas, como params_checksum).
## Nunca lanza errores con entradas malas: todo problema queda en errors.

const TICK_RATE := 60
const GLOBAL_CD_TICKS := 84
const MAX_STEPS := 16
const MAX_PROJECTILES := 6
const MAX_HAZARDS := 8
const MIN_UNBLOCKABLE_WINDUP := 18
const MIN_FINAL_RECOVERY := 18
const MIN_NOINTERRUPT_RECOVERY := 30

const CATEGORIES := ["melee", "ranged", "magic", "grab", "buff", "summon", "zone", "counter", "movement"]
const KNOWN_TAGS := ["unblockable", "delayed", "multi_hit", "aerial", "mana_shield", "tracking", "aoe", "projectile"]
const USABLE := ["ground", "air", "mounted", "sprinting", "blocking"]
const INTERRUPTS := ["stun_lvl1", "stun_lvl2", "knockdown", "parry", "guard_break", "stance_break", "grab"]
## Vacío = la habilidad no se corta: solo se esquiva. Quien se corta lo declara.
const DEFAULT_INTERRUPTS: Array = []
const OI_COOLDOWN := ["full", "global_only", "none"]
const USE_WHEN := ["target_in_range", "target_recovering", "target_far", "target_close", "target_blocking",
	"target_healing", "target_downed", "self_low_hp", "self_phase2", "opener"]
const TELE_STYLES := ["weapon_glow", "weapon_flash", "body_pose", "aura", "ground_ring", "ground_line", "ground_cone", "sky_column", "vanish"]
const ARMOR := ["hyper", "super"]
const INVULN_MODES := ["stun_immune", "total"]
const MOVES := ["none", "dash", "leap", "slam", "teleport_behind", "orbit", "retreat", "blink_to_target"]
const TARGET_MODES := ["facing", "target", "lock_point", "away_from_target"]
const ANCHORS := ["self", "lock_point", "spawn_point"]
const SHAPES := ["circle", "arc", "line", "ring", "box"]
const DMG_TYPES := ["physical", "fuego", "magico", "sagrado", "rayo", "hielo"]
## weapon_*: damage_per_hit es el multiplicador del fuerte o del ligero del arma (× daño del atacante).
const DMG_SCALING := ["attacker", "magic", "none", "weapon_heavy", "weapon_light"]
const STUN_SCALING := ["physical", "magic", "none"]
const FORCES := ["pull", "push", "launch", "root"]
const BREAKABLE := ["roll", "jump", "parry", "damage_taken", "none"]
const STATUSES := ["sangrado", "slow", "silence", "mark"]
const SPAWNS := ["ground_mark", "ground_wave", "projectile", "zone", "beam", "summon"]
const HAZARD_SPAWNS := ["ground_mark", "ground_wave", "zone"]
const MARK_MODES := ["track", "scatter"]
const ONLY_ON := ["any", "hit", "blocked", "whiff"]
const TRIGGERS := ["auto", "skill"]
const TIME_BASES := ["step", "active"]
const COMMITS := ["window_end", "immediate", "on_step_end"]
const INPUTS := ["skill", "alt", "alt2"]
const EV_ON := ["always", "hit", "whiff"]
const SPAWN_ON := ["always", "hit"]
const NEXT_KEYS := ["default", "on_hit", "on_whiff", "on_blocked"]
const HINT_DODGE := ["roll_early", "roll_late", "roll_through", "sidestep", "jump", "distance", "parry", "block"]
const HINT_DIR := ["side", "back", "forward", "any"]
const REQUIRES := ["target_close", "target_far", "last_hit_landed", "phase2"]
## Etapas 1..7d: constantes de nuevos esquemas
const EXIT_ACTIONS := ["attack", "roll", "move", "combo"]
const ATTACH_TARGETS := ["self", "weapon", "hand", "foot", "ground"]
const ATTACH_POINTS := ["self", "weapon", "hand", "foot", "ground"]
const HAPTICS := ["none", "light", "medium", "heavy"]
const HAPTIC_LEVELS := ["none", "light", "medium", "heavy"]
const VOLLEY_AIMS := ["lock", "facing"]
const VARIANT_TAGS := ["phase1", "phase_1", "phase2", "phase_2", "buff", "rage", "furia", "potenciar_filo", "mana_shield", "skin", "grounded", "airborne", "mounted", "unmounted", "eikon"]
const SELF_WINDOW_TYPES := ["intangible", "no_turn", "fade"]
const SELF_STATUSES := ["rage", "furia", "potenciar_filo", "mana_shield", "skin", "haste", "poise_up", "sangrado", "slow", "silence", "mark"]
const SELF_STATUS_ON := ["always", "hit", "blocked", "whiff"]
const CHAIN_COST_ON := ["start", "opener_commit"]
const CHAIN_CD_ON := ["end", "chain_end"]
const CHAIN_ROLES := ["opener", "link", "finisher"]
## Origen de la habilidad. `source` ya es el programa numérico de las 45: no se reutiliza este nombre.
const ORIGINS := ["boss", "weapon"]
## Familia de animación (no es el id del arma). `cualquiera` va sola: no depende de un arma.
## `arco` y `hacha` existen porque el juego ya tiene arco, ballesta y hacha a dos manos.
const FAMILIAS := ["espada_ligera", "espada_pesada", "martillo", "lanza", "escudo", "magia", "bestia", "arco", "hacha", "cualquiera"]
## Alcance vertical (µm). ground_only: true es el atajo de 0,35 m. No hay campo air_reach.
const REACH_NONE := -1
const REACH_GROUND_UM := 350000
const REACH_JUMP_UM := 2000000
const REACH_LEVITATE_UM := 2500000
const REACH_HIGH_UM := 4500000
## V19: nombres de otras franquicias (palabras completas, minúsculas sin tildes).
const FORBIDDEN_NAMES := ["malenia", "margit", "radahn", "godfrey", "mohg", "morgott", "rennala", "rykard", "ranni",
	"godrick", "maliketh", "placidusax", "miquella", "marika", "waterfowl", "elden", "fromsoftware", "fromsoft",
	"artorias", "ornstein", "smough", "gwyn", "manus", "kalameet", "midir", "gael", "sekiro", "isshin", "genichiro",
	"bloodborne", "ludwig", "gehrman", "lorian", "lothric", "aldrich", "yhorm", "souls", "tarnished", "erdtree"]

## ------------------------------------------------------------------ API

static func load_file(path: String, opts: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		var c := Ctx.new(opts)
		c.err("", "PARSE", "no existe el archivo %s" % path)
		return c.result(null)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var c2 := Ctx.new(opts)
		c2.err("", "PARSE", "no se pudo abrir %s" % path)
		return c2.result(null)
	return load_text(f.get_as_text(), opts)

static func load_text(text: String, opts: Dictionary = {}) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		var c := Ctx.new(opts)
		c.err("", "PARSE", "JSON inválido (línea %d): %s" % [j.get_error_line(), j.get_error_message()])
		return c.result(null)
	return load_data(j.data, opts)

static func load_data(data: Variant, opts: Dictionary = {}) -> Dictionary:
	var c := Ctx.new(opts)
	if not (data is Dictionary):
		c.err("", "SCHEMA", "la raíz debe ser un objeto")
		return c.result(null)
	var baked: Variant = _catalog(c, data)
	if not c.errors.is_empty():
		return c.result(null)
	_freeze(baked)
	return c.result(baked)

## FNV-1a 32 bits sobre el texto de la estructura horneada.
## Alcance aéreo derivado: el `reach_um` más alto de las cajas. -1 = alguna caja no declara tope
## (sin ground_only y sin reach_height_m: la sim de hoy pega a cualquier altura).
## Proyectil y rayo no entran acá; los mira `answers_levitation`.
static func air_reach_um(ability: Dictionary) -> int:
	var best := 0
	var saw := false
	for st: Variant in ability.get("steps", []):
		if not (st is Dictionary):
			continue
		for hb: Variant in (st as Dictionary).get("hitboxes", []):
			if not (hb is Dictionary):
				continue
			var r := int((hb as Dictionary).get("reach_um", REACH_NONE))
			if r < 0:
				return REACH_NONE
			saw = true
			if r > best:
				best = r
	return best if saw else 0

## V20: responde a la levitación (2,5 m) por proyectil, rayo, tope declarado ≥ 2,5 m, o caja sin tope.
static func answers_levitation(ability: Dictionary) -> bool:
	var reach := air_reach_um(ability)
	if reach < 0 or reach >= REACH_LEVITATE_UM:
		return true
	for st: Variant in ability.get("steps", []):
		if not (st is Dictionary):
			continue
		for sp: Variant in (st as Dictionary).get("spawns", []):
			if not (sp is Dictionary):
				continue
			var t := int((sp as Dictionary).get("type", -1))
			if t >= 0 and t < SPAWNS.size() and (SPAWNS[t] == "projectile" or SPAWNS[t] == "beam"):
				return true
	return false

static func _weapon_ids() -> Dictionary:
	var out := {}
	for w in Catalog.weapons():
		out[String(w.id)] = true
	return out

static func checksum(baked: Variant) -> int:
	var h := 2166136261
	for b in var_to_str(baked).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h

static func format_issues(res: Dictionary) -> String:
	var out := PackedStringArray()
	for e: Dictionary in res.get("errors", []):
		out.append("ERROR   [%s] %s: %s" % [e["rule"], e["path"] if e["path"] != "" else "(raíz)", e["message"]])
	for w: Dictionary in res.get("warnings", []):
		out.append("AVISO   [%s] %s: %s" % [w["rule"], w["path"] if w["path"] != "" else "(raíz)", w["message"]])
	return "\n".join(out)

## ------------------------------------------------------------------ contexto

class Ctx extends RefCounted:
	var errors: Array = []
	var warnings: Array = []
	var opts: Dictionary
	var tele_ids: Dictionary = {} ## id -> índice global
	var tele_list: Array = []
	func _init(o: Dictionary) -> void:
		opts = o
	func err(path: String, rule: String, msg: String) -> void:
		errors.append({"path": path, "rule": rule, "message": msg})
	func warn(path: String, rule: String, msg: String) -> void:
		warnings.append({"path": path, "rule": rule, "message": msg})
	func result(baked: Variant) -> Dictionary:
		return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "baked": baked,
			"hash": AbilityCatalog.checksum(baked) if baked != null else 0}

## ------------------------------------------------------------------ lectura tipada (registra errores, nunca falla)

static func _p(base: String, key: String) -> String:
	return key if base == "" else base + "." + key

static func _is_num(v: Variant) -> bool:
	return v is int or v is float

static func _dec3(v: float) -> bool:
	if is_nan(v) or is_inf(v):
		return false
	return absf(v * 1000.0 - roundf(v * 1000.0)) < 1e-6

static func _unknown(c: Ctx, o: Dictionary, path: String, allowed: Array) -> void:
	for k: Variant in o.keys():
		if not (String(k) in allowed):
			c.warn(_p(path, String(k)), "UNKNOWN_FIELD", "campo desconocido (se ignora)")

static func _int(c: Ctx, o: Dictionary, key: String, path: String, req: bool, def: int, lo: int = -2147483648, hi: int = 2147483647) -> int:
	var p := _p(path, key)
	if not o.has(key) or o[key] == null:
		if req:
			c.err(p, "SCHEMA", "campo obligatorio")
		return def
	var v: Variant = o[key]
	if not _is_num(v):
		c.err(p, "SCHEMA", "debe ser un entero")
		return def
	var f := float(v)
	if is_nan(f) or is_inf(f) or f != floorf(f):
		c.err(p, "V09", "debe ser entero (sin decimales)")
		return def
	var i := int(f)
	if i < lo or i > hi:
		c.err(p, "SCHEMA", "fuera de rango [%d, %d]: %d" % [lo, hi, i])
		return clampi(i, lo, hi)
	return i

static func _num(c: Ctx, o: Dictionary, key: String, path: String, req: bool, def: float, lo: float = -1.0e9, hi: float = 1.0e9) -> float:
	var p := _p(path, key)
	if not o.has(key) or o[key] == null:
		if req:
			c.err(p, "SCHEMA", "campo obligatorio")
		return def
	var v: Variant = o[key]
	if not _is_num(v):
		c.err(p, "SCHEMA", "debe ser un número")
		return def
	var f := float(v)
	if not _dec3(f):
		c.err(p, "V09", "número inválido o con más de 3 decimales")
		return def
	if f < lo or f > hi:
		c.err(p, "SCHEMA", "fuera de rango [%s, %s]: %s" % [str(lo), str(hi), str(f)])
		return clampf(f, lo, hi)
	return f

static func _bool(c: Ctx, o: Dictionary, key: String, path: String, def: bool) -> bool:
	if not o.has(key) or o[key] == null:
		return def
	if not (o[key] is bool):
		c.err(_p(path, key), "SCHEMA", "debe ser true/false")
		return def
	return bool(o[key])

static func _str(c: Ctx, o: Dictionary, key: String, path: String, req: bool, def: String = "") -> String:
	var p := _p(path, key)
	if not o.has(key) or o[key] == null:
		if req:
			c.err(p, "SCHEMA", "campo obligatorio")
		return def
	if not (o[key] is String):
		c.err(p, "SCHEMA", "debe ser texto")
		return def
	if req and String(o[key]) == "":
		c.err(p, "SCHEMA", "no puede estar vacío")
	return String(o[key])

## Devuelve el índice en el enum (o el del default).
static func _enum(c: Ctx, o: Dictionary, key: String, path: String, vals: Array, req: bool, def: String = "") -> int:
	var p := _p(path, key)
	if not o.has(key) or o[key] == null:
		if req:
			c.err(p, "SCHEMA", "campo obligatorio (uno de %s)" % ", ".join(PackedStringArray(vals)))
		return maxi(vals.find(def), 0)
	var v: Variant = o[key]
	if not (v is String) or not (String(v) in vals):
		c.err(p, "SCHEMA", "valor inválido %s (uno de %s)" % [str(v), ", ".join(PackedStringArray(vals))])
		return maxi(vals.find(def), 0)
	return vals.find(String(v))

static func _obj(c: Ctx, o: Dictionary, key: String, path: String, req: bool) -> Variant:
	if not o.has(key) or o[key] == null:
		if req:
			c.err(_p(path, key), "SCHEMA", "campo obligatorio (objeto)")
		return null
	if not (o[key] is Dictionary):
		c.err(_p(path, key), "SCHEMA", "debe ser un objeto")
		return null
	return o[key]

static func _arr(c: Ctx, o: Dictionary, key: String, path: String, req: bool) -> Array:
	if not o.has(key) or o[key] == null:
		if req:
			c.err(_p(path, key), "SCHEMA", "campo obligatorio (lista)")
		return []
	if not (o[key] is Array):
		c.err(_p(path, key), "SCHEMA", "debe ser una lista")
		return []
	return o[key]

## Lista de enums -> máscara de bits.
static func _mask(c: Ctx, o: Dictionary, key: String, path: String, vals: Array, def: Array) -> int:
	var src: Array = def
	if o.has(key) and o[key] != null:
		src = _arr(c, o, key, path, false)
	var m := 0
	for i in src.size():
		var v: Variant = src[i]
		if not (v is String) or not (String(v) in vals):
			c.err("%s[%d]" % [_p(path, key), i], "SCHEMA", "valor inválido %s (uno de %s)" % [str(v), ", ".join(PackedStringArray(vals))])
			continue
		m |= 1 << vals.find(String(v))
	return m

## ------------------------------------------------------------------ conversiones (convenciones de SimParams)

static func milli(v: float) -> int: return int(round(v * 1000.0))
static func um(m: float) -> int: return int(round(m * 1000000.0))
static func upt(mps: float) -> int: return int(round(mps * 1000000.0 / TICK_RATE)) ## µm/tick
static func pm(pct: int) -> int: return pct * 10 ## % -> ‰
static func heading(deg: float) -> int: return int(round(deg * 256.0 / 360.0)) ## rumbo (256 por vuelta), con signo
static func turn_mrh(deg_s: float) -> int: return int(round(deg_s / TICK_RATE * 256000.0 / 360.0)) ## mili-rumbos/tick
static func cdeg(deg: float) -> int: return int(round(deg * 100.0)) ## centi-grados
static func cdeg_pt(deg_s: float) -> int: return int(round(deg_s * 100.0 / TICK_RATE)) ## centi-grados/tick
static func cos_half(total_deg: float) -> int: return int(round(cos(deg_to_rad(minf(total_deg * 0.5, 180.0))) * FxMath.ONE))

static func _color(c: Ctx, o: Dictionary, path: String) -> int:
	var s := _str(c, o, "color", path, true)
	if s.length() != 7 or not s.begins_with("#") or not s.substr(1).is_valid_hex_number(false):
		if s != "":
			c.err(_p(path, "color"), "SCHEMA", "color debe ser #RRGGBB")
		return 0
	return s.substr(1).hex_to_int()

static func _asset(c: Ctx, o: Dictionary, key: String, path: String, kind: String) -> String:
	## Ids de vfx/sfx: si hay registro (opts.known_vfx / known_sfx) y no está → aviso + "generic".
	if not o.has(key) or o[key] == null:
		return ""
	if not (o[key] is String):
		c.err(_p(path, key), "SCHEMA", "debe ser texto o null")
		return ""
	var s := String(o[key])
	var reg: Variant = c.opts.get("known_" + kind, null)
	if reg is Array and not (s in reg):
		c.warn(_p(path, key), "ASSET", "%s «%s» no registrado: se usa el genérico" % [kind, s])
		return "generic"
	return s

static func _icon(c: Ctx, o: Dictionary, key: String, path: String, req: bool) -> String:
	var s := _str(c, o, key, path, req)
	if s == "" or s == "generic" or s.begins_with("boss:"):
		return "generic" if s == "" else s
	if s.begins_with("res://"):
		if not bool(c.opts.get("skip_asset_files", false)) and not ResourceLoader.exists(s) and not FileAccess.file_exists(s):
			c.warn(_p(path, key), "ASSET", "icono %s no existe: se usa el genérico" % s)
			return "generic"
		return s
	c.warn(_p(path, key), "ASSET", "icono «%s» no es res://, «generic» ni «boss:<id>»: se usa el genérico" % s)
	return "generic"

static func _cost(c: Ctx, o: Variant, path: String) -> Dictionary:
	var d: Dictionary = o if o is Dictionary else {}
	_unknown(c, d, path, ["stamina", "mana", "health"])
	return {"stamina": milli(_num(c, d, "stamina", path, false, 0.0, 0.0, 1000.0)),
		"mana": milli(_num(c, d, "mana", path, false, 0.0, 0.0, 1000.0)),
		"health": milli(_num(c, d, "health", path, false, 0.0, 0.0, 1000.0))}

static func _offset(c: Ctx, o: Dictionary, path: String) -> Array:
	var d: Variant = _obj(c, o, "offset", path, false)
	if d == null:
		return [0, 0]
	var p := _p(path, "offset")
	_unknown(c, d, p, ["forward_m", "right_m"])
	return [um(_num(c, d, "forward_m", p, false, 0.0, -20.0, 20.0)), um(_num(c, d, "right_m", p, false, 0.0, -20.0, 20.0))]

static func _shape(c: Ctx, o: Dictionary, key: String, path: String, req: bool) -> Variant:
	var d: Variant = _obj(c, o, key, path, req)
	if d == null:
		return null
	var p := _p(path, key)
	var t := _enum(c, d, "type", p, SHAPES, true)
	var out := {"type": t, "r": 0, "cos_half": 0, "len": 0, "w": 0, "inner": 0, "outer": 0}
	match SHAPES[t]:
		"circle":
			_unknown(c, d, p, ["type", "radius_m"])
			out["r"] = um(_num(c, d, "radius_m", p, true, 1.0, 0.05, 20.0))
		"arc":
			_unknown(c, d, p, ["type", "radius_m", "angle_deg"])
			out["r"] = um(_num(c, d, "radius_m", p, true, 1.0, 0.05, 20.0))
			out["cos_half"] = cos_half(_num(c, d, "angle_deg", p, true, 90.0, 1.0, 360.0))
		"line", "box":
			_unknown(c, d, p, ["type", "length_m", "width_m"])
			out["len"] = um(_num(c, d, "length_m", p, true, 1.0, 0.05, 40.0))
			out["w"] = um(_num(c, d, "width_m", p, true, 1.0, 0.05, 20.0))
		"ring":
			_unknown(c, d, p, ["type", "inner_m", "outer_m"])
			var a := _num(c, d, "inner_m", p, true, 0.0, 0.0, 20.0)
			var b := _num(c, d, "outer_m", p, true, 1.0, 0.05, 20.0)
			if b <= a:
				c.err(_p(p, "outer_m"), "SCHEMA", "outer_m debe ser mayor que inner_m")
			out["inner"] = um(a)
			out["outer"] = um(b)
	return out

static func _range(c: Ctx, o: Dictionary, path: String, lo: int, hi: int, base: String) -> Array:
	## V08: [from, to) dentro de [lo, hi], from < to.
	var a := _int(c, o, "from_tick", path, true, 0)
	var b := _int(c, o, "to_tick", path, true, 0)
	if a < lo or b > hi or a >= b:
		c.err(path, "V08", "intervalo [%d, %d) fuera de %s [%d, %d] o vacío" % [a, b, base, lo, hi])
	return [a, b]

## ------------------------------------------------------------------ catálogo

static func _catalog(c: Ctx, d: Dictionary) -> Variant:
	_unknown(c, d, "", ["version", "tick_rate", "abilities", "presets"])
	var ver := _int(c, d, "version", "", true, 1)
	if ver < 1:
		c.err("version", "V01", "version debe ser ≥ 1")
	var tr := _int(c, d, "tick_rate", "", true, TICK_RATE)
	if d.has("tick_rate") and tr != TICK_RATE:
		c.err("tick_rate", "V01", "tick_rate debe ser 60")
	var src := _arr(c, d, "abilities", "", true)
	# Primera pasada: ids de habilidad (V02) y telegrafías globales (V03).
	var index := {}
	for i in src.size():
		var a: Variant = src[i]
		if a is Dictionary and a.get("id") is String:
			var id := String(a["id"])
			if index.has(id):
				c.err("abilities[%d].id" % i, "V02", "id de habilidad repetido «%s»" % id)
			else:
				index[id] = i
	var abilities: Array = []
	var colors: Array = [] ## por habilidad: [{color, sound}]
	for i in src.size():
		var p := "abilities[%d]" % i
		if not (src[i] is Dictionary):
			c.err(p, "SCHEMA", "debe ser un objeto")
			abilities.append({})
			colors.append([])
			continue
		var tl: Array = []
		abilities.append(_ability(c, src[i], p, i, tl))
		colors.append(tl)
	# Presets (V14, V15, V03 color/sonido)
	var presets: Array = []
	var pids := {}
	var third := {}
	var psrc := _arr(c, d, "presets", "", false)
	for i in psrc.size():
		var p := "presets[%d]" % i
		if not (psrc[i] is Dictionary):
			c.err(p, "SCHEMA", "debe ser un objeto")
			continue
		var pr: Dictionary = psrc[i]
		_unknown(c, pr, p, ["id", "name", "abilities", "notes"])
		var pid := _str(c, pr, "id", p, true)
		if pid != "" and pids.has(pid):
			c.err(_p(p, "id"), "V02", "id de preset repetido «%s»" % pid)
		pids[pid] = true
		var pname := _str(c, pr, "name", p, true)
		_names(c, p, [pid, pname])
		var ids := _arr(c, pr, "abilities", p, true)
		if ids.size() < 1 or ids.size() > 3:
			c.err(_p(p, "abilities"), "V14", "un preset lleva de 1 a 3 habilidades (tiene %d)" % ids.size())
		var idx: Array[int] = []
		var seen := {}
		for k in ids.size():
			var q := "%s.abilities[%d]" % [p, k]
			if not (ids[k] is String) or not index.has(String(ids[k])):
				c.err(q, "V14", "habilidad inexistente %s" % str(ids[k]))
				continue
			var ai: int = index[String(ids[k])]
			if seen.has(ai):
				c.err(q, "V14", "habilidad repetida en el preset")
			seen[ai] = true
			idx.append(ai)
			if k == 2:
				third[ai] = true
		# V03: color y sonido de aviso distintos entre habilidades del preset
		for x in idx.size():
			for y in range(x + 1, idx.size()):
				for tx: Dictionary in colors[idx[x]]:
					for ty: Dictionary in colors[idx[y]]:
						if tx["color"] == ty["color"]:
							c.err(p, "V03", "«%s» y «%s» comparten color de aviso" % [ids[x], ids[y]])
						if tx["sound"] == ty["sound"]:
							c.err(p, "V03", "«%s» y «%s» comparten sonido de aviso" % [ids[x], ids[y]])
		presets.append({"index": presets.size(), "id": pid, "name": pname, "abilities": idx})
		# V49: máximo 1 habilidad con phase_transition por preset
		var pt_count := 0
		for ai_pt: int in idx:
			if ai_pt >= 0 and ai_pt < abilities.size() and abilities[ai_pt] is Dictionary and (abilities[ai_pt] as Dictionary).has("phase_transition"):
				pt_count += 1
		if pt_count > 1:
			c.err(p, "V49", "máximo 1 habilidad con phase_transition por preset (tiene %d)" % pt_count)
		# V20: advertencia de justicia. Cada preset necesita una respuesta a 2,5 m.
		var answers := false
		for ai: int in idx:
			if ai >= 0 and ai < abilities.size() and abilities[ai] is Dictionary and answers_levitation(abilities[ai]):
				answers = true
				break
		if not idx.is_empty() and not answers:
			c.warn(p, "V20", "ninguna habilidad alcanza 2,5 m (proyectil, rayo o reach_height_m)")
	# V15: fase 2 solo tiene sentido en el 3.er lugar de un preset
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		if int(a.get("unlock_phase", 1)) == 2 and not third.has(i):
			c.warn("abilities[%d].unlock.phase" % i, "V15", "unlock.phase 2 pero no está en el 3.er lugar de ningún preset")
	var ab_index := {}
	for k: String in index:
		ab_index[k] = index[k]
	return {"version": ver, "tick_rate": TICK_RATE, "global_cd": GLOBAL_CD_TICKS, "abilities": abilities,
		"presets": presets, "ability_index": ab_index, "telegraphs": c.tele_list.duplicate()}

static func _names(c: Ctx, path: String, texts: Array) -> void:
	for t: Variant in texts:
		var s := String(t).to_lower()
		for a in ["á", "é", "í", "ó", "ú", "ü", "ñ"]:
			s = s.replace(a, ["a", "e", "i", "o", "u", "u", "n"][["á", "é", "í", "ó", "ú", "ü", "ñ"].find(a)])
		var words := PackedStringArray()
		var cur := ""
		for ch in s:
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
				cur += ch
			else:
				if cur != "": words.append(cur)
				cur = ""
		if cur != "": words.append(cur)
		for w in words:
			if w in FORBIDDEN_NAMES:
				c.err(path, "V19", "nombre de otra franquicia: «%s»" % w)

## ------------------------------------------------------------------ habilidad

static func _ability(c: Ctx, a: Dictionary, p: String, ai: int, tl: Array) -> Dictionary:
	_unknown(c, a, p, ["id", "name", "icon", "category", "tags", "unlock", "cost", "cooldown_ticks", "uses_global_cd",
		"global_cd_on_repeat", "spameable", "familias", "usable_while", "interruptible_by", "interrupt_priority", "on_interrupt", "entry_step", "steps", "ai", "hint", "source",
		"origin", "requires_weapon", "cost_at_tick", "phase_transition", "chain"])
	if a.has("source") and not (a["source"] is Dictionary):
		c.err(_p(p, "source"), "SCHEMA", "source debe ser un objeto (el programa numérico). El origen va en origin")
	var origin := _enum(c, a, "origin", p, ORIGINS, false, "boss")
	var weapons: Array = []
	var wsrc := _arr(c, a, "requires_weapon", p, false)
	var known := _weapon_ids()
	for i in wsrc.size():
		if not (wsrc[i] is String) or String(wsrc[i]) == "":
			c.err("%s.requires_weapon[%d]" % [p, i], "SCHEMA", "id de arma vacío")
			continue
		var wid := String(wsrc[i])
		if weapons.has(wid):
			c.err("%s.requires_weapon[%d]" % [p, i], "SCHEMA", "arma repetida «%s»" % wid)
			continue
		if not known.has(wid):
			c.err("%s.requires_weapon[%d]" % [p, i], "SCHEMA", "arma inexistente «%s»" % wid)
		weapons.append(wid)
	if origin == ORIGINS.find("weapon") and weapons.is_empty():
		c.err(_p(p, "requires_weapon"), "SCHEMA", "una habilidad de arma necesita requires_weapon")
	if origin != ORIGINS.find("weapon") and not weapons.is_empty():
		c.err(_p(p, "requires_weapon"), "SCHEMA", "requires_weapon solo vale con origin weapon")
	var id := _str(c, a, "id", p, true)
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]{2,31}$")
	if id != "" and re.search(id) == null:
		c.err(_p(p, "id"), "SCHEMA", "id debe cumplir ^[a-z][a-z0-9_]{2,31}$")
	var name := _str(c, a, "name", p, true)
	_names(c, p, [id, name])
	var icon := _icon(c, a, "icon", p, true)
	var cat := _enum(c, a, "category", p, CATEGORIES, true)
	var tags: Array[String] = []
	var tsrc := _arr(c, a, "tags", p, false)
	for i in tsrc.size():
		if not (tsrc[i] is String):
			c.err("%s.tags[%d]" % [p, i], "SCHEMA", "debe ser texto")
			continue
		if not (String(tsrc[i]) in KNOWN_TAGS):
			c.warn("%s.tags[%d]" % [p, i], "UNKNOWN_TAG", "etiqueta desconocida «%s»" % tsrc[i])
		tags.append(String(tsrc[i]))
	var unlock: Variant = _obj(c, a, "unlock", p, false)
	var phase := 1
	if unlock != null:
		_unknown(c, unlock, _p(p, "unlock"), ["phase"])
		phase = _int(c, unlock, "phase", _p(p, "unlock"), false, 1, 1, 2)
	var cost := _cost(c, _obj(c, a, "cost", p, true), _p(p, "cost"))
	if a.get("cost") is Dictionary and cost["stamina"] <= 0 and cost["mana"] <= 0 and cost["health"] <= 0:
		c.err(_p(p, "cost"), "V10", "al menos un costo debe ser > 0")
	var cd := _int(c, a, "cooldown_ticks", p, true, 0, 0, 36000)
	var gcd := _bool(c, a, "uses_global_cd", p, true)
	## spameable (autor) = se puede repetir sin la global y la pulsación tras el disparo queda en cola.
	## Se hornea en el mismo bit que global_cd_on_repeat (invertido): la sim no cambia de protocolo.
	var spam_set := a.has("spameable") and a["spameable"] != null
	var spam := _bool(c, a, "spameable", p, false)
	var gcd_set := a.has("global_cd_on_repeat") and a["global_cd_on_repeat"] != null
	var gcd_rep := _bool(c, a, "global_cd_on_repeat", p, true)
	if spam_set and gcd_set and spam == gcd_rep:
		c.err(_p(p, "spameable"), "SCHEMA", "spameable y global_cd_on_repeat se contradicen")
	if spam_set:
		gcd_rep = not spam
	var familias := _familias(c, a, p)
	var usable := _mask(c, a, "usable_while", p, USABLE, ["ground"])
	var intr := _mask(c, a, "interruptible_by", p, INTERRUPTS, DEFAULT_INTERRUPTS)
	var iprio := _int(c, a, "interrupt_priority", p, false, 0, -100, 100)
	var oi: Variant = _obj(c, a, "on_interrupt", p, false)
	var oid: Dictionary = oi if oi != null else {}
	var oip := _p(p, "on_interrupt")
	_unknown(c, oid, oip, ["recovery_ticks", "cancel_spawns", "cooldown", "refund_pct"])
	var on_int := {"recovery": _int(c, oid, "recovery_ticks", oip, false, 0, 0, 600),
		"cancel_spawns": _bool(c, oid, "cancel_spawns", oip, true),
		"cooldown": _enum(c, oid, "cooldown", oip, OI_COOLDOWN, false, "full"),
		"refund_pm": pm(_int(c, oid, "refund_pct", oip, false, 0, 0, 100))}
	# Pasos
	var ssrc := _arr(c, a, "steps", p, true)
	if a.get("steps") is Array and (ssrc.size() < 1 or ssrc.size() > MAX_STEPS):
		c.err(_p(p, "steps"), "SCHEMA", "una habilidad lleva de 1 a %d pasos (tiene %d)" % [MAX_STEPS, ssrc.size()])
	var sidx := {}
	var any_trail := false
	for i in ssrc.size():
		if ssrc[i] is Dictionary:
			if (ssrc[i] as Dictionary).has("weapon_trail"):
				any_trail = true
			if ssrc[i].get("id") is String:
				var sid := String(ssrc[i]["id"])
				if sidx.has(sid):
					c.err("%s.steps[%d].id" % [p, i], "V02", "id de paso repetido «%s»" % sid)
				else:
					sidx[sid] = i
	var entry := 0
	if a.has("entry_step") and a["entry_step"] != null:
		var es := _str(c, a, "entry_step", p, false)
		if not sidx.has(es):
			c.err(_p(p, "entry_step"), "V04", "entry_step «%s» no existe" % es)
		else:
			entry = sidx[es]
	# Etapa 7d: chain (validación previa para pasar flag a los pasos)
	var has_chain := a.has("chain") and a["chain"] != null
	var chain_out: Variant = null
	if has_chain:
		var chsrc: Variant = _obj(c, a, "chain", p, false)
		if chsrc != null:
			var chp := _p(p, "chain")
			_unknown(c, chsrc, chp, ["cost_on", "cooldown_on", "max_links"])
			var cost_on_s := String(chsrc.get("cost_on", "start"))
			var cd_on_s := String(chsrc.get("cooldown_on", "chain_end"))
			if not (cost_on_s in CHAIN_COST_ON):
				c.err(_p(chp, "cost_on"), "V50", "chain.cost_on debe ser start u opener_commit")
				cost_on_s = "start"
			if not (cd_on_s in CHAIN_CD_ON):
				c.err(_p(chp, "cooldown_on"), "V50", "chain.cooldown_on debe ser end o chain_end")
				cd_on_s = "chain_end"
			var mlinks := _int(c, chsrc, "max_links", chp, false, 2, -100, 100)
			if mlinks < 1 or mlinks > 3:
				c.err(_p(chp, "max_links"), "V52", "chain.max_links debe estar en 1..3")
				mlinks = clampi(mlinks, 1, 3)
			chain_out = {"cost_on": CHAIN_COST_ON.find(cost_on_s), "cooldown_on": CHAIN_CD_ON.find(cd_on_s), "max_links": mlinks}
	var e0 := c.errors.size()
	var tags_ms := "mana_shield" in tags
	var ev_ids := {}
	var steps: Array = []
	for i in ssrc.size():
		var sp := "%s.steps[%d]" % [p, i]
		if not (ssrc[i] is Dictionary):
			c.err(sp, "SCHEMA", "debe ser un objeto")
			steps.append({})
			continue
		steps.append(_step(c, ssrc[i], sp, i, sidx, i == entry, tags_ms, ev_ids, tl, cat, any_trail, has_chain))
	# Etapa 7: cost_at_tick a nivel habilidad
	var ab_cost_at := -1
	if a.has("cost_at_tick") and a["cost_at_tick"] != null:
		var entry_tot: int = int((steps[entry] as Dictionary).get("total", 0)) if entry < steps.size() and steps[entry] is Dictionary else 0
		ab_cost_at = _int(c, a, "cost_at_tick", p, false, 0, -3600, 36000)
		if ab_cost_at < 0 or ab_cost_at >= entry_tot:
			c.err(_p(p, "cost_at_tick"), "V35", "cost_at_tick fuera de la duración del paso inicial [0, %d)" % entry_tot)
	# Etapa 7c: phase_transition a nivel habilidad (V49)
	var pt_out: Variant = null
	if a.has("phase_transition") and a["phase_transition"] != null:
		var ptsrc: Variant = _obj(c, a, "phase_transition", p, false)
		if ptsrc != null:
			var ptp := _p(p, "phase_transition")
			_unknown(c, ptsrc, ptp, ["on_phase", "entry_step", "self_invuln", "skip_global_cd"])
			var on_ph := _int(c, ptsrc, "on_phase", ptp, true, 2, -10, 10)
			if on_ph != 2:
				c.err(_p(ptp, "on_phase"), "V49", "phase_transition.on_phase debe ser 2")
			var pt_es := _str(c, ptsrc, "entry_step", ptp, true)
			var pt_idx := -1
			if not sidx.has(pt_es):
				c.err(_p(ptp, "entry_step"), "V49", "phase_transition.entry_step «%s» no existe" % pt_es)
			else:
				pt_idx = int(sidx[pt_es])
			pt_out = {
				"on_phase": on_ph,
				"entry": pt_idx,
				"self_invuln": 1 if _bool(c, ptsrc, "self_invuln", ptp, true) else 0,
				"skip_global_cd": 1 if _bool(c, ptsrc, "skip_global_cd", ptp, true) else 0,
			}
	# AI
	var aisrc: Variant = _obj(c, a, "ai", p, true)
	var aiout := {"range_min": 0, "range_max": 0, "weight": 10, "use_when": 0, "branch_weights": []}
	if aisrc != null:
		var ap := _p(p, "ai")
		_unknown(c, aisrc, ap, ["range_min", "range_max", "weight", "use_when", "branch_weights", "chain_continue_pct"])
		var rmin := _num(c, aisrc, "range_min", ap, false, 0.0, 0.0, 80.0)
		var rmax := _num(c, aisrc, "range_max", ap, true, 0.0, 0.0, 80.0)
		if rmax < rmin:
			c.err(_p(ap, "range_max"), "SCHEMA", "range_max debe ser ≥ range_min")
		aiout["range_min"] = um(rmin)
		aiout["range_max"] = um(rmax)
		aiout["weight"] = _int(c, aisrc, "weight", ap, false, 10, 1, 100)
		aiout["use_when"] = _mask(c, aisrc, "use_when", ap, USE_WHEN, ["target_in_range"])
		var bw: Variant = _obj(c, aisrc, "branch_weights", ap, false)
		if bw != null:
			var pairs: Array = []
			for k: Variant in bw.keys():
				var q := "%s.branch_weights.%s" % [ap, k]
				if not sidx.has(String(k)):
					c.err(q, "V04", "paso inexistente en branch_weights")
					continue
				pairs.append([int(sidx[String(k)]), _int(c, bw, String(k), _p(ap, "branch_weights"), true, 1, 0, 100)])
			pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			aiout["branch_weights"] = pairs
		if aisrc.has("chain_continue_pct") and aisrc["chain_continue_pct"] != null:
			aiout["chain_continue_pct"] = _int(c, aisrc, "chain_continue_pct", ap, false, 100, 0, 100)
	# hint: solo IA/tutorial; se valida suave y no se hornea para la sim
	var hint: Variant = _obj(c, a, "hint", p, false)
	if hint != null:
		var hp := _p(p, "hint")
		_unknown(c, hint, hp, ["dodge", "direction", "text"])
		if hint.has("dodge") and not (str(hint["dodge"]) in HINT_DODGE):
			c.warn(_p(hp, "dodge"), "HINT", "hint.dodge desconocido")
		if hint.has("direction") and not (str(hint["direction"]) in HINT_DIR):
			c.warn(_p(hp, "direction"), "HINT", "hint.direction desconocido")
	if not steps.is_empty():
		_chain_and_pt_rules(c, p, a, steps, entry, ssrc, chain_out, pt_out)
	if c.errors.size() == e0 and not steps.is_empty():
		_graph(c, p, steps, entry, ssrc, pt_out)
		_ability_rules(c, p, a, steps, intr, ssrc)
	else:
		for s_clean: Variant in steps:
			if s_clean is Dictionary:
				(s_clean as Dictionary).erase("_succ")
				(s_clean as Dictionary).erase("_can_end")
				(s_clean as Dictionary).erase("_terminal")
	var ab_res := {"index": ai, "id": id, "name": name, "icon": icon, "category": cat, "tags": tags, "unlock_phase": phase,
		"cost": cost, "cooldown": cd, "uses_global_cd": 1 if gcd else 0, "global_cd_on_repeat": 1 if gcd_rep else 0,
		"spameable": 1 if not gcd_rep else 0, "familias": familias, "usable_mask": usable, "interrupt_mask": intr,
		"interrupt_priority": iprio, "on_interrupt": on_int, "entry": entry, "steps": steps, "ai": aiout,
		"origin": origin, "requires_weapon": weapons}
	if ab_cost_at >= 0:
		ab_res["cost_at_tick"] = ab_cost_at
	if pt_out != null:
		ab_res["phase_transition"] = pt_out
	if chain_out != null:
		ab_res["chain"] = chain_out
	return ab_res

## Validaciones de Etapa 7c (phase_transition V49) y Etapa 7d (chain V50..V54).
static func _chain_and_pt_rules(c: Ctx, p: String, a: Dictionary, steps: Array, entry: int, ssrc: Array, chain_out: Variant, pt_out: Variant) -> void:
	var n := steps.size()
	var edges: Array = []
	var in_deg: Array[int] = []
	for i in n:
		in_deg.append(0)
		var succ_i: Array = (steps[i] as Dictionary).get("_succ", []) if steps[i] is Dictionary else []
		edges.append(succ_i)
	for i in n:
		for y: int in edges[i]:
			if y >= 0 and y < n:
				in_deg[y] += 1
	# V49: duración máxima de la secuencia de phase_transition (> 600 ticks → aviso)
	if pt_out is Dictionary:
		var pt_entry := int((pt_out as Dictionary).get("entry", -1))
		if pt_entry >= 0 and pt_entry < n:
			var dur_pt := _max_path_ticks(steps, edges, pt_entry, {})
			if dur_pt > 600:
				c.warn(_p(p, "phase_transition"), "V49", "secuencia de phase_transition dura %d ticks (> 600)" % dur_pt)
	# V51: pasos con chain_role link/finisher solo alcanzables desde la misma habilidad y nunca entry_step
	for i in n:
		if not (steps[i] is Dictionary):
			continue
		var st_i: Dictionary = steps[i]
		if not st_i.has("chain_role"):
			continue
		var role_idx := int(st_i["chain_role"])
		if role_idx < 0 or role_idx >= CHAIN_ROLES.size():
			continue
		var rname: String = CHAIN_ROLES[role_idx]
		if rname in ["link", "finisher"]:
			if i == entry or in_deg[i] == 0 or chain_out == null:
				c.err("%s.steps[%d].chain_role" % [p, i], "V51", "paso %s no puede ser entry_step y debe ser alcanzable dentro de una habilidad con chain" % rname)
	if chain_out is Dictionary:
		var chd: Dictionary = chain_out
		var mlinks := int(chd["max_links"])
		# V50: entry_step debe tener chain_role == "opener" y definir combo_input_windows o branch
		var op_st: Dictionary = steps[entry] if entry >= 0 and entry < n and steps[entry] is Dictionary else {}
		var op_role := int(op_st.get("chain_role", -1))
		var has_combo_win := op_st.get("branch", null) != null or not (op_st.get("combo_input_windows", []) as Array).is_empty()
		if op_role != CHAIN_ROLES.find("opener") or not has_combo_win:
			c.err(_p(p, "chain"), "V50", "chain requiere que entry_step tenga chain_role='opener' y defina combo_input_windows o branch")
		# V52: largo máximo alcanzable <= max_links y sin ciclos
		var cyc_info := _chain_max_links(edges, entry, {})
		if bool(cyc_info["cycle"]) or int(cyc_info["max_links"]) > mlinks:
			c.err(_p(p, "chain"), "V52", "cadena con ciclo o largo máximo (%d) > max_links (%d)" % [int(cyc_info["max_links"]), mlinks])
		# V53: abridor <= 2 golpes activos (error) y windup+active <= 90 ticks (aviso)
		var op_hbs: Array = op_st.get("hitboxes", [])
		if op_hbs.size() > 2:
			c.err("%s.steps[%d].hitboxes" % [p, entry], "V53", "el abridor (opener) tiene %d golpes activos (máximo 2)" % op_hbs.size())
		var op_wa := int(op_st.get("windup", 0)) + int(op_st.get("active", 0))
		if op_wa > 90:
			c.warn("%s.steps[%d]" % [p, entry], "V53", "abridor con windup_ticks + active_ticks = %d (> 90)" % op_wa)
		# V54: aviso si la ventana de combo abre < 6 ticks después del último tick activo, o continuación imbloqueable sin telegraph
		for i in n:
			if not (steps[i] is Dictionary):
				continue
			var st_i: Dictionary = steps[i]
			var wu_i := int(st_i.get("windup", 0))
			var last_act := -1
			var unbl_i := false
			for hb_v: Variant in st_i.get("hitboxes", []):
				if hb_v is Dictionary:
					var hb_d: Dictionary = hb_v
					last_act = maxi(last_act, wu_i + int(hb_d.get("to", 0)))
					if int(hb_d.get("blockable", 1)) == 0:
						unbl_i = true
			if last_act >= 0:
				var br_v: Variant = st_i.get("branch", null)
				if br_v is Dictionary and int((br_v as Dictionary).get("from", 99999)) < last_act + 6:
					c.warn("%s.steps[%d].branch" % [p, i], "V54", "ventana de combo abre < 6 ticks después del último tick activo (%d < %d)" % [int((br_v as Dictionary)["from"]), last_act + 6])
				for cw_v: Variant in st_i.get("combo_input_windows", []):
					if cw_v is Dictionary and int((cw_v as Dictionary).get("from", 99999)) < last_act + 6:
						c.warn("%s.steps[%d].combo_input_windows" % [p, i], "V54", "ventana de combo abre < 6 ticks después del último tick activo (%d < %d)" % [int((cw_v as Dictionary)["from"]), last_act + 6])
			if i != entry and unbl_i and st_i.get("telegraph", null) == null:
				c.warn("%s.steps[%d].telegraph" % [p, i], "V54", "continuación imbloqueable sin telegraph propio")

static func _max_path_ticks(steps: Array, edges: Array, u: int, visiting: Dictionary) -> int:
	if u < 0 or u >= steps.size() or visiting.has(u):
		return 0
	var v2 := visiting.duplicate()
	v2[u] = true
	var my_tot := int((steps[u] as Dictionary).get("total", 0)) if steps[u] is Dictionary else 0
	var best := 0
	for nxt: int in edges[u]:
		if nxt >= 0 and nxt < steps.size():
			best = maxi(best, _max_path_ticks(steps, edges, nxt, v2))
	return my_tot + best

static func _chain_max_links(edges: Array, u: int, visiting: Dictionary) -> Dictionary:
	if u < 0 or u >= edges.size():
		return {"cycle": false, "max_links": 0}
	if visiting.has(u):
		return {"cycle": true, "max_links": 999}
	var v2 := visiting.duplicate()
	v2[u] = true
	var best := 0
	var cyc := false
	for nxt: int in edges[u]:
		if nxt >= 0 and nxt < edges.size():
			var sub := _chain_max_links(edges, nxt, v2)
			if bool(sub["cycle"]):
				cyc = true
			best = maxi(best, 1 + int(sub["max_links"]))
	return {"cycle": cyc, "max_links": best}

## Familias de animación. Vacío = sin filtro (catálogos viejos). `cualquiera` no se mezcla.
static func _familias(c: Ctx, a: Dictionary, p: String) -> Array:
	if not a.has("familias") or a["familias"] == null:
		return []
	var src := _arr(c, a, "familias", p, false)
	var out: Array = []
	var bad := 0
	for i in src.size():
		var v: Variant = src[i]
		if not (v is String) or not (String(v) in FAMILIAS):
			c.err("%s.familias[%d]" % [p, i], "SCHEMA", "familia inválida %s (una de %s)" % [str(v), ", ".join(PackedStringArray(FAMILIAS))])
			bad += 1
			continue
		if out.has(String(v)):
			c.err("%s.familias[%d]" % [p, i], "SCHEMA", "familia repetida «%s»" % String(v))
			continue
		out.append(String(v))
	if out.is_empty() and bad == 0:
		c.err(_p(p, "familias"), "SCHEMA", "la lista de familias no puede estar vacía")
	elif out.has("cualquiera") and out.size() > 1:
		c.err(_p(p, "familias"), "SCHEMA", "cualquiera va sola: no depende de un arma")
	return out

## Grafo de pasos: alcanzabilidad (V05), ciclos con max_loops (V05), terminales con recuperación (V06).
static func _graph(c: Ctx, p: String, steps: Array, entry: int, ssrc: Array, pt_out: Variant = null) -> void:
	var n := steps.size()
	var edges: Array = []
	for i in n:
		edges.append((steps[i] as Dictionary).get("_succ", []))
	var seen := {}
	var stack: Array[int] = [entry]
	if pt_out is Dictionary and int((pt_out as Dictionary).get("entry", -1)) >= 0:
		stack.append(int((pt_out as Dictionary)["entry"]))
	while not stack.is_empty():
		var x: int = stack.pop_back()
		if seen.has(x): continue
		seen[x] = true
		for y: int in edges[x]:
			if y >= 0: stack.append(y)
	for i in n:
		if not seen.has(i):
			c.err("%s.steps[%d]" % [p, i], "V05", "paso inalcanzable desde entry_step")
	# Ciclos: un paso en un ciclo (alcanza a sí mismo) necesita max_loops
	for i in n:
		var vis := {}
		var st: Array[int] = []
		for y: int in edges[i]:
			if y >= 0: st.append(y)
		var cyc := false
		while not st.is_empty():
			var x: int = st.pop_back()
			if x == i:
				cyc = true
				break
			if vis.has(x): continue
			vis[x] = true
			for y: int in edges[x]:
				if y >= 0: st.append(y)
		if cyc and int(steps[i].get("max_loops", 0)) <= 0:
			c.err("%s.steps[%d]" % [p, i], "V05", "el paso forma un ciclo y no tiene max_loops")
	for i in n:
		var s: Dictionary = steps[i]
		if bool(s.get("_can_end", false)) and int(s["recovery"]) < MIN_FINAL_RECOVERY:
			c.err("%s.steps[%d].recovery_ticks" % [p, i], "V06", "paso que puede terminar la habilidad: recovery_ticks ≥ %d" % MIN_FINAL_RECOVERY)
	for s: Dictionary in steps:
		s.erase("_succ")
		s.erase("_can_end")

static func _ability_rules(c: Ctx, p: String, a: Dictionary, steps: Array, intr: int, ssrc: Array) -> void:
	# V17: peor caso de piscinas (suma de todos los spawns de la habilidad)
	var proj := 0
	var haz := 0
	for s: Dictionary in steps:
		for sp: Dictionary in s["spawns"]:
			var t: String = SPAWNS[int(sp["type"])]
			if t == "projectile": proj += int(sp["count"])
			elif t in HAZARD_SPAWNS: haz += int(sp["count"])
	if proj > MAX_PROJECTILES:
		c.err(p, "V17", "hasta %d proyectiles simultáneos (peor caso %d)" % [MAX_PROJECTILES, proj])
	if haz > MAX_HAZARDS:
		c.err(p, "V17", "hasta %d peligros simultáneos (peor caso %d)" % [MAX_HAZARDS, haz])
	# Lista vacía = no se corta (solo se esquiva). No exige hiperarmadura.
	for s: Dictionary in steps:
		s.erase("_terminal")

## ------------------------------------------------------------------ paso

static func _ref(c: Ctx, v: Variant, path: String, sidx: Dictionary) -> int:
	## Referencia a paso: string existente, null o "end" (= -1).
	if v == null or (v is String and String(v) == "end"):
		return -1
	if not (v is String) or not sidx.has(String(v)):
		c.err(path, "V04", "referencia a paso inexistente %s" % str(v))
		return -1
	return int(sidx[String(v)])

static func _movement_seg(c: Ctx, msrc: Dictionary, mp: String, total: int) -> Dictionary:
	_unknown(c, msrc, mp, ["type", "from_tick", "to_tick", "target_mode", "speed_mps", "max_distance_m", "stop_at_m", "height_m", "distance_m", "orbit_deg", "impulse",
		"range_min_m", "range_max_m", "fit_to_target", "arrive_angle_deg", "gate_from_tick", "gate_to_tick", "reference_distance_m", "distance_scale_windows"])
	var mt := _enum(c, msrc, "type", mp, MOVES, true)
	var r: Array = [0, 0]
	if MOVES[mt] != "none":
		r = _range(c, msrc, mp, 0, total, "el paso")
		if MOVES[mt] != "blink_to_target" and (not msrc.has("max_distance_m") or msrc["max_distance_m"] == null):
			c.err(_p(mp, "max_distance_m"), "V13", "todo movimiento necesita max_distance_m")
	var tgt := _enum(c, msrc, "target_mode", mp, TARGET_MODES, false, "facing")
	var out := {"type": mt, "from": r[0], "to": r[1], "target": tgt,
		"speed": upt(_num(c, msrc, "speed_mps", mp, false, 0.0, 0.0, 40.0)),
		"max": um(_num(c, msrc, "max_distance_m", mp, false, 14.0 if MOVES[mt] == "blink_to_target" else 0.0, 0.0, 30.0)),
		"stop": um(_num(c, msrc, "stop_at_m", mp, false, 0.0, 0.0, 20.0)),
		"height": um(_num(c, msrc, "height_m", mp, false, 0.0, 0.0, 8.0)),
		"dist": um(_num(c, msrc, "distance_m", mp, false, 0.0, 0.0, 10.0)),
		"orbit": heading(_num(c, msrc, "orbit_deg", mp, false, 0.0, -720.0, 720.0)),
		"imp": 1 if _bool(c, msrc, "impulse", mp, false) else 0}
	# Etapa 1: gating y llegada
	var has_rmin := msrc.has("range_min_m") and msrc["range_min_m"] != null
	var has_rmax := msrc.has("range_max_m") and msrc["range_max_m"] != null
	var rmin_m := _num(c, msrc, "range_min_m", mp, false, 0.0, -100.0, 100.0) if has_rmin else -1.0
	var rmax_m := _num(c, msrc, "range_max_m", mp, false, 0.0, -100.0, 100.0) if has_rmax else -1.0
	if (has_rmin and rmin_m < 0.0) or (has_rmax and rmax_m < 0.0) or (has_rmin and has_rmax and rmin_m > rmax_m):
		c.err(_p(mp, "range_min_m"), "V21", "range_min_m debe ser <= range_max_m y >= 0")
	var fit := _bool(c, msrc, "fit_to_target", mp, false)
	if fit:
		var has_stop: bool = msrc.has("stop_at_m") and msrc["stop_at_m"] != null and _is_num(msrc["stop_at_m"]) and float(msrc["stop_at_m"]) > 0.0
		var points_opp: bool = String(TARGET_MODES[tgt]) in ["target", "lock_point"]
		if not has_stop or not points_opp:
			c.err(_p(mp, "fit_to_target"), "V22", "fit_to_target requiere stop_at_m > 0 y target_mode hacia el rival (target o lock_point)")
	var arr_deg := _num(c, msrc, "arrive_angle_deg", mp, false, 0.0, -3600.0, 3600.0)
	if arr_deg < -180.0 or arr_deg > 180.0:
		c.warn(_p(mp, "arrive_angle_deg"), "V23", "arrive_angle_deg fuera de [-180, 180]: %s" % str(arr_deg))
	var gf := _int(c, msrc, "gate_from_tick", mp, false, int(r[0]), 0, total)
	var gt := _int(c, msrc, "gate_to_tick", mp, false, int(r[1]), 0, total)
	var has_ref := msrc.has("reference_distance_m") and msrc["reference_distance_m"] != null
	var ref_m := _num(c, msrc, "reference_distance_m", mp, false, 0.0, -100.0, 100.0) if has_ref else 0.0
	if has_ref:
		var ref_bad := ref_m <= 0.0 or (has_rmin and ref_m < rmin_m) or (has_rmax and ref_m > rmax_m)
		if ref_bad:
			c.err(_p(mp, "reference_distance_m"), "V37", "reference_distance_m debe ser > 0 y estar dentro de [range_min_m, range_max_m]")
	var dsw_out: Array = []
	if msrc.has("distance_scale_windows") and msrc["distance_scale_windows"] != null:
		if not (msrc["distance_scale_windows"] is Array):
			c.err(_p(mp, "distance_scale_windows"), "V38", "distance_scale_windows debe ser una lista")
		else:
			var dsw_src: Array = msrc["distance_scale_windows"]
			var prev_to := 0
			for wi in dsw_src.size():
				var wp := "%s.distance_scale_windows[%d]" % [mp, wi]
				if not (dsw_src[wi] is Dictionary):
					c.err(wp, "V38", "debe ser un objeto")
					continue
				var wd: Dictionary = dsw_src[wi]
				_unknown(c, wd, wp, ["from_tick", "to_tick", "pct"])
				var wf := _int(c, wd, "from_tick", wp, true, 0)
				var wt := _int(c, wd, "to_tick", wp, true, 0)
				var wpct := _int(c, wd, "pct", wp, true, 100)
				if wf < 0 or wt > total or wf >= wt or wf < prev_to or wpct < 0 or wpct > 400:
					c.err(wp, "V38", "distance_scale_windows sin solapes, dentro del paso y pct en 0..400")
				prev_to = maxi(prev_to, wt)
				dsw_out.append({"from": wf, "to": wt, "pct": wpct, "pm": pm(wpct)})
	if has_rmin: out["range_min"] = um(maxf(rmin_m, 0.0))
	if has_rmax: out["range_max"] = um(maxf(rmax_m, 0.0))
	if msrc.has("fit_to_target"): out["fit"] = 1 if fit else 0
	if msrc.has("arrive_angle_deg"):
		out["arrive_cdeg"] = cdeg(arr_deg)
		out["arrive_head"] = heading(arr_deg)
	if msrc.has("gate_from_tick") or msrc.has("gate_to_tick"):
		out["gate_from"] = gf
		out["gate_to"] = gt
	if has_ref: out["ref_dist"] = um(maxf(ref_m, 0.0))
	if msrc.has("distance_scale_windows"): out["scale_windows"] = dsw_out
	return out

static func _variants_exclusive(a: String, b: String) -> bool:
	var p1 := a in ["phase1", "phase_1"]
	var p2 := a in ["phase2", "phase_2"]
	var q1 := b in ["phase1", "phase_1"]
	var q2 := b in ["phase2", "phase_2"]
	if (p1 and q2) or (p2 and q1):
		return true
	if (a == "grounded" and b == "airborne") or (a == "airborne" and b == "grounded"):
		return true
	if (a == "mounted" and b == "unmounted") or (a == "unmounted" and b == "mounted"):
		return true
	return false

static func _step(c: Ctx, s: Dictionary, p: String, si: int, sidx: Dictionary, is_entry: bool, mana_shield: bool, ev_ids: Dictionary, tl: Array, cat: int = 0, any_trail: bool = false, has_chain: bool = false) -> Dictionary:
	_unknown(c, s, p, ["id", "windup_ticks", "active_ticks", "recovery_ticks", "telegraph", "armor", "self_invuln", "tracking",
		"movement", "hitboxes", "spawns", "cancel_into", "branch", "next", "max_loops", "extra_cost", "events",
		"exit_windows", "buffer_ticks", "exit_buffer_ticks", "combo_input_windows", "weapon_trail", "self_windows",
		"cost_at_tick", "charge", "self_status_at", "counter_window", "guard_windows", "chain_role"])
	var id := _str(c, s, "id", p, true)
	var wu := _int(c, s, "windup_ticks", p, true, 1, 1, 3600)
	var ac := _int(c, s, "active_ticks", p, true, 1, 1, 3600)
	var rc := _int(c, s, "recovery_ticks", p, true, 0, 0, 3600)
	var total := wu + ac + rc
	var succ: Array[int] = []
	# telegraph
	var tele: Variant = null
	var tsrc: Variant = _obj(c, s, "telegraph", p, is_entry)
	if tsrc != null:
		var tp := _p(p, "telegraph")
		_unknown(c, tsrc, tp, ["id", "style", "color", "sound", "ground_marker", "at_tick", "text"])
		var tid := _str(c, tsrc, "id", tp, true)
		var gidx := -1
		if tid != "":
			if c.tele_ids.has(tid):
				c.err(_p(tp, "id"), "V03", "telegraph.id «%s» repetido en el catálogo" % tid)
			else:
				gidx = c.tele_list.size()
				c.tele_ids[tid] = gidx
				c.tele_list.append(tid)
		var color := _color(c, tsrc, tp)
		var sound := _str(c, tsrc, "sound", tp, true)
		tl.append({"color": color, "sound": sound})
		var marker: Variant = null
		var gm: Variant = _obj(c, tsrc, "ground_marker", tp, false)
		if gm != null:
			var gp := _p(tp, "ground_marker")
			_unknown(c, gm, gp, ["shape", "anchor", "fill_ticks"])
			marker = {"shape": _shape(c, gm, "shape", gp, true), "anchor": _enum(c, gm, "anchor", gp, ANCHORS, false, "self"),
				"fill": _int(c, gm, "fill_ticks", gp, false, wu, 0, 3600)}
		var at := _int(c, tsrc, "at_tick", tp, false, 0, 0, 3600)
		if at >= total:
			c.err(_p(tp, "at_tick"), "V08", "at_tick fuera del paso")
		_str(c, tsrc, "text", tp, false)
		tele = {"index": gidx, "id": tid, "style": _enum(c, tsrc, "style", tp, TELE_STYLES, true), "color": color,
			"sound": _asset(c, tsrc, "sound", tp, "sfx"), "marker": marker, "at": at}
	# armor
	var armor: Variant = null
	var asrc: Variant = _obj(c, s, "armor", p, false)
	if asrc != null:
		var ap := _p(p, "armor")
		_unknown(c, asrc, ap, ["type", "from_tick", "to_tick", "poise_bonus_pct", "dmg_reduction_pct"])
		var r := _range(c, asrc, ap, 0, total, "el paso")
		armor = {"type": _enum(c, asrc, "type", ap, ARMOR, true), "from": r[0], "to": r[1],
			"poise_pm": pm(_int(c, asrc, "poise_bonus_pct", ap, false, 100, 0, 500)),
			"dmg_red_pm": pm(_int(c, asrc, "dmg_reduction_pct", ap, false, 0, 0, 50))}
	# self_invuln (V11)
	var inv: Variant = null
	var isrc: Variant = _obj(c, s, "self_invuln", p, false)
	if isrc != null:
		var ip := _p(p, "self_invuln")
		_unknown(c, isrc, ip, ["from_tick", "to_tick", "mode", "dmg_taken_pct"])
		var r := _range(c, isrc, ip, 0, total, "el paso")
		var mode := _enum(c, isrc, "mode", ip, INVULN_MODES, false, "stun_immune")
		if INVULN_MODES[mode] == "total" and not mana_shield:
			c.err(_p(ip, "mode"), "V11", "invulnerabilidad total solo con la etiqueta mana_shield")
		inv = {"from": r[0], "to": r[1], "mode": mode, "dmg_taken_pm": pm(_int(c, isrc, "dmg_taken_pct", ip, false, 85, 50, 100)) if mode == 0 else 0}
	# tracking (Etapa 2 y 6b: windows y giro hasta 2000°/s)
	var trk := {"turn": 0, "lock": wu, "post": 0}
	var trsrc: Variant = _obj(c, s, "tracking", p, false)
	if trsrc != null:
		var trp := _p(p, "tracking")
		_unknown(c, trsrc, trp, ["deg_per_sec", "lock_at_tick", "post_lock_deg_per_sec", "windows"])
		trk["turn"] = turn_mrh(_num(c, trsrc, "deg_per_sec", trp, false, 0.0, 0.0, 2000.0))
		trk["lock"] = _int(c, trsrc, "lock_at_tick", trp, false, wu, 0, 3600)
		if int(trk["lock"]) > total:
			c.err(_p(trp, "lock_at_tick"), "V08", "lock_at_tick fuera del paso")
		var post := _num(c, trsrc, "post_lock_deg_per_sec", trp, false, 0.0, 0.0, 2000.0)
		if post > 60.0 and not _arr(c, s, "hitboxes", p, false).is_empty():
			c.warn(_p(trp, "post_lock_deg_per_sec"), "FAIRNESS", "giro tras el bloqueo > 60°/s en un paso con golpe: la ventana de esquiva casi desaparece")
		trk["post"] = turn_mrh(post)
		if trsrc.has("windows") and trsrc["windows"] != null:
			if not (trsrc["windows"] is Array):
				c.err(_p(trp, "windows"), "V24", "tracking.windows debe ser una lista")
			else:
				var w_arr: Array = trsrc["windows"]
				var w_out: Array = []
				var prev_to := 0
				for wi in w_arr.size():
					var wp := "%s.windows[%d]" % [trp, wi]
					if not (w_arr[wi] is Dictionary):
						c.err(wp, "V24", "debe ser un objeto")
						continue
					var wd: Dictionary = w_arr[wi]
					_unknown(c, wd, wp, ["from_tick", "to_tick", "deg_per_sec"])
					var wf := _int(c, wd, "from_tick", wp, true, 0)
					var wt := _int(c, wd, "to_tick", wp, true, 0)
					var wdps := _num(c, wd, "deg_per_sec", wp, true, 0.0, -10000.0, 10000.0)
					if wf < 0 or wt > total or wf >= wt or wf < prev_to or wdps < 0.0 or wdps > 2000.0:
						c.err(wp, "V24", "ventanas de tracking ordenadas, sin solaparse, dentro del paso y deg_per_sec en 0..2000")
					if wdps > 0.0 and wt > int(trk["lock"]):
						c.warn(wp, "V25", "ventana con giro > 0 después de lock_at_tick (%d > %d)" % [wt, int(trk["lock"])])
					prev_to = maxi(prev_to, wt)
					w_out.append({"from": wf, "to": wt, "turn": turn_mrh(clampf(wdps, 0.0, 2000.0)), "cdeg": cdeg_pt(clampf(wdps, 0.0, 2000.0))})
				trk["windows"] = w_out
	# movement: diccionario único (hoy) o lista de tramos (Etapa 7c, V45)
	var mv: Variant = null
	var mv_list: Array = []
	var has_mv_list := false
	if s.has("movement") and s["movement"] != null:
		if s["movement"] is Array:
			has_mv_list = true
			var marr: Array = s["movement"]
			if marr.is_empty():
				c.err(_p(p, "movement"), "V45", "la lista de tramos de movement no puede estar vacía")
			var prev_mto := 0
			for mi in marr.size():
				var mp_i := "%s.movement[%d]" % [p, mi]
				if not (marr[mi] is Dictionary):
					c.err(mp_i, "V45", "cada tramo de movement debe ser un objeto")
					continue
				var seg := _movement_seg(c, marr[mi], mp_i, total)
				var sf := int(seg["from"])
				var st_to := int(seg["to"])
				if sf < 0 or st_to > total or sf >= st_to or sf < prev_mto:
					c.err(mp_i, "V45", "tramos de movement deben estar ordenados, sin solaparse y dentro del paso")
				prev_mto = maxi(prev_mto, st_to)
				mv_list.append(seg)
			if not mv_list.is_empty():
				mv = mv_list[0]
		elif s["movement"] is Dictionary:
			mv = _movement_seg(c, s["movement"], _p(p, "movement"), total)
		else:
			c.err(_p(p, "movement"), "SCHEMA", "movement debe ser un objeto o una lista de tramos")
	# hitboxes (Etapa 6b: variant V41)
	var unbl := false
	var hbs: Array = []
	var hids := {}
	var hsrc := _arr(c, s, "hitboxes", p, false)
	for i in hsrc.size():
		var hp := "%s.hitboxes[%d]" % [p, i]
		if not (hsrc[i] is Dictionary):
			c.err(hp, "SCHEMA", "debe ser un objeto")
			continue
		var h := _hitbox(c, hsrc[i], hp, ac, wu, true)
		if hids.has(h["id"]):
			c.err(_p(hp, "id"), "V02", "id de hitbox repetido en el paso")
		hids[h["id"]] = true
		if int(h["blockable"]) == 0: unbl = true
		hbs.append(h)
	# V41 aviso: dos variantes del mismo tick pueden estar activas a la vez
	for i in hbs.size():
		for j in range(i + 1, hbs.size()):
			var hi: Dictionary = hbs[i]
			var hj: Dictionary = hbs[j]
			if not hi.has("variant") and not hj.has("variant"):
				continue
			if int(hi["from"]) < int(hj["to"]) and int(hj["from"]) < int(hi["to"]):
				var wi := String((hi.get("variant", {}) as Dictionary).get("when", ""))
				var wj := String((hj.get("variant", {}) as Dictionary).get("when", ""))
				if wi == "" or wj == "" or not _variants_exclusive(wi, wj):
					c.warn("%s.hitboxes[%d].variant" % [p, j], "V41", "dos variantes en el mismo tick pueden estar activas a la vez")
	# spawns (Etapa 6: volley V32/V33 y paired_hitbox V33)
	var sps: Array = []
	var spids := {}
	var spsrc := _arr(c, s, "spawns", p, false)
	for i in spsrc.size():
		var pp := "%s.spawns[%d]" % [p, i]
		if not (spsrc[i] is Dictionary):
			c.err(pp, "SCHEMA", "debe ser un objeto")
			continue
		var sp := _spawn(c, spsrc[i], pp, total, wu, hids)
		if spids.has(sp["id"]):
			c.err(_p(pp, "id"), "V02", "id de spawn repetido en el paso")
		spids[sp["id"]] = true
		if int(sp.get("blockable", 1)) == 0: unbl = true
		sps.append(sp)
	# Etapa 7d: chain_role
	var chain_role_idx := -1
	if s.has("chain_role") and s["chain_role"] != null:
		if not (s["chain_role"] is String) or not (String(s["chain_role"]) in CHAIN_ROLES):
			c.err(_p(p, "chain_role"), "V51", "chain_role inválido (uno de %s)" % ", ".join(PackedStringArray(CHAIN_ROLES)))
		else:
			chain_role_idx = CHAIN_ROLES.find(String(s["chain_role"]))
	# V07 (en continuaciones de cadena sin telegraph, V54 emite aviso en _chain_and_pt_rules)
	if unbl:
		if wu < MIN_UNBLOCKABLE_WINDUP:
			c.err(_p(p, "windup_ticks"), "V07", "paso imbloqueable: windup_ticks ≥ %d" % MIN_UNBLOCKABLE_WINDUP)
		if tele == null and not (has_chain and not is_entry):
			c.err(_p(p, "telegraph"), "V07", "paso imbloqueable sin telegraph propio")
	# cancel_into
	var cancel: Variant = null
	var csrc: Variant = _obj(c, s, "cancel_into", p, false)
	if csrc != null:
		var cp := _p(p, "cancel_into")
		_unknown(c, csrc, cp, ["window_from_tick", "window_to_tick", "steps", "only_on", "trigger"])
		var a := _int(c, csrc, "window_from_tick", cp, true, wu)
		var b := _int(c, csrc, "window_to_tick", cp, true, total)
		if a < wu or b > total or a >= b:
			c.err(cp, "V08", "ventana [%d, %d) fuera de activo+recuperación [%d, %d]" % [a, b, wu, total])
		var targets: Array[int] = []
		var cs := _arr(c, csrc, "steps", cp, true)
		if cs.is_empty() and csrc.has("steps"):
			c.err(_p(cp, "steps"), "SCHEMA", "lista vacía")
		for k in cs.size():
			var t := _ref(c, cs[k], "%s.steps[%d]" % [cp, k], sidx)
			if t >= 0:
				targets.append(t)
				succ.append(t)
		cancel = {"from": a, "to": b, "steps": targets, "only_on": _enum(c, csrc, "only_on", cp, ONLY_ON, false, "any"),
			"trigger": _enum(c, csrc, "trigger", cp, TRIGGERS, false, "auto")}
	# branch (V16)
	var branch: Variant = null
	var can_end := false
	var bsrc: Variant = _obj(c, s, "branch", p, false)
	if bsrc != null:
		var bp := _p(p, "branch")
		_unknown(c, bsrc, bp, ["window_from_tick", "window_to_tick", "time_base", "only_on", "buffer_ticks", "commit", "options", "default_if_no_input"])
		var tb := _enum(c, bsrc, "time_base", bp, TIME_BASES, false, "step")
		var off := wu if TIME_BASES[tb] == "active" else 0
		var a := _int(c, bsrc, "window_from_tick", bp, true, 0) + off
		var b := _int(c, bsrc, "window_to_tick", bp, true, 0) + off
		if a < 0 or b > total or a >= b:
			c.err(bp, "V16", "ventana [%d, %d) (en t_step) fuera del paso [0, %d]" % [a, b, total])
		var opts: Array = []
		var inputs := {}
		var osrc := _arr(c, bsrc, "options", bp, true)
		if bsrc.has("options") and (osrc.size() < 1 or osrc.size() > 4):
			c.err(_p(bp, "options"), "V16", "de 1 a 4 opciones")
		for k in osrc.size():
			var op := "%s.options[%d]" % [bp, k]
			if not (osrc[k] is Dictionary):
				c.err(op, "SCHEMA", "debe ser un objeto")
				continue
			var o: Dictionary = osrc[k]
			_unknown(c, o, op, ["input", "step", "hud_icon", "label", "extra_cost", "requires"])
			var inp := _enum(c, o, "input", op, INPUTS, true)
			if inputs.has(inp):
				c.err(_p(op, "input"), "V16", "dos opciones con el mismo input")
			inputs[inp] = true
			if not o.has("step"):
				c.err(_p(op, "step"), "V16", "campo obligatorio")
			var t := _ref(c, o.get("step"), _p(op, "step"), sidx)
			if t < 0 and o.has("step"):
				c.err(_p(op, "step"), "V16", "la opción debe apuntar a un paso existente")
			if t >= 0: succ.append(t)
			var icon := "generic"
			var label := ""
			if INPUTS[inp] != "skill":
				if not (o.get("hud_icon") is String) or String(o["hud_icon"]) == "":
					c.err(_p(op, "hud_icon"), "V16", "la opción alternativa necesita hud_icon")
				else:
					icon = _icon(c, o, "hud_icon", op, false)
				label = _str(c, o, "label", op, false)
				if label == "":
					c.err(_p(op, "label"), "V16", "la opción alternativa necesita label")
				if INPUTS[inp] == "alt2":
					c.warn(_p(op, "input"), "V16", "alt2 no tiene bit de entrada hoy")
			var req: Array[String] = []
			var rsrc := _arr(c, o, "requires", op, false)
			for r in rsrc.size():
				var rv := str(rsrc[r])
				if not (rv in REQUIRES) and not rv.begins_with("mana_ge:"):
					c.err("%s.requires[%d]" % [op, r], "SCHEMA", "condición desconocida «%s»" % rv)
				req.append(rv)
			opts.append({"input": inp, "step": t, "icon": icon, "label": label,
				"extra_cost": _cost(c, o.get("extra_cost"), _p(op, "extra_cost")), "requires": req})
		var dflt := _ref(c, bsrc.get("default_if_no_input", "end"), _p(bp, "default_if_no_input"), sidx)
		if dflt < 0: can_end = true
		else: succ.append(dflt)
		var commit_idx := _enum(c, bsrc, "commit", bp, COMMITS, false, "window_end")
		if COMMITS[commit_idx] == "on_step_end":
			commit_idx = 0
		branch = {"from": a, "to": b, "only_on": _enum(c, bsrc, "only_on", bp, ONLY_ON, false, "any"),
			"buffer": _int(c, bsrc, "buffer_ticks", bp, false, 6, 0, 12), "commit": commit_idx,
			"options": opts, "default": dflt}
	# next
	var nx := {"default": -1, "on_hit": -1, "on_whiff": -1, "on_blocked": -1}
	var nsrc: Variant = _obj(c, s, "next", p, false)
	if nsrc != null:
		var np := _p(p, "next")
		_unknown(c, nsrc, np, NEXT_KEYS)
		nx["default"] = _ref(c, nsrc.get("default"), _p(np, "default"), sidx)
		for k in ["on_hit", "on_whiff", "on_blocked"]:
			nx[k] = _ref(c, nsrc[k], _p(np, k), sidx) if nsrc.has(k) else nx["default"]
	for k: String in nx:
		if int(nx[k]) < 0:
			# con branch, el final por next solo aplica si la ventana no se abre (only_on); igual cuenta como fin posible
			can_end = true
		else:
			succ.append(int(nx[k]))
	var loops := _int(c, s, "max_loops", p, false, 0, 1, 5)
	var xc: Variant = null
	if s.has("extra_cost") and s["extra_cost"] != null:
		xc = _cost(c, _obj(c, s, "extra_cost", p, false), _p(p, "extra_cost"))
	# Etapa 3: exit_windows, buffer_ticks y combo_input_windows (V26, V27, V39, V40)
	var exit_buf := 0
	var has_exit_buf := false
	if s.has("buffer_ticks") and s["buffer_ticks"] != null:
		has_exit_buf = true
		exit_buf = _int(c, s, "buffer_ticks", p, false, 0, -100, 100)
		if exit_buf < 0 or exit_buf > 12:
			c.err(_p(p, "buffer_ticks"), "V26", "buffer_ticks debe estar en 0..12")
			exit_buf = clampi(exit_buf, 0, 12)
	elif s.has("exit_buffer_ticks") and s["exit_buffer_ticks"] != null:
		has_exit_buf = true
		exit_buf = _int(c, s, "exit_buffer_ticks", p, false, 0, -100, 100)
		if exit_buf < 0 or exit_buf > 12:
			c.err(_p(p, "exit_buffer_ticks"), "V26", "exit_buffer_ticks debe estar en 0..12")
			exit_buf = clampi(exit_buf, 0, 12)
	var exit_wins: Array = []
	var has_combo_action := false
	if s.has("exit_windows") and s["exit_windows"] != null:
		if not (s["exit_windows"] is Array):
			c.err(_p(p, "exit_windows"), "V26", "exit_windows debe ser una lista")
		else:
			var ew_src: Array = s["exit_windows"]
			var move_to := -1
			var roll_to := -1
			for wi in ew_src.size():
				var ewp := "%s.exit_windows[%d]" % [p, wi]
				if not (ew_src[wi] is Dictionary):
					c.err(ewp, "V26", "debe ser un objeto")
					continue
				var ewd: Dictionary = ew_src[wi]
				_unknown(c, ewd, ewp, ["action", "from_tick", "to_tick"])
				var act_s := String(ewd.get("action", ""))
				var act_i := EXIT_ACTIONS.find(act_s)
				var wf := _int(c, ewd, "from_tick", ewp, true, 0)
				var wt := _int(c, ewd, "to_tick", ewp, true, 0)
				if act_i < 0 or wf < 0 or wt > total or wf >= wt:
					c.err(ewp, "V26", "exit_windows requiere action válida y ventana dentro del paso [0, %d]" % total)
				if act_s == "combo":
					has_combo_action = true
				elif act_s == "move":
					move_to = maxi(move_to, wt)
				elif act_s == "roll":
					roll_to = maxi(roll_to, wt)
				exit_wins.append({"action": maxi(act_i, 0), "from": wf, "to": wt})
			if move_to >= 0 and roll_to >= 0 and move_to < roll_to:
				c.warn(_p(p, "exit_windows"), "V27", "la ventana de salida 'move' (%d) cierra antes que 'roll' (%d)" % [move_to, roll_to])
	var combo_wins: Array = []
	if s.has("combo_input_windows") and s["combo_input_windows"] != null:
		if not (s["combo_input_windows"] is Array):
			c.err(_p(p, "combo_input_windows"), "V40", "combo_input_windows debe ser una lista")
		else:
			var cw_src: Array = s["combo_input_windows"]
			var prev_cto := 0
			for wi in cw_src.size():
				var cwp := "%s.combo_input_windows[%d]" % [p, wi]
				if not (cw_src[wi] is Dictionary):
					c.err(cwp, "V40", "debe ser un objeto")
					continue
				var cwd: Dictionary = cw_src[wi]
				_unknown(c, cwd, cwp, ["from_tick", "to_tick", "window_from_tick", "window_to_tick", "buffer_ticks", "commit", "only_on", "step"])
				var fk := "from_tick" if cwd.has("from_tick") else "window_from_tick"
				var tk_k := "to_tick" if cwd.has("to_tick") else "window_to_tick"
				var wf := _int(c, cwd, fk, cwp, true, 0)
				var wt := _int(c, cwd, tk_k, cwp, true, 0)
				var cbuf := _int(c, cwd, "buffer_ticks", cwp, false, 6, -100, 100)
				if wf < 0 or wt > total or wf >= wt or wf < prev_cto or cbuf < 0 or cbuf > 12:
					c.err(cwp, "V40", "combo_input_windows dentro del paso, ordenadas, sin solaparse y buffer_ticks en 0..12")
				prev_cto = maxi(prev_cto, wt)
				var c_commit := _enum(c, cwd, "commit", cwp, COMMITS, false, "window_end")
				if COMMITS[c_commit] == "on_step_end":
					c_commit = 0
				var c_step := -1
				if cwd.has("step") and cwd["step"] != null:
					c_step = _ref(c, cwd["step"], _p(cwp, "step"), sidx)
					if c_step >= 0:
						succ.append(c_step)
				combo_wins.append({"from": wf, "to": wt, "buffer": clampi(cbuf, 0, 12), "commit": c_commit,
					"only_on": _enum(c, cwd, "only_on", cwp, ONLY_ON, false, "any"), "step": c_step})
	if has_combo_action or not combo_wins.is_empty():
		var has_cont := branch != null or cancel != null or int(nx["default"]) >= 0 or int(nx["on_hit"]) >= 0 or int(nx["on_whiff"]) >= 0 or int(nx["on_blocked"]) >= 0
		for cw_d: Dictionary in combo_wins:
			if int(cw_d.get("step", -1)) >= 0:
				has_cont = true
		if not has_cont:
			c.err(_p(p, "combo_input_windows" if not combo_wins.is_empty() else "exit_windows"), "V39", "combo requiere next, cancel_into o branch no nulo")
	# Etapa 4: weapon_trail y V28
	var wtrail: Variant = null
	if s.has("weapon_trail") and s["weapon_trail"] != null:
		var wtsrc: Variant = _obj(c, s, "weapon_trail", p, false)
		if wtsrc != null:
			var wtp := _p(p, "weapon_trail")
			_unknown(c, wtsrc, wtp, ["from_tick", "to_tick", "style"])
			var wr := _range(c, wtsrc, wtp, 0, total, "el paso")
			wtrail = {"from": wr[0], "to": wr[1], "style": _str(c, wtsrc, "style", wtp, true, "slash")}
	if cat == CATEGORIES.find("melee") and not hbs.is_empty() and (s.has("weapon_trail") or any_trail or bool(c.opts.get("check_weapon_trail", false))):
		var trail_ok := wtrail is Dictionary
		if trail_ok:
			for hb_t: Dictionary in hbs:
				if int(wtrail["from"]) > wu + int(hb_t["from"]) or int(wtrail["to"]) < wu + int(hb_t["to"]):
					trail_ok = false
					break
		if not trail_ok:
			c.warn(_p(p, "weapon_trail"), "V28", "caja de golpe activa en paso melee sin weapon_trail que la cubra")
	# events (ids únicos en la habilidad; Etapa 4 y 5: V29, V30, V31)
	var evs: Array = []
	var esrc := _arr(c, s, "events", p, false)
	for i in esrc.size():
		var ep := "%s.events[%d]" % [p, i]
		if not (esrc[i] is Dictionary):
			c.err(ep, "SCHEMA", "debe ser un objeto")
			continue
		var e: Dictionary = esrc[i]
		_unknown(c, e, ep, ["id", "tick", "vfx", "sfx", "camera_shake", "on",
			"duration_ticks", "outlive_step", "attach", "sfx_attach", "follow", "sfx_loop", "stop_on_interrupt", "footstep"])
		var eid := _str(c, e, "id", ep, true)
		if eid != "" and ev_ids.has(eid):
			c.err(_p(ep, "id"), "V02", "id de evento repetido en la habilidad «%s»" % eid)
		var ev_index := ev_ids.size()
		ev_ids[eid] = ev_index
		var tk := _int(c, e, "tick", ep, true, 0, -3600, 3600)
		if tk < 0 or tk >= total:
			c.err(_p(ep, "tick"), "V08", "tick fuera del paso [0, %d)" % total)
			if e.has("duration_ticks") or e.has("outlive_step"):
				c.err(_p(ep, "tick"), "V29", "evento fuera del paso [0, %d)" % total)
		var dur := _int(c, e, "duration_ticks", ep, false, 0, -3600, 36000)
		var outlive := _bool(c, e, "outlive_step", ep, false)
		if dur < 0 or (dur > 0 and tk >= 0 and tk + dur > total and not outlive):
			c.err(_p(ep, "duration_ticks"), "V29", "duration_ticks >= 0 y el evento debe caber en el paso (o usar outlive_step: true)")
		var att_idx := 0
		if e.has("attach") and e["attach"] != null:
			if not (e["attach"] is String) or not (String(e["attach"]) in ATTACH_TARGETS):
				c.err(_p(ep, "attach"), "V30", "attach inválido (uno de %s)" % ", ".join(PackedStringArray(ATTACH_TARGETS)))
			else:
				att_idx = ATTACH_TARGETS.find(String(e["attach"]))
		var sfx_att_idx := att_idx
		if e.has("sfx_attach") and e["sfx_attach"] != null:
			if not (e["sfx_attach"] is String) or not (String(e["sfx_attach"]) in ATTACH_TARGETS):
				c.err(_p(ep, "sfx_attach"), "V30", "sfx_attach inválido (uno de %s)" % ", ".join(PackedStringArray(ATTACH_TARGETS)))
			else:
				sfx_att_idx = ATTACH_TARGETS.find(String(e["sfx_attach"]))
		var shake_lvl := 0
		var shake_obj: Variant = null
		if e.has("camera_shake") and e["camera_shake"] != null:
			if e["camera_shake"] is Dictionary:
				var csd: Dictionary = e["camera_shake"]
				var csp := _p(ep, "camera_shake")
				_unknown(c, csd, csp, ["level", "falloff_start_m", "falloff_end_m", "haptic"])
				shake_lvl = _int(c, csd, "level", csp, true, 0, 0, 3)
				var fs := _num(c, csd, "falloff_start_m", csp, false, 10.0, -1000.0, 1000.0)
				var fe := _num(c, csd, "falloff_end_m", csp, false, 30.0, -1000.0, 1000.0)
				if fs < 0.0 or fe < 0.0 or fs > fe:
					c.err(_p(csp, "falloff_start_m"), "V31", "falloff_start_m debe ser <= falloff_end_m y >= 0")
				var hap_def: String = HAPTICS[clampi(shake_lvl, 0, 3)]
				var hap_idx := _enum(c, csd, "haptic", csp, HAPTICS, false, hap_def)
				shake_obj = {"level": shake_lvl, "falloff_start": um(maxf(fs, 0.0)), "falloff_end": um(maxf(fe, 0.0)), "haptic": hap_idx}
			else:
				shake_lvl = _int(c, e, "camera_shake", ep, false, 0, 0, 3)
		var ev_out := {"index": ev_index, "id": eid, "tick": tk, "vfx": _asset(c, e, "vfx", ep, "vfx"), "sfx": _asset(c, e, "sfx", ep, "sfx"),
			"shake": shake_lvl, "on": _enum(c, e, "on", ep, EV_ON, false, "always")}
		if e.has("duration_ticks"): ev_out["duration"] = maxi(dur, 0)
		if e.has("outlive_step"): ev_out["outlive"] = 1 if outlive else 0
		if e.has("attach"): ev_out["attach"] = att_idx
		if e.has("sfx_attach"): ev_out["sfx_attach"] = sfx_att_idx
		if e.has("follow"): ev_out["follow"] = 1 if _bool(c, e, "follow", ep, true) else 0
		if e.has("sfx_loop"): ev_out["sfx_loop"] = 1 if _bool(c, e, "sfx_loop", ep, false) else 0
		if e.has("stop_on_interrupt"): ev_out["stop_on_interrupt"] = 1 if _bool(c, e, "stop_on_interrupt", ep, true) else 0
		if e.has("footstep"): ev_out["footstep"] = 1 if _bool(c, e, "footstep", ep, false) else 0
		if shake_obj != null: ev_out["shake_obj"] = shake_obj
		evs.append(ev_out)
	# Etapa 7: self_windows (V34, V35, V36) y cost_at_tick (V35)
	var self_wins: Array = []
	if s.has("self_windows") and s["self_windows"] != null:
		if not (s["self_windows"] is Array):
			c.err(_p(p, "self_windows"), "V35", "self_windows debe ser una lista")
		else:
			var sw_src: Array = s["self_windows"]
			for wi in sw_src.size():
				var swp := "%s.self_windows[%d]" % [p, wi]
				if not (sw_src[wi] is Dictionary):
					c.err(swp, "V35", "debe ser un objeto")
					continue
				var swd: Dictionary = sw_src[wi]
				_unknown(c, swd, swp, ["type", "from_tick", "to_tick", "opacity_from", "opacity_to"])
				var st_s := String(swd.get("type", ""))
				var st_i := SELF_WINDOW_TYPES.find(st_s)
				var wf := _int(c, swd, "from_tick", swp, true, 0)
				var wt := _int(c, swd, "to_tick", swp, true, 0)
				var op_from := _int(c, swd, "opacity_from", swp, false, 100, -100, 200)
				var op_to := _int(c, swd, "opacity_to", swp, false, 0, -100, 200)
				if st_i < 0 or wf < 0 or wt > total or wf >= wt or op_from < 0 or op_from > 100 or op_to < 0 or op_to > 100:
					c.err(swp, "V35", "self_windows requiere type válido, ventana dentro del paso y opacidad en 0..100")
				if st_s == "intangible" and wt - wf > 60:
					c.warn(swp, "V36", "ventana intangible de %d ticks (> 60)" % (wt - wf))
				if st_s == "fade" and op_to < 30:
					if not _has_reappear_cue(tele, evs, wf, wt):
						c.err(swp, "V34", "fade a opacidad < 30 exige telegraph o evento con sfx en el tick de reaparición")
				self_wins.append({"type": maxi(st_i, 0), "from": wf, "to": wt, "op_from": clampi(op_from, 0, 100), "op_to": clampi(op_to, 0, 100)})
	var st_cost_at := -1
	if s.has("cost_at_tick") and s["cost_at_tick"] != null:
		st_cost_at = _int(c, s, "cost_at_tick", p, false, 0, -3600, 36000)
		if st_cost_at < 0 or st_cost_at >= total:
			c.err(_p(p, "cost_at_tick"), "V35", "cost_at_tick fuera del paso [0, %d)" % total)
	# Etapa 7c: V46 blink_to_target (entre desaparición y primer activo >= 18 ticks + cue de reaparición V34)
	var all_mvs: Array = mv_list if has_mv_list else ([mv] if mv is Dictionary else [])
	var first_act_abs := total
	if not hbs.is_empty():
		first_act_abs = wu + int((hbs[0] as Dictionary)["from"])
		for hb_m: Dictionary in hbs:
			first_act_abs = mini(first_act_abs, wu + int(hb_m["from"]))
	for mseg: Variant in all_mvs:
		if mseg is Dictionary and MOVES[int((mseg as Dictionary)["type"])] == "blink_to_target":
			var bf := int((mseg as Dictionary)["from"])
			var bt := int((mseg as Dictionary)["to"])
			var cue_ok := _has_reappear_cue(tele, evs, bf, bt)
			if first_act_abs - bf < 18 or not cue_ok:
				c.err(_p(p, "movement"), "V46", "blink_to_target requiere >= 18 ticks entre desaparición y primer activo, y telegraph o sfx al reaparecer")
				if not cue_ok:
					c.err(_p(p, "movement"), "V34", "blink_to_target exige telegraph o sfx en el tick de reaparición")
	# Etapa 7b: charge (V42), self_status_at (V43, V48), counter_window (V44)
	var charge_out: Variant = null
	if s.has("charge") and s["charge"] != null:
		var chsrc: Variant = _obj(c, s, "charge", p, false)
		if chsrc != null:
			var chp := _p(p, "charge")
			_unknown(c, chsrc, chp, ["from_tick", "max_ticks", "release_step", "tiers"])
			var cf := _int(c, chsrc, "from_tick", chp, false, 0, 0, total)
			var cm := _int(c, chsrc, "max_ticks", chp, true, wu, 1, total)
			if cf < 0 or cm <= cf or cm > total:
				c.err(chp, "V42", "charge requiere 0 <= from_tick < max_ticks <= total")
			var rel_step := -1
			if chsrc.has("release_step") and chsrc["release_step"] != null:
				rel_step = _ref(c, chsrc["release_step"], _p(chp, "release_step"), sidx)
				if rel_step >= 0:
					succ.append(rel_step)
			var t_arr := _arr(c, chsrc, "tiers", chp, true)
			if t_arr.is_empty():
				c.err(_p(chp, "tiers"), "V42", "charge.tiers no puede estar vacío")
			var tiers_out: Array = []
			var prev_at := cf - 1
			for ti in t_arr.size():
				var tp_i := "%s.tiers[%d]" % [chp, ti]
				if not (t_arr[ti] is Dictionary):
					c.err(tp_i, "V42", "debe ser un objeto")
					continue
				var td: Dictionary = t_arr[ti]
				_unknown(c, td, tp_i, ["at_tick", "damage_pct", "stun_pct", "vfx", "sfx", "sfx_loop"])
				var at_t := _int(c, td, "at_tick", tp_i, true, cf)
				var dpct := _int(c, td, "damage_pct", tp_i, false, 100, 1, 500)
				var spct := _int(c, td, "stun_pct", tp_i, false, 100, 1, 500)
				var tvfx := _str(c, td, "vfx", tp_i, false, "")
				var tsfx := _str(c, td, "sfx", tp_i, false, "")
				var tloop := _str(c, td, "sfx_loop", tp_i, false, "")
				if at_t < cf or at_t > cm or at_t <= prev_at or (tvfx == "" and tsfx == "" and tloop == ""):
					c.err(tp_i, "V42", "cada tier de charge requiere at_tick ordenado en [from_tick, max_ticks] y al menos vfx, sfx o sfx_loop")
				prev_at = at_t
				tiers_out.append({"at": at_t, "dmg_pct": dpct, "stun_pct": spct, "vfx": tvfx, "sfx": tsfx, "sfx_loop": tloop})
			charge_out = {"from": cf, "max": cm, "release_step": rel_step, "tiers": tiers_out}
	var sstat_out: Array = []
	if s.has("self_status_at") and s["self_status_at"] != null:
		if not (s["self_status_at"] is Array):
			c.err(_p(p, "self_status_at"), "V43", "self_status_at debe ser una lista")
		else:
			var ss_arr: Array = s["self_status_at"]
			for si_k in ss_arr.size():
				var ssp := "%s.self_status_at[%d]" % [p, si_k]
				if not (ss_arr[si_k] is Dictionary):
					c.err(ssp, "V43", "debe ser un objeto")
					continue
				var ssd: Dictionary = ss_arr[si_k]
				_unknown(c, ssd, ssp, ["tick", "status", "duration_ticks", "on"])
				var stk := _int(c, ssd, "tick", ssp, true, 0)
				var st_name := String(ssd.get("status", ""))
				var sdur := _int(c, ssd, "duration_ticks", ssp, true, 60)
				var son_s := String(ssd.get("on", "always"))
				if stk < 0 or stk >= total or sdur < 1 or not (st_name in SELF_STATUSES):
					c.err(ssp, "V43", "self_status_at requiere status conocido, tick dentro del paso y duration_ticks >= 1")
				if not (son_s in SELF_STATUS_ON):
					c.err(_p(ssp, "on"), "V48", "self_status_at.on debe ser always, hit, blocked o whiff")
				sstat_out.append({"tick": stk, "status": maxi(SELF_STATUSES.find(st_name), 0), "status_id": st_name, "duration": maxi(sdur, 1), "on": maxi(SELF_STATUS_ON.find(son_s), 0)})
	var cwin_out: Variant = null
	if s.has("counter_window") and s["counter_window"] != null:
		var cwsrc: Variant = _obj(c, s, "counter_window", p, false)
		if cwsrc != null:
			var cwp := _p(p, "counter_window")
			_unknown(c, cwsrc, cwp, ["from_tick", "to_tick", "damage_taken_pct", "stun_taken_pct"])
			var cwf := _int(c, cwsrc, "from_tick", cwp, true, 0)
			var cwt := _int(c, cwsrc, "to_tick", cwp, true, 0)
			var cwdmg := _int(c, cwsrc, "damage_taken_pct", cwp, true, 100)
			var cwstun := _int(c, cwsrc, "stun_taken_pct", cwp, false, 100)
			if cwf < 0 or cwt > total or cwf >= cwt or cwdmg < 100 or cwdmg > 200 or cwstun < 0 or cwstun > 300:
				c.err(cwp, "V44", "counter_window requiere ventana dentro del paso y damage_taken_pct en 100..200")
			elif cwt - cwf > 40:
				c.warn(cwp, "V44", "counter_window de %d ticks (> 40)" % (cwt - cwf))
			cwin_out = {"from": cwf, "to": cwt, "dmg_pct": cwdmg, "stun_pct": cwstun}
	# Etapa 7c: guard_windows (V47)
	var gwins_out: Array = []
	if s.has("guard_windows") and s["guard_windows"] != null:
		if not (s["guard_windows"] is Array):
			c.err(_p(p, "guard_windows"), "V47", "guard_windows debe ser una lista")
		else:
			var gw_arr: Array = s["guard_windows"]
			for gi in gw_arr.size():
				var gwp := "%s.guard_windows[%d]" % [p, gi]
				if not (gw_arr[gi] is Dictionary):
					c.err(gwp, "V47", "debe ser un objeto")
					continue
				var gwd: Dictionary = gw_arr[gi]
				_unknown(c, gwd, gwp, ["from_tick", "to_tick", "block_dmg_pct", "knockback_pct", "stamina_regen_pct"])
				var gwf := _int(c, gwd, "from_tick", gwp, true, 0)
				var gwt := _int(c, gwd, "to_tick", gwp, true, 0)
				var gbd := _int(c, gwd, "block_dmg_pct", gwp, false, 70)
				var gkb := _int(c, gwd, "knockback_pct", gwp, false, 50)
				var gsr := _int(c, gwd, "stamina_regen_pct", gwp, false, 30)
				if gwf < 0 or gwt > total or gwf >= gwt or gbd < 0 or gbd > 100 or gkb < 0 or gkb > 100 or gsr < 0 or gsr > 100:
					c.err(gwp, "V47", "guard_windows requiere ventana dentro del paso y porcentajes en 0..100")
				gwins_out.append({"from": gwf, "to": gwt, "block_dmg_pct": clampi(gbd, 0, 100), "knockback_pct": clampi(gkb, 0, 100), "stamina_regen_pct": clampi(gsr, 0, 100)})
	var st_out := {"index": si, "id": id, "windup": wu, "active": ac, "recovery": rc, "total": total, "telegraph": tele,
		"armor": armor, "invuln": inv, "tracking": trk, "movement": mv, "hitboxes": hbs, "spawns": sps,
		"cancel": cancel, "branch": branch, "next": nx, "max_loops": loops, "extra_cost": xc, "events": evs,
		"_succ": succ, "_can_end": can_end, "_terminal": can_end}
	if has_mv_list: st_out["movements"] = mv_list
	if s.has("exit_windows"): st_out["exit_windows"] = exit_wins
	if has_exit_buf: st_out["exit_buffer"] = exit_buf
	if s.has("combo_input_windows"): st_out["combo_input_windows"] = combo_wins
	if wtrail != null: st_out["weapon_trail"] = wtrail
	if s.has("self_windows"): st_out["self_windows"] = self_wins
	if st_cost_at >= 0: st_out["cost_at_tick"] = st_cost_at
	if charge_out != null: st_out["charge"] = charge_out
	if s.has("self_status_at"): st_out["self_status_at"] = sstat_out
	if cwin_out != null: st_out["counter_window"] = cwin_out
	if s.has("guard_windows"): st_out["guard_windows"] = gwins_out
	if chain_role_idx >= 0: st_out["chain_role"] = chain_role_idx
	return st_out

static func _has_reappear_cue(tele: Variant, evs: Array, wf: int, wt: int) -> bool:
	if tele is Dictionary and int((tele as Dictionary).get("at", 0)) >= wf:
		return true
	for ev: Variant in evs:
		if ev is Dictionary and String((ev as Dictionary).get("sfx", "")) != "" and int((ev as Dictionary).get("tick", -1)) >= wf:
			return true
	return false

## ------------------------------------------------------------------ hitbox / fuerza / estado / spawn

static func _hitbox(c: Ctx, h: Dictionary, p: String, active: int, windup: int, full: bool) -> Dictionary:
	var allowed := ["damage_per_hit", "damage_type", "damage_scaling", "blockable", "parryable", "stun_power", "stun_scaling"]
	if full:
		allowed += ["id", "shape", "offset", "anchor", "ground_only", "reach_height_m", "from_tick", "to_tick", "hits", "hit_interval_ticks",
			"on_hit", "consumes_mark", "lifesteal_pct", "variant"]
	_unknown(c, h, p, allowed)
	var out := {"dmg": milli(_num(c, h, "damage_per_hit", p, true, 0.0, 0.0, 500.0)),
		"dmg_type": _enum(c, h, "damage_type", p, DMG_TYPES, false, "physical"),
		"dmg_scaling": _enum(c, h, "damage_scaling", p, DMG_SCALING, false, "attacker"),
		"blockable": 1 if _bool(c, h, "blockable", p, true) else 0,
		"parryable": 1 if _bool(c, h, "parryable", p, true) else 0,
		"stun": milli(_num(c, h, "stun_power", p, true, 0.0, 0.0, 500.0)),
		"stun_scaling": _enum(c, h, "stun_scaling", p, STUN_SCALING, false, "physical")}
	if not full:
		return out
	out["id"] = _str(c, h, "id", p, true)
	out["shape"] = _shape(c, h, "shape", p, true)
	var off := _offset(c, h, p)
	out["fwd"] = off[0]
	out["right"] = off[1]
	out["anchor"] = _enum(c, h, "anchor", p, ANCHORS, false, "self")
	var ground := _bool(c, h, "ground_only", p, false)
	out["ground_only"] = 1 if ground else 0
	# ground_only sigue siendo el bit que lee la sim. reach_um es el tope declarado, en µm.
	if h.has("reach_height_m"):
		var reach_m := _num(c, h, "reach_height_m", p, true, 0.0, 0.0, 8.0)
		out["reach_um"] = um(reach_m)
		if ground and int(out["reach_um"]) != REACH_GROUND_UM:
			c.err(_p(p, "reach_height_m"), "SCHEMA", "ground_only es el atajo de 0,35 m")
	elif ground:
		out["reach_um"] = REACH_GROUND_UM
	else:
		out["reach_um"] = REACH_NONE
	var r := _range(c, h, p, 0, active, "el activo")
	out["from"] = r[0]
	out["to"] = r[1]
	out["hits"] = _int(c, h, "hits", p, false, 1, 1, 20)
	out["interval"] = _int(c, h, "hit_interval_ticks", p, false, 0, 0, 600)
	if int(out["hits"]) > 1 and int(out["interval"]) < 1:
		c.err(_p(p, "hit_interval_ticks"), "SCHEMA", "con hits > 1, hit_interval_ticks ≥ 1")
	out["consumes_mark"] = 1 if _bool(c, h, "consumes_mark", p, false) else 0
	out["lifesteal_pm"] = pm(_int(c, h, "lifesteal_pct", p, false, 0, 0, 50))
	out["knock_speed"] = 0
	out["knock_t"] = 0
	out["knockdown"] = 0
	out["status"] = null
	out["force"] = null
	var oh: Variant = _obj(c, h, "on_hit", p, false)
	if oh != null:
		var op := _p(p, "on_hit")
		_unknown(c, oh, op, ["knockback", "knockdown", "status", "force"])
		var kb: Variant = _obj(c, oh, "knockback", op, false)
		if kb != null:
			var kp := _p(op, "knockback")
			_unknown(c, kb, kp, ["speed_mps", "duration_ticks"])
			out["knock_speed"] = upt(_num(c, kb, "speed_mps", kp, true, 0.0, 0.0, 12.0))
			out["knock_t"] = _int(c, kb, "duration_ticks", kp, true, 1, 1, 20)
		if _bool(c, oh, "knockdown", op, false):
			out["knockdown"] = 1
			if windup < 30:
				c.warn(_p(op, "knockdown"), "FAIRNESS", "derribo forzado con windup < 30")
		out["status"] = _status(c, _obj(c, oh, "status", op, false), _p(op, "status"))
		out["force"] = _force(c, _obj(c, oh, "force", op, false), _p(op, "force"))
	if h.has("variant") and h["variant"] != null:
		var vp := _p(p, "variant")
		if not (h["variant"] is Dictionary):
			c.err(vp, "V41", "variant debe ser un objeto")
		else:
			var vd: Dictionary = h["variant"]
			_unknown(c, vd, vp, ["when"])
			var wtag := _str(c, vd, "when", vp, true)
			if not (wtag in VARIANT_TAGS):
				c.err(_p(vp, "when"), "V41", "variant.when «%s» desconocido" % wtag)
			out["variant"] = {"when": wtag, "tag_idx": maxi(VARIANT_TAGS.find(wtag), 0)}
	return out

static func _force(c: Ctx, f: Variant, p: String) -> Variant:
	if f == null:
		return null
	_unknown(c, f, p, ["type", "strength_mps", "duration_ticks", "max_distance_m", "breakable_by"])
	var t := _enum(c, f, "type", p, FORCES, true)
	var dur := _int(c, f, "duration_ticks", p, true, 1, 1, 600)
	var md := _num(c, f, "max_distance_m", p, true, 0.0, 0.0, 20.0)
	var br := _mask(c, f, "breakable_by", p, BREAKABLE, ["roll"])
	if FORCES[t] == "pull":
		if dur > 24:
			c.err(_p(p, "duration_ticks"), "V12", "pull: duration_ticks ≤ 24")
		if md > 4.0:
			c.err(_p(p, "max_distance_m"), "V12", "pull: max_distance_m ≤ 4")
		if br == 0 or br == 1 << BREAKABLE.find("none"):
			c.err(_p(p, "breakable_by"), "V12", "pull: breakable_by no puede estar vacío")
	if FORCES[t] == "root" and dur > 45:
		c.err(_p(p, "duration_ticks"), "SCHEMA", "root: duration_ticks ≤ 45")
	return {"type": t, "strength": upt(_num(c, f, "strength_mps", p, true, 0.0, 0.0, 40.0)), "duration": dur, "max": um(md), "breakable_mask": br}

static func _status(c: Ctx, s: Variant, p: String) -> Variant:
	if s == null:
		return null
	_unknown(c, s, p, ["type", "duration_ticks", "tick_interval", "damage", "stacks_max", "slow_pct"])
	var t := _enum(c, s, "type", p, STATUSES, true)
	var ti := _int(c, s, "tick_interval", p, STATUSES[t] == "sangrado", 0, 0, 600)
	if STATUSES[t] == "sangrado" and ti < 1 and s.has("tick_interval"):
		c.err(_p(p, "tick_interval"), "SCHEMA", "sangrado: tick_interval ≥ 1")
	return {"type": t, "duration": _int(c, s, "duration_ticks", p, true, 1, 1, 600), "interval": ti,
		"dmg": milli(_num(c, s, "damage", p, false, 0.0, 0.0, 200.0)), "stacks": _int(c, s, "stacks_max", p, false, 1, 1, 5),
		"slow_pm": pm(_int(c, s, "slow_pct", p, STATUSES[t] == "slow", 0 if STATUSES[t] != "slow" else 10, 0 if STATUSES[t] != "slow" else 10, 50))}

static func _spawn(c: Ctx, s: Dictionary, p: String, total: int, windup: int, hids: Dictionary = {}) -> Dictionary:
	var common := ["id", "type", "at_tick", "anchor", "offset", "count", "spread_deg", "volley", "paired_hitbox"]
	var t := _enum(c, s, "type", p, SPAWNS, true)
	var at := _int(c, s, "at_tick", p, true, 0, 0, 3600)
	if at >= total:
		c.err(_p(p, "at_tick"), "V08", "at_tick fuera del paso [0, %d)" % total)
	var off := _offset(c, s, p)
	var out := {"id": _str(c, s, "id", p, true), "type": t, "at": at, "anchor": _enum(c, s, "anchor", p, ANCHORS, false, "self"),
		"fwd": off[0], "right": off[1], "count": _int(c, s, "count", p, false, 1, 1, 12),
		"spread": heading(_num(c, s, "spread_deg", p, false, 0.0, 0.0, 360.0))}
	if s.has("volley") and s["volley"] != null:
		var vp := _p(p, "volley")
		if not (s["volley"] is Dictionary):
			c.err(vp, "V32", "volley debe ser un objeto")
		else:
			var vd: Dictionary = s["volley"]
			_unknown(c, vd, vp, ["count", "interval_ticks", "origin_offsets", "spread_deg", "aim"])
			var vc := _int(c, vd, "count", vp, true, 1, -100, 100)
			var vi := _int(c, vd, "interval_ticks", vp, true, 0, -100, 3600)
			if vc < 1 or vi < 0 or at + (maxi(vc, 1) - 1) * maxi(vi, 0) >= total:
				c.err(vp, "V32", "volley requiere count >= 1, interval_ticks >= 0 y último sub-spawn dentro del paso [0, %d)" % total)
			var voffs: Array = []
			if vd.has("origin_offsets") and vd["origin_offsets"] != null:
				if not (vd["origin_offsets"] is Array):
					c.err(_p(vp, "origin_offsets"), "V33", "origin_offsets debe ser una lista")
				else:
					var oarr: Array = vd["origin_offsets"]
					if oarr.size() != vc:
						c.err(_p(vp, "origin_offsets"), "V33", "origin_offsets debe tener largo count (%d != %d)" % [oarr.size(), vc])
					for oi_k in oarr.size():
						var op_k := "%s.origin_offsets[%d]" % [vp, oi_k]
						if not (oarr[oi_k] is Dictionary):
							c.err(op_k, "V33", "debe ser un objeto")
							continue
						var od: Dictionary = oarr[oi_k]
						_unknown(c, od, op_k, ["forward_m", "right_m"])
						voffs.append([um(_num(c, od, "forward_m", op_k, false, 0.0, -20.0, 20.0)), um(_num(c, od, "right_m", op_k, false, 0.0, -20.0, 20.0))])
			var vspread := _num(c, vd, "spread_deg", vp, false, 0.0, 0.0, 360.0)
			var vaim := _enum(c, vd, "aim", vp, VOLLEY_AIMS, false, "lock")
			out["volley"] = {"count": maxi(vc, 1), "interval": maxi(vi, 0), "offsets": voffs, "spread": heading(vspread), "spread_cdeg": cdeg(vspread), "aim": vaim}
	if s.has("paired_hitbox") and s["paired_hitbox"] != null:
		var phb := _str(c, s, "paired_hitbox", p, false)
		if phb == "" or not hids.has(phb):
			c.err(_p(p, "paired_hitbox"), "V33", "paired_hitbox «%s» no existe en el paso" % phb)
		out["paired_hitbox"] = phb
	match SPAWNS[t]:
		"ground_mark":
			_unknown(c, s, p, common + ["shape", "warn_ticks", "damage", "stun_power", "knockback_mps", "blockable", "mode", "scatter_radius_m", "interval_ticks", "on", "hits_airborne"])
			out["shape"] = _shape(c, s, "shape", p, true)
			out["warn"] = _int(c, s, "warn_ticks", p, true, 30, 0, 600)
			if int(out["warn"]) < 30:
				c.warn(_p(p, "warn_ticks"), "FAIRNESS", "aviso de marca < 30 ticks")
			out["dmg"] = milli(_num(c, s, "damage", p, true, 0.0, 0.0, 500.0))
			out["stun"] = milli(_num(c, s, "stun_power", p, false, 0.0, 0.0, 500.0))
			out["knock"] = upt(_num(c, s, "knockback_mps", p, false, 0.0, 0.0, 12.0))
			out["blockable"] = 1 if _bool(c, s, "blockable", p, true) else 0
			out["mode"] = _enum(c, s, "mode", p, MARK_MODES, false, "track")
			out["scatter_r"] = um(_num(c, s, "scatter_radius_m", p, false, 0.0, 0.0, 20.0))
			out["interval"] = _int(c, s, "interval_ticks", p, false, 0, 0, 600)
			out["on"] = _enum(c, s, "on", p, SPAWN_ON, false, "always")
			out["hits_airborne"] = 1 if _bool(c, s, "hits_airborne", p, false) else 0
		"ground_wave":
			_unknown(c, s, p, common + ["speed_mps", "range_m", "width_m", "warn_ticks", "ring", "damage", "stun_power", "blockable", "on", "knockback_mps", "hits_airborne"])
			var spd_m := _num(c, s, "speed_mps", p, true, 0.0, 0.0, 40.0)
			if spd_m > 0.0 and spd_m < 0.1:
				c.err(_p(p, "speed_mps"), "SCHEMA", "una onda que viaja va a 0,1 m/s o más; 0 es la línea quieta")
			out["speed"] = upt(spd_m)
			out["range"] = um(_num(c, s, "range_m", p, true, 0.0, 0.1, 40.0))
			out["width"] = um(_num(c, s, "width_m", p, true, 0.0, 0.1, 10.0))
			out["warn"] = _int(c, s, "warn_ticks", p, true, 0, 0, 600)
			out["ring"] = 1 if _bool(c, s, "ring", p, false) else 0
			out["dmg"] = milli(_num(c, s, "damage", p, true, 0.0, 0.0, 500.0))
			out["stun"] = milli(_num(c, s, "stun_power", p, false, 0.0, 0.0, 500.0))
			out["blockable"] = 1 if _bool(c, s, "blockable", p, true) else 0
			out["on"] = _enum(c, s, "on", p, SPAWN_ON, false, "always")
			out["knock"] = upt(_num(c, s, "knockback_mps", p, false, 6.0, 0.0, 40.0))
			out["hits_airborne"] = 1 if _bool(c, s, "hits_airborne", p, false) else 0
		"projectile":
			_unknown(c, s, p, common + ["speed_mps", "homing_deg", "homing_ticks", "lifetime_ticks", "radius_m", "pierce", "reflectable_by_parry", "hitbox"])
			out["speed"] = upt(_num(c, s, "speed_mps", p, true, 0.0, 0.1, 60.0))
			out["homing"] = turn_mrh(_num(c, s, "homing_deg", p, false, 0.0, 0.0, 720.0))
			out["homing_t"] = _int(c, s, "homing_ticks", p, false, 0, 0, 600)
			out["life"] = _int(c, s, "lifetime_ticks", p, true, 60, 1, 600)
			out["radius"] = um(_num(c, s, "radius_m", p, false, 0.5, 0.05, 3.0))
			out["pierce"] = 1 if _bool(c, s, "pierce", p, false) else 0
			out["reflectable"] = 1 if _bool(c, s, "reflectable_by_parry", p, false) else 0
			var hb: Variant = _obj(c, s, "hitbox", p, true)
			out["hitbox"] = _hitbox(c, hb, _p(p, "hitbox"), 1, windup, false) if hb != null else null
			if hb != null: out["blockable"] = int(out["hitbox"]["blockable"])
		"zone":
			_unknown(c, s, p, common + ["shape", "delay_ticks", "duration_ticks", "hitbox_every_ticks", "damage", "status", "hits_airborne"])
			out["shape"] = _shape(c, s, "shape", p, true)
			out["delay"] = _int(c, s, "delay_ticks", p, false, 0, 0, 600)
			out["duration"] = _int(c, s, "duration_ticks", p, true, 1, 1, 1200)
			out["every"] = _int(c, s, "hitbox_every_ticks", p, true, 1, 1, 600)
			out["dmg"] = milli(_num(c, s, "damage", p, true, 0.0, 0.0, 500.0))
			out["status"] = _status(c, _obj(c, s, "status", p, false), _p(p, "status"))
			out["hits_airborne"] = 1 if _bool(c, s, "hits_airborne", p, false) else 0
		"beam":
			_unknown(c, s, p, common + ["length_m", "width_m", "angle_deg", "duration_ticks", "tick_interval", "sweep_deg_per_sec", "damage", "stun_power"])
			out["len"] = um(_num(c, s, "length_m", p, true, 0.0, 0.1, 40.0))
			out["w"] = um(_num(c, s, "width_m", p, false, 0.0, 0.0, 10.0))
			out["cos_half"] = cos_half(_num(c, s, "angle_deg", p, false, 0.0, 0.0, 360.0)) if s.has("angle_deg") else 0
			if not s.has("width_m") and not s.has("angle_deg"):
				c.err(p, "SCHEMA", "beam necesita width_m o angle_deg")
			out["duration"] = _int(c, s, "duration_ticks", p, true, 1, 1, 600)
			out["interval"] = _int(c, s, "tick_interval", p, true, 1, 1, 600)
			out["sweep"] = turn_mrh(_num(c, s, "sweep_deg_per_sec", p, false, 0.0, 0.0, 360.0))
			out["dmg"] = milli(_num(c, s, "damage", p, true, 0.0, 0.0, 500.0))
			out["stun"] = milli(_num(c, s, "stun_power", p, false, 0.0, 0.0, 500.0))
		"summon":
			_unknown(c, s, p, common + ["entity", "hp", "lifetime_ticks", "cap"])
			out["entity"] = _str(c, s, "entity", p, true)
			out["hp"] = milli(_num(c, s, "hp", p, true, 1.0, 1.0, 1000.0))
			out["life"] = _int(c, s, "lifetime_ticks", p, true, 60, 1, 3600)
			out["cap"] = _int(c, s, "cap", p, false, 1, 1, 2)
	return out

## Congela recursivamente la estructura horneada (solo lectura).
static func _freeze(v: Variant) -> void:
	if v is Dictionary:
		for k: Variant in v:
			_freeze(v[k])
		(v as Dictionary).make_read_only()
	elif v is Array:
		for x: Variant in v:
			_freeze(x)
		(v as Array).make_read_only()
