class_name SimAbilities
extends RefCounted
## Habilidades de jefe en la simulación determinista (BossAbilities + BossAbilitiesExt): estocada,
## carga en área, ráfaga teledirigida, escudo de maná (100 % invulnerable), combo de la pausa falsa,
## salto con caída y las ampliadas (timeline, ondas, lluvia, aliento, ráfaga, furia y contragolpe).
## Reglas: recarga global de 1,4 s tras cada habilidad (la ráfaga encadena consigo misma), coste en
## aguante/maná/vida (la vida nunca baja a 0), imbloqueables = tipo «jefe» (sin bloqueo ni parry).
## Todo en enteros: los tiempos se hornean a ticks con SimParams.tk() sobre la MISMA expresión en
## segundos que usa el offline (Fighter / FighterBossExt), con el factor de aviso online fijo.
## Las marcas de suelo y ondas viven en la piscina HZ_* del estado; la cinemática de agarre es solo
## presentación (GRAB_T / GRABS, la sim ya resolvió posición, daño y aturdimiento).

## Factor de aviso online (Fighter.telegraph_k): fijo para los dos pares (PC y móvil juegan igual).
const TELE_ONLINE := 1.12
const GLOBAL_CD := 85 # tk(Fighter.BOSS_GLOBAL_CD = 1,4 s)
const EldenCatalog = preload("res://scripts/data/elden_catalog.gd")
const ExtraCatalog = preload("res://scripts/data/extra_catalog.gd")
enum { T_ESTOCADA, T_CARGA, T_RAFAGA, T_ESCUDO, T_COMBO, T_SALTO, T_TIMELINE = 10, T_WAVE, T_RAIN, T_BREATH, T_RAGE, T_COUNTER, T_CATALOG = 16, T_STEPS = 17 }
## AB_FL: bits de la habilidad en curso
const FL_LANDED := 1
const FL_COUNTERED := 2
const FL_VANISHED := 4
const FL_STAGGERED := 8
const FL_QUEUED := 16
const FL_READY := 32
const FL_FINISHER := 64
const FL_VARIANT := 128 ## combo: remate en estocada (Fighter.ab_combo_variant)
const FL_LOCKED := 256
const FL_FLICK0 := 512
const FL_FLICK1 := 1024
const FL_CATALOG := 2048 ## habilidad del catálogo por pasos (SimCatalog)
const ELEM_FUEGO := 5

static func ids() -> Array:
	return BossAbilities.all_ids()

static func code_of(id: String) -> int:
	return ids().find(id)

# ---------------- Horneado (SimParams) ----------------
static func _tk(sec: float) -> int:
	return SimParams.tk(sec)

static func _turn(deg_s: float) -> int:
	return maxi(int(round(deg_s / 60.0 * 256.0 / 360.0)), 1)

static func _um(m: float) -> int:
	return SimParams.um(m)

## +40 % de alcance en tajos, persecuciones y ondas que viajan. No entra en básicos ni en artes.
const REACH_PM := 1400
## Ticks de rumbo quieto antes del activo. El piso de §11.2.
const DODGE_LOCK := 18

static func reach_up(v: int) -> int:
	if v <= 0:
		return 0
	return v * REACH_PM / 1000

## El catálogo persigue hasta cerca del golpe y deja al menos 18 ticks para rodar.
static func pursue_lock(authored: int, windup: int) -> int:
	var latest := windup - 18
	if latest < 0:
		latest = 0
	var lock := authored
	var pursue := windup - 24
	if pursue > lock:
		lock = pursue
	if lock > latest:
		lock = latest
	return lock

static func _ml(v: float) -> int:
	return SimParams.milli(v)

## Daño base y fuerzas (Fighter.ab_damage / ab_force) sin rabia ni furia (se aplican en vivo).
static func compile_all(f: Fighter) -> Array:
	var out: Array = []
	for id: String in f.boss_ids:
		var c := compile(f, id)
		if not c.is_empty():
			out.append(c)
	return out

