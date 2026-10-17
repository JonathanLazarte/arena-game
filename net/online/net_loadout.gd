class_name NetLoadout
extends RefCounted
## Equipo del lobby como datos puros para enviarlo al rival y reconstruir los dos Fighter igual en
## ambos pares (el params_checksum del bake lo verifica). Solo ids, niveles y números: nada de
## recursos ni rutas. Fase 4: también eikon, hechizos, arte, sello y habilidades de jefe (el bake los cubre).
const MAX_LEVEL := 99

static func from_game_state(gs: Node) -> Dictionary:
	if gs == null:
		return {}
	var wl := func(id: String) -> Array: return [id, int(gs.weapon_level(id)), String(gs.weapon_infusion(id))] if id != "" else ["", 0, ""]
	return {
		"name": String(gs.display_name_with_title()),
		"char": String(gs.character_id),
		"w": wl.call(String(gs.weapon_id)),
		"w2": wl.call(String(gs.weapon2_id)),
		"lh": wl.call(String(gs.left_hand_id)),
		"level": int(gs.char_level()),
		"skills": Array(gs.char_skills()).duplicate(),
		"attrs": Dictionary(gs.char_attrs()).duplicate(),
		"armor": Dictionary(gs.armor_eq).duplicate(),
		"trinkets": Array(gs.equipped_trinkets()).duplicate(),
		"eikon": String(gs.eikon_id),
		"spells": Array(gs.equipped_spells()).duplicate(),
		"art": String(gs.weapon_art()),
		"seal": String(gs.equipped_eikon_seal),
		"boss": Array(gs.boss_abilities()).duplicate(),
	}

static func _strs(v: Variant, n: int) -> Array:
	var out: Array = []
	if v is Array:
		for x in (v as Array).slice(0, n): out.append(String(x).left(40))
	return out

## Eikon, magia y jefe en un Fighter ya creado (ambos pares igual). Llamar antes de add_child.
static func apply_extras(f: Fighter, a: Dictionary) -> void:
	f.eikon = load(String(a.get("eikon_path", Catalog.EIKONS["fenix"])))
	f.set_magic(a.get("spells", []), String(a.get("art", "")), String(a.get("seal", "")))
	f.set_boss_abilities(a.get("boss", []))

static func _weapon(e: Variant) -> WeaponDef:
	if not (e is Array) or (e as Array).size() < 3 or String(e[0]) == "":
		return null
	var w := Catalog.weapon(String(e[0]))
	if w.id != String(e[0]):
		return null
	return Smithing.effective(w, clampi(int(e[1]), 0, Smithing.MAX_LEVEL), String(e[2]))

## Argumentos de Arena._make_fighter (cd, wd, skills, attrs, equipo) o {} si no hay equipo válido.
static func fighter_args(lo: Dictionary) -> Dictionary:
	if lo.is_empty() or not lo.has("char"):
		return {}
	var cd := Catalog.character(String(lo["char"]))
	var wd := _weapon(lo.get("w", []))
	if wd == null:
		wd = Catalog.weapon("espada_escudo")
	var w2_id := String((lo.get("w2", [""]) as Array)[0]) if lo.get("w2") is Array else ""
	var lh_id := String((lo.get("lh", [""]) as Array)[0]) if lo.get("lh") is Array else ""
	var w2 := _weapon(lo.get("w2", [])) if w2_id != "escudo" else null
	if w2 != null and not w2.ranged: w2 = null
	var off := _weapon(lo.get("lh", [])) if lh_id != "escudo" else null
	if off != null and (off.ranged or off.two_handed): off = null
	var attrs := {}
	var la: Variant = lo.get("attrs", {})
	if la is Dictionary:
		for k: Variant in la: attrs[String(k)] = clampi(int(la[k]), 0, MAX_LEVEL)
	var armor := {}
	var lar: Variant = lo.get("armor", {})
	if lar is Dictionary:
		for k: Variant in lar: armor[String(k)] = String(lar[k])
	var skills: Array = []
	for v in (lo.get("skills", []) if lo.get("skills") is Array else []): skills.append(String(v))
	var trinkets: Array = []
	for v in (lo.get("trinkets", []) if lo.get("trinkets") is Array else []): trinkets.append(String(v))
	return {"name": String(lo.get("name", "Rival")).left(32), "cd": cd, "wd": wd, "skills": skills, "attrs": attrs,
		"eqp": {"level": clampi(int(lo.get("level", 1)), 1, MAX_LEVEL), "armor": armor, "w2": w2, "left_hand": lh_id,
			"offhand": off, "shield": w2_id == "escudo", "trinkets": trinkets},
		"eikon_path": Catalog.EIKONS.get(String(lo.get("eikon", "fenix")), Catalog.EIKONS["fenix"]),
		"spells": _strs(lo.get("spells", []), 4), "art": String(lo.get("art", "")).left(40),
		"seal": String(lo.get("seal", "")).left(40), "boss": _strs(lo.get("boss", []), 3)}
