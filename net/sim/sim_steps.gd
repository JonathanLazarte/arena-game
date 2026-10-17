class_name SimSteps
extends RefCounted
## Motor de pasos (etapa 1). Con SimParams.ab_engine == 1 ejecuta las habilidades migradas
## del catálogo `data/abilities/catalog.json`. Apagado, no se usa.
##
## Reloj: update() ya sumó 1 a AB_T. t_step = AB_T - 1. Los ticks del JSON están en t_step
## (0 = primer tick). El camino viejo compara contra AB_T: un umbral H del viejo es el tick
## H - 1 del catálogo. Así el mismo golpe cae en el mismo tick.
##
## Checksum: estas cuatro no prenden FL_CATALOG ni escriben campos que el camino viejo deja
## en cero (AB_TICK, AB_WAIT, AB_IMM). La recarga sigue siendo la global de 85, el costo de
## vida se rechaza si dejaría 0 (SimAbilities._cost_ok) y cualquier aturdimiento corta.
## El daño del catálogo, en esta etapa, es el multiplicador del fuerte del arma (el esquema
## aún no tiene ese escalado: ver la pregunta al final de la etapa).

const PATH := "res://data/abilities/catalog.json"
const IDS: Array[String] = [
	"tajo_retardado", "estocada_negra", "pisoton", "flecha_grave",
	"presa_verdugo", "giro_martillo", "danza_cisne", "paso_espectral",
	"cuerno_embiste", "tajo_cruzado", "zarpazo_sangre", "barrido_cola", "daga_sagrada", "flor_umbral",
	"presa_fauces", "giro_noble", "danza_triple", "alas_picado",
]
const EXEC_TIMELINE := 0
const EXEC_WAVE := 1
const EXEC_RAIN := 2
const EXEC_GRAPH := 3
const SP_MARK := 0
const SP_WAVE := 1
const COMMIT_END := 0
const COMMIT_NOW := 1

static var _by_id: Dictionary = {}

static func handles(id: String) -> bool:
	return id in IDS

## El programa numérico es el del camino viejo. Acá se cambia el tipo y se lee la máscara.
static func wrap(c: Dictionary, id: String) -> Dictionary:
	c["family"] = int(c["type"])
	c["type"] = SimAbilities.T_STEPS
	c["imask"] = _mask(id)
	c["graph"] = 0
	c["evs"] = _events_of(id)
	return c

static func _events_of(id: String) -> Array:
	var out: Array = []
	var a: Dictionary = catalog().get(id, {})
	var steps: Array = a.get("steps", [])
	for st: Dictionary in steps:
		var evs: Array = st.get("events", [])
		for ev: Dictionary in evs:
			out.append({"id": String(ev.get("id", "")), "tick": int(ev.get("tick", 0)), "step": int(st.get("index", 0))})
	return out

static func _mask(id: String) -> int:
	var a: Dictionary = catalog().get(id, {})
	return int(a.get("interrupt_mask", 0))

static func wants_parry(id: String) -> bool:
	return (_mask(id) & (1 << 3)) != 0

## true = este aturdimiento no corta la habilidad ni se le aplica mientras dura.
static func ignores_stun(ab: Dictionary, dur: int) -> bool:
	if int(ab.get("type", -1)) != SimAbilities.T_STEPS:
		return false
	var bit := -1
	if dur == FightSim.T_STAGGER:
		bit = 0
	elif dur == FightSim.T_STUN:
		bit = 1
	elif dur == FightSim.T_DOWN + FightSim.T_GETUP:
		bit = 2
	else:
		return false
	return (int(ab.get("imask", 0)) & (1 << bit)) == 0

static func catalog() -> Dictionary:
	if _by_id.is_empty():
		var res := AbilityCatalog.load_file(PATH)
		if not bool(res.get("ok", false)):
			push_error("SimSteps: catálogo inválido\n%s" % AbilityCatalog.format_issues(res))
			return _by_id
		var baked: Dictionary = res["baked"]
		var abs: Array = baked["abilities"]
		for a: Dictionary in abs:
			var id := String(a.get("id", ""))
			if id in IDS:
				_by_id[id] = a
	return _by_id

