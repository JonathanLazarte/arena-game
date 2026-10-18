# Guía: animar habilidades (clips alineados con la sim)

Esta guía explica cómo ponerle animación a una habilidad del catálogo (las de pasos: Fisura,
Volteretas, Hoja, etc.) sin romper el rollback. La regla de oro del proyecto vale acá también:
**la jugabilidad vive en `net/sim`; la vista solo dibuja**. La animación nunca decide nada:
lee el estado de la sim y pinta la pose que corresponde a ese tick.

Relacionadas: [CHARACTER_GUIDE.md](CHARACTER_GUIDE.md) (personajes, reapuntado y §13 bibliotecas
convertidas) y [abilities_guide.md](abilities_guide.md) (esquema de habilidades y pasos).

## 1. Dónde vive cada cosa

| Qué | Archivo | Campo / función |
|---|---|---|
| Vínculo habilidad → clips | `data/animations/ability_anims.json` | `abilities.<id>.steps.<id_paso>[]` (tramos) |
| Bibliotecas que se cargan | mismo JSON | `libraries` (prefijo → `res://…res`) |
| Lector y muestreo | `scripts/visual/ability_anims.gd` (`AbilityAnims`) | `sample()`, `clip_time()`, `clip_name()` |
| Estados del árbol | `scripts/visual/knight_visual.gd` | `AB_STATES` (`ab0`, `ab1`), `_setup_ability_anims()`, `_ability_sample()` |
| Estado de la sim que se lee | `net/sim/sim_view.gd` | `f.ab_id`, `f.ab_fired` (= índice de paso), `f.ab_tick` (= `AB_T`), `f.ab_seq` (= `AB_STARTS`) |
| Tiempos de cada paso | `data/abilities/*.json` | `windup_ticks`, `active_ticks`, `recovery_ticks`, `events[].tick`, `movement` |
| Exportación | `export_presets.cfg` | `include_filter` incluye `data/animations/*.json` |

Las habilidades que **no** están en `ability_anims.json` siguen con la pose genérica de
`KnightVisual._ability_state()` (por ejemplo `"rafaga"` → `light0`/`light1`).

El JSON es **solo de vista**: no entra en `SimParams` ni en `params_checksum`, así que podés
cambiar clips y claves sin subir el protocolo.

## 2. Bibliotecas disponibles y cómo elegir clip

Bibliotecas en `assets/animations/` (cada una con su `.manifest.json` que lista clips, duración y
bucle). Ya vienen reapuntadas al esqueleto del juego, sin traslación horizontal de cadera.

| Prefijo sugerido | Archivo | Clips |
|---|---|---|
| (sin prefijo) | modelo base | `Idle`, `1H_Melee_Attack_Slice_Diagonal`, `1H_Melee_Attack_Slice_Horizontal`, `1H_Melee_Attack_Chop`, `2H_Melee_Attack_Chop`, `Dodge_Forward/Backward/Left/Right`, `Jump_Start/Idle/Land`, `Use_Item`, … |
| `mx` | `mixamo/lib_kaykit.res` (ya cargada siempre) | `roll_f`, `jump_slam`, `boss_charge`, `boss_lunge`, `cast`, `sns_light0..2`, `sns_heavy`, `gs_*`, `axe_heavy`, `strafe_a/b`, `hit`, `stun`, … |
| `xh`, `xb`, `xn`, … | `explosive_<id>.res` (12: knight, swordsman, spearman, hammer, crossbow, mage, archer, two_handed, sorceress, ninja, karate, brute) | `idle`, `walk`, `walk_slow`, `run`, `jump`, `fall`, `attack1` |
| `dl1` | `doublel_one_hand.res` | `light_a1..3`, `light_b1..3`, `block_idle`, `block_hit`, `walk_*`, `run_*`, `sprint`, `jump`, … |
| `dlc` | `doublel_common.res` | `hit_1`, `hit_2`, `action_4_1`, `action_5_1/2`, `enemy_attack`, `enemy_charge_attack` |
| `dlb` | `doublel_bow.res` | `bow_attack_a/b`, `bow_idle` |

