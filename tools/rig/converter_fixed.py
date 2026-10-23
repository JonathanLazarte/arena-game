"""Havok XML -> humanoide44 JSON (versión corregida).

Copia corregida del conversor original (no lo reemplaza). Diferencias:
  * Antes: el esqueleto reducido a 44 huesos se armaba encadenando la lista TARGET_BONES
    (Collar -> Neck, Shoulder -> UpperArm, Elbow -> Forearm, Hip -> Thigh, Collar -> Clavicle),
    pero las poses locales (referencePose y pistas) se copiaban tal cual del esqueleto original,
    donde esos huesos son HERMANOS (todos cuelgan del abuelo). Resultado: hijos expresados
    respecto del abuelo pero declarados bajo el hueso de ayuda.
  * Ahora: el padre de cada hueso conservado es su ancestro conservado más cercano en la jerarquía
    ORIGINAL, y la transformación local se recompone por cuadro:
        local' = inverse(global(padre conservado)) * global(hueso)
    así los huesos descartados intermedios (p. ej. Master) quedan "horneados" en el hijo.
  * Se decodifican TODAS las pistas (no solo las de la lista) para poder componer; los huesos
    sin pista usan la referencePose.
  * --keep-full: no reduce; guarda el esqueleto original completo y solo filtra pistas.

Uso:
  python3 converter_fixed.py --skel skel.xml --anim anim.xml --out out.json [--keep-full]
  python3 converter_fixed.py ./inputs ./jsons            # modo lote, igual que el original
"""
import json, os, sys, argparse
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("havok_dec", os.path.join(_here, "havok_decode.py"))
dec = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(dec)

TARGET_BONES = dec.TARGET_BONES

# ---------- matemática TRS (cuaterniones xyzw, como Havok) ----------
def q_mul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return np.array([aw*bx + ax*bw + ay*bz - az*by,
                     aw*by - ax*bz + ay*bw + az*bx,
                     aw*bz + ax*by - ay*bx + az*bw,
                     aw*bw - ax*bx - ay*by - az*bz])

def q_mat(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])

def trs(t, q, s):
    m = np.eye(4); m[:3, :3] = q_mat(np.asarray(q, float)) * np.asarray(s, float); m[:3, 3] = t
    return m

def mat_q(r):
    # r = rotación pura 3x3 -> cuaternión xyzw
    tr = r[0,0] + r[1,1] + r[2,2]
    if tr > 0:
        S = np.sqrt(tr + 1.0) * 2; w = 0.25*S
        x = (r[2,1]-r[1,2])/S; y = (r[0,2]-r[2,0])/S; z = (r[1,0]-r[0,1])/S
    elif r[0,0] > r[1,1] and r[0,0] > r[2,2]:
        S = np.sqrt(1.0 + r[0,0] - r[1,1] - r[2,2]) * 2; x = 0.25*S
        w = (r[2,1]-r[1,2])/S; y = (r[0,1]+r[1,0])/S; z = (r[0,2]+r[2,0])/S
    elif r[1,1] > r[2,2]:
        S = np.sqrt(1.0 + r[1,1] - r[0,0] - r[2,2]) * 2; y = 0.25*S
        w = (r[0,2]-r[2,0])/S; x = (r[0,1]+r[1,0])/S; z = (r[1,2]+r[2,1])/S
    else:
        S = np.sqrt(1.0 + r[2,2] - r[0,0] - r[1,1]) * 2; z = 0.25*S
        w = (r[1,0]-r[0,1])/S; x = (r[0,2]+r[2,0])/S; y = (r[1,2]+r[2,1])/S
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)

def decompose(m):
    t = m[:3, 3].copy()
    s = np.linalg.norm(m[:3, :3], axis=0)
    r = m[:3, :3] / np.where(s > 1e-12, s, 1.0)
    if np.linalg.det(r) < 0:  # escala negativa: la cargamos en X
        s[0] = -s[0]; r[:, 0] = -r[:, 0]
    return t, mat_q(r), s

# ---------- conversión ----------
def full_locals(anim, skel):
    """Matrices locales [frame][bone] del esqueleto completo (pista o referencePose)."""
    n = anim["numFrames"]; nb = len(skel["bones"])
    ref = [trs(p["translation"], p["rotation"], p["scale"]) for p in skel["referencePose"]]
    L = [[ref[b] for b in range(nb)] for _ in range(n)]
    for k, tr in anim["tracks"].items():
        b = int(k)
        for f in range(n):
            L[f][b] = trs(tr["translation"][f], tr["rotation"][f], tr["scale"][f])
    return ref, L

def globals_of(locs, parents):
    G = [None] * len(parents)
    def g(i):
        if G[i] is None:
            p = parents[i]
            G[i] = locs[i] if p < 0 else g(p) @ locs[i]
        return G[i]
    for i in range(len(parents)): g(i)
    return G