static func compile(f: Fighter, id: String) -> Dictionary:
	var a: Dictionary = catalog().get(id, {})
	if a.is_empty():
		return {}
	var steps: Array = a.get("steps", [])
	if steps.is_empty():
		return {}
	var st: Dictionary = steps[0]
	var leg := BossAbilities.def(id)
	var w := f.melee()
	var dm := SimParams._dmg_mult(f)
	var magia := float(f.ad.get("magia", 100.0)) / 100.0
	var st_k := float(f.tfx["stamina_cost"])
	var phys_f := StunRules.str_force(float(f.attributes().get("fuerza", 10))) + StunRules.weapon_force(w)
	var sd := float(f.ad.get("stun_dealt", 1.0))
	var mag_f := StunRules.magic_force(float(f.ad.get("magia", 100.0)))
	var wpn := w.light_damage if bool(leg.get("light", false)) else w.heavy_damage
	var magic := bool(leg.get("magic", false))
	var c := {
		"code": SimAbilities.code_of(id), "id": id, "type": SimAbilities.T_STEPS,
		"cost_type": 0, "cost": 0, "unbl": 1 if BossAbilities.is_unblockable(id) else 0,
		"resist": _resist(st), "raw": 0, "exec": EXEC_TIMELINE, "family": SimAbilities.T_TIMELINE,
		"graph": 0, "end": int(st.get("total", 1)), "evs": _events(st),
		"arm0": 0, "arm1": 0,
	}
	var cost: Dictionary = a.get("cost", {})
	if int(cost.get("health", 0)) > 0:
		c["cost_type"] = 2
		c["cost"] = int(cost["health"])
	elif int(cost.get("mana", 0)) > 0:
		c["cost_type"] = 1
		c["cost"] = int(cost["mana"])
	else:
		c["cost_type"] = 0
		c["cost"] = int(round(float(cost.get("stamina", 0)) * st_k))
	var armor: Variant = st.get("armor", null)
	if armor is Dictionary:
		c["arm0"] = int(armor.get("from", 0))
		c["arm1"] = int(armor.get("to", 0))
	var boxes: Array = st.get("hitboxes", [])
	var spawns: Array = st.get("spawns", [])
	var wave: Dictionary = {}
	var mark: Dictionary = {}
	for sp: Dictionary in spawns:
		if int(sp.get("type", -1)) == SP_WAVE and wave.is_empty():
			wave = sp
		elif int(sp.get("type", -1)) == SP_MARK and mark.is_empty():
			mark = sp
	if not wave.is_empty():
		_as_wave(c, st, wave, wpn, dm, magia, magic, phys_f, sd, mag_f)
	elif boxes.is_empty() and not mark.is_empty():
		_as_rain(c, st, mark, wpn, dm, magia, magic, phys_f, sd, mag_f)
	else:
		_as_timeline(c, st, boxes, mark, wpn, dm, magia, magic, phys_f, sd, mag_f)
	return c

static func _resist(st: Dictionary) -> int:
	var armor: Variant = st.get("armor", null)
	if armor is Dictionary and int(armor.get("type", 1)) != 0:
		return int(armor.get("poise_pm", 0))
	return 0

static func _events(st: Dictionary) -> Array:
	var out: Array = []
	for ev: Dictionary in st.get("events", []):
		out.append({"id": String(ev.get("id", "")), "tick": int(ev.get("tick", 0)), "step": 0})
	return out

static func _raw(wpn: float, dm: float, magia: float, dmg_milli: int, magic: bool) -> int:
	var base := wpn * dm * (float(dmg_milli) / 1000.0)
	if magic:
		base *= magia
	return SimParams.milli(base)

static func _stun(milli: int, scale: int, phys_f: float, sd: float, mag_f: float) -> int:
	var power := float(milli) / 1000.0
	if scale == 2:
		return SimParams.milli(power)
	if scale == 1:
		return SimParams.milli(mag_f + power)
	return SimParams.milli((phys_f + power) * sd)

static func _rate(mrh: int) -> int:
	if mrh <= 0:
		return 0
	return maxi(1, int(round(float(mrh) / 1000.0)))

static func _track_of(st: Dictionary) -> Dictionary:
	var tr: Dictionary = st.get("tracking", {})
	return {"rate": _rate(int(tr.get("turn", 0))), "lock": int(tr.get("lock", 0))}

