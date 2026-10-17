class_name SimParams
extends RefCounted
## Parámetros de la simulación online (solo lectura durante la partida). Se "hornean" a enteros al
## empezar el combate a partir de los Fighter reales (personaje, arma, atributos, armadura,
## talismanes), de modo que la sim usa los mismos números que el juego offline. Ambos pares hornean
## con los mismos datos de partida y comparan params_checksum() antes de empezar.
##
## Unidades: posición µm, velocidad µm/tick, vida/aguante/fuerza en milésimas, factores en ‰, tiempo en ticks (60 Hz).

const HZ := 60.0
## Índices de ataque: 0..2 golpes del combo ligero, 3 fuerte, 4 estocada (dash/voltereta/carrera).
const A_HEAVY := 3
const A_DASH := 4
const A_JUMP := 5 ## fase 7: picado desde el salto
## Alturas de referencia. No entran en el diccionario horneado ni en params_checksum:
## la sim todavía no las aplica (el salto sigue en JUMP_VELOCITY / GRAVITY).
## mount_hover_m: la montura levita a 1,2 m. El salto llega a 1,6 m, así que se la alcanza saltando.
const MOUNT_HOVER_M := 1.2
const MOUNT_HOVER_UM := 1200000
## eikon_fly_m: vuelo alto del Eikon, 3,5 m, estado temporal. Todavía no se simula.
## Diseño: 5–8 s, maná continuo, arriba no se bloquea ni se hace parry, bajar avisa y se castiga.
const EIKON_FLY_M := 3.5
const EIKON_FLY_UM := 3500000
## Subtipos físicos para la tabla de defensa: 0 = sin subtipo (flechas), 1..4 = PhysTypes.
const SUBS := ["", "estandar", "cortante", "contundente", "perforante"]
const DEF_TAB_MAX := 400 ## daño bruto máximo tabulado (por unidad)
## Entra en params_checksum. Por defecto 1: las 45 salen por SimSteps.
## El valor ya no elige el camino (el camino sin envolver no existe). Queda en los params
## para que un cliente viejo no coincida en el checksum.
static var ab_engine := 1

static func sub_code(sub: String) -> int:
	return maxi(SUBS.find(sub), 0)

## Ticks hasta que un temporizador offline (t += 1/60 en float, condición t >= sec) se cumple.
## Reproduce el redondeo real del juego offline (p. ej. 0,4 s = 25 ticks, no 24).
static func tk(sec: float) -> int:
	var t := 0.0
	var n := 0
	var dt := 1.0 / HZ
	while t < sec and n < 100000:
		t += dt
		n += 1
	return n

static func um(m: float) -> int:
	return int(round(m * 1000000.0))

static func milli(v: float) -> int:
	return int(round(v * 1000.0))

static func pm(v: float) -> int:
	return int(round(v * 1000.0))

static func cos_q(deg: float) -> int:
	return int(round(cos(deg_to_rad(minf(deg, 180.0))) * FxMath.ONE))

## Hornea los parámetros de los dos luchadores (a = jugador 0, b = jugador 1).
static func bake(a: Fighter, b: Fighter) -> Array:
	return [_bake_one(a, b), _bake_one(b, a)]

