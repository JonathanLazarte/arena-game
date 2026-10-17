# Guía de habilidades de jefe — esquema de datos para autores (humanos o modelos)

> **Para qué sirve este documento.** Es una especificación autocontenida para escribir habilidades nuevas
> («habilidades de jefe», *boss skills*) del juego en formato JSON. Está pensada para pasársela entera a un
> modelo de IA y que devuelva habilidades **válidas, justas y deterministas** sin tener que leer el código.
>
> **Importante:** el esquema que se describe acá es el **objetivo**. Hoy las habilidades viven en diccionarios
> GDScript (ver §13 «Estado actual vs esquema objetivo»). Migrar el código a este esquema es trabajo futuro.
> Todo número marcado como *(ejemplo)* es solo ilustrativo, aunque usa la escala real del juego.

---

## Índice
1. Reglas del juego que el esquema respeta
2. Unidades, escalas y conversión tick ↔ ms
3. Archivo de catálogo
4. Habilidad (`ability`)
5. Paso (`step`)
6. Cajas de golpe (`hitboxes`)
7. Bloques de construcción: movimiento, fuerzas, estados, formas
8. Ramas: `next`, `cancel_into` y remates a elección (`branch`)
9. Eventos visuales y de sonido (rollback-safe)
10. Tipos de ataque futuros (proyectiles, zonas, rayos, agarres, posturas, carga, bufos, invocaciones…)
11. Reglas cruzadas y validación
12. Ejemplos completos
13. Estado actual vs esquema objetivo
14. Checklist de diseño (justicia y legibilidad online)
15. Errores comunes
16. Cómo pedirle a un modelo una habilidad (plantilla)
17. Cómo validar un catálogo

---

## 1. Reglas del juego que el esquema respeta

- **Simulación determinista a 60 Hz** (`net/sim/fight_sim.gd`). Todo el estado de partida es un arreglo de
  enteros. Dentro de la sim no hay floats, ni reloj, ni `randf`, ni nodos.
- **Decimales solo en el JSON.** Los valores con decimales (vida, metros, grados) se convierten **una sola vez**
  a enteros/punto fijo al cargar, en `SimParams.bake`. Después la sim solo ve enteros.
- **Azar solo del RNG sembrado de la sim** (`FightSim.rng_next`, xorshift guardado en el estado). Nunca otro.
- **Netcode con rollback** (estilo GGPO, ventana de 8 ticks). La sim puede re-simularse: cualquier efecto
  visual o sonoro necesita una **clave estable** para no repetirse ni quedar «fantasma» tras un rollback (§9).
- **Cada campeón equipa hasta 3 habilidades.** Los jefes **no son dueños** de habilidades: un jefe usa un
  *preset* (arquetipo) que lista ids del catálogo. *Máximo 3* se refiere **solo** a habilidades equipadas;
  la cantidad de pasos dentro de una habilidad es libre (§5).
- **Fase II del campeón** (al bajar del 50 % de vida): desbloquea la **3.ª habilidad** del campeón (además
  de furia, 0,85 s de invulnerabilidad y, según el campeón, medidor de eikon lleno).
- **Costo de recurso** obligatorio: aguante (`stamina`), maná (`mana`, = Energía) o vida (`health`). Un costo
  de vida **se rechaza** si `vida − costo ≤ 0`. Si se paga, se recorta para dejar como mínimo **1 de vida**.
- **Recarga:** la sim usa solo la **global de 85 ticks** (`tk(1,4)`, 1,4 s). El `cooldown_ticks` del catálogo
  no se aplica todavía. Más adelante la recarga será `max(global, propia)`. La ráfaga se encadena consigo
  misma y saltea la global. El 84 del esquema objetivo no corre en la sim.
- **Aturdimiento en 3 niveles acumulados** durante una ventana de **3 s (180 ticks)** desde el primer golpe:
  umbrales `acumulado / robustez` = **1,0 tambaleo** (21 ticks, se cancela rodando) · **1,6 aturdido**
  (54 ticks) · **2,4 derribo** (66 ticks en el suelo + 48 levantándose). Un golpe aporta como mucho
  **0,95 × robustez**: ningún golpe aturde solo.
- **Derribo**: inmune al aturdimiento desde el derribo hasta levantarse + 36 ticks, y el daño entra ×0,85
  (`GETUP_DMG_PM`). No es invulnerable.
- **Inmunidad total** (el golpe cuenta como esquiva): i-frames de la Danza, el Paso Espectral, la transición
  a Fase II y el escudo de maná. La carga y la embestida de la Estocada también, igual que hoy, y queda
  **pendiente de balance**. En el resto, «invulnerable» del esquema (inmune al aturdimiento + daño ×0,85)
  no reemplaza esas esquivas.
- **Cada habilidad tiene un aviso (telegraph) propio y único**, con forma/color/sonido distinguibles.
- **Flags de cancelación y parry** por habilidad y por caja de golpe (`interruptible_by`, `parryable`, …).

---

## 2. Unidades, escalas y conversión tick ↔ ms

### 2.1 Unidades del JSON y su conversión en `bake`

| Magnitud | Unidad en JSON | Tipo JSON | Unidad interna (sim) | Conversión |
|---|---|---|---|---|
| Tiempo | **ticks** (1/60 s) | int | ticks | ninguna (el JSON ya va en ticks) |
| Vida, daño, aguante, maná | puntos («de vida») | number, ≤ 3 decimales | milésimas | `round(v × 1000)` |
| Fuerza de aturdimiento | puntos de fuerza | number, ≤ 3 decimales | milésimas | `round(v × 1000)` |
| Distancia | metros | number, ≤ 3 decimales | µm | `round(m × 1 000 000)` |
| Velocidad | m/s | number | µm/tick | `round(m/s × 1e6 / 60)` |
| Ángulo (arco, abanico) | grados | number | coseno ×4096 o rumbo 0..255 | `cos_q(deg)` / `deg × 256 / 360` |
| Giro (tracking) | grados/s | number | mili-rumbos/tick | `round(deg/s / 60 × 256000 / 360)` |
| Porcentaje | % | int 0..100 (o más si se indica) | ‰ | `pct × 10` |

Reglas: **ningún tiempo en segundos** en el JSON; **ningún valor de la sim sale de un float en runtime**. Si un
campo es `int`, un decimal es error de validación.

### 2.2 Escala real del juego (para elegir números razonables)

Valores tomados del código (`resources/`, `scripts/data/`, `SimParams.defaults()`):

| Concepto | Valores reales |
|---|---|
| Vida máxima | 80–130 base por clase (arquero 80, asesino 85, caballero 100, berserker 120, paladín 130) + bonus de Vitalidad (≈ +4/pt hasta 25, luego decrece) |
| Aguante máximo | 100 base (+ atributos). Rodar cuesta 20, salto 12, parry 15 |
| Maná (Energía) | 50 + bonus de Concentración |
| Daño ligero de armas | 8 (dagas) · 12 (base) · 13 (lanza) · 15 (espada larga) · 20 (hacha 2 m) |
| Daño fuerte de armas | 18 (dagas) · 26 (base) · 27 (lanza) · 30 (espada larga) · 40 (hacha 2 m) |
| Daño típico de una habilidad hoy | 0,4×–1,6× del fuerte del arma → ~10–65 de vida **por golpe** |
| Robustez (poise) | 30 (asesino) · 35 (arquero) · 50 (base) · 65 (paladín) · 80 (berserker) + armadura |
| Fuerza de aturdimiento por golpe | base del golpe 8–70 + fuerza por Fuerza (0,6/pt hasta 30, 0,3 hasta 50, 0,1 después) + fuerza del arma (dagas 4 … hacha 14) |
| Voltereta | i-frames del tick 4 al 27 (≈ 400 ms), 4,5 m |
| Ventana de parry | 18 ticks (+0..2 online según el retardo de entrada) |
| Arena | radio 40 m; 6 pilares |
| Piscinas de entidades | proyectiles **12**, peligros de suelo (marcas/ondas) **16**, compartidas por los dos luchadores |

### 2.3 Tabla tick ↔ ms (60 Hz; 1 tick = 16,67 ms)

| ticks | ms | referencia |
|---|---|---|
| 1 | 17 | — |
| 3 | 50 | latencia de un sentido a ~100 ms RTT |
| 6 | 100 | |
| 9 | 150 | arranque de un ligero rápido |
| 12 | 200 | |
| 18 | 300 | **mínimo** de aviso de algo imbloqueable; recuperación mínima castigable |
| 21 | 350 | tambaleo |
| 24 | 400 | i-frames de voltereta (aprox.) |
| 30 | 500 | |
| 36 | 600 | inmunidad tras levantarse |
| 42 | 700 | |
| 48 | 800 | levantarse |
| 54 | 900 | aturdido |
| 60 | 1000 | |
| 66 | 1100 | en el suelo tras derribo |
| 84 | 1400 | **recarga global** |
| 90 | 1500 | |
| 96 | 1600 | carga de la estocada actual |
| 120 | 2000 | |
| 180 | 3000 | ventana de acumulación de aturdimiento |
| 300 | 5000 | |
| 600 | 10000 | |

Fórmulas: `ms = ticks × 1000 / 60` · `ticks = round(ms × 60 / 1000)`.

---

## 3. Archivo de catálogo

Un único JSON (ruta propuesta: `resources/abilities/catalog.json`).

```json
{
  "version": 1,
  "tick_rate": 60,
  "abilities": [],
  "presets": [
    { "id": "verdugo_ceniza", "name": "Verdugo de Ceniza", "abilities": ["presa_verdugo", "onda_rastrera", "furia_fase"] }
  ]
}
```

| Campo | Tipo | Oblig. | Valores / restricciones |
|---|---|---|---|
| `version` | int | sí | ≥ 1. Se sube al cambiar el formato. Entra en `params_checksum` |
| `tick_rate` | int | sí | **siempre 60**. Cualquier otro valor = error |
| `abilities` | array<Ability> | sí | ids únicos (§4) |
| `presets` | array<Preset> | no (default `[]`) | arquetipos de jefe |

**Preset** («arquetipo de jefe»):

| Campo | Tipo | Oblig. | Notas |
|---|---|---|---|
| `id` | string `snake_case` | sí | único entre presets |
| `name` | string | sí | nombre visible, propio |
| `abilities` | array<string> | sí | **1 a 3** ids existentes, sin repetir (no hace falta llegar a 3). El orden importa: el **3.º** (índice 2), si existe, es el que el campeón desbloquea en Fase II |
| `notes` | string | no | texto libre de diseño, ignorado por la sim |

Los jefes **no definen habilidades**: solo referencian ids. Una misma habilidad puede estar en varios presets.

---

## 4. Habilidad (`ability`)