static func _move_of(st: Dictionary) -> Dictionary:
	var mv: Variant = st.get("movement", null)
	if not (mv is Dictionary) or int((mv as Dictionary).get("type", 0)) == 0:
		return {"on": 0, "from": 0, "to": 0, "spd": 0, "stop": 0}
	var m: Dictionary = mv
	return {"on": 1, "from": int(m.get("from", 0)), "to": int(m.get("to", 0)), "spd": int(m.get("speed", 0)), "stop": int(m.get("stop", 0))}

static func _as_timeline(c: Dictionary, st: Dictionary, boxes: Array, mark: Dictionary, wpn: float, dm: float, magia: float, magic: bool, phys_f: float, sd: float, mag_f: float) -> void:
	c["exec"] = EXEC_TIMELINE
	c["family"] = SimAbilities.T_TIMELINE
	var hb: Dictionary = boxes[0] if not boxes.is_empty() else {}
	var scale := 1 if magic or int(hb.get("dmg_scaling", 0)) == 1 else int(hb.get("dmg_scaling", 0))
	var use_magic := scale == 1
	c["raw"] = _raw(wpn, dm, magia, int(hb.get("dmg", 0)), use_magic)
	c["force"] = _stun(int(hb.get("stun", 0)), int(hb.get("stun_scaling", 0)), phys_f, sd, mag_f)
	c["kind"] = 3 if int(hb.get("blockable", 1)) == 0 else 0
	c["reach"] = int(hb.get("shape", {}).get("r", 0)) if hb.get("shape") is Dictionary else 0
	c["cos"] = int(hb.get("shape", {}).get("cos_half", 0)) if hb.get("shape") is Dictionary else 0
	c["pd"] = 2000 if int(c["kind"]) == 3 else 1000
	var tr := _track_of(st)
	c["track"] = tr["rate"]
	c["lock"] = tr["lock"]
	var mv := _move_of(st)
	c["mv"] = mv
	c["hit_at"] = int(st.get("windup", 0))
	if mark.is_empty():
		c["slam"] = 0
	else:
		var k := 0
		var body := int(hb.get("dmg", 0))
		if body > 0:
			k = int(mark.get("dmg", 0)) * 1000 / body
		var sh: Dictionary = mark.get("shape", {}) if mark.get("shape") is Dictionary else {}
		c["slam"] = 1
		c["slam_r"] = int(sh.get("r", 0))
		c["slam_warn"] = int(mark.get("warn", 0))
		c["slam_k"] = k
		c["slam_force"] = _stun(int(mark.get("stun", 0)), 0, phys_f, sd, mag_f)
		c["slam_fwd"] = int(mark.get("fwd", 0))
		c["slam_knock"] = int(mark.get("knock", 150000))
		c["slam_on"] = int(mark.get("on", 0))

static func _as_wave(c: Dictionary, st: Dictionary, wave: Dictionary, wpn: float, dm: float, magia: float, magic: bool, phys_f: float, sd: float, mag_f: float) -> void:
	c["exec"] = EXEC_WAVE
	c["family"] = SimAbilities.T_WAVE
	c["raw"] = _raw(wpn, dm, magia, int(wave.get("dmg", 0)), magic)
	c["force"] = _stun(int(wave.get("stun", 0)), 0, phys_f, sd, mag_f)
	var tr := _track_of(st)
	c["turn"] = tr["rate"] if int(tr["rate"]) > 0 else 1
	c["lock"] = int(st.get("windup", tr["lock"]))
	var cnt := int(wave.get("count", 1))
	var spread := int(wave.get("spread", 0))
	var ring := int(wave.get("ring", 0)) != 0
	var offs: Array = []
	for i in cnt:
		var ang := i * spread if ring else i * spread - (cnt - 1) * spread / 2
		offs.append(-ang)
	c["offs"] = offs
	c["spd"] = int(wave.get("speed", 0))
	c["range"] = int(wave.get("range", 0))
	c["width"] = int(wave.get("width", 0))
	c["warn"] = int(wave.get("warn", 0))
	c["fwd"] = int(wave.get("fwd", 1000000))
	c["spawn_at"] = int(wave.get("at", int(st.get("windup", 0))))