static func _bake_one(f: Fighter, o: Fighter) -> Dictionary:
	var p := {}
	var st_k: float = float(f.tfx["stamina_cost"])
	var sp := f.attr_speed()
	var w := f.melee()
	var foot: MountData = f.foot_stats
	p["hp"] = milli(f.max_health)
	p["st_max"] = milli(f.stamina_max)
	p["speed"] = um(foot.speed * f.speed_mult() / HZ)
	p["sprint_pm"] = pm(foot.sprint_multiplier)
	p["acc"] = um(Fighter.FOOT_MOVE_ACCEL / HZ / HZ)
	p["acc_sprint"] = um(Fighter.FOOT_SPRINT_ACCEL / HZ / HZ)
	p["brake"] = um(Fighter.FOOT_BRAKE_ACCEL / HZ / HZ)
	p["turn"] = maxi(int(round(Fighter.TURN_RATE_DEG / HZ * 256.0 / 360.0)), 1)
	p["steer"] = maxi(int(round(Fighter.TURN_RATE_DEG * Fighter.STEER_TURN_MULT / HZ * 256.0 / 360.0)), 1)
	p["sprint_up"] = maxi(int(round(1000.0 / (Fighter.SPRINT_RAMP_UP * HZ))), 1)
	p["sprint_down"] = maxi(int(round(1000.0 / (Fighter.SPRINT_RAMP_DOWN * HZ))), 1)
	p["cost_jump"] = milli(Fighter.COST_JUMP * st_k)
	var rm := f.roll_mod()
	p["regen"] = milli(Fighter.REGEN * float(rm["regen"]) / HZ)
	p["regen_idle"] = milli(Fighter.REGEN_IDLE * float(rm["regen"]) / HZ)
	p["regen_delay"] = tk(Fighter.REGEN_DELAY)
	p["exhaust"] = tk(Fighter.EXHAUST_TIME)
	p["drain_block"] = milli(Fighter.DRAIN_BLOCK * st_k / HZ)
	p["drain_sprint"] = milli(Fighter.DRAIN_SPRINT * st_k / HZ)
	var roll_k: float = f.character.roll_cost_mult * float(f.mods["roll_cost"]) * float(f.ad["roll_cost"]) * st_k
	p["cost_roll"] = milli(Fighter.COST_ROLL * roll_k)
	p["cost_backstep"] = milli(Fighter.BACKSTEP_STAMINA * roll_k)
	p["cost_parry"] = milli(Fighter.COST_PARRY * st_k)
	p["cost_bow"] = milli(Fighter.COST_BOW * st_k)
	p["dash_cd"] = tk(foot.dash_cooldown)
	p["roll_start"] = tk(Fighter.ROLL_STARTUP)
	p["roll_if_end"] = tk(f.roll_iframe_end())
	p["roll_total"] = tk(f.roll_total())
	p["roll_fast"] = tk(Fighter.ROLL_IFRAME_END)
	p["roll_dist"] = um(Fighter.ROLL_DISTANCE * float(rm["dist"]))
	p["roll_drift"] = um(Fighter.ROLL_RECOVERY_DRIFT)
	p["roll_buffer"] = tk(Fighter.ROLL_BUFFER)
	p["backstep_t"] = tk(Fighter.BACKSTEP_TIME)
	p["backstep_v"] = um(Fighter.BACKSTEP_DISTANCE / Fighter.BACKSTEP_TIME / HZ)
	p["parry_window"] = tk(f.parry_window)
	p["parry_recovery"] = tk(Fighter.PARRY_RECOVERY)
	p["parry_stagger"] = tk(Fighter.PARRY_STAGGER)
	p["swap_t"] = tk(Fighter.SWAP_TIME)
	p["hit_radius"] = um(0.75)
	p["robust"] = milli(f.robustness())
	p["stance_max"] = milli(f.stance_max)
	p["stance_regen"] = milli(Fighter.STANCE_REGEN / HZ)
	p["has_shield"] = 1 if f.has_shield() else 0
	p["chip_pm"] = pm(Fighter.BLOCK_REDUCTION if f.has_shield() else w.no_shield_block_chip)
	var conc := EquipStats.resist_mult("concentracion", f.eq, f.eq_ref) if not f.eq.is_empty() else 1.0
	p["guard_break_t"] = tk(Fighter.GUARD_BREAK_STAGGER * conc)
	p["max_combo"] = f.max_combo()
	p["pillars"] = 1 if Projectile.obstacles.size() == 6 else 0 # la arena real los tiene
	p["has_bow"] = 1 if f.secondary != null else 0
	# Ataques
	var atks: Array = []
	for i in 3:
		atks.append(_bake_attack(f, o, i, st_k, sp))
	atks.append(_bake_attack(f, o, A_HEAVY, st_k, sp))
	atks.append(_bake_attack(f, o, A_DASH, st_k, sp))
	atks.append(_bake_attack(f, o, A_JUMP, st_k, sp))
	p["atk"] = atks
	p["gc_pm"] = pm(Fighter.GC_WINDUP_MULT)
	p["crit_raw"] = milli(w.heavy_damage * _dmg_mult(f) * Fighter.CRIT_MULT)
	p["crit_sub"] = sub_code(w.phys_type)
	# Defensa de ESTE luchador como defensor: tabla incoming(a)/a (ppm) por subtipo, a = 0..400
	if not f.eq.is_empty():
		var tabs: Array = []
		for sb: String in SUBS + ELEMS:
			var t := PackedInt32Array()
			for a in DEF_TAB_MAX + 1:
				var amt := maxf(float(a), 0.01)
				var v := EquipStats.incoming(amt, sb, f.eq, f.eq_ref) if sb in ELEMS else EquipStats.incoming(amt, "fisico", f.eq, f.eq_ref, sb)
				t.append(int(round(v / amt * 1000000.0)))
			tabs.append(t)
		p["def_tab"] = tabs
	# Infusiones (elemento) y estados que inflige / umbrales que recibe
	p["elem_melee"] = _elem_code(f.melee())
	p["elem_arrow"] = _elem_code(f.ranged())
	p["st_melee"] = _status_arr(f.melee().status)
	p["st_arrow"] = _status_arr(f.ranged().status)
	var thr: Array[int] = []
	for k: String in StatusFx.TYPES:
		thr.append(milli(f.status_threshold(k)))
	p["st_thr"] = thr
	p["bleed_dmg"] = milli(f.max_health * StatusFx.BLEED_PCT + StatusFx.BLEED_FLAT)
	p["frost_dmg"] = milli(f.max_health * StatusFx.FROST_PCT + StatusFx.FROST_FLAT)
	# Pasivas y talismanes con efecto en tiempo de partida
	p["furia_pm"] = pm(0.25 * f.passive_k()) if f.character.passive_id == "furia" else 0
	p["heal_tick"] = milli(2.0 * f.passive_k() * float(f.ad["curacion"]) / HZ) if f.character.passive_id == "luz_sanadora" else 0
	p["parry_stamina"] = milli(float(f.tfx["parry_stamina"]))
	p["aim_lead_pm"] = pm(f.aim_lead)
	# Arco
	var r := f.ranged()
	p["bow_draw"] = tk(r.fire_draw / sp)
	p["bow_recovery"] = tk(r.fire_recovery)
	p["bow_recovery_ch"] = tk(r.fire_recovery * 1.2)
	p["bow_reload"] = tk(r.reload_time)
	p["bow_cd"] = tk(r.fire_cooldown)
	p["bow_hold"] = tk(Fighter.CHARGE_HOLD)
	p["bow_slow_pm"] = pm(r.fire_slow)
	var kind := f.charged_shot_kind()
	var dmg_k := 1.0
	var spd_k := 1.0
	var stun_k := 1.0
	var n := 1
	if kind == "potente":
		dmg_k = 2.4 if f.character.passive_id == "ojo_de_halcon" else 2.2
		spd_k = 1.4
		stun_k = 2.5
	else:
		n = 3
		dmg_k = 0.7
		stun_k = 1.2
	var base := r.arrow_damage * (1.0 + 0.3 * f.passive_k() if f.character.passive_id == "ojo_de_halcon" else 1.0) * f.weapon_attr_mult(r) * r.upgrade_dmg_mult
	p["arrow_raw"] = milli(base)
	p["arrow_raw_ch"] = milli(base * dmg_k)
	p["arrow_reflect_life"] = tk(2.0)
	p["arrow_speed"] = um(r.projectile_speed / HZ)
	p["arrow_speed_ch"] = um(r.projectile_speed * spd_k / HZ)
	p["arrow_force"] = milli(f.arrow_stun_force(r.ranged_hitstun))
	p["arrow_force_ch"] = milli(f.arrow_stun_force(r.ranged_hitstun * stun_k))
	p["arrow_n_ch"] = n
	p["arrow_life"] = tk(2.5)
	p["arrow_radius"] = um(0.5)
	p["arrow_block_cost"] = milli(Fighter.COST_BLOCKED_ARROW * float(o.tfx["stamina_cost"]))
	p["counter_arrow_pm"] = pm(float(PhysTypes.COUNTER_DMG["estandar"]))
	# Fase 4: habilidades de jefe, magia, eikon y montura (cubiertos por params_checksum)
	p["ab_engine"] = ab_engine
	p["boss"] = SimAbilities.compile_all(f)
	# fase 8: frasco (Fighter.drink_flask)
	p["flasks"] = 1
	p["flask_t"] = tk(Fighter.FLASK_TIME)
	p["flask_heal_pm"] = pm(Fighter.FLASK_HEAL_FRACTION)
	SimMagic.bake(f, p)
	p["m_dash_bc"] = milli(o.blocked_hit_cost(Fighter.DASH_DAMAGE, f) * float(o.tfx["stamina_cost"]))
	return p

