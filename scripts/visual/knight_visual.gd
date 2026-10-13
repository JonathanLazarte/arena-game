class_name KnightVisual
extends Node3D
## Caballero KayKit (CC0) con AnimationTree. Solo es visual: la detección de
## golpes sigue en Fighter (arcos), esto únicamente refleja su estado.
##
## Árbol: base (Transition: a pie = BlendSpace2D Idle/Walk/Run/Strafe/Back,
## montado = Sit_Chair_Pose) -> mix (Blend2, filtro de medio cuerpo superior)
## <- act (StateMachine con los estados de combate).

const SCENE := preload("res://assets/models/Knight.glb")
const TEX := preload("res://assets/models/knight_texture.png")
const SCALE := 0.85
const MOUNT_Y := -0.36 ## baja el modelo para que la cadera (sentada) quede en el origen = punto de silla
const CONTACT := 0.42 ## fracción del clip de ataque en la que la hoja impacta
const UPPER := ["spine", "chest", "upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r", "head",
	"elbowIK.l", "handIK.l", "elbowIK.r", "handIK.r"]
const LIGHTS := ["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop"]
const STATES := {
	"none": "Idle", "light0": LIGHTS[0], "light1": LIGHTS[1], "light2": LIGHTS[2],
	"heavy": "2H_Melee_Attack_Chop", "block": "Blocking", "block_hit": "Block_Hit",
	"parry": "Block_Attack", "dodge_f": "Dodge_Forward", "dodge_b": "Dodge_Backward",
	"dodge_l": "Dodge_Left", "dodge_r": "Dodge_Right", "hit": "Hit_A", "stun": "Hit_B",
	"death": "Death_A", "aim": "2H_Ranged_Aiming", "shoot": "2H_Ranged_Shoot", "swap": "Use_Item",
	# Ronda 14
	"dash_strike": DASH_STRIKE_ANIM, "jump_up": "Jump_Start", "jump_air": "Jump_Idle", "land": "Jump_Land",
	"slam": "2H_Melee_Attack_Chop",
}
const SCALED := ["light0", "light1", "light2", "heavy", "swap", "parry", "dodge_f", "dodge_b", "dodge_l", "dodge_r", "dash_strike", "slam"]
## Animación propia (KayKit no trae una estocada en carrera): se compone en Godot a partir de
## Dodge_Forward (piernas y cadera: el impulso de la zancada) y 1H_Melee_Attack_Slice_Horizontal
## (tronco y brazos: el tajo), con el tronco inclinado hacia delante durante la arremetida.
const DASH_STRIKE_ANIM := "Dash_Strike"
const DASH_STRIKE_LEN := 0.8
const DASH_STRIKE_SLICE := 0.75 ## fracción del tajo usada
const DS_CONTACT := CONTACT / DASH_STRIKE_SLICE ## momento del impacto dentro de Dash_Strike
## Estados que solo afectan al tren superior aunque se vaya a pie.
const UPPER_STATES := ["block", "block_hit", "aim", "shoot", "swap"]

var model: Node3D
var ap: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var mix: AnimationNodeBlend2
var sword: MeshInstance3D
var shield: MeshInstance3D
var bow: MeshInstance3D
var glow_mat: StandardMaterial3D
var body_mat: StandardMaterial3D
var accent_mat: StandardMaterial3D
var tint: Color = Color.WHITE
var state: String = "none"
var oneshot: String = ""
var oneshot_t: float = 0.0
var _weight: float = 0.0
var _last_attack_id: int = -1
var riding: RidingPose
var _mounted: bool = false

var cdef: CharacterDef
var wdef: WeaponDef
var sword_l: MeshInstance3D ## segunda arma (dagas)
var states: Dictionary = STATES.duplicate()
var _char_tint: Color = Color.WHITE