Para usar una, agregala a `libraries` con su prefijo y nombrá los clips como `prefijo/clip`:

```json
"libraries": { "xh": "res://assets/animations/explosive_hammer.res" }
```

Criterios para elegir:

1. **Silueta legible**: el gesto tiene que contar qué pasa (golpe vertical para un impacto en
   área, giro para un tajo circular, salto para un desplazamiento aéreo).
2. **Un fotograma clave claro**: el impacto, el despegue o el aterrizaje. Lo vas a anclar al tick
   del evento de la sim.
3. **En el lugar**: nada de avance propio (ver §6). Las bibliotecas convertidas ya lo cumplen.
4. **Duración razonable**: los clips de `dl1`/`dlc` duran 2–3 s porque incluyen la vuelta a la
   guardia; usá solo el tramo que te sirve (`keys` con inicio y fin, §3).

Para encontrar el fotograma clave, mirá la altura de la cadera (la pista de posición de `hips`)
en un script headless: el punto más bajo de un golpe pesado suele ser el impacto; el más bajo
antes de un salto, el impulso.

## 3. Alinear el clip con windup / activo / recuperación

Cada paso dura `T = windup_ticks + active_ticks + recovery_ticks` ticks (60 por segundo). La
sim cuenta el tick del paso como `t = AB_T - 1` (0 … T-1). Un **tramo** es:

```json
{ "clip": "xh/attack1", "keys": [[0, 0.30], [14, 0.75], [18, 0.85], [58, 1.73]] }
```

`keys` son pares `[tick del paso, tiempo del clip]`. Entre dos claves el tiempo del clip se
interpola lineal; antes de la primera y después de la última queda fijo en el extremo.

Fórmulas (para elegir las claves a mano):

- **Escala de tiempo** de un tramo entre claves `(t0, c0)` y `(t1, c1)`:
  `escala = (c1 - c0) / ((t1 - t0) / 60)`. Escala 1 = velocidad original; 2 = el doble de rápido.
- **Recorte** (trim): la primera clave no tiene por qué ser `c = 0` ni la última el largo del
  clip. `[0, 0.30]` arranca el clip ya en 0,30 s; `[58, 1.73]` lo termina en 1,73 s.
- **Contacto**: si el impacto del clip está en `c_imp` y el golpe de la sim sale en el tick
  `t_imp` (normalmente `windup_ticks`, o el `tick` del evento de impacto), poné una clave
  `[t_imp, c_imp]`. La escala del tramo previo queda `(c_imp - c_ini) / (t_imp / 60)`.
- **Activo**: una clave en `t_imp + active_ticks` evita que el impacto "patine" mientras dura la
  caja de golpe (por ejemplo `[18, 0.85]` en la Fisura).
- **Recuperación**: la última clave en `T` con el final del gesto (vuelta a guardia).
- `"unit": "frac"` permite escribir el tiempo como fracción del largo (0 … 1). Útil cuando el
  clip cambia según el personaje (las espadas de 1 mano usan `CONTACT = 0,42`).

Varios tramos en un mismo paso se suceden: el tramo activo es el último cuya primera clave ya
pasó. Cada cambio de tramo alterna entre los estados `ab0`/`ab1`, así el árbol **funde** 0,08 s
de uno a otro (no hay corte seco). Para fundir más largo, superponé las claves: que el tramo nuevo
empiece un poco antes de que termine el anterior y arranque en una pose parecida.

## 4. Combos de varios pasos y alternancia izquierda/derecha

Cada paso (`steps.<id_paso>`) tiene su lista de tramos. Para alternar lados:

- **Espejo**: `"mirror": true` arma (una sola vez, al cargar) una copia espejada del clip en la
  biblioteca `abm` (intercambia huesos `.l`/`.r` y refleja en X). Así un tajo derecho se vuelve
  izquierdo sin otro clip. Volteretas usa el mismo tajo en `salto_1` y espejado en `salto_2`.
