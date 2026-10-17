class_name SimMagic
extends RefCounted
## Magia (EikonSpells: proyectil, cono, piel de piedra), medidor/invocación de eikon, eikon
## compañero (persigue y ataca: cuerpo a cuerpo, a distancia o golpe al suelo) y eikon montable
## (velocidad/giro de montura, postura de montura con derribo, especial y fin de invocación).
## Enteros y ticks; los parámetros se hornean en SimParams (bake_magic) desde el Fighter real.

const MOUNT_STANCE := 100000
const MOUNT_REGEN := 200 # 12/s
const MOUNT_REGEN_DELAY := 240 # 4 s
const DISMOUNT_SIDE := 1600000
const MOUNT_REACH := 3500000
const SPECIALS := ["", "llamarada", "colmillo", "vendaval"]

## Ticks que tarda en vaciarse un temporizador offline que resta delta hasta <= 0.
static func tk_down(sec: float) -> int:
	var t := sec
	var n := 0
	while t > 0.0 and n < 100000:
		t -= 1.0 / 60.0
		n += 1
	return n

static func _elem(e: String) -> int:
	if e == "" or e == "fisico":
		return 0
	var i := SimParams.ELEMS.find(e)
	return 0 if i < 0 else SimParams.SUBS.size() + i

static func bake(f: Fighter, p: Dictionary) -> void:
	p["mana_max"] = SimParams.milli(f.energy_max)
	p["mana_regen"] = SimParams.milli(float(f.ad["energia_regen"]))
	p["meter_pm"] = SimParams.pm(float(f.ad["medidor"]) * float(f.tfx["eikon_rate"]))
	p["meter0"] = 0 # online siempre empieza con el medidor vacío (el valor vivo no es determinista)
	p["sagrado_pm"] = SimParams.pm(float(f.ad["sagrado"]))
	p["aoe_pm"] = SimParams.pm(EquipStats.resist_mult("inmunidad", f.eq, f.eq_ref)) if not f.eq.is_empty() else 1000
	p["eikon_block_cost"] = SimParams.milli(Fighter.COST_BLOCKED_EIKON * float(f.tfx["stamina_cost"]))
	# hechizos
	var sp: Array = []
	var pw_sel := 0
	for k in f.spells.size():
		var id := String(f.spells[k])
		var d := EikonSpells.spell(id)
		if d.is_empty():
			sp.append({})
			continue
		var pw := EikonSpells.power(id, f.ad)
		var e := {"id": id, "type": ["proyectil", "cono", "buff"].find(String(d["type"])), "cost": SimParams.milli(float(d["cost"])),
			"cd": tk_down(float(d["cooldown"])), "cast": tk_down(float(d["cast"])), "elem": _elem(String(d.get("element", ""))),
			"raw": SimParams.milli(float(d.get("damage", 0.0)) * pw), "st": SimParams._status_arr(d.get("status", {}))}
		match int(e["type"]):
			0: e["spd"] = SimParams.um(float(d["speed"]) / 60.0)
			1:
				e["range"] = SimParams.um(float(d["range"]))
				e["cos_arc"] = SimParams.cos_q(float(d["arc"]) * 0.5)
			2:
				e["dur"] = tk_down(float(d["duration"]) * pw)
				p["skin_red_pm"] = SimParams.pm(float(d.get("reduction", 0.0)))
				p["skin_poise_pm"] = SimParams.pm(float(d.get("poise", 1.0)))
		sp.append(e)
	while sp.size() < 4:
		sp.append({})
	sp.resize(4)
	p["spells"] = sp
	p["spell_sel0"] = clampi(f.spell_idx, 0, 3)
	# eikon
	p["eikon_elem"] = _elem(String(EquipStats.EIKON_ELEMENT.get(f.eikon.id if f.eikon else "", "fisico")))
	p["eikon_st"] = [0, 0, SimParams.milli(Fighter.LOBO_FROST)] if f.eikon and f.eikon.id == "lobo" else [0, 0, 0]
	# arte del arma (Fighter.special sin habilidad propia → use_weapon_art)
	var art := WeaponArts.art(f.weapon_art_id)
	p["art"] = {}
	if not art.is_empty() and not f.has_special() and WeaponArts.compatible(f.melee()):
		var st_k := float(f.tfx["stamina_cost"])
		var ai := {"type": 1 if f.weapon_art_id == "estocada_impulsada" else 2, "cost": SimParams.milli(float(art["cost"])),
			"cd": tk_down(float(art["cooldown"])), "k": SimParams.pm(float(art["mult"]))}
		if int(ai["type"]) == 1:
			ai["st"] = SimParams.milli(f.melee().light_stamina * st_k)
		else:
			ai["st"] = SimParams.milli(f.melee().heavy_stamina * st_k)
			ai["t"] = tk_down(0.3)
			ai["r"] = SimParams.um(float(art["radius"]))
			ai["raw"] = SimParams.milli(f.melee().light_damage * float(art["mult"]) * f.damage_mult())
		p["art"] = ai
	# montado (Fighter.stats() = montura; arma: alcance y daño a caballo)
	var w := f.melee()
	p["m_reach_pm"] = SimParams.pm(w.reach_mounted / maxf(w.reach_foot, 0.1))
	p["m_dmg_pm"] = SimParams.pm(w.mounted_damage_mult)
	p["m_dash_raw"] = SimParams.milli(Fighter.DASH_DAMAGE)
	p["m_dash_knock"] = SimParams.um(Fighter.DASH_KNOCKBACK / 60.0)
	p["m_dash_cost"] = SimParams.milli(Fighter.COST_DASH * float(f.tfx["stamina_cost"]))
	if f.eikon == null:
		p["ek"] = {}
		return
	var ed := EikonSeals.apply_to(f.eikon, f.eikon_seal_id)
	var bond := float(f.ad["eikon"])
	var ek := {"id": ed.id, "ride": 1 if ed.rideable else 0, "life": tk_down(ed.duration), "hp": SimParams.milli(ed.max_health * bond),
		"move": SimParams.um(ed.move_speed / 60.0), "kind": int(ed.attack_kind), "dmg": SimParams.milli(ed.attack_damage * bond),
		"range": SimParams.um(ed.attack_range), "range_in": SimParams.um(ed.attack_range * 0.8), "cd": tk_down(ed.attack_cooldown), "cd0": tk_down(0.5),
		"special": maxi(SPECIALS.find(ed.special_id), 0), "sp_dmg": SimParams.milli(ed.special_damage * bond), "sp_cd": tk_down(ed.special_cooldown),
		"y": SimParams.um(1.0 * ed.size)}
	if ed.rideable and ed.ride:
		var m := ed.ride
		ek["hover"] = SimParams.um(m.hover)
		p["m_speed"] = SimParams.um(m.speed * f.speed_mult() / 60.0)
		p["m_turn"] = maxi(int(round(rad_to_deg(m.turn_speed) / 60.0 * 256.0 / 360.0)), 1)
		p["m_dash_spd"] = SimParams.um(m.dash_speed / 60.0)
		p["m_dash_t"] = tk_down(m.dash_duration)
		p["m_dash_if"] = tk_down(m.dash_iframes)
		p["m_dash_cd"] = tk_down(m.dash_cooldown)
	# invocación golpeable (Eikon.take_hit / Mount.take_hit sin jinete): radio y altura
	ek["hr"] = SimParams.um(1.2 if ed.rideable else 0.9 * ed.size)
	ek["fly"] = 1 if (ed.flying and not ed.rideable) else 0
	ek["cy"] = SimParams.um(2.5 if int(ek["fly"]) != 0 else 0.9 * ed.size)
	p["ek"] = ek