static func compile(f: Fighter, id: String) -> Dictionary:
	if HojaCatalog.has(id) or EldenCatalog.has(id) or ExtraCatalog.has(id):
		return SimCatalog.compile(f, id)
	var d := BossAbilities.def(id)
	if d.is_empty():
		return {}
	var tk := TELE_ONLINE
	var w := f.melee()
	var dm := SimParams._dmg_mult(f)
	var magia := float(f.ad.get("magia", 100.0)) / 100.0
	var base := (w.light_damage if d.get("light", false) else w.heavy_damage) * dm * float(d.get("dmg", 0.0))
	if d.get("magic", false):
		base *= magia
	var st_k := float(f.tfx["stamina_cost"])
	var phys_f := StunRules.str_force(float(f.attributes().get("fuerza", 10))) + StunRules.weapon_force(w)
	var sd := float(f.ad.get("stun_dealt", 1.0))
	var mag_f := StunRules.magic_force(float(f.ad.get("magia", 100.0)))
	var fphys := func(a: float) -> int: return _ml((phys_f + a) * sd)
	var fmag := func(a: float) -> int: return _ml(mag_f + a)
	var cost := float(d.get("cost", 0.0))
	if id == "combo_falso":
		cost /= float(maxi((d.get("hits", []) as Array).size(), 1))
	var ct := ["stamina", "mana", "health"].find(String(d.get("cost_type", "stamina")))
	var c := {"code": code_of(id), "id": id, "cost_type": ct, "cost": _ml(cost * (st_k if ct == 0 else 1.0)),
		"unbl": 1 if BossAbilities.is_unblockable(id) else 0, "resist": _ml(float(d.get("resist", 0.0))),
		"raw": _ml(base), "cd": _tk(float(d.get("cd", d.get("cooldown", 1.4)))), "type": -1}
	match id:
		"estocada":
			c["type"] = T_ESTOCADA
			c["raw"] = _ml(w.heavy_damage * dm * Fighter.BOSS_DMG_MULT)
			c["charge"] = _tk(Fighter.BOSS_CHARGE)
			c["track"] = maxi(c["charge"] - DODGE_LOCK, 0)
			c["home_t"] = _tk(Fighter.BOSS_LUNGE_HOME_T)
			c["home"] = int(round(Fighter.BOSS_HOME_DEG / 60.0 * 256000.0 / 360.0))
			c["spd"] = _um(Fighter.BOSS_SPEED / 60.0)
			c["dist"] = reach_up(_um(Fighter.BOSS_DIST))
			c["reach"] = reach_up(_um(Fighter.BOSS_REACH))
			c["cos_arc"] = SimParams.cos_q(Fighter.BOSS_ARC_DEG)
			c["rec_hit"] = _tk(Fighter.BOSS_RECOVER_HIT)
			c["rec_miss"] = _tk(Fighter.BOSS_RECOVER_MISS)
		"carga_area":
			c["type"] = T_CARGA
			c["r"] = _um(float(d["radius"]))
			c["warn"] = _tk(float(d["windup"]))
			c["force"] = fmag.call(float(d["force"]))
			c["end"] = _tk(float(d["windup"]) + float(d["recovery"]))
		"rafaga":
			_compile_rafaga(c, d, fmag, 1.0)
		"escudo_mana":
			c["type"] = T_ESCUDO
			c["w"] = _tk(float(d["windup"]))
			c["end"] = _tk(float(d["windup"]) + float(d["active"]))
		"combo_falso":
			c["type"] = T_COMBO
			var hs: Array = []
			for h: Array in d["hits"]:
				hs.append([_ml(float(h[1])), fphys.call(float(h[2]))])
			c["hits"] = hs
			c["stage"] = _tk(float(d["stage_windup"]))
			c["final"] = _tk(float(d["final_stage_time"]))
			c["leap0"] = _tk(float(d["final_stage_time"]) - float(d["final_leap_time"]))
			c["leap_hgt"] = _um(float(d.get("final_leap_height", 3.2)))
			c["leap_rise"] = _tk(float(d.get("final_rise_time", 0.34)))
			c["leap_hold"] = _tk(float(d.get("final_apex_hold", 0.22)))
			c["leap_fall"] = _tk(float(d.get("final_fall_time", 0.34)))
			c["chain"] = _tk(float(d.get("chain_window", 1.15)))
			c["recovery"] = _tk(float(d["recovery"]))
			c["strike_r"] = reach_up(_um(float(d["strike_radius"])))
			c["turn"] = _turn(float(d["turn_deg"]))
			c["lunge_t"] = _tk(float(d["stage_windup"]) - float(d["lunge_time"]))
			c["lunge_spd"] = _um(float(d["lunge_speed"]) / 60.0)
			c["lunge_dist_v"] = _um(float(d["lunge_dist"]) / float(d["lunge_time"]) / 60.0)
			c["stop"] = _um(float(d["lunge_stop_dist"]))
			c["retreat"] = _um(float(d["final_retreat_speed"]) / 60.0)
			c["slam_r"] = _um(float(d["slam_radius"]))
			c["slam_warn"] = _tk(float(d.get("slam_warn", 0.25)))
			c["slam_k"] = _ml(float(d.get("slam_mult", 0.7)))
			c["slam_force"] = fphys.call(float(d.get("slam_force", 48.0)))
			# variante (botón «Estocada» antes del último golpe): estocada larga sin salto ni AoE
			var hl: Array = (d["hits"] as Array)[-1]
			c["var_w"] = _tk(float(d["variant_windup"]))
			c["var_lunge_t"] = _tk(float(d["variant_windup"]) - float(d["lunge_time"]))
			c["var_stop"] = _um(1.4)
			c["var_dist_v"] = _um(float(d["lunge_dist"]) * 1.45 / float(d["lunge_time"]) / 60.0)
			c["var_reach"] = reach_up(_um(float(d.get("variation_reach", 6.5))))
			c["var_cos"] = SimParams.cos_q(65.0)
			c["var_k"] = _ml(float(hl[1]) * 1.2)
			c["var_force"] = fphys.call(float(hl[2]) + 8.0)
			c["stagger"] = _tk(StunRules.STAGGER_T)
			c["resist_final"] = 1000
		"salto_caida":
			c["type"] = T_SALTO
			c["air0"] = _tk(0.05) + 1
			c["rise"] = _tk(float(d.get("rise", 0.55)))
			c["lock"] = _tk(float(d["lock"]))
			c["land"] = _tk(float(d["land"]))
			c["hgt"] = _um(float(d.get("height", 6.0)))
			c["lock_us"] = int(round(float(d["lock"]) * 1000000.0))
			c["span_us"] = int(round((float(d["land"]) - float(d["lock"])) * 1000000.0))
			c["warn"] = _tk(float(d["land"]) - float(d["lock"]))
			c["r"] = _um(float(d["radius"]))
			c["force"] = fphys.call(float(d["force"]))
			c["end"] = _tk(float(d["land"]) + float(d["recovery"]))
	if c["type"] >= 0:
		return _finish(c, id)
	match String(d.get("type", "")):
		"timeline":
			c["type"] = T_TIMELINE
			var hits: Array = d["hits"]
			var hs: Array = []
			for h: Array in hits:
				var th := float(h[0]) * tk
				var hit_tk := _tk(th)
				hs.append([hit_tk, _ml(float(h[1])), fphys.call(float(h[2])), _um((float(h[3]) if h.size() > 3 else 0.0) / 60.0),
					maxi(hit_tk - DODGE_LOCK, 0), _tk(th - 0.25), _tk(th + 0.04)])
			c["hits"] = hs
			var unbl := bool(d.get("unblockable", false))
			c["kind"] = 3 if unbl or String(d.get("kind", "melee")) == "jefe" else 0
			c["sub"] = SimParams.sub_code(w.phys_type)
			c["pd_pm"] = SimParams.pm(2.0 * w.poise_damage_mult * float(PhysTypes.POISE_MOD.get(w.phys_type, 1.0)) * float(f.ad["impacto"])) if c["kind"] == 0 else 2000
			c["counter_pm"] = SimParams.pm(float(PhysTypes.COUNTER_DMG.get(w.phys_type, 1.15)))
			c["reach"] = reach_up(_um(float(d.get("reach", 2.8))))
			c["gap"] = _um(float(d.get("reach", 2.6)) * 0.55)
			c["cos_arc"] = SimParams.cos_q(float(d.get("arc", 60.0)))
			c["track"] = _turn(float(d.get("track", 180.0)))
			c["end"] = _tk(float(hits[-1][0]) * tk + float(d.get("recovery", 0.9)))
			c["grab"] = 1 if d.get("grab", false) else 0
			c["grab_stun"] = _tk(float(d.get("grab_stun", 1.1)))
			c["grab_t"] = _tk(0.8)
			c["grab_d"] = _um(1.1)
			c["abort"] = 1 if d.get("abort_on_miss", false) else 0
			c["miss_t"] = c["end"] - _tk(float(d.get("miss_extra", 0.5)) + float(d.get("recovery", 0.9)))
			c["hit_if"] = 1 if d.get("hit_iframes", false) else 0
			c["parry_cancel"] = 1 if SimSteps.wants_parry(id) else 0
			c["vanish"] = _tk(float(d["vanish"]) * tk) if d.has("vanish") else -1
			c["reappear"] = _tk(float(hits[0][0]) * tk - 0.2)
			c["blink"] = _um(float(d.get("blink_dist", 2.4)))
			var fl: Array = d.get("flicker", [])
			c["flick0"] = _tk(float(fl[0]) * tk) if fl.size() > 1 else -1
			c["flick1"] = _tk(float(fl[1]) * tk) if fl.size() > 1 else -1
			c["slam_r"] = _um(float(d.get("slam_radius", 0.0)))
			c["slam_warn"] = _tk(float(d.get("slam_warn", 0.35)))
			c["slam_k"] = _ml(float(d.get("slam_mult", 0.65)))
			c["slam_force"] = fphys.call(float(d.get("slam_force", 40.0)))
			c["slam_last"] = 1 if d.get("slam_on_last", false) else 0
			c["slam_always"] = 1 if d.get("slam_always", false) else 0
			c["block_cost"] = 0
			if id == "alas_picado":
				c["leap_hgt"] = _um(3.5)
				c["leap_land"] = _tk(float(hits[0][0]) * tk)
		"wave":
			c["type"] = T_WAVE
			c["w"] = _tk(float(d["windup"]) * tk)
			c["turn"] = _turn(240.0)
			var cnt := int(d.get("count", 3))
			var spread := float(d.get("spread_deg", 18.0))
			var offs: Array = []
			for i in cnt:
				var ang: float = (i * spread) if d.get("ring", false) else (i - (cnt - 1) * 0.5) * spread
				offs.append(-int(round(ang * 256.0 / 360.0))) # rotated(UP, +a) = rumbo − a
			c["offs"] = offs
			c["spd"] = _um(float(d["speed"]) / 60.0)
			c["range"] = reach_up(_um(float(d["range"])))
			c["width"] = reach_up(_um(float(d["width"])))
			c["warn"] = _tk(float(d["warn"]) * tk)
			c["force"] = fphys.call(float(d.get("force", 30.0)))
			c["end"] = _tk(float(d["windup"]) * tk + float(d.get("recovery", 0.8)))
		"rain":
			c["type"] = T_RAIN
			var cnt := int(d["count"])
			var iv := float(d["interval"])
			var ft: Array = []
			for i in cnt:
				ft.append(_tk(float(d["windup"]) * tk + i * iv))
			c["fire"] = ft
			c["scatter"] = 1 if String(d.get("mode", "track")) != "track" else 0
			c["scatter_r"] = _um(float(d.get("scatter_r", 7.5)))
			c["r"] = _um(float(d["radius"]))
			c["warn"] = _tk(float(d["tele"]) * tk)
			c["force"] = fmag.call(float(d.get("force", 25.0)))
			c["knock"] = _um(float(d.get("knock", 6.0)) / 60.0)
			c["end"] = _tk(float(d["windup"]) * tk + (cnt - 1) * iv + float(d.get("recovery", 0.6)))
		"breath":
			c["type"] = T_BREATH
			c["w"] = _tk(float(d["windup"]) * tk)
			c["w_end"] = _tk(float(d["windup"]) * tk + float(d["duration"]))
			var t := float(d.get("tick", 0.3))
			var n := 0
			while t > 0.0 and n < 1000:
				t -= 1.0 / 60.0
				n += 1
			c["tick"] = n
			c["range"] = reach_up(_um(float(d.get("range", 7.5))))
			c["cos_arc"] = SimParams.cos_q(float(d.get("arc", 28.0)))
			c["turn"] = _turn(float(d.get("turn_deg", 70.0)))
			c["elem"] = SimParams.SUBS.size() + SimParams.ELEMS.find(String(d.get("element", "fuego")))
			c["force"] = fmag.call(float(d.get("force", 8.0)))
			c["end"] = _tk(float(d["windup"]) * tk + float(d["duration"]) + float(d.get("recovery", 1.1)))
		"rage":
			c["type"] = T_RAGE
			c["w"] = _tk(float(d["windup"]) * tk)
			c["dur"] = _tk(float(d.get("duration", 9.0)))
			c["end"] = _tk(float(d["windup"]) * tk + float(d.get("recovery", 0.3)))
		"counter":
			c["type"] = T_COUNTER
			c["w"] = _tk(float(d["windup"]) * tk)
			c["ws"] = _tk(float(d["windup"]) * tk + float(d["stance"]) * tk)
			c["rec_hit"] = _tk(float(d["recovery_hit"]))
			c["end_miss"] = _tk(float(d["windup"]) * tk + float(d["stance"]) * tk + float(d["recovery_miss"]))
			c["reach"] = reach_up(_um(float(d.get("reach", 4.0))))
			c["c_raw"] = _ml(w.heavy_damage * dm * float(d.get("cmult", 1.6)))
			c["c_force"] = fphys.call(float(d.get("cforce", 55.0)))
		"rafaga":
			_compile_rafaga(c, d, fmag, tk)
	return _finish(c, id)