static func _as_rain(c: Dictionary, st: Dictionary, mark: Dictionary, wpn: float, dm: float, magia: float, magic: bool, phys_f: float, sd: float, mag_f: float) -> void:
	c["exec"] = EXEC_RAIN
	c["family"] = SimAbilities.T_RAIN
	c["raw"] = _raw(wpn, dm, magia, int(mark.get("dmg", 0)), magic)
	c["force"] = _stun(int(mark.get("stun", 0)), 1, phys_f, sd, mag_f)
	var sh: Dictionary = mark.get("shape", {}) if mark.get("shape") is Dictionary else {}
	c["r"] = int(sh.get("r", sh.get("outer", 0)))
	c["warn"] = int(mark.get("warn", 0))
	c["knock"] = int(mark.get("knock", 0))
	c["unbl"] = 0 if int(mark.get("blockable", 1)) != 0 else 1
	c["scatter"] = 1 if int(mark.get("mode", 0)) != 0 else 0
	c["scatter_r"] = int(mark.get("scatter_r", 0))
	var n := maxi(int(mark.get("count", 1)), 1)
	var iv := int(mark.get("interval", 0))
	var t0 := int(mark.get("at", int(st.get("windup", 0))))
	var fire: Array = []
	for i in n:
		fire.append(t0 + i * iv)
	c["fire"] = fire

# ---------------- tick ----------------

static func resist_now(s: PackedInt64Array, P: Array, i: int) -> int:
	var o := i * FightSim.F_FIELDS
	var ab := SimAbilities._ab(s, P, i)
	if int(ab.get("arm1", 0)) <= int(ab.get("arm0", 0)):
		return int(ab.get("resist", 0))
	var ts := s[o + FightSim.AB_T] - 1
	if ts < 0:
		ts = 0
	if ts >= int(ab["arm0"]) and ts < int(ab["arm1"]):
		return int(ab.get("resist", 0))
	return 0

static func latch(s: PackedInt64Array, P: Array, i: int, alt: bool) -> bool:
	var o := i * FightSim.F_FIELDS
	var ab := SimAbilities._ab(s, P, i)
	if int(ab.get("graph", 0)) == 0:
		return false
	var step := _gstep(ab, s[o + FightSim.AB_FIRED])
	var br: Variant = step.get("branch", null)
	if not (br is Dictionary):
		var cancel: Variant = step.get("cancel", null)
		if cancel is Dictionary and int(cancel.get("trigger", 0)) == 1 and not alt:
			return _latch_bits(s, o, step, false)
		return false
	if (s[o + FightSim.AB_FL] & SimAbilities.FL_READY) != 0:
		return true
	var t := s[o + FightSim.AB_T] - 1
	var b: Dictionary = br
	if t < int(b["from"]) - int(b.get("buffer", 0)) or t >= int(b["to"]):
		return false
	if alt:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_VARIANT
	else:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_QUEUED
	return true

static func _latch_bits(s: PackedInt64Array, o: int, step: Dictionary, _alt: bool) -> bool:
	var cancel: Dictionary = step["cancel"]
	var t := s[o + FightSim.AB_T] - 1
	if t < int(cancel["from"]) or t >= int(cancel["to"]):
		return false
	if (s[o + FightSim.AB_FL] & SimAbilities.FL_READY) != 0:
		return true
	s[o + FightSim.AB_FL] |= SimAbilities.FL_QUEUED
	return true

