class_name FighterCombat
extends RefCounted
## Controlador de ataques, encadenamiento y parada. Fighter mantiene la fachada pública.

static func parry(f: Fighter) -> bool:
	if f.mounted:
		return false
	if f.loadout != Fighter.Loadout.SWORD_SHIELD or not f._can_act() or f.swap_t > 0.0 or f.roll_t >= 0.0:
		return false
	if f.atk_state != Fighter.Atk.NONE or f.parry_state != Fighter.Parry.NONE or f.stamina <= 0.0:
		return false
	f.parry_state = Fighter.Parry.ACTIVE
	f.parry_t = 0.0
	f.blocking = false
	f.spend_stamina(Fighter.COST_PARRY)
	return true

static func request_attack(f: Fighter, heavy: bool) -> bool:
	if f.backstep_t > 0.0 and not f.mounted and f.loadout == Fighter.Loadout.SWORD_SHIELD:
		f.backstep_attack_queued = true
		return true
	if f.roll_t >= 0.0 and not f.mounted and f.loadout == Fighter.Loadout.SWORD_SHIELD and f.alive and f.roll_t < f.roll_iframe_end():
		f._roll_atk_buffer = true
		return false
	if f.loadout != Fighter.Loadout.SWORD_SHIELD or not f._can_act() or f.swap_t > 0.0 or f.parry_state != Fighter.Parry.NONE or f.roll_t >= 0.0:
		return false
	if not f.mounted and not f.airborne and f.atk_state == Fighter.Atk.NONE and f.stamina > 0.0:
		var ct := f.crit_candidate()
		if ct:
			f._start_crit(ct)
			return true
		if f.guard_counter_t > 0.0:
			f.guard_counter_t = 0.0
			f.blocking = false
			f.combo = f.max_combo()
			f._start_attack(true, false)
			f.atk_gc = true
			f.atk_dur *= Fighter.GC_WINDUP_MULT
			f.guard_counters += 1
			return true
		if f.sprinting and not heavy and f.move_input.length() > 0.5:
			f.dash_dir = MeshUtil.flat(f.move_input).normalized()
			f.running_attacks += 1
			f._start_dash_strike()
			return true
	if f.mounted and absf(rad_to_deg(f.rider_yaw)) > Fighter.MELEE_TWIST_MAX_DEG:
		return false
	if f.airborne and not f.mounted:
		if f.atk_state != Fighter.Atk.NONE or f.stamina <= 0.0:
			return false
		f.atk_jump = true
		f.combo = f.max_combo()
		f._start_attack(false, false)
		f.velocity.y = minf(f.velocity.y, -2.0)
		return true
	if f.atk_state != Fighter.Atk.NONE:
		var in_window := f.atk_state != Fighter.Atk.RECOVERY or f.cur_hit == null or f.atk_t <= f.cur_hit.window
		if not heavy and not f.atk_heavy and f.combo < f.max_combo() and in_window and (f.atk_state != Fighter.Atk.WINDUP or f.atk_t > f.atk_dur * 0.5):
			f._buffered = true
		return false
	if f.blocking or f.stamina <= 0.0:
		return false
	f.combo = 1
	f._start_attack(heavy, false)
	if f.mounted and f.dash_time > 0.0:
		f._ds_visual = true
	return true

static func update_parry(f: Fighter, delta: float) -> void:
	if f.parry_state == Fighter.Parry.NONE:
		return
	f.parry_t += delta
	if f.parry_state == Fighter.Parry.ACTIVE and f.parry_t >= f.parry_window:
		f.parry_state = Fighter.Parry.RECOVERY
		f.parry_t = 0.0
	elif f.parry_state == Fighter.Parry.RECOVERY and f.parry_t >= Fighter.PARRY_RECOVERY:
		f.parry_state = Fighter.Parry.NONE

static func cancel_attack(f: Fighter) -> void:
	f.atk_state = Fighter.Atk.NONE
	f._dash_atk = false
	f.atk_dash = false
	f._ds_visual = false
	f.atk_jump = false
	f.combo = 0
	f.cur_hit = null
	f._buffered = false
	f._blade_mat.emission_enabled = false
	f._kv.set_glow(false, Color.BLACK)
	f._sword_pivot.rotation = Vector3.ZERO

