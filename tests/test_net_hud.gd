extends SceneTree
## Fase 6: botones táctiles de jefe/magia/eikon/montura/arte (y ciclos) llegan a la sim online como bits.
## godot --headless --path . -s res://tests/test_net_hud.gd
var fails := 0
func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var hud := HUD.new()
	root.add_child(hud)
	await process_frame
	hud.online_mode = true
	var want := {"boss": FightSim.IN_BOSS, "boss_variation": FightSim.IN_BOSS_VAR, "spell": FightSim.IN_SPELL,
		"spell_next": FightSim.IN_SPELL_NEXT, "summon": FightSim.IN_EIKON, "special": FightSim.IN_ART, "mount": FightSim.IN_MOUNT}
	for a: String in want:
		check(hud.btns.has(a) and (hud.btns[a] as TouchScreenButton).action == a, "botón táctil «%s» genera la acción" % a)
		var v := SimMatch.extra_buttons_from(func(x: String) -> bool: return x == a)
		check(v == int(want[a]), "acción %s → bit %d" % [a, want[a]])
	# el botón ▶ (siguiente habilidad de jefe) online pulsa la acción boss_next
	var sm := SimMatch.new()
	hud.boss_next_btn.pressed.emit()
	check(Input.is_action_pressed("boss_next") and (sm.extra_buttons() & FightSim.IN_BOSS_NEXT) != 0, "▶ online → IN_BOSS_NEXT")
	await create_timer(0.3).timeout
	check(not Input.is_action_pressed("boss_next"), "▶ se suelta solo (flanco único)")
	# toque real sobre el botón: Input.action_press como haría TouchScreenButton
	Input.action_press("special")
	check((sm.extra_buttons() & FightSim.IN_ART) != 0, "«Habilidad» online → arte del arma")
	Input.action_release("special")
	sm.free()
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
