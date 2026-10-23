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
const EldenCatalog = preload("res://scripts/data/elden_catalog.gd")
const ExtraCatalog = preload("res://scripts/data/extra_catalog.gd")

static func compile(f: Fighter, id: String) -> Dictionary:
	var a := HojaCatalog.ability(id)
	if a.is_empty() and EldenCatalog.has(id):
		a = EldenCatalog.ability(id)
	if a.is_empty() and ExtraCatalog.has(id):
		a = ExtraCatalog.ability(id)
	if a.is_empty():
		return {}
	var w := f.melee()
	var dm := SimParams._dmg_mult(f)
	var magia := float(f.ad.get("magia", 100.0)) / 100.0
	var st_k := float(f.tfx["stamina_cost"])
	var phys_f := StunRules.str_force(float(f.attributes().get("fuerza", 10))) + StunRules.weapon_force(w)
	var sd := float(f.ad.get("stun_dealt", 1.0))
	var mag_f := StunRules.magic_force(float(f.ad.get("magia", 100.0)))
	return compile_dict(a, dm, magia, st_k, phys_f, sd, mag_f, SimAbilities.code_of(id))

static func compile_dict(a: Dictionary, dm: float = 1.0, magia: float = 1.0, st_k: float = 1.0, phys_f: float = 10.0, sd: float = 1.0, mag_f: float = 10.0, code_override: int = -1) -> Dictionary:
	var id := String(a.get("id", ""))
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
	var n_st := steps.size()
	var depth_map := {}
	depth_map[0] = 0
	for idx in n_st:
		var d: int = depth_map.get(idx, 0)
		var st_c: Dictionary = steps[idx]
		var targets := [int(st_c["nxt"]), int(st_c["brs"]), int(st_c["bra"]), int(st_c["brd"]), int(st_c.get("cancel_step", -1))]
		if st_c.has("combo_win") and st_c["combo_win"] is Array:
			for cw_v: Variant in st_c["combo_win"]:
				if cw_v is Dictionary:
					targets.append(int((cw_v as Dictionary).get("step", -1)))
		for tg: int in targets:
			if tg >= 0 and tg < n_st and tg != idx:
				depth_map[tg] = maxi(depth_map.get(tg, 0), d + 1)
	var max_d := 0
	for d_val: int in depth_map.values():
		max_d = maxi(max_d, d_val)
	var total_chain := max_d + 1
	for idx in n_st:
		steps[idx]["chain_idx"] = depth_map.get(idx, 0)
		steps[idx]["total_chain"] = total_chain
	var out := {
		"code": code_override if code_override >= 0 else SimAbilities.code_of(id), "id": id, "type": SimAbilities.T_CATALOG,
		"cost_type": int(ct[0]), "cost": int(ct[1]),
		"unbl": 0, "resist": 0, "raw": 0,
		"cd": int(a.get("cooldown", 0)), "imask": int(a.get("interrupt_mask", 0)),
		"phase": int(a.get("unlock_phase", 1)), "entry": int(a.get("entry", 0)),
		"rmin": int(ai.get("range_min", 0)), "rmax": int(ai.get("range_max", 0)),
		"balt": balt, "steps": steps,
	}
	var entry_idx := int(a.get("entry", 0))
	var cost_at := int(a.get("cost_at_tick", a.get("cost_at", -1)))
	if cost_at < 0 and entry_idx >= 0 and entry_idx < steps.size() and (steps[entry_idx] as Dictionary).has("cost_at"):
		cost_at = int(steps[entry_idx]["cost_at"])
	if a.has("chain") and a["chain"] is Dictionary:
		var ch: Dictionary = a["chain"]
		out["chain"] = ch.duplicate()
		if int(ch.get("cooldown_on", 0)) == 1 or int(ch.get("cd_on", 0)) == 1:
			out["cd_end"] = 1
		if int(ch.get("cost_on", 0)) == 1 and cost_at < 0 and entry_idx >= 0 and entry_idx < steps.size():
			cost_at = int(steps[entry_idx].get("w", 0))
	if cost_at >= 0:
		out["cost_at"] = cost_at
	if a.has("phase_transition") and a["phase_transition"] is Dictionary:
		out["pt"] = (a["phase_transition"] as Dictionary).duplicate()
	if ai.has("chain_continue_pct"):
		out["chain_cont_pct"] = int(ai["chain_continue_pct"])
	return out

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
		if mv_k != 1 and mv_k != 2 and mv_k != 3 and mv_k != 6:
			mv_k = 0
		mv0 = int(mv.get("from", 0))
		mv1 = int(mv.get("to", 0))
		spd = int(mv.get("speed", 0))
		maxd = SimAbilities.reach_up(int(mv.get("max", 0)))
		stop = int(mv.get("stop", 0))
		height = int(mv.get("height", 0))
		mode = 1 if int(mv.get("target", 0)) == 2 else 0
	var imp := 0
	if mv is Dictionary:
		imp = int(mv.get("imp", 0))
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
	if int(hb.get("ground_only", 0)) == 0:
		hbr = SimAbilities.reach_up(hbr)
		hbw = SimAbilities.reach_up(hbw)
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
	var marks: Array = []
	var waves: Array = []
	for sp: Variant in src.get("spawns", []):
		if not (sp is Dictionary):
			continue
		var sk: int = int((sp as Dictionary).get("type", -1))
		if sk == 3 and spawn.is_empty():
			spawn = sp
		elif sk == 0:
			marks.append(sp)
		elif sk == 1:
			waves.append(sp)
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
	var evs: Array = []
	for ev: Variant in src.get("events", []):
		if ev is Dictionary:
			var e: Dictionary = ev
			var ce := {"id": String(e.get("id", "")), "tick": int(e.get("tick", 0)), "shake": int(e.get("shake", 0))}
			if e.has("duration") or e.has("dur"):
				ce["dur"] = int(e.get("duration", e.get("dur", 0)))
			if e.has("stop_on_interrupt") or e.has("stop_int"):
				ce["stop_int"] = int(e.get("stop_on_interrupt", e.get("stop_int", 1)))
			for ek: String in ["outlive", "attach", "sfx_attach", "follow", "sfx_loop", "footstep", "shake_obj", "vfx", "sfx"]:
				if e.has(ek):
					if ek in ["vfx", "sfx"] and not (ce.has("dur") or e.has("attach") or e.has("sfx_attach") or e.has("follow") or e.has("sfx_loop") or e.has("footstep") or e.has("shake_obj")):
						continue
					ce[ek] = e[ek]
			evs.append(ce)
	var out := {
		"w": int(src.get("windup", 0)), "a": int(src.get("active", 0)), "r": int(src.get("recovery", 0)),
		"dur": int(src.get("total", 0)),
		"trk": _headings(int(tr.get("turn", 0))),
		"trk2": _headings(int(tr.get("post", 0))),
		"lock": SimAbilities.pursue_lock(int(tr.get("lock", 0)), int(src.get("windup", 0))),
		"mv": mv_k, "mv0": mv0, "mv1": mv1, "spd": spd, "maxd": maxd, "stop": stop, "height": height, "mode": mode, "imp": imp,
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
		"marks": _marks(marks, dm, magia),
		"waves": _waves(waves, dm, magia),
		"evs": evs,
	}
	if nx is Dictionary:
		if int(nx.get("on_hit", -1)) >= 0: out["nxt_hit"] = int(nx["on_hit"])
		if int(nx.get("on_block", -1)) >= 0: out["nxt_block"] = int(nx["on_block"])
		if int(nx.get("on_whiff", -1)) >= 0: out["nxt_whiff"] = int(nx["on_whiff"])
	if tr.has("windows") and tr["windows"] is Array:
		var tw: Array = []
		for w: Variant in tr["windows"]:
			if w is Dictionary:
				var w_mrh := int(w.get("turn", w.get("turn_mrh", 0)))
				var w_cdeg := int(w.get("cdeg", w.get("cdeg_pt", 0)))
				tw.append({"from": int(w.get("from", 0)), "to": int(w.get("to", 0)), "turn": _headings(w_mrh), "cdeg_pt": w_cdeg})
		out["tr_win"] = tw
	var has_adv_mv := src.has("movements")
	if not has_adv_mv and mv is Dictionary:
		var mvd: Dictionary = mv
		has_adv_mv = mvd.has("rmin") or mvd.has("range_min") or mvd.has("rmax") or mvd.has("range_max") or mvd.has("fit") or mvd.has("ang_cdeg") or mvd.has("arrive_cdeg") or mvd.has("gfrom") or mvd.has("gate_from") or mvd.has("gto") or mvd.has("gate_to") or mvd.has("ref_d") or mvd.has("ref_dist") or mvd.has("dscale") or mvd.has("scale_windows") or int(mvd.get("type", 0)) == 7
	if has_adv_mv:
		var mv_src: Array = src["movements"] if src.has("movements") and src["movements"] is Array else [mv]
		out["mvs"] = _compile_mvs(mv_src)
	var ew_arr = src.get("exit_windows", src.get("exit_win", null))
	if ew_arr is Array:
		out["exit_win"] = (ew_arr as Array).duplicate(true)
		out["exit_buf"] = int(src.get("exit_buffer", src.get("exit_buf", 0)))
	var cw_arr = src.get("combo_input_windows", src.get("combo_win", null))
	if cw_arr is Array:
		out["combo_win"] = (cw_arr as Array).duplicate(true)
	if (out.has("exit_win") or out.has("combo_win")) and src.get("cancel", null) is Dictionary:
		var csteps: Array = (src["cancel"] as Dictionary).get("steps", [])
		if not csteps.is_empty():
			out["cancel_step"] = int(csteps[0])
	if src.has("weapon_trail") and src["weapon_trail"] is Dictionary:
		out["weapon_trail"] = (src["weapon_trail"] as Dictionary).duplicate()
	var has_variants := boxes.size() > 1
	if not has_variants and boxes.size() == 1 and boxes[0] is Dictionary:
		has_variants = (boxes[0] as Dictionary).has("variant")
	if has_variants:
		out["hbs"] = _compile_hbs(boxes, dm, magia, phys_f, sd, mag_f)
	var volleys := _compile_volleys(src.get("spawns", []), boxes, dm, magia, phys_f, sd, mag_f)
	if not volleys.is_empty():
		out["volleys"] = volleys
	var sw_arr = src.get("self_windows", src.get("self_win", null))
	if sw_arr is Array:
		out["self_win"] = (sw_arr as Array).duplicate(true)
	if src.has("cost_at_tick") or src.has("cost_at"):
		out["cost_at"] = int(src.get("cost_at_tick", src.get("cost_at", 0)))
	if src.has("charge") and src["charge"] is Dictionary:
		out["charge"] = (src["charge"] as Dictionary).duplicate(true)
	var ss_arr = src.get("self_status_at", src.get("self_st", null))
	if ss_arr is Array:
		out["self_st"] = (ss_arr as Array).duplicate(true)
	var cw_dict = src.get("counter_window", src.get("cwin", null))
	if cw_dict is Dictionary:
		out["cwin"] = (cw_dict as Dictionary).duplicate()
	var gw_arr = src.get("guard_windows", src.get("gwin", null))
	if gw_arr is Array:
		out["gwin"] = (gw_arr as Array).duplicate(true)
	if src.has("chain_role"):
		out["crole"] = int(src["chain_role"])
	return out

