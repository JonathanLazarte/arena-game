"""Re-riguea un modelo humanoide al esqueleto humanoide44 (44 huesos) en Blender, sin interfaz.

    blender -b --factory-startup -P tools/rig/rig_humanoid44.py -- \
        --model modelo.glb --map tools/rig/maps/mixamo.json --out modelo_h44.glb [--drop-extra] [--auto-weights]

Qué hace (ver docs/SKELETON_GUIDE.md):
  1. Importa el modelo (.glb/.gltf/.fbx) y toma su armadura (la de más huesos).
  2. Busca, con el mapa (hueso humanoide44 -> hueso del modelo), la posición de cada articulación.
     Los huesos humanoide44 que el modelo no tiene se ubican solos: Spine1 entre Spine y Spine2,
     Collar entre Spine2 y Neck, Shoulder/Elbow/Hip en la articulación de su hijo (son ayudantes
     de giro), face_root/Jaw/Eyebrow/Blink_Lower en la cabeza, Root en el piso bajo la pelvis.
  3. Crea la armadura humanoide44 con esa forma (proporciones del modelo, nombres y jerarquía
     humanoide44) y pasa los pesos: cada grupo de vértices del modelo se renombra a su hueso
     humanoide44; los huesos sin equivalente (giros, dedos extra, falanges) se suman al ancestro
     mapeado más cercano. Con --drop-extra también se funden pelo/ropa/arma; si no, quedan como
     huesos extra colgando del hueso humanoide44 correspondiente (el juego los ignora).
  4. Mallas sin pesos (o con --auto-weights, todas): pesos automáticos de Blender (heat).
  5. Exporta .glb sin animaciones.
El reposo queda en la pose del modelo (A o T): el horneado (tools/rig/bake_humanoid44.gd)
corrige la diferencia contra la pose de referencia del conversor.
"""
import bpy, sys, json, re, argparse, os
from mathutils import Vector

BONES = ["Root", "Pelvis", "Spine", "Spine1", "Spine2", "Collar", "Neck", "Head", "face_root", "Jaw", "Eyebrow", "Blink_Lower"]
PARENT = {"Root": None, "Pelvis": "Root", "Spine": "Pelvis", "Spine1": "Spine", "Spine2": "Spine1", "Collar": "Spine2",
          "Neck": "Collar", "Head": "Neck", "face_root": "Head", "Jaw": "face_root", "Eyebrow": "face_root", "Blink_Lower": "face_root"}
for s in "LR":
    arm = ["Clavicle", "Shoulder", "UpperArm", "Elbow", "Forearm", "Hand"]
    for i, b in enumerate(arm):
        BONES.append(f"{s}_{b}")
        PARENT[f"{s}_{b}"] = "Collar" if i == 0 else f"{s}_{arm[i - 1]}"
    for f in range(5):
        BONES.append(f"{s}_Finger{f}")
        PARENT[f"{s}_Finger{f}"] = f"{s}_Hand"
for s in "LR":
    leg = ["Hip", "Thigh", "Calf", "Foot", "Toe0"]
    for i, b in enumerate(leg):
        BONES.append(f"{s}_{b}")
        PARENT[f"{s}_{b}"] = "Pelvis" if i == 0 else f"{s}_{leg[i - 1]}"
assert len(BONES) == 44
# hueso -> hijo «natural» para orientar la cola
TAIL = {"Pelvis": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Collar", "Collar": "Neck", "Neck": "Head"}
for s in "LR":
    TAIL.update({f"{s}_Clavicle": f"{s}_UpperArm", f"{s}_Shoulder": f"{s}_Forearm", f"{s}_UpperArm": f"{s}_Forearm",
                 f"{s}_Elbow": f"{s}_Hand", f"{s}_Forearm": f"{s}_Hand", f"{s}_Hip": f"{s}_Calf", f"{s}_Thigh": f"{s}_Calf",
                 f"{s}_Calf": f"{s}_Foot", f"{s}_Foot": f"{s}_Toe0"})
NUM = re.compile(r"_\d+$")


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--map", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--drop-extra", action="store_true")
    p.add_argument("--auto-weights", action="store_true")
    return p.parse_args(a)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    else:
        sys.exit("formato no soportado: " + ext)


def resolve(arm, m, strip):
    by = {}
    for b in arm.data.bones:
        for k in (b.name, NUM.sub("", b.name), b.name.removeprefix(strip), NUM.sub("", b.name.removeprefix(strip))):
            by.setdefault(k, b.name)
    out = {}
    for h, want in m.items():
        for k in (want, want.removeprefix(strip)):
            if k in by:
                out[h] = by[k]
                break
    return out


