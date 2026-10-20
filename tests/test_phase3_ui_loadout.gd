extends SceneTree
## Fase 3: Filtrado de loadout por familias de armas y validación estética de UI estilo Elden Ring.
## godot --headless --path . -s res://tests/test_phase3_ui_loadout.gd

var fails := 0

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST FASE 3: FAMILIAS DE ANIMACIÓN Y LOADOUT ---")
	# 1. Familias de armas
	var f_sword: Array = BossAbilities.families_of_weapon("espada_escudo")
	check("espada_ligera" in f_sword and "escudo" in f_sword, "espada_escudo pertenece a espada_ligera y escudo")
	var f_greatsword: Array = BossAbilities.families_of_weapon("espada_larga")
	check("espada_pesada" in f_greatsword, "espada_larga pertenece a espada_pesada")
	var f_bow: Array = BossAbilities.families_of_weapon("arco")
	check("arco" in f_bow, "arco pertenece a arco")

	# 2. Familias de habilidades del catálogo
	var fams_combo: Array = BossAbilities.weapon_families("combo_falso")
	check("espada_pesada" in fams_combo and "martillo" in fams_combo, "combo_falso requiere espada_pesada/martillo (%s)" % [fams_combo])
	var fams_flecha: Array = BossAbilities.weapon_families("flecha_grave")
	check("arco" in fams_flecha, "flecha_grave requiere arco (%s)" % [fams_flecha])
	var fams_estocada: Array = BossAbilities.weapon_families("estocada")
	check("espada_ligera" in fams_estocada and "lanza" in fams_estocada, "estocada requiere espada_ligera/lanza (%s)" % [fams_estocada])

	# 3. Compatibilidad de familias
	check(BossAbilities.is_family_compatible("combo_falso", "espada_larga"), "combo_falso es compatible con espada_larga")
	check(not BossAbilities.is_family_compatible("combo_falso", "arco"), "combo_falso NO es compatible con arco")
	check(BossAbilities.is_family_compatible("flecha_grave", "arco"), "flecha_grave es compatible con arco")
	check(not BossAbilities.is_family_compatible("flecha_grave", "espada_larga"), "flecha_grave NO es compatible con espada_larga")
	check(BossAbilities.is_family_compatible("estocada", "espada_escudo"), "estocada es compatible con espada_escudo")
	check(not BossAbilities.is_family_compatible("estocada", "arco"), "estocada NO es compatible con arco")

	# 4. Spameable / rep_free
	check(BossAbilities.spameable("estocada") == false, "estocada no es spameable")

	# 5. Restricción en GameState
	var gs := root.get_node_or_null("GameState")
	if gs:
		AdminMode.enabled = false
		gs.weapon_id = "arco"
		gs.weapon2_id = ""
		gs.char_boss[gs.character_id] = ["flecha_grave"]
		var can_toggle_heavy: bool = bool(gs.toggle_boss_ability("combo_falso"))
		check(not can_toggle_heavy, "GameState rechaza equipar combo_falso con arco fuera de AdminMode")
		
		# Con AdminMode habilitado se permite
		AdminMode.enabled = true
		var admin_toggle: bool = bool(gs.toggle_boss_ability("combo_falso"))
		check(admin_toggle, "AdminMode permite saltar restricción de familia")
		AdminMode.enabled = false

	print("--- TEST FASE 3: COMPONENTES DE UI ESTILO ELDEN RING ---")
	var theme: Theme = UIKit.theme()
	check(theme != null, "UIKit.theme() se inicializa correctamente")
	var btn: Button = UIKit.button("Iniciar Duelo", 20, UIKit.ORANGE)
	check(btn != null and btn.has_node("Cursor"), "UIKit.button crea cursor integrado")
	var big_btn: Button = UIKit.big_button("EMPEZAR", 32)
	check(big_btn != null and big_btn.has_node("Shine"), "UIKit.big_button crea brillo cálido integrado")

	var ornament := OrnamentLine.new()
	ornament.size = Vector2(400, 20)
	root.add_child(ornament)
	await process_frame
	check(ornament.size.x == 400, "OrnamentLine instanciado con tamaño 400x20")
	ornament.queue_free()

	var panel := CrystalPanel.new()
	panel.size = Vector2(500, 300)
	root.add_child(panel)
	await process_frame
	check(panel.size.x == 500, "CrystalPanel instanciado con degradado y filete dorado")
	panel.queue_free()

	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