# ---------------- Hechizos ----------------
static func cycle_spell(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	var sp: Array = P[i].get("spells", [])
	for k in range(1, 5):
		var j: int = (s[o + FightSim.SP_SEL] + k) % 4
		if j < sp.size() and not (sp[j] as Dictionary).is_empty():
			s[o + FightSim.SP_SEL] = j
			return

static func cast(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var sp: Array = P[i].get("spells", [])
	var k: int = s[o + FightSim.SP_SEL]
	if k >= sp.size() or (sp[k] as Dictionary).is_empty():
		return false
	var e: Dictionary = sp[k]
	if s[o + FightSim.MOUNTED] != 0 or not FightSim._can_act(s, o) or s[o + FightSim.EXH] > 0 or s[o + FightSim.BACKSTEP_T] > 0 or s[o + FightSim.ROLL_T] >= 0 or s[o + FightSim.SWAP_T] > 0:
		return false
	if s[o + FightSim.SHOT_STATE] == FightSim.Shot.DRAW or s[o + FightSim.SHOT_STATE] == FightSim.Shot.RECOVER:
		return false
	if s[o + FightSim.ATK_STATE] != FightSim.Atk.NONE or s[o + FightSim.PARRY_STATE] != FightSim.Parry.NONE:
		return false
	if s[o + FightSim.SCD0 + k] > 0 or s[o + FightSim.MANA] < int(e["cost"]):
		return false
	s[o + FightSim.MANA] -= int(e["cost"])
	s[o + FightSim.SCD0 + k] = e["cd"]
	s[o + FightSim.CAST_T] = e["cast"]
	s[o + FightSim.CAST_SLOT] = k
	s[o + FightSim.BLOCKING] = 0
	s[o + FightSim.SPELLS] += 1
	return true

static func update(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	for k in 4:
		if s[o + FightSim.SCD0 + k] > 0:
			s[o + FightSim.SCD0 + k] -= 1
	if s[o + FightSim.SKIN_T] > 0:
		s[o + FightSim.SKIN_T] -= 1
	if s[o + FightSim.CAST_T] > 0:
		if s[o + FightSim.ALIVE] == 0 or s[o + FightSim.STUN] > 0:
			s[o + FightSim.CAST_T] = 0
			s[o + FightSim.CAST_SLOT] = -1
		else:
			s[o + FightSim.CAST_T] -= 1
			if s[o + FightSim.CAST_T] <= 0:
				var k2: int = s[o + FightSim.CAST_SLOT]
				s[o + FightSim.CAST_SLOT] = -1
				_fire(s, P, i, k2)
	_eikon(s, P, i)
	_mount(s, P, i)

static func _fire(s: PackedInt64Array, P: Array, i: int, k: int) -> void:
	var o := i * FightSim.F_FIELDS
	var sp: Array = P[i].get("spells", [])
	if k < 0 or k >= sp.size() or (sp[k] as Dictionary).is_empty():
		return
	var e: Dictionary = sp[k]
	s[o + FightSim.FACE] = SimAbilities._tdir(s, i)
	var f: int = s[o + FightSim.FACE]
	match int(e["type"]):
		0:
			FightSim.spawn_proj(s, i, 2, s[o + FightSim.X] + FxMath.COS[f] * 1200000 / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[f] * 1200000 / FxMath.ONE,
				FightSim.HIT_CENTER_Y + 600000, f, e["spd"], 150, 500000, e["raw"], -1, e["elem"], k + 1, 0, 0, 0, false)
		1:
			if SimAbilities._in_reach(s, P, i, e["range"], e["cos_arc"]):
				FightSim._take_hit(s, P, i, 4, e["raw"], 0, -1, 2000, 1000, 0, e["elem"], e["st"])
		2:
			s[o + FightSim.SKIN_T] = e["dur"]

# ---------------- Eikon ----------------
static func eikon_button(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var ek: Dictionary = P[i].get("ek", {})
	if ek.is_empty() or s[o + FightSim.ALIVE] == 0:
		return false
	if s[o + FightSim.EK_T] > 0:
		if s[o + FightSim.MOUNTED] != 0:
			return _special(s, P, i, ek)
		if int(ek["ride"]) != 0:
			return remount(s, P, i)
		return false
	if s[o + FightSim.METER] < FightSim.METER_MAX or s[o + FightSim.STUN] > 0:
		return false
	if int(ek["ride"]) != 0:
		if s[o + FightSim.ATK_STATE] != FightSim.Atk.NONE or s[o + FightSim.ROLL_T] >= 0 or s[o + FightSim.SWAP_T] > 0:
			return false
		s[o + FightSim.MOUNTED] = 1
		s[o + FightSim.MSTANCE] = MOUNT_STANCE
		s[o + FightSim.MDASH_T] = 0
		s[o + FightSim.EK_X] = s[o + FightSim.X]
		s[o + FightSim.EK_Z] = s[o + FightSim.Z]
	else:
		var side := (s[o + FightSim.FACE] - 64) & 255 # facing × UP = derecha
		s[o + FightSim.EK_X] = s[o + FightSim.X] + FxMath.COS[side] * 3000000 / FxMath.ONE
		s[o + FightSim.EK_Z] = s[o + FightSim.Z] + FxMath.SIN[side] * 3000000 / FxMath.ONE
	s[o + FightSim.EK_T] = ek["life"]
	s[o + FightSim.EK_HP] = ek["hp"]
	s[o + FightSim.EK_CD] = ek["cd0"]
	s[o + FightSim.EK_SPC] = 0
	s[o + FightSim.METER] = 0
	s[o + FightSim.SUMMONS] += 1
	return true

static func remount(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.MOUNTED] != 0 or s[o + FightSim.EK_T] <= 0 or s[o + FightSim.STUN] > 0 or s[o + FightSim.ATK_STATE] != FightSim.Atk.NONE or s[o + FightSim.ROLL_T] >= 0:
		return false
	if FxMath.length(s[o + FightSim.X] - s[o + FightSim.EK_X], s[o + FightSim.Z] - s[o + FightSim.EK_Z]) > MOUNT_REACH:
		return false
	s[o + FightSim.MOUNTED] = 1
	s[o + FightSim.MSTANCE] = MOUNT_STANCE
	s[o + FightSim.X] = s[o + FightSim.EK_X]
	s[o + FightSim.Z] = s[o + FightSim.EK_Z]
	return true

static func dismount(s: PackedInt64Array, P: Array, i: int, forced: bool) -> void:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.MOUNTED] == 0:
		return
	s[o + FightSim.MOUNTED] = 0
	s[o + FightSim.EK_X] = s[o + FightSim.X]
	s[o + FightSim.EK_Z] = s[o + FightSim.Z]
	var side := (s[o + FightSim.FACE] - 64) & 255
	s[o + FightSim.X] -= FxMath.COS[side] * DISMOUNT_SIDE / FxMath.ONE
	s[o + FightSim.Z] -= FxMath.SIN[side] * DISMOUNT_SIDE / FxMath.ONE
	s[o + FightSim.VX] = 0
	s[o + FightSim.VZ] = 0
	SimAbilities.clamp_world(s, P, o)
	s[o + FightSim.DISMOUNTS] += 1
	if forced:
		FightSim._apply_stun(s, o, 36)

static func mount_stance_hit(s: PackedInt64Array, P: Array, i: int, amount: int) -> void:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.MOUNTED] == 0 or amount <= 0:
		return
	s[o + FightSim.MSTANCE] = maxi(s[o + FightSim.MSTANCE] - amount, 0)
	s[o + FightSim.MDASH_T] = MOUNT_REGEN_DELAY # (reutilizado: espera de regeneración de la postura de montura)
	if s[o + FightSim.MSTANCE] <= 0:
		s[o + FightSim.MSTANCE] = MOUNT_STANCE
		dismount(s, P, i, true)

static func _mount(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.MOUNTED] == 0:
		return
	if s[o + FightSim.MDASH_T] > 0:
		s[o + FightSim.MDASH_T] -= 1
	else:
		s[o + FightSim.MSTANCE] = mini(s[o + FightSim.MSTANCE] + MOUNT_REGEN, MOUNT_STANCE)

static func _special(s: PackedInt64Array, P: Array, i: int, ek: Dictionary) -> bool:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.EK_SPC] > 0 or s[o + FightSim.STUN] > 0:
		return false
	s[o + FightSim.EK_SPC] = ek["sp_cd"]
	s[o + FightSim.EK_SPECIALS] += 1
	var f: int = s[o + FightSim.FACE]
	var b := FightSim._opp(i)
	match int(ek["special"]):
		1:
			FightSim.spawn_proj(s, i, 2, s[o + FightSim.X] + FxMath.COS[f] * 1800000 / FxMath.ONE, s[o + FightSim.Z] + FxMath.SIN[f] * 1800000 / FxMath.ONE,
				1600000 + int(ek.get("hover", 0)), f, 400000, 150, 700000, ek["sp_dmg"], -1, -1, 0, 0, 0, 0, true)
		2:
			s[o + FightSim.KX] = FxMath.COS[f] * 166667 / FxMath.ONE
			s[o + FightSim.KZ] = FxMath.SIN[f] * 166667 / FxMath.ONE
			if s[b + FightSim.ALIVE] != 0:
				var dx: int = s[b + FightSim.X] - s[o + FightSim.X]
				var dz: int = s[b + FightSim.Z] - s[o + FightSim.Z]
				var l := FxMath.length(dx, dz)
				if l < 4500000 and (l < 500000 or dx * FxMath.COS[f] + dz * FxMath.SIN[f] > 2048 * l):
					if FightSim._take_hit(s, P, i, 4, ek["sp_dmg"], 0, -1, 2000, 1000, 0) == 1:
						FightSim._apply_stun(s, b, 30)
		3:
			if s[b + FightSim.ALIVE] != 0:
				var dx2: int = s[b + FightSim.X] - s[o + FightSim.X]
				var dz2: int = s[b + FightSim.Z] - s[o + FightSim.Z]
				var l2 := FxMath.length(dx2, dz2)
				if l2 < 5500000:
					var r := FightSim._take_hit(s, P, i, 4, ek["sp_dmg"], 0, -1, 2000, 1000, 0)
					if r == 1 or r == 2:
						var kv := 233333 # 14 m/s
						if l2 > 100000:
							s[b + FightSim.KX] = dx2 * kv / l2
							s[b + FightSim.KZ] = dz2 * kv / l2
						else:
							s[b + FightSim.KX] = FxMath.COS[f] * kv / FxMath.ONE
							s[b + FightSim.KZ] = FxMath.SIN[f] * kv / FxMath.ONE
						if r == 1:
							FightSim._apply_stun(s, b, 15)
	return true

## Vida de la invocación, especial en recarga y eikon compañero (persigue y ataca al rival).
static func _eikon(s: PackedInt64Array, P: Array, i: int) -> void:
	var o := i * FightSim.F_FIELDS
	if s[o + FightSim.EK_T] <= 0:
		return
	var ek: Dictionary = P[i].get("ek", {})
	if s[o + FightSim.EK_SPC] > 0:
		s[o + FightSim.EK_SPC] -= 1
	s[o + FightSim.EK_T] -= 1
	if s[o + FightSim.EK_T] <= 0 or s[o + FightSim.ALIVE] == 0 or ek.is_empty():
		s[o + FightSim.EK_T] = 0
		if s[o + FightSim.MOUNTED] != 0:
			dismount(s, P, i, false)
		return
	if s[o + FightSim.MOUNTED] != 0:
		s[o + FightSim.EK_X] = s[o + FightSim.X]
		s[o + FightSim.EK_Z] = s[o + FightSim.Z]
		return
	if int(ek["ride"]) != 0:
		return # montura sin jinete: espera a su dueño (no ataca online)
	var b := FightSim._opp(i)
	if s[o + FightSim.EK_CD] > 0:
		s[o + FightSim.EK_CD] -= 1
	if s[b + FightSim.ALIVE] == 0:
		return
	var dx: int = s[b + FightSim.X] - s[o + FightSim.EK_X]
	var dz: int = s[b + FightSim.Z] - s[o + FightSim.EK_Z]
	var l := FxMath.length(dx, dz)
	if l > int(ek["range_in"]) and l > 0:
		s[o + FightSim.EK_X] += dx * int(ek["move"]) / l
		s[o + FightSim.EK_Z] += dz * int(ek["move"]) / l
	if l <= int(ek["range"]) and s[o + FightSim.EK_CD] <= 0:
		s[o + FightSim.EK_CD] = ek["cd"]
		match int(ek["kind"]):
			0:
				if FightSim._take_hit(s, P, i, 4, ek["dmg"], 0, -1, 2000, 1000, 0) == 1:
					s[o + FightSim.EK_HITS] += 1
			1:
				var face := FxMath.dir_of(dx, dz, 0)
				FightSim.spawn_proj(s, i, 3, s[o + FightSim.EK_X], s[o + FightSim.EK_Z], ek["y"], face, 366667, 150, 700000, ek["dmg"], -1, -1, 0, 0, 0, 0, true)
			_:
				SimAbilities.spawn_hz(s, i, 1, s[o + FightSim.EK_X], s[o + FightSim.EK_Z], 36, ek["range"], ek["dmg"], 40000, 100000, 0)

# ---------------- Fase 6: artes de arma ----------------
## FighterMagic.use_weapon_art: estocada impulsada (dash con x1,5) o torbellino (AoE a 0,3 s).
static func art(s: PackedInt64Array, P: Array, i: int) -> bool:
	var o := i * FightSim.F_FIELDS
	var a: Dictionary = P[i].get("art", {})
	if a.is_empty() or s[o + FightSim.MOUNTED] != 0 or not FightSim._can_act(s, o) or s[o + FightSim.EXH] > 0 or s[o + FightSim.BACKSTEP_T] > 0:
		return false
	if s[o + FightSim.ART_CD] > 0 or s[o + FightSim.ROLL_T] >= 0 or s[o + FightSim.LOADOUT] != FightSim.Load.SWORD:
		return false
	if s[o + FightSim.ATK_STATE] != FightSim.Atk.NONE or s[o + FightSim.PARRY_STATE] != FightSim.Parry.NONE or s[o + FightSim.SWAP_T] > 0 or s[o + FightSim.ST] <= 0:
		return false
	if s[o + FightSim.MANA] < int(a["cost"]):
		return false
	s[o + FightSim.MANA] -= int(a["cost"])
	s[o + FightSim.ART_CD] = a["cd"]
	s[o + FightSim.ARTS] += 1
	s[o + FightSim.BLOCKING] = 0
	FightSim._spend(s, P, i, a["st"])
	if int(a["type"]) == 1:
		s[o + FightSim.DASH_DIR] = SimAbilities._tdir(s, i)
		s[o + FightSim.FACE] = s[o + FightSim.DASH_DIR]
		FightSim._start_attack(s, P, i, SimParams.A_DASH, false)
		s[o + FightSim.ART_K] = a["k"]
	else:
		s[o + FightSim.ART_T] = a["t"]
		SimAbilities.spawn_hz(s, i, 1, s[o + FightSim.X], s[o + FightSim.Z], a["t"], a["r"], a["raw"], 40000, 150000, 0)
	return true

# ---------------- Fase 6: invocaciones golpeables ----------------
## ¿El eikon del rival (compañero o montura sin jinete) está activo y se puede golpear?
static func pet_live(s: PackedInt64Array, P: Array, d: int) -> bool:
	var o := d * FightSim.F_FIELDS
	return s[o + FightSim.EK_T] > 0 and s[o + FightSim.MOUNTED] == 0 and not (P[d].get("ek", {}) as Dictionary).is_empty()

static func pet_in_arc(s: PackedInt64Array, P: Array, att: int, reach: int, cos_arc: int) -> bool:
	var d := 1 - att
	if not pet_live(s, P, d):
		return false
	var o := att * FightSim.F_FIELDS
	var q := d * FightSim.F_FIELDS
	var dx: int = s[q + FightSim.EK_X] - s[o + FightSim.X]
	var dz: int = s[q + FightSim.EK_Z] - s[o + FightSim.Z]
	var l := FxMath.length(dx, dz)
	if l - int(P[d]["ek"]["hr"]) / 2 > reach:
		return false
	if l < 500000:
		return true
	var f: int = s[o + FightSim.FACE]
	return dx * FxMath.COS[f] + dz * FxMath.SIN[f] >= cos_arc * l

## Eikon.take_hit: resta vida sin defensa; a 0 se retira (montura incluida).
static func pet_hit(s: PackedInt64Array, P: Array, att: int, raw: int) -> void:
	var d := 1 - att
	var q := d * FightSim.F_FIELDS
	if not pet_live(s, P, d):
		return
	s[q + FightSim.EK_HP] -= raw
	s[att * FightSim.F_FIELDS + FightSim.PET_HITS] += 1
	if s[q + FightSim.EK_HP] <= 0:
		s[q + FightSim.EK_T] = 0
		s[att * FightSim.F_FIELDS + FightSim.PET_KILLS] += 1

## Proyectil contra el eikon del rival (esfera contra esfera).
static func pet_proj(s: PackedInt64Array, P: Array, att: int, px: int, py: int, pz: int, pr: int) -> bool:
	var d := 1 - att
	if not pet_live(s, P, d):
		return false
	var q := d * FightSim.F_FIELDS
	var ek: Dictionary = P[d]["ek"]
	var ex: int = px - s[q + FightSim.EK_X]
	var ez: int = pz - s[q + FightSim.EK_Z]
	var ey: int = py - int(ek["cy"])
	var r: int = pr + int(ek["hr"])
	return ex * ex + ez * ez + ey * ey < r * r

## Área en el suelo contra el eikon del rival (los voladores no la reciben).
static func pet_aoe(s: PackedInt64Array, P: Array, att: int, x: int, z: int, r: int, raw: int) -> void:
	var d := 1 - att
	if not pet_live(s, P, d) or int(P[d]["ek"].get("fly", 0)) != 0:
		return
	var q := d * FightSim.F_FIELDS
	if FxMath.length(s[q + FightSim.EK_X] - x, s[q + FightSim.EK_Z] - z) <= r:
		pet_hit(s, P, att, raw)
