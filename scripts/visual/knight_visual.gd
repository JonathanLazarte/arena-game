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
const TRAIL_LIFE := 0.24
const TRAIL_MAX_SAMPLES := 18
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
	"reload": "2H_Ranged_Reload", # Ronda 17 (ballesta)
	# Ronda 14
	"dash_strike": DASH_STRIKE_ANIM, "jump_up": "Jump_Start", "jump_air": "Jump_Idle", "land": "Jump_Land",
	"slam": "2H_Melee_Attack_Chop",
	# Ronda 28 (por defecto KayKit; con la biblioteca Mixamo se sustituyen, ver MX_*)
	"boss_charge": "Blocking", "boss_lunge": DASH_STRIKE_ANIM, "stance_break": "Hit_B", "cast": "Use_Item",
	# Ronda 31: derribo y levantarse (clips nativos KayKit)
	"down": "Lie_Down", "getup": "Lie_StandUp",
}
const SCALED := ["down", "getup", "boss_charge", "boss_lunge", "stance_break", "cast", "hit", "stun", "reload", "aim", "light0", "light1", "light2", "heavy", "swap", "parry", "dodge_f", "dodge_b", "dodge_l", "dodge_r", "dash_strike", "slam"]
## Animación propia (KayKit no trae una estocada en carrera): se compone en Godot a partir de
## Dodge_Forward (piernas y cadera: el impulso de la zancada) y 1H_Melee_Attack_Slice_Horizontal
## (tronco y brazos: el tajo), con el tronco inclinado hacia delante durante la arremetida.
const DASH_STRIKE_ANIM := "Dash_Strike"
const DASH_STRIKE_LEN := 0.8
const DASH_STRIKE_SLICE := 0.75 ## fracción del tajo usada
const DS_CONTACT := CONTACT / DASH_STRIKE_SLICE ## momento del impacto dentro de Dash_Strike
## Puntos extra de locomoción: nombre -> [clip, posición (lateral, adelante), velocidad del clip].
## La posición es la velocidad relativa a la mirada / velocidad base (correr = ~1,3).
const LOCO_SPEEDS := {
	"Run_Fwd": ["Running_A", Vector2(0, 1.35), 1.15],
	"Run_Back": ["Walking_Backwards", Vector2(0, -1.1), 1.9],
	"Walk_Strafe_L": ["Running_Strafe_Left", Vector2(-0.45, 0), 0.6],
	"Walk_Strafe_R": ["Running_Strafe_Right", Vector2(0.45, 0), 0.6],
	"Run_Strafe_L": ["Running_Strafe_Left", Vector2(-1.35, 0), 1.2],
	"Run_Strafe_R": ["Running_Strafe_Right", Vector2(1.35, 0), 1.2],
}
## Ronda 28: animaciones Mixamo (vía Souls-Combat) reapuntadas al rig KayKit sin traslación
## horizontal de caderas (tools/retarget_kaykit.gd). Sustituyen a los clips KayKit donde encajan mejor.
const MX_LIB := preload("res://assets/animations/mixamo/lib_kaykit.res")
const MX := "mx/"
## Comunes a todos los personajes a pie.
const MX_COMMON := {"dodge_f": "roll_f", "hit": "hit", "stun": "stun", "stance_break": "stance_break",
	"slam": "jump_slam", "boss_charge": "boss_charge", "boss_lunge": "boss_lunge", "cast": "cast"}
## Por arma: combos, pesado, guardia, reposo y muerte.
const MX_WEAPON := {
	"espada_escudo": {"light0": "sns_light0", "light1": "sns_light1", "light2": "sns_light2", "heavy": "sns_heavy", "idle": "sns_idle", "death": "death_1h"},
	"espada_larga": {"light0": "gs_light0", "light1": "gs_light1", "light2": "gs_light2", "heavy": "gs_heavy", "block": "gs_block", "idle": "gs_idle", "death": "death_2h"},
	"hacha_2m": {"light0": "gs_light1", "light1": "gs_light0", "light2": "gs_light2", "heavy": "axe_heavy", "block": "gs_block", "idle": "gs_idle", "death": "death_2h"},
	"lanza": {"death": "death_2h"},
	# Ronda 29: dagas = tajos a una mano (Mixamo no trae cuchilladas dobles) (asesino y arquero: su arma cuerpo a cuerpo)
	"dagas": {"light0": "sns_light0", "light1": "sns_light2", "light2": "sns_light1", "heavy": "sns_heavy", "idle": "light_idle", "death": "death_1h"},
}
## Strafe caminando (KayKit solo trae strafe corriendo): clips Mixamo de espadón.
const MX_LOCO := {"Walk_Strafe_L": "strafe_a", "Walk_Strafe_R": "strafe_b"}
var idle_clip: String = "Idle"

## Estados que solo afectan al tren superior aunque se vaya a pie.
const UPPER_STATES := ["block", "block_hit", "aim", "shoot", "swap", "reload"]

var model: Node3D
var ap: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var mix: AnimationNodeBlend2
var sword: MeshInstance3D
var shield: MeshInstance3D
var offhand_weapon_mesh: MeshInstance3D
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
var _sword_trail: MeshInstance3D
var _sword_trail_mesh: ArrayMesh
var _sword_trail_material: StandardMaterial3D
var _trail_samples: Array[Dictionary] = []
var _trail_override_t: float = 0.0
var _trail_override_color: Color = Color.WHITE

