extends SceneTree
## Ronda 28: reapunta clips Mixamo (ya en espacio humanoide, %GeneralSkeleton) al rig KayKit
## (Knight/Barbarian/Mage/Rogue comparten esqueleto) y los guarda en lib_kaykit.res.
## Método: delta global por hueso. D = Gpose_src · Grest_src⁻¹ ; Gpose_tgt = D · Grest_tgt.
## La traslación horizontal de las caderas se elimina (en el sitio: el desplazamiento lo da
## el sistema de embestidas/pasos del juego); se conserva la altura (escalada).
## godot --headless --path . -s res://tools/retarget_kaykit.gd
const OUT := "res://assets/animations/mixamo/lib_kaykit.res"
const SRC := "res://assets/animations/mixamo/lib_mixamo_all.res"
const CONTACT := 0.42 ## igual que KnightVisual.CONTACT
const FPS := 30.0
## humanoide -> hueso KayKit
const MAP := {"Hips": "hips", "Spine": "spine", "UpperChest": "chest", "Head": "head",
	"LeftUpperArm": "upperarm.l", "LeftLowerArm": "lowerarm.l", "LeftHand": "wrist.l",
	"RightUpperArm": "upperarm.r", "RightLowerArm": "lowerarm.r", "RightHand": "wrist.r",
	"LeftUpperLeg": "upperleg.l", "LeftLowerLeg": "lowerleg.l", "LeftFoot": "foot.l", "LeftToes": "toes.l",
	"RightUpperLeg": "upperleg.r", "RightLowerLeg": "lowerleg.r", "RightFoot": "foot.r", "RightToes": "toes.r"}
## nombre de salida: [clip origen, modo, parámetro]
##   "full": entero · "contact": recorta para que el pico de velocidad de la mano derecha caiga en
##   CONTACT · "trim": [inicio, fin] en s · "loop": entero y en bucle
const CLIPS := {
	"sns_light0": ["xbot_sword_and_shield_slash_1", "contact", 0],
	"sns_light1": ["paladin_sword_and_shield_attack_2", "contact", 0],
	"sns_light2": ["paladin_sword_and_shield_attack", "contact", 0],
	"sns_heavy": ["paladin_sword_and_shield_slash", "contact", 0],
	"gs_light0": ["greatsword_slash", "contact", 0],
	"gs_light1": ["greatsword_slash_5", "contact", 0],
	"gs_light2": ["greatsword_slash_4", "contact", 0],
	"gs_heavy": ["greatsword_attack", "contact", 0],
	"axe_heavy": ["greatsword_high_spin_attack", "contact", 0],
	"gs_idle": ["greatsword_idle", "loop", 0],
	"sns_idle": ["paladin_standing_idle", "loop", 0],
	"light_idle": ["akai_idle", "loop", 0],
	"gs_block": ["greatsword_blocking", "loop", 0],
	"roll_f": ["akai_sprinting_forward_roll_inplace", "full", 0],
	"hit": ["greatsword_impact_4", "full", 0],
	"stun": ["greatsword_impact_2", "full", 0],
	"stance_break": ["akai_tripping", "full", 0],
	"death_2h": ["greatsword_two_handed_sword_death", "full", 0],
	"death_1h": ["akai_sword_and_shield_death", "full", 0],
	"boss_charge": ["paladin_sword_scream", "trim", [0.0, 2.0]],
	"boss_lunge": ["greatsword_slide_attack", "contact", 0],
	"jump_slam": ["greatsword_jump_attack", "contact", 0],
	"cast": ["magic_1h_magic_attack_01", "contact", 0],
	"cast_2h": ["magic_2h_cast_spell_01", "contact", 0],
	"strafe_a": ["greatsword_strafe", "loop", 0],
	"strafe_b": ["greatsword_strafe_2", "loop", 0],
}

var prof := SkeletonProfileHumanoid.new()
var sg_rest: Dictionary = {} ## humanoide -> Basis global de reposo
var tk: Skeleton3D
var tg_rest: Array[Basis] = []

