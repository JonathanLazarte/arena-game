# Guía: cómo agregar un personaje jugable vos mismo

Manual paso a paso para sumar un personaje humanoide nuevo a Arena (Godot 4.7.2). Está escrito
con los pasos y los problemas reales que aparecieron al meter modelos no KayKit. Todo lo que se
describe acá es **visual**: la simulación (`net/sim`, `FightSim`, checksums) no se toca nunca.
Las estadísticas del personaje sí entran a la sim (se hornean desde `CharacterDef` vía
`SimParams.bake`), así que cambiar números de un personaje existente cambia el juego; sumar uno
nuevo no altera a los demás.

> **Dónde está el código del reapuntado genérico.** El horneado de animaciones para modelos no
> KayKit (`tools/bake_test_models.gd`, el campo `CharacterDef.retarget_lib` y
> `KnightVisual._prepare_retarget`) vive hoy en la rama `test-models`. Esa rama además trae
> modelos de terceros que **no pueden** llegar a `master`. Si querés usar el reapuntado en
> `master`, traé **solo el código** (ver §11), nunca la carpeta `assets/test_models/`.

## 0. Resumen rápido

1. Conseguí un modelo humanoide con licencia que te permita usarlo (§1).
2. Revisalo: rig, huesos, polígonos, texturas (§2).
3. Copialo a `assets/<carpeta>/<id>/`, achicá texturas a ≤ 1024 px e importá (§3).
4. Mapeá sus huesos a los nombres KayKit y horneá las animaciones (§4–§5).
5. Creá `resources/characters/<id>.tres` y registralo en `scripts/data/catalog.gd` (§7).
6. Probá headless (§9) y armá el APK (§10).

## 1. Conseguir el modelo y la licencia

- **Formatos**: `.glb` (glTF binario) es lo mejor: trae mallas, piel, texturas embebidas y
  animaciones en un solo archivo. `.fbx` también funciona (Godot 4.7 lo importa nativo con
  ufbx, sin Blender), pero las texturas suelen venir aparte y con rutas rotas (§12).
  `.zip`: descomprimilo y buscá el `.glb`/`.fbx` adentro (suele estar en `source/`).
- **Licencia**: para `master`/release solo sirven modelos propios, CC0, CC-BY (con crédito en
  `docs/` o en los créditos del juego) o comprados con licencia que permita redistribuir dentro
  de un juego. Los «rips» de juegos comerciales o personajes con marca **no** van a `master`
  (se pueden probar en privado en una rama aparte, como `test-models`, y nunca se fusionan).
  Los KayKit actuales son CC0.
- **Animaciones**: no hace falta que el modelo traiga animaciones; el juego usa las de KayKit +
  la biblioteca Mixamo ya reapuntada. Si las trae y tienen nombre claro (Idle, Walk, Attack…),
  se pueden usar (§6).

## 2. Revisar el modelo antes de importarlo

Requisitos del rig:

- **Humanoide** con una cadena reconocible: cadera → columna → pecho → cuello → cabeza;
  hombro/brazo/antebrazo/mano a cada lado; muslo/pierna/pie/punta a cada lado.
- **Una sola piel / un solo `Skeleton3D`** (lo normal). Los nombres pueden ser cualquiera
  (`Left arm_0136`, `upperarm_l`, `thigh.L`, `L Thigh`…): se mapean a mano.
- **Pose de reposo**: T o A, da igual (el horneado corrige la diferencia de pose A → T).
- **Orientación**: con la convención glTF (mira a +Z, izquierda del personaje en +X) no hay
  que rotar nada; KayKit usa la misma y `KnightVisual` gira el modelo 180° (`rotation.y = PI`).
- **Escala**: cualquiera; se ajusta sola a la altura KayKit (§5). Ojo con nodos padre con
  escala (exportes de Sketchfab traen `Sketchfab_model` rotado −90° en X y a veces escala 0,01
  o 10): el horneado los tiene en cuenta.

Presupuesto para Android (lo que usamos y anduvo):

| Cosa | Recomendado | Máximo razonable |
|---|---|---|
| Triángulos por personaje | ≤ 20 000 | ~40 000 |
| Mallas (draw calls) | ≤ 5 | ~15 |
| Huesos | ≤ 100 | ~500 (funciona, pero cuesta CPU) |
| Texturas | 1024 × 1024 | 2048 solo si es una sola |

