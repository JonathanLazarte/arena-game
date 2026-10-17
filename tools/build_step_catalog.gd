extends SceneTree
## Escribe data/abilities/catalog.json desde las definiciones actuales.
## godot --headless --path . -s res://tools/build_step_catalog.gd

const TK := 1.12
## Vacío = solo se esquiva. El resto declara con qué se corta.
const CUTS := {
	"pisoton": ["stun_lvl1", "stun_lvl2", "knockdown"],
	"garra_suelo": ["stun_lvl1", "stun_lvl2", "knockdown"],
	"danza_cisne": ["parry", "stun_lvl2", "knockdown"],
	"tajo_cruzado": ["parry", "stun_lvl2", "knockdown"],
	"barrido_cola": ["parry", "stun_lvl2", "knockdown"],
	"zarpazo_sangre": ["parry", "stun_lvl2", "knockdown"],
	"combo_falso": ["parry", "stun_lvl2", "knockdown"],
	"danza_triple": ["stun_lvl2", "knockdown"],
	"onda_rastrera": ["stun_lvl2", "knockdown"],
	"vendaval_hacha": ["stun_lvl2", "knockdown"],
	"anillo_fuego": ["stun_lvl2", "knockdown"],
	"embate_sismico": ["knockdown"],
	"rayos_trazadores": ["stun_lvl2", "knockdown"],
	"lluvia_meteoros": ["stun_lvl2", "knockdown"],
	"lluvia_lanzas": ["stun_lvl2", "knockdown"],
	"lluvia_sangre": ["stun_lvl2", "knockdown"],
	"columnas_rayo": ["stun_lvl2", "knockdown"],
	"aliento_dragon": ["stun_lvl2", "knockdown"],
	"aliento_rayo": ["stun_lvl2", "knockdown"],
	"aliento_escarcha": ["stun_lvl2", "knockdown"],
	"chorro_lava": ["stun_lvl2", "knockdown"],
	"carga_area": ["stun_lvl2", "knockdown"],
}

func _initialize() -> void:
	var abilities: Array = []
	for id: String in BossAbilities.ORDER + BossAbilities.EXT_ORDER:
		abilities.append(_ability(id))
	var root := {"version": 1, "tick_rate": 60, "abilities": abilities}
	var text := JSON.stringify(root, "\t")
	var f := FileAccess.open("res://data/abilities/catalog.json", FileAccess.WRITE)
	f.store_string(text + "\n")
	f.close()
	print("escribió %d habilidades" % abilities.size())
	quit()

func _ability(id: String) -> Dictionary:
	var d := BossAbilities.def(id)
	var typ := String(d.get("type", _base_type(id)))
	var unbl := BossAbilities.is_unblockable(id)
	var scaling := "weapon_light" if d.get("light", false) else "weapon_heavy"
	var step := _step(id, d, typ, unbl, scaling)
	var cat := "melee"
	match typ:
		"wave", "rain": cat = "zone"
		"breath", "rafaga": cat = "magic" if d.get("magic", false) else "ranged"
		"rage": cat = "buff"
		"counter": cat = "counter"
		"grab": cat = "grab"
	if d.get("grab", false):
		cat = "grab"
	var tags: Array = []
	if unbl:
		tags.append("unblockable")
	if typ in ["wave", "rain"]:
		tags.append("aoe")
	if typ == "rafaga":
		tags.append("projectile")
	var cost := {"stamina": 0.0, "mana": 0.0, "health": 0.0}
	cost[String(d.get("cost_type", "stamina"))] = float(d.get("cost", 1.0))
	if float(d.get("cost", 0.0)) <= 0.0:
		cost["stamina"] = 1.0
	var cd := int(round(float(d.get("cd", 8.0)) * 60.0))
	return {
		"id": id,
		"name": String(d.get("name", id)),
		"icon": "boss:%s" % id,
		"category": cat,
		"tags": tags,
		"unlock": {"phase": 1},
		"cost": cost,
		"cooldown_ticks": cd,
		"uses_global_cd": true,
		"usable_while": ["ground"],
		"interruptible_by": CUTS.get(id, []),
		"entry_step": step["id"],
		"ai": {"range_min": 0.0, "range_max": float(d.get("range", 8.0)), "weight": 10, "use_when": ["target_in_range"]},
		"hint": {"text": String(d.get("tele_txt", d.get("tele", d.get("desc", ""))))},
		"steps": [step],
	}

func _base_type(id: String) -> String:
	match id:
		"estocada", "combo_falso": return "timeline"
		"carga_area", "salto_caida": return "rain"
		"rafaga": return "rafaga"
		"escudo_mana": return "rage"
		_: return "timeline"