static func _compile_mvs(mv_src: Array) -> Array:
	var res: Array = []
	for m: Variant in mv_src:
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		var mk := int(md.get("type", 0))
		if mk != 1 and mk != 2 and mk != 3 and mk != 6 and mk != 7:
			mk = 0
		var m0 := int(md.get("from", 0))
		var m1 := int(md.get("to", 0))
		var max_raw := int(md.get("max", 0))
		var dsc = md.get("scale_windows", md.get("dscale", []))
		res.append({
			"mv": mk, "mv0": m0, "mv1": m1,
			"spd": int(md.get("speed", 0)),
			"maxd": SimAbilities.reach_up(max_raw),
			"max_raw": max_raw,
			"stop": int(md.get("stop", 0)),
			"height": int(md.get("height", 0)),
			"mode": 1 if int(md.get("target", 0)) == 2 else 0,
			"imp": int(md.get("imp", 0)),
			"rmin": int(md.get("range_min", md.get("rmin", -1))),
			"rmax": int(md.get("range_max", md.get("rmax", -1))),
			"fit": int(md.get("fit", 0)),
			"ang_cdeg": int(md.get("arrive_cdeg", md.get("ang_cdeg", 0))),
			"gfrom": int(md.get("gate_from", md.get("gfrom", m0))),
			"gto": int(md.get("gate_to", md.get("gto", m1))),
			"ref_d": int(md.get("ref_dist", md.get("ref_d", -1))),
			"dscale": (dsc as Array).duplicate(true) if dsc is Array else [],
		})
	return res

static func _compile_hbs(boxes: Array, dm: float, magia: float, phys_f: float, sd: float, mag_f: float) -> Array:
	var res: Array = []
	for b_var: Variant in boxes:
		if not (b_var is Dictionary):
			continue
		var hb: Dictionary = b_var
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
		if int(hb.get("ground_only", 0)) == 0:
			hbr = SimAbilities.reach_up(hbr)
			hbw = SimAbilities.reach_up(hbw)
		var st: Variant = hb.get("status", null)
		var bleed := 1 if st is Dictionary and int((st as Dictionary).get("type", -1)) == 0 else 0
		var when_tag := ""
		if hb.get("variant", null) is Dictionary:
			when_tag = String((hb["variant"] as Dictionary).get("when", ""))
		res.append({
			"id": String(hb.get("id", "")),
			"hb": hb_k, "hbr": hbr, "hbw": hbw, "hbcos": hbcos,
			"hbf": int(hb.get("from", 0)), "hbt": int(hb.get("to", 0)),
			"off": int(hb.get("fwd", 0)),
			"raw": _scaled(int(hb.get("dmg", 0)), int(hb.get("dmg_scaling", 0)), dm, magia),
			"force": _stun(int(hb.get("stun", 0)), int(hb.get("stun_scaling", 0)), phys_f, sd, mag_f),
			"parry": int(hb.get("parryable", 1)),
			"unbl": 1 if int(hb.get("blockable", 1)) == 0 else 0,
			"gb": int(hb.get("guard_break", 0)),
			"ls": int(hb.get("lifesteal_pm", 0)) / 10,
			"kb": int(hb.get("knock_speed", 0)),
			"ground": int(hb.get("ground_only", 0)),
			"bleed": bleed,
			"when": when_tag,
		})
	return res

static func _compile_volleys(spawns: Array, boxes: Array, dm: float, magia: float, phys_f: float, sd: float, mag_f: float) -> Array:
	var hb_from_map := {}
	for b_var: Variant in boxes:
		if b_var is Dictionary:
			hb_from_map[String((b_var as Dictionary).get("id", ""))] = int((b_var as Dictionary).get("from", 0))
	var res: Array = []
	for sp_var: Variant in spawns:
		if not (sp_var is Dictionary):
			continue
		var sp: Dictionary = sp_var
		var sk := int(sp.get("type", -1))
		var has_vol := sp.has("volley") and sp["volley"] is Dictionary
		var paired_hb := String(sp.get("paired_hitbox", sp.get("paired_hb", "")))
		var has_pair := paired_hb != ""
		if sk != 2 and not has_vol and not has_pair:
			continue
		var vol: Dictionary = sp.get("volley", {}) if has_vol else {}
		var count := maxi(int(vol.get("count", int(sp.get("count", 1)))), 1)
		var interval := maxi(int(vol.get("interval", 0)), 0)
		var sp_spread_cdeg := int(sp.get("spread_mrh", 0)) * 36000 / 256000
		if sp_spread_cdeg == 0 and sp.has("spread"):
			sp_spread_cdeg = int(sp["spread"]) * 36000 / 256
		var spread_cdeg := int(vol.get("spread_cdeg", sp_spread_cdeg))
		var aim := int(vol.get("aim", 0))
		var offsets: Array = vol.get("offsets", []) if vol.get("offsets", []) is Array else []
		var paired_from := int(hb_from_map.get(paired_hb, -1)) if has_pair else -1
		var shape: Dictionary = sp.get("shape", {}) if sp.get("shape") is Dictionary else {}
		var rad := int(sp.get("radius", shape.get("r", 0)))
		if rad <= 0:
			rad = int(shape.get("outer", 400000))
		var sp_hb: Dictionary = sp.get("hitbox", {}) if sp.get("hitbox") is Dictionary else {}
		var sp_dmg := int(sp_hb.get("dmg", sp.get("dmg", 0)))
		var sp_dmg_sc := int(sp_hb.get("dmg_scaling", sp.get("dmg_scaling", 0)))
		var sp_stun := int(sp_hb.get("stun", sp.get("stun", 0)))
		var sp_stun_sc := int(sp_hb.get("stun_scaling", 0))
		res.append({
			"type": sk,
			"at": int(sp.get("at", 0)),
			"paired_from": paired_from,
			"count": count,
			"interval": interval,
			"spread_cdeg": spread_cdeg,
			"aim": aim,
			"offsets": offsets.duplicate(true),
			"fwd": int(sp.get("fwd", 1000000)),
			"right": int(sp.get("right", 0)),
			"spd": maxi(int(sp.get("speed", 400000)), 0),
			"range": maxi(int(sp.get("range", 12000000)), 0),
			"life": int(sp.get("life", 0)),
			"width": maxi(int(sp.get("width", 1000000)), 0),
			"warn": int(sp.get("warn", 24)),
			"r": maxi(rad, 300000),
			"raw": _scaled(sp_dmg, sp_dmg_sc, dm, magia),
			"force": _stun(sp_stun, sp_stun_sc, phys_f, sd, mag_f),
			"knock": int(sp.get("knock", 0)),
			"homing": int(sp.get("homing", sp.get("homing_mrh", 0))),
			"homing_t": int(sp.get("homing_t", 0)),
		})
	return res

# ---------------- ciclo de vida y hooks (SimAbilities / FightSim) ----------------