def main():
    a = args()
    load(os.path.abspath(a.model))
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not arms:
        sys.exit("el modelo no tiene armadura: usá --auto-weights con un rig base (ver SKELETON_GUIDE)")
    src = max(arms, key=lambda o: len(o.data.bones))
    md = json.load(open(a.map))
    hmap = resolve(src, md["map"], md.get("strip_prefix", ""))
    need = ["Pelvis", "Head", "L_UpperArm", "L_Forearm", "L_Hand", "R_UpperArm", "R_Forearm", "R_Hand",
            "L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot"]
    miss = [b for b in need if b not in hmap]
    if miss:
        sys.exit("faltan huesos obligatorios en el mapa: %s" % miss)
    W = src.matrix_world
    head = {h: W @ src.data.bones[n].head_local for h, n in hmap.items()}
    tailv = {h: W @ src.data.bones[n].tail_local for h, n in hmap.items()}
    P = lambda b: head[b]
    # Huesos que faltan
    if "Spine" not in head:
        head["Spine"] = P("Pelvis").lerp(P("Head"), 0.15)
    if "Spine2" not in head:
        head["Spine2"] = P("Pelvis").lerp(P("Head"), 0.55)
    if "Neck" not in head:
        head["Neck"] = P("Pelvis").lerp(P("Head"), 0.85)
    if "Spine1" not in head:
        head["Spine1"] = P("Spine").lerp(P("Spine2"), 0.5)
    if "Collar" not in head:
        head["Collar"] = P("Spine2").lerp(P("Neck"), 0.5)
    head.setdefault("Root", Vector((P("Pelvis").x, P("Pelvis").y, min(P("L_Foot").z, P("R_Foot").z) - 0.05)))
    for f in ("face_root", "Eyebrow", "Blink_Lower", "Jaw"):
        head.setdefault(f, P("Head").copy())
    for s in "LR":
        head.setdefault(f"{s}_Clavicle", P("Collar").lerp(P(f"{s}_UpperArm"), 0.15))
        head.setdefault(f"{s}_Shoulder", P(f"{s}_UpperArm").copy())
        head.setdefault(f"{s}_Elbow", P(f"{s}_Forearm").copy())
        head.setdefault(f"{s}_Hip", P(f"{s}_Thigh").copy())
        if f"{s}_Toe0" not in head:
            head[f"{s}_Toe0"] = P(f"{s}_Foot") + (tailv[f"{s}_Foot"] - P(f"{s}_Foot"))
        hand_dir = (P(f"{s}_Hand") - P(f"{s}_Forearm")).normalized()
        for fi in range(5):
            head.setdefault(f"{s}_Finger{fi}", P(f"{s}_Hand") + hand_dir * 0.06)
    height = P("Head").z - head["Root"].z
    # Armadura nueva
    bpy.ops.object.select_all(action="DESELECT")
    ad = bpy.data.armatures.new("humanoid44")
    ao = bpy.data.objects.new("humanoid44", ad)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for b in BONES:
        e = ad.edit_bones.new(b)
        e.head = head[b]
        t = TAIL.get(b)
        if t and (head[t] - head[b]).length > 1e-4:
            e.tail = head[t]
        elif b in tailv and (tailv[b] - head[b]).length > 1e-4:
            e.tail = tailv[b]
        else:
            par = PARENT[b]
            d = (head[b] - head[par]).normalized() if par and (head[b] - head[par]).length > 1e-4 else Vector((0, 0, 1))
            e.tail = head[b] + d * height * 0.03
        eb[b] = e
    for b in BONES:
        if PARENT[b]:
            eb[b].parent = eb[PARENT[b]]
    # Ancestro mapeado de cada hueso del modelo
    inv = {n: h for h, n in hmap.items()}
    def h44_of(bone):
        c = bone
        while c is not None:
            if c.name in inv:
                return inv[c.name]
            c = c.parent
        return "Pelvis"
    target = {}
    extra = []
    for b in src.data.bones:
        if b.name in inv:
            target[b.name] = inv[b.name]
            continue
        anc = h44_of(b.parent) if b.parent else "Root"
        twist_like = re.search(r"(?i)twist|finger|thumb|index|middle|ring|little|pinky|toe|ball|wrist", b.name)
        if a.drop_extra or twist_like or b.parent is None:
            target[b.name] = anc
        else:
            extra.append(b)
            target[b.name] = "x_" + b.name
    for b in extra:  # huesos secundarios (pelo, ropa, arma propia): se conservan
        e = ad.edit_bones.new("x_" + b.name)
        e.head, e.tail = W @ b.head_local, W @ b.tail_local
        if (e.tail - e.head).length < 1e-5:
            e.tail = e.head + Vector((0, 0, height * 0.01))
    for b in extra:
        p = b.parent
        ad.edit_bones["x_" + b.name].parent = ad.edit_bones[target[p.name]] if p.name in target else eb["Root"]
    bpy.ops.object.mode_set(mode="OBJECT")
    # Pesos
    report = {"renamed": 0, "merged": 0, "auto": []}
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        mod = next((m for m in o.modifiers if m.type == "ARMATURE"), None)
        has_w = mod is not None and len(o.vertex_groups) > 0
        if has_w and not a.auto_weights:
            groups = {}
            for vg in list(o.vertex_groups):
                tgt = target.get(vg.name)
                if tgt is None:
                    continue
                groups.setdefault(tgt, []).append(vg)
            for tgt, vgs in groups.items():
                dst = o.vertex_groups.get(tgt) or o.vertex_groups.new(name=tgt)
                for vg in vgs:
                    if vg == dst:
                        continue
                    for v in o.data.vertices:
                        for g in v.groups:
                            if g.group == vg.index and g.weight > 0:
                                dst.add([v.index], g.weight, "ADD")
                    report["merged" if len(vgs) > 1 else "renamed"] += 1
                for vg in vgs:
                    if vg != dst:
                        o.vertex_groups.remove(vg)
            mod.object = ao
            wm = o.matrix_world.copy()
            o.parent = ao
            o.matrix_world = wm
        else:
            for m in [m for m in o.modifiers if m.type == "ARMATURE"]:
                o.modifiers.remove(m)
            o.vertex_groups.clear()
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            ao.select_set(True)
            bpy.context.view_layer.objects.active = ao
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
            report["auto"].append(o.name)
    bpy.data.objects.remove(src, do_unlink=True)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and not o.children]:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(a.out), export_format="GLB", export_animations=False,
                              export_skins=True, export_yup=True)
    print("RIG44 OK huesos=%d mapeados=%d extra=%d grupos renombrados=%d fundidos=%d auto=%s -> %s" % (
        len(ad.bones), len(hmap), len(extra), report["renamed"], report["merged"], report["auto"], a.out))
    print("RIG44 sin mapear (ubicados solos): %s" % [b for b in BONES if b not in hmap])


main()
