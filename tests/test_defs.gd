extends SceneTree
## Ronda 10: definiciones de personajes y armas.
var fails: int = 0
func _initialize() -> void:
	_run()
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1
func _run() -> void:
	var cs := Catalog.characters()
	var ws := Catalog.weapons()
	check(cs.size() == 5, "5 personajes (%d)" % cs.size())
	check(ws.size() == 7, "7 tipos de arma (%d)" % ws.size())
	var ids := {}
	for w in ws:
		ids[w.id] = true
		var l := w.attack(false)
		var h := w.attack(true)
		check(w.ranged or (h["damage"] > l["damage"] and h["windup"] > l["windup"] and w.reach_foot > 0.0), "%s: fuerte > ligero, alcance > 0" % w.id)
		check(l.has_all(["damage", "windup", "active", "recovery", "stamina"]), "%s: datos de ataque completos" % w.id)
	for k: String in ["espada_larga", "espada_escudo", "hacha_2m", "dagas", "lanza", "arco"]:
		check(ids.has(k), "existe el arma " + k)
	check(not Catalog.weapon("espada_larga").allows_shield and Catalog.weapon("espada_escudo").allows_shield and Catalog.weapon("lanza").allows_shield, "escudo: espada y escudo / lanza sí, espada larga no")
	for c in cs:
		check(c.display_name != "" and c.role != "" and c.description != "" and c.passive_name != "", "%s: nombre, rol, descripción y pasiva" % c.id)
		check(c.allows(c.default_weapon) and ResourceLoader.exists(c.model_path) and ResourceLoader.exists(c.texture_path), "%s: arma por defecto compatible y modelo existe" % c.id)
		for wid: String in c.weapons:
			check(ids.has(wid), "%s: arma %s existe" % [c.id, wid])
		check(Catalog.weapons_for(c).size() == c.weapons.size(), "%s: filtro de armas por rol" % c.id)
	check(not Catalog.character("arquero").allows("hacha_2m") and Catalog.character("berserker").allows("hacha_2m"), "el arquero no puede usar hacha; el berserker sí")
	# Visual: cada combinación personaje+arma se construye y su estado de ataque usa la anim del arma
	for c in cs:
		for w in Catalog.weapons_for(c):
			var kv := KnightVisual.new()
			root.add_child(kv)
			kv.setup(Color.BLUE, c, w)
			var mw := w if not w.ranged else Catalog.weapon("dagas")
			check(kv.sword != null and kv.ap.has_animation(kv.states["heavy"]) and kv.ap.has_animation(kv.states["light0"]) and kv.states["light0"] == (KnightVisual.MX + KnightVisual.MX_WEAPON[mw.id]["light0"] if KnightVisual.MX_WEAPON.get(mw.id, {}).has("light0") else (mw.combo_hit(0, c).clip_name() if not mw.combo.is_empty() else mw.anim_light[0])) and kv.ap.has_animation(kv.states["light1"]) and kv.ap.has_animation(kv.states["light2"]), "visual %s + %s (clips del combo)" % [c.id, w.id])
			kv.free()
	print("RESULT: ", "OK" if fails == 0 else "FALLO", " (%d fallos)" % fails)
	quit(1 if fails > 0 else 0)