static func tick(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	if int(ab.get("graph", 0)) != 0:
		_graph(s, P, i, ab)
		return
	var o := i * FightSim.F_FIELDS
	match SimAbilities.kind_of(ab):
		SimAbilities.T_TIMELINE:
			SimAbilities._timeline(s, P, i, ab)
		SimAbilities.T_WAVE:
			SimAbilities._wave(s, P, i, ab)
		SimAbilities.T_RAIN:
			SimAbilities._rain(s, P, i, ab)
		SimAbilities.T_BREATH:
			SimAbilities._breath(s, P, i, ab)
		SimAbilities.T_RAFAGA:
			SimAbilities._rafaga(s, P, i, ab)
		SimAbilities.T_SALTO:
			SimAbilities._salto(s, P, i, ab)
		SimAbilities.T_COMBO:
			SimAbilities._combo(s, P, i, ab)
		SimAbilities.T_CARGA:
			if s[o + FightSim.AB_T] >= int(ab["end"]):
				SimAbilities.end_ability(s, o, false)
		SimAbilities.T_ESCUDO:
			if s[o + FightSim.AB_T] >= int(ab["w"]):
				s[o + FightSim.INVULN] = maxi(s[o + FightSim.INVULN], 3)
			if s[o + FightSim.AB_T] >= int(ab["end"]):
				s[o + FightSim.INVULN] = 0
				SimAbilities.end_ability(s, o, false)
		SimAbilities.T_RAGE:
			if s[o + FightSim.AB_FIRED] == 0 and s[o + FightSim.AB_T] >= int(ab["w"]):
				s[o + FightSim.AB_FIRED] = 1
				s[o + FightSim.RAGE_T] = ab["dur"]
			if s[o + FightSim.AB_T] >= int(ab["end"]):
				SimAbilities.end_ability(s, o, false)
		SimAbilities.T_COUNTER:
			var done: bool = s[o + FightSim.AB_T] >= int(ab["ws"]) + int(ab["rec_hit"]) if (s[o + FightSim.AB_FL] & SimAbilities.FL_COUNTERED) != 0 else s[o + FightSim.AB_T] >= int(ab["end_miss"])
			if done:
				SimAbilities.end_ability(s, o, false)

static func _flick(s: PackedInt64Array, o: int, ab: Dictionary, ts: int) -> void:
	for ev: Dictionary in ab.get("evs", []):
		if ts < int(ev.get("tick", 0)):
			continue
		var id := String(ev.get("id", ""))
		if id == "ev_flick0":
			s[o + FightSim.AB_FL] |= SimAbilities.FL_FLICK0
		elif id == "ev_flick1":
			s[o + FightSim.AB_FL] |= SimAbilities.FL_FLICK1

static func _timeline(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, ts: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	if s[o + FightSim.AB_FIRED] < 1 and s[b + FightSim.ALIVE] != 0 and ts < int(ab.get("lock", 0)):
		s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], SimAbilities._tdir(s, i), int(ab.get("track", 1)))
	var mv: Dictionary = ab.get("mv", {})
	# La arremetida vive en el golpe que todavía no salió: al conectar, AB_FIRED avanza y el
	# tick siguiente ya no empuja, aunque la ventana del catálogo llegue un tick más.
	if s[o + FightSim.AB_FIRED] < 1 and int(mv.get("on", 0)) != 0 and int(mv.get("spd", 0)) > 0 and ts >= int(mv["from"]) and ts < int(mv["to"]):
		var gap := 99000000
		if s[b + FightSim.ALIVE] != 0:
			gap = FightSim._dist_to_opp(s, i)
		if gap > int(mv.get("stop", 0)):
			var f: int = s[o + FightSim.FACE]
			var spd := int(mv["spd"])
			s[o + FightSim.AB_VX] = FxMath.COS[f] * spd / FxMath.ONE
			s[o + FightSim.AB_VZ] = FxMath.SIN[f] * spd / FxMath.ONE
	if s[o + FightSim.AB_FIRED] < 1 and ts >= int(ab.get("hit_at", 0)):
		var landed := _strike(s, P, i, ab)
		if s[o + FightSim.AB_SLOT] < 0:
			return
		if int(ab.get("slam", 0)) != 0 and (int(ab.get("slam_on", 0)) == 0 or landed):
			var f2: int = s[o + FightSim.FACE]
			var fwd := int(ab.get("slam_fwd", 0))
			SimAbilities.spawn_hz(s, i, 1, s[o + FightSim.X] + FxMath.COS[f2] * fwd / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[f2] * fwd / FxMath.ONE,
				int(ab["slam_warn"]), int(ab["slam_r"]), SimAbilities.raw_live(s, P, i, int(ab["raw"]) * int(ab["slam_k"]) / 1000),
				int(ab["slam_force"]), int(ab.get("slam_knock", 150000)), 0)
		s[o + FightSim.AB_FIRED] = 1
	if ts >= int(ab["end"]) - 1:
		SimAbilities.end_ability(s, o, false)

