extends RefCounted
## Pruebas de validación V21..V54, regresión de catálogos existentes, sim determinista + rollback
## de 8 ticks y capa de vista/mobile (Etapas 1..8).

const AC := preload("res://net/sim/ability_catalog.gd")

func run_all(t: SceneTree, base: Dictionary) -> void:
	_test_existing_catalogs_regression(t)
	_test_rules_v21_to_v54(t, base)
	_test_guide_examples(t, base)
	_test_sim_and_rollback(t, base)
	_test_view_idempotency_and_mobile(t)

func _test_existing_catalogs_regression(t: SceneTree) -> void:
	var expected := {
		"res://data/abilities/catalog.example.json": 0xa2a2f8bd,
		"res://data/abilities/catalog.json": 0x56aca177,
		"res://data/abilities/hoja_escarlata_catalog.json": 0x858691f9,
		"res://data/abilities/elden_inspired_catalog.json": 0x5a8717b5,
		"res://data/abilities/artorias_inspired_catalog.json": 0x67526046,
	}
	for path: String in expected.keys():
		var r: Dictionary = AC.load_file(path)
		var exp_h: int = int(expected[path])
		t.check(r["ok"] and (r["errors"] as Array).is_empty() and int(r["hash"]) == exp_h,
			"regresión %s → ok y mismo hash (%08x == %08x)" % [path.get_file(), int(r["hash"]), exp_h])

func _expect_err(t: SceneTree, base: Dictionary, rule: String, f: Callable, label: String) -> void:
	var d: Dictionary = base.duplicate(true)
	f.call(d)
	var r: Dictionary = AC.load_data(d)
	t.check(not r["ok"] and t._has(r, rule, "", "errors"), "%s → error %s (obtuvo %s)" % [label, rule, str(t._rules(r, "errors"))])

func _expect_warn(t: SceneTree, base: Dictionary, rule: String, f: Callable, label: String) -> void:
	var d: Dictionary = base.duplicate(true)
	f.call(d)
	var r: Dictionary = AC.load_data(d)
	t.check(r["ok"] and t._has(r, rule, "", "warnings"), "%s → aviso %s (obtuvo %s)" % [label, rule, str(t._rules(r, "warnings"))])

func _expect_ok(t: SceneTree, base: Dictionary, rule: String, f: Callable, label: String) -> void:
	var d: Dictionary = base.duplicate(true)
	f.call(d)
	var r: Dictionary = AC.load_data(d)
	t.check(r["ok"] and not t._has(r, rule, "", "errors") and not t._has(r, rule, "", "warnings"),
		"%s → pasa %s sin error/aviso (%s)" % [label, rule, AC.format_issues(r)])