static func _finish(c: Dictionary, id: String) -> Dictionary:
	if c.is_empty() or not SimSteps.handles(id):
		return c
	return SimSteps.wrap(c, id)

## Tajo que persigue. scale 1 = ráfaga base (tiempos de escritorio); el resto alarga el aviso.
static func _compile_rafaga(c: Dictionary, d: Dictionary, fmag: Callable, scale: float) -> void:
	c["type"] = T_RAFAGA
	c["w"] = _tk(float(d["windup"]) * scale)
	c["turn"] = _turn(360.0)
	c["count"] = int(d["count"])
	c["spd"] = _um(float(d["speed"]) / 60.0)
	c["life"] = reach_up(_tk(float(d["life"])))
	c["radius"] = _um(float(d.get("radius", 0.7)))
	c["force"] = fmag.call(float(d["force"]))
	c["home_t"] = _tk(float(d["home_time"]) * scale)
	c["home"] = int(round(float(d["home_deg"]) / 60.0 * 256000.0 / 360.0))
	c["pitch"] = int(round(float(d.get("home_pitch_deg", 24.0)) / 60.0 * 256000.0 / 360.0))
	c["end"] = _tk((float(d["windup"]) + float(d["recovery"])) * scale)

# ---------------- Utilidades ----------------
static func _ab(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	if i >= P.size():
		return {}
	var boss: Array = P[i].get("boss", [])
	var slot: int = s[i * FightSim.F_FIELDS + FightSim.AB_SLOT]
	if slot < 0 or slot >= boss.size():
		return {}
	return boss[slot]

## Tipo de ejecutor. El motor de pasos guarda el original en `family` y pone `type` = T_STEPS.
static func kind_of(ab: Dictionary) -> int:
	return int(ab.get("family", ab.get("type", -1)))

static func is_shield(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	return s[o + FightSim.AB_SLOT] >= 0 and kind_of(_ab(s, P, i)) == T_ESCUDO

## Daño en vivo: furia con vida baja y furia de fase (+30 %).
static func raw_live(s: PackedInt64Array, P: Array, i: int, raw: int) -> int:
	var o := i * FightSim.F_FIELDS
	if P[i].get("furia_pm", 0) > 0 and s[o + FightSim.HP] * 1000 < P[i]["hp"] * FightSim.FURIA_HP_PM:
		raw = raw * (1000 + P[i]["furia_pm"]) / 1000
	if s[o + FightSim.RAGE_T] > 0:
		raw = raw * 1300 / 1000
	return raw

static func _tdir(s: PackedInt64Array, i: int) -> int:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	if s[b + FightSim.ALIVE] != 0 and FightSim._dist_to_opp(s, i) > 100000:
		return FightSim._dir_to_opp(s, i)
	return s[o + FightSim.FACE]

## ¿El rival está a tiro? dist <= alcance + radio y dentro del arco (cos_arc ×4096).
static func _in_reach(s: PackedInt64Array, P: Array, i: int, reach: int, cos_arc: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	if s[b + FightSim.ALIVE] == 0:
		return false
	var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
	var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
	var l := FxMath.length(dx, dz)
	if l > reach + P[1 - i]["hit_radius"]:
		return false
	if l > 200000:
		var f: int = s[o + FightSim.FACE]
		return dx * FxMath.COS[f] + dz * FxMath.SIN[f] >= cos_arc * l
	return true

static func clamp_world(s: PackedInt64Array, P: Array, o: int) -> void:
	var r := FxMath.length(s[o + FightSim.X], s[o + FightSim.Z])
	var lim := FightSim.ARENA_R - 450000
	if r > lim:
		s[o + FightSim.X] = s[o + FightSim.X] * lim / r
		s[o + FightSim.Z] = s[o + FightSim.Z] * lim / r
	if P[0].get("pillars", 0) != 0:
		for k in 6:
			var dx: int = s[o + FightSim.X] - FightSim.PILLARS[k * 2]
			var dz: int = s[o + FightSim.Z] - FightSim.PILLARS[k * 2 + 1]
			var dl := FxMath.length(dx, dz)
			if dl < FightSim.PILLAR_BODY_R:
				if dl < 1000:
					dx = FxMath.COS[s[o + FightSim.FACE]]; dz = FxMath.SIN[s[o + FightSim.FACE]]; dl = FxMath.ONE
				s[o + FightSim.X] = FightSim.PILLARS[k * 2] + dx * FightSim.PILLAR_BODY_R / dl
				s[o + FightSim.Z] = FightSim.PILLARS[k * 2 + 1] + dz * FightSim.PILLAR_BODY_R / dl

## Marca de suelo (GroundAoE) o onda (GroundWave) en la piscina. Devuelve el índice o -1 (llena).
static func spawn_hz(s: PackedInt64Array, owner: int, typ: int, x: int, z: int, warn: int, r: int, raw: int, force: int, knock: int, unbl: int, dir: int = 0, spd: int = 0, rng: int = 0, width: int = 0) -> int:
	for j in FightSim.HZ_MAX:
		var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
		if s[q + FightSim.HZ_ON] != 0:
			continue
		for k in FightSim.HZ_FIELDS:
			s[q + k] = 0
		s[q + FightSim.HZ_ON] = 1
		s[q + FightSim.HZ_TYPE] = typ
		s[q + FightSim.HZ_OWNER] = owner
		s[q + FightSim.HZ_X] = x
		s[q + FightSim.HZ_Z] = z
		s[q + FightSim.HZ_WARN] = warn
		s[q + FightSim.HZ_R] = r
		s[q + FightSim.HZ_RAW] = raw
		s[q + FightSim.HZ_FORCE] = force
		s[q + FightSim.HZ_KNOCK] = knock
		s[q + FightSim.HZ_UNBL] = unbl
		s[q + FightSim.HZ_DX] = FxMath.COS[dir & 255]
		s[q + FightSim.HZ_DZ] = FxMath.SIN[dir & 255]
		s[q + FightSim.HZ_SPD] = spd
		s[q + FightSim.HZ_RANGE] = rng
		s[q + FightSim.HZ_W] = width
		return j
	return -1

static func _grounded(s: PackedInt64Array, b: int) -> bool:
	return s[b + FightSim.AB_AIR] == 0 and s[b + FightSim.AIR] == 0 and s[b + FightSim.FY] < FightSim.GROUND_H

## Avance de marcas y ondas (después de los luchadores y proyectiles, como nodos añadidos después).
static func hazards(s: PackedInt64Array, P: Array) -> void:
	for j in FightSim.HZ_MAX:
		var q := FightSim.HZ_BASE + j * FightSim.HZ_FIELDS
		if s[q + FightSim.HZ_ON] == 0:
			continue
		s[q + FightSim.HZ_T] += 1
		var owner: int = s[q + FightSim.HZ_OWNER]
		var b := FightSim._opp(owner)
		if s[q + FightSim.HZ_TYPE] == 1:
			if s[q + FightSim.HZ_DONE] != 0:
				if s[q + FightSim.HZ_T] >= s[q + FightSim.HZ_WARN] + 24:
					s[q + FightSim.HZ_ON] = 0
				continue
			if s[q + FightSim.HZ_T] < s[q + FightSim.HZ_WARN]:
				continue
			s[q + FightSim.HZ_DONE] = 1
			SimMagic.pet_aoe(s, P, owner, s[q + FightSim.HZ_X], s[q + FightSim.HZ_Z], s[q + FightSim.HZ_R], s[q + FightSim.HZ_RAW])
			if s[b + FightSim.ALIVE] == 0:
				continue
			var dx: int = s[b + FightSim.X] - s[q + FightSim.HZ_X]
			var dz: int = s[b + FightSim.Z] - s[q + FightSim.HZ_Z]
			var l := FxMath.length(dx, dz)
			if l > s[q + FightSim.HZ_R] or not _grounded(s, b):
				continue
			var res := FightSim._take_hit(s, P, owner, 5, s[q + FightSim.HZ_RAW], 0, s[q + FightSim.HZ_FORCE], 2000, 1000, 0, -1, [], s[q + FightSim.HZ_UNBL] != 0)
			if res == 1:
				if s[q + FightSim.HZ_KIND] != 0:
					SimCatalog.on_zone_hit(s, P, owner)
				var kv: int = s[q + FightSim.HZ_KNOCK]
				if l > 100000:
					s[b + FightSim.KX] = dx * kv / l
					s[b + FightSim.KZ] = dz * kv / l
				else:
					s[b + FightSim.KX] = FxMath.COS[s[b + FightSim.FACE]] * kv / FxMath.ONE
					s[b + FightSim.KZ] = FxMath.SIN[s[b + FightSim.FACE]] * kv / FxMath.ONE
				s[owner * FightSim.F_FIELDS + FightSim.AB_HITS] += 1
		elif s[q + FightSim.HZ_SPD] == 0:
			if s[q + FightSim.HZ_DONE] != 0:
				if s[q + FightSim.HZ_T] >= s[q + FightSim.HZ_WARN] + 24:
					s[q + FightSim.HZ_ON] = 0
				continue
			if s[q + FightSim.HZ_T] < s[q + FightSim.HZ_WARN]:
				continue
			s[q + FightSim.HZ_DONE] = 1
			if s[b + FightSim.ALIVE] == 0 or not _grounded(s, b):
				continue
			var lx: int = s[b + FightSim.X] - s[q + FightSim.HZ_X]
			var lz: int = s[b + FightSim.Z] - s[q + FightSim.HZ_Z]
			var hr0: int = P[1 - owner]["hit_radius"]
			var along0: int = (lx * s[q + FightSim.HZ_DX] + lz * s[q + FightSim.HZ_DZ]) / FxMath.ONE
			var side0: int = absi(lx * s[q + FightSim.HZ_DZ] - lz * s[q + FightSim.HZ_DX]) / FxMath.ONE
			if along0 < -hr0 or along0 > s[q + FightSim.HZ_RANGE] + hr0 or side0 > s[q + FightSim.HZ_W] / 2 + hr0:
				continue
			var res3 := FightSim._take_hit(s, P, owner, 5, s[q + FightSim.HZ_RAW], 0, s[q + FightSim.HZ_FORCE], 2000, 1000, 0)
			if res3 == 1:
				s[b + FightSim.KX] = s[q + FightSim.HZ_DX] * s[q + FightSim.HZ_KNOCK] / FxMath.ONE
				s[b + FightSim.KZ] = s[q + FightSim.HZ_DZ] * s[q + FightSim.HZ_KNOCK] / FxMath.ONE
				s[owner * FightSim.F_FIELDS + FightSim.AB_HITS] += 1
		else:
			if s[q + FightSim.HZ_T] < s[q + FightSim.HZ_WARN]:
				continue
			var stp: int = s[q + FightSim.HZ_SPD]
			s[q + FightSim.HZ_X] += s[q + FightSim.HZ_DX] * stp / FxMath.ONE
			s[q + FightSim.HZ_Z] += s[q + FightSim.HZ_DZ] * stp / FxMath.ONE
			s[q + FightSim.HZ_TRAV] += stp
			if s[q + FightSim.HZ_TRAV] >= s[q + FightSim.HZ_RANGE] or FxMath.length(s[q + FightSim.HZ_X], s[q + FightSim.HZ_Z]) > FightSim.ARENA_R + 2000000:
				s[q + FightSim.HZ_ON] = 0
				continue
			if P[0].get("pillars", 0) != 0 and FightSim._in_pillar(s[q + FightSim.HZ_X], s[q + FightSim.HZ_Z], FightSim.PILLAR_ARROW_R):
				s[q + FightSim.HZ_ON] = 0
				continue
			if s[q + FightSim.HZ_DONE] != 0 or s[b + FightSim.ALIVE] == 0:
				continue
			var rx: int = s[b + FightSim.X] - s[q + FightSim.HZ_X]
			var rz: int = s[b + FightSim.Z] - s[q + FightSim.HZ_Z]
			var hr: int = P[1 - owner]["hit_radius"]
			var along: int = absi(rx * s[q + FightSim.HZ_DX] + rz * s[q + FightSim.HZ_DZ]) / FxMath.ONE
			var side: int = absi(rx * s[q + FightSim.HZ_DZ] - rz * s[q + FightSim.HZ_DX]) / FxMath.ONE
			if along > 600000 + hr / 2 + stp or side > s[q + FightSim.HZ_W] / 2 + hr / 2:
				continue
			s[q + FightSim.HZ_DONE] = 1
			if not _grounded(s, b):
				continue
			var res2 := FightSim._take_hit(s, P, owner, 5, s[q + FightSim.HZ_RAW], 0, s[q + FightSim.HZ_FORCE], 2000, 1000, 0)
			if res2 == 1:
				s[b + FightSim.KX] = s[q + FightSim.HZ_DX] * s[q + FightSim.HZ_KNOCK] / FxMath.ONE
				s[b + FightSim.KZ] = s[q + FightSim.HZ_DZ] * s[q + FightSim.HZ_KNOCK] / FxMath.ONE
				s[owner * FightSim.F_FIELDS + FightSim.AB_HITS] += 1

# ---------------- Entrada ----------------
## Habilidades disponibles: el campeón guarda la tercera hasta su Fase II (P["boss_n"]).
static func boss_avail(s: PackedInt64Array, P: Array, i: int) -> int:
	var n: int = (P[i].get("boss", []) as Array).size()
	if s[i * FightSim.F_FIELDS + FightSim.PH2] == 0:
		n = mini(n, int(P[i].get("boss_n", n)))
	return n

static func cycle(s: PackedInt64Array, P: Array, i: int) -> void:
	var n: int = boss_avail(s, P, i)
	if n > 1:
		s[i * FightSim.F_FIELDS + FightSim.AB_SEL] = (s[i * FightSim.F_FIELDS + FightSim.AB_SEL] + 1) % n

static func _cost_ok(s: PackedInt64Array, i: int, ab: Dictionary) -> bool:
	var o := i * FightSim.F_FIELDS
	var c: int = ab["cost"]
	match int(ab["cost_type"]):
		0: return s[o + FightSim.ST] >= c and s[o + FightSim.EXH] <= 0
		1: return s[o + FightSim.MANA] >= c
		2: return s[o + FightSim.HP] - c > 0
	return false

static func _pay(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var c: int = ab["cost"]
	match int(ab["cost_type"]):
		0: FightSim._spend(s, P, i, c)
		1: s[o + FightSim.MANA] -= c
		2: s[o + FightSim.HP] = maxi(s[o + FightSim.HP] - c, 1000)

static func can_use(s: PackedInt64Array, P: Array, i: int, slot: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var boss: Array = P[i].get("boss", [])
	if slot < 0 or slot >= boss_avail(s, P, i):
		return false
	if s[o + FightSim.AIR] != 0 or s[o + FightSim.FLASK_T] > 0:
		return false
	var ab: Dictionary = boss[slot]
	if s[o + FightSim.MOUNTED] != 0 or s[o + FightSim.ALIVE] == 0 or s[o + FightSim.STUN] > 0 or s[o + FightSim.EXH] > 0 or s[o + FightSim.CAST_T] > 0 or s[o + FightSim.CRIT_T] >= 0:
		return false
	if s[o + FightSim.BS_PH] != 0 or s[o + FightSim.AB_SLOT] >= 0 or s[o + FightSim.BACKSTEP_T] > 0:
		return false
	if s[o + FightSim.ATK_STATE] != FightSim.Atk.NONE or s[o + FightSim.PARRY_STATE] != FightSim.Parry.NONE or s[o + FightSim.ROLL_T] >= 0 or s[o + FightSim.SWAP_T] > 0:
		return false
	if s[o + FightSim.SHOT_STATE] == FightSim.Shot.DRAW or s[o + FightSim.SHOT_STATE] == FightSim.Shot.RECOVER:
		return false
	if kind_of(ab) != T_ESCUDO and s[o + FightSim.LOADOUT] != FightSim.Load.SWORD:
		return false
	if int(ab.get("phase", 1)) >= 2:
		var ph: Dictionary = P[i].get("ph2", {})
		if not ph.is_empty() and s[o + FightSim.PH2] == 0:
			return false
	if not AdminMode.enabled and slot < 64 and s[o + FightSim.BCD_BASE + slot] > 0 and not (kind_of(ab) == T_RAFAGA and s[o + FightSim.AB_LAST] == int(ab["code"])):
		return false
	return _cost_ok(s, i, ab)

static func press(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var boss: Array = P[i].get("boss", [])
	if boss.is_empty():
		return false
	if s[o + FightSim.AB_SLOT] >= 0 and s[o + FightSim.AB_SLOT] < boss.size():
		var cur: Dictionary = boss[s[o + FightSim.AB_SLOT]]
		if int(cur.get("type", -1)) == T_CATALOG:
			return SimCatalog.latch(s, P, i, false)
		if int(cur.get("type", -1)) == T_STEPS and SimSteps.latch(s, P, i, false):
			return true
	var slot: int = clampi(s[o + FightSim.AB_SEL], 0, maxi(boss_avail(s, P, i) - 1, 0))
	var ab: Dictionary = boss[slot]
	if kind_of(ab) == T_COMBO and s[o + FightSim.AB_SLOT] == slot:
		if s[o + FightSim.AB_FIRED] >= (ab["hits"] as Array).size():
			return false
		if not _cost_ok(s, i, ab):
			_end_combo(s, P, i, true)
			return true
		_pay(s, P, i, ab)
		s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~FL_VARIANT) | FL_QUEUED
		return true
	if not can_use(s, P, i, slot):
		return false
	_pay(s, P, i, ab)
	s[o + FightSim.AB_LAST] = ab["code"]
	s[o + FightSim.AB_STARTS] += 1
	_start(s, P, i, slot)
	return true

## Fighter.boss_variation: activa la rama alternativa/variación apenas se pulse.
static func variation(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.AB_SLOT] < 0:
		return false
	if not alt_window(s, P, i):
		return false
	var ab := _ab(s, P, i)
	if int(ab.get("type", -1)) == T_CATALOG:
		return SimCatalog.latch(s, P, i, true)
	if int(ab.get("type", -1)) == T_STEPS and SimSteps.latch(s, P, i, true):
		return true
	if kind_of(ab) == T_COMBO:
		if not _cost_ok(s, i, ab):
			_end_combo(s, P, i, true)
			return true
		_pay(s, P, i, ab)
		s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~FL_QUEUED) | FL_VARIANT
		return true
	return false

## La ventana del remate alternativo (bit 21). La vista solo lee esto.
static func alt_window(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.AB_SLOT] < 0:
		return false
	var ab := _ab(s, P, i)
	if int(ab.get("type", -1)) == T_CATALOG:
		return SimCatalog.alt_window(s, P, i)
	if int(ab.get("type", -1)) == T_STEPS and int(ab.get("graph", 0)) != 0:
		return SimSteps.alt_window(s, P, i)
	if kind_of(ab) == T_COMBO:
		var hits: Array = ab.get("hits", [])
		if hits.is_empty():
			return false
		var fl: int = s[o + FightSim.AB_FL]
		if (fl & FL_FINISHER) != 0:
			return false
		var fired: int = s[o + FightSim.AB_FIRED]
		return fired == hits.size() - 1
	return false

static func alt_label(s: PackedInt64Array, P: Array, i: int) -> String:
	if not alt_window(s, P, i):
		return ""
	var ab := _ab(s, P, i)
	if int(ab.get("type", -1)) == T_CATALOG:
		return SimCatalog.alt_label(s, P, i)
	if kind_of(ab) == T_COMBO:
		return "Estocada"
	return ""

static func combo_info(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.AB_SLOT] < 0:
		return {"can_combo": false, "active": false, "progress": 0.0, "queued": false, "label": ""}
	var ab := _ab(s, P, i)
	if int(ab.get("type", -1)) == T_CATALOG:
		return SimCatalog.combo_info(s, P, i)
	if int(ab.get("type", -1)) == T_STEPS and int(ab.get("graph", 0)) != 0:
		return SimSteps.combo_info(s, P, i)
	if kind_of(ab) == T_COMBO:
		var hits: Array = ab.get("hits", [])
		var fired: int = s[o + FightSim.AB_FIRED]
		var can := fired < hits.size() - 1 or fired == hits.size() - 1
		var fl: int = s[o + FightSim.AB_FL]
		var queued := (fl & (FL_QUEUED | FL_VARIANT)) != 0
		var active := true
		var step_count: int = fired + (1 if queued else 0)
		var prog := 1.0 - float(step_count) / maxf(float(hits.size()), 1.0)
		if prog <= 0.05:
			prog = 1.0 / maxf(float(hits.size()), 1.0)
		return {"can_combo": can, "active": active, "progress": prog, "queued": queued, "label": "Estocada" if fired == hits.size() - 1 else ""}
	return {"can_combo": false, "active": false, "progress": 0.0, "queued": false, "label": ""}


static func _start(s: PackedInt64Array, P: Array, i: int, slot: int) -> void:
	var o := i * FightSim.F_FIELDS
	var ab: Dictionary = P[i]["boss"][slot]
	s[o + FightSim.BLOCKING] = 0
	var dir := _tdir(s, i)
	s[o + FightSim.FACE] = dir
	var own_cd: int = 0 if AdminMode.enabled else int(ab.get("cd", GLOBAL_CD))
	if slot < 64:
		s[o + FightSim.BCD_BASE + slot] = own_cd
	s[o + FightSim.BOSS_CD] = own_cd
	if kind_of(ab) == T_ESTOCADA:
		s[o + FightSim.AB_SLOT] = slot
		s[o + FightSim.BS_PH] = 1
		s[o + FightSim.BS_T] = 0
		s[o + FightSim.BS_TRAV] = 0
		s[o + FightSim.BS_HIT] = 0
		s[o + FightSim.BS_DIR] = dir * 1000
		return
	s[o + FightSim.AB_SLOT] = slot
	s[o + FightSim.AB_T] = 0
	s[o + FightSim.AB_FIRED] = 0
	s[o + FightSim.AB_FL] = 0
	s[o + FightSim.AB_VX] = 0
	s[o + FightSim.AB_VZ] = 0
	s[o + FightSim.AB_AIR] = 0
	s[o + FightSim.AB_IMM] = 0
	s[o + FightSim.AB_TICK] = 0
	s[o + FightSim.AB_WAIT] = own_cd
	s[o + FightSim.AB_HZ] = -1
	s[o + FightSim.AB_FX] = s[o + FightSim.X]
	s[o + FightSim.AB_FZ] = s[o + FightSim.Z]
	var b := FightSim._opp(i)
	s[o + FightSim.AB_X] = s[b + FightSim.X] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.X] + FxMath.COS[dir] * 6000000 / FxMath.ONE
	s[o + FightSim.AB_Z] = s[b + FightSim.Z] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.Z] + FxMath.SIN[dir] * 6000000 / FxMath.ONE
	if int(ab["type"]) == T_CATALOG:
		s[o + FightSim.AB_FL] = FL_CATALOG
		s[o + FightSim.AB_FIRED] = int(ab.get("entry", 0))
		s[o + FightSim.AB_WAIT] = own_cd | (int(ab.get("imask", 0)) << 16)
	elif kind_of(ab) == T_CARGA:
		s[o + FightSim.AB_HZ] = spawn_hz(s, i, 1, s[o + FightSim.X], s[o + FightSim.Z], ab["warn"], ab["r"], raw_live(s, P, i, ab["raw"]), ab["force"], 150000, 0)

## Fin de la habilidad (Fighter._end_ability): recarga individual por ranura.
static func end_ability(s: PackedInt64Array, o: int, interrupted: bool) -> void:
	if s[o + FightSim.AB_SLOT] < 0:
		return
	var fl: int = s[o + FightSim.AB_FL]
	if (fl & FL_CATALOG) != 0 and interrupted:
		SimCatalog.cancel_zones(s, o / FightSim.F_FIELDS)
	if interrupted:
		s[o + FightSim.AB_INTR] += 1
		var hz: int = s[o + FightSim.AB_HZ]
		if hz >= 0:
			var q := FightSim.HZ_BASE + hz * FightSim.HZ_FIELDS
			if s[q + FightSim.HZ_ON] != 0 and s[q + FightSim.HZ_DONE] == 0 and s[q + FightSim.HZ_TYPE] == 1:
				s[q + FightSim.HZ_ON] = 0
	s[o + FightSim.AB_SLOT] = -1
	s[o + FightSim.AB_T] = 0
	s[o + FightSim.AB_VX] = 0
	s[o + FightSim.AB_VZ] = 0
	s[o + FightSim.AB_AIR] = 0
	s[o + FightSim.AB_IMM] = 0
	s[o + FightSim.AB_HZ] = -1
	s[o + FightSim.AB_FL] = 0
	if s[o + FightSim.FY] > 0:
		s[o + FightSim.FY] = 0
		s[o + FightSim.AIR] = 0
		s[o + FightSim.FVY] = 0
	s[o + FightSim.BOSS_CD] = FightSim.boss_cd_read(s, o, s[o + FightSim.AB_SEL])

static func _end_combo(s: PackedInt64Array, P: Array, i: int, penalize: bool) -> void:
	var o := i * FightSim.F_FIELDS
	var ab := _ab(s, P, i)
	var n: int = (ab.get("hits", []) as Array).size()
	end_ability(s, o, penalize and s[o + FightSim.AB_FIRED] < n)
	if penalize and s[o + FightSim.ALIVE] != 0:
		s[o + FightSim.EXH] = maxi(s[o + FightSim.EXH], P[i]["exhaust"])

## Súper-armadura de la habilidad en curso (Fighter.ab_resist).
static func resist_pm(s: PackedInt64Array, P: Array, i: int) -> int:
	var o := i * FightSim.F_FIELDS
	var ab := _ab(s, P, i)
	if int(ab.get("type", -1)) == T_CATALOG:
		return SimCatalog.resist_now(s, P, i)
	if int(ab.get("type", -1)) == T_STEPS:
		return SimSteps.resist_now(s, P, i)
	if kind_of(ab) == T_COMBO:
		var n: int = (ab["hits"] as Array).size()
		var fin: int = ab["var_w"] if (s[o + FightSim.AB_FL] & FL_VARIANT) != 0 else ab["final"]
		if s[o + FightSim.AB_FIRED] == n - 1 and s[o + FightSim.AB_T] < fin:
			return ab["resist_final"]
	return ab["resist"]

## Postura de contragolpe: si le golpean en la ventana, no recibe daño y castiga (tipo jefe).
static func counter_trigger(s: PackedInt64Array, P: Array, d: int, att: int) -> bool:
	var o := d * FightSim.F_FIELDS
	if s[o + FightSim.AB_SLOT] < 0:
		return false
	var ab := _ab(s, P, d)
	if kind_of(ab) != T_COUNTER or (s[o + FightSim.AB_FL] & FL_COUNTERED) != 0:
		return false
	if s[o + FightSim.AB_T] < int(ab["w"]) or s[o + FightSim.AB_T] > int(ab["ws"]):
		return false
	s[o + FightSim.AB_FL] |= FL_COUNTERED
	s[o + FightSim.AB_T] = ab["ws"]
	var a := att * FightSim.F_FIELDS
	var dx: int = s[a + FightSim.X] - s[o + FightSim.X]
	var dz: int = s[a + FightSim.Z] - s[o + FightSim.Z]
	var l := FxMath.length(dx, dz)
	if l > 100000:
		s[o + FightSim.FACE] = FxMath.dir_of(dx, dz, s[o + FightSim.FACE])
	if l <= int(ab["reach"]) + P[att]["hit_radius"]:
		var res := FightSim._take_hit(s, P, d, 3, raw_live(s, P, d, ab["c_raw"]), 4, ab["c_force"], 2000, 1000, 0)
		if res == 1:
			s[o + FightSim.AB_HITS] += 1
	return true

# ---------------- Actualización por tick ----------------
static func update(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	if AdminMode.enabled:
		s[o + FightSim.BOSS_CD] = 0
		for k in 64:
			s[o + FightSim.BCD_BASE + k] = 0
	else:
		for k in 64:
			if s[o + FightSim.BCD_BASE + k] > 0:
				s[o + FightSim.BCD_BASE + k] -= 1
		var sel := clampi(s[o + FightSim.AB_SEL], 0, 63)
		s[o + FightSim.BOSS_CD] = s[o + FightSim.BCD_BASE + sel]
	if s[o + FightSim.RAGE_T] > 0: s[o + FightSim.RAGE_T] -= 1
	if s[o + FightSim.GRAB_T] > 0: s[o + FightSim.GRAB_T] -= 1
	if s[o + FightSim.BS_PH] != 0:
		_estocada(s, P, i)
	if s[o + FightSim.AB_SLOT] < 0:
		return
	if s[o + FightSim.ALIVE] == 0:
		end_ability(s, o, true)
		return
	s[o + FightSim.AB_T] += 1
	s[o + FightSim.AB_VX] = 0
	s[o + FightSim.AB_VZ] = 0
	var ab := _ab(s, P, i)
	if ab.is_empty():
		end_ability(s, o, true)
		return
	match int(ab.get("type", -1)):
		T_CATALOG:
			SimCatalog.tick(s, P, i, ab)
		T_STEPS:
			SimSteps.tick(s, P, i, ab)
		_:
			end_ability(s, o, true)
	# inmunidad (Fighter.ab_immune): escudo tras su anticipación, o en el aire (salto / combo)
	if s[o + FightSim.AB_SLOT] >= 0:
		var cur_ab := _ab(s, P, i)
		var t := kind_of(cur_ab)
		s[o + FightSim.AB_IMM] = 1 if (t == T_ESCUDO and s[o + FightSim.AB_T] >= int(cur_ab.get("w", 0))) or ((t == T_SALTO or t == T_COMBO) and s[o + FightSim.AB_AIR] != 0) else 0

static func _estocada(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	var ab: Dictionary = {}
	for c: Dictionary in P[i].get("boss", []):
		if kind_of(c) == T_ESTOCADA:
			ab = c
	if ab.is_empty() or s[o + FightSim.ALIVE] == 0:
		_end_boss(s, o)
		return
	s[o + FightSim.BS_T] += 1
	if s[o + FightSim.BS_PH] == 1 or s[o + FightSim.BS_PH] == 2:
		s[o + FightSim.INVULN] = maxi(s[o + FightSim.INVULN], 3)
	match s[o + FightSim.BS_PH]:
		1:
			if s[o + FightSim.BS_T] <= int(ab["track"]):
				s[o + FightSim.BS_DIR] = _tdir(s, i) * 1000
				s[o + FightSim.FACE] = s[o + FightSim.BS_DIR] / 1000
			if s[o + FightSim.BS_T] >= int(ab["charge"]):
				s[o + FightSim.BS_PH] = 2
				s[o + FightSim.BS_T] = 0
		2:
			if s[o + FightSim.BS_T] <= int(ab["home_t"]):
				var cur: int = s[o + FightSim.BS_DIR]
				var want: int = _tdir(s, i) * 1000
				var dd: int = ((want - cur + 128000) % 256000 + 256000) % 256000 - 128000
				var hr: int = ab["home"]
				s[o + FightSim.BS_DIR] = ((cur + clampi(dd, -hr, hr)) % 256000 + 256000) % 256000
			var f: int = (s[o + FightSim.BS_DIR] / 1000) & 255
			s[o + FightSim.FACE] = f
			var stp: int = ab["spd"]
			s[o + FightSim.X] += FxMath.COS[f] * stp / FxMath.ONE
			s[o + FightSim.Z] += FxMath.SIN[f] * stp / FxMath.ONE
			clamp_world(s, P, o)
			s[o + FightSim.VX] = 0
			s[o + FightSim.VZ] = 0
			s[o + FightSim.BS_TRAV] += stp
			if _in_reach(s, P, i, ab["reach"], ab["cos_arc"]):
				var res := FightSim._take_hit(s, P, i, 3, raw_live(s, P, i, ab["raw"]), 4, -1, 2000, 1000, 0)
				if res == 1 or res == 2:
					s[o + FightSim.BS_HIT] = 1
					if res == 1:
						s[o + FightSim.AB_HITS] += 1
			if s[o + FightSim.BS_HIT] != 0 or s[o + FightSim.BS_TRAV] >= int(ab["dist"]):
				s[o + FightSim.BS_PH] = 3
				s[o + FightSim.BS_T] = 0
				s[o + FightSim.INVULN] = 0
		3:
			if s[o + FightSim.BS_T] >= (int(ab["rec_hit"]) if s[o + FightSim.BS_HIT] != 0 else int(ab["rec_miss"])):
				_end_boss(s, o)

static func _end_boss(s: PackedInt64Array, o: int) -> void:
	if s[o + FightSim.BS_PH] == 1 or s[o + FightSim.BS_PH] == 2:
		s[o + FightSim.INVULN] = 0
	s[o + FightSim.BS_PH] = 0
	s[o + FightSim.BS_T] = 0
	s[o + FightSim.AB_SLOT] = -1
	s[o + FightSim.BOSS_CD] = FightSim.boss_cd_read(s, o, s[o + FightSim.AB_SEL])

static func _rafaga(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.AB_T] < int(ab["w"]) - DODGE_LOCK:
		s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], _tdir(s, i), ab["turn"])
	while s[o + FightSim.AB_FIRED] < int(ab["count"]) and s[o + FightSim.AB_T] >= int(ab["w"]):
		var f: int = s[o + FightSim.FACE]
		var ox: int = s[o + FightSim.X] + FxMath.COS[f] * 1000000 / FxMath.ONE
		var oz: int = s[o + FightSim.Z] + FxMath.SIN[f] * 1000000 / FxMath.ONE
		FightSim.spawn_proj(s, i, 1, ox, oz, FightSim.HIT_CENTER_Y + 300000, f, ab["spd"], ab["life"], ab["radius"], raw_live(s, P, i, ab["raw"]),
			ab["force"], -1, 0, ab["home_t"], ab["home"], ab["pitch"], true)
		s[o + FightSim.AB_FIRED] += 1
	if s[o + FightSim.AB_T] >= int(ab["end"]):
		end_ability(s, o, false)

static func _timeline(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var t: int = s[o + FightSim.AB_T]
	var hits: Array = ab["hits"]
	var b := FightSim._opp(i)
	if int(ab.get("leap_hgt", 0)) > 0:
		var lhgt: int = int(ab["leap_hgt"])
		var lland: int = int(ab.get("leap_land", 81))
		if t < lland:
			s[o + FightSim.AB_AIR] = 1
			var up_tk: int = int(round(float(lland) * 0.65))
			var cur_h: int = 0
			if t < up_tk:
				cur_h = int(lhgt * sin(float(t) / float(maxi(up_tk, 1)) * PI * 0.5))
			else:
				var f_span: int = maxi(lland - up_tk, 1)
				var rem: int = clampi(lland - t, 0, f_span)
				cur_h = int(lhgt * rem * rem / (f_span * f_span))
			s[o + FightSim.FY] = cur_h
			s[o + FightSim.AIR] = 1 if cur_h > 0 else 0
			s[o + FightSim.FVY] = 0
		else:
			s[o + FightSim.AB_AIR] = 0
			s[o + FightSim.FY] = 0
			s[o + FightSim.AIR] = 0
			s[o + FightSim.FVY] = 0
	if int(ab["flick0"]) >= 0:
		if t >= int(ab["flick0"]): s[o + FightSim.AB_FL] |= FL_FLICK0
		if t >= int(ab["flick1"]): s[o + FightSim.AB_FL] |= FL_FLICK1
	if int(ab["vanish"]) >= 0:
		if t >= int(ab["vanish"]) and t < int(ab["reappear"]):
			s[o + FightSim.INVULN] = maxi(s[o + FightSim.INVULN], 5)
			s[o + FightSim.AB_FL] |= FL_VANISHED
		elif (s[o + FightSim.AB_FL] & FL_VANISHED) != 0 and t >= int(ab["reappear"]):
			s[o + FightSim.AB_FL] &= ~FL_VANISHED
			if s[b + FightSim.ALIVE] != 0:
				var bf := (s[b + FightSim.FACE] + 128) & 255
				s[o + FightSim.X] = s[b + FightSim.X] + FxMath.COS[bf] * int(ab["blink"]) / FxMath.ONE
				s[o + FightSim.Z] = s[b + FightSim.Z] + FxMath.SIN[bf] * int(ab["blink"]) / FxMath.ONE
				clamp_world(s, P, o)
				s[o + FightSim.FACE] = _tdir(s, i)
	if s[o + FightSim.AB_FIRED] < hits.size():
		var h: Array = hits[s[o + FightSim.AB_FIRED]]
		if s[b + FightSim.ALIVE] != 0 and t < int(h[4]):
			s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], _tdir(s, i), ab["track"])
		if int(h[3]) > 0 and t >= int(h[5]) and t < int(h[6]):
			var gap := FightSim._dist_to_opp(s, i) if s[b + FightSim.ALIVE] != 0 else 99000000
			if gap > int(ab["gap"]):
				s[o + FightSim.AB_VX] = FxMath.COS[s[o + FightSim.FACE]] * int(h[3]) / FxMath.ONE
				s[o + FightSim.AB_VZ] = FxMath.SIN[s[o + FightSim.FACE]] * int(h[3]) / FxMath.ONE
		if t >= int(h[0]):
			if int(ab["hit_if"]) != 0:
				s[o + FightSim.INVULN] = maxi(s[o + FightSim.INVULN], 9)
			var landed := _strike(s, P, i, ab, h)
			if s[o + FightSim.AB_SLOT] < 0:
				return # cortada por un parry
			s[o + FightSim.AB_FIRED] += 1
			if not landed and int(ab["abort"]) != 0 and s[o + FightSim.AB_FIRED] == 1:
				s[o + FightSim.AB_FIRED] = hits.size()
				s[o + FightSim.AB_T] = ab["miss_t"]
	if s[o + FightSim.AB_T] >= int(ab["end"]):
		end_ability(s, o, false)

static func _strike(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, h: Array) -> bool:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var any_hit := false
	if _in_reach(s, P, i, ab["reach"], ab["cos_arc"]):
		var raw := raw_live(s, P, i, int(ab["raw"]) * int(h[1]) / 1000)
		var res := FightSim._take_hit(s, P, i, ab["kind"], raw, ab["sub"], h[2], ab["pd_pm"], ab["counter_pm"], P[i]["atk"][SimParams.A_HEAVY if raw >= 14000 else 0]["block_cost"])
		if res == 3 and int(ab["parry_cancel"]) != 0:
			end_ability(s, o, true)
			return false
		if res == 1 or res == 2:
			any_hit = true
			s[o + FightSim.AB_FL] |= FL_LANDED
			s[o + FightSim.AB_HITS] += 1
			if res == 1 and int(ab["grab"]) != 0 and s[o + FightSim.AB_FIRED] == 0:
				s[o + FightSim.GRABS] += 1
				s[b + FightSim.GRAB_T] = ab["grab_t"]
				FightSim._apply_stun(s, b, ab["grab_stun"])
				var f: int = s[o + FightSim.FACE]
				s[b + FightSim.X] = s[o + FightSim.X] + FxMath.COS[f] * int(ab["grab_d"]) / FxMath.ONE
				s[b + FightSim.Z] = s[o + FightSim.Z] + FxMath.SIN[f] * int(ab["grab_d"]) / FxMath.ONE
				clamp_world(s, P, b)
	var last_ok: bool = int(ab["slam_last"]) == 0 or s[o + FightSim.AB_FIRED] >= (ab["hits"] as Array).size() - 1
	if last_ok and int(ab["slam_r"]) > 0 and (any_hit or int(ab.get("slam_always", 0)) != 0):
		var f2: int = s[o + FightSim.FACE]
		spawn_hz(s, i, 1, s[o + FightSim.X] + FxMath.COS[f2] * 1200000 / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[f2] * 1200000 / FxMath.ONE,
			ab["slam_warn"], ab["slam_r"], raw_live(s, P, i, int(ab["raw"]) * int(ab["slam_k"]) / 1000), ab["slam_force"], 150000, 0)
	return any_hit

static func _wave(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var t: int = s[o + FightSim.AB_T]
	if t < int(ab["w"]) - DODGE_LOCK:
		s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], _tdir(s, i), ab["turn"])
	if s[o + FightSim.AB_FIRED] == 0 and t >= int(ab["w"]):
		var raw := raw_live(s, P, i, ab["raw"])
		for off: int in ab["offs"]:
			var dir: int = (s[o + FightSim.FACE] + off) & 255
			spawn_hz(s, i, 2, s[o + FightSim.X] + FxMath.COS[dir] * 1000000 / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[dir] * 1000000 / FxMath.ONE,
				ab["warn"], 0, raw, ab["force"], 100000, 0, dir, ab["spd"], ab["range"], ab["width"])
		s[o + FightSim.AB_FIRED] = (ab["offs"] as Array).size()
	if t >= int(ab["end"]):
		end_ability(s, o, false)