func _initialize() -> void:
	for i in prof.bone_size:
		var n := prof.get_bone_name(i)
		var par := prof.get_bone_parent(i)
		var local := prof.get_reference_pose(i).basis
		sg_rest[n] = (sg_rest[par] * local) if par != &"" else local
	var knight: Node = (load("res://assets/models/Knight.glb") as PackedScene).instantiate()
	tk = knight.find_child("Skeleton3D", true, false) as Skeleton3D
	for i in tk.get_bone_count():
		var p := tk.get_bone_parent(i)
		var b := tk.get_bone_rest(i).basis
		tg_rest.append(tg_rest[p] * b if p >= 0 else b)
	var src := load(SRC) as AnimationLibrary
	var out := AnimationLibrary.new()
	var report := []
	for nm: String in CLIPS:
		var c: Array = CLIPS[nm]
		var a := src.get_animation(c[0])
		var t0 := 0.0
		var t1 := a.length
		match c[1]:
			"contact":
				var tp := _peak_hand(a)
				var L := minf(tp / CONTACT, (a.length - tp) / (1.0 - CONTACT))
				t0 = tp - CONTACT * L
				t1 = tp + (1.0 - CONTACT) * L
			"trim":
				t0 = c[2][0]
				t1 = minf(c[2][1], a.length)
		var anim := _retarget(a, t0, t1)
		anim.loop_mode = Animation.LOOP_LINEAR if c[1] == "loop" else Animation.LOOP_NONE
		out.add_animation(nm, anim)
		report.append("%s<-%s [%.2f-%.2f]" % [nm, c[0], t0, t1])
	print("\n".join(report))
	print("guardado: ", ResourceSaver.save(out, OUT, ResourceSaver.FLAG_COMPRESS))
	knight.free()
	quit()

func _local_rot(a: Animation, bone: String, t: float) -> Quaternion:
	var ti := a.find_track(NodePath("%GeneralSkeleton:" + bone), Animation.TYPE_ROTATION_3D)
	if ti < 0:
		return prof.get_reference_pose(prof.find_bone(bone)).basis.get_rotation_quaternion()
	return a.rotation_track_interpolate(ti, t)

func _globals(a: Animation, t: float) -> Dictionary:
	var g := {}
	for i in prof.bone_size:
		var n := prof.get_bone_name(i)
		var par := prof.get_bone_parent(i)
		var local := Basis(_local_rot(a, n, t))
		g[n] = (g[par] * local) if par != &"" else local
	return g

## Momento del golpe: pico de velocidad angular global del antebrazo+mano derechos.
func _peak_hand(a: Animation) -> float:
	var best := 0.0
	var tb := a.length * 0.5
	var prev: Dictionary = _globals(a, 0.0)
	var t := 1.0 / FPS
	while t <= a.length:
		var g := _globals(a, t)
		var s := 0.0
		for b in ["RightHand", "RightLowerArm"]:
			s += (prev[b] as Basis).get_rotation_quaternion().angle_to((g[b] as Basis).get_rotation_quaternion())
		if s > best and t > 0.15 and t < a.length - 0.1:
			best = s
			tb = t
		prev = g
		t += 1.0 / FPS
	return tb

func _retarget(a: Animation, t0: float, t1: float) -> Animation:
	var anim := Animation.new()
	anim.length = maxf(t1 - t0, 1.0 / FPS)
	var tracks := {}
	var inv_map := {}
	for h: String in MAP:
		inv_map[MAP[h]] = h
	for i in tk.get_bone_count():
		var bn := tk.get_bone_name(i)
		if inv_map.has(bn):
			var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tr, NodePath("Rig/Skeleton3D:" + bn))
			tracks[i] = tr
	var hp := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hp, NodePath("Rig/Skeleton3D:hips"))
	var hip_src := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
	var src_rest_h := prof.get_reference_pose(prof.find_bone("Hips")).origin
	var hips_i := tk.find_bone("hips")
	var tgt_rest_h := tk.get_bone_rest(hips_i).origin
	var k := tgt_rest_h.y / maxf(src_rest_h.y, 0.01)
	var y0 := a.position_track_interpolate(hip_src, 0.0).y if hip_src >= 0 else src_rest_h.y
	var n := int(round(anim.length * FPS))
	for f in n + 1:
		var tt := minf(f / FPS, anim.length)
		var ts := t0 + tt
		var g := _globals(a, ts)
		var tgp: Array[Basis] = []
		tgp.resize(tk.get_bone_count())
		for i in tk.get_bone_count():
			var p := tk.get_bone_parent(i)
			var bn := tk.get_bone_name(i)
			var D: Basis
			if inv_map.has(bn):
				var h: String = inv_map[bn]
				D = (g[h] as Basis) * (sg_rest[h] as Basis).inverse()
			elif p >= 0:
				D = tgp[p] * tg_rest[p].inverse()
			else:
				D = Basis()
			tgp[i] = D * tg_rest[i]
			if tracks.has(i):
				var loc := (tgp[p].inverse() * tgp[i]) if p >= 0 else tgp[i]
				anim.rotation_track_insert_key(tracks[i], tt, loc.get_rotation_quaternion().normalized())
		var y := tgt_rest_h.y
		if hip_src >= 0:
			# altura relativa al primer fotograma del clip original (los clips de Mixamo arrancan de pie)
			y = tgt_rest_h.y + (a.position_track_interpolate(hip_src, ts).y - y0) * k
		anim.position_track_insert_key(hp, tt, Vector3(tgt_rest_h.x, y, tgt_rest_h.z))
	return anim
