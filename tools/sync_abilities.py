"""
Script para sincronizar y registrar automáticamente habilidades desde catálogos JSON
hacia el juego (ExtraCatalog y BossAbilities).

Uso:
    python tools/sync_abilities.py
"""

import json
import os
import re

CATALOGS_DIR = "data/abilities"
EXTRA_CATALOG_GD = "scripts/data/extra_catalog.gd"
BOSS_ABILITIES_GD = "scripts/data/boss_abilities.gd"

def main():
    print("=== Sincronizador de Habilidades de Catálogo ===")
    
    # 1. Escanear todos los catálogos JSON en data/abilities
    json_files = []
    for f in os.listdir(CATALOGS_DIR):
        if f.endswith(".json") and f != "catalog.json" and f != "catalog.example.json":
            json_files.append(f)
    json_files.sort()
    
    print(f"Catálogos encontrados: {json_files}")
    
    # 2. Actualizar PATHS en ExtraCatalog
    if os.path.exists(EXTRA_CATALOG_GD):
        with open(EXTRA_CATALOG_GD, "r", encoding="utf-8") as f:
            code = f.read()
        
        paths_lines = [f'\t"res://data/abilities/{jf}",' for jf in json_files]
        new_paths_block = "const PATHS := [\n" + "\n".join(paths_lines) + "\n]"
        
        code = re.sub(r"const PATHS := \[[^\]]*\]", new_paths_block, code, flags=re.DOTALL)
        
        with open(EXTRA_CATALOG_GD, "w", encoding="utf-8", newline="") as f:
            f.write(code)
        print(f"[OK] {EXTRA_CATALOG_GD} actualizado con {len(json_files)} catálogos.")
        
    # 3. Extraer habilidades de todos los catálogos y registrar nombres cortos/colores en BossAbilities
    all_abilities = {}
    for jf in json_files:
        path = os.path.join(CATALOGS_DIR, jf)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for ab in data.get("abilities", []):
                aid = ab.get("id")
                name = ab.get("name", aid)
                color = "#999999"
                # Intentar sacar color de telegraph del primer paso si existe
                steps = ab.get("steps", [])
                if steps and isinstance(steps[0], dict):
                    tele = steps[0].get("telegraph")
                    if isinstance(tele, dict) and "color" in tele:
                        color = tele["color"]
                if aid:
                    all_abilities[aid] = {"name": name, "color": color}
        except Exception as e:
            print(f"Error leyendo {jf}: {e}")

    print(f"Habilidades detectadas en catálogos extra: {list(all_abilities.keys())}")
    
    if os.path.exists(BOSS_ABILITIES_GD):
        with open(BOSS_ABILITIES_GD, "r", encoding="utf-8") as f:
            b_code = f.read()
            
        for aid, info in all_abilities.items():
            short = info["name"].split()[0]
            # Si no está en SHORT, agregarla
            if f'"{aid}":' not in b_code:
                # Insertar en SHORT antes del cierre }
                match = re.search(r'(const SHORT := \{[^}]*)(})', b_code)
                if match:
                    prefix, suffix = match.group(1), match.group(2)
                    b_code = b_code[:match.start()] + prefix + f', "{aid}": "{short}"' + suffix + b_code[match.end():]
                    
        with open(BOSS_ABILITIES_GD, "w", encoding="utf-8", newline="") as f:
            f.write(b_code)
        print(f"[OK] {BOSS_ABILITIES_GD} actualizado.")

if __name__ == "__main__":
    main()
