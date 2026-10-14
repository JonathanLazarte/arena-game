extends SceneTree
## Ronda 20: herrería (+0..+10, piedras de forja, infusiones), Herrero en el lobby,
## recompensas, Tienda de materiales, rival mejorado y migración v6 -> v7.
## godot --headless --path . -s res://tests/test_smithing.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var cab := Catalog.character("caballero")
	var at := Attributes.start_for("caballero")
	# --- Datos y fórmulas ---
	check(Smithing.stone_for(1) == "piedra_1" and Smithing.stone_for(3) == "piedra_1" and Smithing.stone_for(4) == "piedra_2" and Smithing.stone_for(7) == "piedra_3" and Smithing.stone_for(10) == "piedra_antigua", "piedras por tramo: I (+1..3), II (+4..6), III (+7..9), antigua (+10)")
	check(Smithing.stone_count(1) == 1 and Smithing.stone_count(3) == 3 and Smithing.stone_count(4) == 1 and Smithing.stone_count(10) == 1, "1-2-3 piedras por nivel del tramo")
	check(Smithing.gold_cost(1) < Smithing.gold_cost(5) and Smithing.gold_cost(5) < Smithing.gold_cost(10), "el oro sube por nivel")
	var w := Catalog.weapon("espada_escudo")
	check(Smithing.effective(w, 0, "") == w, "+0 normal = el recurso base")
	var w5 := Smithing.effective(w, 5, "")
	check(w5 != w and w.upgrade_level == 0 and w5.upgrade_level == 5, "la mejora no toca el recurso compartido")
	check(is_equal_approx(w5.upgrade_dmg_mult, 1.3) and w5.scaling["fuerza"] > w.scaling["fuerza"], "+5: +30 % daño base y más escalado")
	check(w5.display_name == "Espada y escudo +5", "nombre «+5» (%s)" % w5.display_name)
	var ar0: float = EquipStats.attack_rating(cab, w, at)["total"]
	var ar5: float = EquipStats.attack_rating(cab, w5, at)["total"]
	var ar10: float = EquipStats.attack_rating(cab, Smithing.effective(w, 10, ""), at)["total"]
	check(ar5 > ar0 * 1.25 and ar10 > ar5, "el Ataque sube (%.1f → %.1f → %.1f)" % [ar0, ar5, ar10])
	var strong := at.duplicate()
	strong["fuerza"] = 40
	var gain0: float = EquipStats.attack_rating(cab, w, strong)["total"] / ar0
	var gain5: float = EquipStats.attack_rating(cab, w5, strong)["total"] / ar5
	check(gain5 > gain0, "la mejora también sube el escalado (x%.2f vs x%.2f con FUE 40)" % [gain5, gain0])
	var hv := Smithing.effective(w, 0, "pesado")
	var sh := Smithing.effective(w, 0, "afilado")
	check(hv.scaling["fuerza"] > w.scaling["fuerza"] and hv.scaling["destreza"] < w.scaling["destreza"], "Pesado: más FUE, menos DES")
	check(sh.scaling["destreza"] > w.scaling["destreza"] and sh.scaling["fuerza"] < w.scaling["fuerza"], "Afilado: más DES, menos FUE")
	for inf: String in ["sangrante", "venenoso", "gelido"]:
		var e := Smithing.effective(w, 2, inf)
		var k: String = {"sangrante": "sangrado", "venenoso": "veneno", "gelido": "congelacion"}[inf]
		check(float(e.status.get(k, 0.0)) > 15.0 and e.upgrade_dmg_mult < 1.12, "%s: acumula %s (%.1f) a cambio de algo de daño" % [inf, k, e.status.get(k, 0.0)])
	var dag := Smithing.effective(Catalog.weapon("dagas"), 5, "")
	check(dag.status["sangrado"] > Catalog.weapon("dagas").status["sangrado"], "las dagas mejoradas sangran más")
	check(Smithing.rival_level(1) == 0 and Smithing.rival_level(5) == 2 and Smithing.rival_level(30) == 10, "nivel de mejora del rival según su nivel")
	# --- Progreso ---
	gs.save_path = "user://test_smithing.cfg"
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	gs.oro = 0
	check(gs.can_upgrade("espada_escudo") == "oro", "sin oro no se mejora")
	gs.oro = 100000
	check(gs.can_upgrade("espada_escudo") == "piedra", "sin piedras no se mejora")
	check(gs.can_upgrade("hacha_2m") == "no", "solo armas que tienes")
	gs.add_material("piedra_1", 6)
	var oro0: int = gs.oro
	check(gs.upgrade_weapon("espada_escudo") == "ok" and gs.weapon_level("espada_escudo") == 1 and gs.material("piedra_1") == 5 and gs.oro == oro0 - Smithing.gold_cost(1), "mejora a +1 (oro y 1 piedra)")
	check(gs.upgrade_weapon("espada_escudo") == "ok" and gs.upgrade_weapon("espada_escudo") == "ok" and gs.material("piedra_1") == 0 and gs.weapon_level("espada_escudo") == 3, "+3 gasta 1+2+3 piedras I")
	check(gs.can_upgrade("espada_escudo") == "piedra", "+4 pide Piedra II")
	check(gs.buy_stone("piedra_2") == "nivel", "la Piedra II requiere nivel de cuenta")
	check(gs.buy_stone("piedra_1") == "ok" and gs.material("piedra_1") == 1, "comprar Piedra I en la Tienda")
	check(gs.infuse("espada_escudo", "sangrante") == "ok" and gs.weapon_infusion("espada_escudo") == "sangrante", "infusión Sangrante")
	check(gs.eff_weapon("espada_escudo").display_name == "Espada y escudo sangrante +3", "nombre del arma infusionada (%s)" % gs.eff_weapon("espada_escudo").display_name)
	check(gs.sheet()["resist"].size() > 0, "la ficha usa el arma mejorada")
	# Recompensas
	var m0: int = gs.material("piedra_1")
	var res: Dictionary = gs.apply_match_result({"won": true, "rounds": 2, "lost_rounds": 0, "hits": 5, "parries": 0, "difficulty": "facil"})
	check(gs.material("piedra_1") == m0 + 2 and res["stones"]["piedra_1"] == 2, "ganar da 2 Piedras I")
	m0 = gs.material("piedra_1")
	gs.apply_match_result({"won": false, "rounds": 0, "lost_rounds": 2, "hits": 1, "parries": 0, "difficulty": "facil"})
	check(gs.material("piedra_1") == m0 + 1, "perder da 1 Piedra I")
	# Persistencia
	gs.save_loadout()
	var lv: int = gs.weapon_level("espada_escudo")
	var mats: Dictionary = gs.materials.duplicate()
	gs.weapon_up = {}
	gs.weapon_inf = {}
	gs.materials = {}
	gs.load_loadout()
	check(gs.weapon_level("espada_escudo") == lv and gs.weapon_infusion("espada_escudo") == "sangrante" and gs.materials == mats and gs.migrated_from == 0, "niveles, infusiones y materiales se guardan (v7)")
	# --- Migración v6 -> v7 ---
	var cfg := ConfigFile.new()
	cfg.load(gs.save_path)
	cfg.set_value("meta", "version", 6)
	cfg.erase_section("herreria")
	cfg.save(gs.save_path)
	gs.load_loadout()
	check(gs.migrated_from == 6 and gs.smith_migrated and gs.weapon_level("espada_escudo") == 0 and gs.material("piedra_1") == 3, "v6 -> v7: armas a +0 y 3 Piedras I de bienvenida")
	var c2 := ConfigFile.new()
	c2.load(gs.save_path)
	check(int(c2.get_value("meta", "version")) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 8, "se reescribe con la versión actual")
	check(gs.character_id == "caballero" and gs.armor_eq.size() > 0, "la migración conserva personaje y armadura")
	# --- Herrero en el lobby (clics reales) ---
	gs.oro = 100000
	gs.add_material("piedra_1", 3)
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.set_tab("Herrero")
	await process_frame
	var up := lobby.find_child("SmithUpgrade", true, false) as Button
	check(up != null and not up.disabled, "Herrero: botón Mejorar")
	check("→" in lobby.detail.text and "Ataque" in lobby.detail.text, "Herrero: Ataque antes → después")
	up.pressed.emit()
	await process_frame
	check(gs.weapon_level("espada_escudo") == 1, "Mejorar desde el Herrero (+1)")
	var ib := lobby.find_child("Inf_gelido", true, false) as Button
	ib.pressed.emit()
	await process_frame
	check(gs.weapon_infusion("espada_escudo") == "gelido", "infusión Gélida desde el Herrero")
	check("Congelación" in lobby.detail.text, "el Herrero muestra el estado del arma")
	lobby.set_tab("Tienda")
	lobby.shop_cat = "Materiales"
	lobby._refresh_all(false)
	await process_frame
	var bs := lobby.find_child("Buy_stone_piedra_1", true, false) as Button
	var p1: int = gs.material("piedra_1")
	bs.pressed.emit()
	check(gs.material("piedra_1") == p1 + 1, "Tienda · Materiales: comprar piedra")
	# --- Rival con arma mejorada ---
	gs.account_xp = 99999
	gs.char_xp["caballero"] = 99999
	gs.from_lobby = true
	gs.random_rival = true
	Arena.start_mounted = false
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	var rl := Smithing.rival_level(gs.char_level())
	check(arena.enemy.weapon.upgrade_level == rl and rl > 0, "el rival lleva el arma a +%d (nivel %d)" % [rl, gs.char_level()])
	check(arena.player.weapon.infusion == "gelido" and arena.player.weapon.upgrade_level == 1, "el jugador entra con su arma mejorada")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