- **Clips distintos por paso**: `light_a1` → `light_a2` → `light_a3`, uno por paso.
- **Alternancia por pulsación** (habilidades que se repiten, como la ráfaga): usá
  `f.ab_seq` (`AB_STARTS`, cuenta los arranques en la sim). Ejemplo: `KnightVisual.rafaga_chain_index(n) = (n - 1) % 2`
  elige `light0`/`light1`. Nunca uses un contador propio de la vista.

## 5. Pasos sostenidos (bucles)

Para un paso que se mantiene (canalizar, cargar, girar en el aire):

```json
{ "clip": "mx/boss_charge", "keys": [[0, 0.0], [20, 0.6]],
  "loop": { "from": 0.6, "to": 1.4, "speed": 1.0 } }
```

Después de la última clave, el tiempo del clip es
`from + ((t - t_última) / 60 · speed) mod (to - from)`. Elegí `from`/`to` en dos poses casi
iguales para que el bucle no salte. El test acepta que un tramo con `loop` no termine en `T`.

## 6. Cuerpo entero o solo torso

`"layer": "full"` (por defecto) reemplaza todo el cuerpo. `"layer": "upper"` mezcla el clip solo
en los huesos de `UPPER` (tronco, brazos, cabeza) y deja las piernas con la locomoción: sirve para
lanzar algo mientras se camina. Regla práctica: si la sim mueve al personaje con un `movement`
propio (salto, embestida, retroceso), usá `full`; si el paso deja caminar, `upper`.

## 7. Movimiento de raíz: lo mueve la sim

- La **sim** mueve al personaje (posición, salto con `FY`, embestidas). El clip va **en el
  lugar**: sin traslación horizontal de cadera. Si el clip avanzara, el modelo se separaría de la
  caja de golpe y en online "rebotaría" con cada corrección.
- La altura de la cadera en el clip (agacharse, impulso) está permitida: es pose, no
  desplazamiento. Si un clip de salto sube mucho la cadera y la sim también eleva al personaje,
  usá solo el tramo del impulso y una pose aérea quieta, como en la Fisura (`xh/jump` de 0 a 0,8 s).
- El conversor (`tools/import_anim_pack.gd`) ya fija X/Z de la cadera; `root_keep_vertical`
  conserva solo la altura.

## 8. Rollback: la pose es una función del estado

- El tiempo del clip sale **solo** de `(f.ab_id, f.ab_fired, f.ab_tick)`, que `SimView` copia de
  la sim cada cuadro. El estado `ab0`/`ab1` tiene `TimeScale = 0` y un `TimeSeek` al tiempo
  calculado: el árbol no acumula tiempo propio.
- Si llega una corrección y la sim vuelve atrás, el próximo cuadro pinta la pose del tick nuevo.
  No hay `playback.start()` disparado por un contador de la vista ni temporizadores locales.
- Prohibido: guardar en la vista "ya empecé este golpe", sumar `delta` para avanzar el clip, o
  leer `Time`/`Engine` para decidir la pose.

## 9. Faltantes y respaldo

- `"fallback": "Dodge_Forward"` en un tramo: si el clip principal no está (biblioteca ausente),
  se usa ese.
- Si no hay clip ni respaldo, `_ability_sample()` devuelve vacío y la habilidad cae a la pose
  genérica de `_ability_state()`. Nunca se rompe la partida.
- Las bibliotecas de `libraries` se cargan solo si existen (`ResourceLoader.exists`).

## 10. Probar sin abrir el editor

`tests/test_ability_anims.gd` comprueba, para cada habilidad del JSON:

