class_name SimCatalog
extends RefCounted
## Ejecutor de las habilidades del catálogo por pasos (T_CATALOG).
## Enteros únicamente. Reusa los campos AB_* : no agrega estado ni sube el protocolo.
## Reloj: update() ya sumó 1 a AB_T; el tick del paso es AB_T - 1. El último tick válido
## es dur - 1. Si AB_T > dur, se pasa al paso siguiente y este tick no lo ejecuta.
## Recarga propia: un solo BOSS_CD = max(global, la de la habilidad). No hay un CD por ranura.
## La zona es una tanda de marcas de suelo (la piscina no tiene charco persistente).
## El sangrado es la acumulación que ya existe, no un daño periódico nuevo.

const INT_L1 := 1
const INT_L2 := 2
const INT_DOWN := 4
const INT_PARRY := 8
const BLEED_BUILD := 25000 ## por debajo del umbral: no estalla en un solo golpe
const CD_MASK := 65535

static func compile(f: Fighter, id: String) -> Dictionary:
	var a := HojaCatalog.ability(id)
	if a.is_empty():
		return {}
	var w := f.melee()
	var dm := SimParams._dmg_mult(f)
	var magia := float(f.ad.get("magia", 100.0)) / 100.0
	var st_k := float(f.tfx["stamina_cost"])
	var phys_f := StunRules.str_force(float(f.attributes().get("fuerza", 10))) + StunRules.weapon_force(w)
	var sd := float(f.ad.get("stun_dealt", 1.0))
	var mag_f := StunRules.magic_force(float(f.ad.get("magia", 100.0)))
	var ct: Array = _cost(a, st_k)
	var ai: Dictionary = a.get("ai", {})
	var weights := {}
	for pair: Variant in ai.get("branch_weights", []):
		var pw: Array = pair
		weights[int(pw[0])] = int(pw[1])
	var steps: Array = []
	var balt := 0
	for st: Dictionary in a.get("steps", []):
		var compiled := _step(st, dm, magia, phys_f, sd, mag_f)
		steps.append(compiled)
		if int(compiled["bra"]) >= 0:
			balt = int(weights.get(int(compiled["bra"]), balt))
	return {
		"code": SimAbilities.code_of(id), "id": id, "type": SimAbilities.T_CATALOG,
		"cost_type": int(ct[0]), "cost": int(ct[1]),
		"unbl": 0, "resist": 0, "raw": 0,
		"cd": int(a.get("cooldown", 0)), "imask": int(a.get("interrupt_mask", 0)),
		"phase": int(a.get("unlock_phase", 1)), "entry": int(a.get("entry", 0)),
		"rmin": int(ai.get("range_min", 0)), "rmax": int(ai.get("range_max", 0)),
		"balt": balt, "steps": steps,
	}

## El horneado ya trae el costo en milésimas. El aguante sigue el modificador del luchador.
static func _cost(a: Dictionary, st_k: float) -> Array:
	var c: Dictionary = a.get("cost", {})
	if int(c.get("health", 0)) > 0:
		return [2, int(c["health"])]
	if int(c.get("mana", 0)) > 0:
		return [1, int(c["mana"])]
	return [0, int(round(float(c.get("stamina", 0)) * st_k))]

## mili-rumbos/tick del horneado → rumbos/tick (0 se queda en 0).
static func _headings(mrh: int) -> int:
	if mrh <= 0:
		return 0
	return maxi(1, int(round(float(mrh) / 1000.0)))

static func _scaled(milli: int, scale: int, dm: float, magia: float) -> int:
	if scale == 2:
		return milli
	if scale == 1:
		return int(round(float(milli) * magia))
	return int(round(float(milli) * dm))

static func _stun(milli: int, scale: int, phys_f: float, sd: float, mag_f: float) -> int:
	var power := float(milli) / 1000.0
	if scale == 2:
		return SimParams.milli(power)
	if scale == 1:
		return SimParams.milli(mag_f + power)
	return SimParams.milli((phys_f + power) * sd)