static func update_attack(f: Fighter, delta: float) -> void:
	if f.atk_state == Fighter.Atk.NONE:
		return
	f.atk_t += delta
	var d := f._atk_data()
	match f.atk_state:
		Fighter.Atk.WINDUP:
			if f.dash_time > 0.0 and f.mounted:
				f._dash_atk = true
				return
			if f._dash_atk and f.atk_t >= Fighter.DASH_STRIKE_MIN_TIME and f.atk_t < f.atk_dur:
				f.atk_t = f.atk_dur
				f.dash_strikes += 1
			f._dash_atk = f._dash_atk and f.atk_t < f.atk_dur
			if f.atk_heavy and not f.atk_gc and f.want_charge and f.atk_t >= f.atk_dur and f.charge_t < Fighter.CHARGE_MAX and f.stamina > 0.0:
				f.charge_t = minf(f.charge_t + delta, Fighter.CHARGE_MAX)
				f.atk_t = f.atk_dur - 0.001
				if f.mounted:
					f._sword_pivot.rotation.x = -0.48 * clampf(f.charge_t / Fighter.CHARGE_MAX, 0.0, 1.0)
				return
			if f.atk_t >= f.atk_dur:
				f.atk_state = Fighter.Atk.ACTIVE
				f.atk_t = 0.0
				f.atk_dur = d["active"]
				f._blade_mat.emission_enabled = false
				f._kv.set_glow(false, Color.BLACK)
				var half := f.sword_half_arc()
				var tw := f.create_tween()
				tw.tween_property(f._sword_pivot, "rotation", Vector3(0, -half, 0), f.atk_dur)
				strike_frame(f, d)
		Fighter.Atk.ACTIVE:
			strike_frame(f, d)
			if f.atk_t >= f.atk_dur:
				f.atk_state = Fighter.Atk.RECOVERY
				f.atk_t = 0.0
				f.atk_dur = d["recovery"] + (0.0 if f._atk_landed else d["whiff"])
				if not f._atk_landed:
					f._snd("whiff")
				if f.combo >= f.max_combo():
					f.atk_dur += Fighter.FINISHER_EXTRA_RECOVERY
		Fighter.Atk.RECOVERY:
			if f._buffered and f.combo < f.max_combo() and f.atk_t >= Fighter.CHAIN_MIN_RECOVERY and f.stamina > 0.0 and f.exhausted <= 0.0 and f.stun <= 0.0:
				f.combo += 1
				f.atk_dash = false
				f._ds_visual = false
				f._start_attack(false, true)
				return
			if f.atk_t >= f.atk_dur:
				cancel_attack(f)

static func strike_frame(f: Fighter, d: Dictionary) -> void:
	if not f.alive:
		return
	for t in MeshUtil.enemies_of(f.get_tree(), f.team):
		if t in f._atk_hit or not f.in_sword_arc(t):
			continue
		f._atk_hit.append(t)
		var was_open: bool = t is Fighter and ((t as Fighter).in_recovery() or (t as Fighter).stun > 0.0)
		var res: String = t.take_hit(d["damage"], f, "melee")
		if res == "hit" and t is Fighter and (t as Fighter).mounted:
			var mount_target := t as Fighter
			var charge_ratio := clampf(f.charge_t / Fighter.CHARGE_MAX, 0.0, 1.0)
			mount_target.damage_mount_stance(30.0 + 40.0 * charge_ratio if f.mounted and f.atk_heavy else float(d["damage"]) * (1.8 if f.atk_heavy else 0.9))
		if res == "hit" or res == "block" or res == "parry":
			f._atk_landed = true
		if res == "hit":
			f.add_meter(18.0 if f.atk_heavy else 12.0)
		elif res == "block":
			f.add_meter(3.0)
		if res == "hit":
			f.hits_landed += 1
			if f.atk_heavy or was_open:
				f.hitstop.emit(Fighter.HITSTOP_HEAVY)
				f.impact.emit(0.9)
		f.landed_hit.emit(t, res, was_open)

static func stance_fraction(f: Fighter) -> float:
	return clampf(f.stance / maxf(f.stance_max, 1.0), 0.0, 1.0)

static func update_exchange(f: Fighter, delta: float) -> void:
	f.guard_counter_t = maxf(f.guard_counter_t - delta, 0.0)
	f.stance_broken_t = maxf(f.stance_broken_t - delta, 0.0)
	if f._since_hit > Fighter.STANCE_DELAY:
		f.stance = minf(f.stance + Fighter.STANCE_REGEN * delta, f.stance_max)
	if f.crit_t >= 0.0:
		f.crit_t += delta
		if not f._crit_done and f.crit_t >= Fighter.CRIT_HIT_AT:
			f._crit_done = true
			if is_instance_valid(f._crit_target) and f._crit_target.alive:
				var dmg := f.melee().heavy_damage * f.damage_mult() * Fighter.CRIT_MULT
				var h0 := f._crit_target.health
				f._crit_target.take_hit(dmg, f, "critico")
				f.crits += 1
				f.critical_landed.emit(f._crit_target, h0 - f._crit_target.health)
				f._snd("eikon_slam", -3.0)
				f.hitstop.emit(0.12)
				f.impact.emit(1.2)
		if f.crit_t >= Fighter.CRIT_TIME:
			f.crit_t = -1.0
			f._crit_target = null

static func crit_candidate(f: Fighter) -> Fighter:
	for t in MeshUtil.enemies_of(f.get_tree(), f.team):
		if not (t is Fighter):
			continue
		var target := t as Fighter
		if target.stance_broken_t <= 0.0 or target.mounted or not target.alive:
			continue
		var d := MeshUtil.flat(f.global_position - target.global_position)
		if d.length() > Fighter.CRIT_RANGE:
			continue
		if d.length() > 0.1 and target.facing.dot(d.normalized()) < 0.2:
			continue
		return target
	return null

static func start_crit(f: Fighter, target: Fighter) -> void:
	f.crit_t = 0.0
	f._crit_done = false
	f._crit_target = target
	f.execution_cinematic.emit(f, target, Fighter.CRIT_TIME)
	f.invuln = Fighter.CRIT_TIME
	f.blocking = false
	var dd := MeshUtil.flat(target.global_position - f.global_position)
	if dd.length() > 0.1:
		f.facing = dd.normalized()
	target.stance_broken_t = 0.0
	target.stun = maxf(target.stun, Fighter.CRIT_TIME + 0.3)
	target.blocking = false
	f.spend_stamina(Fighter.COST_PARRY)
	f._kv.event("slam")
	f._snd("swing_heavy")
