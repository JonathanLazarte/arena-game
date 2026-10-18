# Prompt: motor genérico de pasos + migración de las 45 habilidades (para Grok Build)

> Prompt listo para pegar en Grok Build (modelo local). No es documentación de diseño: las reglas duraderas
> siguen en `docs/design.md` y el esquema en `docs/abilities_guide.md`.
>
> Hoja Escarlata ya corre (ronda 48): `data/abilities/hoja_escarlata_catalog.json` se hornea con `AbilityCatalog` y lo
> ejecuta `SimCatalog` reusando `AB_*`, sin campos nuevos y sin subir el protocolo. No la reescribas ni la
> migres otra vez. Este prompt es para las 45 anteriores.

---

Vas a trabajar en el repo `arena-game` (Godot 4.7.2, GDScript), luchador de arena 1v1 de fantasía medieval con
sim determinista a 60 Hz y netcode con rollback. Rama `master`. Antes de tocar nada hacé `git pull --rebase` y
leé, en este orden: `docs/HANDOFF.md` (sobre todo §3 protocolo y §4 «la regla clave»), `docs/abilities_guide.md`
(esquema completo, §13 «Estado actual vs esquema objetivo», §17 validador), `docs/netcode.md`, `docs/design.md`,
`net/sim/fight_sim.gd`, `net/sim/sim_abilities.gd`, `net/sim/sim_params.gd`, `net/sim/ability_catalog.gd`,
`scripts/data/boss_abilities.gd`, `scripts/combat/boss_abilities_ext.gd`, `net/sim/sim_events.gd`, `net/sim/sim_fx.gd`.

## Objetivo

Construir el **motor genérico de pasos** dentro de la sim, que ejecute habilidades del catálogo horneado por
`AbilityCatalog` (`baked`: enteros, ids → índices, `-1` = fin), y **migrar las 45 habilidades actuales** a ese
catálogo en etapas, sin romper el juego en ningún momento.

## Reglas que no se negocian

1. **Determinismo**: dentro de la sim solo enteros / punto fijo (las convenciones de `SimParams`: milésimas, µm,
   µm/tick, ‰, ticks, rumbos 0..255, mili-rumbos/tick, coseno ×`FxMath.ONE`). Nada de `float`, `randf`, reloj,
   `delta`, nodos ni física del árbol. Azar solo con `FightSim.rng_next`. Los decimales del JSON se convierten una
   sola vez al cargar (`AbilityCatalog` → `SimParams.bake`).
2. **Estado rollback-safe**: todo lo que el motor necesite recordar entre ticks (paso actual, `t_step`, resultado
   del paso, impactos por hitbox, ramas elegidas, búfer de pulsación, bucles, recarga propia por habilidad, fuerzas
   y estados aplicados) vive en el `PackedInt64Array` de `FightSim` (campos nuevos en el layout, `SIZE` recalculado),
   así entra en save/load (`duplicate()`) y en `FightSim.checksum`. Nada de estado en diccionarios aparte.
3. **Eventos con id estable**: los efectos se derivan del estado (habilidad, paso, `t_step`) con claves del estilo
   `frame:ab_ev:<jugador>:<ability_code>:<step>:<event_id>`, compatibles con `SimEvents` + `SimFx` (retención online).
   Un rollback no debe duplicar ni dejar efectos fantasma.
4. **Remate alternativo**: la opción `alt` de `branch` usa el bit de entrada **21** (`IN_BOSS_VAR`, acción
   `boss_variation`, tecla `M`, botón táctil), hoy cableado solo para `combo_falso`. Generalizarlo cambia la
   semántica de entradas: **subí el protocolo** (`GAME_PROTO` en `net/online/net_link.gd`, `server/src/index.ts`,
   `server/test/relay.test.ts`, `tests/test_net_reconnect.gd` y docs: lista completa en `docs/HANDOFF.md` §3). El
   bit 31 no se envía; `alt2` no tiene bit.
5. **HUD desde el estado de la sim**: el botón alternativo (icono y texto de la opción) se muestra solo mientras la
   ventana de `branch` está abierta **según el estado de la sim** volcado por `SimView`. Nunca decidas visibilidad
   solo en la vista (eso causó el «parpadeo» del ciclo ▶ que se arregló en la fase 9).
6. **La jugabilidad vive solo en `net/sim`** (HANDOFF §4). `Fighter`, `Mount`, `Eikon` y la arena solo dibujan.
7. **Checksums**: en la etapa 1 el camino viejo y el nuevo deben dar **checksums idénticos** para las habilidades
   migradas. Si una diferencia es inevitable, frená y explicala antes de seguir.
8. **Nombres propios**: nada de nombres ni referencias de FromSoftware ni de otras franquicias.
9. `docs/design.md` = solo datos/reglas duraderas, sin prompts ni bitácora (el historial va a README/netcode).
   No toques `DEBUG_GRANT`. No hace falta compilar APK ni builds.
10. **Commit + push por etapa** (y checkpoints chicos dentro de cada etapa), con `git pull --rebase` antes de
    pushear: el usuario también pushea desde su PC.

## Divergencias conocidas: PREGUNTAME antes de cambiar la semántica

Estas diferencias entre el código actual y el esquema están en `docs/abilities_guide.md` §13.4. **No las cambies
por tu cuenta**: en la etapa 1 replicá el comportamiento actual tal cual y, antes de la etapa 2, preguntame una por
una qué querés hacer (mantener lo actual, adoptar el esquema, o una variante), con tu recomendación:

