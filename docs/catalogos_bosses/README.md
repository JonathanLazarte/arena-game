# Catálogos de jefes

Esta carpeta ya no tiene JSON. El juego no la carga.

Los nueve de Radagon, Malenia y Godfrey están en un solo archivo, que es el que corre:

`data/abilities/bosses_elden_catalog.json`

Lo abre `EldenCatalog`. Las copias partidas (`radagon_orden_dorada.json`, `malenia_hoja_espiral.json`, `godfrey_senor_telurico.json`) se borraron porque repetían ese archivo y editarlas no cambiaba la partida.

El Caballero Umbral y Golpe de Fisura tampoco viven acá. Están en `data/abilities/artorias_caballero_umbral.json` y `data/abilities/golpe_fisura_skill.json`.

Qué archivo está vivo, y cuál es el reloj de cada uno, está en [`docs/ESTADO.md`](../ESTADO.md).

## Cómo se sienten las ramas

Radagon, `martillo_alba`. El segundo golpe abre la ventana:

- `skill`: `remate_estallido`, descarga pesada.
- `alt`: `remate_barrido`, empuja y abre distancia.

Malenia, `danza_espirales`. Tras la primera ráfaga:

- `skill`: `segunda_rafaga` y luego la caída.
- `alt`: `corte_evasivo`, corta y retrocede.

Godfrey, `pisoton_telurico`. Tras el pisotón:

- `skill`: `hachazo_partidor`.
- `alt`: `rugido_guerra`, pulso en 360°.

La tercera habilidad de cada preset es de Fase II para el campeón.

Validar el archivo que sí usa la sim:

```bash
godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/bosses_elden_catalog.json
```