Inspección rápida sin abrir el editor (lista huesos, animaciones, triángulos e imágenes de un
`.glb`): leé el JSON del glTF con Python (`struct` + `json`, sin dependencias) — es lo que
hicimos — o importalo y recorré el `Skeleton3D` con un script `extends SceneTree` que imprima
`get_bone_name(i)`, el padre y `get_bone_global_rest(i).origin`. Imprimir la posición de cada
hueso sirve para confirmar la orientación (manos en ±X, puntas de pie hacia +Z) y la altura.

## 3. Importar en Godot 4.7

1. Creá la carpeta `assets/<carpeta>/<id>/` (en `test-models` usamos `assets/test_models/<id>/`)
   y copiá el modelo. `assets/` está en `.gitignore` pero versionado: para agregar archivos nuevos
   hace falta `git add -f assets/...`.
2. **Texturas embebidas en `.glb`**: Godot las extrae a PNG al lado del modelo
   (`gltf/embedded_image_handling` = «Extract Textures», el valor por defecto) con el nombre
   `<modelo>_<nombre de imagen>.png`. Si las imágenes del glTF **no tienen nombre**, todas se
   extraen con el mismo nombre y se pisan (todas las mallas terminan con la misma textura).
   Arreglo que usamos: reescribir el `.glb` con Python + Pillow antes de importarlo, dándole a
   cada imagen un nombre único (`<id>_tex0`, `<id>_tex1`…) y bajándolas a 1024 px como máximo
   (`Image.resize(..., LANCZOS)`). Eso además achicó los archivos a la mitad.
3. **FBX con texturas sueltas**: el importador busca cada textura **por nombre de archivo en la
   misma carpeta del `.fbx`** (las rutas absolutas de la máquina del autor no sirven). Poné todos
   los PNG/JPG al lado del `.fbx`, no en una subcarpeta `textures/`. Las que no existan dan
   avisos `FBX: Image index N couldn't be loaded` y se ignoran (no rompe nada).
4. Importá: `godot --headless --path . --import`. La primera vez puede tirar
   `Can't find file 'uid://…'` si borraste texturas viejas; se va con otra pasada.
5. **Compresión de texturas**: `project.godot` ya tiene
   `textures/vram_compression/import_etc2_astc=true`, así que en Android las texturas van en
   ETC2/ASTC automáticamente. Para limitar tamaño sin tocar la imagen: en el `.png.import`
   poné `process/size_limit=1024`.
6. **Animaciones del modelo que no vas a usar**: en el `.glb.import` poné
   `animation/import=false`. Así no ocupan lugar en el APK ni aparece un `AnimationPlayer` extra.
7. No hace falta tocar `nodes/root_scale` ni rotaciones en la importación: escala y orientación
   las resuelve el horneado (§5).

## 4. Mapear los huesos a los nombres KayKit

Todo el código visual trabaja con los nombres del rig KayKit (filtro de medio cuerpo, espejado de
combos, armaduras, «pies en el suelo», enganche de armas). En vez de reescribir ese código, el
modelo nuevo **renombra sus huesos** a esos nombres al cargarse. Necesitás decir, para cada hueso
KayKit, cuál es el del modelo:

| KayKit | Qué hueso del modelo |
|---|---|
| `hips` | cadera / pelvis (la raíz de la cadena del cuerpo) |
| `spine` | columna baja/media |
| `chest` | pecho (de donde salen los hombros o clavículas) |
| `head` | cabeza (no el cuello) |
| `upperarm.l` / `.r` | brazo (hombro → codo), **no** la clavícula |
| `lowerarm.l` / `.r` | antebrazo (codo → muñeca) |
| `hand.l` / `.r` | mano / muñeca |
| `upperleg.l` / `.r` | muslo |
| `lowerleg.l` / `.r` | pierna (rodilla → tobillo) |
| `foot.l` / `.r` | pie / tobillo |
| `toes.l` / `.r` | punta del pie |

`.l` es la izquierda **del personaje** (en reposo queda en +X). Los huesos sin mapear (cuello,
clavículas, dedos, pelo, ropa, giros de antebrazo) quedan en reposo relativo a su padre: se
mueven con el cuerpo pero no se animan. `handslot.l/r` (donde se enganchan las armas) **no** hace
falta mapearlo: se crea solo como hijo de la mano.

Si el modelo ya tiene un hueso con un nombre KayKit (por ejemplo un rig estilo Blender con un
hueso `spine` que en realidad es la cadera), no pasa nada: al cargarse, ese hueso pasa a llamarse
`spine_orig` y el mapeado manda.

## 5. Hornear las animaciones (reapuntado)

`tools/bake_test_models.gd` (rama `test-models`) toma los clips de
`res://assets/models/Knight.glb` (salvo los que el juego no usa, lista `SKIP`) y los 26 de la biblioteca Mixamo `res://assets/animations/mixamo/lib_kaykit.res`
y los reapunta al esqueleto de cada modelo:

