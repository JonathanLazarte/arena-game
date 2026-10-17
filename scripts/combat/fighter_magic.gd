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
