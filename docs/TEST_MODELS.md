# Modelos de prueba (rama `test-models`)

**Solo para pruebas privadas. Esta rama NO se fusiona con `master` ni va a ninguna release.**

Los cinco modelos de `assets/test_models/` son de terceros (descargados de internet por el dueño
del repo) y tienen copyright de sus autores o editores. Se aprobaron únicamente para probar en
privado cómo se ven personajes humanoides no KayKit en el juego. No se pueden publicar, subir a
tiendas ni mezclar con `master`. Si alguno se queda en el juego, hay que reemplazarlo por un
modelo propio o con licencia libre.

| id | Nombre en el juego | Archivo |
|---|---|---|
| `test_jane` | Prueba: Oficinista | `test_jane/jane.glb` |
| `test_yoomi` | Prueba: Chica urbana | `test_yoomi/yoomi.glb` |
| `test_mita` | Prueba: Chica de gafas | `test_mita/mita.glb` |
| `test_nightgown` | Prueba: Camisón | `test_nightgown/luna.fbx` |
| `test_knight` | Prueba: Caballero oscuro | `test_knight/knight.glb` |

## Cómo funcionan (solo visual; la simulación no cambia)

- `CharacterDef.retarget_lib` apunta a `<id>_anims.res`, que hornea `tools/bake_test_models.gd`:
  los clips KayKit de `Knight.glb` y la biblioteca Mixamo `mx` (`lib_kaykit.res`) reapuntados al
  esqueleto de cada modelo (delta de orientación global por hueso + corrección de pose A → T).
- `KnightVisual._prepare_retarget` renombra los huesos mapeados a los nombres KayKit (`hips`,
  `upperarm.l`...), añade `handslot.l/r`, ajusta la escala a la altura KayKit y achica las armas
  (`TEST_WEAPON_K`).
- Estadísticas, pasiva y armas: las del Caballero. Se reclutan gratis (`Progression.req`).
- Texturas reducidas a 1024 px como máximo (Android).
- Rehornear tras cambiar un modelo o el mapa de huesos:
  `godot --headless --path . -s res://tools/bake_test_models.gd`
- Prueba: `godot --headless --path . -s res://tests/test_test_models.gd`