- Para cada hueso mapeado copia el **cambio de orientación global** respecto del reposo
  (no la rotación local, que depende de los ejes de cada rig).
- Corrige la pose de reposo: alinea la dirección de cada hueso del modelo con la del KayKit
  (brazos en A → T), así los brazos no quedan 45° más abajo.
- La cadera también se traslada, escalada por la altura de cadera de cada modelo.
- Calcula la escala para que la altura (estimada como altura del hueso de la cabeza / 0,87)
  iguale la del cuerpo KayKit (≈ 2,31 unidades antes del `SCALE` 0,85).
- Guarda `assets/<…>/<id>/<id>_anims.res`: una `AnimationLibrary` con los clips KayKit y, en
  metadatos, la biblioteca `mx`, el mapa de huesos, el reposo de `handslot.l/r`, la escala de
  ajuste y las mallas a ocultar o reenganchar.

Para sumar un modelo, agregá una entrada en `configs()`:

```gdscript
{"id": "mi_personaje", "path": "res://assets/personajes/mi_personaje/mi_personaje.glb", "map": _lr(
	{"hips": "Hips", "spine": "Spine", "chest": "Chest", "head": "Head"},
	# izquierda: upperarm, lowerarm, hand, upperleg, lowerleg, foot, toes
	["LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToe"],
	["RightArm", "RightForeArm", "RightHand", "RightUpLeg", "RightLeg", "RightFoot", "RightToe"]),
	# opcionales:
	"hide_bone": "R_weapon",           # oculta las mallas pesadas >50 % a ese hueso (arma propia)
	"rebind": {"Armature": "head"}},   # mallas pesadas 100 % a un hueso raíz -> se pegan a la cabeza
```

y corré:

```bash
godot --headless --path . -s res://tools/bake_test_models.gd            # todos
ONLY=mi_personaje godot --headless --path . -s res://tools/bake_test_models.gd   # uno
```

Tarda medio segundo por modelo y deja ~0,5 MB por personaje (15 fps, `const FPS`). Si falta un hueso del mapa, el
`assert` lo dice con el nombre exacto.

### 5.1 Alternativa: BoneMap + SkeletonProfileHumanoid de Godot

Godot trae su propio reapuntado: en el diálogo de importación, `Skeleton3D` → **Retarget →
Bone Map** → nuevo `BoneMap` con perfil **SkeletonProfileHumanoid**; activá «Rename Bones» y
«Unique Node» (`%GeneralSkeleton`) y, si el modelo está en pose A, `retarget/rest_fixer/fix_silhouette`.
Las bibliotecas Mixamo `lib_mixamo_all.res` (99 clips) y `lib_paladin/greatsword/akai/magic/xbot.res`
ya apuntan a `%GeneralSkeleton` (ver `assets/animations/mixamo/README.md`, los BoneMap
`bonemap_mixamo.tres`, `bonemap_mixamorig.tres`, `bonemap_paladin.tres` y `tools/build_mixamo_libs.gd`).

**Pero** `KnightVisual` espera nombres KayKit (`hips`, `upperarm.l`…) y clips con nombre KayKit
(tabla del §6). Con un esqueleto renombrado a perfil humanoide (`Hips`, `LeftUpperArm`…) el filtro
de medio cuerpo, el espejado de combos, las armaduras y los enganches de armas no encuentran sus
huesos. Por eso, para personajes jugables, el camino que funciona es el del §5. El BoneMap sirve
si querés usar clips de `lib_mixamo_all.res` en otra escena (por ejemplo una vitrina).

> El viejo `_create_fallback_ap` de `KnightVisual` (usado si el modelo no trae
> `AnimationPlayer` y no tiene `retarget_lib`) copia las rotaciones KayKit tal cual con
> `RETARGET_BONE_MAP`; solo se ve bien si el rig tiene exactamente los mismos ejes y reposo que
> KayKit. Con rigs de otro origen el resultado sale retorcido: usá el horneado.

## 6. Ranuras de animación que el juego espera

`scripts/visual/knight_visual.gd` (`STATES`, `LOCO_SPEEDS`, `MX_*`) busca estos clips **por
nombre** en el `AnimationPlayer` del personaje (biblioteca `""`) y en la biblioteca `mx`:

| Estado (`states[...]`) | Clip por defecto (KayKit) | Reemplazo Mixamo (`mx/`) |
|---|---|---|
| `none` (reposo de combate) | `Idle` | `idle` por arma: `sns_idle`, `gs_idle`, `light_idle` |
| `light0` / `light1` / `light2` | `1H_Melee_Attack_Slice_Diagonal` / `…_Slice_Horizontal` / `1H_Melee_Attack_Chop` (o `WeaponDef.anim_light`) | `sns_light0..2`, `gs_light0..2` |
| `heavy` | `2H_Melee_Attack_Chop` (o `WeaponDef.anim_heavy`) | `sns_heavy`, `gs_heavy`, `axe_heavy` |
| `block` | `Blocking` | `gs_block` (espadón/hacha) |
| `block_hit` | `Block_Hit` | — |
| `parry` | `Block_Attack` | — |
| `dodge_f` / `dodge_b` / `dodge_l` / `dodge_r` | `Dodge_Forward` / `Dodge_Backward` / `Dodge_Left` / `Dodge_Right` | `dodge_f` → `roll_f` |
| `hit` / `stun` | `Hit_A` / `Hit_B` | `hit` / `stun` |
| `death` | `Death_A` | `death_1h`, `death_2h` |
| `aim` / `shoot` / `reload` | `2H_Ranged_Aiming` / `2H_Ranged_Shoot` / `2H_Ranged_Reload` (o `WeaponDef.anim_aim/shoot/reload`) | — |
| `swap` / `cast` | `Use_Item` | `cast` → `cast` |
| `dash_strike` | `Dash_Strike` (se compone en Godot con `Dodge_Forward` + un tajo) | — |
| `jump_up` / `jump_air` / `land` | `Jump_Start` / `Jump_Idle` / `Jump_Land` | — |
| `slam` | `2H_Melee_Attack_Chop` | `jump_slam` |
| `boss_charge` / `boss_lunge` / `stance_break` | `Blocking` / `Dash_Strike` / `Hit_B` | `boss_charge` / `boss_lunge` / `stance_break` |
| `down` / `getup` | `Lie_Down` / `Lie_StandUp` | — |

Locomoción (BlendSpace2D de la base): `Idle`, `Walking_A`, `Running_A`, `Walking_Backwards`,
`Running_Strafe_Left`, `Running_Strafe_Right` (strafe caminando: `mx/strafe_a`, `mx/strafe_b`).
Montado: `Sit_Chair_Pose`. En bucle (`AnimUtil.set_loops`): `Idle`, `Walking_A`,
`Walking_Backwards`, `Running_A`, `Running_Strafe_Left`, `Running_Strafe_Right`, `Blocking`,
`2H_Ranged_Aiming`, `Sit_Chair_Pose`, `Jump_Idle`.

La duración de cada acción la decide la sim; la vista estira el clip (`SCALED`) para que entre.
Por eso un clip propio más largo o más corto no rompe nada: solo se ve más rápido o más lento.

**Usar animaciones propias del modelo**: tienen que estar en el **mismo rig ya renombrado**,
así que lo práctico es: importarlas, mirar nombre y duración de cada una
(`get_animation_list()`, `length`), y si tienen nombres claros, en el horneado agregarlas a la
biblioteca con el nombre KayKit de la ranura que reemplazan (por ejemplo, el idle propio como
`Idle`). Si los clips vienen sin nombre (`[Action Stash]`, `Take 001`…) no hay forma confiable de
saber cuál es cuál sin mirarlos uno por uno en el editor; en ese caso conviene desactivar su
importación (`animation/import=false`) y usar las KayKit + Mixamo horneadas.

## 7. Crear la definición y registrarlo (roster / lobby / loadout)

No hay una «escena de personaje» por separado: la vista es siempre `KnightVisual`
(`scripts/visual/knight_visual.gd`), que instancia `model_path` y le arma el `AnimationTree`.
Lo que creás es un recurso `CharacterDef` (`scripts/data/character_def.gd`).