## damage_mult sin la parte que depende del estado (furia con vida baja): la sim la aplica en vivo.
static func _dmg_mult(f: Fighter) -> float:
	var k := f.damage_mult()
	if f.character.passive_id == "furia" and f.health < f.max_health * 0.4:
		k /= 1.0 + 0.25 * f.passive_k()
	return k

static func _incoming(o: Fighter, amount: float, sub: String) -> float:
	if o.eq.is_empty():
		return amount
	return EquipStats.incoming(amount, "fisico", o.eq, o.eq_ref, sub)

static func _bake_attack(f: Fighter, o: Fighter, idx: int, st_k: float, sp: float) -> Dictionary:
	var w := f.melee()
	var d: Dictionary
	var h: ComboHit = null
	var reach := w.reach_foot
	var arc := w.half_arc_foot_deg
	var hitstun := 0.3
	var resist := 0.0
	var pmult := w.poise_damage_mult
	var sub := w.phys_type
	var step := w.step_heavy
	var window := -1.0
	var lunge := 0.0
	if idx == A_JUMP:
		d = Fighter.JUMP_ATTACK.duplicate()
		hitstun = 0.45
		resist = StunRules.DASH_JUMP_RESIST
		step = 0.0
	elif idx == A_DASH:
		d = Fighter.DASH_STRIKE.duplicate()
		hitstun = 0.45
		resist = StunRules.DASH_JUMP_RESIST
		step = 0.0
		lunge = Fighter.LUNGE_SPEED
	elif idx == A_HEAVY:
		d = w.attack(true)
		hitstun = w.heavy_hitstun
		resist = w.heavy_stun_resist
	else:
		h = f.combo_hit_for(idx + 1)
		d = h.attack_dict() if h else w.attack(false)
		step = w.step_light[clampi(idx, 0, w.step_light.size() - 1)] if not w.step_light.is_empty() else 0.0
		if h:
			reach = h.reach
			arc = h.arc_deg
			hitstun = h.hitstun
			resist = h.stun_resist
			pmult *= h.poise_mult
			window = h.window
			lunge = h.lunge
			sub = PhysTypes.of_hit(w, h)
	var raw: float = float(d["damage"]) * _dmg_mult(f)
	var per := h.stun_force if (h and h.stun_force >= 0.0) else hitstun * StunRules.HITSTUN_TO_FORCE
	var force := (StunRules.str_force(float(f.attributes().get("fuerza", 10))) + StunRules.weapon_force(w) + per) * float(f.ad.get("stun_dealt", 1.0))
	pmult *= float(PhysTypes.POISE_MOD.get(sub, 1.0))
	return {
		"windup": tk(float(d["windup"]) / sp), "active": tk(float(d["active"])),
		"recovery": tk(float(d["recovery"]) / sp), "whiff": tk(float(d["whiff"]) / sp),
		# sumas horneadas como un solo temporizador (el offline acumula un único float)
		"rec_hit": tk(float(d["recovery"]) / sp), "rec_whiff": tk(float(d["recovery"]) / sp + float(d["whiff"]) / sp),
		"rec_hit_fin": tk(float(d["recovery"]) / sp + Fighter.FINISHER_EXTRA_RECOVERY),
		"rec_whiff_fin": tk(float(d["recovery"]) / sp + float(d["whiff"]) / sp + Fighter.FINISHER_EXTRA_RECOVERY),
		"gc_windup": tk(float(d["windup"]) / sp * Fighter.GC_WINDUP_MULT),
		"stamina": milli(float(d["stamina"]) * st_k),
		"reach": um(reach), "cos_arc": cos_q(arc), "window": tk(window) if window >= 0.0 else -1,
		"step": um(step), "lunge": um(lunge * f.speed_mult() / HZ),
		"raw": milli(raw), "sub": sub_code(sub),
		"force": milli(force), "resist_pm": pm(resist),
		"pd_pm": pm(2.0 * pmult * float(f.ad["impacto"])),
		"counter_pm": pm(float(PhysTypes.COUNTER_DMG.get(sub, 1.15))),
		"block_cost": milli(o.blocked_hit_cost(raw, f) * float(o.tfx["stamina_cost"])),
		# montado: el coste de bloqueo sale del daño con el multiplicador de la montura (umbral de golpe fuerte)
		"block_cost_m": milli(o.blocked_hit_cost(raw * w.mounted_damage_mult, f) * float(o.tfx["stamina_cost"])),
		"heavy_hit": 1 if raw >= Fighter.HEAVY_HIT else 0,
	}

