# Guía de armas 3D (enganche a la mano)

Cómo conseguir, importar y enganchar mallas de armas (espadas, hachas, arcos…) a la mano de
cualquier personaje, sin tocar código. El sistema es **guiado por datos**:
`data/weapons/weapons.json` + `scripts/visual/weapon_attacher.gd` (clase `WeaponAttacher`).

## 1. Qué buscar al comprar o bajar un arma

- **Licencia comercial.** CC0, CC-BY (anotá el crédito en `CREDITS.md`) o una licencia de tienda
  que permita uso en juegos comerciales (Unity Asset Store/Fab/itch, leé la letra chica). Nada
  "solo uso personal" ni "editorial".
- **Nada sacado de otros juegos.** Ni rips ni "fan models" de juegos existentes, y en particular
  **nada de FromSoftware** (Dark Souls, Elden Ring, Bloodborne, Sekiro…) aunque esté "gratis" en
  Sketchfab: no tienen licencia válida. Inspirarse está bien; copiar el diseño, no.
- **Formato: GLB preferido** (glTF binario: malla + materiales + texturas en un archivo). FBX
  sirve, pero suele venir con escala 100 o ejes cambiados. OBJ sirve pero sin jerarquía.
- **Estática, sin esqueleto.** Una malla rígida; si trae huesos o animaciones, no hacen falta.
- **Liviana: menos de 5.000 triángulos** por arma (en la arena se ven chicas; más es desperdicio).
- **Texturas de 1024×1024 o menos** (512 suele alcanzar). Mejor una sola textura/material.
- **Una pieza por arma.** Si el pack trae 20 espadas en un solo archivo, separalas (en Blender) o
  usá `mesh_node` para elegir una (ver §4).
- **Origen en la empuñadura (ideal).** Que el punto (0,0,0) del modelo esté donde cierra la mano y
  la hoja apunte a +Y. Si no, se corrige (§3) o se compensa con `offset` (§5).

## 2. Importar

1. Copiá el archivo a `assets/weapons/<id>/<id>.glb` (y sus texturas al lado si son externas).
2. `godot --headless --path . --import` (o abrí el editor una vez).
3. En el panel de importación del `.glb` podés desactivar animaciones y, para FBX, ajustar
   `Root Scale` si viene gigante.

## 3. Arreglar el origen (opcional pero recomendado)

En Blender: seleccioná el arma → modo edición → seleccioná un vértice/anillo del centro de la
empuñadura → `Shift+S` → *Cursor to Selected* → modo objeto → *Object › Set Origin › Origin to 3D
Cursor*. Rotala para que la hoja apunte a +Z de Blender (= +Y en Godot tras exportar glTF) y
aplicá transformaciones (`Ctrl+A` › *All Transforms*). Exportá como glTF binario.

Si no tenés Blender, dejalo como viene y compensá todo con `offset`.

## 4. Agregar la entrada al JSON

`data/weapons/weapons.json`, clave = **id del arma** (el mismo de `resources/weapons/<id>.tres`,
`Catalog.WEAPONS` y `requires_weapon` de las habilidades):

```json
"espada_larga": {
  "enabled": true,
  "mesh": "res://assets/weapons/espada_larga/espada_larga.glb",
  "mesh_node": "",
  "hand": "both",
  "bone": "handslot.r",
  "bone_overrides": {"mixamo": "mixamorig_RightHand", "ue": "hand_r", "mi_personaje": "Hand_R_Weapon"},
  "offset": {"position": [0, 0.02, 0], "rotation_degrees": [0, 90, 0], "scale": [1, 1, 1]},
  "second_grip": {"position": [0, -0.25, 0]},
  "notes": "Espada X de pack Y (CC0)"
}
```