1. `resources/characters/<id>.tres` (copiá `caballero.tres` o `asesino.tres` como base):

   ```ini
   [gd_resource type="Resource" script_class="CharacterDef" load_steps=2 format=3]

   [ext_resource type="Script" path="res://scripts/data/character_def.gd" id="1"]

   [resource]
   script = ExtResource("1")
   id = "mi_personaje"                 ; único, minúsculas; se guarda en la partida y viaja por red
   display_name = "Mi personaje"       ; lo que se ve en el lobby
   role = "Equilibrado"
   description = "Una línea para la ficha."
   passive_id = "guardia_firme"        ; una de: guardia_firme, ojo_de_halcon, furia, luz_sanadora, sombra
   passive_name = "Guardia firme"
   passive_desc = "Bloquear golpes cuesta un 20 % menos de aguante."
   weapons = PackedStringArray("espada_escudo", "espada_larga", "lanza")
   default_weapon = "espada_escudo"    ; tiene que estar en weapons
   model_path = "res://assets/personajes/mi_personaje/mi_personaje.glb"
   texture_path = ""                   ; "" = usa los materiales del modelo (si no, pisa todo con esa textura)
   body_prefix = ""                    ; "" = muestra todas las mallas; "X_" = solo las que empiezan así
   shield_mesh = "Round_Shield"        ; escudo copiado de shield_source (Knight.glb por defecto); "" = sin escudo
   retarget_lib = "res://assets/personajes/mi_personaje/mi_personaje_anims.res"
   ```

   Estadísticas (`vida`, `estamina`, `velocidad`, `poise`, `dano`, `guardia`,
   `roll_iframe_bonus`, `roll_cost_mult`): si no las ponés quedan las del Caballero (1,0). Estas
   **sí** van a la sim (`SimParams.bake`), así que cambiarlas cambia el combate; no toques las de
   los personajes existentes sin querer.
   `combo_finisher` / `combo_finisher_weapon` son opcionales (ver `caballero.tres`).
2. Registralo en `scripts/data/catalog.gd`, al **final** de `CHARACTERS` (los builds exportados no
   pueden listar `res://`, por eso la lista es explícita). Con eso aparece en:
   - el lobby → pestaña **Reclutar** (`scripts/ui/lobby.gd`, `_build_recruit`), y una vez
     reclutado en el carrusel de personajes (`cycle_character`) y en el loadout;
   - la primera partida (`scripts/ui/first_run.gd`, todos los de `Catalog.characters()`);
   - rivales aleatorios de la IA (`GameState.random_loadout`).
3. Precio y nivel para reclutarlo: `Progression.req("character", id)` en
   `scripts/data/progression.gd` (`CHAR_REQ = [nivel de cuenta, oro]`, igual para todos).
4. Árbol de habilidades: `Progression.TREES` por id; si no tiene entrada, queda sin árbol (no
   rompe).
5. Online: el id viaja en el loadout; si el otro jugador tiene una versión sin ese personaje,
   `Catalog.character(id)` cae al Caballero. Para jugar online con un personaje nuevo, los dos
   tienen que tener el mismo build.

## 8. Armas y puntos de enganche

- Las armas se enganchan con `BoneAttachment3D` a `handslot.r` (derecha) y `handslot.l`
  (izquierda: escudo, arma secundaria, arco). `_hand_bone()` acepta también `HandL`, `hand.l`,
  `wrist.l`… si no existe `handslot`.
- Con el horneado, `handslot.l/r` se crean solos con la misma orientación global que en KayKit,
  así las mallas de `WeaponDef.mesh_source` / `mesh_right` / `mesh_left` (copiadas de los `.glb`
  KayKit) quedan bien orientadas sin tocar nada.
- Las armas KayKit son enormes para un cuerpo realista (estética chibi): `TEST_WEAPON_K = 0.65`
  en `KnightVisual` las achica, y `_compensate_attachments` neutraliza la escala propia del
  esqueleto del modelo (si no, en un FBX con escala 10 la espada sale 10 veces más grande).
- Arma propia del modelo: ocultala con `hide_bone` (§5) o con `body_prefix`; si querés usarla en
  lugar de la del juego, poné su nombre de malla en `WeaponDef.mesh_right` (se busca primero en
  el propio modelo con `find_child`).
- Lanza (`procedural = "lanza"`) y arco son mallas generadas por código; se enganchan igual.

## 9. Probar (headless + chequeo rápido)

```bash
godot --headless --path . --import                                   # tras sumar archivos o class_name nuevos
godot --headless --path . -s res://tests/test_defs.gd                 # defs, armas, modelo existe, clips de combo
godot --headless --path . -s res://tests/test_test_models.gd          # (rama test-models) personajes reapuntados
for t in tests/test_*.gd; do godot --headless --path . -s "res://$t"; done   # suite completa
```

`test_net_relay5` y `test_net_matchmaking` necesitan el relay local
(`cd server && npm run build && PORT=47800 REGION=local npm start`); si no está corriendo,
salteálos. Los checksums de la sim (`test_fight_sim`, `test_net_*`) tienen que seguir pasando:
si fallan, tocaste algo que no es visual.