static func _clear_step_ext(s: PackedInt64Array, ext: int) -> void:
	s[ext + FightSim.EX_MV_EVAL] = 0
	s[ext + FightSim.EX_MV_OK] = 0
	s[ext + FightSim.EX_MV_SPD] = 0
	s[ext + FightSim.EX_MV_DIST] = 0
	s[ext + FightSim.EX_MV_TX] = 0
	s[ext + FightSim.EX_MV_TZ] = 0
	s[ext + FightSim.EX_MV_SCALE] = 0
	s[ext + FightSim.EX_MV_SEG] = 0
	s[ext + FightSim.EX_EXIT_ACT] = 0
	s[ext + FightSim.EX_EXIT_TICK] = 0
	s[ext + FightSim.EX_VOL_IDX] = 0
	s[ext + FightSim.EX_VOL_DIR] = 0
	s[ext + FightSim.EX_HB_USED] = 0
	s[ext + FightSim.EX_INTANG] = 0
	s[ext + FightSim.EX_NOTURN] = 0
	s[ext + FightSim.EX_STATUS_MASK] = 0
	s[ext + FightSim.EX_GUARD_ON] = 0
	s[ext + FightSim.EX_AI_ROLLED] = 0

static func on_start(s: PackedInt64Array, P: Array, i: int, slot: int, ab: Dictionary, own_cd: int) -> void:
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	_clear_step_ext(s, ext)
	s[ext + FightSim.EX_CHARGE_TIER] = 0
	s[ext + FightSim.EX_CHARGE_DMG] = 0
	s[ext + FightSim.EX_CHARGE_STUN] = 0
	s[ext + FightSim.EX_CHAIN_LINKS] = 0
	s[ext + FightSim.EX_COST_PAID] = 0
	s[ext + FightSim.EX_CHAIN_CD_DEF] = 0
	if int(ab.get("cd_end", 0)) != 0 and not AdminMode.enabled:
		if slot >= 0 and slot < 64:
			s[o + FightSim.BCD_BASE + slot] = 0
		s[o + FightSim.BOSS_CD] = 0
		s[ext + FightSim.EX_CHAIN_CD_DEF] = own_cd

static func on_end(s: PackedInt64Array, i: int, o: int, slot_prev: int, _interrupted: bool) -> void:
	var ext := FightSim.ext_of(i)
	_clear_step_ext(s, ext)
	s[ext + FightSim.EX_CHARGE_TIER] = 0
	s[ext + FightSim.EX_CHARGE_DMG] = 0
	s[ext + FightSim.EX_CHARGE_STUN] = 0
	s[ext + FightSim.EX_CHAIN_LINKS] = 0
	s[ext + FightSim.EX_COST_PAID] = 0
	var def_cd := int(s[ext + FightSim.EX_CHAIN_CD_DEF])
	s[ext + FightSim.EX_CHAIN_CD_DEF] = 0
	if def_cd > 0 and not AdminMode.enabled:
		if slot_prev >= 0 and slot_prev < 64:
			s[o + FightSim.BCD_BASE + slot_prev] = def_cd
		s[o + FightSim.BOSS_CD] = def_cd

static func on_control(s: PackedInt64Array, P: Array, i: int, inp: int, pressed: int) -> void:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return
	var step := _step_of(s, P, i)
	if step.is_empty():
		return
	var t := int(s[o + FightSim.AB_T])
	# combo_input_windows: acepta IN_BOSS o IN_BOSS_VAR con buffer_ticks
	if step.has("combo_win") and t > 0:
		var cws: Array = step["combo_win"]
		for cw_var: Variant in cws:
			if not (cw_var is Dictionary):
				continue
			var cw: Dictionary = cw_var
			var wf := int(cw.get("from", 0)) - int(cw.get("buffer", 6))
			var wt := maxi(int(cw.get("to", 0)), int(step.get("dur", 60))) if cws.size() == 1 else int(cw.get("to", 0))
			if (cws.size() == 1 and t <= wt) or (t >= wf and t <= wt):
				if (pressed & FightSim.IN_BOSS_VAR) != 0 and String(step.get("blab", "")) != "":
					s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_QUEUED) | SimAbilities.FL_VARIANT
				elif (pressed & FightSim.IN_BOSS) != 0 and s[o + FightSim.AB_SEL] == s[o + FightSim.AB_SLOT]:
					s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_VARIANT) | SimAbilities.FL_QUEUED
	# exit_windows: guarda la acción en el buffer (0..12 ticks antes de abrirse)
	if not step.has("exit_win"):
		return
	var buf := int(step.get("exit_buf", 0))
	var act := 0
	if (pressed & (FightSim.IN_BOSS | FightSim.IN_BOSS_VAR)) != 0:
		act = 4
	elif (pressed & FightSim.IN_ROLL) != 0:
		act = 2
	elif (pressed & FightSim.IN_ATK) != 0:
		act = 1
	elif (inp & FightSim.IN_MOVE) != 0:
		act = 3
	if act == 0:
		return
	var act_code := act - 1 # 0=attack, 1=roll, 2=move, 3=combo
	for ew_var: Variant in step["exit_win"]:
		if not (ew_var is Dictionary):
			continue
		var ew: Dictionary = ew_var
		if int(ew.get("action", -1)) != act_code:
			continue
		var wf := int(ew.get("from", 0))
		var wt := int(ew.get("to", 0))
		if t >= wf - buf and t < wt:
			var ext := FightSim.ext_of(i)
			s[ext + FightSim.EX_EXIT_ACT] = act
			s[ext + FightSim.EX_EXIT_TICK] = t
			return

static func check_phase_transition(s: PackedInt64Array, P: Array, i: int) -> void:
	if i < 0 or i >= P.size():
		return
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.ALIVE] == 0:
		return
	var ext := FightSim.ext_of(i)
	if s[ext + FightSim.EX_PT_DONE] != 0:
		return
	var boss: Array = P[i].get("boss", [])
	for slot in boss.size():
		var ab: Dictionary = boss[slot]
		if int(ab.get("type", -1)) != SimAbilities.T_CATALOG or not ab.has("pt"):
			continue
		var pt: Dictionary = ab["pt"]
		var thr := int(pt.get("threshold", 50))
		if s[o + FightSim.HP] * 100 > int(P[i].get("hp", 100000)) * thr and s[o + FightSim.PH2] == 0:
			continue
		s[ext + FightSim.EX_PT_DONE] = 1
		s[o + FightSim.PH2] = 1
		if s[o + FightSim.AB_SLOT] >= 0:
			SimAbilities.end_ability(s, o, false)
		s[o + FightSim.STUN] = 0
		s[o + FightSim.STAGGER_T] = 0
		s[o + FightSim.ATK_STATE] = FightSim.Atk.NONE
		s[o + FightSim.AB_LAST] = int(ab.get("code", slot))
		s[o + FightSim.AB_STARTS] += 1
		SimAbilities._start(s, P, i, slot)
		var pt_step := int(pt.get("step", 0))
		s[o + FightSim.AB_FIRED] = pt_step
		var steps: Array = ab.get("steps", [])
		var dur := int(steps[pt_step].get("dur", 60)) if pt_step >= 0 and pt_step < steps.size() else 60
		s[o + FightSim.INVULN] = maxi(s[o + FightSim.INVULN], dur)
		s[ext + FightSim.EX_INTANG] = 1
		return

static func counter_window_pm(s: PackedInt64Array, P: Array, d: int) -> Array:
	var o := d * FightSim.F_FIELDS
	if not _alive(s, o):
		return [1000, 1000]
	var step := _step_of(s, P, d)
	if step.is_empty() or not step.has("cwin"):
		return [1000, 1000]
	var cw: Dictionary = step["cwin"]
	var t := maxi(_t(s, o), 0)
	if t >= int(cw.get("from", 0)) and t < int(cw.get("to", 0)):
		return [int(cw.get("dmg_pct", 100)) * 10, int(cw.get("stun_pct", 100)) * 10]
	return [1000, 1000]

static func _active_guard_win(s: PackedInt64Array, P: Array, d: int) -> Dictionary:
	var o := d * FightSim.F_FIELDS
	if not _alive(s, o):
		return {}
	var step := _step_of(s, P, d)
	if step.is_empty() or not step.has("gwin"):
		return {}
	var t := maxi(_t(s, o), 0)
	for gw_var: Variant in step["gwin"]:
		if gw_var is Dictionary:
			var gw: Dictionary = gw_var
			if t >= int(gw.get("from", 0)) and t < int(gw.get("to", 0)):
				return gw
	return {}

static func guard_stam_pct(s: PackedInt64Array, P: Array, d: int) -> int:
	var gw := _active_guard_win(s, P, d)
	if gw.is_empty():
		return 100
	return int(gw.get("stam_pct", 50))

