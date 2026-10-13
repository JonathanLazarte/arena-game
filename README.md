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
- Modelos CC0 (ver `CREDITS.md`): caballero KayKit para ambos luchadores (tinte azul/rojo en capa y escudo), caballo de Quaternius, lobo y dragón-fénix de Quaternius, Goleling como gólem provisional (sustituido en la ronda 8) y el Castle Kit de Kenney para muros, pilares y decoración.
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

## Ronda 8: jinete a horcajadas, gólem nuevo y escudo contra eikons
- **Postura de montar:** el jinete se sienta a horcajadas. Parte de `Sit_Chair_Pose` y `RidingPose` (un `SkeletonModifier3D`, `scripts/visual/riding_pose.gd`) corrige las piernas después del AnimationTree: abre los muslos hacia los flancos, los baja y deja las espinillas colgando. La cadera se coloca cada frame en el **punto de silla** del caballo (`Mount.saddle_position()`, un BoneAttachment3D en el hueso `Torso`), así que sube y baja con el galope. Al desmontar la postura se quita poco a poco.
- **Gólem de piedra:** usa el *Giant* de Quaternius (CC0, con Walk/Idle/Attack) con material de roca (ruido triplanar), ojos de lava y rocas de Quaternius en hombros, espalda y puños, que siguen a los huesos. Mide unos 3 m. Sustituye al Goleling.
- **Escudo contra eikons:** un ataque de eikon bloqueado (bola de fuego del fénix, mordisco del lobo, onda del gólem) deja pasar el **50 %** del daño y cuesta **30** de aguante (`EIKON_BLOCK_PASS`, `COST_BLOCKED_EIKON`). Las flechas siguen anuladas del todo. Los proyectiles tienen ahora `kind` ("arrow" o "eikon"), y las bolas de fuego del fénix ya no se pueden devolver con parry (igual que el resto de ataques de eikon).
- Pruebas nuevas: `tests/test_eikon_block.gd` y `tests/test_riding.gd`. Capturas: `tests/screenshot_mounted.gd -- <png> [still|gallop] [show|hide] [side|front]` y `tests/golem_preview.gd -- <png>` (necesitan pantalla, p. ej. `xvfb-run ... --rendering-driver opengl3`).
- `test_match` devolvía código 1 aunque la partida terminara (comprobaba el estado después de reiniciar). Ya está corregido.

## Ronda 9: respiros de la IA, voltereta estilo Dark Souls, eikon arreglado y dash + ataque
- **Respiros de la IA** (`Phase.BREATHE` en `ai_controller.gd`, ajustes en `AIDifficulty`): tras un intercambio (con probabilidad `breather_chance`), o si lleva `breather_interval` s sin respirar, el rival se aleja a `breather_dist`, rodea despacio, recupera aguante o espera quieto mirándote durante un tiempo aleatorio entre `breather_min` y `breather_max`. En ese tiempo no ataca, pero sigue defendiéndose.
  | Perfil | Probabilidad | Duración | Distancia | Respiro forzado cada |
  |---|---|---|---|---|
  | easy | 65 % | 3,5–7 s | 13 m | 9 s |
  | normal | 35 % | 2–4,5 s | 11 m | 14 s |
  | hard | 15 % | 1,2–2,8 s | 9 m | 22 s |