static func _strike(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> bool:
	var o := i * FightSim.F_FIELDS
	if not SimAbilities._in_reach(s, P, i, int(ab["reach"]), int(ab["cos"])):
		return false
	var raw := SimAbilities.raw_live(s, P, i, int(ab["raw"]))
	var heavy: int = SimParams.A_HEAVY if raw >= 14000 else 0
	var res := FightSim._take_hit(s, P, i, int(ab["kind"]), raw, 0, int(ab["force"]), int(ab.get("pd", 2000)), 1000, P[i]["atk"][heavy]["block_cost"])
	if res == 1 or res == 2:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LANDED
		s[o + FightSim.AB_HITS] += 1
		return true
	return false

static func _wave(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, ts: int) -> void:
	var o := i * FightSim.F_FIELDS
	if ts < int(ab.get("lock", 0)):
		s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], SimAbilities._tdir(s, i), int(ab.get("turn", 1)))
	if s[o + FightSim.AB_FIRED] == 0 and ts >= int(ab.get("spawn_at", 0)):
		var raw := SimAbilities.raw_live(s, P, i, int(ab["raw"]))
		for off: int in ab["offs"]:
			var dir: int = (s[o + FightSim.FACE] + off) & 255
			var fwd := int(ab.get("fwd", 1000000))
			SimAbilities.spawn_hz(s, i, 2, s[o + FightSim.X] + FxMath.COS[dir] * fwd / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[dir] * fwd / FxMath.ONE,
				int(ab["warn"]), 0, raw, int(ab["force"]), 100000, 0, dir, int(ab["spd"]), int(ab["range"]), int(ab["width"]))
		s[o + FightSim.AB_FIRED] = (ab["offs"] as Array).size()
	if ts >= int(ab["end"]) - 1:
		SimAbilities.end_ability(s, o, false)

static func _rain(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, ts: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var ft: Array = ab["fire"]
	while s[o + FightSim.AB_FIRED] < ft.size() and ts >= int(ft[s[o + FightSim.AB_FIRED]]):
		var f: int = s[o + FightSim.FACE]
		var px: int = s[o + FightSim.X] + FxMath.COS[f] * 5000000 / FxMath.ONE
		var pz: int = s[o + FightSim.Z] + FxMath.SIN[f] * 5000000 / FxMath.ONE
		if int(ab.get("scatter", 0)) == 0:
			if s[b + FightSim.ALIVE] != 0:
				px = s[b + FightSim.X]
				pz = s[b + FightSim.Z]
		else:
			var ang: int = FightSim.rng_next(s) & 255
			var u: int = FightSim.rng_next(s) % 1000000
			var rad: int = FxMath.isqrt(u * 1000000) * int(ab["scatter_r"]) / 1000000
			var cx: int = s[b + FightSim.X] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.X]
			var cz: int = s[b + FightSim.Z] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.Z]
			px = cx + FxMath.COS[ang] * rad / FxMath.ONE
			pz = cz + FxMath.SIN[ang] * rad / FxMath.ONE
		SimAbilities.spawn_hz(s, i, 1, px, pz, int(ab["warn"]), int(ab["r"]), SimAbilities.raw_live(s, P, i, int(ab["raw"])), int(ab["force"]), int(ab["knock"]), int(ab["unbl"]))
		s[o + FightSim.AB_FIRED] += 1
	if ts >= int(ab["end"]) - 1:
		SimAbilities.end_ability(s, o, false)

# ---------------- grafo (branch / cancel / next), no usado por las cuatro migradas ----------------

static func _gstep(ab: Dictionary, si: int) -> Dictionary:
	var steps: Array = ab.get("steps", [])
	if si < 0 or si >= steps.size():
		return {}
	return steps[si]

