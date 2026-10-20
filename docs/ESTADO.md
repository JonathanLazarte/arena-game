# Estado vivo

Mapa corto de lo que el juego carga hoy. El historial por rondas sigue en `README.md`. El esquema de una habilidad nueva está en `docs/abilities_guide.md`. El handoff largo está en `docs/HANDOFF.md`.

Godot 4.7.2. Protocolo **12**. No lo subas si no cambia el layout del estado, los bits de entrada, los params o los mensajes. No subas `DEBUG_GRANT`. No armes un APK salvo que se pida.

## Catálogos que sí carga la partida

Todos están en `data/abilities/`. Un JSON de `docs/` no entra a la sim.

| Archivo | Quién lo abre | Qué ejecuta |
|---|---|---|
| `catalog.json` | `BossAbilities` y `SimSteps` | Las 45. El reloj es el campo `source`. |
| `hoja_escarlata_catalog.json` | `HojaCatalog` | Trazos, Garza, Caída, Floración. `SimCatalog`. |
| `bosses_elden_catalog.json` | `EldenCatalog` | Radagon, Malenia y Godfrey (9 habilidades, 3 presets). `SimCatalog`. |
| `artorias_caballero_umbral.json` | `ExtraCatalog` | Caballero Umbral (9). `SimCatalog`. |
| `golpe_fisura_skill.json` | `ExtraCatalog` | Golpe de Fisura. `SimCatalog`. |

`catalog.example.json` es el fixture del validador. No es una habilidad del juego.

`spameable: true` (Ráfaga, Saeta Oscura, Orbe Lunar) se salta la recarga global al repetirse. Se hornea en el mismo bit que `global_cd_on_repeat` (invertido). El protocolo no cambia. `BossAbilities.spameable` lo expone.

`familias` es la familia de animación, no el id del arma. Las 45 la declaran. Vacío no filtra: Hoja, Elden, Artorias y Fisura siguen vacías. `cualquiera` va sola. El loadout filtra por compatibilidad de familia (`BossAbilities.is_family_compatible` y `GameState.toggle_boss_ability`/`set_boss_loadout`), permitiendo equipar libremente solo en modo admin (`AdminMode.enabled`).

La interfaz (UI) cuenta con un rediseño visual de fantasía oscura inspirado en Elden Ring / FromSoftware: paneles de piedra obsidiana translúcidos, filos finos de latón envejecido y oro rúnico (`UIKit.ORANGE`, `UIKit.YELLOW`), chevrons de selección y barras de HUD (vida en carmesí profundo `UIKit.RED`, concentración/eikon en azul espiritual `UIKit.CYAN`, y resistencia en verde savia `UIKit.GREEN`).

`docs/catalogos_bosses/` ya no tiene JSON. Radagon, Malenia y Godfrey tenían una copia partida ahí; coincidía con `bosses_elden_catalog.json` y nadie la cargaba. Editar esa copia no cambiaba la partida. No la recrees.

`docs/backup/habilidades_ronda46/` es un respaldo. Tiene `.gdignore`. No declares `class_name` ahí: Godot usaría el respaldo en vez del script vivo.

## Reloj de las 45

`SimSteps.wrap` deja `graph` en 0. El golpe usa los segundos de `source`, compilados por `SimAbilities` (`TELE_ONLINE` 1.12 en casi todas; la pausa falsa, la carga, el salto y el escudo no). El `windup_ticks` del paso horneado **no** es el reloj. Sí se leen `interruptible_by` y los eventos.

Hoja, Elden, Artorias y Fisura no tienen `source`. Ahí el paso (windup, activo, recuperación) es el reloj, y lo corre `SimCatalog`.

La entrada de una rama es un flanco (`inp & ~prev`). Sostener el botón todo el paso no entra. El tick en que el paso empieza tiene `AB_T` en 0 y el latch lo descarta.

## Piso de esquiva

`docs/abilities_guide.md` §11.2, decisión 18. Ya está en los catálogos de jefe. `tests/test_dodge_floor.gd` lo vigila.

- Tajo normal: 33 ticks (0,55 s). La referencia es la pausa falsa.
- Pesado, o línea que viaja: 45. Salto que es el golpe: 60. Clavado: 48. Línea quieta: al menos 60.
- El tracking se traba al menos 18 ticks antes del activo (`SimAbilities.DODGE_LOCK`). En el catálogo se escribe `windup − 24`.
- Entre dos golpes de una cadena hay al menos 33 ticks (45 si el siguiente es pesado).
- Básicos y artes no entran. Tampoco escudo, furia, grito, postura ni guardia.

Volteretas Cortantes saltan con `impulse` (gravedad, no una altura sostenida). Alrededor de un segundo en el aire, el tajo es el aterrizaje, sale por el suelo y el segundo salto pega. No vuelvas a un conteo exacto de ticks en el aire.

Golpe de Fisura: el salto puede acercarse. El martillazo tiene `max_distance_m` 0,3. Un slam con tope 0 se desliza hasta el punto fijado. La línea quieta sigue en 60 ticks, 28 m × 2,1 m, y `REACH_PM` no la alarga.

`REACH_PM` (+40 %) sí alarga tajos de jefe, la distancia máxima de sus saltos, las ondas que viajan y la vida de sus proyectiles. También el tope del martillazo, así que 0,3 m se mide cerca de 0,39 m.

Las ventanas de hitbox son relativas al activo. Si alargás un windup, no las corras. Sí se corren movimiento, eventos y ramas cuyo tick era mayor o igual que el windup viejo.

## Export

