class_name FighterMagic
extends RefCounted
## Controlador de hechizos y artes. Fighter conserva propiedades y métodos fachada.

static func set_magic(f: Fighter, sp: Array, art: String, seal: String) -> void:
	f.spells = sp.duplicate()
	f.spell_idx = 0
	for i in f.spells.size():
		if String(f.spells[i]) != "":
			f.spell_idx = i
			break
	f.weapon_art_id = art
	f.eikon_seal_id = seal if EikonSeals.DEFS.has(seal) else ""

static func has_spells(f: Fighter) -> bool:
	for s in f.spells:
		if String(s) != "":
			return true
	return false

static func current_spell(f: Fighter) -> String:
	return String(f.spells[f.spell_idx]) if f.spell_idx < f.spells.size() else ""

static func cycle_spell(f: Fighter) -> String:
	if not has_spells(f):
		return ""
	for k in range(1, f.spells.size() + 1):
		var i := (f.spell_idx + k) % f.spells.size()
		if String(f.spells[i]) != "":
			f.spell_idx = i
			break
	f.spell_changed.emit(f.spell_idx, current_spell(f))
	return current_spell(f)

static func spell_cd_left(f: Fighter, id: String = "") -> float:
	return float(f.spell_cd.get(current_spell(f) if id == "" else id, 0.0))

static func can_cast(f: Fighter) -> bool:
	var id := current_spell(f)
	if id == "" or f.mounted or f.airborne or not f._can_act() or f.roll_t >= 0.0 or f.swap_t > 0.0 or f.is_shooting():
		return false
	if f.atk_state != Fighter.Atk.NONE or f.parry_state != Fighter.Parry.NONE:
		return false
	return spell_cd_left(f, id) <= 0.0 and f.energy >= float(EikonSpells.spell(id)["cost"])

static func cast_spell(f: Fighter) -> bool:
	if not can_cast(f):
		return false
	var id := current_spell(f)
	var d := EikonSpells.spell(id)
	f.energy -= float(d["cost"])
	f.energy_changed.emit(f.energy, f.energy_max)
	f.spell_cd[id] = float(d["cooldown"])
	f.cast_t = float(d["cast"])
	f._cast_id = id
	f.blocking = false
	f.spells_cast += 1
	f._snd("eikon_summon", -6.0)
	f._kv.event("shoot")
	return true

static func update(f: Fighter, delta: float) -> void:
	for k: String in f.spell_cd.keys():
		f.spell_cd[k] = maxf(float(f.spell_cd[k]) - delta, 0.0)
	f.art_cd = maxf(f.art_cd - delta, 0.0)
	f.stoneskin_t = maxf(f.stoneskin_t - delta, 0.0)
	if f.cast_t > 0.0:
		if not f.alive or f.stun > 0.0:
			f.cast_t = 0.0
			f._cast_id = ""
			return
		f.cast_t -= delta
		if f.cast_t <= 0.0:
			f.cast_t = 0.0
			var id := f._cast_id
			f._cast_id = ""
			fire_spell(f, id)

static func spell_dir(f: Fighter) -> Vector3:
	var tgt: Node3D = f.face_target if f._lock_valid() else MeshUtil.nearest(f.global_position, MeshUtil.enemies_of(f.get_tree(), f.team))
	if tgt:
		var dd := MeshUtil.flat(tgt.global_position - f.global_position)
		if dd.length() > 0.1:
			return dd.normalized()
	return f.facing

static func fire_spell(f: Fighter, id: String) -> void:
	var d := EikonSpells.spell(id)
	if d.is_empty():
		return
	var pw := EikonSpells.power(id, f.ad)
	f.facing = spell_dir(f)
	match String(d["type"]):
		"proyectil":
			var p := Projectile.new()
			p.team = f.team
			p.shooter = f
			p.kind = "eikon"
			p.element = String(d["element"])
			p.status = d.get("status", {})
			p.direction = f.facing
			p.speed = float(d["speed"])
			p.damage = float(d["damage"]) * pw
			p.color = Color(1.0, 0.55, 0.2) if d["element"] == "fuego" else Color(0.75, 0.9, 1.0)
			f.get_parent().add_child(p)
			p.global_position = f.get_hit_center() + Vector3(0, 0.6, 0) + f.facing * 1.2
			f._snd("eikon_fire" if d["element"] == "fuego" else "eikon_wind")
		"cono":
			f._snd("eikon_ice")
			var half := deg_to_rad(float(d["arc"]) * 0.5)
			for t in MeshUtil.enemies_of(f.get_tree(), f.team):
				var dd := MeshUtil.flat(t.global_position - f.global_position)
				if dd.length() > float(d["range"]) + float(t.hit_radius):
					continue
				if dd.length() > 0.2 and f.facing.angle_to(dd.normalized()) > half:
					continue
				if t is Fighter:
					(t as Fighter).incoming_element = String(d["element"])
					(t as Fighter).incoming_status = d.get("status", {})
				t.take_hit(float(d["damage"]) * pw, f, "eikon")
			f._burst_particles(Color(0.7, 0.9, 1.0))
		"buff":
			f._stoneskin = d
			f.stoneskin_t = float(d["duration"]) * pw
			f._burst_particles(Color(0.75, 0.65, 0.5))
			f._snd("eikon_slam", -4.0)

static func use_weapon_art(f: Fighter) -> bool:
	var a := WeaponArts.art(f.weapon_art_id)
	if a.is_empty() or f.mounted or f.airborne or not f._can_act() or f.art_cd > 0.0 or f.roll_t >= 0.0:
		return false
	if f.loadout != Fighter.Loadout.SWORD_SHIELD or f.atk_state != Fighter.Atk.NONE or f.parry_state != Fighter.Parry.NONE or f.swap_t > 0.0 or f.stamina <= 0.0:
		return false
	if f.energy < float(a["cost"]):
		return false
	f.energy -= float(a["cost"])
	f.energy_changed.emit(f.energy, f.energy_max)
	f.art_cd = float(a["cooldown"])
	f.arts_used += 1
	f.blocking = false
	match f.weapon_art_id:
		"estocada_impulsada":
			f.dash_dir = spell_dir(f)
			f.spend_stamina(f.melee().light_stamina)
			f._start_dash_strike()
			f._art_mult = float(a["mult"])
		"torbellino":
			f.special_t = 0.3
			f.spend_stamina(f.melee().heavy_stamina)
			GroundAoE.spawn(f.get_parent(), f, f.team, f.global_position, float(a["radius"]), 0.3, f.melee().light_damage * float(a["mult"]) * f.damage_mult())
			f._kv.event("slam")
			f._snd("swing_heavy")
	return true