## c: color de equipo. cd/wd: personaje y arma (null = Caballero con espada y escudo).
func setup(c: Color, cd: CharacterDef = null, wd: WeaponDef = null, offhand_def: WeaponDef = null, ranged_def: WeaponDef = null) -> void:
	cdef = cd if cd else load("res://resources/characters/caballero.tres") as CharacterDef
	wdef = wd if wd else load("res://resources/weapons/espada_escudo.tres") as WeaponDef
	var melee_w := wdef
	if wdef.ranged:
		melee_w = load("res://resources/weapons/dagas.tres") as WeaponDef
	for i in 3:
		states["light%d" % i] = melee_w.anim_light[i % melee_w.anim_light.size()]
	states["heavy"] = melee_w.anim_heavy
	var rw: WeaponDef = ranged_def if ranged_def else (wdef if wdef.ranged else load("res://resources/weapons/arco.tres") as WeaponDef)
	states["aim"] = rw.anim_aim
	states["shoot"] = rw.anim_shoot
	states["reload"] = rw.anim_reload
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
	var own_shield := cdef.shield_mesh != ""
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
	if offhand_def:
		var offhand_mesh_name := offhand_def.mesh_left if offhand_def.mesh_left != "" else offhand_def.mesh_right
		offhand_weapon_mesh = _weapon_mesh(sk, offhand_def.mesh_source, offhand_mesh_name, true)
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
	_create_sword_trail()
	# Arco: arma propia enganchada a la mano izquierda con BoneAttachment3D
	var att := BoneAttachment3D.new()
	att.name = "bow_slot"
	att.bone_name = "handslot.l"
	sk.add_child(att)
	bow = MeshUtil.box(att, Vector3(0.1, 1.8, 0.14), Vector3.ZERO, Color(0.5, 0.3, 0.12))
	MeshUtil.box(bow, Vector3(0.02, 1.7, 0.02), Vector3(0, 0, 0.25), Color(0.9, 0.9, 0.85)) # cuerda
	if rw.procedural == "ballesta":
		# Ronda 17: ballesta = malla «1H_Crossbow» del Rogue (KayKit Adventurers, CC0)
		bow.queue_free()
		bow = _weapon_mesh(sk, rw.mesh_source, rw.mesh_right)
		bow.name = "Ballesta"
	bow.visible = false
	# Postura a horcajadas sobre el AnimationTree (SkeletonModifier3D)
	riding = RidingPose.new()
	riding.name = "RidingPose"
	sk.add_child(riding)
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	AnimUtil.set_loops(ap, ["Idle", "Walking_A", "Walking_Backwards", "Running_A", "Running_Strafe_Left",
		"Running_Strafe_Right", "Blocking", "2H_Ranged_Aiming", "Sit_Chair_Pose", "Jump_Idle"])
	author_dash_strike(ap, melee_w.anim_light[1 % melee_w.anim_light.size()])
	# Ronda 16: combo de 3 golpes con clips propios (espejados / encadenados en Godot)
	if not melee_w.combo.is_empty():
		for i in 3:
			var h := melee_w.combo_hit(i, cdef)
			states["light%d" % i] = author_combo_clip(ap, h)
	_apply_mixamo(melee_w)
	_build_tree()

## Ronda 28: clips Mixamo reapuntados (biblioteca «mx») para las acciones donde encajan mejor.
func _apply_mixamo(melee_w: WeaponDef) -> void:
	if MX_LIB == null or ap == null:
		return
	if not ap.has_animation_library(&"mx"):
		ap.add_animation_library(&"mx", MX_LIB)
	var table: Dictionary = MX_COMMON.duplicate()
	table.merge(MX_WEAPON.get(melee_w.id, {}), true)
	for k: String in table:
		var clip: String = MX + String(table[k])
		if not ap.has_animation(clip):
			continue
		if k == "idle":
			idle_clip = clip
		elif states.has(k):
			states[k] = clip
	for k: String in MX_LOCO:
		if ap.has_animation(MX + String(MX_LOCO[k])):
			_loco_clips[k] = MX + String(MX_LOCO[k])
var _loco_clips: Dictionary = {}

## Malla de arma: la del propio modelo si existe, o copiada de otro .glb KayKit
## (mismo hueso handslot y misma transformación local).
func _weapon_mesh(sk: Skeleton3D, source: String, mesh_name: String, force_left: bool = false) -> MeshInstance3D:
	var own: MeshInstance3D = null
	if not force_left:
		own = model.find_child(mesh_name, true, false) as MeshInstance3D
	if own:
		own.visible = true
		return own
	var src := (load(source) as PackedScene).instantiate() as Node3D
	var smi := src.find_child(mesh_name, true, false) as MeshInstance3D
	var bone := "handslot.l" if force_left or mesh_name.contains("Offhand") or mesh_name.contains("Shield") else "handslot.r"
	if not force_left and smi and smi.get_parent() is BoneAttachment3D:
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

static func _mirror_bone(b: String) -> String:
	if b.ends_with(".l"):
		return b.substr(0, b.length() - 2) + ".r"
	if b.ends_with(".r"):
		return b.substr(0, b.length() - 2) + ".l"
	return b