Los JSON se leen con `FileAccess`, no son recursos importados. Los tres presets de `export_presets.cfg` incluyen `data/abilities/*.json`. Si agregás un catálogo en otra carpeta, el APK no lo va a tener hasta que entre en ese filtro.

## Comprobar

```bash
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/catalog.json
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/hoja_escarlata_catalog.json
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/bosses_elden_catalog.json
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/artorias_caballero_umbral.json
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/golpe_fisura_skill.json
godot --headless --path . -s res://tests/test_dodge_floor.gd
godot --headless --path . -s res://tests/test_artorias.gd
godot --headless --path . -s res://tests/test_hoja_escarlata.gd
godot --headless --path . -s res://tests/test_elden_bosses.gd
godot --headless --path . -s res://tests/test_step_engine.gd
```

## Eikons Scripteables (Gambits FFXII)

Los eikons compañeros (o monturas sin jinete) ejecutan un sistema de **Gambits tácticos** de 3 ranuras prioritarias (`EikonGambits`, configurables en el lobby y persistentes en `GameState`).
- Cada ranura evalúa: `[Condición] ➔ [Habilidad]`.
- Condiciones: `always`, `owner_hp_lt_50`, `owner_hp_lt_30`, `enemy_hp_lt_35`, `enemy_charging`, `enemy_dist_gt_8m`, `enemy_dist_lt_3m`.
- Habilidades: `basic` (ataque estándar), `special` (habilidad icónica del eikon), `shield` (escudo protector al dueño), `disrupt` (choque que interrumpe al rival), `leap` (embestida de cierre).
- En la simulación (`SimMagic`), los cooldowns de las ranuras se empaquetan en lanes de 16 bits dentro de `EK_SPC`, preservando el layout de estado y `GAME_PROTO` = 12.

## Lo que no está empezado

Después de este piso quedan compañeros no eikónicos y duelos de campeón en escalera. No arranques esa fase sin que se pida. La estocada cuenta con súper-armadura en la carga (recibe daño, interrumpible por aturdimiento nivel 2 o derribo) e invulnerabilidad en la embestida. La recarga propia corre como `max(global, propia)` respetando `spameable`.

## Actualizaciones Recientes (Eikons Gambits + Combate + Modelos)
- **Eikons Scripteables (FFXII Gambits)**: Implementado sistema de 3 ranuras prioritarias de condiciones y acciones autónomas (`scripts/data/eikon_gambits.gd`, `net/sim/sim_magic.gd`), configurable desde el Lobby e integrado de forma determinista en simulación multijugador.
- **Artes de Armas Reincorporadas**: Se mantienen diferenciadas de las habilidades (skills de jefes/personajes con saltos y zancadas) por carecer de desplazamiento propio (ataques concentrados en el sitio, sin vectores de carrera).
- **Animación de Rodar (Roll Real)**: Corregido el roll para que siempre ejecute la voltereta completa (`roll_f` / `mx/roll_f`) alineando el modelo a la dirección de esquiva (`dash_dir`), eliminando los dashes/saltos estáticos de KayKit en todas las direcciones y durante lock-on.
- **Cámara Aún Más Cercana**: Ajustadas distancias orbitales (`DIST = 4.6`, `LOCK_DIST = 4.2`, altura de pivote a 1.6 m, hombro a 1.3 m) para una vista de combate íntima y de acción Souls/ARPG.
- **HUD y Alternancia de Objetivo**: Reemplazado el botón «Objetivo» por un botón compacto con flecha `⇄` ubicado al lado de «Fijar», visible únicamente cuando hay más de un rival en la arena.
- **Indicador de Combo Fragmentado**: La circunferencia fragmentada de la habilidad se actualiza inmediatamente al primer toque (e.g. al pulsar una skill de 4 fases pasa a 75%, luego 50%, etc.), dibujando los fragmentos restantes de forma clara.
- **4 Slots y Botones de Boss Skills**: Ampliado a 4 ranuras equipables (`BossAbilities.MAX_EQUIPPED = 4`) con 4 botones dedicados en fila horizontal en el HUD para activar directamente cualquiera de las 4 habilidades. Se eliminaron por completo las flechas laterales («◀» y «▶») del HUD de combate.
- **Menú de Habilidades de Jefe**: Ahora muestra las 4 ranuras equipadas en la cabecera del lobby. Las habilidades de jefe (`origin == "boss"`) son universales y se equipan en cualquier personaje sin bloqueos de familia de arma; al pulsar una nueva con 4 ya equipadas, reemplaza la última de forma inmediata y guarda con `save_loadout()`.
- **Ajuste de Cercanía de Cámara**: Se añadieron 3 niveles de distancia en Ajustes (`cerca`, `medio`, `alejado`):
  - *Cerca* (por defecto): libre a 3.6 m, lock a 3.2 m, pivote a 1.5 m (aún más íntima y cercana al personaje).
  - *Medio*: libre a 4.6 m, lock a 4.2 m, pivote a 1.6 m.
  - *Alejado*: libre a 6.2 m, lock a 5.6 m, pivote a 1.8 m.
  Disponible tanto en la pestaña Ajustes del Lobby como en el menú de pausa durante el combate.
- **HUD Limpio**: Oculto permanentemente el botón «chispa» / hechizo en el HUD de combate móvil.
- **Modelos Humanoides**: Sustituidos todos los modelos chibi KayKit por modelos de prueba Mixamo/realistas (`assets/test_models/`) en los personajes principales (`caballero`, `paladin`, `berserker`, `asesino`, `arquero`).