```json
{
  "id": "hachazo_penitente",
  "name": "Hachazo del Penitente",
  "icon": "generic",
  "category": "melee",
  "tags": ["unblockable", "delayed"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 26, "mana": 0, "health": 0 },
  "cooldown_ticks": 480,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["knockdown", "parry"],
  "interrupt_priority": 0,
  "on_interrupt": { "recovery_ticks": 30, "cancel_spawns": true, "cooldown": "full", "refund_pct": 0 },
  "entry_step": "golpe_tardio",
  "steps": [],
  "ai": { "range_min": 1.5, "range_max": 4.0, "weight": 10, "use_when": ["target_in_range"] },
  "hint": { "dodge": "roll_late", "text": "No ruedes al ver el arma arriba: esperá el destello." }
}
```

| Campo | Tipo | Oblig. | Default | Valores / restricciones |
|---|---|---|---|---|
| `id` | string | sí | — | `^[a-z][a-z0-9_]{2,31}$`, único en el catálogo. Nunca se renombra (entra en replays/checksums) |
| `name` | string | sí | — | nombre visible en español, original |
| `icon` | string | sí | — | `generic` (icono procedural de `BossIcon`), `boss:<id>` (icono procedural de una habilidad existente) o una ruta `res://` a una imagen. Si la ruta no existe: aviso `ASSET` y se usa el genérico |
| `category` | enum | sí | — | `melee` · `ranged` · `magic` · `grab` · `buff` · `summon` · `zone` · `counter` · `movement` |
| `tags` | array<string> | no | `[]` | conocidos: `unblockable`, `delayed`, `multi_hit`, `aerial`, `mana_shield`, `tracking`, `aoe`, `projectile`. `mana_shield` habilita la invulnerabilidad total (§5.3) |
| `unlock.phase` | int | no | `1` | `1` (siempre) o `2` (solo en Fase II del dueño) |
| `cost.stamina` / `.mana` / `.health` | number ≥ 0 | sí (al menos uno > 0) | `0` | puntos; se pueden combinar. El de aguante se multiplica por los modificadores de costo del luchador (talismanes) en `bake` |
| `cooldown_ticks` | int ≥ 0 | sí | — | recarga propia; arranca al **terminar** la habilidad (o al interrumpirse si `on_interrupt.cooldown` = `full`) |
| `uses_global_cd` | bool | no | `true` | respeta y dispara la recarga global de 84 ticks |
| `usable_while` | array<enum> | no | `["ground"]` | `ground` · `air` · `mounted` · `sprinting` · `blocking`. Fuera de esos estados la habilidad no arranca. Nunca: muerto, aturdido, bebiendo frasco, agotado |
| `interruptible_by` | array<enum> | no | `[]` | `stun_lvl1` (tambaleo) · `stun_lvl2` (aturdido) · `knockdown` · `parry` · `guard_break` · `stance_break` · `grab`. **Lista vacía = no se corta** (solo se esquiva). Quien se corta lo declara, por ejemplo `["stun_lvl2","knockdown","parry"]` |
| `interrupt_priority` | int | no | `0` | desempate determinista (§8.4) |
| `on_interrupt.recovery_ticks` | int ≥ 0 | no | `0` | recuperación extra tras ser cortada (además del aturdimiento recibido) |
| `on_interrupt.cancel_spawns` | bool | no | `true` | marcas/zonas que aún no estallaron desaparecen |
| `on_interrupt.cooldown` | enum | no | `"full"` | `full` (propia + global) · `global_only` · `none` |
| `on_interrupt.refund_pct` | int 0..100 | no | `0` | devolución del costo |
| `entry_step` | string | no | id del primer paso | paso inicial |
| `steps` | array<Step> | sí | — | **longitud variable: 1..N pasos** (no hay un número fijo; 1 es válido, 7 también). Tope práctico 16 |
| `ai` | objeto | sí | — | §4.1 |
| `hint` | objeto | no | — | **solo para IA y tutorial**, la sim lo ignora (§5.7) |

### 4.1 Bloque `ai`

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `range_min` | number (m) | `0` | distancia mínima al objetivo para elegirla |
| `range_max` | number (m) | — | obligatoria; `range_max ≥ range_min` |
| `weight` | int 1..100 | `10` | peso relativo frente a las otras habilidades disponibles |
| `use_when` | array<enum> | `["target_in_range"]` | `target_in_range` · `target_recovering` (rival castigable) · `target_far` · `target_close` · `target_blocking` · `target_healing` (bebiendo frasco, estado visible) · `target_downed` · `self_low_hp` · `self_phase2` · `opener` |
| `branch_weights` | objeto | — | pesos por paso destino de un `branch` (§8.3), p. ej. `{"remate_normal": 60, "remate_alt": 40}` |

La IA (`net/sim/sim_ai.gd`) **lee estado**, nunca las entradas crudas del rival en el mismo tick, y decide con su
propio RNG sembrado. Hoy solo juega offline, pero igual no debe hacer trampa.

---

## 5. Paso (`step`)

Una habilidad es una lista de **1..N pasos** (sin cantidad fija). Cada paso es una acción completa:
**anticipación (`windup`) → activo (`active`) → recuperación (`recovery`)** y luego una transición (`next`,
`cancel_into` o `branch`). Cada paso tiene **su propia recuperación castigable**.

**Bases de tiempo** (muy importante):
- **`t_step`**: tick dentro del paso; `0` = primer tick de la anticipación. Rango `0 .. windup+active+recovery−1`.
  Lo usan `telegraph`, `armor`, `self_invuln`, `tracking.lock_at_tick`, `movement`, `events`, `spawns`,
  `cancel_into` y `branch` (salvo `branch.time_base = "active"`).
- **`t_active`**: tick relativo al **inicio del activo** (`t_active = t_step − windup_ticks`). Lo usan **solo**
  las cajas de golpe (`hitboxes[].from_tick/to_tick`).
- Los intervalos son **semiabiertos** `[from, to)`: `from` incluido, `to` excluido.

```json
{
  "id": "golpe_tardio",
  "windup_ticks": 75,
  "active_ticks": 6,
  "recovery_ticks": 54,
  "telegraph": { "id": "tg_hachazo_ambar", "style": "weapon_glow", "color": "#FFB347", "sound": "sfx_tele_hachazo", "ground_marker": null, "at_tick": 0 },
  "armor": { "type": "super", "from_tick": 0, "to_tick": 81, "poise_bonus_pct": 80, "dmg_reduction_pct": 0 },
  "self_invuln": null,
  "tracking": { "deg_per_sec": 220, "lock_at_tick": 66, "post_lock_deg_per_sec": 0 },
  "movement": { "type": "dash", "from_tick": 69, "to_tick": 81, "speed_mps": 7, "max_distance_m": 1.4, "target_mode": "facing", "stop_at_m": 1.0 },
  "hitboxes": [],
  "spawns": [],
  "cancel_into": null,
  "branch": null,
  "next": { "default": null },
  "events": [ { "id": "ev_destello", "tick": 60, "vfx": "vfx_flash_white", "sfx": "sfx_blade_ring" } ]
}
```

| Campo | Tipo | Oblig. | Default | Restricciones |
|---|---|---|---|---|
| `id` | string | sí | — | único **dentro de la habilidad** |
| `windup_ticks` | int | sí | — | ≥ 1 (≥ 18 si algún hitbox del paso es imbloqueable, V07) |
| `active_ticks` | int | sí | — | ≥ 1 |
| `recovery_ticks` | int | sí | — | ≥ 0; **≥ 18** si el paso es terminal (puede terminar la habilidad) |
| `telegraph` | objeto | sí en el paso de entrada y en todo paso con hitbox imbloqueable | — | §5.1 |
| `armor` | objeto o null | no | `null` | §5.2 |
| `self_invuln` | objeto o null | no | `null` | §5.3 |
| `tracking` | objeto o null | no | sin giro | §5.4 |
| `movement` | objeto o null | no | `null` | §7.1 |
| `hitboxes` | array | no | `[]` | §6 |
| `spawns` | array | no | `[]` | §10 |
| `cancel_into` | objeto o null | no | `null` | §8.2 |
| `branch` | objeto o null | no | `null` | §8.3 |
| `next` | objeto | no | `{"default": null}` | §8.1. `null` = la habilidad termina |
| `max_loops` | int 1..5 | no | — | obligatorio si el paso puede volver a sí mismo (ciclo) |
| `extra_cost` | objeto `{stamina,mana,health}` | no | `null` | costo adicional al **entrar** en el paso (p. ej. un remate). Si no se puede pagar, se sigue `next.default` del paso anterior o se termina |
| `events` | array | no | `[]` | §9 |

### 5.1 `telegraph`

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `id` | string | — | **único en todo el catálogo**. Prefijo recomendado `tg_` |
| `style` | enum | — | `weapon_glow` · `weapon_flash` · `body_pose` · `aura` · `ground_ring` · `ground_line` · `ground_cone` · `sky_column` · `vanish` |
| `color` | string `#RRGGBB` | — | distinto entre las habilidades de un mismo preset |
| `sound` | string | — | id de sonido; distinto entre las habilidades de un mismo preset |
| `ground_marker` | objeto o null | `null` | `{shape, anchor, fill_ticks}`: dibuja en el suelo la forma **real** del golpe y se llena en `fill_ticks` |
| `at_tick` | int (`t_step`) | `0` | cuándo aparece |
| `text` | string | — | descripción para el códice («Se reconoce: …») |

El aviso es **presentación**: la sim no lo lee, pero se deriva del estado (habilidad + paso + `t_step`) para que un
rollback lo corrija sin duplicarlo.

### 5.2 `armor`

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `type` | enum | — | `hyper` = no acumula aturdimiento (no lo cortan niveles de aturdimiento ni derribo); `super` = robustez × (1 + `poise_bonus_pct`/100) |
| `from_tick`, `to_tick` | int (`t_step`) | — | `0 ≤ from < to ≤ duración del paso` |
| `poise_bonus_pct` | int 0..500 | `100` | solo `super`. Referencia actual: fuerte en anticipación +100, dash/salto +50 |
| `dmg_reduction_pct` | int 0..50 | `0` | daño recibido reducido en ese tramo |

`hyper` siempre requiere aviso claro (aura) y recuperación castigable después.

### 5.3 `self_invuln`

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `from_tick`, `to_tick` | int (`t_step`) | — | tramo |
| `mode` | enum | `"stun_immune"` | `stun_immune` = la «invulnerabilidad» del juego: no acumula aturdimiento y recibe daño × `dmg_taken_pct`. `total` = sin daño ni aturdimiento: **solo** con tag `mana_shield` |
| `dmg_taken_pct` | int 50..100 | `85` | solo `stun_immune` |