## Ronda 16: crea (una vez por biblioteca) el clip de un golpe de combo y devuelve su nombre.
## - reverse: el clip al revés (revés con el mismo brazo, empieza en el final del tajo anterior).
## - mirror: espejo izquierda<->derecha (intercambia huesos .l/.r y refleja en X: rotación
##   (x, -y, -z, w), posición (-x, y, z)), para que el 2.º tajo vuelva en sentido contrario.
## - then_anim: concatena dos clips (primera parte de `anim` hasta `split`, después `then_anim`),
##   con 0,06 s de fundido; p. ej. golpe de escudo + estocada.
static func author_combo_clip(player: AnimationPlayer, h: ComboHit) -> String:
	var nm := h.clip_name()
	if player.has_animation(nm):
		return nm
	if not player.has_animation(h.anim):
		return "1H_Melee_Attack_Slice_Horizontal"
	var src := player.get_animation(h.anim)
	var anim: Animation
	if h.then_anim != "" and player.has_animation(h.then_anim):
		anim = _concat(src, player.get_animation(h.then_anim), h.split)
	elif h.mirror or h.reverse:
		anim = _mirrored(src) if h.mirror else src
		if h.reverse:
			anim = _reversed(anim)
	else:
		return h.anim
	var lib := player.get_animation_library(&"")
	if lib and not lib.has_animation(nm):
		lib.add_animation(nm, anim)
	return nm

static func _mirrored(src: Animation) -> Animation:
	var anim := Animation.new()
	anim.length = src.length
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var path := src.track_get_path(i)
		var bone := String(path.get_concatenated_subnames())
		var np := NodePath(String(path.get_concatenated_names()) + ":" + _mirror_bone(bone))
		var nt := anim.add_track(ty)
		anim.track_set_path(nt, np)
		for k in src.track_get_key_count(i):
			var t := src.track_get_key_time(i, k)
			var v = src.track_get_key_value(i, k)
			match ty:
				Animation.TYPE_ROTATION_3D:
					var q: Quaternion = v
					anim.rotation_track_insert_key(nt, t, Quaternion(q.x, -q.y, -q.z, q.w))
				Animation.TYPE_POSITION_3D:
					var pv: Vector3 = v
					anim.position_track_insert_key(nt, t, Vector3(-pv.x, pv.y, pv.z))
				_:
					anim.scale_track_insert_key(nt, t, v)
	return anim

static func _reversed(src: Animation) -> Animation:
	var anim := Animation.new()
	anim.length = src.length
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var nt := anim.add_track(ty)
		anim.track_set_path(nt, src.track_get_path(i))
		for k in src.track_get_key_count(i):
			var t := src.length - src.track_get_key_time(i, k)
			var v = src.track_get_key_value(i, k)
			match ty:
				Animation.TYPE_ROTATION_3D: anim.rotation_track_insert_key(nt, t, v)
				Animation.TYPE_POSITION_3D: anim.position_track_insert_key(nt, t, v)
				_: anim.scale_track_insert_key(nt, t, v)
	return anim

static func _concat(a: Animation, b: Animation, split: float) -> Animation:
	var anim := Animation.new()
	var la := a.length * split
	var blend := 0.06
	anim.length = la + b.length * 0.85
	var fps := 30.0
	var n := int(anim.length * fps)
	for i in a.get_track_count():
		var ty := a.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var path := a.track_get_path(i)
		var bi := b.find_track(path, ty)
		var nt := anim.add_track(ty)
		anim.track_set_path(nt, path)
		for k in n + 1:
			var t := k / fps
			var ta := minf(t, la)
			var tb := clampf(t - la, 0.0, b.length)
			var w := clampf((t - la + blend) / (2.0 * blend), 0.0, 1.0) if bi >= 0 else 0.0
			match ty:
				Animation.TYPE_ROTATION_3D:
					var q := a.rotation_track_interpolate(i, ta)
					if bi >= 0:
						q = q.slerp(b.rotation_track_interpolate(bi, tb), w)
					anim.rotation_track_insert_key(nt, t, q.normalized())
				Animation.TYPE_POSITION_3D:
					var pv := a.position_track_interpolate(i, ta)
					if bi >= 0:
						pv = pv.lerp(b.position_track_interpolate(bi, tb), w)
					anim.position_track_insert_key(nt, t, pv)
				_:
					anim.scale_track_insert_key(nt, t, a.scale_track_interpolate(i, ta))
	return anim

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
	loco.add_blend_point(AnimUtil.anim_node(idle_clip), Vector2(0, 0), -1, &"Idle")
	loco.add_blend_point(AnimUtil.anim_node("Walking_A"), Vector2(0, 0.45), -1, &"Walking_A")
	loco.add_blend_point(AnimUtil.anim_node("Running_A"), Vector2(0, 1.0), -1, &"Running_A")
	loco.add_blend_point(AnimUtil.anim_node("Walking_Backwards"), Vector2(0, -0.45), -1, &"Walking_Backwards")
	loco.add_blend_point(AnimUtil.anim_node("Running_Strafe_Left"), Vector2(-1, 0), -1, &"Running_Strafe_Left")
	loco.add_blend_point(AnimUtil.anim_node("Running_Strafe_Right"), Vector2(1, 0), -1, &"Running_Strafe_Right")
	# Ronda 15: locomoción direccional para correr fijado (souls). KayKit no trae carrera hacia
	# atrás ni strafe caminando: se reutilizan clips acelerados/ralentizados (ver LOCO_SPEEDS).
	for nm: String in LOCO_SPEEDS:
		var lc: String = _loco_clips.get(nm, LOCO_SPEEDS[nm][0])
		loco.add_blend_point(AnimUtil.scaled_anim(lc), LOCO_SPEEDS[nm][1], -1, StringName(nm))
	loco.min_space = Vector2(-1.4, -1.4)
	loco.max_space = Vector2(1.4, 1.4)
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
				tr.xfade_time = 0.14 if "swap" in [a, b] else 0.08
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
	for nm: String in LOCO_SPEEDS:
		# los strafes Mixamo andan a ~1,2 m/s: velocidad 1 al caminar
		tree.set("parameters/loco/%s/ts/scale" % nm, 1.0 if _loco_clips.has(nm) else LOCO_SPEEDS[nm][2])
	playback = tree.get("parameters/act/playback") as AnimationNodeStateMachinePlayback
	playback.start("none")