1. **Recarga propia por habilidad**: los `cd` de las ampliadas no se usan en la sim (solo la global de 85 ticks;
   el esquema dice 84) y offline está apagado. La familia ráfaga saltea la global al repetirse.
2. **Interrupciones**: hoy cualquier nivel de aturdimiento (incluso el tambaleo) corta la habilidad, salvo
   `AB_IMM` y la estocada (nunca se corta). El esquema tiene `interruptible_by` por habilidad. El parry que corta la
   Danza del Cisne está cableado por id.
3. **Semántica de `INVULN`**: hoy es inmunidad total (cuenta como esquiva) en la estocada, el Paso Espectral, los
   i-frames de la Danza y la Fase II. El esquema: «invulnerable» = inmune al aturdimiento + daño ×0,85, total solo
   en el escudo de maná.
4. **Derribo**: hoy inmune al aturdimiento con daño ×0,85 (`GETUP_DMG_PM`), no invulnerable. El esquema lo quiere
   invulnerable hasta levantarse.
5. **Costo de vida**: hoy se **rechaza** el uso si dejaría la vida en 0 (y al pagar se recorta a 1). El esquema
   solo pide recortar a 1.
6. **Daño como multiplicador del arma**: hoy el daño escala con el fuerte/ligero del arma equipada (y magia). El
   esquema usa `damage_per_hit` absoluto + `damage_scaling`. Para migrar sin cambiar números vas a necesitar un
   modo de escalado «relativo al arma» (proponé el campo y preguntame antes de agregarlo al esquema).
También: imbloqueable hoy implica sin parry (golpe tipo 3, perforante); y `usable_while` está cableado en
`SimAbilities.can_use` (suelo, sin montar, sin frasco, con espada salvo el escudo).

## Etapas

### Etapa 1 — motor detrás de un flag + pocas habilidades simples
- `net/sim/sim_steps.gd` (o el nombre que encaje): ejecuta windup/activo/recuperación, hitboxes con `from/to`
  relativos al activo, `hits`/intervalo, tracking con `lock_at_tick`, movimiento con tope, armadura, `next` por
  resultado (`hit`/`blocked`/`whiff`), `cancel_into`, `branch` (primera pulsación gana, búfer, empate por orden de
  opciones), eventos, recarga global, costos (con la regla de vida ACTUAL), interrupciones (con la regla ACTUAL).
- Flag en params (p. ej. `p["ab_engine"] = 0|1`, incluido en `params_checksum`), apagado por defecto.
- Conversor de las definiciones actuales (`BossAbilities`/`BossAbilitiesExt`) a JSON del esquema o catálogo JSON
  escrito a mano en `data/abilities/catalog.json`, validado con
  `godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/catalog.json`.
- Migrá **2–4 habilidades simples** (por ejemplo una `timeline` de un golpe como `tajo_retardado` o `estocada_negra`,
  una `wave` como `pisoton` y una `rain` como `flecha_grave`).
- Test nuevo (p. ej. `tests/test_step_engine.gd`): misma partida con entradas guionadas, flag apagado vs encendido →
  **checksums tick a tick idénticos** para esas habilidades; save/load a mitad de habilidad; resim (rollback) da el
  mismo estado; eventos sin duplicados tras rollback.
- Corré la suite completa (con el relay local para `test_net_relay5` y `test_net_matchmaking`) y `test_net_rollback`
  + `test_net_online`. Commit + push.
- **Después de la etapa 1, preguntame por las divergencias** antes de seguir.

### Etapa 2 — migrar el resto por lotes
- Lotes por familia: timelines restantes (incluidos agarres, `vanish`, `hit_iframes`, `slam_on_last`/`slam_always`),
  ondas, lluvias (`scatter` con el RNG de la sim), alientos (`beam`), ráfagas (`projectile`), furias (`buff`),
  contragolpes (`counter`), y al final las 6 base (estocada, carga en área, ráfaga, escudo de maná, combo de la
  pausa falsa con su remate alternativo por `branch` + bit 21, salto con caída).
- En cada lote: catálogo validado, test de equivalencia de checksums (o diferencia aprobada por mí), suite verde,
  commit + push. El remate alternativo genérico (bit 21) entra junto con `combo_falso`, con la subida de protocolo
  y el HUD derivado del estado de la sim.
- Mantené la IA (`net/sim/sim_ai.gd`) funcionando; si pasa a leer el bloque `ai` del catálogo, que siga siendo
  determinista con su propio RNG y sin leer entradas del rival.

### Etapa 3 — sacar los caminos cableados
- Con todo migrado y probado: encendé el motor por defecto, borrá los tipos cableados de `SimAbilities` y las
  definiciones duplicadas, dejá `BossAbilities` solo como fachada de lectura del catálogo (nombres, iconos, códice,
  HUD). Actualizá tests, `docs/abilities_guide.md` §13 (estado actual), `docs/HANDOFF.md`, `docs/netcode.md` y, si
  cambió alguna regla duradera, `docs/design.md`. Commit + push.

## Entrega por etapa
Resumen corto: commits, archivos tocados, resultados de tests (cuántos pasan), cambios de protocolo, y la lista de
decisiones que necesitás de mí.
