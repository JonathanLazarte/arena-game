# Catálogos de Habilidades Inspirados en Jefes de Elden Ring

Este directorio contiene los catálogos y plantillas de habilidades diseñadas según el esquema oficial y determinista de [`docs/abilities_guide.md`](../abilities_guide.md), tomando como inspiración los movimientos, patrones de castigo y timings de jefes emblemáticos de *Elden Ring*.

---

## 1. Filosofía de Adaptación

1. **Simulación a 60 Hz**: Elden Ring opera a 60 FPS. Cada frame de animación se traduce 1:1 a **ticks** (1 tick = 16,67 ms).
2. **Escala de Vida y Daño**: La vida del juego base es de **80 a 130 PV**. Los golpes infligen entre 6 y 38 puntos de daño según su velocidad y riesgo. Ningún golpe aturde por sí solo (respeto a la regla de robustez poise ≤ 0,95).
3. **Regla V19 (Nombres Propios Originales)**: Nombres originales y evocadores en español, integrados al lore de fantasía de la arena, sin copiar marcas registradas de otras franquicias.
4. **Legibilidad Online y Juego Limpio**:
   - Golpes imbloqueables tienen anticipación (`windup_ticks`) ≥ 18 ticks (idealmente ≥ 30).
   - El tracking hacia el rival se bloquea (`lock_at_tick`) antes de soltar el impacto para dejar una ventana de esquiva real emergente.
   - Pisotones y ondas expansivas usan `ground_only: true` (se esquivan saltando).
   - Los agarres (`grab`) son imbloqueables pero se pueden evadir rodando a tiempo.

---

## 2. Jefes Disponibles y Variaciones de Combo (`branch`)

### 1. Radagon (`radagon_orden_dorada.json`)
* **Preset**: `orden_dorada` («Guardián de la Orden Dorada»)
* **Rol**: Castigador sagrado, retrasos y zonas de choque áureas.
* **Habilidades**:
  1. `martillo_alba`: Dos golpes de martillo. El segundo abre una ventana de bifurcación (`branch`):
     - **Pulsar `skill`** (mismo botón): `remate_estallido` — Descarga pesada imbloqueable con superarmadura que derriba y deja una marca sagrada en el suelo (`ground_mark`).
     - **Pulsar `alt`** (botón contextual / tecla `M`): `remate_barrido` — Barrido rápido que empuja al rival a 9 m/s para resetear la distancia neutra.
  2. `lanza_veredicto`: Proyectil sagrado que se clava en la posición del rival y detona tras 30 ticks de aviso.
  3. `triptico_sagrado` (Fase II): Secuencia icónica de 3 impactos en salto; los dos primeros son ondas en el suelo y el tercero es un aplastamiento aéreo colosal imbloqueable.

### 2. Malenia (`malenia_hoja_espiral.json`)
* **Preset**: `hoja_espiral` («Duelista de la Hoja Espiral»)
* **Rol**: Duelista acrobática de alta presión, movilidad aérea y sangrado.
* **Habilidades**:
  1. `danza_espirales`: Elevación en el aire y primera ráfaga de cortes múltiples en esfera. Abre ventana de bifurcación (`branch`):
     - **Pulsar `skill`**: `segunda_rafaga` — Prosigue la danza en el aire hacia el objetivo y concluye con una caída cortante en área.
     - **Pulsar `alt`**: `corte_evasivo` («Repliegue») — Corta hacia abajo y retrocede 3,6 m con un salto hacia atrás (`retreat`), castigando a quien intente contraatacar bajo sus pies.
  2. `estocada_penetrante`: Postura baja con destello en la hoja; el tracking se fija en el tick 38 y arremete en el 44. Castiga la voltereta prematura.
  3. `floracion_purpurea` (Fase II): Vuelo prolongado con alas carmesí, picado vertical imbloqueable e impacto que inflige daño masivo y acumulación de `sangrado`.

### 3. Godfrey (`godfrey_senor_telurico.json`)
* **Preset**: `senor_telurico` («Señor Telúrico»)
* **Rol**: Coloso físico de rotura de postura, ondas terrestres y agarres.
* **Habilidades**:
  1. `pisoton_telurico`: Pisotón que genera una onda de choque expansiva a ras de suelo (`ground_only: true`, obliga a saltar). Abre ventana de bifurcación (`branch`):
     - **Pulsar `skill`**: `hachazo_partidor` — Hachazo vertical a dos manos con superarmadura de gran impacto.
     - **Pulsar `alt`**: `rugido_guerra` («Rugido») — Grito brutal que emite un pulso omnidireccional en 360° empujando al rival a 10 m/s.
  2. `presa_del_coloso`: Abalanzada imbloqueable con brazos abiertos. Si conecta, levanta al rival y lo azota contra el suelo provocando derribo forzado (`knockdown`). Si falla, queda expuesto 44 ticks.
  3. `hendedura_cataclismica` (Fase II): Hunde el hacha abriendo una grieta lineal en la arena y la arranca en una violenta erupción de rocas imbloqueable.

---

## 3. Validación de los Catálogos

Para comprobar que cualquiera de estos catálogos cumple al 100 % con las reglas V01–V19 del motor:

```bash
godot --headless --path . --script res://tools/validate_abilities.gd -- docs/catalogos_bosses/radagon_orden_dorada.json
godot --headless --path . --script res://tools/validate_abilities.gd -- docs/catalogos_bosses/malenia_hoja_espiral.json
godot --headless --path . --script res://tools/validate_abilities.gd -- docs/catalogos_bosses/godfrey_senor_telurico.json
```