func set_tint(c: Color, flash: bool, ec: Color = Color.WHITE) -> void:
	body_mat.albedo_color = Color.WHITE.lerp(c, 0.25) * _char_tint
	accent_mat.albedo_color = Color.WHITE.lerp(c, 0.9) * _char_tint
	for m: StandardMaterial3D in [body_mat, accent_mat]:
		m.emission_enabled = flash
		m.emission = ec
		m.emission_energy_multiplier = 0.8

## Ronda 32: pose de carga del fuerte.
const PREPOSE_MIN := 0.06
var _prepose: bool = false
var _pre_attack: int = -1
var _ab_hit_key: int = -1
## Ronda 32: arco/ballesta con carga completa: brillo dorado pulsante.
var bow_charged: bool = false
var _bow_glow_mat: StandardMaterial3D
var _bow_t: float = 0.0
func set_bow_charged(on: bool) -> void:
	bow_charged = on
	if bow == null:
		return
	if on:
		if _bow_glow_mat == null:
			_bow_glow_mat = StandardMaterial3D.new()
			_bow_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_bow_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_bow_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_bow_glow_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
		bow.material_overlay = _bow_glow_mat
		_bow_t = 0.0
	else:
		bow.material_overlay = null

func _update_bow_glow(delta: float) -> void:
	if bow_charged and _bow_glow_mat:
		_bow_t += delta
		# destello fuerte al cargarse y luego pulso
		var flash := maxf(1.0 - _bow_t * 4.0, 0.0)
		_bow_glow_mat.albedo_color.a = clampf(0.45 + 0.35 * sin(_bow_t * 10.0) + flash, 0.0, 1.0)

func set_glow(on: bool, c: Color) -> void:
	glow_mat.albedo_color = c * 0.8 if on else base_glow

## Ronda 30: brillo permanente del grabado (+5 o más); los destellos de carga vuelven a él.
var base_glow: Color = Color.BLACK
func set_base_glow(c: Color) -> void:
	base_glow = c
	if glow_mat:
		glow_mat.albedo_color = c

## loadout: 0 espada+escudo, 1 arco, -1 cambiando (manos vacías)
var _base_scales: Dictionary = {}
var _swap_k: float = 1.0

## Ronda 15: desenfunda/enfunda suave. La primera mitad encoge el arma saliente; a mitad
## se cambian las mallas y la nueva crece (sin «pop» brusco). p = progreso 0..1.
func swap_visual(from_l: int, p: float) -> void:
	var to_l := 1 - from_l
	set_loadout(from_l if p < 0.5 else to_l)
	_swap_k = smoothstep(0.0, 1.0, absf(p - 0.5) * 2.0)
	_apply_weapon_scale()

func _apply_weapon_scale() -> void:
	for m: MeshInstance3D in [sword, sword_l, shield, bow]:
		if m == null:
			continue
		if not _base_scales.has(m):
			_base_scales[m] = m.scale
		var b: Vector3 = _base_scales[m]
		m.scale = Vector3(b.x, b.y, b.z) * maxf(_swap_k, 0.02)

func set_loadout(l: int, shield_enabled: bool = true) -> void:
	sword.visible = l == 0
	if sword_l:
		sword_l.visible = l == 0 and offhand_weapon_mesh == null
	shield.visible = l == 0 and shield_enabled
	if offhand_weapon_mesh:
		offhand_weapon_mesh.visible = l == 0
	bow.visible = l == 1

func set_mounted(m: bool, sword_scale: float) -> void:
	tree.set("parameters/base/transition_request", "mounted" if m else "foot")
	model.position.y = MOUNT_Y if m else 0.0
	_mounted = m
	sword.scale = Vector3(1.0, sword_scale, 1.0)
	_base_scales[sword] = sword.scale

## Evento puntual: "hit", "block_hit", "shoot".
func event(e: String) -> void:
	oneshot = e
	oneshot_t = {"hit": 0.4, "block_hit": 0.45, "shoot": 0.5, "slam": Fighter.SLAM_TELEGRAPH + 0.25}.get(e, 0.4)
	_last_attack_id = -1
	if e == state:
		playback.start(e, true)

## Duración del lanzamiento en curso (cast_t cuenta hacia atrás desde el «cast» del hechizo).
var _cast_max: float = 0.0
func _cast_total(f: Fighter) -> float:
	if f.cast_t > _cast_max or _cast_max <= 0.0:
		_cast_max = f.cast_t
	return _cast_max