- que cada paso de la habilidad tenga tramos, con claves en orden;
- que la última clave caiga en `T` (o que el tramo tenga `loop`);
- que todos los clips (y los espejos `abm/…`) existan en el `AnimationPlayer`;
- que el contacto de la Fisura (0,75 s) caiga en el tick del impacto;
- que la pose dependa solo del tick (ir a 40 y volver a 15 da el mismo tiempo de clip);
- que la sim corra los pasos con la duración que suponen las claves.

```
godot --headless --path . -s res://tests/test_ability_anims.gd
```

Si cambiás tiempos en `data/abilities/*.json`, este test te avisa qué clave quedó desfasada.

## 11. Checklist

- [ ] Habilidad y pasos identificados (`id`, `steps[].id`, `T` de cada paso).
- [ ] Tick clave de la sim anotado (impacto = `windup_ticks` o `events[].tick`; despegue = inicio
      del `movement`).
- [ ] Clip elegido, en el lugar, con su fotograma clave medido.
- [ ] Biblioteca agregada a `libraries` con prefijo corto.
- [ ] Claves: inicio, contacto, fin del activo y `T`. Escala resultante entre 0,5 y 2.
- [ ] Alternancia con `mirror` o clips distintos por paso, si corresponde.
- [ ] `layer` correcto (`full` si la sim desplaza).
- [ ] `fallback` si la biblioteca puede faltar en algún personaje.
- [ ] `test_ability_anims.gd` en verde.
- [ ] Nada de estado de la vista que cambie la pose.

## 12. Ejemplo completo: Golpe de Fisura

Datos de la sim (`data/abilities/golpe_fisura_skill.json`):

| Paso | windup | activo | recup. | T | Clave de la sim |
|---|---|---|---|---|---|
| `saltar` | 30 | 1 | 0 | 31 | `movement` leap de 14 a 31 (despegue en el tick 14, `ev_salto`) |
| `martillazo` | 14 | 4 | 40 | 58 | caja de golpe y `ev_impacto` en el tick 14 |

Clip: `xh/attack1` (martillo a dos manos, golpe vertical de arriba hacia abajo). La cadera baja
de 0,39 a 0,26 m entre 0,53 y 0,80 s: el impacto está en ~0,75 s. Para el salto, `xh/jump`: se
agacha hasta 0,27 s y despega en ~0,40 s.

```json
"golpe_fisura": {
  "file": "res://data/abilities/golpe_fisura_skill.json",
  "steps": {
    "saltar":     [ { "clip": "xh/jump",    "keys": [[0, 0.0], [14, 0.40], [31, 0.80]] } ],
    "martillazo": [ { "clip": "xh/attack1", "keys": [[0, 0.30], [14, 0.75], [18, 0.85], [58, 1.73]] } ]
  }
}
```

Cuentas:

- `saltar`: el impulso del clip (0,40 s) cae en el tick 14, cuando la sim despega. Escala del
  agache: `0,40 / (14/60) = 1,71`. En el aire (ticks 14–31) avanza 0,40 s en 17 ticks
  (`escala 1,41`) hasta una pose aérea, sin llegar al aterrizaje del clip (lo hace el paso
  siguiente).
- `martillazo`: arranca en 0,30 s (brazos ya arriba, viene del salto). Impacto: `[14, 0.75]`, o
  sea `escala = (0,75 - 0,30) / (14/60) = 1,93`. El activo dura 4 ticks (`[18, 0.85]`). La
  recuperación estira de 0,85 a 1,73 s en 40 ticks (`escala 1,32`).
- Cuerpo entero: la sim mueve al personaje en los dos pasos.
- Cada paso alterna `ab0`/`ab1`, así el salto funde con el martillazo.

Volteretas Cortantes (`voltereta_cuchilla`) sigue el mismo patrón: en cada salto, `mx/roll_f`
(voltereta) mientras la sim lo eleva (ticks 0–52) y después el tajo horizontal con contacto en el
tick 66 (`windup_ticks`); en `salida` un `Dodge_Backward` que llena los 37 ticks del retroceso, y
el segundo salto repite con el tajo **espejado** para alternar lado.