## c: color de equipo. cd/wd: personaje y arma (null = Caballero con espada y escudo).
func setup(c: Color, cd: CharacterDef = null, wd: WeaponDef = null) -> void:
	cdef = cd if cd else load("res://resources/characters/caballero.tres") as CharacterDef
	wdef = wd if wd else load("res://resources/weapons/espada_escudo.tres") as WeaponDef
	var melee_w := wdef
	if wdef.ranged:
		melee_w = load("res://resources/weapons/dagas.tres") as WeaponDef
	for i in 3:
		states["light%d" % i] = melee_w.anim_light[i % melee_w.anim_light.size()]
	states["heavy"] = melee_w.anim_heavy
	tint = c
	_char_tint = cdef.tint
	model = (load(cdef.model_path) as PackedScene).instantiate() as Node3D
	model.rotation.y = PI # KayKit mira a +Z; el juego usa -Z como frente
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_texture = load(cdef.texture_path)
	accent_mat = body_mat.duplicate() as StandardMaterial3D
	set_tint(c, false)
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var own_shield := melee_w.allows_shield and cdef.shield_mesh != ""
	for mi in AnimUtil.meshes(model):
		var n := String(mi.name)
		if not n.begins_with(cdef.body_prefix) or n.contains("Shield"):
			mi.visible = false
		mi.material_override = accent_mat if n.ends_with("Cape") else body_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if melee_w.procedural == "lanza":
		sword = _make_lance(sk)
	else:
		sword = _weapon_mesh(sk, melee_w.mesh_source, melee_w.mesh_right)
	if melee_w.mesh_left != "":
		sword_l = _weapon_mesh(sk, melee_w.mesh_source, melee_w.mesh_left)
	if own_shield:
		shield = _weapon_mesh(sk, cdef.shield_source, cdef.shield_mesh)
		shield.material_override = accent_mat
	else:
		# Escudo invisible de relleno (así el resto del código no tiene casos nulos)
		shield = MeshInstance3D.new()
		shield.name = "NoShield"
		sk.add_child(shield)
	sword.material_override = body_mat if sword.material_override == null else sword.material_override
	glow_mat = StandardMaterial3D.new()
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color.BLACK
	glow_mat.roughness = 1.0
	glow_mat.metallic_specular = 0.0
	sword.material_overlay = glow_mat
	# Arco: arma propia enganchada a la mano izquierda con BoneAttachment3D
	var att := BoneAttachment3D.new()
	att.name = "bow_slot"
	att.bone_name = "handslot.l"
	sk.add_child(att)
	bow = MeshUtil.box(att, Vector3(0.1, 1.8, 0.14), Vector3.ZERO, Color(0.5, 0.3, 0.12))
	MeshUtil.box(bow, Vector3(0.02, 1.7, 0.02), Vector3(0, 0, 0.25), Color(0.9, 0.9, 0.85)) # cuerda
	bow.visible = false
	# Postura a horcajadas sobre el AnimationTree (SkeletonModifier3D)
	riding = RidingPose.new()
	riding.name = "RidingPose"
	sk.add_child(riding)
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	AnimUtil.set_loops(ap, ["Idle", "Walking_A", "Walking_Backwards", "Running_A", "Running_Strafe_Left",
		"Running_Strafe_Right", "Blocking", "2H_Ranged_Aiming", "Sit_Chair_Pose", "Jump_Idle"])
	author_dash_strike(ap, states["light1"])
	_build_tree()

## Malla de arma: la del propio modelo si existe, o copiada de otro .glb KayKit
## (mismo hueso handslot y misma transformación local).
func _weapon_mesh(sk: Skeleton3D, source: String, mesh_name: String) -> MeshInstance3D:
	var own := model.find_child(mesh_name, true, false) as MeshInstance3D
	if own:
		own.visible = true
		return own
	var src := (load(source) as PackedScene).instantiate() as Node3D
	var smi := src.find_child(mesh_name, true, false) as MeshInstance3D
	var bone := "handslot.l" if mesh_name.contains("Offhand") or mesh_name.contains("Shield") else "handslot.r"
	if smi and smi.get_parent() is BoneAttachment3D:
		bone = (smi.get_parent() as BoneAttachment3D).bone_name
	var att := BoneAttachment3D.new()
	att.name = mesh_name + "_slot"
	att.bone_name = bone
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	if smi:
		mi.mesh = smi.mesh
		mi.transform = smi.transform
		var tex := (smi.get_active_material(0) as BaseMaterial3D)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex.albedo_texture if tex else null
		mi.material_override = m
	else:
		mi.mesh = BoxMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	att.add_child(mi)
	src.free()
	return mi