static func _rain(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var ft: Array = ab["fire"]
	while s[o + FightSim.AB_FIRED] < ft.size() and s[o + FightSim.AB_T] >= int(ft[s[o + FightSim.AB_FIRED]]):
		var f: int = s[o + FightSim.FACE]
		var px: int = s[o + FightSim.X] + FxMath.COS[f] * 5000000 / FxMath.ONE
		var pz: int = s[o + FightSim.Z] + FxMath.SIN[f] * 5000000 / FxMath.ONE
		if int(ab["scatter"]) == 0:
			if s[b + FightSim.ALIVE] != 0:
				px = s[b + FightSim.X]
				pz = s[b + FightSim.Z]
		else:
			var a: int = FightSim.rng_next(s) & 255
			var u: int = FightSim.rng_next(s) % 1000000
			var rad: int = FxMath.isqrt(u * 1000000) * int(ab["scatter_r"]) / 1000000
			var cx: int = s[b + FightSim.X] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.X]
			var cz: int = s[b + FightSim.Z] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.Z]
			px = cx + FxMath.COS[a] * rad / FxMath.ONE
			pz = cz + FxMath.SIN[a] * rad / FxMath.ONE
		spawn_hz(s, i, 1, px, pz, ab["warn"], ab["r"], raw_live(s, P, i, ab["raw"]), ab["force"], ab["knock"], ab["unbl"])
		s[o + FightSim.AB_FIRED] += 1
	if s[o + FightSim.AB_T] >= int(ab["end"]):
		end_ability(s, o, false)