func _test_rules_v21_to_v54(t: SceneTree, base: Dictionary) -> void:
	# V21: range_min_m <= range_max_m
	_expect_err(t, base, "V21", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["range_min_m"] = 6.0; mv["range_max_m"] = 2.0, "V21 dispara con range_min_m > range_max_m")
	_expect_ok(t, base, "V21", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["range_min_m"] = 1.5; mv["range_max_m"] = 5.0, "V21 pasa con range_min_m <= range_max_m")

	# V22: fit_to_target requiere stop_at_m > 0 y target_mode hacia el rival
	_expect_err(t, base, "V22", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["fit_to_target"] = true; mv["target_mode"] = "facing", "V22 dispara con fit_to_target y target_mode=facing")
	_expect_ok(t, base, "V22", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["fit_to_target"] = true; mv["target_mode"] = "lock_point"; mv["stop_at_m"] = 1.2, "V22 pasa con target_mode=lock_point y stop_at_m>0")

	# V23: aviso arrive_angle_deg fuera de [-180, 180]
	_expect_warn(t, base, "V23", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"]["arrive_angle_deg"] = 240.0, "V23 avisa con arrive_angle_deg=240")
	_expect_ok(t, base, "V23", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"]["arrive_angle_deg"] = 90.0, "V23 pasa con arrive_angle_deg=90")

	# V24: tracking.windows ordenadas, sin solaparse, dentro del paso y deg_per_sec 0..2000
	_expect_err(t, base, "V24", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["tracking"]["windows"] = [
			{"from_tick": 0, "to_tick": 30, "deg_per_sec": 180},
			{"from_tick": 20, "to_tick": 40, "deg_per_sec": 360}
		], "V24 dispara con tracking.windows solapadas")
	_expect_ok(t, base, "V24", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["tracking"]["windows"] = [
			{"from_tick": 0, "to_tick": 20, "deg_per_sec": 180},
			{"from_tick": 20, "to_tick": 66, "deg_per_sec": 1800}
		], "V24 pasa con tracking.windows ordenadas hasta 1800°/s")

	# V25: aviso si hay ventana con giro > 0 después de lock_at_tick
	_expect_warn(t, base, "V25", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["tracking"]["windows"] = [
			{"from_tick": 0, "to_tick": 66, "deg_per_sec": 180},
			{"from_tick": 66, "to_tick": 80, "deg_per_sec": 120}
		], "V25 avisa con giro > 0 tras lock_at_tick")
	_expect_ok(t, base, "V25", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["tracking"]["windows"] = [
			{"from_tick": 0, "to_tick": 66, "deg_per_sec": 180},
			{"from_tick": 66, "to_tick": 100, "deg_per_sec": 0}
		], "V25 pasa con giro 0 tras lock_at_tick")

	# V26: exit_windows dentro del paso y buffer_ticks 0..12
	_expect_err(t, base, "V26", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["exit_windows"] = [{"action": "roll", "from_tick": 90, "to_tick": 200}],
		"V26 dispara con exit_windows fuera del paso")
	_expect_ok(t, base, "V26", func(d: Dictionary) -> void:
		var s: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]
		s["buffer_ticks"] = 6
		s["exit_windows"] = [{"action": "roll", "from_tick": 90, "to_tick": 120}],
		"V26 pasa con exit_windows dentro del paso y buffer_ticks=6")

	# V27: aviso si move cierra antes que roll
	_expect_warn(t, base, "V27", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["exit_windows"] = [
			{"action": "roll", "from_tick": 90, "to_tick": 125},
			{"action": "move", "from_tick": 92, "to_tick": 115}
		], "V27 avisa cuando move cierra antes que roll")
	_expect_ok(t, base, "V27", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["exit_windows"] = [
			{"action": "roll", "from_tick": 90, "to_tick": 120},
			{"action": "move", "from_tick": 92, "to_tick": 130}
		], "V27 pasa cuando move cierra después que roll")

	# V28: aviso si caja activa en melee no tiene weapon_trail que la cubra
	_expect_warn(t, base, "V28", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["weapon_trail"] = {"from_tick": 0, "to_tick": 20, "style": "slash"},
		"V28 avisa si weapon_trail no cubre la ventana activa")
	_expect_ok(t, base, "V28", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["weapon_trail"] = {"from_tick": 70, "to_tick": 85, "style": "slash"},
		"V28 pasa si weapon_trail cubre [75, 81]")

	# V29: duration_ticks >= 0 y dentro del paso (salvo outlive_step: true)
	_expect_err(t, base, "V29", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]["duration_ticks"] = 120,
		"V29 dispara cuando tick + duration_ticks excede el paso sin outlive_step")
	_expect_ok(t, base, "V29", func(d: Dictionary) -> void:
		var ev: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]
		ev["duration_ticks"] = 120; ev["outlive_step"] = true,
		"V29 pasa con outlive_step: true")

	# V30: attach válido
	_expect_err(t, base, "V30", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]["attach"] = "head",
		"V30 dispara con attach inválido")
	_expect_ok(t, base, "V30", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]["attach"] = "weapon",
		"V30 pasa con attach='weapon'")

	# V31: camera_shake falloff_start_m <= falloff_end_m
	_expect_err(t, base, "V31", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]["camera_shake"] = {"level": 2, "falloff_start_m": 25, "falloff_end_m": 10},
		"V31 dispara con falloff_start_m > falloff_end_m")
	_expect_ok(t, base, "V31", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["events"][0]["camera_shake"] = {"level": 2, "falloff_start_m": 8, "falloff_end_m": 25, "haptic": "medium"},
		"V31 pasa con falloff_start_m <= falloff_end_m")

	# V32: volley count >= 1, interval_ticks >= 0 y último sub-spawn dentro del paso
	_expect_err(t, base, "V32", func(d: Dictionary) -> void:
		t._ab(d, "saeta_brasas")["steps"][0]["spawns"][0]["volley"] = {"count": 5, "interval_ticks": 10},
		"V32 dispara cuando el último sub-spawn cae fuera del paso")
	_expect_ok(t, base, "V32", func(d: Dictionary) -> void:
		t._ab(d, "saeta_brasas")["steps"][0]["spawns"][0]["volley"] = {"count": 4, "interval_ticks": 4, "aim": "lock"},
		"V32 pasa cuando todos los sub-spawns caen dentro del paso")

	# V33: origin_offsets de largo count y paired_hitbox existente
	_expect_err(t, base, "V33", func(d: Dictionary) -> void:
		t._ab(d, "saeta_brasas")["steps"][0]["spawns"][0]["volley"] = {
			"count": 3, "interval_ticks": 2, "origin_offsets": [{"forward_m": 0.5, "right_m": 0.0}]
		}, "V33 dispara cuando origin_offsets.size() != count")
	_expect_ok(t, base, "V33", func(d: Dictionary) -> void:
		t._ab(d, "saeta_brasas")["steps"][0]["spawns"][0]["volley"] = {
			"count": 2, "interval_ticks": 2,
			"origin_offsets": [{"forward_m": 0.5, "right_m": -0.3}, {"forward_m": 0.5, "right_m": 0.3}]
		}, "V33 pasa cuando origin_offsets.size() == count")

	# V34: fade a opacidad < 30 exige cue de reaparición
	_expect_err(t, base, "V34", func(d: Dictionary) -> void:
		var s: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]
		s["events"] = []
		s["self_windows"] = [{"type": "fade", "from_tick": 10, "to_tick": 30, "opacity_from": 100, "opacity_to": 0}],
		"V34 dispara en fade a 0 sin evento sfx posterior")
	_expect_ok(t, base, "V34", func(d: Dictionary) -> void:
		var s: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]
		s["self_windows"] = [{"type": "fade", "from_tick": 10, "to_tick": 30, "opacity_from": 100, "opacity_to": 0}],
		"V34 pasa cuando hay evento con sfx en el tick de reaparición")

	# V35: self_windows válidas y cost_at_tick dentro del paso
	_expect_err(t, base, "V35", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["cost_at_tick"] = 500,
		"V35 dispara con cost_at_tick fuera del paso")
	_expect_ok(t, base, "V35", func(d: Dictionary) -> void:
		var s: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]
		s["cost_at_tick"] = 20
		s["self_windows"] = [{"type": "no_turn", "from_tick": 66, "to_tick": 100}],
		"V35 pasa con cost_at_tick=20 y self_windows válida")

	# V36: aviso si intangible dura > 60 ticks
	_expect_warn(t, base, "V36", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_windows"] = [{"type": "intangible", "from_tick": 0, "to_tick": 70}],
		"V36 avisa con ventana intangible de 70 ticks (> 60)")
	_expect_ok(t, base, "V36", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_windows"] = [{"type": "intangible", "from_tick": 10, "to_tick": 40}],
		"V36 pasa con ventana intangible de 30 ticks")

	# V37: reference_distance_m > 0 y dentro de [range_min_m, range_max_m]
	_expect_err(t, base, "V37", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["range_min_m"] = 2.0; mv["range_max_m"] = 5.0; mv["reference_distance_m"] = 7.0,
		"V37 dispara con reference_distance_m fuera de [range_min_m, range_max_m]")
	_expect_ok(t, base, "V37", func(d: Dictionary) -> void:
		var mv: Dictionary = t._ab(d, "hachazo_penitente")["steps"][0]["movement"]
		mv["range_min_m"] = 2.0; mv["range_max_m"] = 5.0; mv["reference_distance_m"] = 3.5,
		"V37 pasa con reference_distance_m dentro del rango")

	# V38: distance_scale_windows sin solapes y pct 0..400
	_expect_err(t, base, "V38", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"]["distance_scale_windows"] = [
			{"from_tick": 69, "to_tick": 75, "pct": 500}
		], "V38 dispara con pct=500 (> 400)")
	_expect_ok(t, base, "V38", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"]["distance_scale_windows"] = [
			{"from_tick": 69, "to_tick": 75, "pct": 200},
			{"from_tick": 75, "to_tick": 81, "pct": 80}
		], "V38 pasa con ventanas ordenadas y pct en 0..400")

	# V39: combo requiere next, cancel_into o branch no nulo
	_expect_err(t, base, "V39", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["exit_windows"] = [{"action": "combo", "from_tick": 82, "to_tick": 110}],
		"V39 dispara con exit_windows combo en paso sin continuación")
	_expect_ok(t, base, "V39", func(d: Dictionary) -> void:
		t._ab(d, "martillo_runico")["steps"][0]["exit_windows"] = [{"action": "combo", "from_tick": 38, "to_tick": 50}],
		"V39 pasa en paso con next/cancel_into")

	# V40: combo_input_windows dentro del paso, ordenadas y sin solaparse
	_expect_err(t, base, "V40", func(d: Dictionary) -> void:
		t._ab(d, "martillo_runico")["steps"][0]["combo_input_windows"] = [
			{"from_tick": 36, "to_tick": 46, "step": "golpe_2"},
			{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}
		], "V40 dispara con combo_input_windows solapadas")
	_expect_ok(t, base, "V40", func(d: Dictionary) -> void:
		t._ab(d, "martillo_runico")["steps"][0]["combo_input_windows"] = [
			{"from_tick": 36, "to_tick": 42, "step": "golpe_2"},
			{"from_tick": 44, "to_tick": 50, "step": "golpe_2"}
		], "V40 pasa con 2 combo_input_windows separadas")

	# V41: hitboxes.variant tag conocido; aviso si dos variantes del mismo tick pueden estar activas a la vez
	_expect_err(t, base, "V41", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["hitboxes"][0]["variant"] = {"when": "tag_inventado"},
		"V41 dispara con tag desconocido")
	_expect_warn(t, base, "V41", func(d: Dictionary) -> void:
		var hbs: Array = t._ab(d, "hachazo_penitente")["steps"][0]["hitboxes"]
		var hb2: Dictionary = hbs[0].duplicate(true)
		hb2["id"] = "hb_hachazo_2"
		hbs[0]["variant"] = {"when": "phase1"}
		hb2["variant"] = {"when": "rage"}
		hbs.append(hb2), "V41 avisa cuando dos variantes no mutuamente excluyentes coinciden en tick")
	_expect_ok(t, base, "V41", func(d: Dictionary) -> void:
		var hbs: Array = t._ab(d, "hachazo_penitente")["steps"][0]["hitboxes"]
		var hb2: Dictionary = hbs[0].duplicate(true)
		hb2["id"] = "hb_hachazo_2"
		hbs[0]["variant"] = {"when": "phase1"}
		hb2["variant"] = {"when": "phase2"}
		hbs.append(hb2), "V41 pasa sin aviso cuando las variantes son phase1 vs phase2")

	# V42: charge.tiers ordenados y con vfx/sfx/sfx_loop
	_expect_err(t, base, "V42", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["charge"] = {
			"from_tick": 0, "max_ticks": 50, "tiers": [{"at_tick": 20, "damage_pct": 120}]
		}, "V42 dispara cuando un tier de charge no tiene vfx/sfx")
	_expect_ok(t, base, "V42", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["charge"] = {
			"from_tick": 0, "max_ticks": 50,
			"tiers": [
				{"at_tick": 20, "damage_pct": 120, "stun_pct": 110, "sfx": "sfx_tele_hachazo"},
				{"at_tick": 40, "damage_pct": 150, "stun_pct": 130, "vfx": "vfx_flash_white"}
			]
		}, "V42 pasa con tiers ordenados y con sfx/vfx")

	# V43: self_status_at válido
	_expect_err(t, base, "V43", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_status_at"] = [{"tick": 20, "status": "inmortal", "duration_ticks": 60}],
		"V43 dispara con status desconocido")
	_expect_ok(t, base, "V43", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_status_at"] = [{"tick": 20, "status": "rage", "duration_ticks": 120}],
		"V43 pasa con status='rage' y tick válido")

	# V44: counter_window dentro del paso y damage_taken_pct 100..200
	_expect_err(t, base, "V44", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["counter_window"] = {"from_tick": 0, "to_tick": 20, "damage_taken_pct": 260},
		"V44 dispara con damage_taken_pct > 200")
	_expect_ok(t, base, "V44", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["counter_window"] = {"from_tick": 0, "to_tick": 25, "damage_taken_pct": 135, "stun_taken_pct": 120},
		"V44 pasa con ventana <= 40 ticks y damage_taken_pct=135")

	# V45: movement[] multi-tramo ordenado y sin solaparse
	_expect_err(t, base, "V45", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"] = [
			{"type": "dash", "from_tick": 10, "to_tick": 30, "speed_mps": 6, "max_distance_m": 2.0},
			{"type": "dash", "from_tick": 25, "to_tick": 45, "speed_mps": 6, "max_distance_m": 2.0}
		], "V45 dispara con tramos de movement[] solapados")
	_expect_ok(t, base, "V45", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"] = [
			{"type": "retreat", "from_tick": 10, "to_tick": 25, "speed_mps": 5, "max_distance_m": 1.5},
			{"type": "dash", "from_tick": 40, "to_tick": 65, "speed_mps": 8, "max_distance_m": 3.0}
		], "V45 pasa con 2 tramos ordenados sin solaparse")

	# V46: blink_to_target exige >= 18 ticks antes del primer activo y cue de reaparición
	_expect_err(t, base, "V46", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"] = {
			"type": "blink_to_target", "from_tick": 65, "to_tick": 72, "target_mode": "lock_point", "stop_at_m": 1.2
		}, "V46 dispara cuando entre from_tick del blink y el primer activo hay < 18 ticks")
	_expect_ok(t, base, "V46", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["movement"] = {
			"type": "blink_to_target", "from_tick": 20, "to_tick": 45, "target_mode": "lock_point", "stop_at_m": 1.2
		}, "V46 pasa con >= 18 ticks antes del activo y sfx en reaparición")

	# V47: guard_windows dentro del paso y porcentajes 0..100
	_expect_err(t, base, "V47", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["guard_windows"] = [
			{"from_tick": 10, "to_tick": 40, "block_dmg_pct": 120}
		], "V47 dispara con block_dmg_pct > 100")
	_expect_ok(t, base, "V47", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["guard_windows"] = [
			{"from_tick": 10, "to_tick": 40, "block_dmg_pct": 75, "knockback_pct": 50, "stamina_regen_pct": 30}
		], "V47 pasa con guard_windows en rango")

	# V48: self_status_at.on válido
	_expect_err(t, base, "V48", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_status_at"] = [
			{"tick": 20, "status": "rage", "duration_ticks": 120, "on": "parry"}
		], "V48 dispara con self_status_at.on inválido")
	_expect_ok(t, base, "V48", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["self_status_at"] = [
			{"tick": 75, "status": "rage", "duration_ticks": 120, "on": "hit"}
		], "V48 pasa con self_status_at.on='hit'")

	# V49: phase_transition on_phase=2 y entry_step existente
	_expect_err(t, base, "V49", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["phase_transition"] = {"on_phase": 2, "entry_step": "no_existe"},
		"V49 dispara con entry_step inexistente")
	_expect_ok(t, base, "V49", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["phase_transition"] = {"on_phase": 2, "entry_step": "golpe_tardio", "self_invuln": true, "skip_global_cd": true},
		"V49 pasa con on_phase=2 y entry_step válido")

	# V50: chain requiere entry_step con chain_role='opener' y ventana de combo/branch
	_expect_err(t, base, "V50", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2},
		"V50 dispara cuando entry_step no tiene chain_role='opener' ni ventana de combo")
	_expect_ok(t, base, "V50", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 3}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}]
		ab["steps"][1]["chain_role"] = "link"
		ab["steps"][2]["chain_role"] = "finisher"
		ab["steps"][3]["chain_role"] = "finisher", "V50 pasa con cadena bien formada")

	# V51: link/finisher no puede ser entry_step ni fuera de habilidad con chain
	_expect_err(t, base, "V51", func(d: Dictionary) -> void:
		t._ab(d, "hachazo_penitente")["steps"][0]["chain_role"] = "finisher",
		"V51 dispara cuando entry_step tiene chain_role='finisher'")
	_expect_ok(t, base, "V51", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 3}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}]
		ab["steps"][1]["chain_role"] = "link"
		ab["steps"][2]["chain_role"] = "finisher"
		ab["steps"][3]["chain_role"] = "finisher", "V51 pasa con roles opener/link/finisher válidos")

	# V52: max_links en 1..3 y largo máximo alcanzable <= max_links
	_expect_err(t, base, "V52", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 1}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}],
		"V52 dispara cuando la cadena tiene 2 eslabones y max_links=1")
	_expect_ok(t, base, "V52", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}],
		"V52 pasa cuando el largo máximo es <= max_links")

	# V53: opener <= 2 golpes activos (error) y windup+active <= 90 (aviso)
	_expect_err(t, base, "V53", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2}
		var s0: Dictionary = ab["steps"][0]
		s0["chain_role"] = "opener"
		s0["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}]
		var h1: Dictionary = s0["hitboxes"][0].duplicate(true); h1["id"] = "hb_extra_1"
		var h2: Dictionary = s0["hitboxes"][0].duplicate(true); h2["id"] = "hb_extra_2"
		s0["hitboxes"].append(h1); s0["hitboxes"].append(h2),
		"V53 dispara cuando el opener tiene 3 hitboxes")
	_expect_ok(t, base, "V53", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}],
		"V53 pasa con opener de 1 hitbox y <= 90 ticks")

	# V54: aviso si la ventana de combo abre < 6 ticks después del último tick activo
	_expect_warn(t, base, "V54", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 38, "to_tick": 50, "step": "golpe_2"}],
		"V54 avisa cuando combo_input_windows abre < 6 ticks tras el activo (38 < 36+6)")
	_expect_ok(t, base, "V54", func(d: Dictionary) -> void:
		var ab: Dictionary = t._ab(d, "martillo_runico")
		ab["chain"] = {"cost_on": "start", "cooldown_on": "chain_end", "max_links": 2}
		ab["steps"][0]["chain_role"] = "opener"
		ab["steps"][0]["combo_input_windows"] = [{"from_tick": 42, "to_tick": 50, "step": "golpe_2"}],
		"V54 pasa cuando combo_input_windows abre >= 6 ticks tras el activo")

