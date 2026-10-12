# Arena de Eikons (Godot 4.7.2)

Juego de lucha 1 contra 1 en arena, de fantasía medieval. Los dos luchadores van montados y usan espada, escudo y arco. Cada uno puede invocar un **eikon** (fénix de fuego, lobo de hielo o gólem de piedra) cuando su medidor está lleno. Todo el arte es de placeholder hecho con primitivas.

## Controles
| Acción | Teclado | Táctil |
|---|---|---|
| Moverse (relativo a la cámara, o al rival con lock-on); atrás = marcha atrás sin girar | WASD / flechas | Joystick virtual (izquierda) |
| Fijar objetivo (lock-on, activado por defecto) | Tab | Botón *Fijar* |
| Atacar: pulsar = ligero (combo de hasta 3), mantener 0,4 s = fuerte. Con arco, dispara | J | Botón *Atacar* (único botón de ataque) |
| Cambiar arma (espada+escudo ⇄ arco, 2 s) | R | Botón *Cambiar* |
| Escudo: mantener para bloquear (solo bloquea) | K | Botón *Escudo* |
| Parry (acción propia) | Q | Botón *Parry* |
| Invocar eikon (medidor lleno) | E | Botón *Eikon* |
| Montar / desmontar (cerca de una montura libre) | F | Botón *Montar* |
| Galope / sprint (mantener; gasta aguante) | Shift | Botón *Galope* (mantener) |
| Dash / carga (a pie: voltereta) (en la dirección del movimiento; 0,2 s de invulnerabilidad; si choca, empuja al rival) | Espacio | Botón *Dash* |

## Reglas
- **Combate estilo souls:** cada ataque tiene anticipación (la hoja se alza y brilla), frames activos y recuperación, durante la cual eres vulnerable.
  - **Ligero:** 0,45 s de anticipación, 12 de daño, 14 de aguante. Se encadena hasta 3 golpes con búfer de entrada; el último deja más expuesto.
  - **Fuerte:** 0,8 s, 26 de daño, 28 de aguante, súper-armadura en la anticipación y alta probabilidad de derribo.
  - **Compromiso:** durante el ataque no puedes bloquear, disparar, cambiar de arma ni montar. Solo puedes cancelar con voltereta/dash en la 2.ª mitad de la recuperación.
  - Fallar el golpe alarga la recuperación (+0,3 s).
- **Poise:** cada golpe recibido gasta poise y, si se agota, quedas aturdido. Un golpe interrumpe el ataque ligero del rival, así que intercambiar golpes no sale gratis.
- **Armas:** espada+escudo **o** arco, nunca ambos. Cambiar tarda 2 s (barra en el HUD) y en ese tiempo no puedes atacar ni bloquear. Con arco no hay escudo: solo dash o voltereta.
- **Parry (acción propia, no depende del escudo):** abre una ventana activa de 0,3 s (`PARRY_WINDOW`) y cuesta 15 de aguante. Si acierta: no recibes daño, el atacante queda aturdido 1,6 s y tu siguiente golpe hace ×1,8 (riposte). Si falla: 0,8 s de recuperación sin poder bloquear, atacar ni hacer dash, y recibes un +25 % de daño. No se puede usar con el arco. La IA también lo usa, con el mismo riesgo.
- **IA:** lee tus anticipaciones y esquiva, retrocede o hace parry; luego castiga tu recuperación. Sus propios ataques también se telegrafían y se pueden castigar. Cambia de arma según la distancia, pagando el mismo coste de 2 s.
- **Jinete y montura son entidades separadas.** Montado eres rápido y la espada (hoja larga) alcanza unos 3,4 m en un arco de ±100° (frente y lados). A pie (8,3 de velocidad) vas más lento, giras más cerrado, la espada alcanza unos 2,2 m (±70°) y el dash se convierte en una voltereta rápida. La montura sin jinete se queda cerca paseando; acércate y pulsa *Montar*.
- **Derribo:** un dash que acierta (50 %) o un golpe fuerte de 14 o más de daño (30 %) puede tirarte de la montura.
- **Aguante (barra amarilla):** lo gastan dash/voltereta, espada, arco, galope, mantener el escudo y bloquear golpes. Se recupera si no lo gastas, y más rápido si estás quieto o retrocediendo. Si llega a 0 quedas **agotado** unos 1,5 s: más lento, sin ataques ni dash y con un bloqueo más débil.
- Al mejor de 3 rondas. Cada ronda dura 90 s; si se acaba el tiempo, gana quien tenga más vida (en %).
- El medidor de eikon se carga al golpear (espada +12, flecha +8), al recibir golpes (+5), al bloquear (+3) y al hacer parry (+15).
- Bloquear de frente reduce el daño un 80 %. Un parry anula el golpe, aturde al atacante y devuelve las flechas.
- **Lock-on:** el jugador mira siempre al rival, la cámara encuadra a ambos, la espada y el arco apuntan al rival y el movimiento pasa a ser un *strafe* alrededor de él.
- El eikon lucha durante un tiempo limitado y también puede recibir ataques.