def reduce_skeleton(skel, keep):
    B, P = skel["bones"], skel["parentIndices"]
    idx = {b: i for i, b in enumerate(B)}
    kept = [b for b in keep if b in idx]
    missing = [b for b in keep if b not in idx]
    new_parent = []
    for b in kept:
        j = P[idx[b]]
        while j >= 0 and B[j] not in kept:
            j = P[j]
        new_parent.append(kept.index(B[j]) if j >= 0 else -1)
    return kept, new_parent, missing

def convert(anim, skel, keep_full=False, keep=TARGET_BONES):
    if keep_full:
        tr = {k: v for k, v in anim["tracks"].items() if v["boneName"] in keep}
        return dict(anim, skeleton=skel, tracks=tr)
    B, P = skel["bones"], skel["parentIndices"]
    idx = {b: i for i, b in enumerate(B)}
    kept, npar, missing = reduce_skeleton(skel, keep)
    if missing:
        print("   [!] huesos de la lista que no están en el esqueleto:", missing)
    ref, L = full_locals(anim, skel)
    Gref = globals_of(ref, P)
    def reduced_local(G, b, k):
        gi = G[idx[b]]
        if npar[k] >= 0:
            return np.linalg.inv(G[idx[kept[npar[k]]]]) @ gi
        # raíz: relativa a la pose de REFERENCIA de sus ancestros descartados (Master). Así el marco
        # queda igual que en los JSON viejos (lo que espera el horneado) y se conserva el
        # desplazamiento/giro animado de Master como movimiento de Root.
        p0 = P[idx[b]]
        return gi if p0 < 0 else np.linalg.inv(Gref[p0]) @ gi
    ref_pose = []
    for k, b in enumerate(kept):
        t, q, s = decompose(reduced_local(Gref, b, k))
        ref_pose.append({"translation": t.tolist(), "rotation": q.tolist(), "scale": s.tolist()})
    tracked = {int(k) for k in anim["tracks"]}
    tracks = {}
    per = {k: {"translation": [], "rotation": [], "scale": []} for k in range(len(kept))}
    for f in range(anim["numFrames"]):
        G = globals_of(L[f], P)
        for k, b in enumerate(kept):
            t, q, s = decompose(reduced_local(G, b, k))
            prev = per[k]["rotation"]
            if prev and np.dot(prev[-1], q) < 0: q = -q  # continuidad del hemisferio
            per[k]["translation"].append(t.tolist()); per[k]["rotation"].append(q.tolist()); per[k]["scale"].append(s.tolist())
    for k, b in enumerate(kept):
        # guardamos pista si el hueso o algún ancestro descartado intermedio está animado
        chain = []; j = idx[b]
        stop = idx[kept[npar[k]]] if npar[k] >= 0 else -1
        while j >= 0 and j != stop: chain.append(j); j = P[j]
        if any(c in tracked for c in chain):
            tracks[str(k)] = dict(boneName=b, **per[k])
    return {"converter": "converter_fixed", "parents": "havok", "duration": anim["duration"], "numFrames": anim["numFrames"], "frameDuration": anim["frameDuration"],
            "fps": anim["fps"], "skeleton": {"name": skel["name"], "bones": kept, "parentIndices": npar,
            "referencePose": ref_pose}, "tracks": tracks}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="?"); ap.add_argument("jsons", nargs="?")
    ap.add_argument("--skel"); ap.add_argument("--anim"); ap.add_argument("--out")
    ap.add_argument("--keep-full", action="store_true")
    a = ap.parse_args()
    if a.skel:
        skel = dec.parse_skeleton(a.skel)
        out = convert(dec.parse_animation(a.anim, skel), skel, a.keep_full)
        json.dump(out, open(a.out, "w")); print("OK ->", a.out, len(out["skeleton"]["bones"]), "huesos,", len(out["tracks"]), "pistas")
        return
    ib, jb = a.inputs or "./inputs", a.jsons or "./jsons"
    for folder in [f.path for f in os.scandir(ib) if f.is_dir()]:
        sk = [f for f in os.listdir(folder) if "skel" in f.lower() and f.lower().endswith(".xml")]
        if not sk: print("[OMITIDO]", folder); continue
        skel = dec.parse_skeleton(os.path.join(folder, sk[0]))
        od = os.path.join(jb, os.path.basename(folder)); os.makedirs(od, exist_ok=True)
        for fn in sorted(os.listdir(folder)):
            if not fn.lower().endswith(".xml") or fn == sk[0] or fn.startswith("_witchy") or fn.startswith("anim-"): continue
            try:
                out = convert(dec.parse_animation(os.path.join(folder, fn), skel), skel, a.keep_full)
                json.dump(out, open(os.path.join(od, os.path.splitext(fn)[0] + ".json"), "w")); print("  OK", fn)
            except Exception as e:
                print("  [ERROR]", fn, e)

if __name__ == "__main__":
    main()