static func _make_danza_eclipse() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities/nuevas_habilidades_catalog.json"))
	return (raw["abilities"][0] as Dictionary).duplicate(true)

static func _make_salva_velo_astral() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities/nuevas_habilidades_catalog.json"))
	return (raw["abilities"][1] as Dictionary).duplicate(true)

func _test_guide_examples(t: SceneTree, base: Dictionary) -> void:
	var d: Dictionary = base.duplicate(true)
	d["abilities"].append(_make_danza_eclipse())
	d["abilities"].append(_make_salva_velo_astral())
	var r: Dictionary = AC.load_data(d)
	t.check(r["ok"] and (r["errors"] as Array).is_empty() and (r["warnings"] as Array).is_empty(),
		"los 2 ejemplos nuevos de la guía (danza_eclipse y salva_velo_astral) validan sin errores ni avisos %s" % AC.format_issues(r))

func _test_sim_and_rollback(t: SceneTree, base: Dictionary) -> void:
	var d: Dictionary = base.duplicate(true)
	d["abilities"] = [_make_danza_eclipse(), _make_salva_velo_astral()]
	d["presets"] = [{"id": "test_preset", "name": "Test Preset", "abilities": ["danza_eclipse", "salva_velo_astral"]}]
	var loaded: Dictionary = AC.load_data(d)
	t.check(loaded["ok"], "catálogo de prueba carga para sim")
	var compiled: Dictionary = SimCatalog.compile_dict(loaded["baked"])
	var p: Dictionary = SimParams.defaults()
	p["boss"] = compiled
	for k in 2:
		p["f"][k]["boss_ids"] = [0, 1]
		p["f"][k]["boss_n"] = 2
		p["f"][k]["max_mana"] = 100000
		p["f"][k]["max_stamina"] = 100000

	# Simulación directa vs rollback de 8 ticks en cada frame
	var s_direct := FightSim.new_state(p, 12345)
	var s_rb := FightSim.new_state(p, 12345)
	s_direct[FightSim.PHASE] = FightSim.PH_FIGHT
	s_rb[FightSim.PHASE] = FightSim.PH_FIGHT
	var history: Array[PackedInt64Array] = []
	var inputs: Array[Vector2i] = []
	for f in 180:
		var in0 := FightSim.IN_LOCK
		var in1 := FightSim.IN_LOCK
		if f == 2:
			in0 |= FightSim.IN_ABILITY # lanza danza_eclipse
			in1 |= FightSim.ab_sel_bits(1) | FightSim.IN_ABILITY # lanza salva_velo_astral
		elif f == 50:
			in0 |= FightSim.IN_ABILITY # encadena 1ra continuación en combo_input_windows
		elif f == 95:
			in0 |= FightSim.IN_ROLL # sale por exit_windows con roll
		elif f == 72:
			in1 |= FightSim.IN_ROLL # salva_velo_astral sale por exit_windows
		inputs.append(Vector2i(in0, in1))
		history.append(s_rb.duplicate())
		FightSim.step(s_direct, p, in0, in1)
		FightSim.step(s_rb, p, in0, in1)
		if f >= 8 and f % 7 == 0:
			var back := f - 8
			s_rb = history[back].duplicate()
			for rf in range(back, f + 1):
				FightSim.step(s_rb, p, inputs[rf].x, inputs[rf].y)
	t.check(FightSim.checksum(s_direct) == FightSim.checksum(s_rb),
		"determinismo + rollback de 8 ticks idéntico al tick 180 (%08x == %08x)" % [FightSim.checksum(s_direct), FightSim.checksum(s_rb)])

	# Verificar salva_velo_astral: cost_at_tick=12, intangible [8,26), fade [8,16], volley de 7 proyectiles desde tick 36
	var s_velo := FightSim.new_state(p, 999)
	s_velo[FightSim.PHASE] = FightSim.PH_FIGHT
	var mana_ini := s_velo[FightSim.fb(0) + FightSim.F_MANA]
	var velo_in := FightSim.ab_sel_bits(1) | FightSim.IN_ABILITY | FightSim.IN_LOCK
	FightSim.step(s_velo, p, velo_in, FightSim.IN_LOCK)
	t.check(s_velo[FightSim.fb(0) + FightSim.F_MANA] == mana_ini, "cost_at_tick=12: en el tick 1 aún no cobró maná")
	for k in 10:
		FightSim.step(s_velo, p, FightSim.IN_LOCK, FightSim.IN_LOCK)
	t.check(s_velo[FightSim.eb(0) + FightSim.EX_INTANG] == 1, "self_windows intangible activo en tick 11")
	var op_mid := SimCatalog.step_opacity(s_velo, p, 0)
	t.check(op_mid < 100 and op_mid >= 15, "self_windows fade interpola opacidad en vista (%d)" % op_mid)
	for k in 5:
		FightSim.step(s_velo, p, FightSim.IN_LOCK, FightSim.IN_LOCK)
	t.check(s_velo[FightSim.fb(0) + FightSim.F_MANA] < mana_ini, "cost_at_tick=12: ya cobró maná al cruzar el tick 12")
	for k in 35:
		FightSim.step(s_velo, p, FightSim.IN_LOCK, FightSim.IN_LOCK)
	var active_projs := 0
	for pi in FightSim.PR_MAX:
		if s_velo[FightSim.prb(pi) + FightSim.PR_ON] == 1:
			active_projs += 1
	t.check(active_projs >= 4, "volley de 7 proyectiles spawnea sub-proyectiles secuenciados (activos: %d)" % active_projs)

