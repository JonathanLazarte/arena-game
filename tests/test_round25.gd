extends SceneTree
## Ronda 25: cámara. El recorrido de 8 direcciones dependía de la posición y se fue en la fase 8
## (la jugabilidad quedó en test_fight_sim / test_sim_rules).
## godot --headless --path . -s res://tests/test_round25.gd

var fails: int = 0

func _initialize() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): 
	await process_frame
	change_scene_to_file("res://scenes/arena.tscn")
	await process_frame
	await process_frame
	var arena: Arena = current_scene
	var rig := arena.rig
	await physics_frame
	await physics_frame
	# Colisión con un pilar
	var pivot := Vector3(0, 2, 0)
	var want := pivot + Vector3(0, 0, 9)
	var free := rig._collide(pivot, want)
	rig.obstacles.append(Vector3(pivot.x, 1.5, pivot.z + 4.0))
	var hit := rig._collide(pivot, want)
	rig.obstacles.pop_back()
	check(free.distance_to(want) < 0.1 and hit.distance_to(pivot) < 3.0, "un pilar en medio acerca la cámara (%.1f m)" % hit.distance_to(pivot))
	check(rig._collide(Vector3(40, 2, 0), Vector3(50, 2, 0)).x < CameraRig.new().arena_radius, "no atraviesa el muro")
	check(not rig._touch_ok(Vector2(100, 400)), "Android: la mitad izquierda no orbita (joystick)")
	var bpos: Vector2 = arena.hud.btns["attack_sword"].global_position
	check(not rig._touch_ok(bpos), "Android: sobre un botón no orbita")
	check(rig._touch_ok(Vector2(1000, 120)), "Android: mitad derecha libre orbita")
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Lock-on: la cámara sigue al objetivo; tirón cambia de objetivo
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 3. Estocada de jefe ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Ronda 31: la embestida corrige la dirección: el paso lateral ya no basta (solo la volteret
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): Impacto
	await physics_frame
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 4. IA: esquiva y usa la Estocada de jefe ---
	# [fase 8] retirado (jugabilidad del Fighter offline; cubierto en test_fight_sim/test_sim_rules): --- 5. Paso de ataque + magnetismo ---
	quit(1 if fails > 0 else 0)