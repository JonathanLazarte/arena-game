# Estado vivo

Mapa corto de lo que el juego carga hoy. El historial por rondas sigue en `README.md`. El esquema de una habilidad nueva está en `docs/abilities_guide.md`. El handoff largo está en `docs/HANDOFF.md`.

Godot 4.7.2. Protocolo **11**. No lo subas si no cambia el layout del estado, los bits de entrada, los params o los mensajes. No subas `DEBUG_GRANT`. No armes un APK salvo que se pida.

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

## Lo que no está empezado

Después de este piso quedan magia de eikon, armas únicas, compañeros y duelos de campeón. No arranques esa fase sin que se pida. La estocada sigue con inmunidad total en la carga y la embestida; el balance está pendiente.
