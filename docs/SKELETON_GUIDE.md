# Guía del esqueleto humanoide44

Cómo poner un modelo de personaje sobre el esqueleto **humanoide44**: 44 huesos (`Root`, `Pelvis`,
`Spine`…`Spine2`, `Neck`, `Head`, `face_root`, brazos con `Collar/Clavicle/Shoulder/UpperArm/Elbow/Forearm/Hand`,
piernas con `Hip/Thigh/Calf/Foot/Toe0`). Lista canónica: `tools/rig/humanoid44.gd` (`Humanoid44.BONES`).

## Hay dos caminos, elegí uno

| | **A. Retarget en Godot** (recomendado) | **B. Re-rig en Blender** |
|---|---|---|
| Qué hace | El modelo conserva su esqueleto y pesos; se hornean los clips humanoide44 a sus huesos | El modelo pasa a tener *literalmente* los 44 huesos (más extras `x_…`) |
| Costo | Un JSON de mapeo + correr un script | Revisar pesos a mano en Blender |
| Armas | Nada cambia (`handslot.r`) | Nada cambia si se mapea la mano |
| Cuándo | Siempre que el modelo ya tenga rig | Modelo sin rig, o querés un esqueleto único para todo |

El camino A es el que usan `caballero` y `asesino`. El B se probó con el caballero
(`test_knight_h44`, fuera del roster).

## 1. Preparar el modelo
- Exportá a `.glb` en T-pose o A-pose (las dos andan: la corrección de pose se hace por segmento).
- Unidades en metros, +Y arriba, mirando a +Z, escala aplicada (Ctrl+A en Blender).
- Un solo `Armature`; mallas con `Armature` modifier. Sin shape keys raras.
- Poné el `.glb` en `assets/test_models/<id>/` (la carpeta `assets/` está en `.gitignore`: subilo con `git add -f`
  solo el modelo y sus texturas, **nunca** packs FBX de terceros).
- Los JSON de animación humanoide44 van en `assets_raw/humanoid44/` (tiene `.gdignore` y no se sube).

## 2. Mapear huesos
Un mapa es `tools/rig/maps/<algo>.json`:
```json
{"_doc": "…", "match": "exact", "strip_prefix": "", "map": {"Pelvis": "Hips_1", "L_Hand": "hand_l"}}
```
Clave = hueso humanoide44, valor = hueso del modelo. El resolvedor acepta nombre exacto, nombre con sufijo
`_123` (glTF numerado) y `strip_prefix` (ej. `mixamorig:`). Ya hay: `kaykit`, `mixamo`, `explosivellc`,
`ue5_manny`, `biped_test_knight`, `mmd_test_mita`, `humanoid44` (identidad, para modelos del camino B).
Los huesos de ayuda (`Collar`, `Shoulder`, `Elbow`, `Hip`) y los de cara pueden quedar sin mapear.

## 3. Camino B: correr el script de Blender
```sh
blender -b --python tools/rig/rig_humanoid44.py -- \
  --model assets/test_models/test_knight/knight.glb \
  --map tools/rig/maps/biped_test_knight.json \
  --out assets/test_models/test_knight_h44/knight_h44.glb [--drop-extra] [--auto-weights]
```
- Renombra los huesos mapeados a humanoide44, crea los que faltan (Spine1, Collar, Elbow…), renombra/fusiona
  grupos de vértices. Los huesos que sobran quedan como `x_<nombre>` (o se borran con `--drop-extra`, fusionando
  sus pesos al padre).
- `--auto-weights`: mallas sin pesos reciben pesos automáticos.

### Revisar pesos
Abrí el `.glb` de salida en Blender → Weight Paint, y probá doblar codos, rodillas y cuello. Buscá vértices que
no se mueven (grupo perdido) o que se estiran hacia el origen (peso a un hueso equivocado). Corregí y exportá
de nuevo (glTF 2.0, `+Y up`, con skin, sin animaciones).

## 4. Hornear los clips
1. Agregá el modelo en `tools/rig/h44_targets.json`:
```json
{"id": "test_x", "model": "res://…/x.glb", "retarget_lib": "res://…/test_x_anims.res",
 "map": "res://tools/rig/maps/x.json", "out": "res://…/test_x_h44.res"}
```
`retarget_lib` es la biblioteca KayKit del modelo (de `tools/bake_test_models.gd`): de ahí se sacan los nombres
finales de los huesos tras el renombrado de `KnightVisual`.
2. Corré (siempre con `</dev/null` y `timeout`, si no un error de script cuelga el depurador):
```sh
godot --headless --path . --import </dev/null
ONLY=test_x timeout 300 godot --headless --path . -s res://tools/rig/bake_humanoid44.gd </dev/null
```
Imprime cuántos huesos quedaron mapeados y cuáles no.

## 5. Registrar en Godot
En el `CharacterDef` (`resources/characters/<id>.tres`):
- `h44_lib = "res://…/test_x_h44.res"` → se carga la biblioteca `h44` en el AnimationPlayer.
- `h44_slots = {"idle": "h44_test_a"}` → reemplaza esa ranura por el clip humanoide44. Vacío = no cambia nada
  en el juego (así quedó, para no romper nada).

## 6. Armas: `bone_overrides`
El arma va en un `BoneAttachment3D` por `data/weapons/weapons.json`. Tras el renombrado los huesos se llaman
`handslot.r` / `hand.r`, así que normalmente no hay que tocar nada. Si un modelo tiene otra mano:
```json
"bone_overrides": {"<id_personaje>": "R_Hand", "mixamo": "mixamorig_RightHand"}
```
Prioridad: id del personaje → perfil del esqueleto → `bone` → manos de respaldo.

## 7. Probar
```sh
timeout 120 godot --headless --path . -s res://tests/test_humanoid44.gd </dev/null
```
Comprueba que la biblioteca carga, que siguen los clips viejos, que todas las pistas apuntan a huesos reales,
que la pose sigue al JSON (< 30°) y que el arma sigue a la mano.

## Problemas comunes
- **Piernas para arriba / brazos rotos**: el JSON lista `Collar/Shoulder/Elbow/Hip` como padres, pero los datos de
  los hijos son relativos al abuelo. `Humanoid44.PARENT_FIX` lo corrige (Neck→Spine2, UpperArm→Clavicle,
  Forearm→UpperArm, Thigh→Pelvis). Si el conversor se arregla, cargá con `fix_parents=false`.
- **Izquierda/derecha cambiadas**: humanoide44 mira a +X con la izquierda en +Z; el horneado espeja (`MIRROR`).
  Mirá un clip asimétrico en el editor y confirmá que levanta la mano correcta.
- **El FBX entra al APK**: nunca lo pongas fuera de `assets_raw/` (con `.gdignore`).
- **Modelo sin rig**: camino B con `--auto-weights`, después revisá pesos a mano.
- **Hueso “no resuelve”**: revisá el nombre en el mapa (sufijo `_N`, prefijo) y mirá la salida del horneado.
- **Script colgado**: faltó `</dev/null`, o una `class_name` nueva sin `--import` previo.