func _step(id: String, d: Dictionary, typ: String, unbl: bool, scaling: String) -> Dictionary:
	var windup := 18
	var active := 6
	var recovery := 30
	var hitboxes: Array = []
	var spawns: Array = []
	var events: Array = []
	var tracking: Variant = null
	var movement: Variant = null
	if typ == "timeline" or d.has("hits"):
		var hits: Array = d.get("hits", [[1.0, 1.0, 20.0, 0.0]])
		var first := SimParams.tk(float(hits[0][0]) * TK)
		var last := SimParams.tk(float(hits[-1][0]) * TK)
		var end := SimParams.tk(float(hits[-1][0]) * TK + float(d.get("recovery", 0.9)))
		windup = maxi(first - 1, 1)
		if unbl:
			windup = maxi(windup, 18)
		active = maxi(last - first + 1, 1)
		recovery = maxi(end - windup - active, 18)
		for i in hits.size():
			var h: Array = hits[i]
			var ht := SimParams.tk(float(h[0]) * TK) - 1
			var from := clampi(ht - windup, 0, active - 1)
			hitboxes.append({
				"id": "hb_%d" % i,
				"shape": {"type": "arc", "radius_m": float(d.get("reach", 2.8)), "angle_deg": float(d.get("arc", 60.0)) * 2.0},
				"from_tick": from, "to_tick": from + 1,
				"damage_per_hit": _r3(float(d.get("dmg", 1.0)) * float(h[1])),
				"damage_scaling": scaling,
				"blockable": not unbl, "parryable": not unbl,
				"stun_power": float(h[2]), "stun_scaling": "physical",
			})
		if float(d.get("track", 0.0)) > 0.0:
			var lock := SimParams.tk(float(hits[0][0]) * TK - 0.06) - 1
			tracking = {"deg_per_sec": float(d["track"]), "lock_at_tick": clampi(lock, 0, windup + active + recovery - 1), "post_lock_deg_per_sec": 0.0}
		var fl: Array = d.get("flicker", [])
		if fl.size() > 1:
			events.append({"id": "ev_flick0", "tick": maxi(SimParams.tk(float(fl[0]) * TK) - 1, 0), "vfx": "vfx_flash", "sfx": "sfx_ring"})
			events.append({"id": "ev_flick1", "tick": maxi(SimParams.tk(float(fl[1]) * TK) - 1, 0), "vfx": "vfx_flash", "sfx": "sfx_ring"})
		events.append({"id": "ev_golpe", "tick": maxi(last - 1, 0), "vfx": "vfx_slash", "sfx": "sfx_heavy"})
		if float(d.get("slam_radius", 0.0)) > 0.0:
			var at := clampi(last - 1, 0, windup + active + recovery - 1)
			spawns.append({
				"id": "sp_slam", "type": "ground_mark", "at_tick": at,
				"on": "always" if d.get("slam_always", false) else "hit",
				"offset": {"forward_m": 1.2},
				"shape": {"type": "circle", "radius_m": float(d["slam_radius"])},
				"warn_ticks": maxi(SimParams.tk(float(d.get("slam_warn", 0.35))), 1),
				"damage": _r3(float(d.get("dmg", 1.0)) * float(d.get("slam_mult", 0.65))),
				"stun_power": float(d.get("slam_force", 40.0)),
				"knockback_mps": 9.0, "blockable": true, "mode": "track",
			})
	elif typ == "wave":
		windup = maxi(SimParams.tk(float(d["windup"]) * TK) - 1, 1)
		active = 1
		var end := SimParams.tk(float(d["windup"]) * TK + float(d.get("recovery", 0.8)))
		recovery = maxi(end - windup - active, 18)
		tracking = {"deg_per_sec": 240.0, "lock_at_tick": mini(windup, windup + active + recovery - 1), "post_lock_deg_per_sec": 0.0}
		spawns.append({
			"id": "sp_onda", "type": "ground_wave", "at_tick": mini(windup, windup),
			"offset": {"forward_m": 1.0}, "count": int(d.get("count", 1)),
			"spread_deg": float(d.get("spread_deg", 0.0)), "ring": bool(d.get("ring", false)),
			"speed_mps": float(d["speed"]), "range_m": float(d["range"]), "width_m": float(d["width"]),
			"warn_ticks": SimParams.tk(float(d["warn"]) * TK),
			"damage": float(d.get("dmg", 0.8)), "stun_power": float(d.get("force", 30.0)),
			"blockable": not unbl, "knockback_mps": 6.0,
		})
	elif typ == "rain":
		windup = maxi(SimParams.tk(float(d.get("windup", d.get("lock", 1.0))) * TK) - 1, 1)
		if unbl:
			windup = maxi(windup, 18)
		active = 1
		var cnt := int(d.get("count", 1))
		var end := SimParams.tk(float(d.get("windup", 0.7)) * TK + (cnt - 1) * float(d.get("interval", 0.0)) + float(d.get("recovery", 0.6)))
		recovery = maxi(end - windup - active, 18)
		var mode := "scatter" if String(d.get("mode", "track")) != "track" else "track"
		spawns.append({
			"id": "sp_marca", "type": "ground_mark", "at_tick": mini(windup, windup + active + recovery - 2),
			"shape": {"type": "circle", "radius_m": float(d.get("radius", 2.0))},
			"warn_ticks": maxi(SimParams.tk(float(d.get("tele", d.get("warn", 0.8))) * (TK if d.get("tele") is float or d.has("tele") else 1.0)), 30),
			"damage": float(d.get("dmg", 1.0)), "stun_power": float(d.get("force", 25.0)),
			"knockback_mps": float(d.get("knock", 6.0)), "blockable": not unbl,
			"mode": mode, "count": cnt, "interval_ticks": SimParams.tk(float(d.get("interval", 0.0))),
			"scatter_radius_m": float(d.get("scatter_r", 0.0)),
		})
	else:
		windup = maxi(SimParams.tk(float(d.get("windup", 0.6)) * TK) - 1, 18 if unbl else 1)
		active = maxi(SimParams.tk(float(d.get("duration", d.get("active", 1.0)))), 1)
		recovery = maxi(SimParams.tk(float(d.get("recovery", 0.8))), 18)
		if typ == "breath":
			spawns.append({
				"id": "sp_cono", "type": "beam", "at_tick": mini(windup, windup + active - 1),
				"length_m": float(d.get("range", 7.0)), "angle_deg": float(d.get("arc", 28.0)),
				"duration_ticks": active, "tick_interval": maxi(SimParams.tk(float(d.get("tick", 0.3))), 1),
				"sweep_deg_per_sec": float(d.get("turn_deg", 40.0)),
				"damage": float(d.get("dmg", 0.4)), "stun_power": float(d.get("force", 8.0)),
			})
		elif typ == "rafaga":
			spawns.append({
				"id": "sp_tiro", "type": "projectile", "at_tick": mini(windup, 1),
				"count": int(d.get("count", 1)), "speed_mps": float(d.get("speed", 16.0)),
				"homing_deg": float(d.get("home_deg", 40.0)), "homing_ticks": SimParams.tk(float(d.get("home_time", 1.0))),
				"lifetime_ticks": maxi(SimParams.tk(float(d.get("life", 2.0))), 1),
				"radius_m": float(d.get("radius", 0.7)),
				"hitbox": {"damage_per_hit": float(d.get("dmg", 1.0)), "stun_power": float(d.get("force", 20.0)), "blockable": not unbl, "parryable": false},
			})
	var total := windup + active + recovery
	var tele_at := 0
	var step := {
		"id": "paso",
		"windup_ticks": windup,
		"active_ticks": active,
		"recovery_ticks": recovery,
		"telegraph": {
			"id": "tg_%s" % id,
			"style": "ground_ring" if typ in ["wave", "rain"] else "weapon_glow",
			"color": _hex(d),
			"sound": "sfx_tele_%s" % id,
			"at_tick": tele_at,
			"text": String(d.get("tele_txt", d.get("tele", ""))),
		},
		"hitboxes": hitboxes,
		"spawns": spawns,
		"events": _fit_events(events, total),
	}
	if tracking != null:
		step["tracking"] = tracking
	if movement != null:
		step["movement"] = movement
	var resist := float(d.get("resist", 0.0))
	if resist > 0.0 and resist < 90.0:
		step["armor"] = {"type": "super", "from_tick": 0, "to_tick": total, "poise_bonus_pct": clampi(int(round(resist * 100.0)), 1, 500)}
	return step

func _fit_events(events: Array, total: int) -> Array:
	var out: Array = []
	var used := {}
	for ev: Dictionary in events:
		var t := clampi(int(ev["tick"]), 0, total - 1)
		while used.has(t) and t + 1 < total:
			t += 1
		if used.has(t):
			continue
		used[t] = true
		ev["tick"] = t
		out.append(ev)
	return out

func _r3(v: float) -> float:
	return snapped(v, 0.001)

func _hex(d: Dictionary) -> String:
	var c: Color = d.get("color", Color(0.9, 0.8, 0.4))
	return "#" + c.to_html(false)