## Estructura
- `scenes/arena.tscn` + `scripts/arena.gd`: arena (muro circular y pilares), cámara, rondas y pantalla final.
- `scripts/combat/fighter.gd`: jinete (movimiento montado o a pie, espada con arco de alcance, escudo/parry, arco, dash/voltereta, aguante, montar/desmontar, invocación).
- `scripts/combat/mount.gd`: montura independiente (sigue al jinete; libre, pasea cerca). Cualquier jinete puede montar cualquier montura libre.
- `scripts/combat/eikon.gd`: invocaciones (ataques cuerpo a cuerpo, a distancia o en área).
- `scripts/combat/projectile.gd`: flechas y proyectiles.
- `scripts/ai/ai_controller.gd`: IA rival por fases (rodear a media distancia por delante, comprometerse a atacar con espada o dash, retirarse y descansar o huir cuando le falta aguante). Si la derriban, vuelve a montar cuando es seguro o lucha a pie. Evita quedarse a la espalda y nunca se solapa.
- `scripts/player_controller.gd`: teclado y controles táctiles.
- `scripts/ui/hud.gd`, `touch_stick.gd`: HUD, joystick y botones táctiles (multitáctil).
- `scripts/data/mount_data.gd`, `eikon_data.gd`: Resources de datos.
- `resources/mounts/*.tres`: caballo, unicornio, grifo y `on_foot.tres` (estadísticas a pie). `resources/eikons/*.tres`: fénix, lobo de hielo, gólem.
- `tests/`: pruebas automáticas y captura de pantalla.

## Cómo ampliar
- **Nueva montura:** duplica un `.tres` de `resources/mounts/` y cambia sus valores (velocidad, giro, dash, vida extra, color).
- **Nuevo eikon:** duplica un `.tres` de `resources/eikons/` y elige `attack_kind` (0 cuerpo a cuerpo, 1 a distancia, 2 área). Luego añádelo a `EIKONS` en `arena.gd`.
- **Mobs (futuro):** cualquier nodo del grupo `damageable` con `team`, `alive`, `hit_radius`, `take_hit()` y `get_hit_center()` funciona ya como objetivo de espadas, flechas y eikons. Usa un `team` distinto (p. ej. 2) para un bando neutral.

## Pruebas
```
godot --headless --path . -s res://tests/test_combat.gd   # espada, bloqueo, parry, arco, eikon
godot --headless --path . -s res://tests/test_match.gd    # partida IA contra IA completa
godot --headless --path . -s res://tests/test_souls.gd   # compromiso, fuerte, cambio de arma, parry, lectura de la IA
godot --headless --path . -s res://tests/test_ai.gd -- 1  # la IA no se pega a la espalda ni se solapa (semilla opcional)
```

## Exportar
Los presets "Android" (arm64, apaisado, sin compilación Gradle, firma de depuración) y "Windows Desktop" están en `export_presets.cfg`. Necesitas:
- Las plantillas de exportación de Godot 4.7.2.
- JDK 17 y el Android SDK (platform-tools, build-tools 35, platform android-35), configurados en *Editor Settings > Export > Android*.
- Un keystore de depuración, o uno de release para publicar (AAB + Gradle para Play Store).

`godot --headless --export-debug Android ../out/arena-game-debug.apk`

## Próximos pasos
Animaciones y modelos reales, selector de montura y eikon, vuelo del grifo, cambio de objetivo con lock-on (mobs), más ataques por eikon, oleadas de mobs, sonido y efectos, y ajustar la dificultad de la IA.

## Arte (ronda 6)
- Modelos CC0 (ver `CREDITS.md`): caballero KayKit para ambos luchadores (tinte azul/rojo en capa y escudo), caballo de Quaternius, lobo y dragón-fénix de Quaternius, Goleling como gólem provisional y el Castle Kit de Kenney para muros, pilares y decoración.
- `scripts/visual/knight_visual.gd`: AnimationTree del jinete. La base es la locomoción (BlendSpace2D Idle/Walk/Run/Strafe/Back) a pie o `Sit_Chair_Pose` montado. Encima va una StateMachine de acciones mezclada con un Blend2 con máscara de tren superior (montado, bloqueo, arco y cambio de arma):
  - ataques ligeros (combo Slice Diagonal / Horizontal / Chop) con la velocidad ajustada por fase (windup, active, recovery) y ataque fuerte con 2H Chop;
  - bloqueo con Blocking y Block_Hit; parry con Block_Attack;
  - voltereta con Dodge_F/B/L/R; golpe con Hit_A, aturdimiento con Hit_B y muerte con Death_A;
  - arco con 2H_Ranged_Aiming y Shoot; cambio de arma con Use_Item.
- Caballo: BlendSpace1D Idle/Walk/Gallop según la velocidad real.
- Las armas van en BoneAttachment3D (`handslot.r` / `handslot.l`). La detección de golpes no cambia: sigue siendo por arcos en `fighter.gd`. Los modelos son solo visuales.
- La arena es un 40 % más grande: radio 42, pilares a 23,8 m y salida a ±19,6 m.

## Escudo y dificultad (ronda 7)
- **Escudo (arco frontal):**
  - Las flechas bloqueadas no hacen daño y solo cuestan 3 de aguante.
  - El cuerpo a cuerpo bloqueado deja pasar un 12 % del daño (chip). Cada golpe ligero bloqueado cuesta 22 de aguante y los fuertes el doble, así que la barra llena aguanta unos 4-5 ligeros.
  - Mantener el escudo gasta 3 de aguante por segundo.
  - Si te quedas sin aguante bajo el escudo, se **rompe la guardia**: tambaleo de 1 s y quedas expuesto.
- **Dificultad de la IA:** se configura con el recurso `AIDifficulty` (`resources/ai/easy|normal|hard.tres`), con estos parámetros: pausas entre ataques, cadena máxima, agresividad (dash de entrada, aguante mínimo para atacar), probabilidad de castigar, esquivar, hacer parry y bloquear flechas, tiempo de reacción e intervalo de decisión.
  - El rival por defecto es el nivel 1 "easy". El perfil "normal" equivale al comportamiento anterior.