- **Voltereta a pie estilo Dark Souls** (el dash montado no cambia). A 30 fps: **2 frames de arranque vulnerable + 12 i-frames + 10 de recuperación vulnerable = 24 frames (0,8 s)**, recorre 4,5 m (+0,4 m al levantarse) y cuesta 20 de aguante. Durante la recuperación no se puede atacar, bloquear, hacer parry ni volver a rodar. Si ruedas demasiado pronto o demasiado tarde, te golpean. Animación: `Dodge_Forward/Backward/Left/Right` de KayKit (la voltereta del pack), con la velocidad ajustada para que dure exactamente 0,8 s.
  - Datos de referencia (30 fps):
    - **DS1:** fast roll de 13 i-frames y 21–24 frames en total; medium roll de 11 i-frames y 33 frames; fat roll de 9 i-frames y 46 frames (GameFAQs, "Rol/Flip iFrames and recovery info", https://gamefaqs.gamespot.com/boards/606312-dark-souls/63774400). La wiki de Fandom da 11 i-frames para todas las rolls y separa la recuperación: fast roll al 25 %, 11 i-frames + 3 de recuperación + 8 de "inestabilidad" + 2 = 24 frames (https://darksouls.fandom.com/wiki/Rolling).
    - **DS3:** 12 i-frames (0,4 s; Carthus Bloodring +3), según https://github.com/gastevens/dark-souls-3-mechanics-cheat-sheet/blob/master/ds3mechanicscheatsheet.md. El fast roll tiene unos 13 i-frames y 21 frames en total (datos de 60 fps divididos entre 2: https://gamefaqs.gamespot.com/boards/168566-dark-souls-iii/74600300).
  - En DS1 los i-frames empiezan en el primer frame. Los 2 frames de arranque vulnerable son una decisión de diseño de este juego, para castigar el roll de pánico tardío.
- **Eikon (fénix):** la entrada, la aparición y los ataques funcionaban. El problema era que el medidor casi nunca se llenaba:
  - se ponía a 0 en cada ronda;
  - solo subía con golpes (unos 8 golpes acertados en 90 s);
  - en una partida IA contra IA el jugador llegó como máximo a 90 / 100 y solo invocó una vez en toda la partida.
  - Además, pulsar E o el botón *Eikon* con el medidor a medias no daba ningún aviso, y las bolas de fuego eran una varilla fina que apuntaba a donde estaba el rival, no a donde iba (fallaban contra jinetes en movimiento).
  - **Arreglos:**
    - el medidor se conserva entre rondas (solo se vacía al reiniciar la partida);
    - sube de forma pasiva (+1,2/s en combate);
    - el HUD avisa ("Eikon: medidor al 70 %", "¡Eikon listo!") y el botón se ilumina cuando está lleno;
    - las bolas de fuego se ven (núcleo y estela) y apuntan adelantándose al objetivo.
  - Ahora se invoca hacia los 40 s y varias veces por partida.
- **Dash montado + ataque:** puedes empezar la anticipación (ligero, o el fuerte cargado al mantener el botón) antes o durante el dash montado. La anticipación sigue cargándose durante el dash, el caballo frena justo delante del rival (sin embestida) y el golpe sale al acabar el dash (o en cuanto lleve 0,12 s de anticipación). El dash montado sin ataque es igual que antes.
- Pruebas nuevas: `test_roll`, `test_dash_attack`, `test_eikon_summon` y `test_ai_breather`.

## Ronda 10 — Lobby, personajes, armas y equipamiento

- **Lobby** (`scenes/lobby.tscn`, escena principal): personaje en un pedestal giratorio (se arrastra para girarlo) delante de murallas de castillo; barra superior con nombre editable, nivel y **oro** (de muestra, solo local); pestañas **Personajes, Armas, Eikons, Monturas, Inventario**; dificultad **Fácil / Normal / Difícil**; botón **JUGAR**. Teclado: Q/E pestañas, 1-3 dificultad, Enter jugar.
- **Datos:** `CharacterDef` (`resources/characters/*.tres`) y `WeaponDef` (`resources/weapons/*.tres`), listados en `scripts/data/catalog.gd`.
- **Equipamiento** (`GameState`, autoload): personaje, arma (filtrada por rol), eikon, montura y dificultad. Se guarda en `user://loadout.cfg`. El rival recibe un equipamiento aleatorio coherente (siempre cuerpo a cuerpo).
- **Armas en combate:** alcance, arco de golpe, daño, anticipación/activo/recuperación, coste de aguante, combo máximo, escudo o no (sin escudo el bloqueo deja pasar más daño y cuesta x1,5), rompeguardias, daño al equilibrio, bonus de la lanza montado. El arquero empieza con arco y lucha con dagas.
- **Pasivas:** Guardia firme (−20 % de aguante al bloquear), Ojo de halcón (+30 % flechas), Furia (+25 % de daño con menos del 40 % de vida), Luz sanadora (2 de vida/s tras 3 s sin recibir golpes), Sombra (+3 frames de invulnerabilidad en la voltereta y −25 % de coste).
- Al acabar la partida: **Volver al lobby** (o Reiniciar).
- Si se abre `arena.tscn` directamente (pruebas), se usa el luchador neutro clásico con espada y escudo, sin pasiva.
- Pruebas nuevas: `test_defs`, `test_loadout`, `test_weapons`. Captura: `godot --path . --rendering-driver opengl3 -s res://tests/screenshot_lobby.gd -- out.png [personaje] [pestaña]`.

## Ronda 11 — Primera elección, progresión y estilo dark fantasy

- **Primera ejecución** (`scenes/first_run.tscn`): «ELIGE TU DESTINO». Presenta los 5 roles con modelo, descripción, pasiva y estadísticas, y pide confirmación («Sellar pacto» → «Jurar lealtad»). Solo el elegido queda desbloqueado; los demás se compran con oro en el lobby, con confirmación.
- **Progresión** (`scripts/data/progression.gd`):
  - Curva de XP: 100·n^1.4 por nivel (100, 260, 470, 700, 950…), tope en nivel 30.
  - La XP va a la cuenta y al personaje usado. 1 punto de habilidad por nivel de personaje.
  - Recompensas: victoria 120 XP/150 oro, derrota 50/60, +25 XP/+20 oro por ronda ganada, +3 XP por golpe (máximo 30 golpes), +10 XP/+5 oro por parry. Multiplicador ×0,8 en fácil y ×1,3 en difícil. +100 oro por cada nivel de cuenta.
  - Precios de personajes: Caballero y Arquero 1200, Berserker 1500, Paladín y Asesino 1800 (cuenta nueva: 300 oro).
  - Armas: Espada larga nivel 2 + 350, Lanza nivel 4 + 600.
  - Eikons: Lobo nivel 3 + 800, Gólem nivel 6 + 1400.
  - Monturas: Unicornio nivel 2 + 500, Grifo nivel 5 + 1200.
  - Árbol de 4 nodos por rol (pestaña **Habilidades**).
- **Resultados** al acabar la partida: desglose de XP y oro, barra de nivel animada y avisos de subida de nivel.
- **Guardado v2** en `user://loadout.cfg` (`[meta] version=2`). Un guardado v1 (ronda 10) se migra:
  - Se desbloquea el personaje que usaba y se conserva lo que tenía equipado.
  - Se conservan el nombre y el oro.
  - No se vuelve a pedir la elección.
- **Estilo dark fantasy:**
  - Paleta negra, carmesí, oro deslustrado y ceniza.
  - Fuentes Cinzel e IM Fell (OFL).
  - Paneles con marco ornamentado, viñeta y brasas.
  - Lobby de noche con antorchas parpadeantes, niebla roja y foco sobre el pedestal.
  - Botones con animación y sonido (Kenney, CC0) y fundidos entre escenas.
  - La arena es un crepúsculo con niebla y 8 braseros.
- Pruebas nuevas: `test_first_run`, `test_purchase`, `test_progression`, `test_migration`.
- Capturas: `tests/screenshot_lobby.gd -- <png> first_run|lobby|results [personaje] [pestaña]`.