## Lanza procedimental: asta larga de madera y punta metálica.
func _make_lance(sk: Skeleton3D) -> MeshInstance3D:
	var att := BoneAttachment3D.new()
	att.name = "lance_slot"
	att.bone_name = "handslot.r"
	sk.add_child(att)
	var shaft := MeshUtil.box(att, Vector3(0.07, 2.6, 0.07), Vector3(0, 0.7, 0), Color(0.45, 0.3, 0.15))
	shaft.name = "Lanza"
	var tip := MeshUtil.box(shaft, Vector3(0.14, 0.4, 0.05), Vector3(0, 1.45, 0), Color(0.8, 0.82, 0.9))
	tip.rotation.y = PI / 4
	return shaft

## Crea la animación Dash_Strike en la biblioteca del AnimationPlayer (una vez por modelo).
## Muestrea a 30 fps: tren superior = tajo (re-temporizado), tren inferior = arranque de la
## voltereta hacia delante mezclado de vuelta a la pose del tajo, y un "override" de hueso
## (spine/chest) que inclina el tronco en la arremetida.
static func author_dash_strike(player: AnimationPlayer, slice_name: String = "1H_Melee_Attack_Slice_Horizontal") -> Animation:
	if player.has_animation(DASH_STRIKE_ANIM):
		return player.get_animation(DASH_STRIKE_ANIM)
	if not player.has_animation(slice_name):
		slice_name = "1H_Melee_Attack_Slice_Horizontal"
	var atk := player.get_animation(slice_name)
	var dodge := player.get_animation("Dodge_Forward")
	var anim := Animation.new()
	anim.length = DASH_STRIKE_LEN
	var fps := 30.0
	var n := int(DASH_STRIKE_LEN * fps)
	var la := atk.length * DASH_STRIKE_SLICE
	var lunge_end := DASH_STRIKE_LEN * 0.35
	for i in atk.get_track_count():
		var ty := atk.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var path := atk.track_get_path(i)
		var bone := String(path.get_concatenated_subnames())
		var upper := bone in UPPER
		var di := dodge.find_track(path, ty) if dodge else -1
		var use_dodge := not upper and di >= 0 and bone != "root" and ty != Animation.TYPE_SCALE_3D
		var nt := anim.add_track(ty)
		anim.track_set_path(nt, path)
		for k in n + 1:
			var t := k / fps
			var ta := t / DASH_STRIKE_LEN * la
			# peso de la zancada: 1 al principio, se funde con la pose del tajo hacia el final
			var w := 1.0 - smoothstep(lunge_end, DASH_STRIKE_LEN * 0.85, t)
			var td := minf(t, lunge_end) / lunge_end * dodge.length * 0.22 if dodge else 0.0
			var lean := sin(clampf(t / (DASH_STRIKE_LEN * 0.6), 0.0, 1.0) * PI) * deg_to_rad(16.0)
			match ty:
				Animation.TYPE_ROTATION_3D:
					var q := atk.rotation_track_interpolate(i, ta)
					if use_dodge:
						q = q.slerp(dodge.rotation_track_interpolate(di, td), w)
					if bone == "spine" or bone == "chest":
						q = q * Quaternion(Vector3.RIGHT, lean * 0.5)
					anim.rotation_track_insert_key(nt, t, q.normalized())
				Animation.TYPE_POSITION_3D:
					var pv := atk.position_track_interpolate(i, ta)
					if use_dodge:
						pv = pv.lerp(dodge.position_track_interpolate(di, td), w)
					anim.position_track_insert_key(nt, t, pv)
				_:
					anim.scale_track_insert_key(nt, t, atk.scale_track_interpolate(i, ta))
	var lib := player.get_animation_library(&"")
	if lib and not lib.has_animation(DASH_STRIKE_ANIM):
		lib.add_animation(DASH_STRIKE_ANIM, anim)
	return anim