static func on_guard_hit(s: PackedInt64Array, P: Array, att: int, d: int, kind: int, raw: int, mult: int, ipm: int, st: Array, block_cost: int) -> int:
	var a := att * FightSim.F_FIELDS
	var b := d * FightSim.F_FIELDS
	var gw := _active_guard_win(s, P, d)
	if gw.is_empty():
		return 0
	var is_gb := kind == 3
	if not is_gb and s[a + FightSim.AB_SLOT] >= 0 and (s[a + FightSim.AB_FL] & SimAbilities.FL_CATALOG) != 0:
		var a_step := _step_of(s, P, att)
		if a_step.has("hbs"):
			for hb_d: Dictionary in a_step["hbs"]:
				if int(hb_d.get("gb", 0)) != 0:
					is_gb = true
	if is_gb and int(gw.get("gb_int", 1)) != 0:
		s[b + FightSim.GUARD_BREAKS] += 1
		SimAbilities.end_ability(s, b, true)
		FightSim._apply_stun(s, b, int(P[d].get("guard_break_t", 60)), P)
		return 1
	s[b + FightSim.BLOCKS] += 1
	var bpct := int(gw.get("block_pct", 80))
	var pass_pm := clampi((100 - bpct) * 10, 0, 1000)
	var dmg := raw * mult / 1000 * pass_pm / 1000 * ipm / 1000
	if dmg > 0:
		FightSim._damage(s, a, b, dmg)
	FightSim._hit_status_ext(s, P, att, kind, st, FightSim.BLOCK_STATUS_PM)
	if block_cost > 0:
		FightSim._spend(s, P, d, block_cost * pass_pm / 1000)
	FightSim._meter(s, P, d, 3000)
	return 2

# ---------------- consulta (con P, durante el golpe) ----------------

static func _alive(s: PackedInt64Array, o: int) -> bool:
	return s[o + FightSim.AB_SLOT] >= 0 and (s[o + FightSim.AB_FL] & SimAbilities.FL_CATALOG) != 0