## Parámetros por defecto sin árbol de escena (pruebas puras de rollback): dos luchadores neutros.
static func defaults() -> Array:
	var p := {
		"hp": 100000, "st_max": 100000, "speed": 138333, "sprint_pm": 1600,
		"acc": um(Fighter.FOOT_MOVE_ACCEL / HZ / HZ), "acc_sprint": um(Fighter.FOOT_SPRINT_ACCEL / HZ / HZ), "brake": um(Fighter.FOOT_BRAKE_ACCEL / HZ / HZ),
		"turn": maxi(int(round(Fighter.TURN_RATE_DEG / HZ * 256.0 / 360.0)), 1),
		"steer": maxi(int(round(Fighter.TURN_RATE_DEG * Fighter.STEER_TURN_MULT / HZ * 256.0 / 360.0)), 1),
		"sprint_up": maxi(int(round(1000.0 / (Fighter.SPRINT_RAMP_UP * HZ))), 1), "sprint_down": maxi(int(round(1000.0 / (Fighter.SPRINT_RAMP_DOWN * HZ))), 1),
		"cost_jump": 12000, "regen": 300, "regen_idle": 533, "regen_delay": 36, "exhaust": 90, "drain_block": 50, "drain_sprint": 333,
		"cost_roll": 20000, "cost_backstep": 6000, "cost_parry": 15000, "cost_bow": 6000, "dash_cd": 48,
		"roll_start": 4, "roll_if_end": 28, "roll_total": 48, "roll_fast": 28, "roll_dist": 4500000, "roll_drift": 400000,
		"roll_buffer": 11, "backstep_t": 21, "backstep_v": 95238, "parry_window": 18, "parry_recovery": 48, "parry_stagger": 96,
		"swap_t": 26, "has_bow": 1, "hit_radius": 750000, "robust": 50000, "stance_max": 175000, "stance_regen": 200, "has_shield": 1,
		"chip_pm": 120, "guard_break_t": 60, "max_combo": 3, "gc_pm": 600, "crit_raw": 57200, "crit_sub": 1,
		"bow_draw": 30, "bow_recovery": 24, "bow_recovery_ch": 29, "bow_reload": 0, "bow_cd": 9, "bow_hold": 54, "bow_slow_pm": 250,
		"arrow_raw": 8000, "arrow_raw_ch": 17600, "arrow_reflect_life": 120, "arrow_speed": 533333, "arrow_speed_ch": 746667,
		"arrow_force": 18000, "arrow_force_ch": 33000, "arrow_n_ch": 1, "arrow_life": 150, "arrow_radius": 500000,
		"arrow_block_cost": 3000, "counter_arrow_pm": 1150,
	}
	var atks: Array = []
	for i in 3:
		atks.append({"windup": 26 if i < 2 else 30, "active": 8, "recovery": 33, "whiff": 15, "stamina": 13000, "reach": 2200000,
			"cos_arc": 1401, "window": 27, "step": 900000 if i < 2 else 1200000, "lunge": 0, "raw": 11000 if i < 2 else 14000,
			"sub": 1, "force": 26000 if i < 2 else 34000, "resist_pm": 0, "pd_pm": 2000 if i < 2 else 2600,
			"counter_pm": 1150, "block_cost": 22000 if i < 2 else 44000, "heavy_hit": 0 if i < 2 else 1})
	atks.append({"windup": 48, "active": 9, "recovery": 45, "whiff": 21, "stamina": 28000, "reach": 2200000, "cos_arc": 1401,
		"window": -1, "step": 1400000, "lunge": 0, "raw": 26000, "sub": 1, "force": 38000, "resist_pm": 1000, "pd_pm": 2000,
		"counter_pm": 1150, "block_cost": 44000, "heavy_hit": 1})
	atks.append({"windup": 10, "active": 9, "recovery": 30, "whiff": 15, "stamina": 10000, "reach": 2200000, "cos_arc": 1401,
		"window": -1, "step": 0, "lunge": 200000, "raw": 15000, "sub": 1, "force": 32000, "resist_pm": 500, "pd_pm": 2000,
		"counter_pm": 1150, "block_cost": 44000, "heavy_hit": 1})
	atks.append({"windup": 13, "active": 7, "recovery": 27, "whiff": 12, "stamina": 14000, "reach": 2200000, "cos_arc": 1401,
		"window": -1, "step": 0, "lunge": 0, "raw": 16000, "sub": 1, "force": 32000, "resist_pm": 500, "pd_pm": 2000,
		"counter_pm": 1150, "block_cost": 44000, "heavy_hit": 1})
	p["atk"] = atks
	return [p, p.duplicate(true)]