func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.add_blend_point(AnimUtil.anim_node("Idle"), Vector2(0, 0), -1, &"Idle")
	loco.add_blend_point(AnimUtil.anim_node("Walking_A"), Vector2(0, 0.45), -1, &"Walking_A")
	loco.add_blend_point(AnimUtil.anim_node("Running_A"), Vector2(0, 1.0), -1, &"Running_A")
	loco.add_blend_point(AnimUtil.anim_node("Walking_Backwards"), Vector2(0, -0.6), -1, &"Walking_Backwards")
	loco.add_blend_point(AnimUtil.anim_node("Running_Strafe_Left"), Vector2(-1, 0), -1, &"Running_Strafe_Left")
	loco.add_blend_point(AnimUtil.anim_node("Running_Strafe_Right"), Vector2(1, 0), -1, &"Running_Strafe_Right")
	loco.min_space = Vector2(-1, -1)
	loco.max_space = Vector2(1, 1.3)
	root.add_node("loco", loco)
	root.add_node("sit", AnimUtil.anim_node("Sit_Chair_Pose"))
	var base := AnimationNodeTransition.new()
	base.add_input("foot")
	base.add_input("mounted")
	base.xfade_time = 0.15
	root.add_node("base", base)
	root.connect_node("base", 0, "loco")
	root.connect_node("base", 1, "sit")
	var act := AnimationNodeStateMachine.new()
	for s: String in STATES:
		act.add_node(s, AnimUtil.scaled_anim(states[s]) if s in SCALED else AnimUtil.anim_node(states[s]))
	for a: String in STATES:
		for b: String in STATES:
			if a != b:
				var tr := AnimationNodeStateMachineTransition.new()
				tr.xfade_time = 0.08
				act.add_transition(a, b, tr)
	act.add_transition("Start", "none", AnimationNodeStateMachineTransition.new())
	root.add_node("act", act)
	mix = AnimationNodeBlend2.new()
	for b: String in UPPER:
		mix.set_filter_path(NodePath("Rig/Skeleton3D:" + b), true)
	root.add_node("mix", mix)
	root.connect_node("mix", 0, "base")
	root.connect_node("mix", 1, "act")
	root.connect_node("output", 0, "mix")
	tree = AnimationTree.new()
	tree.tree_root = root
	model.add_child(tree)
	tree.root_node = NodePath("..")
	tree.anim_player = tree.get_path_to(ap)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.active = true
	playback = tree.get("parameters/act/playback") as AnimationNodeStateMachinePlayback
	playback.start("none")

func set_tint(c: Color, flash: bool) -> void:
	body_mat.albedo_color = Color.WHITE.lerp(c, 0.25) * _char_tint
	accent_mat.albedo_color = Color.WHITE.lerp(c, 0.9) * _char_tint
	for m: StandardMaterial3D in [body_mat, accent_mat]:
		m.emission_enabled = flash
		m.emission = Color.WHITE
		m.emission_energy_multiplier = 0.8

func set_glow(on: bool, c: Color) -> void:
	glow_mat.albedo_color = c * 0.8 if on else Color.BLACK

## loadout: 0 espada+escudo, 1 arco, -1 cambiando (manos vacías)
func set_loadout(l: int) -> void:
	sword.visible = l == 0
	if sword_l:
		sword_l.visible = l == 0
	shield.visible = l == 0
	bow.visible = l == 1

func set_mounted(m: bool, sword_scale: float) -> void:
	tree.set("parameters/base/transition_request", "mounted" if m else "foot")
	model.position.y = MOUNT_Y if m else 0.0
	_mounted = m
	sword.scale = Vector3(1.0, sword_scale, 1.0)

## Evento puntual: "hit", "block_hit", "shoot".
func event(e: String) -> void:
	oneshot = e
	oneshot_t = {"hit": 0.4, "block_hit": 0.45, "shoot": 0.5, "slam": Fighter.SLAM_TELEGRAPH + 0.25}.get(e, 0.4)
	_last_attack_id = -1
	if e == state:
		playback.start(e, true)

func _clip_len(s: String) -> float:
	return ap.get_animation(states[s]).length