static func _step_of(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	var o := i * FightSim.F_FIELDS
	if i >= P.size():
		return {}
	var boss: Array = P[i].get("boss", [])
	var slot: int = s[o + FightSim.AB_SLOT]
	if slot < 0 or slot >= boss.size():
		return {}
	var ab: Dictionary = boss[slot]
	var steps: Array = ab.get("steps", [])
	var si: int = s[o + FightSim.AB_FIRED]
	if si < 0 or si >= steps.size():
		return {}
	return steps[si]

static func _t(s: PackedInt64Array, o: int) -> int:
	return s[o + FightSim.AB_T] - 1

static func incoming_pm(s: PackedInt64Array, P: Array, d: int) -> int:
	var o := d * FightSim.F_FIELDS
	var pm := 1000
	var ext := FightSim.ext_of(d)
	if s[ext + FightSim.EX_BUFF_T] > 0 and s[ext + FightSim.EX_BUFF_KIND] == 2:
		pm = pm * clampi(1000 - s[ext + FightSim.EX_BUFF_VAL], 100, 2000) / 1000
	if not _alive(s, o):
		return pm
	var step := _step_of(s, P, d)
	if step.is_empty() or int(step.get("inv0", -1)) < 0:
		return pm
	var t := _t(s, o)
	if t >= int(step["inv0"]) and t < int(step["inv1"]):
		return pm * int(step["invpm"]) / 1000
	return pm

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
	var bonus := 0
	var ext := FightSim.ext_of(i)
	if s[ext + FightSim.EX_BUFF_T] > 0 and s[ext + FightSim.EX_BUFF_KIND] == 3:
		bonus = int(s[ext + FightSim.EX_BUFF_VAL])
	var step := _step_of(s, P, i)
	if step.is_empty():
		return bonus
	var t := _t(s, o)
	if int(step["armor"]) == 1 and t >= int(step["af"]) and t < int(step["at"]):
		return int(step["poise"]) + bonus
	return bonus

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
	var win_end := maxi(int(step.get("br1", 0)), int(step.get("dur", 60)))
	return t >= 0 and t < win_end

static func can_exit_combo(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return true
	var step := _step_of(s, P, i)
	if step.is_empty():
		return true
	var t := _t(s, o)
	if step.has("exit_win"):
		for ew_var: Variant in step["exit_win"]:
			if ew_var is Dictionary:
				var ew: Dictionary = ew_var
				var wf := int(ew.get("from", 0))
				var wt := int(ew.get("to", 0))
				if t >= wf and t < wt:
					return true
		return false
	var min_t := int(step.get("w", 0)) + int(step.get("a", 0))
	return t >= min_t

static func alt_label(s: PackedInt64Array, P: Array, i: int) -> String:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return ""
	return String(_step_of(s, P, i).get("blab", ""))

static func combo_info(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return {"can_combo": false, "active": false, "progress": 0.0, "queued": false, "label": ""}
	var step := _step_of(s, P, i)
	if step.is_empty() or (int(step.get("br0", -1)) < 0 and not step.has("combo_win")):
		return {"can_combo": false, "active": false, "progress": 0.0, "queued": false, "label": ""}
	var dur := maxf(float(maxi(int(step.get("br1", 0)), int(step.get("dur", 60)))), 1.0)
	var t := _t(s, o)
	var active := t >= 0 and t < int(dur)
	var total_ch: int = int(step.get("total_chain", 1))
	var c_idx: int = int(step.get("chain_idx", 0))
	var fl := s[o + FightSim.AB_FL]
	var queued := (fl & (SimAbilities.FL_QUEUED | SimAbilities.FL_VARIANT)) != 0
	var step_count: int = (c_idx + 1) + (1 if queued else 0)
	var prog: float = 1.0
	if total_ch > 1:
		prog = clampf(float(step_count) / float(total_ch - 1), 0.0, 1.0)
	return {
		"can_combo": true,
		"active": active,
		"progress": prog,
		"queued": queued,
		"label": String(step.get("blab", ""))
	}

static func latch(s: PackedInt64Array, P: Array, i: int, alt: bool) -> bool:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return false
	var step := _step_of(s, P, i)
	if step.is_empty():
		return false
	var t := _t(s, o)
	if t < 0:
		return false
	if step.has("combo_win"):
		var cws: Array = step["combo_win"]
		for cw_var: Variant in cws:
			if not (cw_var is Dictionary):
				continue
			var cw: Dictionary = cw_var
			var wf := int(cw.get("from", 0)) - int(cw.get("buffer", 6))
			var wt := maxi(int(cw.get("to", 0)), int(step.get("dur", 60))) if cws.size() == 1 else int(cw.get("to", 0))
			if (cws.size() == 1 and t < wt) or (t >= wf and t <= wt):
				if alt and String(step.get("blab", "")) != "":
					s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_QUEUED) | SimAbilities.FL_VARIANT
				else:
					s[o + FightSim.AB_FL] = (s[o + FightSim.AB_FL] & ~SimAbilities.FL_VARIANT) | SimAbilities.FL_QUEUED
				return true
	if int(step.get("br0", -1)) < 0:
		return false
	if alt and String(step.get("blab", "")) == "":
		return false
	var win_end := maxi(int(step.get("br1", 0)), int(step.get("dur", 60)))
	if t < 0 or t >= win_end:
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
		_advance(s, P, i, ab, step, steps)
		return
	var t := _t(s, o)
	_pay_deferred(s, P, i, ab, si, t)
	_self_windows(s, i, step, t)
	if _charge_tick(s, P, i, ab, step, steps, t):
		return
	if _exit_tick(s, P, i, ab, step, steps, t):
		return
	_track(s, i, step, t)
	_horiz(s, P, i, step, t)
	_vert(s, o, step, t)
	_hit(s, P, i, step, t)
	_spawn(s, P, i, step, t)
	_spawn_marks(s, P, i, step, t)
	_spawn_waves(s, P, i, step, t)
	_spawn_volleys(s, P, i, step, t)
	_self_status_tick(s, P, i, step, t)

static func _pay_deferred(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, si: int, t: int) -> void:
	if not ab.has("cost_at"):
		return
	var cost_at := int(ab["cost_at"])
	if cost_at <= 0 or si != int(ab.get("entry", 0)):
		return
	var ext := FightSim.ext_of(i)
	if s[ext + FightSim.EX_COST_PAID] != 0 or t < cost_at:
		return
	s[ext + FightSim.EX_COST_PAID] = 1
	SimAbilities._pay(s, P, i, ab)

static func _self_windows(s: PackedInt64Array, i: int, step: Dictionary, t: int) -> void:
	var ext := FightSim.ext_of(i)
	var intang := 0
	var noturn := 0
	var guard := 0
	if step.has("self_win"):
		for sw_var: Variant in step["self_win"]:
			if not (sw_var is Dictionary):
				continue
			var sw: Dictionary = sw_var
			if t >= int(sw.get("from", 0)) and t < int(sw.get("to", 0)):
				var wt := int(sw.get("type", -1))
				if wt == 0:
					intang = 1
				elif wt == 1:
					noturn = 1
	if step.has("mvs"):
		for seg_idx in (step["mvs"] as Array).size():
			var seg: Dictionary = step["mvs"][seg_idx]
			if int(seg.get("mv", 0)) == 7 and t >= int(seg["mv0"]) and t < int(seg["mv1"]):
				if (s[ext + FightSim.EX_MV_EVAL] & (1 << seg_idx)) == 0 or (s[ext + FightSim.EX_MV_OK] & (1 << seg_idx)) != 0:
					intang = 1
	if step.has("gwin"):
		for gw_var: Variant in step["gwin"]:
			if gw_var is Dictionary:
				var gw: Dictionary = gw_var
				if t >= int(gw.get("from", 0)) and t < int(gw.get("to", 0)):
					guard = 1
	if s[ext + FightSim.EX_INTANG] != intang:
		s[ext + FightSim.EX_INTANG] = intang
	if s[ext + FightSim.EX_NOTURN] != noturn:
		s[ext + FightSim.EX_NOTURN] = noturn
	if s[ext + FightSim.EX_GUARD_ON] != guard:
		s[ext + FightSim.EX_GUARD_ON] = guard

static func _charge_tick(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, step: Dictionary, steps: Array, t: int) -> bool:
	if not step.has("charge"):
		return false
	var ch: Dictionary = step["charge"]
	var c_from := int(ch.get("from", 0))
	var c_max := int(ch.get("max", ch.get("max_ticks", 0)))
	if t < c_from:
		return false
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	var ct := t - c_from
	var tiers: Array = ch.get("tiers", [])
	for ti in tiers.size():
		var td: Dictionary = tiers[ti]
		if ct >= int(td.get("at", 0)):
			s[ext + FightSim.EX_CHARGE_TIER] = ti + 1
			s[ext + FightSim.EX_CHARGE_DMG] = int(td.get("dmg_pct", 100)) * 10
			s[ext + FightSim.EX_CHARGE_STUN] = int(td.get("stun_pct", 100)) * 10
	var held := (s[o + FightSim.PREV_IN] & (FightSim.IN_BOSS | FightSim.IN_ATK)) != 0
	if ct >= c_max or (ct > 0 and not held):
		var rel_step := int(ch.get("release_step", -1))
		var tier := s[ext + FightSim.EX_CHARGE_TIER]
		var cdmg := s[ext + FightSim.EX_CHARGE_DMG]
		var cstun := s[ext + FightSim.EX_CHARGE_STUN]
		_transition_to(s, i, ab, steps, rel_step)
		s[ext + FightSim.EX_CHARGE_TIER] = tier
		s[ext + FightSim.EX_CHARGE_DMG] = cdmg
		s[ext + FightSim.EX_CHARGE_STUN] = cstun
		return true
	return false

static func _exit_tick(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, step: Dictionary, steps: Array, t: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	if step.has("combo_win"):
		var fl: int = s[o + FightSim.AB_FL]
		if (fl & (SimAbilities.FL_QUEUED | SimAbilities.FL_VARIANT)) != 0:
			for cw_var: Variant in step["combo_win"]:
				if not (cw_var is Dictionary):
					continue
				var cw: Dictionary = cw_var
				var c_mode := int(cw.get("commit", 0))
				var c_target: int = int(cw.get("step", -1))
				if c_mode == 1 and t >= int(cw.get("from", 0)) and t <= int(cw.get("to", 0)):
					if c_target >= 0:
						_transition_to(s, i, ab, steps, c_target)
					else:
						_advance(s, P, i, ab, step, steps)
					return true
				elif (c_mode == 0 or c_mode == 2) and t >= int(cw.get("to", 0)):
					if c_target >= 0:
						_transition_to(s, i, ab, steps, c_target)
					else:
						_advance(s, P, i, ab, step, steps)
					return true
	if not step.has("exit_win"):
		return false
	var buf := int(step.get("exit_buf", 0))
	var buffered_act := int(s[ext + FightSim.EX_EXIT_ACT])
	var buffered_t := int(s[ext + FightSim.EX_EXIT_TICK])
	if buffered_act == 0 and (s[o + FightSim.PREV_IN] & FightSim.IN_MOVE) != 0:
		for ew_m: Variant in step["exit_win"]:
			if ew_m is Dictionary and int((ew_m as Dictionary).get("action", -1)) == 2:
				var mf := int((ew_m as Dictionary).get("from", 0))
				var mt := int((ew_m as Dictionary).get("to", 0))
				if t >= mf and t < mt:
					buffered_act = 3
					buffered_t = t
					break
	if buffered_act == 0:
		return false
	var act_code := buffered_act - 1
	for ew_var: Variant in step["exit_win"]:
		if not (ew_var is Dictionary):
			continue
		var ew: Dictionary = ew_var
		if int(ew.get("action", -1)) != act_code:
			continue
		var wf := int(ew.get("from", 0))
		var wt := int(ew.get("to", 0))
		if t >= wf and t < wt and buffered_t >= wf - buf:
			s[ext + FightSim.EX_EXIT_ACT] = 0
			s[ext + FightSim.EX_EXIT_TICK] = 0
			match act_code:
				0: # attack
					SimAbilities.end_ability(s, o, false)
					FightSim._request_attack(s, P, i, false)
					return true
				1: # roll
					SimAbilities.end_ability(s, o, false)
					FightSim._dash(s, P, i)
					return true
				2: # move
					SimAbilities.end_ability(s, o, false)
					return true
				3: # combo
					s[o + FightSim.AB_FL] |= SimAbilities.FL_QUEUED
					if step.has("cancel_step") and int(step["cancel_step"]) >= 0:
						_transition_to(s, i, ab, steps, int(step["cancel_step"]))
					else:
						_advance(s, P, i, ab, step, steps)
					return true
	return false

static func _advance(s: PackedInt64Array, P: Array, i: int, ab: Dictionary, step: Dictionary, steps: Array) -> void:
	var o := i * FightSim.F_FIELDS
	var fl: int = s[o + FightSim.AB_FL]
	var nxt := int(step["nxt"])
	if (fl & SimAbilities.FL_LANDED) != 0 and step.has("nxt_hit"):
		nxt = int(step["nxt_hit"])
	elif (fl & SimAbilities.FL_COUNTERED) != 0 and step.has("nxt_block"):
		nxt = int(step["nxt_block"])
	elif (fl & (SimAbilities.FL_LANDED | SimAbilities.FL_COUNTERED)) == 0 and step.has("nxt_whiff"):
		nxt = int(step["nxt_whiff"])
	if int(step["br0"]) >= 0 or step.has("combo_win"):
		if (fl & SimAbilities.FL_VARIANT) != 0 and int(step["bra"]) >= 0:
			nxt = int(step["bra"])
		elif (fl & SimAbilities.FL_QUEUED) != 0:
			if int(step["brs"]) >= 0:
				nxt = int(step["brs"])
			elif step.has("cancel_step"):
				nxt = int(step["cancel_step"])
			elif step.has("combo_win") and not (step["combo_win"] as Array).is_empty():
				var first_cw: Dictionary = (step["combo_win"] as Array)[0]
				if int(first_cw.get("step", -1)) >= 0:
					nxt = int(first_cw["step"])
		elif int(step["br0"]) >= 0:
			nxt = int(step["brd"])
	_transition_to(s, i, ab, steps, nxt)

static func _transition_to(s: PackedInt64Array, i: int, ab: Dictionary, steps: Array, nxt: int) -> void:
	var o := i * FightSim.F_FIELDS
	if nxt < 0 or nxt >= steps.size():
		SimAbilities.end_ability(s, o, false)
		return
	var ext := FightSim.ext_of(i)
	var next_step: Dictionary = steps[nxt]
	if int(next_step.get("crole", -1)) == 1:
		s[ext + FightSim.EX_CHAIN_LINKS] += 1
		if ab.has("chain"):
			var max_l := int((ab["chain"] as Dictionary).get("max_links", 0))
			if max_l > 0 and s[ext + FightSim.EX_CHAIN_LINKS] > max_l:
				SimAbilities.end_ability(s, o, false)
				return
	var keep_links := s[ext + FightSim.EX_CHAIN_LINKS]
	var keep_cd_def := s[ext + FightSim.EX_CHAIN_CD_DEF]
	var keep_paid := s[ext + FightSim.EX_COST_PAID]
	_clear_step_ext(s, ext)
	s[ext + FightSim.EX_CHAIN_LINKS] = keep_links
	s[ext + FightSim.EX_CHAIN_CD_DEF] = keep_cd_def
	s[ext + FightSim.EX_COST_PAID] = keep_paid
	s[ext + FightSim.EX_CHARGE_TIER] = 0
	s[ext + FightSim.EX_CHARGE_DMG] = 0
	s[ext + FightSim.EX_CHARGE_STUN] = 0
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
	var ext := FightSim.ext_of(i)
	var locked := (s[o + FightSim.AB_FL] & SimAbilities.FL_LOCKED) != 0
	if not locked and s[b + FightSim.ALIVE] != 0:
		s[o + FightSim.AB_X] = s[b + FightSim.X]
		s[o + FightSim.AB_Z] = s[b + FightSim.Z]
	if t >= int(step["lock"]) and not locked:
		s[o + FightSim.AB_FL] |= SimAbilities.FL_LOCKED
		locked = true
		if step.has("volleys"):
			s[ext + FightSim.EX_VOL_DIR] = SimAbilities._tdir(s, i)
	if step.has("volleys") and t == 0 and int(step["lock"]) > 0:
		s[ext + FightSim.EX_VOL_DIR] = SimAbilities._tdir(s, i)
	if s[ext + FightSim.EX_NOTURN] != 0:
		return
	var rate := -1
	if step.has("tr_win"):
		for w_var: Variant in step["tr_win"]:
			if w_var is Dictionary:
				var w: Dictionary = w_var
				if t >= int(w["from"]) and t < int(w["to"]):
					rate = int(w["turn"])
					break
	if rate < 0:
		rate = int(step["trk2"]) if locked else int(step["trk"])
	if rate <= 0 or s[b + FightSim.ALIVE] == 0:
		return
	var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
	var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
	if FxMath.length(dx, dz) <= 100000:
		return
	s[o + FightSim.FACE] = FxMath.turn_toward(s[o + FightSim.FACE], FxMath.dir_of(dx, dz, s[o + FightSim.FACE]), rate)

static func _eval_mv_seg(s: PackedInt64Array, i: int, step: Dictionary, seg: Dictionary, seg_idx: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var ext := FightSim.ext_of(i)
	s[ext + FightSim.EX_MV_EVAL] |= (1 << seg_idx)
	var dist := FightSim._dist_to_opp(s, i) if s[b + FightSim.ALIVE] != 0 else 0
	var rmin := int(seg.get("rmin", -1))
	var rmax := int(seg.get("rmax", -1))
	var fit := int(seg.get("fit", 0))
	var ref_d := int(seg.get("ref_d", -1))
	var is_chain := step.has("crole") or step.has("combo_win")
	if fit == 0 and ref_d <= 0 and not is_chain:
		if (rmin >= 0 and dist < rmin) or (rmax >= 0 and dist > rmax):
			s[ext + FightSim.EX_MV_OK] &= ~(1 << seg_idx)
			return
	s[ext + FightSim.EX_MV_OK] |= (1 << seg_idx)
	var stop := int(seg.get("stop", 0))
	var ang_cdeg := int(seg.get("ang_cdeg", 0))
	var bx: int = s[b + FightSim.X] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.AB_X]
	var bz: int = s[b + FightSim.Z] if s[b + FightSim.ALIVE] != 0 else s[o + FightSim.AB_Z]
	var ax: int = s[o + FightSim.X] - bx
	var az: int = s[o + FightSim.Z] - bz
	var dir_ra := FxMath.dir_of(ax, az, (s[o + FightSim.FACE] + 128) & 255)
	var arr_dir := dir_ra
	if ang_cdeg != 0:
		var ang_h := int(round(float(ang_cdeg) * 256.0 / 36000.0))
		var d_pos := (dir_ra + ang_h) & 255
		var d_neg := (dir_ra - ang_h) & 255
		var tx_pos: int = bx + FxMath.COS[d_pos] * maxi(stop, 1000000) / FxMath.ONE
		var tz_pos: int = bz + FxMath.SIN[d_pos] * maxi(stop, 1000000) / FxMath.ONE
		var tx_neg: int = bx + FxMath.COS[d_neg] * maxi(stop, 1000000) / FxMath.ONE
		var tz_neg: int = bz + FxMath.SIN[d_neg] * maxi(stop, 1000000) / FxMath.ONE
		var l_pos := FxMath.length(tx_pos - s[o + FightSim.X], tz_pos - s[o + FightSim.Z])
		var l_neg := FxMath.length(tx_neg - s[o + FightSim.X], tz_neg - s[o + FightSim.Z])
		arr_dir = d_neg if l_neg < l_pos else d_pos
	var tx: int = bx + FxMath.COS[arr_dir] * stop / FxMath.ONE
	var tz: int = bz + FxMath.SIN[arr_dir] * stop / FxMath.ONE
	s[ext + FightSim.EX_MV_TX] = tx
	s[ext + FightSim.EX_MV_TZ] = tz
	var eff_dist := FxMath.length(tx - s[o + FightSim.X], tz - s[o + FightSim.Z])
	if rmin >= 0:
		eff_dist = maxi(eff_dist, rmin)
	if rmax >= 0:
		eff_dist = mini(eff_dist, rmax)
	var max_raw := int(seg.get("max_raw", 0))
	if max_raw > 0:
		eff_dist = mini(eff_dist, max_raw)
	var span := maxi(int(seg["mv1"]) - int(seg["mv0"]), 1)
	if fit != 0:
		s[ext + FightSim.EX_MV_SPD] = eff_dist / span
	else:
		s[ext + FightSim.EX_MV_SPD] = int(seg["spd"])
	if ref_d > 0:
		s[ext + FightSim.EX_MV_SCALE] = eff_dist * 1000 / ref_d
	else:
		s[ext + FightSim.EX_MV_SCALE] = 1000

static func _horiz(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if step.has("mvs"):
		_horiz_mvs(s, P, i, step, t)
		return
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
	if mv == 6:
		dx = s[o + FightSim.X] - s[b + FightSim.X]
		dz = s[o + FightSim.Z] - s[b + FightSim.Z]
	elif int(step["mode"]) == 1 or mv == 3:
		dx = s[o + FightSim.AB_X] - s[o + FightSim.X]
		dz = s[o + FightSim.AB_Z] - s[o + FightSim.Z]
	else:
		dx = s[b + FightSim.X] - s[o + FightSim.X]
		dz = s[b + FightSim.Z] - s[o + FightSim.Z]
	var dist := FxMath.length(dx, dz)
	var stop: int = int(step["stop"])
	if mv != 3 and mv != 6 and stop > 0 and dist <= stop:
		return
	var f: int = s[o + FightSim.FACE]
	if mv == 6 and dist > 100000:
		f = FxMath.dir_of(dx, dz, f)
	elif (int(step["mode"]) == 1 or mv == 3) and dist > 100000:
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

static func _horiz_mvs(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	var ext := FightSim.ext_of(i)
	var mvs: Array = step["mvs"]
	var lock_t := int(step["lock"])
	for seg_idx in mvs.size():
		var seg: Dictionary = mvs[seg_idx]
		var gfrom := int(seg["gfrom"])
		var gto := int(seg["gto"])
		var eval_t := lock_t if (lock_t >= gfrom and lock_t <= gto) else gfrom
		var mv0 := int(seg["mv0"])
		var mv1 := int(seg["mv1"])
		if (t == eval_t or t == mv0) and (s[ext + FightSim.EX_MV_EVAL] & (1 << seg_idx)) == 0:
			_eval_mv_seg(s, i, step, seg, seg_idx)
		if (s[ext + FightSim.EX_MV_OK] & (1 << seg_idx)) == 0:
			continue
		var mv := int(seg["mv"])
		if mv == 7: # blink_to_target
			if t >= mv0 and t < mv1:
				s[o + FightSim.AB_FL] |= SimAbilities.FL_VANISHED
				s[ext + FightSim.EX_INTANG] = 1
			if t == mv1 - 1:
				s[o + FightSim.AB_FL] &= ~SimAbilities.FL_VANISHED
				s[o + FightSim.X] = s[ext + FightSim.EX_MV_TX]
				s[o + FightSim.Z] = s[ext + FightSim.EX_MV_TZ]
				SimAbilities.clamp_world(s, P, o)
				s[o + FightSim.FACE] = SimAbilities._tdir(s, i)
			continue
		if mv == 0 or t < mv0 or t >= mv1:
			continue
		if s[ext + FightSim.EX_MV_SEG] != seg_idx + 1:
			s[ext + FightSim.EX_MV_SEG] = seg_idx + 1
			s[ext + FightSim.EX_MV_DIST] = 0
		var fit := int(seg.get("fit", 0)) != 0
		var maxd: int = int(seg["max_raw"]) if fit or int(seg.get("ref_d", -1)) > 0 else int(seg["maxd"])
		if maxd > 0 and s[ext + FightSim.EX_MV_DIST] >= maxd:
			return
		var use_locked_pt := fit or int(seg.get("ang_cdeg", 0)) != 0 or int(seg["mode"]) == 1 or mv == 3
		var dx: int
		var dz: int
		if mv == 6:
			dx = s[o + FightSim.X] - s[b + FightSim.X]
			dz = s[o + FightSim.Z] - s[b + FightSim.Z]
		elif use_locked_pt:
			dx = s[ext + FightSim.EX_MV_TX] - s[o + FightSim.X]
			dz = s[ext + FightSim.EX_MV_TZ] - s[o + FightSim.Z]
		else:
			dx = s[b + FightSim.X] - s[o + FightSim.X]
			dz = s[b + FightSim.Z] - s[o + FightSim.Z]
		var dist := FxMath.length(dx, dz)
		var stop: int = 0 if (fit or int(seg.get("ang_cdeg", 0)) != 0) else int(seg["stop"])
		if mv != 3 and mv != 6 and stop > 0 and dist <= stop:
			return
		var f: int = s[o + FightSim.FACE]
		if dist > 10000:
			f = FxMath.dir_of(dx, dz, f)
			if mv != 6 and s[ext + FightSim.EX_NOTURN] == 0:
				s[o + FightSim.FACE] = f
		var spd: int = s[ext + FightSim.EX_MV_SPD] if fit else int(seg["spd"])
		if not fit and int(seg.get("ref_d", -1)) > 0 and s[ext + FightSim.EX_MV_SCALE] > 0:
			spd = spd * s[ext + FightSim.EX_MV_SCALE] / 1000
		for dsw_var: Variant in seg.get("dscale", []):
			if dsw_var is Dictionary:
				var dsw: Dictionary = dsw_var
				if t >= int(dsw.get("from", 0)) and t < int(dsw.get("to", 0)):
					spd = spd * int(dsw.get("pct", 100)) / 100
					break
		if maxd > 0:
			spd = mini(spd, maxd - s[ext + FightSim.EX_MV_DIST])
		if fit or int(seg.get("ang_cdeg", 0)) != 0:
			spd = mini(spd, dist)
		elif stop > 0:
			spd = mini(spd, maxi(dist - stop, 0))
		if spd <= 0:
			return
		s[o + FightSim.AB_VX] = FxMath.COS[f] * spd / FxMath.ONE
		s[o + FightSim.AB_VZ] = FxMath.SIN[f] * spd / FxMath.ONE
		s[ext + FightSim.EX_MV_DIST] += spd
		s[o + FightSim.AB_TICK] += spd
		return

## Impulso vertical. La gravedad del tick hace el arco; height_m solo fija la fuerza.
static func _impulse(s: PackedInt64Array, o: int, h: int) -> void:
	if h <= 0:
		return
	s[o + FightSim.AIR] = 1
	s[o + FightSim.AIR_T] = 0
	s[o + FightSim.FY] = 0
	s[o + FightSim.FVY] = FxMath.isqrt(2 * FightSim.GRAVITY_T * h)

static func _set_fy(s: PackedInt64Array, o: int, h: int) -> void:
	if s[o + FightSim.AIR] == 0:
		s[o + FightSim.AIR] = 1
		s[o + FightSim.AIR_T] = 0
		s[o + FightSim.FVY] = h - s[o + FightSim.FY]
	else:
		s[o + FightSim.FVY] = h - s[o + FightSim.FY] + FightSim.GRAVITY_T

static func _vert(s: PackedInt64Array, o: int, step: Dictionary, t: int) -> void:
	var mv := int(step["mv"])
	var mv0 := int(step["mv0"])
	var mv1 := int(step["mv1"])
	var height := int(step["height"])
	var imp := int(step.get("imp", 0))
	if step.has("mvs"):
		var found := false
		for seg: Dictionary in step["mvs"]:
			var smv := int(seg["mv"])
			if (smv == 2 or smv == 3) and t >= int(seg["mv0"]) and t < int(seg["mv1"]):
				mv = smv; mv0 = int(seg["mv0"]); mv1 = int(seg["mv1"])
				height = int(seg["height"]); imp = int(seg.get("imp", 0))
				found = true
				break
		if not found:
			return
	elif (mv != 2 and mv != 3) or t < mv0 or t >= mv1:
		return
	var n: int = mv1 - mv0
	if n <= 0:
		return
	var u: int = t - mv0
	if mv == 2:
		if imp != 0:
			if u == 0:
				_impulse(s, o, height)
			return
		var h: int = height * (2 * u + 1) * (2 * n - 2 * u - 1) / (n * n)
		_set_fy(s, o, h)
		return
	if u == 0:
		s[o + FightSim.AB_FX] = maxi(s[o + FightSim.FY], 1)
	var h2: int = int(s[o + FightSim.AB_FX]) * (n - u - 1) / n
	_set_fy(s, o, h2)

static func _variant_active(s: PackedInt64Array, P: Array, i: int, when_tag: String) -> bool:
	if when_tag == "":
		return true
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	match when_tag:
		"phase1": return s[o + FightSim.PH2] == 0
		"phase2": return s[o + FightSim.PH2] != 0
		"rage": return s[o + FightSim.RAGE_T] > 0 or (s[ext + FightSim.EX_BUFF_T] > 0 and s[ext + FightSim.EX_BUFF_KIND] == 6)
		"buff": return s[ext + FightSim.EX_BUFF_T] > 0
		"shield": return s[o + FightSim.AB_IMM] != 0 or s[o + FightSim.SKIN_T] > 0
		"grounded": return s[o + FightSim.AIR] == 0
		"airborne": return s[o + FightSim.AIR] != 0
		"full_hp": return s[o + FightSim.HP] >= int(P[i].get("hp", 100000))
		"low_hp": return s[o + FightSim.HP] * 1000 < int(P[i].get("hp", 100000)) * 400
	return false

static func _hit(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if step.has("hbs"):
		_hit_multi(s, P, i, step, t)
		return
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
	var ext := FightSim.ext_of(i)
	var before: int = s[o + FightSim.DMG_DEALT]
	var kind := 0
	var parry := int(step["parry"]) != 0
	var st: Array = [BLEED_BUILD, 0, 0] if int(step["bleed"]) != 0 else []
	var base_raw := int(step["raw"])
	var base_force := int(step["force"])
	if s[ext + FightSim.EX_CHARGE_DMG] > 0:
		base_raw = base_raw * s[ext + FightSim.EX_CHARGE_DMG] / 1000
	if s[ext + FightSim.EX_CHARGE_STUN] > 0:
		base_force = base_force * s[ext + FightSim.EX_CHARGE_STUN] / 1000
	var raw := SimAbilities.raw_live(s, P, i, base_raw)
	var res := FightSim._take_hit(s, P, i, kind, raw, 0, base_force, 1000, 1000, 0, -1, st, false, parry)
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

static func _hit_multi(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	var o := i * FightSim.F_FIELDS
	var b := FightSim._opp(i)
	if s[b + FightSim.ALIVE] == 0:
		return
	var ext := FightSim.ext_of(i)
	var ta := t - int(step["w"])
	var hbs: Array = step["hbs"]
	for hb_idx in hbs.size():
		if (s[ext + FightSim.EX_HB_USED] & (1 << hb_idx)) != 0:
			continue
		var hb_d: Dictionary = hbs[hb_idx]
		var hbf := int(hb_d["hbf"])
		var hbt := int(hb_d["hbt"])
		if ta < hbf or ta >= hbt:
			continue
		if not _variant_active(s, P, i, String(hb_d.get("when", ""))):
			if ta == hbf:
				s[ext + FightSim.EX_HB_USED] |= (1 << hb_idx)
			continue
		if int(hb_d["ground"]) != 0 and (s[b + FightSim.AIR] != 0 or s[b + FightSim.FY] >= FightSim.GROUND_H):
			continue
		if not _overlaps(s, o, b, P[1 - i]["hit_radius"], hb_d):
			continue
		s[ext + FightSim.EX_HB_USED] |= (1 << hb_idx)
		for other_idx in hbs.size():
			if other_idx != hb_idx and int((hbs[other_idx] as Dictionary)["hbf"]) == hbf:
				s[ext + FightSim.EX_HB_USED] |= (1 << other_idx)
		var before: int = s[o + FightSim.DMG_DEALT]
		var parry := int(hb_d["parry"]) != 0
		var unbl := int(hb_d.get("unbl", 0)) != 0
		var st: Array = [BLEED_BUILD, 0, 0] if int(hb_d["bleed"]) != 0 else []
		var base_raw := int(hb_d["raw"])
		var base_force := int(hb_d["force"])
		if s[ext + FightSim.EX_CHARGE_DMG] > 0:
			base_raw = base_raw * s[ext + FightSim.EX_CHARGE_DMG] / 1000
		if s[ext + FightSim.EX_CHARGE_STUN] > 0:
			base_force = base_force * s[ext + FightSim.EX_CHARGE_STUN] / 1000
		var raw := SimAbilities.raw_live(s, P, i, base_raw)
		var res := FightSim._take_hit(s, P, i, 0, raw, 0, base_force, 1000, 1000, 0, -1, st, unbl, parry)
		if s[o + FightSim.AB_SLOT] < 0:
			return
		if res == 1:
			s[o + FightSim.AB_FL] |= SimAbilities.FL_LANDED
			s[o + FightSim.AB_HITS] += 1
			var kb: int = int(hb_d["kb"])
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
		var ls: int = int(hb_d["ls"])
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

static func _spawn_volleys(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if not step.has("volleys"):
		return
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	for v_var: Variant in step["volleys"]:
		if not (v_var is Dictionary):
			continue
		var v: Dictionary = v_var
		var base_at := int(v["at"])
		if int(v.get("paired_from", -1)) >= 0:
			base_at = int(step["w"]) + int(v["paired_from"])
		var count := int(v["count"])
		var interval := int(v["interval"])
		var offsets: Array = v.get("offsets", [])
		for k in count:
			var fire_t := base_at + k * interval
			if t != fire_t:
				continue
			if interval > 0 and s[ext + FightSim.EX_VOL_IDX] > k:
				continue
			s[ext + FightSim.EX_VOL_IDX] = k + 1
			var fwd := int(v["fwd"])
			var right := int(v["right"])
			if k < offsets.size() and offsets[k] is Array and (offsets[k] as Array).size() >= 2:
				fwd = int(offsets[k][0])
				right = int(offsets[k][1])
			var base_h: int = s[ext + FightSim.EX_VOL_DIR] if int(v["aim"]) == 0 else s[o + FightSim.FACE]
			var dir_h := base_h & 255
			var spread_cdeg := int(v.get("spread_cdeg", 0))
			if count > 1 and spread_cdeg > 0:
				var spread_h := int(round(float(spread_cdeg) * 256.0 / 36000.0))
				var off_h := -spread_h / 2 + k * spread_h / maxi(count - 1, 1)
				dir_h = (base_h + off_h) & 255
			var fx: int = FxMath.COS[base_h & 255]
			var fz: int = FxMath.SIN[base_h & 255]
			var ox: int = s[o + FightSim.X] + fx * fwd / FxMath.ONE + fz * right / FxMath.ONE
			var oz: int = s[o + FightSim.Z] + fz * fwd / FxMath.ONE - fx * right / FxMath.ONE
			var raw := SimAbilities.raw_live(s, P, i, int(v["raw"]))
			var vtype := int(v["type"])
			if vtype == 2: # projectile
				var life := int(v.get("life", 0))
				if life <= 0:
					life = maxi(int(v["range"]) / maxi(int(v["spd"]), 1), 15)
				var home_rate := _headings(int(v.get("homing", 0)))
				var home_t := int(v.get("homing_t", 0))
				if home_t <= 0 and home_rate > 0:
					home_t = life
				FightSim.spawn_proj(s, i, 1, ox, oz, FightSim.HIT_CENTER_Y + 200000, dir_h, int(v["spd"]), life, int(v["r"]), raw, int(v["force"]), -1, 0, home_t, home_rate, 0, false)
			elif vtype == 1: # ground_wave
				SimAbilities.spawn_hz(s, i, 2, ox, oz, int(v["warn"]), 0, raw, int(v["force"]), int(v["knock"]), 0, dir_h, int(v["spd"]), int(v["range"]), int(v["width"]))
			else: # ground_mark
				SimAbilities.spawn_hz(s, i, 1, ox, oz, int(v["warn"]), int(v["r"]), raw, int(v["force"]), int(v["knock"]), 0)

static func _self_status_tick(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	if not step.has("self_st"):
		return
	var o := i * FightSim.F_FIELDS
	var ext := FightSim.ext_of(i)
	var fl: int = s[o + FightSim.AB_FL]
	var st_list: Array = step["self_st"]
	for idx in st_list.size():
		if (s[ext + FightSim.EX_STATUS_MASK] & (1 << idx)) != 0:
			continue
		var sd: Dictionary = st_list[idx]
		var at := int(sd.get("tick", sd.get("at", 0)))
		if t < at:
			continue
		var cond := int(sd.get("on", 0))
		var ok := false
		match cond:
			0: ok = true
			1: ok = (fl & SimAbilities.FL_LANDED) != 0
			2: ok = (fl & SimAbilities.FL_COUNTERED) != 0
			3: ok = t >= maxi(at, int(step["w"]) + int(step["a"])) and (fl & (SimAbilities.FL_LANDED | SimAbilities.FL_COUNTERED)) == 0
		if not ok:
			continue
		s[ext + FightSim.EX_STATUS_MASK] |= (1 << idx)
		var st_name := String(sd.get("status_id", sd.get("status", "buff")))
		var dur := int(sd.get("duration", sd.get("dur", 180)))
		var kind := 7
		match st_name:
			"attack_up": kind = 1
			"defense_up": kind = 2
			"poise_up": kind = 3
			"haste": kind = 4
			"regen": kind = 5
			"rage":
				kind = 6
				s[o + FightSim.RAGE_T] = maxi(s[o + FightSim.RAGE_T], dur)
		s[ext + FightSim.EX_BUFF_KIND] = kind
		s[ext + FightSim.EX_BUFF_T] = dur
		s[ext + FightSim.EX_BUFF_VAL] = int(sd.get("val_pm", 200))

static func _marks(src: Array, dm: float, magia: float) -> Array:
	var out: Array = []
	for sp: Variant in src:
		if not (sp is Dictionary):
			continue
		var m: Dictionary = sp
		if m.has("volley") or m.has("paired_hb"):
			continue
		var shape: Dictionary = m.get("shape", {}) if m.get("shape") is Dictionary else {}
		var rad := int(shape.get("r", 0))
		if rad <= 0:
			rad = int(shape.get("outer", 0))
		if rad <= 0:
			rad = maxi(int(shape.get("len", 0)), int(shape.get("w", 0))) / 2
		out.append({
			"at": int(m.get("at", -1)),
			"fwd": int(m.get("fwd", 0)),
			"right": int(m.get("right", 0)),
			"warn": int(m.get("warn", 30)),
			"r": rad,
			"raw": _scaled(int(m.get("dmg", 0)), 0, dm, magia),
			"force": _stun(int(m.get("stun", 0)), 0, 0.0, 1.0, 0.0),
			"knock": int(m.get("knock", 0)),
		})
	return out

static func _waves(src: Array, dm: float, magia: float) -> Array:
	var out: Array = []
	for sp: Variant in src:
		if not (sp is Dictionary):
			continue
		var w: Dictionary = sp
		if w.has("volley") or w.has("paired_hb"):
			continue
		var spd := int(w.get("speed", 0))
		var rng := int(w.get("range", 0))
		var wid := int(w.get("width", 0))
		if spd != 0:
			rng = SimAbilities.reach_up(rng)
			wid = SimAbilities.reach_up(wid)
		out.append({
			"at": int(w.get("at", -1)),
			"fwd": int(w.get("fwd", 0)),
			"right": int(w.get("right", 0)),
			"warn": int(w.get("warn", 0)),
			"spd": spd,
			"range": rng,
			"width": wid,
			"raw": _scaled(int(w.get("dmg", 0)), 0, dm, magia),
			"force": _stun(int(w.get("stun", 0)), 0, 0.0, 1.0, 0.0),
			"knock": int(w.get("knock", 0)),
		})
	return out

## Onda o línea quieta (ground_wave). speed 0 no viaja: la franja espera y pega entera.
static func _spawn_waves(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	var waves: Variant = step.get("waves", [])
	if not (waves is Array) or (waves as Array).is_empty():
		return
	var o := i * FightSim.F_FIELDS
	var f: int = s[o + FightSim.FACE]
	var fx: int = FxMath.COS[f]
	var fz: int = FxMath.SIN[f]
	for sp: Variant in waves:
		if not (sp is Dictionary):
			continue
		var w: Dictionary = sp
		if t != int(w["at"]) or int(w["range"]) <= 0:
			continue
		var fwd := int(w["fwd"])
		var right := int(w["right"])
		var x: int = s[o + FightSim.X] + fx * fwd / FxMath.ONE + fz * right / FxMath.ONE
		var z: int = s[o + FightSim.Z] + fz * fwd / FxMath.ONE - fx * right / FxMath.ONE
		SimAbilities.spawn_hz(s, i, 2, x, z, int(w["warn"]), 0, SimAbilities.raw_live(s, P, i, int(w["raw"])), int(w["force"]), int(w["knock"]), 0, f, int(w["spd"]), int(w["range"]), int(w["width"]))

## Marcas de suelo (ground_mark). La piscina es circular: una línea usa el mayor entre largo y ancho.
static func _spawn_marks(s: PackedInt64Array, P: Array, i: int, step: Dictionary, t: int) -> void:
	var marks: Variant = step.get("marks", [])
	if not (marks is Array) or (marks as Array).is_empty():
		return
	var o := i * FightSim.F_FIELDS
	var f: int = s[o + FightSim.FACE]
	var fx: int = FxMath.COS[f]
	var fz: int = FxMath.SIN[f]
	for sp: Variant in marks:
		if not (sp is Dictionary):
			continue
		var m: Dictionary = sp
		if t != int(m["at"]) or int(m["r"]) <= 0:
			continue
		var fwd := int(m["fwd"])
		var right := int(m["right"])
		var x: int = s[o + FightSim.X] + fx * fwd / FxMath.ONE + fz * right / FxMath.ONE
		var z: int = s[o + FightSim.Z] + fz * fwd / FxMath.ONE - fx * right / FxMath.ONE
		SimAbilities.spawn_hz(s, i, 1, x, z, int(m["warn"]), int(m["r"]), SimAbilities.raw_live(s, P, i, int(m["raw"])), int(m["force"]), int(m["knock"]), 0)

## La marca de suelo del catálogo acumula sangrado al conectar. La piscina no guarda un DoT.
static func on_zone_hit(s: PackedInt64Array, P: Array, owner: int) -> void:
	FightSim._add_status(s, P, owner, 0, BLEED_BUILD)

## Opacidad visual 0..100 del luchador en el paso actual (self_windows type="fade"). Solo vista.
static func step_opacity(s: PackedInt64Array, P: Array, i: int) -> int:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return 100
	var step := _step_of(s, P, i)
	if step.is_empty() or not step.has("self_win"):
		return 100
	var t := maxi(_t(s, o), 0)
	var op := 100
	for sw_var: Variant in step["self_win"]:
		if not (sw_var is Dictionary):
			continue
		var sw: Dictionary = sw_var
		if int(sw.get("type", -1)) != 2:
			continue
		var wf := int(sw.get("from", 0))
		var wt := int(sw.get("to", 0))
		var ofrom := int(sw.get("op_from", 100))
		var oto := int(sw.get("op_to", 0))
		if t >= wf and t <= wt:
			var span := maxi(wt - wf, 1)
			op = ofrom + (oto - ofrom) * (t - wf) / span
		elif t > wt:
			op = oto
	return clampi(op, 0, 100)

## Estela del arma en el paso actual (weapon_trail). Solo vista.
static func weapon_trail_active(s: PackedInt64Array, P: Array, i: int) -> Dictionary:
	var o := i * FightSim.F_FIELDS
	if not _alive(s, o):
		return {"active": false, "style": ""}
	var step := _step_of(s, P, i)
	if step.is_empty() or not step.has("weapon_trail"):
		return {"active": false, "style": ""}
	var wt: Dictionary = step["weapon_trail"]
	var t := maxi(_t(s, o), 0)
	var on := t >= int(wt.get("from", 0)) and t < int(wt.get("to", 0))
	return {"active": on, "style": String(wt.get("style", "default")) if on else ""}