### 5.4 `tracking`

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `deg_per_sec` | number 0..1080 | `0` | giro máximo hacia el objetivo antes del bloqueo |
| `lock_at_tick` | int (`t_step`) | `windup_ticks` | desde acá deja de seguir (o sigue a `post_lock_deg_per_sec`); también fija el `lock_point` |
| `post_lock_deg_per_sec` | number | `0` | giro residual tras el bloqueo; recomendado ≤ 60 |

**El tick de bloqueo define la ventana de esquiva**: entre `lock_at_tick` y el primer tick activo está el tiempo
que tiene el defensor para apartarse sin que el golpe lo corrija. Más corto = más difícil.

### 5.5 Daño por golpe (sin totales ambiguos)

El daño **siempre se escribe por impacto** (`damage_per_hit`) en cada caja de golpe. Nunca «30 de daño en total
repartido en 6 tajos». Si un hitbox puede pegar varias veces (`hits` > 1), el máximo de ese hitbox es
`hits × damage_per_hit`; lo calcula el validador, no el autor.

### 5.6 Resultado del paso

Al terminar el activo, el paso queda con **un** resultado, que decide las ramas:
- `hit`: al menos un impacto conectó sin ser bloqueado ni esquivado.
- `blocked`: hubo contacto y todos fueron bloqueados.
- `whiff`: ningún contacto (incluye esquivado con voltereta y golpes absorbidos por invulnerabilidad).
- *parry*: no es rama. Si `parry` está en `interruptible_by` y la caja es `parryable`, la habilidad se corta (`on_interrupt`).

### 5.7 Por qué NO hay `dodge_window`, `recommended_direction` ni `iframe_required_ms`

Esos valores **no son datos**: **emergen** de la geometría y el tiempo (forma y tamaño del hitbox, `from/to`,
`tracking.lock_at_tick`, `movement`) contra las reglas fijas del defensor (i-frames de voltereta ≈ 24 ticks,
distancia de voltereta 4,5 m, salto que evita golpes a ras de suelo). Si se escribieran aparte, podrían
contradecir lo que la sim realmente hace. Lo único permitido es un `hint` **opcional** para la IA y el tutorial:

```json
"hint": { "dodge": "roll_late", "direction": "side", "text": "Rodá cuando baje el arma, hacia un costado." }
```
`hint.dodge` ∈ `roll_early` · `roll_late` · `roll_through` · `sidestep` · `jump` · `distance` · `parry` · `block`;
`hint.direction` ∈ `side` · `back` · `forward` · `any`. La sim nunca lo lee.

---

## 6. Cajas de golpe (`hitboxes[]`)

```json
{
  "id": "hb_tajo",
  "shape": { "type": "arc", "radius_m": 3.0, "angle_deg": 110 },
  "offset": { "forward_m": 0.0, "right_m": 0.0 },
  "anchor": "self",
  "ground_only": false,
  "from_tick": 0, "to_tick": 6,
  "hits": 1, "hit_interval_ticks": 0,
  "damage_per_hit": 38,
  "damage_type": "physical",
  "damage_scaling": "attacker",
  "blockable": false, "parryable": false,
  "stun_power": 40, "stun_scaling": "physical",
  "on_hit": { "knockback": { "speed_mps": 6, "duration_ticks": 8 }, "knockdown": false, "status": null, "force": null },
  "lifesteal_pct": 0
}
```

| Campo | Tipo | Default | Restricciones |
|---|---|---|---|
| `id` | string | — | único en el paso |
| `shape` | objeto | — | §7.4 |
| `offset.forward_m`, `.right_m` | number | `0` | desde el ancla, en el rumbo del atacante |
| `anchor` | enum | `"self"` | `self` (se mueve con el atacante) · `lock_point` (posición del objetivo al `lock_at_tick`) · `spawn_point` (posición del atacante al empezar el paso) |
| `ground_only` | bool | `false` | true = no golpea a quien está en el aire > 0,35 m (el salto lo evita) |
| `from_tick`, `to_tick` | int (`t_active`) | — | `0 ≤ from < to ≤ active_ticks` |
| `hits` | int 1..20 | `1` | veces que este hitbox puede golpear al mismo objetivo |
| `hit_interval_ticks` | int | `0` | ≥ 1 si `hits` > 1: separación mínima entre impactos |
| `damage_per_hit` | number ≥ 0 | — | puntos de vida **antes** de defensas y armadura |
| `damage_type` | enum | `"physical"` | `physical` · `fuego` · `magico` · `sagrado` · `rayo` · `hielo` (tablas de defensa existentes) |
| `damage_scaling` | enum | `"attacker"` | `weapon_heavy` / `weapon_light` = `damage_per_hit` × el fuerte o el ligero del arma × el multiplicador de daño del atacante. Si la habilidad es mágica, además × magia/100. `attacker` = solo ese multiplicador · `magic` = × magia/100 · `none` = el número tal cual |
| `blockable` | bool | `true` | false = imbloqueable (V07) |
| `parryable` | bool | `true` | false = el parry no la corta. Imbloqueable ⇒ en general también `parryable: false` |
| `stun_power` | number ≥ 0 | — | fuerza de aturdimiento de este impacto (escala §2.2) |
| `stun_scaling` | enum | `"physical"` | `physical` = + fuerza por Fuerza + fuerza del arma, × `stun_dealt` · `magic` = + magia × 0,1 · `none` |
| `on_hit.knockback` | objeto o null | `null` | `{speed_mps 0..12, duration_ticks 1..20}` empuje horizontal |
| `on_hit.knockdown` | bool | `false` | fuerza el nivel 3 (derribo) si el objetivo no es inmune. Solo en golpes finales con windup ≥ 30 |
| `on_hit.status` | objeto o null | `null` | §7.3 |
| `on_hit.force` | objeto o null | `null` | §7.2 (pull/push/launch/root) |
| `consumes_mark` | bool | `false` | detona una `mark` del objetivo (§7.3) |
| `lifesteal_pct` | int 0..50 | `0` | % del daño **efectivamente infligido** que se cura el atacante |

Un objetivo nunca recibe dos impactos del mismo hitbox en el mismo tick. Hitboxes distintos del mismo paso sí
pueden pegar en el mismo tick (se suman, y cada uno aporta a la acumulación de aturdimiento con su tope de 0,95).

---

## 7. Bloques de construcción

### 7.1 Movimiento (`movement`)

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `type` | enum | — | `none` · `dash` · `leap` · `slam` · `teleport_behind` · `orbit` · `retreat` |
| `from_tick`, `to_tick` | int (`t_step`) | — | tramo del movimiento |
| `target_mode` | enum | `"facing"` | `facing` (rumbo actual, sujeto a `tracking`) · `target` (hacia el objetivo) · `lock_point` (punto fijado) · `away_from_target` |
| `speed_mps` | number 0..40 | — | `dash`, `retreat`, `orbit` |
| `max_distance_m` | number ≤ 14 | — | **tope obligatorio** de recorrido |
| `stop_at_m` | number | `0` | se detiene a esta distancia del objetivo (no lo atraviesa) |
| `height_m` | number 0..8 | — | `leap`: altura del arco; durante `leap` el luchador está en el aire |
| `distance_m` | number 0..4 | — | `teleport_behind`: distancia detrás del objetivo |
| `orbit_deg` | number | — | `orbit`: grados a rodear (signo = sentido) |

- `leap` en pasos encadenados = **combo aéreo**: el luchador sigue en el aire mientras los pasos usen `leap`;
  `slam` lo baja con caída rápida.
- `teleport_behind`: siempre con `telegraph.style = "vanish"` y reaparición visible ≥ 12 ticks antes del activo.
- Todo movimiento se recorta contra el muro (radio 40 m − 0,45 m) y los pilares.

### 7.2 Fuerza sobre el objetivo (`on_hit.force`)

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `type` | enum | — | `pull` (arrastra al objetivo hacia el atacante) · `push` · `launch` (lo levanta) · `root` (lo fija en el lugar) |
| `strength_mps` | number | — | velocidad del arrastre/empuje; en `launch`, velocidad vertical |
| `duration_ticks` | int | — | `pull`: ~18 (0,3 s), máx. 24; `root`: máx. 45 |
| `max_distance_m` | number | — | **tope obligatorio** (`pull` ≤ 4) |
| `breakable_by` | array<enum> | `["roll"]` | `roll` · `jump` · `parry` · `damage_taken` · `none` |

**Por qué el `pull` va corto, con tope y rompible rodando**: quitarle el control al rival frustra mucho en PvP, y
con rollback las correcciones de una posición forzada son muy visibles (el rival «salta» de lugar). Un tirón de
~0,3 s, limitado y que se rompe rodando, se lee bien y se corrige poco.

### 7.3 Estados (`on_hit.status`)

| Campo | Tipo | Notas |
|---|---|---|
| `type` | enum | `sangrado` · `slow` · `silence` · `mark` |
| `duration_ticks` | int 1..600 | duración |
| `tick_interval` | int | `sangrado`: cada cuántos ticks hace daño |
| `damage` | number | daño por intervalo (`sangrado`) o daño extra al consumir la marca (`mark`) |
| `stacks_max` | int 1..5 | acumulación máxima (cada aplicación renueva la duración) |
| `slow_pct` | int 10..50 | solo `slow` |

`silence` impide usar habilidades y hechizos (no atacar ni rodar). `mark` sola no hace nada: un hitbox con
`consumes_mark: true` la detona. (El juego tiene además la *acumulación* de sangrado/veneno/congelación de las
armas; ese sistema sigue aparte.)

### 7.4 Formas (`shape`)

| `type` | Dimensiones | Notas |
|---|---|---|
| `circle` | `radius_m` | centrado en ancla + offset |
| `arc` | `radius_m`, `angle_deg` (arco **total**, 1..360) | abanico frente al atacante |
| `line` | `length_m`, `width_m` | rectángulo desde el ancla hacia adelante |
| `ring` | `inner_m`, `outer_m` | anillo; dentro de `inner_m` se está a salvo |
| `box` | `length_m`, `width_m` | rectángulo centrado en ancla + offset |

El radio del cuerpo del objetivo (0,75 m) se suma solo; no lo incluyas en las dimensiones.

---

## 8. Ramas: `next`, `cancel_into` y remates a elección (`branch`)

### 8.1 `next`

```json
"next": { "default": "remate", "on_hit": "remate", "on_whiff": "tropiezo", "on_blocked": null }
```
- Se evalúa **al terminar la recuperación** del paso, según el resultado (§5.6). Si falta la clave específica, se usa `default`.
- `null` (o `"end"`) = la habilidad termina y arranca la recarga.
- Todo id debe existir en `steps`. Ciclos solo con `max_loops`.

