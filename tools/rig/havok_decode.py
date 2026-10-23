import xml.etree.ElementTree as ET
import struct
import json
import math
import sys
import os
import numpy as np

# ==========================================
# LISTA DE HUESOS LIMPIA (Solo guardaremos la animación de estos)
# ==========================================
TARGET_BONES = [
    "Root", "Pelvis", "Spine", "Spine1", "Spine2", "Collar", 
    "Neck", "Head", "face_root", "Jaw", "Eyebrow", "Blink_Lower",
    "L_Clavicle", "L_Shoulder", "L_UpperArm", "L_Elbow", "L_Forearm", "L_Hand", "L_Finger0", "L_Finger1", "L_Finger2", "L_Finger3", "L_Finger4",
    "R_Clavicle", "R_Shoulder", "R_UpperArm", "R_Elbow", "R_Forearm", "R_Hand", "R_Finger0", "R_Finger1", "R_Finger2", "R_Finger3", "R_Finger4",
    "L_Hip", "L_Thigh", "L_Calf", "L_Foot", "L_Toe0",
    "R_Hip", "R_Thigh", "R_Calf", "R_Foot", "R_Toe0"
]

def align(offset: int, alignment: int) -> int:
    return (offset + (alignment - 1)) & ~(alignment - 1)

def parse_havok_float(real_elem) -> float:
    hex_str = real_elem.attrib.get('hex', '')
    if hex_str.startswith('#'):
        val_int = int(hex_str[1:], 16)
        return struct.unpack('<d', struct.pack('<Q', val_int))[0]
    dec_str = real_elem.attrib.get('dec', '0').replace(',', '.')
    return float(dec_str)

def unpack_quat_40bit(b: bytes):
    val = int.from_bytes(b, byteorder='little', signed=False)
    c0 = (val >> 0) & 0xFFF
    c1 = (val >> 12) & 0xFFF
    c2 = (val >> 24) & 0xFFF
    missing_idx = (val >> 36) & 0x3
    sign_bit = (val >> 38) & 0x1

    fractal = 0.000345436
    half_range = 2047.0

    q0 = (c0 - half_range) * fractal
    q1 = (c1 - half_range) * fractal
    q2 = (c2 - half_range) * fractal

    sq_sum = q0*q0 + q1*q1 + q2*q2
    q_missing = math.sqrt(max(0.0, 1.0 - sq_sum))
    if sign_bit:
        q_missing = -q_missing

    quat = [0.0, 0.0, 0.0, 0.0]
    coords = [q0, q1, q2]
    ci = 0
    for i in range(4):
        if i == missing_idx:
            quat[i] = q_missing
        else:
            quat[i] = coords[ci]
            ci += 1

    norm = math.sqrt(sum(c*c for c in quat))
    if norm > 1e-8:
        quat = [c / norm for c in quat]
    else:
        quat = [0.0, 0.0, 0.0, 1.0]
    return quat

def find_knot_span(n: int, p: int, u: float, U: list) -> int:
    if u >= U[n + 1]:
        return n
    if u <= U[p]:
        return p
    low = p
    high = n + 1
    mid = (low + high) // 2
    while u < U[mid] or u >= U[mid + 1]:
        if u < U[mid]:
            high = mid
        else:
            low = mid
        mid = (low + high) // 2
    return mid

def basis_functions(span: int, u: float, p: int, U: list) -> np.ndarray:
    N = np.zeros(p + 1, dtype=np.float64)
    left = np.zeros(p + 1, dtype=np.float64)
    right = np.zeros(p + 1, dtype=np.float64)
    N[0] = 1.0
    for j in range(1, p + 1):
        left[j] = u - U[span + 1 - j]
        right[j] = U[span + j] - u
        saved = 0.0
        for r in range(j):
            denom = right[r + 1] + left[j - r]
            temp = N[r] / denom if abs(denom) > 1e-12 else 0.0
            N[r] = saved + right[r + 1] * temp
            saved = left[j - r] * temp
        N[j] = saved
    return N

def eval_bspline(num_items: int, degree: int, knots: list, control_points: np.ndarray, num_frames: int) -> np.ndarray:
    out = np.zeros((num_frames, control_points.shape[1]), dtype=np.float64)
    for f in range(num_frames):
        u = float(f)
        span = find_knot_span(num_items, degree, u, knots)
        N = basis_functions(span, u, degree, knots)
        val = np.zeros(control_points.shape[1], dtype=np.float64)
        for j in range(degree + 1):
            val += N[j] * control_points[span - degree + j]
        out[f] = val
    return out