`tests/test_test_models.gd` es un buen modelo para tu propio test: crea un `KnightVisual` con tu
`CharacterDef`, apaga el `AnimationTree`, reproduce los mismos clips en el Caballero y en tu
personaje, y compara la **dirección** de cada segmento (brazo, antebrazo, muslo, pierna,
cadera→cabeza). Con el horneado bien mapeado el peor desvío ronda 10° (la muñeca KayKit está
separada de la mano). Más de 20° casi siempre es un hueso mal mapeado (clavícula en vez de
brazo, cuello en vez de cabeza, izquierda/derecha cruzadas). También comprueba que las pieles
sigan enlazadas, que el arma esté en `handslot.r` y su escala.

Chequeo visual rápido sin abrir el editor (una captura): un script `extends SceneTree` que
ponga una `Camera3D`, una luz y varios `KnightVisual` en fila, haga `ap.play(clip)` +
`ap.seek(t, true)`, espere dos frames y guarde `get_root().get_texture().get_image().save_png(...)`.
Corrélo **sin** `--headless` y con `--rendering-driver opengl3 --resolution 1600x700` (en la caja
hay un display X). Así se detectan en segundos mallas que no siguen al cuerpo o armas gigantes.

## 10. Armar el APK de Android

```bash
export JAVA_HOME=$HOME/opt/jdk-17.0.20.1+1
godot --headless --path . --import
godot --headless --path . --export-debug Android /workspace/arena-game-build/arena-game-<commit>.apk
~/Android/Sdk/build-tools/*/apksigner verify --print-certs /workspace/arena-game-build/arena-game-<commit>.apk
```

- Preset `Android` de `export_presets.cfg` (arm64-v8a + armeabi-v7a). La keystore de debug
  (`~/tools/keys/debug.keystore`), Java y el SDK ya están en la configuración del editor
  (`~/.config/godot/editor_settings-4.7.tres`); no hace falta pasarlos a mano.
- Antes de exportar mirá `const DEBUG_GRANT := false` en `scripts/game_state.gd`.
- El error `No project icon specified` al exportar es inofensivo.
- El export usa `all_resources`: **todo** lo importado entra al APK, uses o no el personaje.
  Cada personaje realista agrega del orden de 3–15 MB (malla + texturas ETC2/ASTC + ~1,3 MB de
  animaciones horneadas). Borrá del proyecto los modelos que no vayas a usar, o excluilos en
  `exclude_filter` del preset.

## 11. Llevar el reapuntado a master (solo código)

Desde `master`, trayendo únicamente los archivos de código de la rama `test-models`:

```bash
git checkout master
git checkout test-models -- tools/bake_test_models.gd scripts/visual/knight_visual.gd scripts/data/character_def.gd
```

y después, a mano: dejá en `configs()` del horneado solo tus personajes (renombrá el archivo si
querés, p. ej. `tools/bake_characters.gd`), sacá el atajo «gratis» de `test_` en
`scripts/data/progression.gd` y el filtro `test_` de `scripts/ui/first_run.gd` (no los traigas),
y escribí un test como `tests/test_test_models.gd` para tus ids. **Nunca** hagas
`git merge test-models` ni copies `assets/test_models/` ni `resources/characters/test_*.tres`.

## 12. Problemas que aparecieron y cómo se resolvieron

| Síntoma | Causa | Arreglo |
|---|---|---|
| Todas las mallas con la misma textura | imágenes del glTF sin nombre: al extraerlas se pisan | renombrar las imágenes del `.glb` antes de importar (§3) |
| FBX sin texturas | rutas absolutas de la máquina del autor | copiar las texturas al lado del `.fbx` |
| Brazos 45° más abajo / torcidos | pose A vs. T, o copiar rotaciones locales | horneado con delta global + corrección de pose (§5) |
| Cara o pelo quietos en el aire mientras el cuerpo rueda | mallas pesadas 100 % a un hueso raíz (no al cuerpo) | `"rebind": {"<hueso raíz>": "head"}` en el horneado |
| Dos espadas | el modelo trae su arma | `"hide_bone"` o `body_prefix` |
| Espada/escudo gigantes | escala global del esqueleto del modelo ≠ KayKit, y armas chibi | `_compensate_attachments` + `TEST_WEAPON_K` |
| Crash en `set_tint` | sin `texture_path` no hay `body_mat` | `set_tint` sale si `body_mat` es `null` (el destello de golpe no tiñe esos modelos) |
| Combos ligeros raros | `_mirrored` espeja asumiendo ejes KayKit | para personajes con `retarget_lib` no se componen combos espejados; se usan `anim_light` |
| `test_defs` falla «modelo existe» | `texture_path` vacío | el test acepta `""` cuando hay `retarget_lib` |
| `Can't find file 'uid://…'` al importar | texturas extraídas borradas | volver a correr `--import` |
| `class_name` nuevo no se encuentra | caché `.godot/` sin actualizar | `godot --headless --path . --import` |
| Archivos de `assets/` no aparecen en `git status` | `assets/` está en `.gitignore` | `git add -f` |
| `Parse Error: Cannot infer the type` en un `for` | GDScript tipado estricto | tipar la variable del bucle (`for side: String in [...]`) |
| Clips del modelo sin nombre (`[Action Stash]`) | export sin acciones nombradas | no usarlos (`animation/import=false`) y hornear KayKit + Mixamo |