static func _step(src: Dictionary, dm: float, magia: float, phys_f: float, sd: float, mag_f: float) -> Dictionary:
	var tr: Dictionary = src.get("tracking", {})
	var mv: Variant = src.get("movement", null)
	var mv_k := 0
	var mv0 := 0
	var mv1 := 0
	var spd := 0
	var maxd := 0
	var stop := 0
	var height := 0
	var mode := 0
	if mv is Dictionary:
		mv_k = int(mv.get("type", 0))
		if mv_k > 3:
			mv_k = 0
		mv0 = int(mv.get("from", 0))
		mv1 = int(mv.get("to", 0))
		spd = int(mv.get("speed", 0))
		maxd = int(mv.get("max", 0))
		stop = int(mv.get("stop", 0))
		height = int(mv.get("height", 0))
		mode = 1 if int(mv.get("target", 0)) == 2 else 0
	var hb: Dictionary = {}
	var boxes: Array = src.get("hitboxes", [])
	if not boxes.is_empty() and boxes[0] is Dictionary:
		hb = boxes[0]
	var shape: Dictionary = hb.get("shape", {}) if hb.get("shape") is Dictionary else {}
	var hb_k := 0
	var hbr := 0
	var hbw := 0
	var hbcos := 0
	match int(shape.get("type", -1)):
		0:
			hb_k = 4
			hbr = int(shape.get("r", 0))
		1:
			hb_k = 1
			hbr = int(shape.get("r", 0))
			hbcos = int(shape.get("cos_half", 0))
		2:
			hb_k = 2
			hbr = int(shape.get("len", 0))
			hbw = int(shape.get("w", 0))
		3:
			hb_k = 4
			hbr = int(shape.get("outer", 0))
		4:
			hb_k = 3
			hbr = int(shape.get("len", 0))
			hbw = int(shape.get("w", 0))
	var armor: Variant = src.get("armor", null)
	var arm_k := 0
	var af := 0
	var at := 0
	var poise := 0
	if armor is Dictionary:
		arm_k = 2 if int(armor.get("type", 0)) == 0 else 1
		af = int(armor.get("from", 0))
		at = int(armor.get("to", 0))
		poise = int(armor.get("poise_pm", 0))
	var inv: Variant = src.get("invuln", null)
	var br: Variant = src.get("branch", null)
	var brs := -1
	var bra := -1
	var br0 := -1
	var br1 := -1
	var brbuf := 0
	var brd := -1
	var blab := ""
	if br is Dictionary:
		br0 = int(br.get("from", -1))
		br1 = int(br.get("to", -1))
		brbuf = int(br.get("buffer", 0))
		brd = int(br.get("default", -1))
		for op: Variant in br.get("options", []):
			if not (op is Dictionary):
				continue
			if int((op as Dictionary).get("input", 0)) == 1:
				bra = int((op as Dictionary).get("step", -1))
				blab = String((op as Dictionary).get("label", ""))
			elif int((op as Dictionary).get("input", 0)) == 0:
				brs = int((op as Dictionary).get("step", -1))
	var nxt := -1
	var nx: Variant = src.get("next", null)
	if nx is Dictionary:
		nxt = int(nx.get("default", -1))
	var spawn: Dictionary = {}
	for sp: Variant in src.get("spawns", []):
		if sp is Dictionary and int((sp as Dictionary).get("type", -1)) == 3:
			spawn = sp
			break
	var sp_shape: Dictionary = spawn.get("shape", {}) if spawn.get("shape") is Dictionary else {}
	var delay := int(spawn.get("delay", 0))
	var every := maxi(int(spawn.get("every", 30)), 1)
	var dur_z := int(spawn.get("duration", 0))
	var pulses := 0
	if not spawn.is_empty():
		var at_z := delay
		while at_z < delay + dur_z and pulses < 8:
			pulses += 1
			at_z += every
	var st: Variant = hb.get("status", null)
	var bleed := 1 if st is Dictionary and int((st as Dictionary).get("type", -1)) == 0 else 0
	var sp_st: Variant = spawn.get("status", null)
	return {
		"w": int(src.get("windup", 0)), "a": int(src.get("active", 0)), "r": int(src.get("recovery", 0)),
		"dur": int(src.get("total", 0)),
		"trk": _headings(int(tr.get("turn", 0))),
		"trk2": _headings(int(tr.get("post", 0))),
		"lock": int(tr.get("lock", 0)),
		"mv": mv_k, "mv0": mv0, "mv1": mv1, "spd": spd, "maxd": maxd, "stop": stop, "height": height, "mode": mode,
		"hb": hb_k, "hbr": hbr, "hbw": hbw, "hbcos": hbcos,
		"hbf": int(hb.get("from", 0)), "hbt": int(hb.get("to", 0)),
		"off": int(hb.get("fwd", 0)),
		"raw": _scaled(int(hb.get("dmg", 0)), int(hb.get("dmg_scaling", 0)), dm, magia),
		"force": _stun(int(hb.get("stun", 0)), int(hb.get("stun_scaling", 0)), phys_f, sd, mag_f),
		"parry": int(hb.get("parryable", 1)),
		"ls": int(hb.get("lifesteal_pm", 0)) / 10,
		"kb": int(hb.get("knock_speed", 0)),
		"ground": int(hb.get("ground_only", 0)),
		"bleed": bleed,
		"armor": arm_k, "af": af, "at": at, "poise": poise,
		"inv0": int(inv.get("from", -1)) if inv is Dictionary else -1,
		"inv1": int(inv.get("to", -1)) if inv is Dictionary else -1,
		"invpm": int(inv.get("dmg_taken_pm", 1000)) if inv is Dictionary else 1000,
		"nxt": nxt,
		"br0": br0, "br1": br1, "brbuf": brbuf, "brs": brs, "bra": bra, "brd": brd, "blab": blab,
		"spawn": 0 if spawn.is_empty() else 1,
		"spat": int(spawn.get("at", -1)),
		"spr": int(sp_shape.get("r", 0)),
		"spn": pulses, "spev": every,
		"spraw": _scaled(int(spawn.get("dmg", 0)), 0, dm, magia),
		"spdelay": delay,
		"spbleed": 1 if sp_st is Dictionary and int((sp_st as Dictionary).get("type", -1)) == 0 else 0,
	}

