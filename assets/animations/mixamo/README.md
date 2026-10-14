# Animaciones Mixamo (Ronda 27)

**Origen:** animaciones de **Mixamo** (Adobe) incluidas en el repositorio [BrunoGottlieb/Souls-Combat](https://github.com/BrunoGottlieb/Souls-Combat).
- Ese repositorio **no tiene licencia**. Solo se tomaron los FBX de animación de Mixamo: no hay modelos, texturas, audio, shaders ni C#.
- Las animaciones de Mixamo se pueden usar en juegos según las condiciones de Mixamo/Adobe.
- Algunos FBX traen la malla del personaje de Mixamo con el que se exportaron (por ejemplo, X Bot). Se importan como **AnimationLibrary**, así que **solo se guardan las animaciones**; la malla no llega al juego.

## Cómo usarlas con un modelo propio
1. Importa tu modelo humanoide (glTF/FBX). En el diálogo de importación, selecciona el `Skeleton3D` → **Retarget → Bone Map** → nuevo `BoneMap` con perfil **SkeletonProfileHumanoid**. Comprueba que los huesos queden en verde y deja «Rename Bones» y «Unique Node» activados (`GeneralSkeleton`).
2. En tu `AnimationPlayer`, añade una de estas bibliotecas (ya reapuntadas a `%GeneralSkeleton`):

| Biblioteca | Contenido |
|---|---|
| `lib_mixamo_all.res` | 99 animaciones, con el grupo como prefijo |
| `lib_paladin.res` | 15 |
| `lib_greatsword.res` | 51 |
| `lib_akai.res` | 18 |
| `lib_magic.res` | 13 |
| `lib_xbot.res` | 2 |

3. Reproduce, por ejemplo, `mx/greatsword_slash`.

Cada FBX también se puede usar por separado (importado como AnimationLibrary con un clip `mixamo_com`).

Los mapas de huesos de origen están en esta carpeta:

| Mapa | Rig de origen |
|---|---|
| `bonemap_paladin.tres` | Rig «paladin» de los packs paladin, Great Sword y Magic (`hips`, `L_arm`, `R_elbow`…) |
| `bonemap_mixamo.tres` | Mixamo sin prefijo (akai) |
| `bonemap_mixamorig.tres` | `mixamorig:` (X Bot) |

Para regenerar las bibliotecas: `godot --headless --path . -s res://tools/build_mixamo_libs.gd`. La prueba es `tests/test_mixamo_anims.gd`.

> Mixamo mueve las caderas: casi todas las animaciones traen desplazamiento (no son «in place»). Para el juego, usa root motion o ignora la traslación de `Hips`. Los bucles (reposos, andar, correr, strafe, guardia, agachado) ya vienen activados.

## Mapeo sugerido a las acciones del juego
| Acción del juego | Animación sugerida (nombre en `lib_mixamo_all`) |
|---|---|
| Reposo con espada y escudo / con arma a dos manos | `paladin_standing_idle` / `greatsword_idle`, `paladin_2hand_idle` |
| Andar / correr / strafe | `greatsword_walk`, `akai_walking` / `greatsword_run`, `akai_fast_run` / `greatsword_strafe` (1–4), `paladin_strafe_left` (espejo para la derecha) |
| Ligeros 1-2-3, espada y escudo | `xbot_sword_and_shield_slash` (0,96 s) → `paladin_sword_and_shield_attack_2` (1,30 s) → `paladin_sword_and_shield_attack` (1,73 s); combo completo: `paladin_one_hand_sword_combo` |
| Pesado, espada y escudo | `paladin_sword_and_shield_slash` (2,43 s) o `paladin_sword_and_shield_attack_1` |
| Ligeros, espada larga / hacha a dos manos | `greatsword_slash` (1,27 s) → `greatsword_slash_5` (1,43 s) → `greatsword_slash_4` (1,80 s); combo: `paladin_two_hand_sword_combo` |
| Pesado con arma a dos manos / pesado cargado | `greatsword_attack`, `paladin_great_sword_slash` / `greatsword_high_spin_attack` (1,87 s) |
| Dagas (rápidas) | `xbot_sword_and_shield_slash` a 1,3× |
| Lanza (estocada) | `greatsword_slash_3` o `greatsword_kick` (patada de apertura) |
| Ataque en carrera | `greatsword_slide_attack` / `paladin_great_sword_slide_attack` |
| Voltereta | `akai_sprinting_forward_roll_inplace` (1,17 s; la versión sin «inplace» avanza) |
| Bloqueo / parada | `greatsword_blocking` (bucle), `greatsword_blocking_2` |
| Contra de guardia | `greatsword_blocking_3` → `greatsword_slash_5` (salida rápida) |
| Recibir golpe | `greatsword_impact` (1–5) |
| Rotura de postura / aturdido | `akai_tripping` (2,1 s), `akai_sweep_fall` (2,5 s) + `akai_standing_up` |
| Derribo, lanzado | `akai_getting_thrown` |
| **Estocada de jefe** (carga de ~2 s + embestida) | Carga: `paladin_sword_scream` (2,37 s) o `greatsword_power_up` (3,5 s, recortada a 2 s). Embestida: `greatsword_slide_attack` o `paladin_soccer_tackle` |
| Salto con impacto | `paladin_mutant_jump_attack` (3,70 s), `greatsword_jump_attack` (2,17 s) |
| Saltar | `greatsword_jump`, `greatsword_jump_2` |
| Hechizos / Arte de arma | `magic_1h_magic_attack_01..03`, `magic_2h_magic_attack_01..05`, área: `magic_2h_magic_area_attack_01/02`; invocar eikon: `magic_2h_cast_spell_01`, `greatsword_casting` |
| Desenvainar / cambiar de arma | `greatsword_draw_1`, `greatsword_draw_2` |
| Girar 180° | `greatsword_180_turn` |
| Curarse (estus) | `akai_drinking` |
| Muerte | `greatsword_two_handed_sword_death`, `akai_sword_and_shield_death`, `akai_dying_backwards` |
| Provocar / intro de jefe | `paladin_sword_scream`, `greatsword_idle_5` (7,6 s) |

Sin uso claro: `paladin_fishing_cast` y `akai_closing`.

## Archivos (99) y su origen en Souls-Combat
| Archivo | Origen (`Assets/…`) |
|---|---|
| `misc/base_idle.fbx` | `0@Idle.fbx` |
| `paladin/paladin_fishing_cast.fbx` | `Boss/Boss Animations/New animations/paladin@Fishing Cast.fbx` |
| `paladin/paladin_one_hand_sword_combo.fbx` | `Boss/Boss Animations/New animations/paladin@One Hand Sword Combo.fbx` |
| `paladin/paladin_sword_scream.fbx` | `Boss/Boss Animations/New animations/paladin@Sword Scream.fbx` |
| `paladin/paladin_two_hand_sword_combo.fbx` | `Boss/Boss Animations/New animations/paladin@Two Hand Sword Combo.fbx` |
| `paladin/paladin_2hand_idle.fbx` | `Boss/Boss Animations/paladin@2hand Idle.fbx` |
| `paladin/paladin_great_sword_slash.fbx` | `Boss/Boss Animations/paladin@Great Sword Slash.fbx` |
| `paladin/paladin_great_sword_slide_attack.fbx` | `Boss/Boss Animations/paladin@Great Sword Slide Attack.fbx` |
| `paladin/paladin_mutant_jump_attack.fbx` | `Boss/Boss Animations/paladin@Mutant Jump Attack.fbx` |
| `paladin/paladin_standing_idle.fbx` | `Boss/Boss Animations/paladin@Standing Idle.fbx` |
| `paladin/paladin_strafe_left.fbx` | `Boss/Boss Animations/paladin@Strafe Left.fbx` |
| `paladin/paladin_sword_and_shield_attack_1.fbx` | `Boss/Boss Animations/paladin@Sword And Shield Attack (1).fbx` |
| `paladin/paladin_sword_and_shield_attack_2.fbx` | `Boss/Boss Animations/paladin@Sword And Shield Attack (2).fbx` |
| `paladin/paladin_sword_and_shield_attack.fbx` | `Boss/Boss Animations/paladin@Sword And Shield Attack.fbx` |
| `paladin/paladin_sword_and_shield_slash.fbx` | `Boss/Boss Animations/paladin@Sword And Shield Slash.fbx` |
| `greatsword/greatsword_draw_1.fbx` | `Boss/Great Sword Pack/draw a great sword 1.fbx` |
| `greatsword/greatsword_draw_2.fbx` | `Boss/Great Sword Pack/draw a great sword 2.fbx` |
| `greatsword/greatsword_180_turn_2.fbx` | `Boss/Great Sword Pack/great sword 180 turn (2).fbx` |
| `greatsword/greatsword_180_turn.fbx` | `Boss/Great Sword Pack/great sword 180 turn.fbx` |
| `greatsword/greatsword_attack.fbx` | `Boss/Great Sword Pack/great sword attack.fbx` |
| `greatsword/greatsword_blocking_2.fbx` | `Boss/Great Sword Pack/great sword blocking (2).fbx` |
| `greatsword/greatsword_blocking_3.fbx` | `Boss/Great Sword Pack/great sword blocking (3).fbx` |
| `greatsword/greatsword_blocking.fbx` | `Boss/Great Sword Pack/great sword blocking.fbx` |
| `greatsword/greatsword_casting.fbx` | `Boss/Great Sword Pack/great sword casting.fbx` |
| `greatsword/greatsword_crouching_2.fbx` | `Boss/Great Sword Pack/great sword crouching (2).fbx` |
| `greatsword/greatsword_crouching_3.fbx` | `Boss/Great Sword Pack/great sword crouching (3).fbx` |
| `greatsword/greatsword_crouching_4.fbx` | `Boss/Great Sword Pack/great sword crouching (4).fbx` |
| `greatsword/greatsword_crouching_5.fbx` | `Boss/Great Sword Pack/great sword crouching (5).fbx` |
| `greatsword/greatsword_crouching_6.fbx` | `Boss/Great Sword Pack/great sword crouching (6).fbx` |
| `greatsword/greatsword_crouching.fbx` | `Boss/Great Sword Pack/great sword crouching.fbx` |
| `greatsword/greatsword_high_spin_attack.fbx` | `Boss/Great Sword Pack/great sword high spin attack.fbx` |
| `greatsword/greatsword_idle_2.fbx` | `Boss/Great Sword Pack/great sword idle (2).fbx` |
| `greatsword/greatsword_idle_3.fbx` | `Boss/Great Sword Pack/great sword idle (3).fbx` |
| `greatsword/greatsword_idle_4.fbx` | `Boss/Great Sword Pack/great sword idle (4).fbx` |
| `greatsword/greatsword_idle_5.fbx` | `Boss/Great Sword Pack/great sword idle (5).fbx` |
| `greatsword/greatsword_idle.fbx` | `Boss/Great Sword Pack/great sword idle.fbx` |
| `greatsword/greatsword_impact_2.fbx` | `Boss/Great Sword Pack/great sword impact (2).fbx` |
| `greatsword/greatsword_impact_3.fbx` | `Boss/Great Sword Pack/great sword impact (3).fbx` |
| `greatsword/greatsword_impact_4.fbx` | `Boss/Great Sword Pack/great sword impact (4).fbx` |
| `greatsword/greatsword_impact_5.fbx` | `Boss/Great Sword Pack/great sword impact (5).fbx` |
| `greatsword/greatsword_impact.fbx` | `Boss/Great Sword Pack/great sword impact.fbx` |
| `greatsword/greatsword_jump_2.fbx` | `Boss/Great Sword Pack/great sword jump (2).fbx` |
| `greatsword/greatsword_jump_attack.fbx` | `Boss/Great Sword Pack/great sword jump attack.fbx` |
| `greatsword/greatsword_jump.fbx` | `Boss/Great Sword Pack/great sword jump.fbx` |
| `greatsword/greatsword_kick_2.fbx` | `Boss/Great Sword Pack/great sword kick (2).fbx` |
| `greatsword/greatsword_kick.fbx` | `Boss/Great Sword Pack/great sword kick.fbx` |
| `greatsword/greatsword_power_up.fbx` | `Boss/Great Sword Pack/great sword power up.fbx` |
| `greatsword/greatsword_run_2.fbx` | `Boss/Great Sword Pack/great sword run (2).fbx` |
| `greatsword/greatsword_run.fbx` | `Boss/Great Sword Pack/great sword run.fbx` |
| `greatsword/greatsword_slash_2.fbx` | `Boss/Great Sword Pack/great sword slash (2).fbx` |
| `greatsword/greatsword_slash_3.fbx` | `Boss/Great Sword Pack/great sword slash (3).fbx` |
| `greatsword/greatsword_slash_4.fbx` | `Boss/Great Sword Pack/great sword slash (4).fbx` |
| `greatsword/greatsword_slash_5.fbx` | `Boss/Great Sword Pack/great sword slash (5).fbx` |
| `greatsword/greatsword_slash.fbx` | `Boss/Great Sword Pack/great sword slash.fbx` |
| `greatsword/greatsword_slide_attack.fbx` | `Boss/Great Sword Pack/great sword slide attack.fbx` |
| `greatsword/greatsword_strafe_2.fbx` | `Boss/Great Sword Pack/great sword strafe (2).fbx` |
| `greatsword/greatsword_strafe_3.fbx` | `Boss/Great Sword Pack/great sword strafe (3).fbx` |
| `greatsword/greatsword_strafe_4.fbx` | `Boss/Great Sword Pack/great sword strafe (4).fbx` |
| `greatsword/greatsword_strafe.fbx` | `Boss/Great Sword Pack/great sword strafe.fbx` |
| `greatsword/greatsword_turn_2.fbx` | `Boss/Great Sword Pack/great sword turn (2).fbx` |
| `greatsword/greatsword_turn.fbx` | `Boss/Great Sword Pack/great sword turn.fbx` |
| `greatsword/greatsword_walk_2.fbx` | `Boss/Great Sword Pack/great sword walk (2).fbx` |
| `greatsword/greatsword_walk.fbx` | `Boss/Great Sword Pack/great sword walk.fbx` |
| `greatsword/greatsword_spell_cast.fbx` | `Boss/Great Sword Pack/spell cast.fbx` |
| `greatsword/greatsword_two_handed_sword_death_2.fbx` | `Boss/Great Sword Pack/two handed sword death (2).fbx` |
| `greatsword/greatsword_two_handed_sword_death.fbx` | `Boss/Great Sword Pack/two handed sword death.fbx` |
| `akai/akai_closing.fbx` | `Girl/Animations/akai_e_espiritu@Closing.fbx` |
| `akai/akai_drinking.fbx` | `Girl/Animations/akai_e_espiritu@Drinking.fbx` |
| `akai/akai_dying_backwards.fbx` | `Girl/Animations/akai_e_espiritu@Dying Backwards.fbx` |
| `akai/akai_fast_run.fbx` | `Girl/Animations/akai_e_espiritu@Fast Run.fbx` |
| `akai/akai_getting_thrown.fbx` | `Girl/Animations/akai_e_espiritu@Getting Thrown.fbx` |
| `akai/akai_idle_2.fbx` | `Girl/Animations/akai_e_espiritu@Idle (2).fbx` |
| `akai/akai_idle.fbx` | `Girl/Animations/akai_e_espiritu@Idle.fbx` |
| `akai/akai_running_1.fbx` | `Girl/Animations/akai_e_espiritu@Running (1).fbx` |
| `akai/akai_running_2.fbx` | `Girl/Animations/akai_e_espiritu@Running (2).fbx` |
| `akai/akai_slow_run.fbx` | `Girl/Animations/akai_e_espiritu@Slow Run.fbx` |
| `akai/akai_sprinting_forward_roll_inplace.fbx` | `Girl/Animations/akai_e_espiritu@Sprinting Forward Roll InPlace.fbx` |
| `akai/akai_sprinting_forward_roll.fbx` | `Girl/Animations/akai_e_espiritu@Sprinting Forward Roll.fbx` |
| `akai/akai_standing_up_1.fbx` | `Girl/Animations/akai_e_espiritu@Standing Up (1).fbx` |
| `akai/akai_standing_up.fbx` | `Girl/Animations/akai_e_espiritu@Standing Up.fbx` |
| `akai/akai_sweep_fall.fbx` | `Girl/Animations/akai_e_espiritu@Sweep Fall.fbx` |
| `akai/akai_sword_and_shield_death.fbx` | `Girl/Animations/akai_e_espiritu@Sword And Shield Death.fbx` |
| `akai/akai_tripping.fbx` | `Girl/Animations/akai_e_espiritu@Tripping.fbx` |
| `akai/akai_walking.fbx` | `Girl/Animations/akai_e_espiritu@Walking.fbx` |
| `xbot/xbot_sword_and_shield_slash_1.fbx` | `Magic Far Sword/xbot@Sword And Shield Slash (1).fbx` |
| `xbot/xbot_sword_and_shield_slash.fbx` | `Magic Far Sword/xbot@Sword And Shield Slash.fbx` |
| `magic/magic_1h_magic_attack_01.fbx` | `Magic Spell Pack/Standing 1H Magic Attack 01.fbx` |
| `magic/magic_1h_magic_attack_02.fbx` | `Magic Spell Pack/Standing 1H Magic Attack 02.fbx` |
| `magic/magic_1h_magic_attack_03.fbx` | `Magic Spell Pack/Standing 1H Magic Attack 03.fbx` |
| `magic/magic_2h_cast_spell_01.fbx` | `Magic Spell Pack/Standing 2H Cast Spell 01.fbx` |
| `magic/magic_2h_magic_area_attack_01.fbx` | `Magic Spell Pack/Standing 2H Magic Area Attack 01.fbx` |
| `magic/magic_2h_magic_area_attack_02.fbx` | `Magic Spell Pack/Standing 2H Magic Area Attack 02.fbx` |
| `magic/magic_2h_magic_attack_01.fbx` | `Magic Spell Pack/Standing 2H Magic Attack 01.fbx` |
| `magic/magic_2h_magic_attack_02.fbx` | `Magic Spell Pack/Standing 2H Magic Attack 02.fbx` |
| `magic/magic_2h_magic_attack_03.fbx` | `Magic Spell Pack/Standing 2H Magic Attack 03.fbx` |
| `magic/magic_2h_magic_attack_04.fbx` | `Magic Spell Pack/Standing 2H Magic Attack 04.fbx` |
| `magic/magic_2h_magic_attack_05.fbx` | `Magic Spell Pack/Standing 2H Magic Attack 05.fbx` |
| `magic/magic_1h_cast_spell_01.fbx` | `Magic Spell Pack/standing 1H cast spell 01.fbx` |
| `magic/magic_idle.fbx` | `Magic Spell Pack/standing idle.fbx` |
| `paladin/paladin_soccer_tackle.fbx` | `paladin@Soccer Tackle.fbx` |
| `misc/untitled1_idle.fbx` | `untitled1@Idle.fbx` |
| `misc/untitled1_walking.fbx` | `untitled1@Walking.fbx` |

## No importados
- `Boss Animations/uploads_files_*_NazgulGreatsword.fbx`: modelo de terceros (excluido expresamente).
- `Boss Animations/New animations/paladin@One Hand Sword Combo.fbx`: duplicado exacto (mismo MD5) de `paladin_one_hand_sword_combo`.
- `0@Idle.fbx`: rig que no es de Mixamo (cola, armadura; huesos `leg right thigh`…) y trae malla.
- `untitled1@Idle.fbx` y `untitled1@Walking.fbx`: rig parcial (37 huesos, sin antebrazo izquierdo ni dedos). `Idle` además trae una malla desconocida.
- `@EllenIdle.fbx` (Unity, no Mixamo), `Melee Axe Pack/Alpha@Alpha.fbx` y `Beta@Beta.fbx` (modelos), y el resto de modelos, texturas, audio, shaders y C#.
