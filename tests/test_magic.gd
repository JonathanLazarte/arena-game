extends SceneTree
## Ronda 21: parry desactivado montado, botón «Objetivo» contextual, magia de eikon en ranuras,
## artes de arma intercambiables y migración v7 -> v8.
## godot --headless --path . -s res://tests/test_magic.gd

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
	# --- Datos ---
	var base := Attributes.start_for("caballero")
	check(EikonSpells.slots_for(base) == 2, "2 ranuras de hechizo base")
	var mage := base.duplicate()
	mage["sabiduria"] = 18
	check(EikonSpells.slots_for(mage) == 3, "Sabiduría 18: 3 ranuras")
	mage["devocion"] = 30
	check(EikonSpells.slots_for(mage) == 4, "Devoción 30: 4 ranuras (máximo)")
	check(EikonSpells.available(["fenix"]) == ["chispa"] and EikonSpells.available(["fenix", "lobo", "grifo", "golem"]).size() == 4, "cada eikon poseído enseña su hechizo")
	var a0 := Attributes.derived("caballero", base)
	var hi := base.duplicate()
	hi["sabiduria"] = 40
	check(EikonSpells.power("chispa", Attributes.derived("caballero", hi)) > EikonSpells.power("chispa", a0), "la Sabiduría potencia los hechizos ofensivos")
	var dv := base.duplicate()
	dv["devocion"] = 40
	check(EikonSpells.power("piel_de_piedra", Attributes.derived("caballero", dv)) > EikonSpells.power("piel_de_piedra", a0), "la Devoción potencia las protecciones")
	check(EikonSpells.sanitize(["chispa", "chispa", "aliento_helado"], 2, ["fenix"]) == ["chispa", ""], "sin repetidos ni hechizos de eikons que no tienes")
	# --- Progreso ---
	gs.save_path = "user://test_magic.cfg"
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	check(gs.equipped_spells().size() == 2, "ranuras según atributos")
	check(gs.set_spell(0, "chispa") and not gs.set_spell(1, "aliento_helado"), "solo hechizos de tus eikons")
	gs.owned_eikons.append("lobo")
	check(gs.cycle_spell(1) == "chispa" or gs.equipped_spells()[1] != "", "el botón de ranura cicla hechizos")
	gs.set_spell(0, "chispa")
	gs.set_spell(1, "aliento_helado")
	gs.set_spell(1, "chispa")
	check(gs.equipped_spells() == ["aliento_helado", "chispa"], "equipar uno que ya estaba lo intercambia")
	check(gs.weapon_art() == "estocada_impulsada", "arte inicial: Estocada impulsada")
	check(not gs.set_weapon_art(gs.weapon_id, "torbellino"), "no se equipa un arte que no tienes")
	gs.oro = 1000
	check(gs.buy_art("torbellino") and gs.oro == 700 and not gs.buy_art("torbellino"), "Torbellino se compra una vez (300 oro)")
	check(gs.cycle_weapon_art() == "torbellino", "arte intercambiable desde la colección")
	gs.save_loadout()
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.weapon_art() == "torbellino" and "torbellino" in gs.owned_arts and gs.equipped_spells() == ["aliento_helado", "chispa"], "hechizos y artes persisten (v8)")
	# --- Migración v7 -> v8 ---
	var c := ConfigFile.new()
	c.load(gs.save_path)
	c.set_value("meta", "version", 7)
	c.erase_section("artes")
	c.set_value("slot_0", "spells", null)
	c.set_value("loadout", "eikon_id", "fenix")
	c.save(gs.save_path)
	gs.reset_defaults()
	gs.load_loadout()
	check(gs.magic_migrated and gs.equipped_spells()[0] == "chispa" and gs.owned_arts == ["estocada_impulsada"], "v7→v8: hechizo de tu eikon equipado y arte inicial")
	var c2 := ConfigFile.new()
	c2.load(gs.save_path)
	check(int(c2.get_value("meta", "version", 0)) == GameState.SAVE_VERSION, "se reescribe con la versión actual")
	# --- Lobby ---
	gs.owned_eikons = ["fenix", "lobo", "golem"]
	gs.oro = 1000
	change_scene_to_file("res://scenes/lobby.tscn")
	await process_frame
	await process_frame
	var lobby := current_scene
	lobby.set_tab("Eikons")
	await process_frame
	var sb := lobby.find_child("Spell_0", true, false) as Button
	check(sb != null and "Ranura 1" in sb.text, "Eikons: ranuras de hechizo en el menú")
	var before := String(gs.equipped_spells()[0])
	sb.pressed.emit()
	await process_frame
	check(String(gs.equipped_spells()[0]) != before, "tocar la ranura cambia el hechizo")
	lobby.set_tab("Armas")
	await process_frame
	var ab := lobby.find_child("ArtBtn", true, false) as Button
	check(ab != null and "Arte:" in ab.text, "Armas: botón de arte de arma")
	lobby.shop_cat = "Artes"
	lobby.set_tab("Tienda")
	await process_frame
	check(lobby.find_child("Buy_art_torbellino", true, false) != null, "Tienda: categoría Artes")
	# --- Arena ---
	gs.reset_defaults()
	gs.choose_first_character("caballero")
	gs.owned_eikons = ["fenix", "lobo", "golem"]
	gs.spells = ["aliento_helado", "chispa"]
	gs.from_lobby = true
	gs.random_rival = false
	Arena.start_mounted = true
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	arena.ai.enabled = false
	arena.time_left = 1.0e9
	await create_timer(3.2).timeout
	var p := arena.player
	var e := arena.enemy
	await process_frame
	check(p.mounted, "empieza montado")
	check(not p.parry() and not p.is_parrying(), "montado: el parry no se activa")
	check(not arena.hud.btns["parry"].visible, "montado: botón Parry oculto")
	check(not arena.hud.btns["spell"].visible and not p.cast_spell(), "montado: sin hechizos (se usan los del eikon montado)")
	p.meter = 0.0
	await process_frame
	await process_frame
	var hx: Dictionary = arena.hud.btns
	var sp: Vector2 = (hx["summon"] as TouchScreenButton).position
	var js: Vector2 = arena.hud.joystick.position
	check(absf(sp.x - js.x) < 60.0 and sp.y < js.y - 100.0, "Eikon encima del joystick (lado izquierdo)")
	check(not hx["special"].visible and not p.special(), "montado: botón Arte oculto y sin arte")
	check(not hx["summon"].visible, "medidor vacío: botón Eikon oculto")
	check(not hx["mount"].visible, "sin eikon activo: botón Montar oculto")
	p.meter = Fighter.METER_MAX
	await process_frame
	await process_frame
	check(hx["summon"].visible, "medidor lleno: botón Eikon visible")
	p.meter = 0.0
	check(arena.controller.targets().size() == 1 and not arena.hud.btns["target_next"].visible, "1 objetivo: botón «Objetivo» oculto")
	var dummy := Node3D.new()
	var gd := GDScript.new()
	gd.source_code = "extends Node3D\nvar team := 1\nvar alive := true\nvar hit_radius := 0.5\nfunc get_hit_center() -> Vector3: return global_position\nfunc take_hit(a: float, f: Node3D, k: String) -> String: return \"hit\"\n"
	gd.reload()
	dummy.set_script(gd)
	dummy.add_to_group("damageable")
	arena.add_child(dummy)
	dummy.global_position = Vector3(30, 0, 30)
	await process_frame
	await process_frame
	check(arena.controller.can_cycle_target() and arena.hud.btns["target_next"].visible, "2 objetivos: botón «Objetivo» visible")
	dummy.alive = false
	await process_frame
	await process_frame
	check(not arena.hud.btns["target_next"].visible, "vuelve a ocultarse con 1 objetivo")
	dummy.queue_free()
	p.dismount(false)
	await create_timer(0.3).timeout
	check(not p.mounted and arena.hud.btns["parry"].visible, "a pie: vuelve el botón Parry")
	check(arena.hud.btns["special"].visible, "a pie: vuelve el botón Arte")
	p.stamina = p.stamina_max
	check(p.parry(), "a pie: parry funciona")
	await create_timer(1.0).timeout
	check(arena.hud.btns["spell"].visible and arena.hud.btns["spell_next"].visible, "a pie: botones Hechizo y ↻")
	# Cono helado
	arena.controller.set_physics_process(false)
	e.poise_max = 1e6
	e.poise = 1e6
	e.global_position = p.global_position + p.facing * 3.5
	e.velocity = Vector3.ZERO
	await process_frame
	var hp0 := e.health
	p.energy = p.energy_max
	p.parry_state = Fighter.Parry.NONE # fin de la recuperación del parry de arriba
	check(p.current_spell() == "aliento_helado" and p.cast_spell(), "lanza Aliento helado")
	check(not p.cast_spell(), "no se encadena durante el lanzamiento")
	await create_timer(0.7).timeout
	check(e.health < hp0 and e.status_fx.buildup.get("congelacion", 0.0) > 0.0, "el cono daña (%.1f) y acumula congelación" % (hp0 - e.health))
	check(p.spell_cd_left("aliento_helado") > 0.0, "enfriamiento propio del hechizo")
	check(p.cycle_spell() == "chispa", "↻ pasa a la siguiente ranura")
	var hp1 := e.health
	p.energy = p.energy_max
	e.global_position = p.global_position + p.facing * 8.0
	check(p.cast_spell(), "lanza Chispa ígnea")
	await create_timer(1.2).timeout
	check(e.health < hp1, "el proyectil de fuego impacta (%.1f)" % (hp1 - e.health))
	check(p.spells_cast == 2, "contador de hechizos")
	# Piel de piedra (buff)
	p.set_magic(["piel_de_piedra"], "estocada_impulsada")
	p.energy = p.energy_max
	var dmg_a := _hit(p, e)
	check(p.cast_spell(), "lanza Piel de piedra")
	await create_timer(0.7).timeout
	check(p.stoneskin_t > 0.0, "Piel de piedra activa")
	var dmg_b := _hit(p, e)
	check(dmg_b < dmg_a * 0.9, "Piel de piedra reduce el daño (%.2f → %.2f)" % [dmg_a, dmg_b])
	# Artes de arma
	p.energy = p.energy_max
	p.stamina = 100.0
	e.global_position = p.global_position + p.facing * 3.0
	await process_frame
	var hp2 := e.health
	check(p.special(), "Habilidad sin habilidad propia: arte Estocada impulsada")
	check(is_equal_approx(p._art_mult, 1.5) and p.arts_used == 1, "la estocada lleva x1,5")
	await create_timer(1.2).timeout
	check(e.health < hp2, "la estocada impacta (%.1f)" % (hp2 - e.health))
	check(not p.special(), "enfriamiento del arte")
	p.set_magic([], "torbellino")
	p.art_cd = 0.0
	p.energy = p.energy_max
	p.stamina = 100.0
	e.global_position = p.global_position + p.facing.cross(Vector3.UP) * 2.0 # al costado
	await process_frame
	var hp3 := e.health
	check(p.special(), "arte Torbellino")
	await create_timer(0.8).timeout
	check(e.health < hp3, "Torbellino golpea a los costados (%.1f)" % (hp3 - e.health))
	await create_timer(0.2).timeout
	check(not arena.hud.btns["spell"].visible, "sin hechizos equipados: botón Hechizo oculto")
	p.meter = Fighter.METER_MAX
	check(p.summon(), "invoca su eikon")
	await process_frame
	await process_frame
	check(arena.hud.btns["mount"].visible and p.has_active_eikon(), "con eikon activo: botón Montar visible")
	print("\n%s (%d fallos)" % ["OK" if fails == 0 else "FALLÓ", fails])
	Arena.start_mounted = false
	quit(1 if fails > 0 else 0)

func _hit(p: Fighter, e: Fighter) -> float:
	var h := p.health
	p.stun = 0.0
	p.take_hit(10.0, e, "melee")
	p.stun = 0.0
	p.poise = p.poise_max
	var d := h - p.health
	p.health = p.max_health
	return d