func _test_view_idempotency_and_mobile(t: SceneTree) -> void:
	var fx := SimFx.new()
	fx.fx_quality = "low"
	fx.haptics_enabled = false
	var ev_foot := {
		"kind": "ability_event", "player": 0, "code": 1, "step": 0, "id": "ev_paso",
		"dedup_key": "0:1:0:ev_paso:10", "start_tick": 10, "footstep": true,
		"vfx": "vfx_dust_ring", "sfx": "sfx_step", "shake": 0, "haptic": "none"
	}
	var ev_loop := {
		"kind": "ability_event", "player": 0, "code": 1, "step": 0, "id": "ev_loop",
		"dedup_key": "0:1:0:ev_loop:12", "start_tick": 12, "duration_ticks": 30,
		"sfx": "sfx_hum", "sfx_loop": true, "stop_on_interrupt": true, "vfx": "vfx_aura",
		"shake": 2, "shake_obj": {"level": 2, "falloff_start": 8000000, "falloff_end": 24000000, "haptic": 2},
		"haptic": "medium"
	}
	var r1 := fx.consume(12, [ev_foot, ev_loop], true)
	t.check((r1["events"] as Array).size() == 1, "fx_quality='low' ignora eventos footstep")
	t.check((r1["haptics"] as Array).is_empty(), "haptics_enabled=false desactiva vibraciones")
	t.check(fx.active_loops.has("0:1:0:ev_loop:12"), "sfx_loop registra loop activo")
	# Re-simulación tras rollback del mismo tick: no debe duplicar el evento
	var r2 := fx.consume(12, [ev_loop], true)
	t.check((r2["events"] as Array).is_empty(), "idempotencia en rollback: mismo dedup_key no se dispara dos veces")
	# Rollback a frame anterior al inicio del loop: debe cancelar el loop activo
	fx.rollback_to(8)
	t.check(not fx.active_loops.has("0:1:0:ev_loop:12"), "rollback antes de start_tick cancela el sfx_loop activo")
	# Atenuación por distancia de camera_shake
	var i_near := SimEvents.shake_intensity(ev_loop, 4.0)
	var i_mid := SimEvents.shake_intensity(ev_loop, 16.0)
	var i_far := SimEvents.shake_intensity(ev_loop, 30.0)
	t.check(is_equal_approx(i_near, 2.0) and is_equal_approx(i_mid, 1.0) and is_equal_approx(i_far, 0.0),
		"camera_shake falloff lineal: cerca=%.2f, medio=%.2f, lejos=%.2f" % [i_near, i_mid, i_far])