## Holgura de parada online: +1 tick por tick de retardo de entrada por encima de 1, máximo 2
## (≤ 33 ms). La recuperación se acorta lo mismo, así el compromiso total de la parada no cambia.
static func lenience_for_delay(delay: int) -> int:
	return clampi(delay - 1, 0, 2)

static func online_tuning(ps: Array, lenience: int) -> Array:
	var out: Array = ps.duplicate(true)
	for p: Dictionary in out:
		p["parry_window"] = int(p["parry_window"]) + lenience
		p["parry_recovery"] = maxi(1, int(p["parry_recovery"]) - lenience)
		p["net_lenience"] = lenience
	return out

const ELEMS := ["fuego", "magico", "sagrado", "rayo", "hielo"] ## códigos 5..9 tras SUBS en def_tab

static func _elem_code(w: WeaponDef) -> int:
	if w == null: return 0
	var el := String(Smithing.INFUSIONS.get(String(w.infusion), {}).get("element", ""))
	var i := ELEMS.find(el)
	return 0 if i < 0 else SUBS.size() + i

static func _status_arr(st: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k: String in StatusFx.TYPES:
		out.append(milli(float(st.get(k, 0.0))))
	return out

static func params_checksum(ps: Array) -> int:
	# FNV-1a de 32 bits sobre el texto UTF-8: estable entre plataformas (hash() no lo garantiza).
	var h := 2166136261
	for b in var_to_str(ps).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h