### 8.2 `cancel_into`

```json
"cancel_into": { "window_from_tick": 40, "window_to_tick": 52, "steps": ["remate"], "only_on": "hit", "trigger": "auto" }
```
| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `window_from_tick`, `window_to_tick` | int (`t_step`) | — | dentro del activo + recuperación |
| `steps` | array<string> | — | candidatos; se toma **el primero válido** (costo pagable, condición cumplida) |
| `only_on` | enum | `"any"` | `hit` · `blocked` · `whiff` · `any` |
| `trigger` | enum | `"auto"` | `auto` (salta en `window_from_tick`) · `skill` (al pulsar la habilidad dentro de la ventana) |

Sirve para acortar la recuperación de un paso intermedio y encadenar. El paso destino tiene su propia recuperación.

### 8.3 Combos con variaciones / remates a elección (`branch`)

En un punto de bifurcación **el jugador elige cómo rematar**: pulsar el **botón habitual** de la habilidad de
jefe da el remate normal; un **botón contextual aparte** (aparece junto al botón de habilidad **solo mientras dura
esa ventana** en el HUD táctil, y con tecla asignada en PC) dispara un remate alternativo. Puede haber más de dos
opciones y ramas anidadas; cada remate alternativo puede tener su propio costo y sus condiciones.

```json
"branch": {
  "window_from_tick": 32,
  "window_to_tick": 66,
  "time_base": "step",
  "only_on": "any",
  "buffer_ticks": 6,
  "commit": "window_end",
  "options": [
    { "input": "skill", "step": "remate_caida" },
    { "input": "alt", "step": "remate_embestida", "hud_icon": "generic", "label": "Embestida", "extra_cost": { "stamina": 10 }, "requires": [] }
  ],
  "default_if_no_input": "end"
}
```

| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `window_from_tick`, `window_to_tick` | int | — | `[from, to)`, dentro de la duración del paso |
| `time_base` | enum | `"step"` | `step` (`t_step`) o `active` (`t_active`) |
| `only_on` | enum | `"any"` | `hit` · `blocked` · `whiff` · `any`. Si no se cumple, la ventana no se abre y manda `next` |
| `buffer_ticks` | int 0..12 | `6` | se acepta una pulsación hasta N ticks **antes** de que abra la ventana |
| `commit` | enum | `"window_end"` | `window_end` = la transición ocurre al cerrar la ventana o al terminar la recuperación (lo que pase antes) · `immediate` = en el tick de la pulsación aceptada |
| `options[]` | array, 1..4 | — | cada una: `input`, `step` y opcionales `hud_icon`, `label`, `extra_cost`, `requires` |
| `options[].input` | enum | — | `skill` (mismo botón de la habilidad) · `alt` (botón contextual) · `alt2` (reservado: hoy no hay bit de entrada disponible) |
| `options[].extra_cost` | objeto | `null` | costo adicional de esa opción (aguante/maná/vida) |
| `options[].requires` | array<string> | `[]` | `target_close` · `target_far` · `last_hit_landed` · `phase2` · `mana_ge:<n>` |
| `default_if_no_input` | string | `"end"` | id de paso, o `end`, si nadie pulsa en la ventana |

**Reglas de resolución (deterministas):**
1. La entrada es un **bit de entrada de la sim**: una pulsación de un tick (flanco), igual que el ciclo ▶ de
   habilidades (`SimMatch.pulse`). Nunca una señal de la vista ni del HUD.
2. Gana **la primera pulsación** aceptada dentro de la ventana (o en el búfer previo). Si en el mismo tick llegan
   `skill` y `alt`, gana **la que aparece primero en `options`**.
3. Si la opción pulsada no cumple `requires` o su `extra_cost` no se puede pagar, esa pulsación se ignora y la
   ventana sigue abierta.
4. Una vez aceptada una opción, las demás pulsaciones de la ventana se ignoran.
5. Ramas **anidadas**: el paso destino puede tener su propio `branch`.

**HUD:** el botón alternativo (icono `hud_icon`, texto `label`) se muestra **solo mientras la ventana está abierta
según el estado de la sim** (habilidad en curso + paso + `t_step`, que SimView vuelca a la vista). Nunca se decide
la visibilidad solo en la vista: así se produjo el «parpadeo» del ciclo ▶ que se corrigió en la fase 9. En PC el
botón alternativo usa la tecla de la acción `boss_variation` (hoy `M`).

**IA:** elige con `ai.branch_weights` (filtrando por `requires` y costo) usando su RNG propio.

**Validación (V16):** cada `options[].step` existe; la ventana cae dentro del paso; toda opción `alt` tiene
`hud_icon` y `label`; no hay dos opciones con el mismo `input`; `default_if_no_input` existe o es `end`; cada
remate tiene un aviso distinguible de los otros (el defensor reacciona a la elección, no la adivina).

### 8.4 Prioridad y conflictos (deterministas)

Cuando en un mismo tick se cumplen varias cosas para un luchador, el orden es fijo:
1. muerte → 2. `parry` (si interrumpe) → 3. `knockdown` → 4. `grab` → 5. `guard_break` / `stance_break` →
6. `stun_lvl2` → 7. `stun_lvl1` → 8. `branch` (pulsación) → 9. `cancel_into` → 10. `next`.

Entre los dos luchadores la sim procesa en orden de índice fijo (0 y luego 1), así que los intercambios son
reproducibles. `interrupt_priority` (mayor gana) solo desempata cuando dos habilidades de **distinto dueño** se
resuelven en el mismo tick con la misma regla.

---

## 9. Eventos visuales y de sonido (rollback-safe)

```json
"events": [
  { "id": "ev_salto", "tick": 0, "vfx": "vfx_dust_ring", "sfx": "sfx_leap" },
  { "id": "ev_impacto", "tick": 48, "vfx": "vfx_crack", "sfx": "sfx_slam", "camera_shake": 2, "on": "always" }
]
```
| Campo | Tipo | Default | Notas |
|---|---|---|---|
| `id` | string | — | único en la habilidad |
| `tick` | int (`t_step`) | — | cuándo dispara |
| `vfx`, `sfx` | string o null | `null` | ids de efecto/sonido |
| `camera_shake` | int 0..3 | `0` | |
| `on` | enum | `"always"` | `always` · `hit` · `whiff` |

**Clave estable**: el evento se deduce del estado (habilidad, paso, `t_step`) y su clave es
`frame:ab_ev:<jugador>:<ability_code>:<step_id>:<event_id>`. Si tras un rollback ese estado ya no ocurre, el
evento retenido se cancela; si ocurre igual, la clave coincide y no se repite. Es el mismo mecanismo que hoy usan
`SimEvents` + `SimFx` (retención de 2 ticks online). Nunca dispares efectos desde la vista por tu cuenta.

---

## 10. Tipos de ataque futuros (`spawns[]` y extensiones)

Todo `spawn` lleva `{id, type, at_tick (t_step), anchor, offset, count, spread_deg}` y ocupa plazas de las
piscinas de la sim (proyectiles 12, peligros 16, compartidas). El validador rechaza habilidades que en el peor caso
ocupen más de **6 proyectiles** u **8 peligros** a la vez.

| Tipo | Campos propios | Notas |
|---|---|---|
| `ground_mark` (hoy «lluvia») | `shape`, `warn_ticks` (≥ 30), `damage`, `stun_power`, `knockback_mps`, `blockable`, `mode: track\|scatter`, `scatter_radius_m`, `interval_ticks` | `scatter` usa el RNG de la sim |
| `ground_wave` (hoy «onda») | `speed_mps`, `range_m`, `width_m`, `warn_ticks`, `ring` (bool), `knockback_mps` | siempre `ground_only` (se salta). El empuje `knockback_mps` vale **6** si se omite |
| `projectile` | `speed_mps`, `homing_deg` (°/s), `homing_ticks`, `lifetime_ticks`, `radius_m`, `pierce` (bool), `reflectable_by_parry` (bool), `hitbox` | giro entero con tope; si esquivás, sigue de largo |
| `zone` (persistente) | `shape`, `delay_ticks`, `duration_ticks`, `hitbox_every_ticks`, `damage`, `status` | máx. 2 por luchador |
| `beam` (rayo / aliento) | `length_m`, `width_m` o `angle_deg`, `duration_ticks`, `tick_interval`, `sweep_deg_per_sec` | hoy existe como cono («aliento») |
| `summon` | `entity`, `hp`, `lifetime_ticks`, `cap` (1..2) | el invocado vive en el estado de la sim (cuesta tamaño de estado y checksum): tope 1–2 |

Extensiones previstas de paso/habilidad:
- **Agarres** (`category: grab`): siempre `blockable: false`, **rodables**, windup ≥ 24. Al conectar, los dos
  entran en una pose sincronizada `grab: {duration_ticks, damage_per_hit, release_distance_m}` que resuelve la
  sim; la cinemática es solo vista y conviene diferir la cámara hasta que el tick esté confirmado, porque un
  rollback a mitad de un agarre se ve muy mal.
- **Contras / posturas** (`category: counter`): `stance: {from_tick, to_tick}` + rama `next.on_hit_received` → paso
  de castigo. Si no lo atacan, recuperación larga (≥ 45).
- **Carga** (`charge: {max_ticks, scale: {damage_pct_max, stun_pct_max, range_pct_max}}`): mantener el botón
  alarga la anticipación hasta `max_ticks`; los multiplicadores escalan **linealmente en enteros**.
- **Bufos y escudos propios** (`category: buff`): `buff: {duration_ticks, damage_pct, speed_pct, poise_bonus_pct,
  shield_hp}`, con aura visible mientras dure.
- **Variantes por fase** (`phase_overrides: {"2": { …campos a reemplazar… }}`): mismo id, números distintos en Fase II.
- **Montura / eikon**: `usable_while: ["mounted"]` habilita la habilidad montado; `eikon_interaction`
  (`none` · `boost` · `summon_assist`) queda reservado.
- **Robo de vida**: por hitbox (`lifesteal_pct`), nunca global.

---

## 11. Reglas cruzadas y validación