func _clip_len(s: String) -> float:
	return ap.get_animation(states[s]).length

## Estela 3D muestreada desde la empuñadura hasta la punta del arma, en espacio global.
func _create_sword_trail() -> void:
	_sword_trail = MeshInstance3D.new()
	_sword_trail.name = "SwordRibbonTrail"
	_sword_trail.top_level = true
	_sword_trail.global_transform = Transform3D.IDENTITY
	_sword_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sword_trail_material = StandardMaterial3D.new()
	_sword_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sword_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sword_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sword_trail_material.vertex_color_use_as_albedo = true
	_sword_trail_material.albedo_color = Color.WHITE
	_sword_trail_material.render_priority = 1
	_sword_trail_mesh = ArrayMesh.new()
	_sword_trail.mesh = _sword_trail_mesh
	_sword_trail.material_override = _sword_trail_material
	_sword_trail.visible = false
	add_child(_sword_trail)

func flash_sword_trail(color: Color, duration: float = 0.18) -> void:
	_trail_override_color = color
	_trail_override_t = maxf(_trail_override_t, duration)

func _sword_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if sword == null or sword.mesh == null:
		return points
	var box := sword.get_aabb()
	var axis := 0
	if box.size.y >= box.size.x and box.size.y >= box.size.z:
		axis = 1
	elif box.size.z >= box.size.x:
		axis = 2
	var base := box.position + box.size * 0.5
	var tip := base
	base[axis] = box.position[axis]
	tip[axis] = box.end[axis]
	points.append(sword.to_global(base))
	points.append(sword.to_global(tip))
	return points

func _trail_color(f: Fighter) -> Color:
	if _trail_override_t > 0.0:
		return _trail_override_color
	match String(f.melee().infusion):
		"sangrante": return Color(1.0, 0.12, 0.16)
		"gelido": return Color(0.45, 0.82, 1.0)
		"venenoso": return Color(0.45, 1.0, 0.38)
		"ardiente": return Color(1.0, 0.32, 0.08)
		"magica": return Color(0.7, 0.48, 1.0)
		"sagrada": return Color(1.0, 0.84, 0.38)
	return Color(1.0, 0.9, 0.64)

func _update_sword_trail(f: Fighter, delta: float) -> void:
	_trail_override_t = maxf(_trail_override_t - delta, 0.0)
	for i in range(_trail_samples.size() - 1, -1, -1):
		var sample: Dictionary = _trail_samples[i]
		sample["age"] = float(sample["age"]) + delta
		if float(sample["age"]) >= TRAIL_LIFE:
			_trail_samples.remove_at(i)
	var normal_swing := f.atk_state == Fighter.Atk.ACTIVE and sword.visible and f.loadout == Fighter.Loadout.SWORD_SHIELD
	if normal_swing or _trail_override_t > 0.0:
		var points := _sword_points()
		if points.size() == 2:
			_trail_samples.append({"base": points[0], "tip": points[1], "age": 0.0})
			while _trail_samples.size() > TRAIL_MAX_SAMPLES:
				_trail_samples.pop_front()
	_rebuild_sword_trail(_trail_color(f))