## 13. Convertir un pack de clips externo a biblioteca KayKit (`tools/import_anim_pack.gd`)

Para packs de **solo animaciones** (FBX de otro rig) que queremos usar en los personajes KayKit
sin tocar sus modelos. El conversor es headless y se configura por pack con un **perfil JSON**
en `tools/anim_profiles/`.

### Reglas

- Los FBX crudos **nunca** entran al repo (es público). Guardalos fuera (`/workspace/animpacks/<pack>/`)
  o en `assets_raw/` (está en `.gitignore`). El conversor los copia a un proyecto temporal en `/tmp`,
  no al proyecto del juego.
- Solo se commitea: la herramienta, el perfil y la biblioteca horneada (`assets/animations/*.res`
  + su `*.manifest.json`; `assets/` está ignorado, así que van con `git add -f`).

### Uso

```bash
# un personaje del pack
godot --headless --path . -s res://tools/import_anim_pack.gd -- \
    --profile res://tools/anim_profiles/explosivellc_knight.json --src /workspace/animpacks/explosivellc
# todo el pack (12 bibliotecas) o uno solo con --only <id>
godot --headless --path . -s res://tools/import_anim_pack.gd -- \
    --profile res://tools/anim_profiles/explosivellc_all.json --src /workspace/animpacks/explosivellc [--only mage]
godot --headless --path . --import            # registra los .res nuevos
godot --headless --path . -s res://tests/test_anim_pack.gd
```

### Qué hace

1. Copia `<Prefijo>@*.FBX` + el modelo del personaje (`<Prefijo>.FBX`) a `/tmp/anim_pack_<pack>/`,
   importa con `nodes/import_as_skeleton_bones=true` (dos pasadas: .import por defecto y luego forzado).
   Si algún FBX igual trae los huesos como `Node3D`, se arma un esqueleto equivalente desde esa jerarquía.
2. **Reposo fuente = bind pose del modelo del pack** (`model` en el perfil), llevado al espacio de los
   clips con `bind_axes` (el modelo viene Z-arriba/X-adelante; los clips Y-arriba/Z-adelante). Esto
   arregla el giro de antebrazo/mano que daba usar el frame 0 como reposo. Sin modelo, cae al frame 0.
3. Reapunta con delta global (la misma matemática de `tools/retarget_kaykit.gd`, ver §5):
   `Ws = Apose · Grest⁻¹ ; Adest = Ws · C · Grest_KayKit`, con `C` alineando cada segmento de las
   cadenas del perfil (`chain`); los huesos hoja heredan (`inherit`).
4. **Sin root motion**: el hueso `root_bone` se ignora entero; de la pelvis queda solo la altura
   (escalada por la relación de alturas de cadera); x/z fijos en el reposo KayKit.
5. Bucle por nombre (`loop_patterns`: idle/walk/run/strafe), nombres en snake_case
   (`Knight@WalkSlow.FBX` → `walk_slow`), 30 fps.
6. Escribe `assets/animations/<out>.res` (AnimationLibrary, pistas `Rig/Skeleton3D:<hueso>`) y
   `<out>.manifest.json` con nombre, duración, bucle y ranura sugerida (`slots` del perfil).

### Perfil (resumen de campos)

`target` (glb KayKit de referencia), `fps`, `root_bone`, `bind_axes` (columnas: a dónde va x/y/z del
modelo), `bone_map` (hueso KayKit → hueso fuente), `chain`, `inherit`, `loop_patterns`, `slots`,
`characters[]` (`id`, `prefix`, `model`, `out`). `"extends": "<otro perfil>"` hereda y pisa campos.
Para otro pack: copiá el perfil, cambiá `bone_map`/`root_bone`/`bind_axes` y los personajes.

### Usar los clips en el juego (no se recablea nada por defecto)

Las bibliotecas no están conectadas a ningún personaje. Para probarlas, cargá la biblioteca en el
`AnimationPlayer` con un prefijo propio y apuntá el arma a esos nombres:

```gdscript
# en KnightVisual._apply_mixamo (o donde se arme el AnimationPlayer)
if not ap.has_animation_library(&"xk"):
    ap.add_animation_library(&"xk", load("res://assets/animations/explosive_knight.res"))
```