| Código | Regla |
|---|---|
| V01 | `tick_rate` = 60; `version` ≥ 1 |
| V02 | ids de habilidad únicos en el catálogo; ids de paso únicos en la habilidad; ids de hitbox/evento/spawn únicos en su contenedor |
| V03 | `telegraph.id` único en **todo** el catálogo; color + sonido distintos entre las habilidades de un mismo preset |
| V04 | todo `next.*`, `cancel_into.steps[]`, `branch.options[].step`, `default_if_no_input` y `entry_step` apunta a un paso existente (o `end`/`null`) |
| V05 | todos los pasos son alcanzables desde `entry_step`; no hay ciclos sin `max_loops` |
| V06 | toda ruta termina; todo paso que puede terminar la habilidad tiene `recovery_ticks` ≥ 18 |
| V07 | si un paso tiene algún hitbox `blockable: false`, su `windup_ticks` ≥ 18 **y** tiene telegraph propio visible (recomendado ≥ 30) |
| V08 | `from/to` dentro de rango (`t_active` para hitboxes, `t_step` para lo demás) y `from < to` |
| V09 | campos `int` sin decimales; decimales solo donde se indica (vida, metros, grados, m/s), ≤ 3 cifras; nada de exponentes, NaN ni infinito |
| V10 | al menos un costo > 0; el costo de vida se recorta para dejar ≥ 1 de vida |
| V11 | `self_invuln.mode = total` solo con tag `mana_shield` |
| V12 | `force.pull`: `duration_ticks` ≤ 24, `max_distance_m` ≤ 4, `breakable_by` no vacío |
| V13 | todo `movement` distinto de `none` tiene `max_distance_m` |
| V14 | presets: 1..3 ids existentes, sin repetir |
| V15 | `unlock.phase` = 2 solo tiene sentido en el 3.er lugar de un preset (aviso si no) |
| V16 | `branch`: opciones válidas, sin `input` repetido, `alt` con `hud_icon` y `label`, ventana dentro del paso |
| V17 | piscinas: peor caso ≤ 6 proyectiles y ≤ 8 peligros simultáneos |
| V18 | `interruptible_by` vacío es válido: la habilidad no se corta (solo se esquiva). No exige hiperarmadura |
| V19 | nombres propios: nada de nombres de otras franquicias |

**Mecánicas prohibidas (injustas):**
- Leer la entrada del rival para reaccionar en el mismo tick (p. ej. «se cura si el rival pulsa atacar», «contraataca
  automáticamente al detectar el botón de voltereta»). **No permitido.**
- Golpes imbloqueables sin aviso, o con el mismo aviso que otra habilidad.
- Quitar el control más de ~0,4 s sin forma de romperlo.

**Permitido (y buen diseño):** castigar la **voltereta de pánico** con un golpe retrasado + tracking que se
bloquea tarde (como el Tajo Retardado): el defensor tiene información (el aviso) y una ventana real.

**Determinismo:** todo valor en la sim es entero o punto fijo; azar solo con `rng_next`; ningún campo depende del
framerate, del dispositivo ni del reloj.

---

## 12. Ejemplos completos

> Todos los números son *(ejemplo)*, en la escala real (vida 80–130, fuerte de arma 18–40, robustez 30–80).
> Los campos omitidos toman su default.

### 12.1 «Tormenta Ascendente» — combo aéreo de varios pasos

Salta hacia el objetivo, dos tajos en el aire y caída con golpe en área. 4 pasos.

```json
{
  "id": "tormenta_ascendente",
  "name": "Tormenta Ascendente",
  "icon": "generic",
  "category": "melee",
  "tags": ["aerial", "multi_hit"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 34, "mana": 0, "health": 0 },
  "cooldown_ticks": 600,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["stun_lvl2", "knockdown", "parry"],
  "on_interrupt": { "recovery_ticks": 12, "cancel_spawns": true, "cooldown": "full" },
  "steps": [
    {
      "id": "despegue",
      "windup_ticks": 24, "active_ticks": 1, "recovery_ticks": 0,
      "telegraph": { "id": "tg_tormenta_remolino", "style": "body_pose", "color": "#7FD4FF", "sound": "sfx_tele_tormenta", "ground_marker": null, "at_tick": 0, "text": "Se agacha y lo envuelve un remolino celeste." },
      "tracking": { "deg_per_sec": 360, "lock_at_tick": 24, "post_lock_deg_per_sec": 90 },
      "movement": { "type": "leap", "from_tick": 24, "to_tick": 25, "height_m": 2.5, "speed_mps": 10, "max_distance_m": 6, "target_mode": "target", "stop_at_m": 1.5 },
      "next": { "default": "tajo_aereo_1" },
      "events": [ { "id": "ev_polvo", "tick": 24, "vfx": "vfx_dust_ring", "sfx": "sfx_leap" } ]
    },
    {
      "id": "tajo_aereo_1",
      "windup_ticks": 12, "active_ticks": 5, "recovery_ticks": 4,
      "armor": { "type": "super", "from_tick": 0, "to_tick": 21, "poise_bonus_pct": 50, "dmg_reduction_pct": 0 },
      "tracking": { "deg_per_sec": 180, "lock_at_tick": 8, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "leap", "from_tick": 0, "to_tick": 21, "height_m": 2.5, "speed_mps": 6, "max_distance_m": 2, "target_mode": "facing" },
      "hitboxes": [
        { "id": "hb_t1", "shape": { "type": "arc", "radius_m": 2.6, "angle_deg": 120 }, "from_tick": 0, "to_tick": 5,
          "hits": 1, "damage_per_hit": 14, "blockable": true, "parryable": true, "stun_power": 12 }
      ],
      "next": { "default": "tajo_aereo_2" },
      "events": [ { "id": "ev_t1", "tick": 12, "vfx": "vfx_trail_cyan", "sfx": "sfx_swing_air" } ]
    },
    {
      "id": "tajo_aereo_2",
      "windup_ticks": 14, "active_ticks": 5, "recovery_ticks": 2,
      "armor": { "type": "super", "from_tick": 0, "to_tick": 21, "poise_bonus_pct": 50, "dmg_reduction_pct": 0 },
      "tracking": { "deg_per_sec": 180, "lock_at_tick": 9, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "leap", "from_tick": 0, "to_tick": 21, "height_m": 2.8, "speed_mps": 4, "max_distance_m": 1.5, "target_mode": "facing" },
      "hitboxes": [
        { "id": "hb_t2", "shape": { "type": "arc", "radius_m": 2.6, "angle_deg": 120 }, "from_tick": 0, "to_tick": 5,
          "hits": 1, "damage_per_hit": 16, "blockable": true, "parryable": true, "stun_power": 14 }
      ],
      "next": { "default": "caida" },
      "events": [ { "id": "ev_t2", "tick": 14, "vfx": "vfx_trail_cyan", "sfx": "sfx_swing_air" } ]
    },
    {
      "id": "caida",
      "windup_ticks": 20, "active_ticks": 4, "recovery_ticks": 42,
      "telegraph": { "id": "tg_tormenta_caida", "style": "ground_ring", "color": "#7FD4FF", "sound": "sfx_tele_caida", "ground_marker": { "shape": { "type": "circle", "radius_m": 3.2 }, "anchor": "lock_point", "fill_ticks": 20 }, "at_tick": 0 },
      "tracking": { "deg_per_sec": 0, "lock_at_tick": 0, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "slam", "from_tick": 0, "to_tick": 20, "target_mode": "lock_point", "max_distance_m": 3 },
      "hitboxes": [
        { "id": "hb_caida", "shape": { "type": "circle", "radius_m": 3.2 }, "anchor": "self", "ground_only": true, "from_tick": 0, "to_tick": 4,
          "hits": 1, "damage_per_hit": 24, "blockable": true, "parryable": false, "stun_power": 38,
          "on_hit": { "knockback": { "speed_mps": 7, "duration_ticks": 8 } } }
      ],
      "next": { "default": null },
      "events": [ { "id": "ev_golpe", "tick": 20, "vfx": "vfx_crack_ring", "sfx": "sfx_slam", "camera_shake": 2 } ]
    }
  ],
  "ai": { "range_min": 3.0, "range_max": 7.0, "weight": 12, "use_when": ["target_in_range", "target_recovering"] },
  "hint": { "dodge": "roll_late", "direction": "side", "text": "Bloqueá los tajos y rodá cuando el círculo se llene." }
}
```
Lectura: dos tajos bloqueables de 14 y 16 por golpe + caída de 24 (máximo teórico 54 si conecta todo). El último
paso deja 42 ticks (700 ms) de recuperación en el suelo para castigar.

### 12.2 «Hachazo del Penitente» — golpe retrasado

Alza el arma, amaga a mitad y golpea tarde, imbloqueable. El tracking se fija tarde: castiga la voltereta de pánico
pero no la voltereta a tiempo.

```json
{
  "id": "hachazo_penitente",
  "name": "Hachazo del Penitente",
  "icon": "generic",
  "category": "melee",
  "tags": ["unblockable", "delayed", "tracking"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 26, "mana": 0, "health": 0 },
  "cooldown_ticks": 420,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["knockdown"],
  "on_interrupt": { "recovery_ticks": 20, "cancel_spawns": true, "cooldown": "full" },
  "steps": [
    {
      "id": "golpe_tardio",
      "windup_ticks": 75, "active_ticks": 6, "recovery_ticks": 54,
      "telegraph": { "id": "tg_hachazo_ambar", "style": "weapon_glow", "color": "#FFB347", "sound": "sfx_tele_hachazo", "ground_marker": null, "at_tick": 0, "text": "Hoja ámbar en alto; parpadea en blanco antes del golpe." },
      "armor": { "type": "super", "from_tick": 0, "to_tick": 81, "poise_bonus_pct": 80, "dmg_reduction_pct": 0 },
      "tracking": { "deg_per_sec": 220, "lock_at_tick": 66, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "dash", "from_tick": 69, "to_tick": 81, "speed_mps": 7, "max_distance_m": 1.4, "target_mode": "facing", "stop_at_m": 1.0 },
      "hitboxes": [
        { "id": "hb_hachazo", "shape": { "type": "arc", "radius_m": 3.0, "angle_deg": 110 }, "from_tick": 0, "to_tick": 6,
          "hits": 1, "damage_per_hit": 40, "blockable": false, "parryable": false, "stun_power": 40,
          "on_hit": { "knockback": { "speed_mps": 5, "duration_ticks": 6 } } }
      ],
      "spawns": [
        { "id": "sp_onda", "type": "ground_mark", "at_tick": 81, "anchor": "self", "offset": { "forward_m": 1.5 }, "count": 1,
          "shape": { "type": "circle", "radius_m": 4.5 }, "warn_ticks": 30, "damage": 26, "stun_power": 40, "blockable": true }
      ],
      "next": { "default": null },
      "events": [
        { "id": "ev_amague", "tick": 34, "vfx": "vfx_flash_white", "sfx": "sfx_fake_swing" },
        { "id": "ev_destello", "tick": 60, "vfx": "vfx_flash_white", "sfx": "sfx_blade_ring" },
        { "id": "ev_impacto", "tick": 75, "vfx": "vfx_crack", "sfx": "sfx_heavy_hit", "on": "hit" }
      ]
    }
  ],
  "ai": { "range_min": 1.0, "range_max": 4.0, "weight": 10, "use_when": ["target_in_range", "target_blocking"] },
  "hint": { "dodge": "roll_late", "direction": "side", "text": "Esperá el segundo destello y recién ahí rodá." }
}
```
Ventana de esquiva emergente: el tracking se fija en `t_step` 66 y el golpe sale en 75 → 9 ticks (150 ms) para
salir del arco caminando; rodando, los i-frames (~24 ticks) cubren de sobra si se rueda después del destello.
La onda posterior (aviso 30 ticks) castiga a quien se queda pegado.