static func _graph(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var si := s[o + FightSim.AB_FIRED]
	var step := _gstep(ab, si)
	if step.is_empty():
		SimAbilities.end_ability(s, o, false)
		return
	var ts := s[o + FightSim.AB_T] - 1
	_choose(s, o, step)
	if _commit(s, o, ab, step, ts, true):
		return
	if int(step.get("reach", 0)) > 0 and ts == int(step.get("windup", 0)) and s[o + FightSim.AB_TICK] == 0:
		s[o + FightSim.AB_TICK] = 1
		_ghit(s, P, i, step)
		if s[o + FightSim.AB_SLOT] < 0:
			return
	var cancel: Variant = step.get("cancel", null)
	if cancel is Dictionary and not _branch_open(step, ts):
		var cn: Dictionary = cancel
		if ts >= int(cn["from"]) and ts < int(cn["to"]) and _only(s, o, int(cn.get("only", 0))):
			var auto := int(cn.get("trigger", 0)) == 0
			var pressed := (s[o + FightSim.AB_FL] & SimAbilities.FL_QUEUED) != 0
			if auto or pressed:
				_goto(s, o, int(cn.get("step", -1)))
				return
	if _commit(s, o, ab, step, ts, false):
		return
	if ts >= int(step.get("total", 1)) - 1:
		var br: Variant = step.get("branch", null)
		if br is Dictionary:
			_goto(s, o, int((br as Dictionary).get("default", -1)))
		else:
			_goto(s, o, _next_of(step, s[o + FightSim.AB_WAIT]))

static func _only(s: PackedInt64Array, o: int, only: int) -> bool:
	if only == 0:
		return true
	var r := s[o + FightSim.AB_WAIT]
	if only == 1:
		return r == 1
	if only == 2:
		return r == 2
	return r == 0

static func _branch_open(step: Dictionary, ts: int) -> bool:
	var br: Variant = step.get("branch", null)
	if not (br is Dictionary):
		return false
	return ts >= int((br as Dictionary)["from"]) and ts < int((br as Dictionary)["to"])

static func _choose(s: PackedInt64Array, o: int, step: Dictionary) -> void:
	if (s[o + FightSim.AB_FL] & SimAbilities.FL_READY) != 0:
		return
	var br: Variant = step.get("branch", null)
	if not (br is Dictionary):
		return
	var skill := (s[o + FightSim.AB_FL] & SimAbilities.FL_QUEUED) != 0
	var alt := (s[o + FightSim.AB_FL] & SimAbilities.FL_VARIANT) != 0
	if not skill and not alt:
		return
	var pick := -1
	for op: Array in (br as Dictionary).get("opts", []):
		var inp := int(op[0])
		if inp == 0 and skill:
			pick = 0
			break
		if inp == 1 and alt:
			pick = 1
			break
	if pick < 0:
		return
	s[o + FightSim.AB_FL] |= SimAbilities.FL_READY
	if pick == 0:
		s[o + FightSim.AB_FL] &= ~SimAbilities.FL_VARIANT
	else:
		s[o + FightSim.AB_FL] &= ~SimAbilities.FL_QUEUED

static func _commit(s: PackedInt64Array, o: int, ab: Dictionary, step: Dictionary, ts: int, immediate_only: bool) -> bool:
	var br: Variant = step.get("branch", null)
	if not (br is Dictionary):
		return false
	if (s[o + FightSim.AB_FL] & SimAbilities.FL_READY) == 0:
		return false
	var b: Dictionary = br
	var now := int(b.get("commit", COMMIT_END)) == COMMIT_NOW
	if immediate_only != now:
		return false
	if not now and ts < int(b["to"]) - 1 and ts < int(step.get("total", 1)) - 1:
		return false
	var dest := int(b.get("default", -1))
	var alt := (s[o + FightSim.AB_FL] & SimAbilities.FL_VARIANT) != 0
	for op: Array in b.get("opts", []):
		if int(op[0]) == (1 if alt else 0):
			dest = int(op[1])
			break
	_goto(s, o, dest)
	return true

static func _next_of(step: Dictionary, result: int) -> int:
	var nx: Variant = step.get("next", null)
	if not (nx is Dictionary):
		return -1
	var n: Dictionary = nx
	if result == 1:
		return int(n.get("hit", n.get("default", -1)))
	if result == 2:
		return int(n.get("block", n.get("default", -1)))
	return int(n.get("whiff", n.get("default", -1)))

static func _ghit(s: PackedInt64Array, P: Array, i: int, step: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	if not SimAbilities._in_reach(s, P, i, int(step["reach"]), int(step.get("cos", 0))):
		return
	var raw := int(step.get("raw", 0))
	var res := FightSim._take_hit(s, P, i, int(step.get("kind", 3)), raw, 0, int(step.get("force", 0)), 2000, 1000, 0)
	if res == 1:
		s[o + FightSim.AB_WAIT] = 1
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LANDED
		s[o + FightSim.AB_HITS] += 1
	elif res == 2:
		s[o + FightSim.AB_WAIT] = 2
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LANDED

static func _goto(s: PackedInt64Array, o: int, step_i: int) -> void:
	if step_i < 0:
		SimAbilities.end_ability(s, o, false)
		return
	s[o + FightSim.AB_FIRED] = step_i
	s[o + FightSim.AB_T] = 0
	s[o + FightSim.AB_TICK] = 0
	s[o + FightSim.AB_VX] = 0
	s[o + FightSim.AB_VZ] = 0
	s[o + FightSim.AB_FL] = 0
	s[o + FightSim.AB_WAIT] = 0
