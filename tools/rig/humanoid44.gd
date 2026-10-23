class_name Humanoid44
## Esqueleto «humanoide44» (44 huesos) que exporta el conversor propio a JSON/FBX.
## Lee los JSON de animación (30 fps, pistas translation/rotation/scale, skeleton.bones /
## parentIndices / referencePose; cuaterniones en orden x,y,z,w) y arma poses globales para el
## reapuntado (tools/rig/bake_humanoid44.gd). Ver docs/SKELETON_GUIDE.md.

const BONES: PackedStringArray = ["Root", "Pelvis", "Spine", "Spine1", "Spine2", "Collar", "Neck", "Head",
	"face_root", "Jaw", "Eyebrow", "Blink_Lower",
	"L_Clavicle", "L_Shoulder", "L_UpperArm", "L_Elbow", "L_Forearm", "L_Hand",
	"L_Finger0", "L_Finger1", "L_Finger2", "L_Finger3", "L_Finger4",
	"R_Clavicle", "R_Shoulder", "R_UpperArm", "R_Elbow", "R_Forearm", "R_Hand",
	"R_Finger0", "R_Finger1", "R_Finger2", "R_Finger3", "R_Finger4",
	"L_Hip", "L_Thigh", "L_Calf", "L_Foot", "L_Toe0", "R_Hip", "R_Thigh", "R_Calf", "R_Foot", "R_Toe0"]

## Huesos «ayudantes» (giro a media rotación) que en el JSON figuran como padres pero cuyos datos
## están expresados respecto del abuelo: Collar, Shoulder, Elbow y Hip. Si se respeta el
## parentIndices tal cual, las piernas quedan apuntando para arriba y los brazos estirados el
## doble. Por eso el hijo se cuelga del abuelo (padre «efectivo»). Ver SKELETON_GUIDE §Problemas.
const PARENT_FIX := {"Neck": "Spine2", "L_UpperArm": "L_Clavicle", "R_UpperArm": "R_Clavicle",
	"L_Forearm": "L_UpperArm", "R_Forearm": "R_UpperArm", "L_Thigh": "Pelvis", "R_Thigh": "Pelvis"}

## Segmentos usados para corregir la diferencia de pose de reposo (A/T) al reapuntar.
const CHAIN := {"Pelvis": "Spine2", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
	"L_Clavicle": "L_UpperArm", "L_UpperArm": "L_Forearm", "L_Forearm": "L_Hand",
	"R_Clavicle": "R_UpperArm", "R_UpperArm": "R_Forearm", "R_Forearm": "R_Hand",
	"L_Thigh": "L_Calf", "L_Calf": "L_Foot", "L_Foot": "L_Toe0",
	"R_Thigh": "R_Calf", "R_Calf": "R_Foot", "R_Foot": "R_Toe0"}

var names: PackedStringArray = []
var parents: PackedInt32Array = []
var rest: Array[Transform3D] = [] ## local (padre efectivo)
var fps := 30.0
var num_frames := 0
var duration := 0.0
var _rot := {} ## índice -> Array de [x,y,z,w]
var _pos := {} ## índice -> Array de [x,y,z]

static func _q(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()

static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

## Carga un JSON del conversor. Devuelve null si el formato no coincide.
static func load_json(path: String, fix_parents := true) -> Humanoid44:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("skeleton") or not d.has("tracks"):
		push_error("humanoid44: JSON inválido " + path)
		return null
	var h := Humanoid44.new()
	var sk: Dictionary = d.skeleton
	h.names = PackedStringArray(sk.bones)
	h.fps = float(d.get("fps", 30))
	h.num_frames = int(d.get("numFrames", 0))
	h.duration = float(d.get("duration", 0.0))
	for i in h.names.size():
		var p := int(sk.parentIndices[i])
		var nm := h.names[i]
		if fix_parents and PARENT_FIX.has(nm):
			p = h.names.find(PARENT_FIX[nm])
		h.parents.append(p)
		var rp: Dictionary = sk.referencePose[i]
		h.rest.append(Transform3D(Basis(_q(rp.rotation)), _v(rp.translation)))
	for k: String in d.tracks:
		var tr: Dictionary = d.tracks[k]
		var i := h.names.find(String(tr.get("boneName", "")))
		if i < 0:
			i = int(k)
		if tr.has("rotation"):
			h._rot[i] = tr.rotation
		if tr.has("translation"):
			h._pos[i] = tr.translation
	if h.num_frames <= 0:
		for i: int in h._rot:
			h.num_frames = maxi(h.num_frames, (h._rot[i] as Array).size())
	if h.duration <= 0.0:
		h.duration = maxf(0.0, (h.num_frames - 1) / h.fps)
	return h

func local_at(i: int, frame: int) -> Transform3D:
	var t := rest[i]
	if _rot.has(i):
		var a: Array = _rot[i]
		t.basis = Basis(_q(a[clampi(frame, 0, a.size() - 1)]))
	if _pos.has(i):
		var a: Array = _pos[i]
		t.origin = _v(a[clampi(frame, 0, a.size() - 1)])
	return t

## Poses globales (frame < 0 = pose de referencia). Los padres siempre van antes que los hijos.
func globals(frame: int) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(names.size())
	for i in names.size():
		var l := rest[i] if frame < 0 else local_at(i, frame)
		g[i] = (g[parents[i]] if parents[i] >= 0 else Transform3D.IDENTITY) * l
	return g

func idx(bone: String) -> int:
	return names.find(bone)

## Pistas cuyo hueso no está en BONES (para avisar).
func unknown_bones() -> PackedStringArray:
	var out: PackedStringArray = []
	for n in names:
		if not n in BONES:
			out.append(n)
	return out