func _rebuild_sword_trail(color: Color) -> void:
	if _sword_trail_mesh == null:
		return
	_sword_trail_mesh.clear_surfaces()
	if _trail_samples.size() < 2:
		_sword_trail.visible = false
		return
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in _trail_samples.size():
		var sample: Dictionary = _trail_samples[i]
		var alpha := clampf(1.0 - float(sample["age"]) / TRAIL_LIFE, 0.0, 1.0)
		vertices.append(sample["base"])
		vertices.append(sample["tip"])
		colors.append(Color(color.r, color.g, color.b, alpha))
		colors.append(Color(color.r, color.g, color.b, alpha * 0.82))
		if i > 0:
			var prev := (i - 1) * 2
			var curr := i * 2
			indices.append_array(PackedInt32Array([prev, prev + 1, curr, prev + 1, curr + 1, curr]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_sword_trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_sword_trail_mesh.surface_set_material(0, _sword_trail_material)
	_sword_trail.visible = true

## Ronda 31: pose de cada habilidad de jefe.
func _ability_state(f: Fighter) -> String:
	match f.ab_id:
		"carga_area", "furia_fase", "rayos_trazadores", "lluvia_meteoros": return "boss_charge"
		"rafaga":
			var swing_index := _rafaga_swing_index(f)
			return "light%d" % swing_index if swing_index >= 0 else "cast"
		"onda_rastrera", "aliento_dragon": return "cast"
		"escudo_mana", "postura_contra": return "block"
		"salto_caida": return "jump_air" if f.ab_air else "land"
		"combo_falso": return "heavy" if f.ab_combo_finisher else "light%d" % clampi(f.ab_fired, 0, 2)
		"danza_cisne": return "heavy" if f.ab_fired >= 3 else "light%d" % clampi(f.ab_fired, 0, 2)
		"tajo_retardado", "giro_martillo", "paso_espectral": return "heavy"
		"presa_verdugo": return "dash_strike" if f.ab_fired == 0 else "heavy"
	return "none"

## Cada corte visual empieza antes de que salga su proyectil, para que el contacto de la hoja
## coincida con la emisión del tajo espectral.
func _rafaga_swing_index(f: Fighter) -> int:
	var d: Dictionary = BossAbilities.def("rafaga")
	var windup := float(d.get("windup", 0.6))
	var lead := 0.36
	var tail := 0.5
	if f.ab_t < windup - lead or f.ab_t >= windup + tail:
		return -1
	return posmod(int(f.ab_uses.get("rafaga", 1)) - 1, 3)


func set_paused(paused: bool) -> void:
	if tree:
		tree.active = not paused

func update(f: Fighter, delta: float) -> void:
	oneshot_t = maxf(oneshot_t - delta, 0.0)
	_update_bow_glow(delta)
	_update_sword_trail(f, delta)
	if bow_charged and not f.bow_charged_ready():
		set_bow_charged(false)
	if f.cast_t <= 0.0:
		_cast_max = 0.0
	riding.amount = move_toward(riding.amount, 1.0 if _mounted and f.alive else 0.0, delta * 6.0)
	var s := "none"
	var upper: bool = f.mounted
	if not f.alive:
		s = "death"
		upper = false
	elif f.is_knocked_down() and not f.mounted:
		s = "down"
	elif f.is_getting_up() and not f.mounted:
		s = "getup"
	elif f.ab_id != "":
		s = _ability_state(f)
	elif f.stun > 0.0 and f.atk_state == Fighter.Atk.NONE and not (oneshot == "hit" and oneshot_t > 0.0 and f.stun <= f.last_hitstun + 0.01):
		s = "stance_break" if f.stance_broken_t > 0.0 and not f.mounted else "stun"
	elif f.boss_phase == Fighter.Boss.CHARGE:
		s = "boss_charge" # ronda 25/28: pose de carga clara (grito con la espada, hoja brillando)
	elif f.boss_phase == Fighter.Boss.LUNGE:
		s = "boss_lunge"
	elif f.cast_t > 0.0 and not f.mounted:
		s = "cast"
	elif f.boss_phase == Fighter.Boss.RECOVER:
		s = "land"
	elif f.is_dash_striking():
		s = "dash_strike"
	elif f.atk_state != Fighter.Atk.NONE:
		s = "heavy" if f.atk_heavy or f.atk_jump else "light%d" % (maxi(f.combo - 1, 0) % 3)
	elif f.hold_pose_t > PREPOSE_MIN and not f.mounted and f.loadout == Fighter.Loadout.SWORD_SHIELD:
		s = "heavy" # ronda 32: pose de carga del fuerte desde que se empieza a mantener
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
	elif f.shot_state == Fighter.Shot.RELOAD:
		s = "reload"
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
	elif s == "down":
		tree.set("parameters/act/down/ts/scale", _clip_len(s) / StunRules.DOWN_T)
	elif s == "getup":
		tree.set("parameters/act/getup/ts/scale", _clip_len(s) / StunRules.GETUP_T)
	elif s == "boss_charge" and f.ab_id == "carga_area":
		tree.set("parameters/act/boss_charge/ts/scale", _clip_len(s) / float(BossAbilities.def("carga_area")["windup"]))
	elif s == "boss_charge":
		tree.set("parameters/act/boss_charge/ts/scale", _clip_len(s) / Fighter.BOSS_CHARGE)
	elif s == "boss_lunge":
		# el impacto del clip (CONTACT) coincide con el final de la embestida
		tree.set("parameters/act/boss_lunge/ts/scale", _clip_len(s) * CONTACT / (Fighter.BOSS_DIST / Fighter.BOSS_SPEED))
	elif s == "cast":
		tree.set("parameters/act/cast/ts/scale", _clip_len(s) * CONTACT / maxf(_cast_total(f), 0.1))
	elif s == "stance_break":
		tree.set("parameters/act/stance_break/ts/scale", _clip_len(s) / Fighter.STANCE_BREAK_TIME)
	elif s == "hit" or s == "stun":
		tree.set("parameters/act/%s/ts/scale" % s, maxf(_clip_len(s) / 0.9, 1.0))
	elif s == "slam":
		tree.set("parameters/act/slam/ts/scale", _clip_len("slam") * CONTACT / Fighter.SLAM_TELEGRAPH)
	elif f.ab_id == "combo_falso" and (s == "heavy" or s.begins_with("light")):
		# Ronda 32: cada golpe lento reinicia su clip y lo encaja con su anticipación
		var cd: Dictionary = BossAbilities.def("combo_falso")
		var key := f.ab_fired * 1000 + int(f.ab_uses.get("combo_falso", 0))
		if key != _ab_hit_key:
			_ab_hit_key = key
			playback.start(s, true)
		var wnd := float(cd["final_stage_time"]) if f.ab_combo_finisher and not f.ab_combo_variant else float(cd["variant_windup"]) if f.ab_combo_variant else float(cd["stage_windup"])
		tree.set("parameters/act/%s/ts/scale" % s, _clip_len(s) * CONTACT / maxf(wnd, 0.2))
	elif f.ab_id == "rafaga" and s.begins_with("light"):
		var swing_index := _rafaga_swing_index(f)
		var key := 1000000 + swing_index * 1000 + int(f.ab_uses.get("rafaga", 0))
		if key != _ab_hit_key:
			_ab_hit_key = key
			playback.start(s, true)
		var d: Dictionary = BossAbilities.def("rafaga")
		var lead := float(d.get("rafaga_swing_lead", 0.36))
		tree.set("parameters/act/%s/ts/scale" % s, _clip_len(s) * CONTACT / maxf(lead, 0.1))
	elif s == "heavy" and f.atk_state == Fighter.Atk.NONE:
		# pose de carga: avanza el clip hasta ~60 % de la anticipación mientras se mantiene
		if not _prepose:
			_prepose = true
			playback.start(s, true)
		_last_attack_id = f.attacks_started + 1
		tree.set("parameters/act/heavy/ts/scale", _clip_len(s) * CONTACT * 0.6 / Fighter.HEAVY_HOLD if f.hold_pose_t < Fighter.HEAVY_HOLD else 0.0)
	elif s == "heavy" or s.begins_with("light"):
		var from_pre := _prepose and s == "heavy"
		if _prepose and s != "heavy":
			_last_attack_id = -999 # se soltó antes: sale el ligero desde el principio
		_prepose = false
		if from_pre:
			_pre_attack = f.attacks_started
		if f.attacks_started != _last_attack_id:
			_last_attack_id = f.attacks_started
			playback.start(s, true)
		var L := _clip_len(s)
		var sc := 1.0
		match f.atk_state:
			Fighter.Atk.WINDUP:
				sc = L * CONTACT * (0.4 if _pre_attack == f.attacks_started else 1.0) / maxf(f.atk_dur, 0.05)
			Fighter.Atk.ACTIVE:
				sc = L * (0.62 - CONTACT) / maxf(f.atk_dur, 0.05)
			Fighter.Atk.RECOVERY:
				sc = L * 0.38 / maxf(f.atk_dur, 0.05)
		tree.set("parameters/act/%s/ts/scale" % s, sc)
	elif s == "reload":
		tree.set("parameters/act/reload/ts/scale", _clip_len("reload") / maxf(f.ranged().reload_time, 0.1))
	elif s == "aim":
		# tensar/apuntar dura fire_draw (luego mantiene la pose de apuntar)
		tree.set("parameters/act/aim/ts/scale", 1.0 if f.shot_state != Fighter.Shot.DRAW else maxf(_clip_len("aim") * 0.5 / maxf(f.ranged().fire_draw, 0.05), 0.5))
	elif s == "swap":
		tree.set("parameters/act/swap/ts/scale", _clip_len("swap") / Fighter.SWAP_TIME)
	if f.swap_t > 0.0:
		swap_visual(f.swap_from, f.swap_progress())
	elif _swap_k < 1.0:
		_swap_k = 1.0
		_apply_weapon_scale()
	elif s.begins_with("dodge"):
		# La voltereta (Dodge_* de KayKit) dura exactamente ROLL_TOTAL (24 frames a 30 fps)
		tree.set("parameters/act/%s/ts/scale" % s, _clip_len(s) / (f.roll_total() if f else Fighter.ROLL_TOTAL))
	elif s == "parry":
		tree.set("parameters/act/parry/ts/scale", _clip_len("parry") / (Fighter.PARRY_WINDOW + Fighter.PARRY_RECOVERY))
	if s != state:
		if s != "none":
			if state == "none" or s in ["down", "getup", "boss_charge", "boss_lunge", "stance_break", "cast", "death", "stun", "hit", "block_hit", "shoot", "dash_strike", "jump_up", "land", "slam"] or s.begins_with("dodge"):
				playback.start(s, true)
			else:
				playback.travel(s)
		state = s
	_weight = move_toward(_weight, 0.0 if s == "none" else 1.0, delta * 10.0)
	mix.filter_enabled = upper
	tree.set("parameters/mix/blend_amount", _weight)
	# Ronda 16: salto visual del remate (hacha: salto demoledor)
	var hop_y := 0.0
	if f.cur_hit and f.cur_hit.hop > 0.0 and not _mounted:
		var ph := -1.0
		if f.atk_state == Fighter.Atk.WINDUP:
			ph = clampf((f.atk_t / maxf(f.atk_dur, 0.01) - 0.35) / 0.65, 0.0, 1.0) * 0.8
		elif f.atk_state == Fighter.Atk.ACTIVE:
			ph = 0.8 + 0.2 * f.atk_t / maxf(f.atk_dur, 0.01)
		if ph >= 0.0:
			hop_y = sin(ph * PI) * f.cur_hit.hop
	model.position.y = (MOUNT_Y if _mounted else 0.0) + hop_y + f.ab_hop + (0.0 if _mounted else ground_lift())
	# Locomoción relativa a la mirada
	var st := f.stats()
	var v := MeshUtil.flat(f.planar_vel) / maxf(st.speed, 0.1)
	var bp := Vector2(v.dot(f.facing.cross(Vector3.UP)), v.dot(f.facing))
	tree.set("parameters/loco/blend_position", bp)

# ---------------- Ronda 19: armadura visible ----------------
## Piezas sencillas (cajas/esferas teñidas con el color de la pieza) enganchadas a los huesos
## del rig de KayKit: casco en la cabeza, peto en el pecho, guanteletes en las manos y grebas
## en las piernas. Las estadísticas son lo importante; esto solo da una pista visual.
var _armor_nodes: Array = []

func set_armor(pieces: Dictionary) -> void:
	for n in _armor_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_armor_nodes.clear()
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D if model else null
	if sk == null:
		return
	var parts := {
		"casco": [["head", Vector3(0.0, 0.42, 0.0), Vector3(0.78, 0.36, 0.78)]],
		"pecho": [["chest", Vector3(0.0, 0.18, 0.12), Vector3(0.7, 0.5, 0.18)]],
		"guantes": [["hand.l", Vector3.ZERO, Vector3(0.2, 0.2, 0.2)], ["hand.r", Vector3.ZERO, Vector3(0.2, 0.2, 0.2)]],
		"piernas": [["lowerleg.l", Vector3(0, 0.12, 0.05), Vector3(0.22, 0.3, 0.12)], ["lowerleg.r", Vector3(0, 0.12, 0.05), Vector3(0.22, 0.3, 0.12)]],
	}
	for slot: String in parts:
		var a: ArmorDef = pieces.get(slot)
		if a == null:
			continue
		for d: Array in parts[slot]:
			if sk.find_bone(d[0]) < 0:
				continue
			var att := BoneAttachment3D.new()
			att.name = "armor_%s_%s" % [slot, d[0]]
			att.bone_name = d[0]
			sk.add_child(att)
			var heavy := a.weight_class == "pesado"
			var mi := MeshUtil.box(att, d[2] * (1.12 if heavy else 1.0), d[1], a.tint)
			mi.name = "ArmorMesh"
			_armor_nodes.append(att)


## Ronda 29: garantía visual de suelo. Si un clip (Mixamo retargeteado: estocadas, embestida, salto
## demoledor...) baja los pies por debajo de su altura de reposo, el modelo se eleva lo justo para
## que ningún pie/punta atraviese el suelo. La posición física la garantiza Fighter._clamp_world().
const FOOT_BONES := ["foot.l", "foot.r", "toes.l", "toes.r"]
var _foot_sk: Skeleton3D
var _foot_ids: Array[int] = []
var _foot_rest := INF
var last_lift := 0.0

func _foot_min(rest: bool) -> float:
	var lo := INF
	for i in _foot_ids:
		var o: Vector3 = (_foot_sk.get_bone_global_rest(i) if rest else _foot_sk.get_bone_global_pose(i)).origin
		var pm := model.to_local(_foot_sk.to_global(o))
		lo = minf(lo, (model.transform.basis * pm).y)
	return lo

func foot_lift() -> float:
	if model == null or not model.is_inside_tree():
		return 0.0
	if _foot_sk == null or not is_instance_valid(_foot_sk):
		_foot_sk = model.find_child("Skeleton3D", true, false) as Skeleton3D
		_foot_ids.clear()
		if _foot_sk:
			for b: String in FOOT_BONES:
				var i := _foot_sk.find_bone(b)
				if i >= 0:
					_foot_ids.append(i)
		_foot_rest = _foot_min(true) if not _foot_ids.is_empty() else INF
	if _foot_ids.is_empty() or _foot_rest == INF:
		return 0.0
	last_lift = maxf(0.0, _foot_rest - _foot_min(false))
	return last_lift


# ---------------- Ronda 33: la voltereta no se hunde en el suelo ----------------
## En volteretas/derribos el clip baja la cadera y el tronco por debajo de los pies: se eleva el
## modelo para que ningún hueso del cuerpo (con su grosor) quede bajo el suelo.
const BODY_BONES := {"hips": 0.14, "spine": 0.14, "chest": 0.16, "head": 0.16, "hand.l": 0.05, "hand.r": 0.05,
	"lowerarm.l": 0.06, "lowerarm.r": 0.06, "upperarm.l": 0.08, "upperarm.r": 0.08,
	"upperleg.l": 0.09, "upperleg.r": 0.09, "lowerleg.l": 0.07, "lowerleg.r": 0.07}
const LIFT_STATES := ["dodge_f", "dodge_b", "dodge_l", "dodge_r", "down", "getup", "death"]
var _body_ids: Dictionary = {}
var last_body_lift := 0.0

func body_lift() -> float:
	if _foot_sk == null or not is_instance_valid(_foot_sk):
		foot_lift()
	if _foot_sk == null:
		return 0.0
	if _body_ids.is_empty():
		for b: String in BODY_BONES:
			var i := _foot_sk.find_bone(b)
			if i >= 0:
				_body_ids[i] = float(BODY_BONES[b])
	var need := 0.0
	for i: int in _body_ids:
		var o: Vector3 = _foot_sk.get_bone_global_pose(i).origin
		var y := (model.transform.basis * model.to_local(_foot_sk.to_global(o))).y
		need = maxf(need, float(_body_ids[i]) - y)
	last_body_lift = need
	return need

## Altura extra del modelo: pies en el suelo y, en volteretas/derribos, todo el cuerpo por encima.
func ground_lift() -> float:
	var l := foot_lift()
	if state in LIFT_STATES:
		l = maxf(l, body_lift())
	return l

## Altura mínima (en el espacio del visual) de los huesos del cuerpo, con el modelo colocado (pruebas).
func lowest_body_y() -> float:
	if _foot_sk == null or _body_ids.is_empty():
		body_lift()
	var lo := INF
	for i: int in _body_ids:
		var o: Vector3 = _foot_sk.get_bone_global_pose(i).origin
		lo = minf(lo, _foot_sk.to_global(o).y - float(_body_ids[i]))
	return lo