- `WeaponDef.anim_light = ["xk/attack1", ...]` (y `anim_heavy`, `anim_aim`…) en el `.tres` del arma.
- O en `MX_WEAPON` de `knight_visual.gd`: los valores se prefijan con `mx/`, así que para usar otra
  biblioteca agregá la entrada con su ruta completa y quitá el prefijo para valores que ya traen `/`.

Ranuras sugeridas (también en cada manifiesto):

| clip | ranura (§6) |
|---|---|
| `idle` / `idle1` | `none` / `Idle` |
| `walk` | `Walking_A` |
| `walk_slow` | `Walking_Backwards` (lento) o `Walking_A` alterno |
| `run` | `Running_A` |
| `jump` | `jump_up` |
| `fall` | `jump_air` |
| `attack1` | `light0` (un solo golpe por personaje: repetir o mezclar con otros para `light1/2`) |
| `stunned` (solo `sorceress`) | `stun` |

### Licencia

Ese pack se compró/descargó con licencia **por comprador de la Unity Asset Store**: permite usarlo
dentro de un juego, no redistribuir los archivos. Por eso los FBX crudos quedan fuera del repo. Pero
las bibliotecas horneadas **también son derivadas** del pack: **recomendado hacer el repositorio
privado** mientras estén commiteadas (o sacarlas del repo y hornearlas localmente antes de exportar).

### Segundo pack: animaciones RPG (rig maniquí UE5) — perfil `doublel_ue5.json`

```bash
godot --headless --path . -s res://tools/import_anim_pack.gd -- \
    --profile res://tools/anim_profiles/doublel_ue5.json --src /workspace/animpacks/doublel
```

- Se usan los FBX de la carpeta para Unreal (maniquí UE5: `pelvis`, `spine_01..05`, `neck_01`, `head`,
  `clavicle_l`, `upperarm_l`, `lowerarm_l`, `hand_l`, `thigh_l`, `calf_l`, `foot_l`, `ball_l`).
  Reposo = bind del maniquí base del pack (`Unreal_Base.fbx`); mismos ejes que los clips (`bind_axes` identidad).
- En vez de `prefix`, cada grupo trae `clips` = `{nombre_salida: archivo}`: así se eligen las variantes
  InPlace y se ponen nombres de juego. Bibliotecas por estilo: `doublel_one_hand.res` (espada y escudo),
  `doublel_common.res` (golpes recibidos, ataques genéricos) y `doublel_bow.res`.
- Este pack sube/baja el cuerpo con el hueso `root` (la pelvis no tiene traslación propia):
  `"root_keep_vertical": true` conserva solo la altura de la raíz; x/z y rotación de la raíz se descartan.

| estilo | clips | ranura sugerida |
|---|---|---|
| one_hand | `light_a1`, `light_a2`, `light_a3` | `light0`, `light1`, `light2` (combo de 3) |
| one_hand | `light_b1`, `light_b2`, `light_b3` | combo alterno; `light_b1`/`light_b3` sirven de `heavy` |
| one_hand | `block_idle`, `block_hit` | `block`, `block_hit` |
| one_hand | `idle`, `walk_f`, `walk_b`, `walk_strafe_l/r` | `Idle`, `Walking_A`, `Walking_Backwards`, `Walk_Strafe_L/R` |
| one_hand | `run_f`, `run_b`, `run_strafe_l/r`, `sprint` | `Running_A`, —, `Running_Strafe_L/R`, — |
| one_hand | `jump`, `crouch_idle`, `crouch_walk` | `jump_up` (un solo clip), —, — |
| common | `hit_1`, `hit_2` | `hit` / `stun` |
| common | `enemy_attack`, `enemy_charge_attack` | `heavy` / `boss_lunge`, `dash_strike` |
| common | `action_4_1`, `action_5_1`, `action_5_2` | gestos largos (3.5–4.8 s), sin ranura |
| bow | `bow_attack_a`, `bow_attack_b`, `bow_idle` | `shoot`, `shoot` alterno, `aim` |

El pack **no trae** parry, rodar/esquivar, caída/levantarse, muerte, ni estilos a dos manos, lanza o
sin armas: esas ranuras siguen con los clips actuales. Los ataques duran 2–3 s (incluyen la vuelta a
guardia): al usarlos como combo conviene recortar o acelerar (ver `"contact"` en `tools/retarget_kaykit.gd`).
Licencia: igual que el pack anterior (licencia por comprador de la tienda de assets); FBX fuera del repo,
bibliotecas derivadas → repo privado recomendado.