def parse_skeleton(skel_path: str):
    tree = ET.parse(skel_path)
    root = tree.getroot()
    skel_obj = None
    for obj in root.findall(".//object"):
        rec = obj.find("./record")
        if rec is not None and rec.find("./field[@name='parentIndices']") is not None:
            skel_obj = rec
            break

    if skel_obj is None:
        raise ValueError("No se encontró hkaSkeleton en el XML.")

    skel_name = skel_obj.find("./field[@name='name']/string").attrib['value']
    
    parent_indices = [
        int(e.attrib['value'])
        for e in skel_obj.find("./field[@name='parentIndices']/array").findall("./integer")
    ]

    bones = []
    for rec in skel_obj.find("./field[@name='bones']/array").findall("./record"):
        b_name = rec.find("./field[@name='name']/string").attrib['value']
        bones.append(b_name)

    ref_pose = []
    for rec in skel_obj.find("./field[@name='referencePose']/array").findall("./record"):
        t_elems = rec.find("./field[@name='translation']/array").findall("./real")
        r_elems = rec.find("./field[@name='rotation']/array").findall("./real")
        s_elems = rec.find("./field[@name='scale']/array").findall("./real")
        t = [parse_havok_float(x) for x in t_elems[:3]]
        r = [parse_havok_float(x) for x in r_elems[:4]]
        s = [parse_havok_float(x) for x in s_elems[:3]]
        ref_pose.append({"translation": t, "rotation": r, "scale": s})

    return {
        "name": skel_name,
        "bones": bones,
        "parentIndices": parent_indices,
        "referencePose": ref_pose
    }

def read_vector_track(data_bytes: bytes, offset: int, mask_byte: int, quant_bits: int, num_frames: int, default_val: float):
    static_flags = [bool(mask_byte & (1 << i)) for i in range(3)]
    spline_flags = [bool(mask_byte & (1 << (i + 4))) for i in range(3)]

    track_out = np.full((num_frames, 3), default_val, dtype=np.float64)

    if any(spline_flags):
        offset = align(offset, 2)
        num_items = struct.unpack_from('<H', data_bytes, offset)[0]
        degree = data_bytes[offset + 2]
        offset += 3
        num_knots = num_items + degree + 2
        knots = list(data_bytes[offset : offset + num_knots])
        offset += num_knots
        offset = align(offset, 4)

        extremes = {}
        for axis in range(3):
            if spline_flags[axis]:
                min_v, max_v = struct.unpack_from('<ff', data_bytes, offset)
                extremes[axis] = (min_v, max_v)
                offset += 8
            elif static_flags[axis]:
                val = struct.unpack_from('<f', data_bytes, offset)[0]
                track_out[:, axis] = val
                offset += 4

        dyn_axes = [a for a in range(3) if spline_flags[a]]
        cps = np.zeros((num_items + 1, len(dyn_axes)), dtype=np.float64)

        for cp_idx in range(num_items + 1):
            for d_idx, axis in enumerate(dyn_axes):
                if quant_bits == 1:
                    q_val = struct.unpack_from('<H', data_bytes, offset)[0]
                    offset += 2
                    norm_v = q_val / 65535.0
                else:
                    q_val = data_bytes[offset]
                    offset += 1
                    norm_v = q_val / 255.0
                min_v, max_v = extremes[axis]
                cps[cp_idx, d_idx] = min_v + norm_v * (max_v - min_v)

        eval_dyn = eval_bspline(num_items, degree, knots, cps, num_frames)
        for d_idx, axis in enumerate(dyn_axes):
            track_out[:, axis] = eval_dyn[:, d_idx]

    elif any(static_flags):
        offset = align(offset, 4)
        for axis in range(3):
            if static_flags[axis]:
                val = struct.unpack_from('<f', data_bytes, offset)[0]
                track_out[:, axis] = val
                offset += 4

    return track_out.tolist(), offset

def read_rotation_track(data_bytes: bytes, offset: int, rot_mask: int, num_frames: int):
    is_spline = bool(rot_mask & 0xF0)
    is_static = bool(rot_mask & 0x0F) and not is_spline

    if is_spline:
        offset = align(offset, 2)
        num_items = struct.unpack_from('<H', data_bytes, offset)[0]
        degree = data_bytes[offset + 2]
        offset += 3
        num_knots = num_items + degree + 2
        knots = list(data_bytes[offset : offset + num_knots])
        offset += num_knots

        cps = np.zeros((num_items + 1, 4), dtype=np.float64)
        for cp_idx in range(num_items + 1):
            q = unpack_quat_40bit(data_bytes[offset : offset + 5])
            offset += 5
            if cp_idx > 0 and np.dot(cps[cp_idx - 1], q) < 0.0:
                q = [-c for c in q]
            cps[cp_idx] = q

        eval_q = eval_bspline(num_items, degree, knots, cps, num_frames)
        norms = np.linalg.norm(eval_q, axis=1, keepdims=True)
        norms[norms < 1e-8] = 1.0
        eval_q = eval_q / norms
        return eval_q.tolist(), offset

    elif is_static:
        q = unpack_quat_40bit(data_bytes[offset : offset + 5])
        offset += 5
        return [q for _ in range(num_frames)], offset
    else:
        return [[0.0, 0.0, 0.0, 1.0] for _ in range(num_frames)], offset