### 12.3 «Cadena del Abismo» — tirón + golpe al suelo

```json
{
  "id": "cadena_abismo",
  "name": "Cadena del Abismo",
  "icon": "generic",
  "category": "grab",
  "tags": ["unblockable"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 0, "mana": 28, "health": 0 },
  "cooldown_ticks": 540,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["stun_lvl2", "knockdown"],
  "on_interrupt": { "recovery_ticks": 18, "cancel_spawns": true, "cooldown": "full" },
  "steps": [
    {
      "id": "lanzar_cadena",
      "windup_ticks": 30, "active_ticks": 8, "recovery_ticks": 6,
      "telegraph": { "id": "tg_cadena_violeta", "style": "ground_line", "color": "#9B59FF", "sound": "sfx_tele_cadena", "ground_marker": { "shape": { "type": "line", "length_m": 8, "width_m": 1.2 }, "anchor": "self", "fill_ticks": 30 }, "at_tick": 0, "text": "Línea violeta en el suelo hacia vos y ruido de eslabones." },
      "tracking": { "deg_per_sec": 240, "lock_at_tick": 22, "post_lock_deg_per_sec": 0 },
      "hitboxes": [
        { "id": "hb_cadena", "shape": { "type": "line", "length_m": 8, "width_m": 1.2 }, "from_tick": 0, "to_tick": 8,
          "hits": 1, "damage_per_hit": 6, "damage_scaling": "magic", "damage_type": "magico", "blockable": false, "parryable": false,
          "stun_power": 0, "stun_scaling": "none",
          "on_hit": { "force": { "type": "pull", "strength_mps": 12, "duration_ticks": 18, "max_distance_m": 3.5, "breakable_by": ["roll"] } } }
      ],
      "next": { "default": "golpe_suelo", "on_whiff": "fallo" }
    },
    {
      "id": "golpe_suelo",
      "windup_ticks": 18, "active_ticks": 4, "recovery_ticks": 48,
      "telegraph": { "id": "tg_cadena_suelo", "style": "ground_ring", "color": "#C9A0FF", "sound": "sfx_tele_slam_vacio", "ground_marker": { "shape": { "type": "circle", "radius_m": 2.8 }, "anchor": "self", "fill_ticks": 18 }, "at_tick": 0 },
      "armor": { "type": "super", "from_tick": 0, "to_tick": 22, "poise_bonus_pct": 100, "dmg_reduction_pct": 0 },
      "hitboxes": [
        { "id": "hb_suelo", "shape": { "type": "circle", "radius_m": 2.8 }, "ground_only": true, "from_tick": 0, "to_tick": 4,
          "hits": 1, "damage_per_hit": 30, "damage_scaling": "magic", "damage_type": "magico", "blockable": true, "parryable": false,
          "stun_power": 45, "stun_scaling": "magic",
          "on_hit": { "knockback": { "speed_mps": 8, "duration_ticks": 10 } } }
      ],
      "next": { "default": null },
      "events": [ { "id": "ev_slam", "tick": 18, "vfx": "vfx_void_burst", "sfx": "sfx_slam", "camera_shake": 2 } ]
    },
    {
      "id": "fallo",
      "windup_ticks": 1, "active_ticks": 1, "recovery_ticks": 36,
      "next": { "default": null },
      "events": [ { "id": "ev_recoge", "tick": 0, "vfx": null, "sfx": "sfx_chain_retract" } ]
    }
  ],
  "ai": { "range_min": 3.5, "range_max": 8.0, "weight": 8, "use_when": ["target_far", "target_healing"] },
  "hint": { "dodge": "sidestep", "text": "Salí de la línea violeta; si te engancha, rodá para soltarte." }
}
```
El tirón dura 18 ticks (0,3 s), recorre como mucho 3,5 m y se rompe rodando. Si la cadena falla, 38 ticks de
exposición. El golpe al suelo es bloqueable y se evita saltando.

### 12.4 «Saeta de Brasas» — proyectil (tipo futuro)

```json
{
  "id": "saeta_brasas",
  "name": "Saeta de Brasas",
  "icon": "generic",
  "category": "ranged",
  "tags": ["projectile"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 0, "mana": 18, "health": 0 },
  "cooldown_ticks": 240,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["stun_lvl1", "stun_lvl2", "knockdown", "parry"],
  "steps": [
    {
      "id": "disparo",
      "windup_ticks": 24, "active_ticks": 1, "recovery_ticks": 30,
      "telegraph": { "id": "tg_saeta_brasa", "style": "weapon_glow", "color": "#FF5A1F", "sound": "sfx_tele_brasa", "ground_marker": null, "at_tick": 0, "text": "La mano se enciende en naranja y chisporrotea." },
      "tracking": { "deg_per_sec": 300, "lock_at_tick": 20, "post_lock_deg_per_sec": 0 },
      "spawns": [
        { "id": "sp_saeta", "type": "projectile", "at_tick": 24, "anchor": "self", "offset": { "forward_m": 1.0 }, "count": 3, "spread_deg": 14,
          "speed_mps": 18, "homing_deg": 40, "homing_ticks": 30, "lifetime_ticks": 120, "radius_m": 0.5, "pierce": false, "reflectable_by_parry": true,
          "hitbox": { "damage_per_hit": 9, "damage_type": "fuego", "damage_scaling": "magic", "blockable": true, "parryable": true, "stun_power": 10, "stun_scaling": "magic" } }
      ],
      "next": { "default": null },
      "events": [ { "id": "ev_disparo", "tick": 24, "vfx": "vfx_ember_burst", "sfx": "sfx_fire_cast" } ]
    }
  ],
  "ai": { "range_min": 6.0, "range_max": 18.0, "weight": 10, "use_when": ["target_far"] },
  "hint": { "dodge": "roll_early", "text": "Rodá a través del abanico o bloqueá; un parry la devuelve." }
}
```
Tres proyectiles de 9 por impacto (no «27 de daño»); ocupa 3 de las 12 plazas.

### 12.5 «Furia del Martillo Rúnico» — combo con remate a elección (`branch`)

Dos golpes y, después del segundo, el jugador elige: **mismo botón** = salto con caída en área; **botón
alternativo** («Embestida») = embestida larga imbloqueable con costo extra. Si no pulsa nada, termina con la
recuperación del segundo golpe.

```json
{
  "id": "martillo_runico",
  "name": "Furia del Martillo Rúnico",
  "icon": "generic",
  "category": "melee",
  "tags": ["multi_hit"],
  "unlock": { "phase": 1 },
  "cost": { "stamina": 30, "mana": 0, "health": 0 },
  "cooldown_ticks": 540,
  "uses_global_cd": true,
  "usable_while": ["ground"],
  "interruptible_by": ["stun_lvl2", "knockdown", "parry"],
  "on_interrupt": { "recovery_ticks": 12, "cancel_spawns": true, "cooldown": "full" },
  "steps": [
    {
      "id": "golpe_1",
      "windup_ticks": 30, "active_ticks": 6, "recovery_ticks": 16,
      "telegraph": { "id": "tg_martillo_runas", "style": "weapon_glow", "color": "#3FE0A0", "sound": "sfx_tele_runas", "ground_marker": null, "at_tick": 0, "text": "Runas verdes se encienden en el arma." },
      "tracking": { "deg_per_sec": 240, "lock_at_tick": 24, "post_lock_deg_per_sec": 30 },
      "movement": { "type": "dash", "from_tick": 26, "to_tick": 36, "speed_mps": 8, "max_distance_m": 2.0, "target_mode": "facing", "stop_at_m": 1.2 },
      "hitboxes": [
        { "id": "hb_g1", "shape": { "type": "arc", "radius_m": 2.6, "angle_deg": 100 }, "from_tick": 0, "to_tick": 6,
          "damage_per_hit": 18, "blockable": true, "parryable": true, "stun_power": 20 }
      ],
      "cancel_into": { "window_from_tick": 40, "window_to_tick": 52, "steps": ["golpe_2"], "only_on": "any", "trigger": "auto" },
      "next": { "default": "golpe_2" }
    },
    {
      "id": "golpe_2",
      "windup_ticks": 26, "active_ticks": 6, "recovery_ticks": 40,
      "tracking": { "deg_per_sec": 240, "lock_at_tick": 20, "post_lock_deg_per_sec": 30 },
      "hitboxes": [
        { "id": "hb_g2", "shape": { "type": "arc", "radius_m": 2.8, "angle_deg": 140 }, "from_tick": 0, "to_tick": 6,
          "damage_per_hit": 20, "blockable": true, "parryable": true, "stun_power": 24 }
      ],
      "branch": {
        "window_from_tick": 32, "window_to_tick": 66, "time_base": "step", "only_on": "any", "buffer_ticks": 6, "commit": "window_end",
        "options": [
          { "input": "skill", "step": "remate_caida" },
          { "input": "alt", "step": "remate_embestida", "hud_icon": "generic", "label": "Embestida", "extra_cost": { "stamina": 10 } }
        ],
        "default_if_no_input": "end"
      },
      "next": { "default": null }
    },
    {
      "id": "remate_caida",
      "windup_ticks": 40, "active_ticks": 4, "recovery_ticks": 48,
      "extra_cost": { "stamina": 6 },
      "telegraph": { "id": "tg_martillo_caida", "style": "ground_ring", "color": "#3FE0A0", "sound": "sfx_tele_caida_runas", "ground_marker": { "shape": { "type": "circle", "radius_m": 4.0 }, "anchor": "lock_point", "fill_ticks": 16 }, "at_tick": 24 },
      "armor": { "type": "super", "from_tick": 0, "to_tick": 44, "poise_bonus_pct": 100, "dmg_reduction_pct": 0 },
      "tracking": { "deg_per_sec": 200, "lock_at_tick": 24, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "leap", "from_tick": 4, "to_tick": 40, "height_m": 3.2, "target_mode": "lock_point", "max_distance_m": 5, "stop_at_m": 0.5 },
      "hitboxes": [
        { "id": "hb_caida", "shape": { "type": "circle", "radius_m": 4.0 }, "ground_only": true, "from_tick": 0, "to_tick": 4,
          "damage_per_hit": 28, "blockable": true, "parryable": false, "stun_power": 48 }
      ],
      "next": { "default": null },
      "events": [ { "id": "ev_caida", "tick": 40, "vfx": "vfx_rune_crack", "sfx": "sfx_slam", "camera_shake": 2 } ]
    },
    {
      "id": "remate_embestida",
      "windup_ticks": 30, "active_ticks": 14, "recovery_ticks": 45,
      "telegraph": { "id": "tg_martillo_embestida", "style": "ground_line", "color": "#FF8A3D", "sound": "sfx_tele_embestida", "ground_marker": { "shape": { "type": "line", "length_m": 6.5, "width_m": 1.6 }, "anchor": "self", "fill_ticks": 30 }, "at_tick": 0 },
      "armor": { "type": "super", "from_tick": 0, "to_tick": 44, "poise_bonus_pct": 100, "dmg_reduction_pct": 0 },
      "tracking": { "deg_per_sec": 300, "lock_at_tick": 24, "post_lock_deg_per_sec": 0 },
      "movement": { "type": "dash", "from_tick": 30, "to_tick": 44, "speed_mps": 22, "max_distance_m": 6.5, "target_mode": "facing", "stop_at_m": 1.0 },
      "hitboxes": [
        { "id": "hb_emb", "shape": { "type": "line", "length_m": 1.8, "width_m": 1.6 }, "from_tick": 0, "to_tick": 14,
          "damage_per_hit": 32, "blockable": false, "parryable": false, "stun_power": 50 }
      ],
      "next": { "default": null }
    }
  ],
  "ai": { "range_min": 1.5, "range_max": 5.0, "weight": 10, "use_when": ["target_in_range"], "branch_weights": { "remate_caida": 55, "remate_embestida": 45 } },
  "hint": { "dodge": "roll_late", "text": "Tras el segundo golpe mirá el suelo: círculo = caída (saltá o salí), línea = embestida (al costado)." }
}
```
Cada remate tiene aviso propio (círculo verde vs línea naranja) para que el defensor reaccione a la elección, no
la adivine. El remate imbloqueable tiene 30 ticks de anticipación (≥ 18). En el HUD, el botón «Embestida» aparece
junto al de la habilidad solo entre los ticks 32 y 66 del segundo golpe (según el estado de la sim).