| Campo | Qué es |
|---|---|
| `enabled` | `true` = el juego usa esta malla. `false` = se sigue usando el enganche clásico (malla KayKit o procedural); la entrada solo se valida. |
| `mesh` | `res://` a `.glb`/`.fbx`/`.tscn`/`.res`. Vacío = todavía sin malla. |
| `mesh_node` | Opcional: nombre de un `MeshInstance3D` dentro del archivo (packs con varias armas, como los `.glb` KayKit). |
| `hand` | `right`, `left` o `both` (a dos manos: se engancha a la derecha). |
| `bone` | Hueso preferido. Si no existe en el esqueleto, se prueba la lista de abajo. |
| `bone_overrides` | Mapa por **perfil de esqueleto** (`kaykit`, `mixamo`, `ue`, `rigify`, `biped`, `humanoid`, `unknown`) o por **id de personaje**. El de personaje gana. |
| `offset` | `position` (metros, en el espacio del hueso), `rotation_degrees` (X, Y, Z), `scale` (vector o número). |
| `second_grip` | Opcional, para armas a dos manos: punto donde iría la otra mano. Se crea un `Marker3D` «SecondGrip» (para IK futura). |

Orden de resolución del hueso: override por personaje → override por perfil → `bone` → lista
de respaldo (`handslot.r`, `HandR`, `hand.r`, `hand_r`, `Hand_R`, `Hand.R`, `RightHand`,
`mixamorig_RightHand`, `DEF-hand.R`, `Bip01 R Hand`, …; espejo para la izquierda).

Ojo: Godot 4 no acepta `:` en nombres de hueso, así que los Mixamo importados quedan como
`mixamorig_RightHand` (no `mixamorig:RightHand`).

Los personajes con `retarget_lib` (los modelos de prueba de `assets/test_models`) se renombran a
huesos KayKit y reciben `handslot.l/r` al cargar: para ellos el perfil es `kaykit`.

## 5. Ajustar el offset

1. Sugerencia automática (sin abrir el editor):
   ```bash
   godot --headless --path . --script res://tools/weapon_grip_probe.gd -- espada_larga
   godot --headless --path . --script res://tools/weapon_grip_probe.gd -- res://assets/weapons/x/x.glb
   ```
   Imprime el AABB, si el origen está dentro de la malla, el eje largo, y propone
   `offset.position` (lleva la empuñadura al hueso) y `rotation_degrees` (hoja en +Y). Es una
   heurística: asume que la empuñadura es el extremo más angosto.
2. Afinación en el editor: abrí `scenes/arena.tscn` (o una captura de `tests/screenshot_*.gd`),
   buscá `Skeleton3D/<id>_slot/Grip` en el árbol remoto y movelo; copiá los valores al JSON.
3. Escala: los modelos de prueba aplican la compensación de escala del esqueleto
   (`_compensate_attachments`) pero **no** el factor chibi `TEST_WEAPON_K`; si el arma se ve
   grande o chica, tocá `offset.scale`.

## 6. Validar

```bash
godot --headless --path . --script res://tools/validate_weapons.gd             # sale 1 si hay errores
godot --headless --path . --script res://tools/validate_weapons.gd -- --strict # los avisos también fallan
godot --headless --path . -s res://tests/test_weapon_attach.gd
```

Chequea: ids existentes en el catálogo, rutas `res://` que existan, `mesh_node` presente, `hand`
válido, overrides no vacíos, offsets numéricos `[x, y, z]`, escala > 0, `second_grip` bien
formado; avisa si un arma del catálogo no tiene entrada o hay campos desconocidos.

## 7. Relación con las habilidades (`requires_weapon`)

`requires_weapon` (en `data/abilities/*.json`, ver `docs/abilities_guide.md`) usa **los mismos
ids** que este JSON. Para un arma nueva:

1. `resources/weapons/<id>.tres` (stats, animaciones) y sumarla a `Catalog.WEAPONS`.
2. Entrada `<id>` en `weapons.json` con su malla.
3. Recién ahí, usá `<id>` en `requires_weapon`; `validate_abilities.gd` rechaza ids
   inexistentes.

## 8. Cómo se engancha (para programadores)

`KnightVisual.setup()` llama a `_data_weapon(sk, id)` para el arma cuerpo a cuerpo y para el
arma a distancia. Si la entrada está `enabled` y la malla existe, `WeaponAttacher.attach()` crea
`Skeleton3D/<id>_slot` (`BoneAttachment3D`) › `Grip` (offset) › malla, y la primera
`MeshInstance3D` pasa a ser `sword`/`bow` (tintes, brillo, estela y escala de cambio de arma
siguen funcionando). Si no, se usa el camino de siempre (`_weapon_mesh`, `_make_lance`, arco
procedural). La daga izquierda (`mesh_left`), el arma secundaria y los escudos siguen por el
camino clásico.
