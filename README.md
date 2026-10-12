# Arena de Eikons (Godot 4.7.2)

Juego de lucha 1 contra 1 en arena, de fantasía medieval. Los dos luchadores van montados y usan espada, escudo y arco. Cada uno puede invocar un **eikon** (fénix de fuego, lobo de hielo o gólem de piedra) cuando su medidor está lleno. Todo el arte es de placeholder hecho con primitivas.

## Controles
| Acción | Teclado | Táctil |
|---|---|---|
| Moverse (relativo a la cámara) | WASD / flechas | Joystick virtual (izquierda) |
| Espada | J | Botón *Espada* |
| Escudo (mantener; pulsarlo justo antes del golpe = **parry**) | K | Botón *Escudo* |
| Arco (apuntado automático) | L | Botón *Arco* |
| Invocar eikon (medidor lleno) | E | Botón *Eikon* |
| Dash / carga | Espacio | Botón *Dash* |

## Reglas
- Al mejor de 3 rondas. Cada ronda dura 90 s; si se acaba el tiempo, gana quien tenga más vida (en %).
- El medidor de eikon se carga al golpear (espada +12, flecha +8), al recibir golpes (+5), al bloquear (+3) y al hacer parry (+15).
- Bloquear de frente reduce el daño un 80 %. Un parry anula el golpe, aturde al atacante y devuelve las flechas.
- El eikon lucha durante un tiempo limitado y también puede recibir ataques.

## Estructura
- `scenes/arena.tscn` + `scripts/arena.gd`: arena (muro circular y pilares), cámara, rondas y pantalla final.
- `scripts/combat/fighter.gd`: luchador montado (movimiento, espada, escudo/parry, arco, dash, invocación).
- `scripts/combat/eikon.gd`: invocaciones (ataques cuerpo a cuerpo, a distancia o en área).
- `scripts/combat/projectile.gd`: flechas y proyectiles.
- `scripts/ai/ai_controller.gd`: IA rival (se acerca, rodea, ataca, bloquea, dispara e invoca).
- `scripts/player_controller.gd`: teclado y controles táctiles.
- `scripts/ui/hud.gd`, `touch_stick.gd`: HUD, joystick y botones táctiles (multitáctil).
- `scripts/data/mount_data.gd`, `eikon_data.gd`: Resources de datos.
- `resources/mounts/*.tres`: caballo, unicornio, grifo. `resources/eikons/*.tres`: fénix, lobo de hielo, gólem.
- `tests/`: pruebas automáticas y captura de pantalla.

## Cómo ampliar
- **Nueva montura:** duplica un `.tres` de `resources/mounts/` y cambia sus valores (velocidad, giro, dash, vida extra, color).
- **Nuevo eikon:** duplica un `.tres` de `resources/eikons/` y elige `attack_kind` (0 cuerpo a cuerpo, 1 a distancia, 2 área). Luego añádelo a `EIKONS` en `arena.gd`.
- **Mobs (futuro):** cualquier nodo del grupo `damageable` con `team`, `alive`, `hit_radius`, `take_hit()` y `get_hit_center()` funciona ya como objetivo de espadas, flechas y eikons. Usa un `team` distinto (p. ej. 2) para un bando neutral.

## Pruebas
```
godot --headless --path . -s res://tests/test_combat.gd   # espada, bloqueo, parry, arco, eikon
godot --headless --path . -s res://tests/test_match.gd    # partida IA contra IA completa
```

## Exportar
Los presets "Android" (arm64, apaisado, sin compilación Gradle, firma de depuración) y "Windows Desktop" están en `export_presets.cfg`. Necesitas:
- Las plantillas de exportación de Godot 4.7.2.
- JDK 17 y el Android SDK (platform-tools, build-tools 35, platform android-35), configurados en *Editor Settings > Export > Android*.
- Un keystore de depuración, o uno de release para publicar (AAB + Gradle para Play Store).

`godot --headless --export-debug Android ../out/arena-game-debug.apk`

## Próximos pasos
Animaciones y modelos reales, selector de montura y eikon, vuelo del grifo, lock-on manual, más ataques por eikon, oleadas de mobs, sonido y efectos, y ajustar la dificultad de la IA.