---

## 13. Estado actual vs esquema objetivo

### 13.1 Dónde vive hoy

- **Datos**: `data/abilities/catalog.json`. Cada una de las 45 tiene el paso del esquema y un objeto `source`
  con los tiempos en segundos que compila la sim. `BossAbilities` solo lee ese archivo (nombres, costes, códice, HUD).
  Hoja Escarlata y Elden siguen en sus catálogos. La copia vieja de las 45 está en `docs/backup/habilidades_ronda46/`.
- **Compilación a enteros**: `SimAbilities.compile()` lee `source` y `SimSteps.wrap` pone el tipo en pasos.
  `SimParams.bake` arma `p["boss"]` con `SimParams.tk()` (0,4 s = 25 ticks, no 24).
- **Ejecución**: `SimAbilities.update()` solo despacha `T_STEPS` (`SimSteps.tick`) y `T_CATALOG` (`SimCatalog`).
  El daño y el aturdimiento siguen en `FightSim._take_hit` / `_add_stun_force`.
- **Presets**: `scripts/data/champion_catalog.gd`, campo `boss` (3 ids por campeón: Vael, Lyra, Gorath, Nysera, Draven).
- **IA**: `net/sim/sim_ai.gd` (lógica por id/tipo, en float, solo offline).
- **Eventos**: `SimEvents` (contadores `AB_STARTS`, `AB_HITS`, `AB_INTR`… → claves `frame:kind:player`) + `SimFx`;
  efectos de habilidad en `SimAbilityFx` (solo lee estado).

### 13.2 Ids actuales (45)

| id | nombre | tipo actual | costo | imbloq. | `cd` en datos (s; la sim no lo usa) |
|---|---|---|---|---|---|
| `estocada` | Estocada de jefe | propio | 30 aguante | sí | — |
| `carga_area` | Carga en área | propio | 35 maná | no | — |
| `rafaga` | Ráfaga espectral | propio (proyectil) | 10 maná por tajo | no | — |
| `escudo_mana` | Escudo de maná | propio | 25 maná | — | — |
| `combo_falso` | Combo de la pausa falsa | propio (multi-pulsación) | 38 aguante repartido por golpe | no | — |
| `salto_caida` | Salto con caída | propio | 15 vida | no | — |
| `tajo_retardado` | Tajo Retardado | timeline | 24 aguante | sí | 6 |
| `presa_verdugo` | Presa del Verdugo | timeline (agarre) | 28 aguante | sí | 9 |
| `giro_martillo` | Giro Devastador | timeline | 30 aguante | sí | 10 |
| `danza_cisne` | Danza del Cisne | timeline | 40 aguante | no (un parry la corta) | 14 |
| `paso_espectral` | Paso Espectral | timeline (desaparece) | 25 maná | sí | 10 |
| `onda_rastrera` | Onda Rastrera | wave | 24 aguante | no | 7 |
| `rayos_trazadores` | Rayos Trazadores | rain / track | 25 maná | no | 11 |
| `lluvia_meteoros` | Lluvia de Meteoros | rain / scatter (RNG de la sim) | 35 maná | no | 18 |
| `aliento_dragon` | Aliento de Dragón | breath | 30 maná | no | 14 |
| `furia_fase` | Furia de Fase | rage | 20 vida | — | 30 |
| `postura_contra` | Postura de Contragolpe | counter | 22 aguante | — | 8 |
| `embate_sismico` | Embate Sísmico | wave (anillo de 8) | 18 vida | no | 12 |
| `lanza_celeste` | Lanza Celeste | rain / track | 30 maná | sí | 12 |

Lote 2 (ronda 46, 26 ids; mismos ejecutores; detalle de costos en `docs/design.md`):

| tipo actual | ids (imbloqueables en **negrita**) |
|---|---|
| timeline (golpes) | **`cuerno_embiste`**, `tajo_cruzado`, `zarpazo_sangre`, `barrido_cola`, **`daga_sagrada`**, **`estocada_negra`**, **`flor_umbral`**, **`giro_noble`**, **`danza_triple`**, **`alas_picado`** |
| timeline (agarre) | **`presa_fauces`** |
| wave | `garra_suelo`, `vendaval_hacha`, `anillo_fuego`, `pisoton` |
| rain | `lluvia_lanzas`, **`flecha_grave`**, `lluvia_sangre`, `columnas_rayo` |
| rafaga (tajo que persigue, se puede repetir pagando otra vez) | `saeta_oscura`, `orbe_lunar` |
| breath | `aliento_rayo`, `aliento_escarcha`, `chorro_lava` |
| rage | `grito_guerra` |
| counter | `guardia_reflejo` |

Todas las ampliadas traen `cd` en segundos, que la sim no usa.

### 13.3 Mapeo campo a campo

| Hoy (código) | Esquema objetivo |
|---|---|
| `windup`, `hits[i][0]`, `recovery`… en **segundos** → `tk()` | `windup_ticks`, `active_ticks`, `recovery_ticks` en **ticks** |
| `dmg` = multiplicador del daño fuerte (o ligero si `light`) del arma; × magia si `magic` | `damage_per_hit` absoluto + `damage_scaling` |
| `hits = [[t, mult, fuerza, arremetida], …]` en un único «timeline» | un `step` (o un hitbox con `from/to`) por golpe |
| `force` / `hits[i][2]` + Fuerza + arma (o magia × 0,1) | `stun_power` + `stun_scaling` |
| `resist` (robustez × (1 + resist); ≥ 99 = inmune) | `armor` `super` (`poise_bonus_pct`) / `hyper` |
| `unblockable` / `kind: "jefe"` → golpe tipo 3 (sin bloqueo **ni parry**, perforante) para toda la habilidad | `blockable` / `parryable` **por hitbox** |
| `cost_type` + `cost` (un solo recurso) | `cost{stamina, mana, health}` combinable |
| `track` (°/s constante); estocada: `home_time` / `home_deg` | `tracking{deg_per_sec, lock_at_tick, post_lock_deg_per_sec}` |
| `tele_txt` / `tele` + `color`; factor `TELE_ONLINE` ×1,12 sobre los tiempos | `telegraph{id único, style, sound, ground_marker}`. Si se mantiene el ×1,12, se aplica una sola vez en `bake` sobre `windup_ticks`; el autor no lo pre-aplica |
| `type: wave / rain / breath / rafaga` | `spawns[]`: `ground_wave` / `ground_mark` / `beam` / `projectile` |
| `slam_on_last`, `slam_always` (el área del último golpe sale aunque el cuerpo no conecte), `pillar` (columna visual) | `spawns[]` del paso final (sin condición = «siempre»; con `on: hit` = solo si conecta) + `telegraph.style: sky_column` |
| `grab`, `abort_on_miss`, `miss_extra` | `category: grab` + `next.on_whiff` → paso de fallo |
| `vanish`, `blink_dist` | `movement.type: teleport_behind` + `self_invuln` |
| `hit_iframes` (Danza: invulnerable 9 ticks en cada golpe) | `self_invuln` por paso |
| `parry_cancel` = `id == "danza_cisne"` (cableado) | `interruptible_by: ["parry"]` + `parryable` |
| `combo_falso`: volver a pulsar = siguiente golpe; `IN_BOSS_VAR` = remate en estocada | `cancel_into{trigger: skill}` + `branch` (`skill` / `alt`) |
| `champion.boss` (3 ids) + `P.boss_n = 2` (3.ª ranura bloqueada hasta la Fase II) | `presets[]` + `unlock.phase` |
| Eventos genéricos `ability` / `ability_hit` / `ability_interrupt` con `code` | `events[]` con id estable por paso |

### 13.4 Decisiones (mandan sobre el esquema de arriba)

