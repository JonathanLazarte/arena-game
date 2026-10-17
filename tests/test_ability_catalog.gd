extends SceneTree
## Cargador/validador del catálogo de habilidades (net/sim/ability_catalog.gd, docs/abilities_guide.md).
## godot --headless --path . -s res://tests/test_ability_catalog.gd
const AC := preload("res://net/sim/ability_catalog.gd")
const EXAMPLE := "res://data/abilities/catalog.example.json"
var fails := 0
var base: Dictionary

func check(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _rules(res: Dictionary, key: String = "errors") -> Array:
	var out: Array = []
	for e: Dictionary in res[key]:
		out.append(e["rule"])
	return out

func _has(res: Dictionary, rule: String, path_prefix: String = "", key: String = "errors") -> bool:
	for e: Dictionary in res[key]:
		if e["rule"] == rule and String(e["path"]).begins_with(path_prefix):
			return true
	return false

func _mut(f: Callable) -> Dictionary:
	var d: Dictionary = base.duplicate(true)
	f.call(d)
	return AC.load_data(d)

func _expect(rule: String, f: Callable, label: String, path_prefix: String = "") -> void:
	var r := _mut(f)
	check(not r["ok"] and _has(r, rule, path_prefix), "%s → %s%s (obtuvo %s)" % [label, rule, " en " + path_prefix if path_prefix != "" else "", str(_rules(r))])

func _ab(d: Dictionary, id: String) -> Dictionary:
	for a: Dictionary in d["abilities"]:
		if a["id"] == id: return a
	return {}

func _run() -> void:
	# --- ejemplo válido
	var res: Dictionary = AC.load_file(EXAMPLE)
	check(res["ok"] and (res["errors"] as Array).is_empty(), "el catálogo de ejemplo valida sin errores %s" % AC.format_issues(res))
	check((res["warnings"] as Array).is_empty(), "el catálogo de ejemplo no tiene avisos")
	var b: Dictionary = res["baked"]
	check((b["abilities"] as Array).size() == 5 and (b["presets"] as Array).size() == 2, "5 habilidades y 2 presets horneados")
	var f := FileAccess.open(EXAMPLE, FileAccess.READ)
	base = JSON.parse_string(f.get_as_text())
	# --- horneado: unidades e índices
	var hz: Dictionary = b["abilities"][int(b["ability_index"]["hachazo_penitente"])]
	var st: Dictionary = hz["steps"][0]
	var hb: Dictionary = st["hitboxes"][0]
	check(hb["dmg"] == 40000 and hb["stun"] == 40000 and hb["blockable"] == 0, "daño y fuerza en milésimas (40 → 40000), imbloqueable")
	check(hb["shape"]["r"] == 3000000 and hb["shape"]["cos_half"] == int(round(cos(deg_to_rad(55.0)) * 4096)), "radio en µm y arco como coseno del medio arco ×4096")
	check(st["movement"]["speed"] == 116667 and st["movement"]["max"] == 1400000, "velocidad µm/tick (7 m/s) y tope µm")
	check(st["tracking"]["turn"] == 2607 and st["tracking"]["lock"] == 66, "giro en mili-rumbos/tick (220°/s) y tick de bloqueo")
	check(hz["cost"]["stamina"] == 26000 and hz["cooldown"] == 420 and hz["uses_global_cd"] == 1, "costo en milésimas, recarga en ticks")
	check(hz["interrupt_mask"] == 1 << AC.INTERRUPTS.find("knockdown"), "interruptible_by como máscara de bits")
	check(st["next"]["default"] == -1 and st["telegraph"]["index"] >= 0, "fin = -1; telegrafía con índice global")
	var mr: Dictionary = b["abilities"][int(b["ability_index"]["martillo_runico"])]
	var br: Dictionary = mr["steps"][1]["branch"]
	check(br["options"][0]["step"] == 2 and br["options"][1]["step"] == 3 and br["default"] == -1, "branch: opciones resueltas a índices de paso")
	check(br["options"][1]["input"] == AC.INPUTS.find("alt") and br["options"][1]["extra_cost"]["stamina"] == 10000, "branch: input alt y costo extra")
	check(mr["steps"][0]["cancel"]["steps"] == [1], "cancel_into resuelto a índices")
	check(mr["ai"]["branch_weights"] == [[2, 55], [3, 45]], "ai.branch_weights ordenado por índice de paso")
	check(b["presets"][1]["abilities"].size() == 2, "preset con 2 habilidades (no hace falta llegar a 3)")
	check(hz["on_interrupt"]["cancel_spawns"] == true and mr["steps"][0]["hitboxes"][0]["parryable"] == 1, "defaults aplicados")
	check((b as Dictionary).is_read_only() and (hz["steps"] as Array).is_read_only() and (hb as Dictionary).is_read_only(), "estructura horneada de solo lectura")
	# --- determinismo
	var r2: Dictionary = AC.load_file(EXAMPLE)
	var r3: Dictionary = AC.load_data(base.duplicate(true))
	check(res["hash"] == r2["hash"] and r2["hash"] == r3["hash"] and res["hash"] != 0, "mismo catálogo → mismo hash (%08x)" % int(res["hash"]))
	check(var_to_str(res["baked"]) == var_to_str(r3["baked"]), "mismo catálogo → horneado idéntico")
	check(AC.checksum(res["baked"]) == res["hash"], "checksum(baked) == hash")
	var rc := _mut(func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["cooldown_ticks"] = 241)
	check(rc["ok"] and rc["hash"] != res["hash"], "un cambio de dato cambia el hash")
	# --- reglas V01..V19
	_expect("V01", func(d: Dictionary) -> void: d["tick_rate"] = 30, "tick_rate 30", "tick_rate")
	_expect("V01", func(d: Dictionary) -> void: d["version"] = 0, "version 0", "version")
	_expect("V02", func(d: Dictionary) -> void: d["abilities"].append(d["abilities"][0].duplicate(true)), "id de habilidad repetido", "abilities[5].id")
	_expect("V02", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][2]["id"] = "golpe_suelo", "id de paso repetido", "abilities[2].steps[2].id")
	_expect("V02", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["events"][1]["id"] = "ev_amague", "id de evento repetido", "abilities[1].steps[0].events[1].id")
	_expect("V03", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["steps"][0]["telegraph"]["id"] = "tg_hachazo_ambar", "telegraph.id repetido en el catálogo", "abilities[3].steps[0].telegraph.id")
	_expect("V03", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][0]["telegraph"]["color"] = "#FFB347", "mismo color de aviso en un preset", "presets[0]")
	_expect("V04", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][0]["next"]["default"] = "nada", "next a paso inexistente", "abilities[2].steps[0].next.default")
	_expect("V04", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][0]["cancel_into"]["steps"] = ["fantasma"], "cancel_into a paso inexistente", "abilities[4].steps[0].cancel_into.steps[0]")
	_expect("V05", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][0]["next"].erase("on_whiff"), "paso inalcanzable", "abilities[2].steps[2]")
	_expect("V05", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][1]["branch"]["default_if_no_input"] = "golpe_1", "ciclo sin max_loops", "abilities[4].steps[0]")
	_expect("V06", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["recovery_ticks"] = 10, "recuperación final < 18", "abilities[1].steps[0].recovery_ticks")
	_expect("V07", func(d: Dictionary) -> void:
		var s: Dictionary = _ab(d, "hachazo_penitente")["steps"][0]
		s["windup_ticks"] = 12; s["tracking"]["lock_at_tick"] = 8; s["armor"]["to_tick"] = 18; s["movement"]["from_tick"] = 10; s["movement"]["to_tick"] = 18
		for e: Dictionary in s["events"]: e["tick"] = 5
		s["spawns"][0]["at_tick"] = 18, "imbloqueable con windup 12", "abilities[1].steps[0].windup_ticks")
	_expect("V07", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][3].erase("telegraph"), "imbloqueable sin telegraph", "abilities[4].steps[3].telegraph")
	_expect("V08", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["hitboxes"][0]["to_tick"] = 99, "hitbox fuera del activo", "abilities[1].steps[0].hitboxes[0]")
	_expect("V08", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["armor"]["from_tick"] = 81, "armor vacía (from = to)", "abilities[1].steps[0].armor")
	_expect("V09", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["windup_ticks"] = 75.5, "tick con decimales", "abilities[1].steps[0].windup_ticks")
	_expect("V09", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["hitboxes"][0]["damage_per_hit"] = 40.12345, "más de 3 decimales", "abilities[1].steps[0].hitboxes[0].damage_per_hit")
	_expect("V10", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["cost"] = {"stamina": 0, "mana": 0, "health": 0}, "costo cero", "abilities[3].cost")
	_expect("V11", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["steps"][0]["self_invuln"] = {"from_tick": 0, "to_tick": 20, "mode": "total"}, "invulnerabilidad total sin mana_shield", "abilities[3].steps[0].self_invuln.mode")
	_expect("V12", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][0]["hitboxes"][0]["on_hit"]["force"]["duration_ticks"] = 60, "pull de 60 ticks", "abilities[2].steps[0].hitboxes[0].on_hit.force.duration_ticks")
	_expect("V12", func(d: Dictionary) -> void: _ab(d, "cadena_abismo")["steps"][0]["hitboxes"][0]["on_hit"]["force"]["breakable_by"] = ["none"], "pull irrompible", "abilities[2].steps[0].hitboxes[0].on_hit.force.breakable_by")
	_expect("V13", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["movement"].erase("max_distance_m"), "movimiento sin tope", "abilities[1].steps[0].movement.max_distance_m")
	_expect("V14", func(d: Dictionary) -> void: d["presets"][1]["abilities"] = ["saeta_brasas", "martillo_runico", "cadena_abismo", "hachazo_penitente"], "preset de 4", "presets[1].abilities")
	_expect("V14", func(d: Dictionary) -> void: d["presets"][1]["abilities"] = ["saeta_brasas", "inexistente"], "preset con id inexistente", "presets[1].abilities[1]")
	var w15 := _mut(func(d: Dictionary) -> void: _ab(d, "tormenta_ascendente")["unlock"] = {"phase": 2})
	check(w15["ok"] and _has(w15, "V15", "abilities[0].unlock.phase", "warnings"), "unlock.phase 2 fuera del 3.er lugar → aviso V15")
	_expect("V16", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][1]["branch"]["options"][1].erase("hud_icon"), "alt sin hud_icon", "abilities[4].steps[1].branch.options[1].hud_icon")
	_expect("V16", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][1]["branch"]["options"][1]["input"] = "skill", "dos opciones con el mismo input", "abilities[4].steps[1].branch.options[1].input")
	_expect("V16", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][1]["branch"]["window_to_tick"] = 90, "ventana de branch fuera del paso", "abilities[4].steps[1].branch")
	_expect("V16", func(d: Dictionary) -> void: _ab(d, "martillo_runico")["steps"][1]["branch"]["options"][0]["step"] = "remate_x", "opción a paso inexistente", "abilities[4].steps[1].branch.options[0].step")
	_expect("V17", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["steps"][0]["spawns"][0]["count"] = 7, "7 proyectiles", "abilities[3]")
	_expect("V18", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["interruptible_by"] = [], "sin interrupciones ni hyper", "abilities[1].interruptible_by")
	_expect("V19", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["name"] = "Saeta de Malenia", "nombre de otra franquicia", "abilities[3]")
	_expect("SCHEMA", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["category"] = "laser", "categoría inválida", "abilities[3].category")
	_expect("SCHEMA", func(d: Dictionary) -> void: _ab(d, "saeta_brasas").erase("ai"), "falta ai", "abilities[3].ai")
	_expect("SCHEMA", func(d: Dictionary) -> void: _ab(d, "hachazo_penitente")["steps"][0]["hitboxes"][0]["shape"] = {"type": "circle"}, "forma sin radio", "abilities[1].steps[0].hitboxes[0].shape.radius_m")
	_expect("SCHEMA", func(d: Dictionary) -> void: _ab(d, "saeta_brasas")["steps"] = [], "habilidad sin pasos", "abilities[3].steps")
	# --- avisos
	var wa := _mut(func(d: Dictionary) -> void:
		_ab(d, "saeta_brasas")["icon"] = "res://no/existe.png"
		_ab(d, "saeta_brasas")["poder_secreto"] = 3)
	check(wa["ok"] and _has(wa, "ASSET", "abilities[3].icon", "warnings") and _has(wa, "UNKNOWN_FIELD", "abilities[3].poder_secreto", "warnings"), "icono inexistente y campo desconocido → avisos, no errores")
	check(wa["ok"] and wa["baked"]["abilities"][3]["icon"] == "generic", "icono inexistente → genérico")
	var wv: Dictionary = AC.load_data(base.duplicate(true), {"known_vfx": ["vfx_crack"], "known_sfx": []})
	check(wv["ok"] and _has(wv, "ASSET", "", "warnings"), "registro de vfx/sfx: ids desconocidos → aviso + genérico")
	# --- entradas basura: nunca rompe
	var junk: Array = [42, null, "x", [], {"abilities": "x"}, {"version": "uno", "tick_rate": 60, "abilities": [1, null, {}]},
		{"version": 1, "tick_rate": 60, "abilities": [{"id": "abc", "steps": [null, 3, {"hitboxes": "x", "next": 5, "branch": [], "events": [7]}]}]}]
	var all_bad := true
	for j: Variant in junk:
		var rj: Dictionary = AC.load_data(j)
		if rj["ok"] or (rj["errors"] as Array).is_empty() or rj["baked"] != null:
			all_bad = false
	check(all_bad, "entradas basura → errores estructurados, sin horneado y sin romper")
	var rp: Dictionary = AC.load_text("{ esto no es json")
	check(not rp["ok"] and _has(rp, "PARSE"), "JSON roto → PARSE")
	var rf: Dictionary = AC.load_file("res://data/abilities/no_existe.json")
	check(not rf["ok"] and _has(rf, "PARSE"), "archivo inexistente → PARSE")
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