func update(f: Fighter, delta: float) -> void:
	oneshot_t = maxf(oneshot_t - delta, 0.0)
	riding.amount = move_toward(riding.amount, 1.0 if _mounted and f.alive else 0.0, delta * 6.0)
	var s := "none"
	var upper: bool = f.mounted
	if not f.alive:
		s = "death"
		upper = false
	elif f.stun > 0.0 and f.atk_state == Fighter.Atk.NONE:
		s = "stun"
	elif f.is_dash_striking():
		s = "dash_strike"
	elif f.atk_state != Fighter.Atk.NONE:
		s = "heavy" if f.atk_heavy or f.atk_jump else "light%d" % (maxi(f.combo - 1, 0) % 3)
	elif f.special_t > 0.0 or (oneshot == "slam" and oneshot_t > 0.0):
		s = "slam"
	elif f.swap_t > 0.0:
		s = "swap"
	elif f.parry_state != Fighter.Parry.NONE:
		s = "parry"
	elif f.is_rolling() and not f.mounted:
		var rel := Vector2(f.dash_dir.dot(f.facing.cross(Vector3.UP)), f.dash_dir.dot(f.facing))
		if absf(rel.x) > absf(rel.y):
			s = "dodge_r" if rel.x > 0.0 else "dodge_l"
		else:
			s = "dodge_f" if rel.y >= 0.0 else "dodge_b"
	elif f.airborne and not f.mounted:
		s = "jump_up" if f.velocity.y > 1.5 else "jump_air"
	elif f.land_t > 0.0 and not f.mounted:
		s = "land"
	elif oneshot_t > 0.0:
		s = oneshot
	elif f.blocking:
		s = "block"
	elif f.loadout == Fighter.Loadout.BOW:
		s = "aim"
	if s in UPPER_STATES:
		upper = true
	# Ataques: reinicia el clip en cada ataque nuevo y ajusta su velocidad por fase
	if s == "dash_strike":
		if f.attacks_started != _last_attack_id:
			_last_attack_id = f.attacks_started
			playback.start(s, true)
		var Ld := _clip_len(s)
		var scd := 1.0
		match f.atk_state:
			Fighter.Atk.WINDUP:
				scd = Ld * DS_CONTACT / maxf(f.atk_dur, 0.05)
			Fighter.Atk.ACTIVE:
				scd = Ld * 0.12 / maxf(f.atk_dur, 0.05)
			Fighter.Atk.RECOVERY:
				scd = Ld * maxf(1.0 - DS_CONTACT - 0.12, 0.05) / maxf(f.atk_dur, 0.05)
		tree.set("parameters/act/dash_strike/ts/scale", scd)
	elif s == "slam":
		tree.set("parameters/act/slam/ts/scale", _clip_len("slam") * CONTACT / Fighter.SLAM_TELEGRAPH)
	elif s == "heavy" or s.begins_with("light"):
		if f.attacks_started != _last_attack_id:
			_last_attack_id = f.attacks_started
			playback.start(s, true)
		var L := _clip_len(s)
		var sc := 1.0
		match f.atk_state:
			Fighter.Atk.WINDUP:
				sc = L * CONTACT / maxf(f.atk_dur, 0.05)
			Fighter.Atk.ACTIVE:
				sc = L * (0.62 - CONTACT) / maxf(f.atk_dur, 0.05)
			Fighter.Atk.RECOVERY:
				sc = L * 0.38 / maxf(f.atk_dur, 0.05)
		tree.set("parameters/act/%s/ts/scale" % s, sc)
	elif s == "swap":
		tree.set("parameters/act/swap/ts/scale", _clip_len("swap") / Fighter.SWAP_TIME)
	elif s.begins_with("dodge"):
		# La voltereta (Dodge_* de KayKit) dura exactamente ROLL_TOTAL (24 frames a 30 fps)
		tree.set("parameters/act/%s/ts/scale" % s, _clip_len(s) / Fighter.ROLL_TOTAL)
	elif s == "parry":
		tree.set("parameters/act/parry/ts/scale", _clip_len("parry") / (Fighter.PARRY_WINDOW + Fighter.PARRY_RECOVERY))
	if s != state:
		if s != "none":
			if state == "none" or s in ["death", "stun", "hit", "block_hit", "shoot", "dash_strike", "jump_up", "land", "slam"] or s.begins_with("dodge"):
				playback.start(s, true)
			else:
				playback.travel(s)
		state = s
	_weight = move_toward(_weight, 0.0 if s == "none" else 1.0, delta * 10.0)
	mix.filter_enabled = upper
	tree.set("parameters/mix/blend_amount", _weight)
	# Locomoción relativa a la mirada
	var st := f.stats()
	var v := MeshUtil.flat(f.planar_vel) / maxf(st.speed, 0.1)
	var bp := Vector2(v.dot(f.facing.cross(Vector3.UP)), v.dot(f.facing))
	tree.set("parameters/loco/blend_position", bp)