def parse_animation(anim_path: str, orig_skeleton: dict):
    tree = ET.parse(anim_path)
    root = tree.getroot()

    obj3 = root.find(".//object[@id='object3']/record")
    obj4 = root.find(".//object[@id='object4']/record")

    duration = parse_havok_float(obj3.find("./field[@name='duration']/real"))
    num_tracks = int(obj3.find("./field[@name='numberOfTransformTracks']/integer").attrib['value'])
    num_frames = int(obj3.find("./field[@name='numFrames']/integer").attrib['value'])
    frame_duration = parse_havok_float(obj3.find("./field[@name='frameDuration']/real"))
    mask_size = int(obj3.find("./field[@name='maskAndQuantizationSize']/integer").attrib['value'])

    data_elems = obj3.find("./field[@name='data']/array").findall("./integer")
    data_bytes = bytes(int(e.attrib['value']) for e in data_elems)

    track_to_bone = [
        int(e.attrib['value'])
        for e in obj4.find("./field[@name='transformTrackToBoneIndices']/array").findall("./integer")
    ]

    offset = mask_size
    tracks_decoded = {}

    for track_idx in range(num_tracks):
        try:
            b0, b1, b2, b3 = data_bytes[track_idx*4 : (track_idx + 1)*4]
            pos_quant = b0 & 0x03
            scale_quant = (b0 >> 6) & 0x03
            
            bone_idx_old = track_to_bone[track_idx]
            bone_name = orig_skeleton["bones"][bone_idx_old]

            # ES OBLIGATORIO DECODIFICAR SIEMPRE PARA AVANZAR EL PUNTERO CORRECTAMENTE
            offset = align(offset, 4)
            pos_frames, offset = read_vector_track(data_bytes, offset, b1, pos_quant, num_frames, 0.0)

            offset = align(offset, 4)
            rot_frames, offset = read_rotation_track(data_bytes, offset, b2, num_frames)

            offset = align(offset, 4)
            scale_frames, offset = read_vector_track(data_bytes, offset, b3, scale_quant, num_frames, 1.0)

            # PERO SOLO GUARDAMOS LOS DATOS SI EL HUESO ESTA EN LA LISTA LIMPIA
            if True:  # converter_fixed filtra después de componer
                tracks_decoded[str(bone_idx_old)] = {
                    "boneName": bone_name,
                    "translation": pos_frames,
                    "rotation": rot_frames,
                    "scale": scale_frames
                }
        except Exception as e:
            print(f"       [!] Desfase detectado en pista {track_idx}: {e!r}. Extracción parcial.")
            break 

    return {
        "duration": duration,
        "numFrames": num_frames,
        "frameDuration": frame_duration,
        "fps": round(1.0 / frame_duration),
        "skeleton": orig_skeleton, # Conservamos el esqueleto perfecto de 145 huesos
        "tracks": tracks_decoded
    }

if __name__ == "__main__":
    input_base = sys.argv[1] if len(sys.argv) > 1 else "./inputs"
    json_base = sys.argv[2] if len(sys.argv) > 2 else "./jsons"

    if not os.path.exists(input_base):
        print(f"[ERROR] No existe la carpeta '{input_base}'")
        sys.exit(1)

    subfolders = [f.path for f in os.scandir(input_base) if f.is_dir()]

    if not subfolders:
        print(f"[ERROR] No hay carpetas dentro de '{input_base}'.")
        sys.exit(1)

    print(f"Escaneando {len(subfolders)} carpeta(s) en '{input_base}'...")

    for folder_path in subfolders:
        folder_name = os.path.basename(folder_path)
        
        skel_candidates = [f for f in os.listdir(folder_path) if "skel" in f.lower() and f.lower().endswith(".xml")]
        
        if not skel_candidates:
            print(f"[OMITIDO] No se encontro esqueleto (*skel*.xml) en la carpeta: {folder_name}")
            continue

        skel_path = os.path.join(folder_path, skel_candidates[0])
        print(f"\n--- Procesando Personaje: {folder_name} ---")
        
        try:
            skel_data = parse_skeleton(skel_path)
        except Exception as e:
            print(f"[ERROR] No se pudo leer el esqueleto en {folder_name}: {e}")
            continue

        anim_files = [
            f for f in sorted(os.listdir(folder_path))
            if f.lower().endswith(".xml") and f != skel_candidates[0]
            and not f.startswith("_witchy") and not f.startswith("anim-")
        ]

        if not anim_files:
            continue

        out_dir = os.path.join(json_base, folder_name)
        os.makedirs(out_dir, exist_ok=True)

        for idx, anim_filename in enumerate(anim_files, start=1):
            anim_path = os.path.join(folder_path, anim_filename)
            base_name = os.path.splitext(anim_filename)[0]
            out_json_path = os.path.join(out_dir, f"{base_name}.json")

            print(f"  [{idx}/{len(anim_files)}] {anim_filename} -> Filtrando animación...")
            try:
                anim_data = parse_animation(anim_path, skel_data)
                with open(out_json_path, "w", encoding="utf-8") as f:
                    json.dump(anim_data, f)
            except Exception as e:
                print(f"     [ERROR] Falló: {e}")

    print("\n[OK] Lote XML -> JSON finalizado.")