1. **Recarga.** Solo la global de 85 ticks. El `cd` no se usa. La ráfaga se encadena y saltea la global. Más adelante: `max(global, propia)`.
2. **Interrupción.** `interruptible_by` vacío = no se corta (solo se esquiva). Cada habilidad declara lo que la corta. La base ya no es «cualquier aturdimiento». La Danza del Cisne lo declara (`parry`, `stun_lvl2`, `knockdown`); no hay un `if id == danza_cisne` en el motor nuevo.
3. **Inmunidad total** en los i-frames de la Danza, el Paso Espectral, la Fase II y el escudo de maná. La Estocada se migra como hoy (inmunidad en la carga y la embestida) y queda pendiente de balance.
4. **Derribo:** daño ×0,85 e inmune al aturdimiento. No es invulnerable.
5. **Costo de vida:** se rechaza el uso si la vida quedaría en 0. Al pagar, se recorta a 1.
6. **Daño:** `damage_scaling` `weapon_heavy` o `weapon_light`. `damage_per_hit` es el multiplicador del arma. Lo mágico además × magia/100.
7. **Imbloqueable = sin parry** (golpe tipo 3). Se mantiene.
8. **Cuándo se puede usar:** `SimAbilities.can_use` (suelo, sin montar, sin frasco, sin agotamiento, espada salvo el escudo). Se mantiene.
9. **Ondas:** `knockback_mps` por defecto 6.
10. **Remate alternativo.** El bit 21 (`IN_BOSS_VAR`, acción `boss_variation`, tecla `M`) es el `alt` de la
    ventana abierta: la pausa falsa (remate en estocada), una rama de Hoja y, si el motor de pasos trae `branch`,
    esa rama. `alt2` no tiene bit (el 31 no se envía). El protocolo es 11. El 10 fijó ese significado del bit 21;
    el 11 deja el motor encendido y no hay camino sin envolver. El botón del HUD
    se muestra solo mientras `SimAbilities.alt_window` es verdad; `SimView` vuelca ese flag y la etiqueta
    (`Estocada`, o el `label` de la opción). La vista no decide la ventana.
11. **Desfases de la tabla de las 6 base** (`docs/design.md`): la tabla dice Ráfaga 30 maná / 3 tajos y el código
    10 maná / 1 tajo por pulsación; la tabla dice Carga en área 1,8 s / 4,5 m y el código 2,2 s / 7,5 m. Manda el código.
12. **IA**: decide en float con lógica específica por id; no hay bloque `ai` en los datos.
13. **Presets**: hoy siempre son 3 ids por campeón y la 3.ª se bloquea por ranura (`boss_n`), no por habilidad.

### 13.5 Hoja Escarlata (ronda 48)

Las 45 están en `data/abilities/catalog.json`. `BossAbilities` las lee de ahí. `docs/hoja_escarlata_catalog.json` se hornea con `AbilityCatalog.load_file` y lo ejecuta `SimCatalog` (`T_CATALOG`), reusando los campos `AB_*`. Las 45 de `SimSteps.IDS` salen siempre por `SimSteps`: `source` alimenta el programa numérico y el horneado aporta `interruptible_by` y los eventos. `ab_engine` queda en los params y por defecto es 1; ya no elige el camino. El protocolo es 11: el 9 metió `ab_engine` en los params, el 10 generaliza el bit 21 como `alt` y el 11 enciende el motor.

Adaptaciones respecto del esquema:

- La recarga del motor de pasos es la global de 85 ticks (`tk(1,4)`). El `cooldown` propio no se usa; más adelante será `max(global, propia)`. Hoja (`FL_CATALOG`) sí hace `max(GLOBAL_CD, cooldown)`. El esquema anota 84.
- La zona de Floración son anillos sucesivos (marcas de suelo), no un charco. El sangrado suma a la acumulación que ya existe.
- `self_invuln` en modo `stun_immune` no usa `AB_IMM` (eso contaría el golpe como esquivado): no aturde y el daño entra × `dmg_taken_pct`.
- Hiperarmadura: no acumula robustez. Superarmadura: suma robustez con la fórmula que ya existe.
- Quien no tiene regla de Fase II puede usar una habilidad de `unlock.phase` 2. El campeón no, hasta que entra en Fase II.
- El daño mágico entra por la columna de golpe físico. No hay una columna de elemento.
- `on_interrupt.recovery_ticks` no se suma: el castigo es el aturdimiento o el parry que ya aplica la sim.
- `IN_BOSS_VAR` (bit 21) es el `alt` de la rama. No hay bit para `alt2`.

---

## 14. Checklist de diseño (justicia y legibilidad online, 50–150 ms)

A 150 ms de RTT el rival ve tu acción ~4–5 ticks tarde, y las correcciones por rollback llegan a ~6 ticks.

- [ ] El aviso es **único** (forma + color + sonido) y aparece en el tick 0 del paso de entrada.
- [ ] Imbloqueable ⇒ windup ≥ 18 (recomendado ≥ 30) y aviso visible; agarre ⇒ windup ≥ 24.
- [ ] Hay una **respuesta clara** (rodar a tiempo, apartarse, saltar, bloquear, parry) y el `hint` la nombra.
- [ ] `lock_at_tick` deja ≥ 6 ticks entre el bloqueo del tracking y el primer tick activo (si no, la latencia la vuelve imposible).
- [ ] Recuperación final ≥ 18 (mejor 30–54) y castigable; los fallos (`on_whiff`) recuperan más que los aciertos.
- [ ] Daño por golpe en escala: un golpe no quita más de ~35 % de una vida típica (≈ 35–45).
- [ ] `stun_power` acorde: ningún golpe aturde solo (regla del 0,95); cadenas rápidas no pasan del nivel 2 salvo el remate.
- [ ] Control forzado (pull/root) ≤ 0,3–0,4 s, con tope de distancia y rompible.
- [ ] Movimiento con tope de distancia y `stop_at_m` para no atravesar al rival.
- [ ] Nada lee entradas del rival; azar solo del RNG de la sim; todo en ticks enteros.
- [ ] Eventos visuales con id; ninguno se dispara desde la vista.
- [ ] Peor caso de piscinas respetado (≤ 6 proyectiles, ≤ 8 peligros).
- [ ] Si hay `branch`: cada opción con aviso distinguible y el botón `alt` con icono y etiqueta; el HUD lo muestra desde el estado de la sim.
- [ ] Costo y recarga proporcionados al riesgo (las de vida, para efectos fuertes).
- [ ] Nombre propio, sin referencias a otras franquicias.

---

## 15. Errores comunes

- Escribir tiempos en segundos (`"windup": 1.25`) en vez de ticks (`"windup_ticks": 75`).
- Poner el daño total del combo en un campo («daño 60») en vez de `damage_per_hit` por caja.
- Usar `t_step` en `hitboxes[].from_tick` (es `t_active`) o al revés.
- Agregar `dodge_window` / `iframe_required_ms` como datos: no existen; usá `hint`.
- Reusar un `telegraph.id`, o el mismo color/sonido de otra habilidad del preset.
- `next` apuntando a un paso inexistente o con un typo.
- Paso terminal con `recovery_ticks` < 18 («no se puede castigar»).
- Imbloqueable con windup corto o sin aviso.
- `pull` largo (1 s) o sin `max_distance_m`.
- Movimiento sin `max_distance_m` (tras un rollback cruza media arena).
- `self_invuln.mode: "total"` fuera del escudo de maná.
- Usar azar propio para repartir marcas en vez de `mode: scatter` (RNG de la sim).
- Creer que hacen falta exactamente 3 pasos o 3 habilidades: los pasos son 1..N; las habilidades equipadas, **hasta** 3.
- `branch` con opción `alt` sin `hud_icon`/`label`, con ventana fuera del paso, o con dos opciones del mismo `input`.
- Mecánica que reacciona al botón del rival (curarse al leer el ataque): prohibido.
- Decimales en campos `int` (`"hits": 1.5`).

---

## 16. Cómo pedirle a un modelo una habilidad (plantilla)

Pegá **esta guía completa** y después:

```
Sos diseñador de combate de un luchador de arena 1v1 de fantasía medieval con sim determinista a 60 Hz y
rollback. Usá EXCLUSIVAMENTE el esquema de docs/abilities_guide.md.

Quiero UNA habilidad nueva:
- Concepto: <qué hace, fantasía, 1-2 frases>
- Categoría: <melee | ranged | magic | grab | buff | summon | zone | counter | movement>
- Recurso: <stamina | mana | health> aprox. <n>
- Rol en el preset: <abridora | castigo | control de zona | remate de Fase II>
- Respuesta esperada del defensor: <rodar tarde | apartarse | saltar | bloquear | parry>
- Pasos: <cantidad aproximada o "libre">; ¿remate a elección (branch)? <sí/no, cuántas opciones>
- Restricciones extra: <p. ej. "sin imbloqueables", "máx. 2 proyectiles">

Entregá:
1. El JSON de la habilidad (un solo objeto Ability), válido, con todos los campos obligatorios.
2. Una tabla por paso: windup/active/recovery en ticks y ms, daño por golpe y stun_power de cada hitbox.
3. La ventana de esquiva que EMERGE (lock_at_tick → primer tick activo) y cómo se contrarresta.
4. Las reglas V01–V19 marcadas como cumplidas (o explicá por qué no aplican).
Números en la escala real (vida 80–130, fuerte de arma 18–40, robustez 30–80). Nombre original en español,
sin nombres de otras franquicias. No inventes campos fuera del esquema.
```

Antes de aceptar lo que devuelva: pasalo por el validador (§17), la checklist (§14) y los errores comunes (§15).

---

## 17. Cómo validar un catálogo

Cargador, validador y horneado: `net/sim/ability_catalog.gd` (`AbilityCatalog`). El campo `source` de las 45 se acepta y no entra al horneado. Hoja Escarlata sí ejecuta el horneado en `SimCatalog` (§13.5). El motor de pasos ejecuta el programa que `SimAbilities.compile` arma desde `source`. El horneado aporta la máscara y los eventos.

```bash
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/catalog.example.json
# --strict: los avisos también fallan · --quiet: solo el resumen
```
- Imprime `ERROR [regla] ruta: mensaje` y `AVISO [regla] ruta: mensaje` (rutas tipo
  `abilities[3].steps[1].hitboxes[0].shape.radius_m`) y un resumen con el hash del horneado.
- Código de salida: `0` sin errores, `1` con errores (o avisos con `--strict`), `2` sin argumento.
- Reglas: `V01`–`V19` (§11), `SCHEMA` (tipos, enums, obligatorios, rangos), `PARSE` (JSON/archivo).
  Avisos: `ASSET` (icono/vfx/sfx inexistente → se usa el genérico), `UNKNOWN_FIELD`, `UNKNOWN_TAG`, `HINT`,
  `FAIRNESS`, `V15`.
- Desde código: `AbilityCatalog.load_file(ruta, opts)` / `load_text` / `load_data` →
  `{ok, errors, warnings, baked, hash}`. `opts.known_vfx` / `opts.known_sfx` (listas) activan el chequeo de ids
  de efectos. `baked` es de solo lectura, en enteros con las convenciones de `SimParams` (milésimas, µm, µm/tick,
  ‰, ticks, rumbos 0..255, mili-rumbos/tick, coseno del medio arco ×4096); ids → índices, `-1` = fin.
  `AbilityCatalog.checksum(baked)` = FNV-1a (mismo input → mismo hash).
- Catálogo de ejemplo con las 5 habilidades de §12: `data/abilities/catalog.example.json` (valida sin avisos).
- Pruebas: `tests/test_ability_catalog.gd`.