static func _breath(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var t: int = s[o + FightSim.AB_T]
	if t < int(ab["w"]) - DODGE_LOCK:
		s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], _tdir(s, i), ab["turn"])
	if t >= int(ab["w"]) and t < int(ab["w_end"]):
		s[o + FightSim.AB_TICK] -= 1
		if s[o + FightSim.AB_TICK] <= 0:
			s[o + FightSim.AB_TICK] = ab["tick"]
			s[o + FightSim.AB_FIRED] += 1
			if _in_reach(s, P, i, ab["range"], ab["cos_arc"]):
				var res := FightSim._take_hit(s, P, i, 4, raw_live(s, P, i, ab["raw"]), 0, ab["force"], 2000, 1000, 0, ab["elem"])
				if res == 1 or res == 2:
					s[o + FightSim.AB_HITS] += 1
	if t >= int(ab["end"]):
		end_ability(s, o, false)

static func _salto(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var t: int = s[o + FightSim.AB_T]
	var b := FightSim._opp(i)
	var land: int = int(ab["land"])
	if t < land:
		s[o + FightSim.AB_AIR] = 1 if t >= int(ab["air0"]) else 0
		var hgt: int = int(ab.get("hgt", 6000000))
		var rise: int = int(ab.get("rise", 33))
		var lock: int = int(ab.get("lock", 75))
		var cur_h: int = 0
		if t < rise:
			cur_h = int(hgt * sin(float(t) / float(maxi(rise, 1)) * PI * 0.5))
		elif t < lock:
			cur_h = hgt
		else:
			var span: int = maxi(land - lock, 1)
			var rem: int = clampi(land - t, 0, span)
			cur_h = int(hgt * rem * rem / (span * span))
		s[o + FightSim.FY] = cur_h
		s[o + FightSim.AIR] = 1 if cur_h > 0 else 0
		s[o + FightSim.FVY] = 0
		if (s[o + FightSim.AB_FL] & FL_LOCKED) == 0 and s[b + FightSim.ALIVE] != 0:
			s[o + FightSim.AB_X] = s[b + FightSim.X]
			s[o + FightSim.AB_Z] = s[b + FightSim.Z]
		if t >= int(ab["lock"]) and (s[o + FightSim.AB_FL] & FL_LOCKED) == 0:
			s[o + FightSim.AB_FL] |= FL_LOCKED
			s[o + FightSim.AB_FX] = s[o + FightSim.X]
			s[o + FightSim.AB_FZ] = s[o + FightSim.Z]
			s[o + FightSim.AB_HZ] = spawn_hz(s, i, 1, s[o + FightSim.AB_X], s[o + FightSim.AB_Z], ab["warn"], ab["r"], raw_live(s, P, i, ab["raw"]), ab["force"], 150000, 0)
		if t >= int(ab["lock"]):
			var num: int = t * 1000000 / 60 - int(ab["lock_us"])
			var den: int = maxi(int(ab["span_us"]), 1)
			num = clampi(num, 0, den)
			s[o + FightSim.X] = s[o + FightSim.AB_FX] + (s[o + FightSim.AB_X] - s[o + FightSim.AB_FX]) * num / den
			s[o + FightSim.Z] = s[o + FightSim.AB_FZ] + (s[o + FightSim.AB_Z] - s[o + FightSim.AB_FZ]) * num / den
			clamp_world(s, P, o)
		var dx: int = s[o + FightSim.AB_X] - s[o + FightSim.X]
		var dz: int = s[o + FightSim.AB_Z] - s[o + FightSim.Z]
		if FxMath.length(dx, dz) > 100000:
			s[o + FightSim.FACE] = FxMath.dir_of(dx, dz, s[o + FightSim.FACE])
	else:
		s[o + FightSim.AB_AIR] = 0
		s[o + FightSim.FY] = 0
		s[o + FightSim.AIR] = 0
		s[o + FightSim.FVY] = 0
		if t >= int(ab["end"]):
			end_ability(s, o, false)

static func _combo(s: PackedInt64Array, P: Array, i: int, ab: Dictionary) -> void:
	var o := i * FightSim.F_FIELDS
	var hits: Array = ab["hits"]
	var n := hits.size()
	var b := FightSim._opp(i)
	if (s[o + FightSim.AB_FL] & FL_READY) != 0:
		s[o + FightSim.AB_T] -= 1 # en espera el reloj de la etapa no corre (ab_combo_wait sí)
		s[o + FightSim.AB_WAIT] += 1
		if s[o + FightSim.AB_FIRED] >= n:
			if s[o + FightSim.AB_WAIT] >= int(ab["recovery"]):
				_end_combo(s, P, i, true)
			return
		if (s[o + FightSim.AB_FL] & FL_QUEUED) != 0:
			s[o + FightSim.AB_FL] &= ~(FL_QUEUED | FL_READY)
			s[o + FightSim.AB_WAIT] = 0
			s[o + FightSim.AB_T] = 0
			if s[o + FightSim.AB_FIRED] == n - 1:
				s[o + FightSim.AB_FL] |= FL_FINISHER
			return
		if s[o + FightSim.AB_WAIT] >= int(ab["chain"]):
			_end_combo(s, P, i, true)
		return
	var t: int = s[o + FightSim.AB_T]
	var final_hit: bool = s[o + FightSim.AB_FIRED] == n - 1
	var variant := final_hit and (s[o + FightSim.AB_FL] & FL_VARIANT) != 0
	var strike: int = (ab["var_w"] if variant else ab["final"]) if final_hit else ab["stage"]
	if final_hit and not variant and t >= int(ab["leap0"]) and t < strike:
		s[o + FightSim.AB_AIR] = 1
		var l0: int = int(ab["leap0"])
		var lt: int = t - l0
		var r_tk: int = int(ab.get("leap_rise", 20))
		var h_tk: int = int(ab.get("leap_hold", 13))
		var lhgt: int = int(ab.get("leap_hgt", 3200000))
		var cur_h: int = 0
		if lt < r_tk:
			cur_h = int(lhgt * sin(float(lt) / float(maxi(r_tk, 1)) * PI * 0.5))
		elif lt < r_tk + h_tk:
			cur_h = lhgt
		else:
			var f_span: int = maxi(strike - l0 - r_tk - h_tk, 1)
			var rem: int = clampi(strike - t, 0, f_span)
			cur_h = int(lhgt * rem / f_span)
		s[o + FightSim.FY] = cur_h
		s[o + FightSim.AIR] = 1 if cur_h > 0 else 0
		s[o + FightSim.FVY] = 0
		if t < strike - DODGE_LOCK and s[b + FightSim.ALIVE] != 0:
			var ax: int = s[o + FightSim.X] - s[b + FightSim.X]
			var az: int = s[o + FightSim.Z] - s[b + FightSim.Z]
			var al := FxMath.length(ax, az)
			if al > 100000:
				s[o + FightSim.AB_VX] = ax * int(ab["retreat"]) / al
				s[o + FightSim.AB_VZ] = az * int(ab["retreat"]) / al
	if s[b + FightSim.ALIVE] != 0 and FightSim._dist_to_opp(s, i) > 100000:
		if t < strike - DODGE_LOCK:
			s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], _tdir(s, i), ab["turn"])
		var lt: int = ab["var_lunge_t"] if variant else ab["lunge_t"]
		if (not final_hit or variant) and t >= lt and t < strike:
			var gap := FightSim._dist_to_opp(s, i)
			var stop: int = ab["var_stop"] if variant else ab["stop"]
			if gap > stop:
				var remaining: int = maxi(strike - t, 1)
				var v: int = mini(int(ab["lunge_spd"]), mini(int(ab["var_dist_v"] if variant else ab["lunge_dist_v"]), (gap - stop) / remaining))
				s[o + FightSim.AB_VX] = FxMath.COS[s[o + FightSim.FACE]] * v / FxMath.ONE
				s[o + FightSim.AB_VZ] = FxMath.SIN[s[o + FightSim.FACE]] * v / FxMath.ONE
	if t >= strike and variant:
		s[o + FightSim.AB_AIR] = 0
		s[o + FightSim.FY] = 0
		s[o + FightSim.AIR] = 0
		s[o + FightSim.FVY] = 0
		if s[b + FightSim.ALIVE] != 0 and _in_reach(s, P, i, ab["var_reach"], ab["var_cos"]):
			var res2 := FightSim._take_hit(s, P, i, 3, raw_live(s, P, i, int(ab["raw"]) * int(ab["var_k"]) / 1000), 4, ab["var_force"], 2000, 1000, 0)
			if res2 == 1 or res2 == 2:
				s[o + FightSim.AB_HITS] += 1
		s[o + FightSim.AB_FIRED] += 1
		s[o + FightSim.AB_FL] |= FL_READY
		s[o + FightSim.AB_WAIT] = 0
		return
	if t >= strike:
		s[o + FightSim.AB_AIR] = 0
		s[o + FightSim.FY] = 0
		s[o + FightSim.AIR] = 0
		s[o + FightSim.FVY] = 0
		var h: Array = hits[s[o + FightSim.AB_FIRED]]
		if s[b + FightSim.ALIVE] != 0 and FightSim._dist_to_opp(s, i) <= int(ab["strike_r"]) + P[1 - i]["hit_radius"]:
			var res := FightSim._take_hit(s, P, i, 3, raw_live(s, P, i, int(ab["raw"]) * int(h[0]) / 1000), 4, h[1], 2000, 1000, 0)
			if res == 1 and (s[o + FightSim.AB_FL] & FL_STAGGERED) == 0:
				FightSim._apply_stun(s, b, ab["stagger"])
				s[o + FightSim.AB_FL] |= FL_STAGGERED
			if res == 1 or res == 2:
				s[o + FightSim.AB_HITS] += 1
		if s[o + FightSim.AB_FIRED] == n - 1:
			var f: int = s[o + FightSim.FACE]
			spawn_hz(s, i, 1, s[o + FightSim.X] + FxMath.COS[f] * 1000000 / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[f] * 1000000 / FxMath.ONE,
				ab["slam_warn"], ab["slam_r"], raw_live(s, P, i, int(ab["raw"]) * int(ab["slam_k"]) / 1000), ab["slam_force"], 150000, 0)
		s[o + FightSim.AB_FIRED] += 1
		s[o + FightSim.AB_FL] |= FL_READY
		s[o + FightSim.AB_WAIT] = 0