# ---------------- consulta (con P, durante el golpe) ----------------

static func _alive(s: PackedInt64Array, o: int) -> bool:
	return s[o + FightSim.AB_SLOT] >= 0 and (s[o + FightSim.AB_FL] & SimAbilities.FL_CATALOG) != 0

static func _step_of(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	var o := i * FightSim.F_FIELDS
	var ab: Dictionary = P[i]["boss"][s[o + FightSim.AB_SLOT]]
	var steps: Array = ab.get("steps", [])
	var si: int = s[o + FightSim.AB_FIRED]
	if si < 0 or si >= steps.size():
		return {}
	return steps[si]

static func _t(s: PackedInt64Array, o: int) -> int:
	return s[o + FightSim.AB_T] - 1

static func incoming_pm(s: PackedInt64Array, P: Array, d: int) -> int:
	var o := d * FightSim.F_FIELDS
	if not _alive(s, o):
		return 1000
	var step := _step_of(s, P, d)
	if step.is_empty() or int(step.get("inv0", -1)) < 0:
		return 1000
	var t := _t(s, o)
	if t >= int(step["inv0"]) and t < int(step["inv1"]):
		return int(step["invpm"])
	return 1000

static func skip_stun(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return false
	var step := _step_of(s, P, i)
	if step.is_empty():
		return false
	var t := _t(s, o)
	if int(step["armor"]) == 2 and t >= int(step["af"]) and t < int(step["at"]):
		return true
	if int(step["inv0"]) >= 0 and t >= int(step["inv0"]) and t < int(step["inv1"]):
		return true
	return false

static func resist_now(s: PackedInt64Array, P: Array, i: int) -> int:
	var o := i * FightSim.F_FIELDS
	var step := _step_of(s, P, i)
	if step.is_empty():
		return 0
	var t := _t(s, o)
	if int(step["armor"]) == 1 and t >= int(step["af"]) and t < int(step["at"]):
		return int(step["poise"])
	return 0

static func stun_interrupts(s: PackedInt64Array, o: int, t: int) -> bool:
	var mask := (s[o + FightSim.AB_WAIT] >> 16) & 255
	if t == FightSim.T_STAGGER:
		return (mask & INT_L1) != 0
	if t == FightSim.T_STUN:
		return (mask & INT_L2) != 0
	if t == FightSim.T_DOWN + FightSim.T_GETUP:
		return (mask & INT_DOWN) != 0
	return false

## El parry ya decidió que el golpe no entra. Si la habilidad lo lista, se corta antes del aturdimiento.
static func on_parry(s: PackedInt64Array, att: int) -> void:
	var o := att * FightSim.F_FIELDS
	if not _alive(s, o):
		return
	if ((s[o + FightSim.AB_WAIT] >> 16) & INT_PARRY) == 0:
		return
	SimAbilities.end_ability(s, o, true)

static func cancel_zones(s: PackedInt64Array, owner: int) -> void:
	for j in FightSim.HZ_MAX:
		var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
		if s[q + FightSim.HZ_ON] == 0 or s[q + FightSim.HZ_OWNER] != owner:
			continue
		if s[q + FightSim.HZ_TYPE] == 1 and s[q + FightSim.HZ_DONE] == 0:
			s[q + FightSim.HZ_ON] = 0

static func alt_window(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return false
	var step := _step_of(s, P, i)
	if step.is_empty() or int(step.get("br0", -1)) < 0 or String(step.get("blab", "")) == "":
		return false
	var t := _t(s, o)
	return t >= int(step["br0"]) - int(step.get("brbuf", 0)) and t < int(step["br1"])

static func alt_label(s: PackedInt64Array, P: Array, i: int) -> String:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return ""
	return String(_step_of(s, P, i).get("blab", ""))

static func latch(s: PackedInt64Array, P: Array, i: int, alt: bool) -> bool:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return false
	var step := _step_of(s, P, i)
	if step.is_empty() or int(step["br0"]) < 0:
		return false
	var t := _t(s, o)
	if t < int(step["br0"]) - int(step["brbuf"]) or t >= int(step["br1"]):
		return false
	if alt:
		s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_QUEUED) | SimAbilities.FL_VARIANT
	else:
		s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_VARIANT) | SimAbilities.FL_QUEUED
	return true

# ---------------- tick ----------------

static func tick(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var steps: Array = ab.get("steps", [])
	var si: int = s[o + FightSim.AB_FIRED]
	if si < 0 or si >= steps.size():
		SimAbilities.end_ability(s, o, false)
		return
	var step: Dictionary = steps[si]
	if s[o + FightSim.AB_T] > int(step["dur"]):
		_advance(s, P, i, step, steps)
		return
	var t := _t(s, o)
	_track(s, i, step, t)
	_horiz(s, i, step, t)
	_vert(s, o, step, t)
	_hit(s, P, i, step, t)
	_spawn(s, P, i, step, t)

static func _advance(s: PackedInt64Array, P: Array, i: int, step: Dictionary, steps: Array) -> void:
	var o := i * FightSim.F_FIELDS
	var nxt := int(step["nxt"])
	if int(step["br0"]) >= 0:
		var fl: int = s[o + FightSim.AB_FL]
		if (fl & SimAbilities.FL_VARIANT) != 0:
			nxt = int(step["bra"])
		elif (fl & SimAbilities.FL_QUEUED) != 0:
			nxt = int(step["brs"])
		else:
			nxt = int(step["brd"])
	if nxt < 0 or nxt >= steps.size():
		SimAbilities.end_ability(s, o, false)
		return
	var keep: int = s[o + FightSim.AB_FL] & SimAbilities.FL_CATALOG
	s[o + FightSim.AB_FIRED] = nxt
	s[o + FightSim.AB_T] = 0
	s[o + FightSim.AB_TICK] = 0
	s[o + FightSim.AB_VX] = 0
	s[o + FightSim.AB_VZ] = 0
	s[o + FightSim.AB_FL] = keep
	s[o + FightSim.AB_FX] = s[o + FightSim.X]
	s[o + FightSim.AB_FZ] = s[o + FightSim.Z]

static func _track(s: PackedInt64Array, i: int, step: Dictionary, t: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var locked := (s[o + FightSim.AB_FL] & SimAbilities.FL_LOCKED) != 0
	if not locked and s[b + FightSim.ALIVE] != 0:
		s[o + FightSim.AB_X] = s[b + FightSim.X]
		s[o + FightSim.AB_Z] = s[b + FightSim.Z]
	if t >= int(step["lock"]) and not locked:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LOCKED
		locked = true
	var rate: int = int(step["trk2"]) if locked else int(step["trk"])
	if rate <= 0 or s[b + FightSim.ALIVE] == 0:
		return
	var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
	var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
	if FxMath.length(dx, dz) <= 100000:
		return
	s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], FxMath.dir_of(dx, dz, s[o + FightSim.FACE]), rate)

static func _horiz(s: PackedInt64Array, i: int, step: Dictionary, t: int) -> void:
	var mv := int(step["mv"])
	if mv == 0 or t < int(step["mv0"]) or t >= int(step["mv1"]):
		return
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var maxd: int = int(step["maxd"])
	if maxd > 0 and s[o + FightSim.AB_TICK] >= maxd:
		return
	var dx: int
	var dz: int
	if int(step["mode"]) == 1 or mv == 3:
		dx = s[o + FightSim.AB_X] - s[o + FightSim.X]
		dz = s[o + FightSim.AB_Z] - s[o + FightSim.Z]
	else:
		dx = s[b + FightSim.X] - s[o + FightSim.X]
		dz = s[b + FightSim.Z] - s[o + FightSim.Z]
	var dist := FxMath.length(dx, dz)
	var stop: int = int(step["stop"])
	if mv != 3 and stop > 0 and dist <= stop:
		return
	var f: int = s[o + FightSim.FACE]
	if (int(step["mode"]) == 1 or mv == 3) and dist > 100000:
		f = FxMath.dir_of(dx, dz, f)
		s[o + FightSim.FACE] = f
	var spd: int
	if mv == 3:
		var left: int = int(step["mv1"]) - t
		var room: int = dist
		if maxd > 0:
			room = mini(room, maxd - s[o + FightSim.AB_TICK])
		spd = room / maxi(left, 1)
	else:
		spd = int(step["spd"])
		if maxd > 0:
			spd = mini(spd, maxd - s[o + FightSim.AB_TICK])
		if stop > 0:
			spd = mini(spd, maxi(dist - stop, 0))
	if spd <= 0:
		return
	s[o + FightSim.AB_VX] = FxMath.COS[f] * spd / FxMath.ONE
	s[o + FightSim.AB_VZ] = FxMath.SIN[f] * spd / FxMath.ONE
	s[o + FightSim.AB_TICK] += spd

static func _set_fy(s: PackedInt64Array, o: int, h: int) -> void:
	if s[o + FightSim.AIR] == 0:
		s[o + FightSim.AIR] = 1
		s[o + FightSim.AIR_T] = 0
		s[o + FightSim.FVY] = h - s[o + FightSim.FY]
	else:
		s[o + FightSim.FVY] = h - s[o + FightSim.FY] + FightSim.GRAVITY_T

static func _vert(s: PackedInt64Array, o: int, step: Dictionary, t: int) -> void:
	var mv := int(step["mv"])
	if (mv != 2 and mv != 3) or t < int(step["mv0"]) or t >= int(step["mv1"]):
		return
	var n: int = int(step["mv1"]) - int(step["mv0"])
	if n <= 0:
		return
	var u: int = t - int(step["mv0"])
	if mv == 2:
		var h: int = int(step["height"]) * (2 * u + 1) * (2 * n - 2 * u - 1) / (n * n)
		_set_fy(s, o, h)
		return
	if u == 0:
		s[o + FightSim.AB_FX] = maxi(s[o + FightSim.FY], 1)
	var h2: int = int(s[o + FightSim.AB_FX]) * (n - u - 1) / n
	_set_fy(s, o, h2)

static func _hit(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if int(step["hb"]) == 0:
		return
	var o := i * FightSim.F_FIELDS
	var fl: int = s[o + FightSim.AB_FL]
	if (fl & (SimAbilities.FL_LANDED | SimAbilities.FL_COUNTERED)) != 0:
		return
	var ta := t - int(step["w"])
	if ta < int(step["hbf"]) or ta >= int(step["hbt"]):
		return
	var b := FightSim._opp(i)
	if s[b + FightSim.ALIVE] == 0:
		return
	if int(step["ground"]) != 0 and (s[b + FightSim.AIR] != 0 or s[b + FightSim.FY] >= FightSim.GROUND_H):
		return
	if not _overlaps(s, o, b, P[1 - i]["hit_radius"], step):
		return
	var before: int = s[o + FightSim.DMG_DEALT]
	var kind := 0
	var parry := int(step["parry"]) != 0
	var st: Array = [BLEED_BUILD, 0, 0] if int(step["bleed"]) != 0 else []
	var raw := SimAbilities.raw_live(s, P, i, int(step["raw"]))
	var res := FightSim._take_hit(s, P, i, kind, raw, 0, int(step["force"]), 1000, 1000, 0, -1, st, false, parry)
	if s[o + FightSim.AB_SLOT] < 0:
		return
	if res == 1:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LANDED
		s[o + FightSim.AB_HITS] += 1
		var kb: int = int(step["kb"])
		if kb > 0:
			var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
			var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
			var l := FxMath.length(dx, dz)
			if l > 100000:
				s[b + FightSim.KX] = dx * kb / l
				s[b + FightSim.KZ] = dz * kb / l
			else:
				var f: int = s[o + FightSim.FACE]
				s[b + FightSim.KX] = FxMath.COS[f] * kb / FxMath.ONE
				s[b + FightSim.KZ] = FxMath.SIN[f] * kb / FxMath.ONE
	elif res == 2 or res == 3:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_COUNTERED
	var dealt: int = s[o + FightSim.DMG_DEALT] - before
	var ls: int = int(step["ls"])
	if dealt > 0 and ls > 0 and (res == 1 or res == 2):
		s[o + FightSim.HP] = mini(s[o + FightSim.HP] + dealt * ls / 100, int(P[i]["hp"]))

static func _overlaps(s: PackedInt64Array, o: int, b: int, hr: int, step: Dictionary) -> bool:
	var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
	var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
	var f: int = s[o + FightSim.FACE]
	var along: int = (dx * FxMath.COS[f] + dz * FxMath.SIN[f]) / FxMath.ONE
	var side: int = absi(dx * FxMath.SIN[f] - dz * FxMath.COS[f]) / FxMath.ONE
	var dist := FxMath.length(dx, dz)
	match int(step["hb"]):
		1:
			if dist > int(step["hbr"]) + hr:
				return false
			if dist <= 200000:
				return true
			return along * FxMath.ONE >= int(step["hbcos"]) * dist
		2, 3:
			var near: int = int(step["off"])
			var far: int = near + int(step["hbr"])
			if along + hr < near or along > far + hr:
				return false
			return side <= int(step["hbw"]) / 2 + hr
		4:
			return dist <= int(step["hbr"]) + hr
	return false

static func _spawn(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if int(step["spawn"]) == 0 or t != int(step["spat"]):
		return
	var o := i * FightSim.F_FIELDS
	if (s[o + FightSim.AB_FL] & SimAbilities.FL_READY) != 0:
		return
	s[o + FightSim.AB_FL] |= SimAbilities.FL_READY
	var n: int = int(step["spn"])
	var raw := SimAbilities.raw_live(s, P, i, int(step["spraw"]))
	for k in n:
		var warn: int = int(step["spdelay"]) + k * int(step["spev"])
		var j := SimAbilities.spawn_hz(s, i, 1, s[o + FightSim.X], s[o + FightSim.Z], warn, int(step["spr"]), raw, 0, 0, 0)
		if j < 0:
			return
		if int(step["spbleed"]) != 0:
			var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
			s[q + FightSim.HZ_KIND] = 1

## La marca de suelo del catálogo acumula sangrado al conectar. La piscina no guarda un DoT.
static func on_zone_hit(s: PackedInt64Array, P: Array, owner: int) -> void:
	FightSim._add_status(s, P, owner, 0, BLEED_BUILD)
