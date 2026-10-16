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

## Ronda 12 — Estilo móvil comercial (sustituye al dark fantasy)

- Interfaz brillante y saturada:
  - Paneles azules/cian redondeados y gruesos, acentos naranja/amarillo, texto blanco con contorno oscuro y sombra.
  - Fuente **Lilita One** (OFL) en toda la interfaz (`scripts/ui/ui_kit.gd`).
  - Botones con degradado tipo "glossy" (franja de brillo), bisel inferior que se hunde al pulsar, sombra, rebote al pasar o pulsar, y sonido.
  - **JUGAR** grande y amarillo, con un destello que lo recorre.
- Barra superior con insignia de nivel (hexágono), barra de XP, píldoras de **oro** (moneda dibujada) y **gemas** (moneda premium de muestra, sin uso). Puntos rojos de notificación en las pestañas cuando hay habilidades por aprender o algo que ya se puede comprar.
- Escaparate de día:
  - Cielo azul, césped y castillo claro.
  - Pedestal azul con aro cian pulsante y contraluz cian/dorado.
  - Rayos de luz giratorios (planos aditivos) y destellos.
  - El personaje entra con un rebote.
- Resultados tipo recompensa: 1-3 estrellas (2-0 = 3, 2-1 = 2, derrota con alguna ronda = 1) y una lluvia de monedas que vuela al contador de oro.
- Arena de día con niebla muy ligera; se quitan los braseros, la viñeta y las brasas.
- Se mantienen la elección inicial, la progresión, los árboles, las compras, los resultados y el guardado v2 (con `gemas` añadido sin cambiar la versión).

## Ronda 13 — Estilo inspirado en Final Fantasy (sustituye al estilo móvil)

- Interfaz sobria y épica:
  - Paneles azul medianoche translúcidos con degradado suave, filo plateado, línea dorada interior y cristales en las esquinas.
  - Menús limpios en los que el elemento seleccionado lleva una barra degradada azul y un cursor de cristal que oscila apenas.
  - Títulos en **Cinzel** con halo azul y texto en **Lato** (ambas OFL).
  - Sin rebotes: entradas con fundido y deslizamiento, y fundido entre escenas.
- Barra superior: insignia de nivel (anillo dorado), barra de EXP, oro (moneda grabada) y **Cristales** (moneda de muestra, solo se muestra).
- Novedades marcadas con un cristal azul que brilla.
- Escenario del lobby:
  - Cielo crepuscular con estrellas (un MultiMesh) y aurora (cintas aditivas).
  - Castillo en silueta y pedestal de piedra con runas.
  - **Cristal flotante** con luz azul, esquirlas de cristal 3D y 2D, y luz principal cálida desde delante para que el personaje se lea bien.
- Resultados al estilo FF: estandarte **VICTORIA** entre filos dorados, tabla de conceptos con columnas EXP/Oro, "EXP obtenida / Oro obtenido", barra de nivel con "Siguiente" y avisos de nivel.
- Arena: luz natural (sol alto y lateral más luz de relleno opuesta sin sombras, para que los luchadores no se vean oscuros a contraluz), cielo diurno suave, niebla mínima y suelo de tierra menos pálido.

## Ronda 14: eikons = monturas, combate a pie, esquivar proyectiles, estocada con dash, salto y áreas en el suelo

### Eikons y monturas (decisiones)
| Eikon | Tipo | Al montarlo | Especial (E montado) | Precio |
|---|---|---|---|---|
| Fénix | montable, **vuela** a ras de suelo (modelo de dragón Quaternius) | vel. 15, giro 3,6; las áreas en el suelo no te alcanzan; no salta | **Llamarada**: bola de fuego que persigue (8 de daño, 1,6 s) | gratis |
| Lobo de Hielo | montable (modelo de lobo con el mismo rig que el caballo) | vel. 16,5, giro 4,2 (el más ágil), brinco | **Colmillo helado**: mordisco al frente, 14 de daño y congela 0,5 s (3 s) | Nv 3 · 800 |
| Grifo | montable (reutiliza el modelo de la antigua montura, dorado) | vel. 17 (el más rápido), dash 36, brinco | **Vendaval**: aletazo de 5,5 m que empuja (10 de daño, 4 s) | Nv 5 · 1200 |
| Gólem de Piedra | **no montable**: compañero con IA 15 s | — | sus golpes son áreas en el suelo con aviso (se pueden saltar) | Nv 6 · 1400 |

- **Unicornio: eliminado.** No aportaba nada que no tuvieran el lobo o el grifo. El caballo genérico también desaparece: ahora las monturas son eikons.
- **Invocar** (medidor lleno, E o botón Eikon):
  - Un eikon montable aparece ensillado bajo ti y montas al instante. Dura 20 s (el grifo, 22 s).
  - Con **F** te bajas y vuelves a subir, como antes. Solo su dueño puede montarlo: si bajas, te sigue de cerca.
  - Mientras lo montas usas sus estadísticas de montura. E, o el botón (que pasa a llamarse "Especial"), lanza su ataque especial.
  - Al acabarse el tiempo te baja sin aturdirte y desaparece. El HUD muestra los segundos que le quedan.
  - Un eikon no montable (gólem) lucha a tu lado como antes.
- **Las peleas empiezan a pie.** Cada ronda empieza a pie y sin eikon. El medidor se conserva entre rondas, como antes.
- Reglas que se mantienen:
  - Montado puedes recibir golpes y ser derribado.
  - Los golpes van al jinete; el eikon montado no tiene vida propia.
- **Lobby:** ya no hay pestaña ni ranura de Monturas. La pestaña Eikons indica si cada eikon es montable o compañero, muestra sus estadísticas de montura y su especial, y enseña el modelo del eikon junto al pedestal.
- **Guardado v3 (migración):**
  - Desaparecen `mount_id` y `owned_mounts`.
  - La montura comprada Grifo pasa a ser el eikon Grifo (si ya lo tenía, se devuelve su precio).
  - El Unicornio devuelve sus 500 de oro.
  - El caballo era gratis y no se compensa.
  - La migración funciona desde v1 y desde v2, y se guarda en `mount_migration`.
- **Pruebas antiguas:** las de combate montado clásico ponen `Arena.start_mounted = true` antes de cargar la arena. Así cada luchador recibe un caballo de pruebas neutral (`resources/mounts/horse.tres`, no se vende) y sus comprobaciones siguen midiendo lo mismo.

### Proyectiles con autoapuntado esquivables
- **Autoapuntado:** flechas y bolas de eikon persiguen a su objetivo con un **giro limitado** (flecha 1,6 rad/s, bola 1,4 rad/s). A menos de 2,5 m dejan de corregir.
- **Voltereta a tiempo** (el proyectil llega durante los i-frames): lo atraviesa, el proyectil "pierde" al objetivo y sigue de largo. Una vez rebasado no da la vuelta.
- **Voltereta demasiado pronto:** el proyectil corrige el rumbo y te da.
- El escudo y el parry funcionan igual (el reflejo no persigue).

### Estocada con dash (a pie y montado)
- **Animación propia `Dash_Strike`**, creada en Godot (`KnightVisual.author_dash_strike`) al cargar cada modelo KayKit:
  - piernas y cadera: el arranque de `Dodge_Forward` (la zancada), que se funde con la pose del tajo;
  - tronco y brazos: el tajo ligero del arma, re-temporizado;
  - además, un override de spine/chest que inclina el tronco en la arremetida.
  - Montado, el filtro de medio cuerpo deja solo el tajo.
- **Búfer generoso:**
  - Atacar durante el arranque o los i-frames de la voltereta: al acabar los i-frames sale la estocada, sin recuperación de voltereta y sin frames parados.
  - Hacer dash durante la anticipación de un ligero: se convierte en la estocada.
  - Montado, sigue la mecánica de la ronda 9 (golpe al acabar el dash) con la misma animación.
  - Atacar en la recuperación de la voltereta sigue sin contar.
- **Valores:** 15 de daño, anticipación 0,16 s avanzando a 12 m/s hacia el rival (se para delante, no lo atraviesa), recuperación 0,5 s.

### Salto y golpes de área en el suelo
- **Controles:** salto con **Espacio** o el botón **Saltar**. El dash pasa a **C**/**L** y la habilidad del personaje a **G** o el botón **Habilidad**.
- **Salto a pie:** 8 m/s, unos 0,8 s en el aire y 1,6 m de altura. Cuesta 12 de aguante.
  - En el aire: no hay voltereta, ni doble salto, ni habilidad, y el control es reducido.
  - Al caer hay una recuperación de 0,18 s.
  - **Ataque en salto:** atacar en el aire hace un picado que golpea al caer (16 de daño).
- **Montado:** en el lobo o el grifo el salto es un **brinco de la montura**. En el fénix no se salta (ya vuela).
- **`GroundAoE`** (`scripts/combat/ground_aoe.gd`): área en el suelo con **anillo de aviso** que se va llenando.
  - Al detonar solo alcanza a los objetivos **en el suelo**: saltando o volando en el fénix no te da.
  - La voltereta con i-frames también lo esquiva.
  - El escudo deja pasar el 50 %, como un ataque de eikon, y no se puede hacer parry.
  - A quien alcanza lo empuja y lo derriba un instante.
- **Golpe sísmico del Berserker:** área de 5 m, 0,7 s de aviso, 22 de daño y 8 s de recarga.
- **El gólem** ahora también golpea con un `GroundAoE`.
- **IA:**
  - Cuando un anillo enemigo le va a alcanzar, a veces salta. La probabilidad `jump_aoe_chance` es fácil 0,35, normal 0,6 y difícil 0,85; si no salta, a veces rueda fuera.
  - Un rival Berserker usa el golpe sísmico de cerca.
  - Usa el especial de su eikon montado según la distancia.
- **Pruebas nuevas:** `test_eikon_mount`, `test_projectile_dodge`, `test_dash_strike`, `test_jump_aoe` y la migración v2→v3 en `test_migration`.

## Ronda 15 — personaje fijo, cambio de arma rápido y correr estilo souls

- **Personaje fijo.** Se elige en la primera partida y se conserva. Ya no hay compra ni cambio de
  personajes: la pestaña **Personaje** muestra el tuyo (estadísticas, pasiva y nodos del árbol, que
  llevan a Habilidades). Gancho futuro: objeto de tienda **«Cambio de personaje»** (`Progression.CHARACTER_CHANGE_ITEM`,
  `GameState.change_character()`), hoy deshabilitado y mostrado como **Próximamente**.
- **Guardado v4 por ranuras.** Los datos del personaje (id, arma, XP, habilidades) van en `[slot_0]`
  (`meta/active_slot`, `GameState.MAX_SLOTS = 1`); un futuro selector multi-ranura solo tiene que
  subir `MAX_SLOTS`, fijar `active_slot` y recargar. Migración v2/v3 → v4: se conserva el personaje
  seleccionado (con su XP y habilidades) y se devuelve el oro de **todos** los personajes extra al
  precio antiguo (`LEGACY_CHARACTER_PRICE`); las armas compradas se conservan.
- **Cambio de arma** arco ↔ cuerpo a cuerpo en **0,42 s** (antes 2 s), para jugador e IA. El
  movimiento nunca se bloquea; solo atacar/disparar/bloquear. Transición suave: animación de tren
  superior (Use_Item ajustada al tiempo, fundido 0,14 s) y el arma saliente encoge mientras la nueva
  crece (cambio de malla a mitad, sin «pop»).
- **Correr a pie**: mantener **Mayús**, o alternar con **V / Bloq Mayús** o el botón táctil
  **«Correr»** (montado vuelve a ser **«Galope»** de mantener, sin cambios). Con fijado, correr
  **no gira** al personaje: sigue encarado y corre de espaldas (×0,8) o en diagonal/lateral. Sin
  fijar, correr gira normalmente. Gasta aguante; al agotarse se detiene y el modo alternado se apaga.
  Locomoción direccional: puntos extra en el BlendSpace2D con clips KayKit acelerados/ralentizados
  (carrera atrás = Walking_Backwards ×1,9; strafe caminando = Running_Strafe ×0,6; carrera lateral ×1,2).

## Ronda 16 — apuntado sin homing, cambio de objetivo, eikons compañeros y combos de 3 golpes

- **Proyectiles: solo apuntar.** Al disparar se apunta a la posición *actual* del objetivo
  (`Projectile.aim_dir`) y el proyectil vuela recto: sin homing ni giro (se eliminó lo de la
  ronda 14). Correr de lado a distancia lo esquiva; la voltereta lo atraviesa en los i-frames.
  IA honesta: `AIDifficulty.aim_lead` = 0 en fácil/normal y **0,5** (medio adelanto) en difícil;
  los eikons usan el adelanto de su dueño.
- **Fijado y cambio de objetivo.** Anillo en el suelo del objetivo (dorado con bordes azules,
  cuatro marcas, pulso, visible a través de todo) + rombo dorado encima. Objetivos válidos:
  cualquier enemigo vivo del grupo `damageable` (rival, su Gólem, su eikon montable **sin jinete**,
  futuros enemigos); el rival va primero. **Tab** fija/suelta (igual que antes), **Z** o la
  **rueda del ratón** cambian de objetivo, botón táctil **«Objetivo»**. Si el objetivo cae, vuelve al rival.
- **Eikons con vida.** Los montables tienen ahora vida propia (`EikonData.max_health`: fénix 50,
  lobo 60, grifo 80) mientras no los monta nadie; si llegan a 0 se retiran antes de tiempo (y se puede
  volver a invocar al llenar el medidor). Montado, los golpes van al jinete.
- **Eikon sin jinete = compañero de ataque.** El Gólem siempre, y los montables cuando no los
  montas (o te bajas), atacan con sus datos de compañero: priorizan **eikons enemigos** y si no
  hay, al luchador rival (igual para el rival). Para volver a montar: acércate y pulsa **Montar**
  (F); si está lejos, «Montar» lo **llama** 3 s y lo montas al llegar.
- **Combo de 3 golpes** (`ComboHit` en `WeaponDef.combo`; remate propio en `CharacterDef.combo_finisher`):
  - Espada y escudo: tajo horizontal → revés → tajo descendente (Paladín). **Caballero**: remate
    *escudazo + estocada*.
  - Espada larga: arco amplio → arco de vuelta → giro devastador (180°).
  - Hacha: hachazo diagonal → revés ascendente → *salto demoledor* (salto visual + arremetida).
  - Dagas: puñalada izq. → puñalada der. (espejo) → doble estocada con arremetida.
  - Lanza: estocada → barrido → embestida (arremetida de 9 m/s).
  Cada golpe tiene clip, daño, alcance, arco, anticipación, ventana de entrada y daño de poise
  (el remate ×1,8–2,5). Clips autorizados en Godot: **al revés** (mismo brazo, sentido contrario),
  **espejo** .l/.r (dagas) y **concatenado** (escudo + estocada). La IA usa los combos (fácil: 2 golpes).
- **Correr hacia atrás fijado (corrección).** Corriendo, si la entrada se aleja más de **110°**
  del rival, el personaje se gira y corre de cara hacia allí (hacia la cámara). Lateral y diagonal
  hacia delante siguen haciendo strafe encarado. Caminando, retrocede mirando al rival.

## Ronda 17 — compromiso a distancia, ballesta, tiro parto, aturdimiento por golpe

| Arma | Tensado (inmóvil) | Recuperación (25 % vel.) | Enfriamiento | Recarga | Daño | Vel. proyectil | Aturdimiento |
|---|---|---|---|---|---|---|---|
| Arco | 0,50 s | 0,40 s | 0,12 s | — | 8 | 32 m/s | 0,25 s |
| Ballesta (nv 3, 500 oro; Arquero/Asesino) | 0,25 s | 0,15 s | 0,05 s | 1,3 s (60 % vel.) | 16 | 46 m/s | 0,45 s |

Disparar a pie cancela el sprint y apaga el modo correr. Montado se dispara sin penalización. Montado, fijado y galopando hacia atrás (>110°), la montura huye y el jinete se gira hacia el objetivo (tiro parto). Con el jinete girado más de 100° no hay cuerpo a cuerpo.

| Arma | Golpe 1 | Golpe 2 | Remate | Pesado |
|---|---|---|---|---|
| Espada y escudo | 0,35 | 0,35 | 0,85 (Caballero 0,9) | 0,6 |
| Espada larga | 0,4 | 0,4 | 1,0 | 0,7 |
| Hacha a dos manos | 0,5 | 0,5 | 1,2 | 0,8 |
| Dagas | 0,18 | 0,18 | 0,55 | 0,45 |
| Lanza | 0,38 | 0,38 | 0,8 | 0,6 |

Llamada del eikon (F a pie): viene corriendo desde cualquier distancia y te monta al llegar, en cuanto estés libre. F otra vez o la muerte del eikon cancelan la llamada.

## Ronda 18 — Atributos (8), escalado de armas y requisitos

Inspirado en el sistema de 8 atributos de los «soulslike» (Elden Ring: Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane), con **nombres y fórmulas propias**. Todo bono es *relativo al reparto inicial del rol*: a nivel 1 el combate es idéntico al de la ronda 17. Cada nivel de personaje da **2 puntos de atributo** (el árbol de habilidades conserva su punto por nivel: sistemas separados). Valores 6–60. Redistribuir es gratis por ahora. Las curvas son por tramos (umbral blando = baja la ganancia por punto).

| Atributo (equivalente) | Efectos | Fórmula (por punto, por tramos) |
|---|---|---|
| Vitalidad (Vigor) | Vida; defensa física | Vida +4 hasta 25, +2 hasta 40, +0,6 después · defensa +0,4 % hasta 30, +0,15 % hasta 50 (tope 15 %) |
| Concentración (Mind) | Energía máx. y regeneración (Golpe sísmico cuesta 30) | Energía 50 +3 hasta 25, +1,5 hasta 40 · regen 5/s +0,25 hasta 30, +0,1 hasta 50 |
| Aguante (Endurance + Robustness) | Estamina, poise, robustez (menos aturdimiento recibido), guardia más firme, carga | Estamina +2,5/+1,2/+0,4 (25/40) · poise +1,5/+0,6 (30/50) · aturdimiento recibido −1,2 %/−0,5 % (30/50, mín. 60 %) · coste de bloqueo −0,8 %/−0,3 % · carga 30 + 1,6/1,0/0,5 (25/60) |
| Fuerza (Strength) | Daño de armas FUE; daño a poise y a la guardia; aturdimiento infligido | escala 2 %/1 %/0,4 % (20/40/60) × coef. del arma · poise/guardia +1,5 %/+0,6 % (30/50) · aturdimiento +1 %/+0,4 % (tope +35 %) |
| Destreza (Dexterity) | Daño de armas DES; velocidad de ataque y disparo; voltereta más barata y con más i-frames | velocidad +0,6 %/+0,2 % (30/50, tope +16 %) · coste voltereta −0,8 %/−0,3 % · i-frames +0,07/+0,03 por punto (redondeado, tope +2) |
| Sabiduría (Intelligence) | Poder mágico (futuros hechizos); escala armas SAB | 100 +4 hasta 30, +2 hasta 50 |
| Devoción (Faith) | Curación (Luz sanadora), resistencia sagrada (eikon/área), daño de armas DEV | curación +3 %/+1,2 % (25/40) · resistencia +0,5 %/+0,2 % (30/50, tope 15 %) |
| Vínculo (sustituye a Arcane) | Daño y vida del eikon, ganancia del medidor | eikon +2 %/+0,8 % (25/40) · medidor +1,5 %/+0,6 % |

Escalado: letra según coeficiente (S > 1,7 · A ≥ 1,3 · B ≥ 0,9 · C ≥ 0,55 · D ≥ 0,25 · E). Daño del arma × (1 + Σ coef·escala(attr)) / (lo mismo con el reparto inicial). Bajo requisito: −30 % y aviso ⚠.

| Arma | Escalado | Requisitos |
|---|---|---|
| Espada y escudo | FUE C · DES D · DEV D | FUE 10 · DES 8 |
| Espada larga | FUE B · DES B | FUE 8 · DES 8 |
| Hacha a dos manos | FUE A · DES E | FUE 11 |
| Lanza | FUE B · DES B | FUE 10 · DES 8 |
| Dagas | FUE E · DES S | DES 12 |
| Arco | FUE D · DES B | DES 10 |
| Ballesta | FUE C · DES C | FUE 8 · DES 12 |

Guardado v5: atributos por ranura; las partidas v4 o anteriores reciben los puntos de su nivel repartidos según el rol. El rival aleatorio recibe atributos de su rol al nivel de tu personaje.

Ronda 18 extra: disparar a pie *suspende* la carrera solo durante tensar/recuperar; si «Correr» sigue activo (o Mayús mantenida) se vuelve a correr solo.

Fuentes: Bandai Namco, «ELDEN RING How-To Guide Part 2 – Advanced Stats»; Fextralife «Stats»; Eldenpedia (wiki.gg) «Stats and Attributes»; Fandom «Weapon Scaling»; Prima Games «Soft caps for each stat and attribute in Elden Ring».

## Ronda 19 — Ficha de personaje, armadura, carga de equipo y Tienda

- Lobby: al entrar no hay pestaña abierta (solo el escaparate). Pestañas: Personaje (ficha), Armas, Eikons, Habilidades, **Tienda**, Inventario. Comprar solo en la Tienda (Armas / Armaduras / Eikons, con confirmación); el resto solo equipa lo que tienes. «Cambio de personaje» eliminado.
- Ficha: nivel, atributos, botón **ATRIBUTOS** (con punto y «+N» si hay puntos), pasiva y habilidades, Vida/Energía/Estamina, Ataque der./izq. (base + bono), Defensa, Absorción por tipo, Resistencias, Equilibrio, Carga con barra y tipo de voltereta, y 7 ranuras (arma principal, secundaria, casco, pecho, guantes, piernas, eikon) con selector y comparación verde/rojo.

Fórmulas (propias; todo relativo a la referencia del rol: nivel 1, reparto inicial y equipo inicial ⇒ el nivel 1 es igual que antes):

| Estadística | Fórmula |
|---|---|
| Ataque (AR) | base (daño ligero o de flecha × daño del rol × habilidades) + bono = base × (multiplicador de atributos − 1); parte sagrada = base × coef. DEV × escala(DEV) |
| Defensa | 20 + 1·(nivel − 1) + 0,2·VIT + 0,15·AGU + 0,15·FUE |
| Multiplicador de defensa | r = ataque / defensa; m = 0,9·r / (r + 0,45), entre 10 % y 90 % |
| Absorción (por tipo: físico, mágico, fuego, rayo, sagrado) | 1 − Π(1 − absorción de cada pieza) |
| Daño recibido | ataque × m(ataque, Defensa)/m(ataque, Defensa_ref) × (1 − Abs)/(1 − Abs_ref) |
| Resistencias | 40 + 1,5·(nivel − 1) + atributo (VIT→Inmunidad, AGU→Robustez, CON→Concentración, VIN→Vitalidad; ×0,4 por encima de 40) + armadura. Efecto = 1 − (R − R_ref)/400, entre 0,7 y 1,15: Robustez → aturdimiento por golpe; Inmunidad → daño de área; Concentración → aturdimiento por rotura de equilibrio/guardia; Vitalidad: sin efecto todavía |
| Equilibrio | poise del rol + Aguante + (poise de la armadura − la del equipo inicial) |
| Carga | peso (armadura + armas) / carga máx. (Aguante): ligero < 30 %, medio < 70 %, pesado < 100 %, sobrecargado |

| Carga | Distancia de la voltereta | I-frames | Recuperación | Regeneración de aguante | Movimiento |
|---|---|---|---|---|---|
| Ligero | ×1,15 | = | = | = | = |
| Medio | ×1 | = | = | = | = |
| Pesado | ×0,8 | −1 | ×1,6 | ×0,8 | ×0,95 |
| Sobrecargado | ×0,35 (tropiezo) | ninguno | ×1,8 | ×0,6 | ×0,6 |

Elementos de los eikons: fénix fuego, lobo mágico, grifo rayo y gólem físico. Las armaduras son 9 conjuntos de 4 piezas: los 5 iniciales de cada rol y 4 a la venta (Seda del viento, ligera; Malla del vigía, media; Túnica de ceniza, ligera con absorción de fuego; Placas del bastión, pesada). La armadura se ve con piezas sencillas teñidas sobre los huesos del modelo de KayKit. Guardado v6: se regala el equipo inicial. El rival lleva el conjunto de su rol a partir del nivel 3.

Fuentes: Fextralife «Calculating Damage», «Equip Load», «Damage Types», «Robustness»; Eldenpedia «Equip Load», «Immunity», «Vitality», «Poise»; Bandai Namco «ELDEN RING How-To Guide Part 1 – Stats».

## Ronda 20 — Audio, estados alterados, herrería e infusiones, botones de cierre

**Audio provisional (CC0).** El autoload `Audio` (`scripts/audio_manager.gd`) crea los buses Master, Música, Efectos e UI. La música pasa de una pista a otra con un fundido cruzado: el lobby, dos temas de combate (uno al azar en cada partida) y las ráfagas de victoria y derrota. Los efectos suenan con un tono aleatorio de ±8 %; en la arena son posicionales (`AudioStreamPlayer3D`). Tienen sonido el tajo (ligero o pesado según el peso del arma), el golpe en carne o en armadura (según la absorción física), el bloqueo, la rotura de guardia, el parry, el fallo, la voltereta, los pasos, el salto y la caída, tensar y soltar el arco, disparar y recargar la ballesta, el impacto de la flecha, la invocación, los especiales de cada eikon (fuego, mordisco de hielo, vendaval, golpe del gólem y Golpe sísmico), el golpe a un eikon, el estallido de cada estado, la compra y la herrería. Los sonidos de interfaz de siempre van ahora por el bus UI. La pestaña **Ajustes** tiene un deslizador por bus y guarda los valores en `user://ajustes.cfg`. Las fuentes y licencias están en CREDITS.md.

**Estados alterados (acumulación al estilo Elden Ring).** Cada golpe suma puntos a una barra. Al llenarse, se dispara el efecto y la barra vuelve a 0 (con 1,5 s de bloqueo). La barra empieza a bajar a 10 puntos/s tras 1,5 s sin acumular. El umbral es 10 + la resistencia de la ficha. Las barras se ven en el HUD (propias y del rival) y sobre la cabeza del rival. Cada estallido suelta partículas del color del estado y tiñe al personaje; con veneno o congelación hay un aura y un tinte que duran lo que dura el efecto.

| Estado | Resiste | Efecto (valores propios) | Elden Ring (referencia) | Fuentes |
|---|---|---|---|---|
| Sangrado | Robustez | 12 % de la vida máx. + 6 de golpe | 15 % + 100/200 (jefes 70 %) | Dagas (18/golpe), infusión Sangrante (20) |
| Veneno | Inmunidad | 2 de daño/s durante 14 s | 0,07 % + 7/s durante 90 s (mortal: 0,14 % + 14/s, 30 s) | Infusión Venenosa (22) |
| Congelación | Robustez | 8 % + 4 de golpe; 12 s con +15 % de daño recibido y aguante al 60 % | 10 % + 30 de golpe; +20 % de daño recibido durante 30 s | Lobo de Hielo (30 por golpe de eikon), infusión Gélida (20) |

A nivel 1, el umbral del rival es de unos 100 (6 golpes de dagas para sangrar). Más Aguante o armadura pesada lo suben: el Bastión lo deja en unos 140. Valores de referencia de Fextralife: «Hemorrhage», «Poison», «Frostbite» y «Robustness». En ER la acumulación tampoco tiene enfriamiento; la nuestra lleva un bloqueo corto para que el 1v1 no se vuelva una cadena de estallidos.

**Herrería.** La pestaña **Herrero** tiene la lista de tus armas, el Ataque antes y después de mejorar, el escalado, el coste y el estado del arma; el botón Mejorar; y seis infusiones.

| Mejora | Piedra | Piedras | Oro |
|---|---|---|---|
| +1 / +2 / +3 | Piedra de forja I | 1 / 2 / 3 | 120 / 280 / 480 |
| +4 / +5 / +6 | Piedra de forja II | 1 / 2 / 3 | 720 / 1000 / 1320 |
| +7 / +8 / +9 | Piedra de forja III | 1 / 2 / 3 | 1680 / 2080 / 2520 |
| +10 | Piedra de forja antigua | 1 | 3000 |

Cada nivel da +6 % de daño base (+10 = +60 %) y +4 % a los coeficientes de escalado, así que mejorar luce más cuantos más atributos tengas. La acumulación de estado sube un 3 % por nivel (4 % la de la infusión). Las piedras se ganan en cada partida (al ganar, 2 de nivel I, +1 de nivel II desde el nivel 4 y +1 de nivel III desde el 7; al perder, 1 de nivel I) y se compran en Tienda → Materiales (150 / 350 / 700 / 2000 de oro; de nivel de cuenta 1 / 3 / 5 / 8). En ER son 2/4/6 piedras por nivel hasta +25 con la piedra antigua al final (Fextralife «Smithing Stones», «Upgrades»); aquí está comprimido a +10.

| Infusión | Efecto | Coste |
|---|---|---|
| Normal | sin cambios | gratis (quita la infusión) |
| Pesada | FUE ×1,4 + 0,3; DES ×0,3; daño ×1,04 | 500 de oro |
| Afilada | DES ×1,4 + 0,3; FUE ×0,4 | 500 de oro |
| Sangrante | +20 de sangrado/golpe; daño ×0,92 | 500 de oro |
| Venenosa | +22 de veneno/golpe; daño ×0,92 | 500 de oro |
| Gélida | +20 de congelación/golpe; daño ×0,92 | 500 de oro |

Las armas se mejoran en una copia del recurso (`Smithing.effective`); +0 normal es exactamente el arma de antes, así que el nivel 1 no cambia. El rival lleva su arma a +⌊(nivel − 1)/2⌋. Guardado v7 (`[herreria]`: niveles, infusiones y materiales). Al migrar de v6 o antes, las armas quedan a +0 y se regalan 3 Piedras de forja I.

**Cierre de paneles.** Personaje, Armas, Eikons, Habilidades, Herrero, Tienda, Inventario y Ajustes tienen un «✕» arriba a la derecha. La pantalla de Atributos y el selector de equipo tienen el suyo. Esc y el botón Atrás de Android cierran lo que esté encima: la confirmación, luego Atributos, luego el selector y luego la pestaña. Al cerrar se vuelve al escaparate sin ninguna pestaña elegida.

Pruebas nuevas: `test_status.gd`, `test_smithing.gd` (incluye la migración de v6 a v7) y `test_ui_audio.gd` (botones de cierre, Esc y Atrás, buses, volúmenes guardados y efectos 3D).

## Ronda 21 — Montado sin parry, objetivo contextual, magia de eikon y artes de arma

**Montado sin parry.** Montado, el parry no existe: el botón táctil «Parry» se oculta y la tecla Q no hace nada (`Fighter.parry()` lo rechaza también). Al desmontar vuelve.

**Botón «Objetivo».** Solo aparece cuando hay más de un objetivo válido para fijar (rival + eikon enemigo, montura sin jinete, etc.). Con 0 o 1 objetivos se oculta (`PlayerController.can_cycle_target()`).

**Botones Eikon y Montar.** «Eikon» pasa a ser el botón de combate más a la izquierda y solo aparece cuando se puede invocar (medidor lleno, sin eikon activo, sin aturdir) o cuando vas montado en tu eikon (su Especial). «Montar» solo aparece con un eikon activo en la arena; montar/desmontar el caballo sigue en la tecla F.

**Magia de eikon.** Eikons → «Hechizos»: ranuras que se tocan para cambiar de hechizo (equipar uno que ya está en otra ranura los intercambia).

| Hechizo | Eikon | Tipo | Efecto | Energía | Enfr. | Escala |
|---|---|---|---|---|---|---|
| Chispa ígnea | Fénix | proyectil | 9 de fuego | 14 | 1,4 s | Sabiduría |
| Aliento helado | Lobo de Hielo | cono 5,5 m / 60° | 6 de hielo + 30 de congelación | 20 | 4 s | Sabiduría |
| Saeta del vendaval | Grifo | proyectil rápido | 7 de rayo | 12 | 1,1 s | Sabiduría |
| Piel de piedra | Gólem | protección | 6 s: −15 % daño, +50 % equilibrio | 24 | 12 s | Devoción |

Ranuras: 2 base, +1 con Sabiduría o Devoción ≥ 18, +1 con ≥ 30 (máx. 4): los magos se apoyan más en los eikons. Solo a pie: X lanza, T pasa a la siguiente ranura (táctil: «Hechizo» y «↻»). El lanzamiento inmoviliza 0,25–0,5 s y un golpe que aturde lo interrumpe (la Energía se pierde).

**Artes de arma (colección intercambiable).** Armas → «Arte» cambia el arte del arma cuerpo a cuerpo equipada entre las que poseés; Tienda → Artes vende las nuevas. Se usan con Habilidad (G) si tu personaje no tiene habilidad propia; el Berserker conserva el Golpe sísmico.

| Arte | Efecto | Energía | Enfr. | Precio |
|---|---|---|---|---|
| Estocada impulsada | embestida hacia el objetivo, x1,5 de daño | 18 | 5 s | inicial |
| Torbellino | giro de 360°, radio 3 m, x1,2 | 22 | 7 s | 300 de oro |

Curación (lágrimas) queda pospuesta por decisión del usuario. Guardado **v8**: `spells` por ranura de personaje y `[artes]` (colección y arte por arma). Al migrar desde v7 se equipa el hechizo de tu eikon y la Estocada impulsada. La IA del rival todavía no usa hechizos ni artes.

Prueba nueva: `test_magic.gd` (parry montado, botón Objetivo, ranuras, hechizos en combate, artes, Tienda, persistencia y migración v7→v8).

## Ronda 22 — Ajustes del HUD táctil

- **Eikon** pasa al lado izquierdo, encima del joystick de movimiento. Sigue las mismas reglas: solo aparece cuando se puede invocar, y montado en tu eikon dice «Especial».
- **Arte / Habilidad** se oculta montado (y la tecla G no hace nada montado). Vuelve al bajar.
- Flujo nuevo: el proyecto vive en GitHub (`origin`, rama `master`). Para probar: `git pull` y Play en Godot 4.7.

## Ronda 23 — Búfer de entrada y sensación de juego

**Búfer de entrada** (`PlayerController`). Si pulsás una acción cuando todavía no se puede hacer (en mitad de un golpe, de una voltereta, de un cambio de arma, de un salto o aturdido), se guarda y sale en el primer fotograma en que sea posible, siempre que no hayan pasado más de **0,4 s** desde la pulsación (`BUFFER_WINDOW`; ajustable de 0,1 a 1,5 s en **Ajustes → Controles → Búfer**, se guarda en `user://ajustes.cfg`).
- Cubre: ataque ligero y fuerte (y pasos de combo), disparo, voltereta/dash, cambio de arma, hechizo, Habilidad/Arte, parry, salto y montar/desmontar. Igual a pie y montado (montado no se guardan parry ni Arte porque no existen).
- Gana la última pulsación, salvo que la guardada sea **esquivar**: la esquiva tiene prioridad.
- Un golpe que te aturde vacía el búfer; lo que pulses **durante** el aturdimiento sí se guarda y sale al recuperarte.
- El ligero pulsado durante un golpe se integra al combo (no dispara un ataque de más). Al reintentar, una esquiva no convierte la anticipación del siguiente ligero en estocada con dash.
- No hay objetos consumibles todavía, así que «usar objeto» queda para cuando existan.

**Mejoras de sensación**
1. **Hit-stop:** los golpes fuertes y los castigos (golpear a alguien en recuperación o aturdido) congelan el juego 0,08 s; un parry logrado, 0,06 s. Es en tiempo real y siempre se restablece (`Arena.hitstop_enabled`).
2. **Temblor de cámara afinado:** escala 0,3 por impacto y caída exponencial; los golpes fuertes y el parry ahora también sacuden. Golpe seco, sin temblor largo.
3. **Giro hacia el objetivo al atacar:** con objetivo fijado el golpe se encara siempre al objetivo (antes solo si estaba delante); sin fijar, sigue igual (solo si está delante y cerca).
4. Ya existían y se mantienen: cancelar la recuperación del golpe con voltereta en su segunda mitad, voltereta en la dirección del joystick aunque esté fijado, búfer de estocada tras los i-frames y demora de 0,6 s antes de recuperar aguante.

El equilibrio a nivel 1 no cambia (no se tocó daño, costes ni tiempos de acciones). Prueba nueva: `test_buffer.gd`.

## Ronda 24 — «El intercambio» (Fase 1 de la hoja de ruta, sin curación)

**1. Contraataque.** Golpear al rival mientras está en anticipación o en pleno golpe (o lanzando un hechizo) hace ×1,15 de daño (×1,25 con perforante) y ×1,3 de daño de equilibrio. Aviso «¡Contraataque!».

**2. Subtipos físicos y equilibrio por arma.** Cada arma tiene subtipo (`WeaponDef.phys_type`) y cada golpe de combo puede definir el suyo (`ComboHit.phys_type`; las estocadas son perforantes). El subtipo escala la absorción física de la armadura según su clase de peso (la referencia del rol usa el mismo factor, así que con el equipo inicial el nivel 1 no cambia).

| Arma | Subtipo | Equilibrio (x) |
|---|---|---|
| Espada y escudo | estándar | 1,0 |
| Espada larga | cortante | 1,2 |
| Hacha a 2 manos | contundente | 1,8 |
| Lanza | perforante (estocadas) | 1,0 |
| Dagas | cortante | 0,6 |

| Absorción física × | estándar | contundente | cortante | perforante |
|---|---|---|---|---|
| Ligera | 1,0 | 1,15 | 0,75 | 0,9 |
| Media | 1,0 | 1,0 | 1,0 | 0,9 |
| Pesada | 1,0 | 0,7 | 1,25 | 1,1 |

Equilibrio extra por subtipo: contundente ×1,15, cortante ×0,95.

**3. Contra de guardia.** Atacar (ligero o fuerte) en los 0,35 s después de bloquear un golpe lanza un fuerte rápido (anticipación ×0,6), con súper-armadura y ×2 de daño de equilibrio. Sin botón nuevo: es el mismo botón de ataque.

**4. Postura y crítico frontal.** Además del equilibrio hay **postura** (equilibrio ×3,5, unas dos cadenas completas sin pausa) que solo se recupera tras 2,5 s sin recibir golpes (12/s). Al vaciarse, el luchador a pie queda **expuesto 1,2 s**. Atacar de frente a menos de 2,6 m lanza un **crítico**: 0,8 s de animación (provisional, el golpe sísmico) con el atacante invulnerable, ×2,2 del daño fuerte del arma, hit-stop. Avisos «¡Postura rota!» y «¡Crítico!».

**IA.** Aprovecha tu postura rota con un crítico (fácil 50 %, normal 85 %, difícil 100 %), usa la contra de guardia tras bloquear (15 / 45 / 75 %), deja de presionar con la postura baja y, como novedad de la Fase 2, a veces **retrasa** su primer golpe para romper el ritmo del parry (20 / 35 / 50 %, hasta 0,35-0,55 s).

**Fase 2 adelantada.**
- **Fuerte cargado:** mantener el ataque después de que salga el fuerte lo retiene hasta 0,6 s: hasta +40 % de daño y equilibrio.
- **Ataque corriendo:** atacar mientras corrés a pie = embestida en la dirección de carrera.
- **Guardia alzada:** el aguante se regenera a la mitad.

**Pendiente:** curación (pospuesta), animación propia del crítico y del ataque corriendo (necesitan clips), barra de postura en el HUD, estabilidad propia de cada escudo, crítico montado. La contra de guardia y el crítico son solo a pie.

Prueba nueva: `test_exchange.gd`.

## Ronda 25 — Cámara orbital, 8 direcciones y la Estocada de jefe

**Pilar de diseño nuevo** (arriba de `docs/ELDEN_RING_REFERENCIA.md`): mitad PvP, mitad jefe de Dark Souls; habilidades de jefe imparables e invulnerables, pero siempre telegrafiadas: el reto es el ritmo, no los reflejos.

### Diagonal hacia atrás (arreglado)
A pie (libre o fijado) y montado, las 8 direcciones andando y corriendo. Causa: con `dot < -0,6` el personaje retrocedía en vez de girar, y la cámara vieja seguía su orientación (giraba sin fin). Ahora sólo retrocede montado, sin correr y con atrás casi puro (`dot < -0,92`); si no, gira hacia la entrada. Nota: S+A+Shift en algunos teclados no registra las tres teclas (ghosting de hardware); **V** alterna correr.

### Cámara orbital (`scripts/camera_rig.gd`)
- **PC:** clic derecho + arrastrar (por defecto, no choca con la UI). Opcional en Ajustes «Ratón capturado (PC)»; **Esc** lo libera.
- **Android:** arrastrar en la mitad derecha, fuera de los botones (+12 px).
- El movimiento es relativo a la cámara.
- **Fijado:** la cámara se pone detrás del jugador mirando al objetivo (distancia 8 + 0,15·d, a la altura del hombro). Un tirón horizontal (140 px en 0,25 s) cambia de objetivo.
- **Libre:** se recentra tras 1,5 s sin tocar la cámara mientras avanzas.
- La inclinación se limita a −0,15…1,1 rad; la distancia es 9,5 m. Choca con los pilares y el muro (no los atraviesa).
- **Ajustes:** sensibilidad 0,2–3, Invertir Y y Ratón capturado (se guardan).

### Estocada de jefe — tecla **B** / botón táctil **«Jefe»**
Tiene un botón propio, no comparte hueco con Habilidad/Arte: es el hueco para futuras habilidades de jefe. Sólo a pie y con espada; pasa por el búfer. El botón se oscurece y muestra los segundos de enfriamiento.

| Parámetro | Valor |
|---|---|
| Carga (pose, brillo de hoja 0,5→6, partículas, sonido creciente) | 2,0 s |
| Sigue al objetivo / luego fija la dirección | 1,2 s / 0,8 s |
| Embestida fija | 7,5 m a 24 m/s (para al impactar; si no alcanza, al aire) |
| Alcance / arco | 1,6 m / 35° |
| Daño | 1,6 × pesado del arma × multiplicador |
| Postura | ×3 (no se puede parar; perforante) |
| Invulnerable e imparable | carga + embestida |
| Recuperación castigable | 1,0 s si acierta / 1,4 s si falla |
| Enfriamiento / aguante | 14 s / 25 |

**IA:** deja de bloquear y atacar, rueda en perpendicular con un error de tiempo y luego castiga. También la usa a 3,5–8,5 m si está de cara.

| Dificultad | uso por pensamiento | prob. de esquivar | error de tiempo |
|---|---|---|---|
| Fácil | 0,015 | 0,30 | 0,25 s |
| Normal | 0,03 | 0,60 | 0,12 s |
| Difícil | 0,05 | 0,85 | 0,05 s |

### Paso adelante en los ataques (estilo ER)
Cada ataque a pie avanza (en `WeaponDef.step_light` / `step_heavy`). El paso se reparte entre el 45 % final de la preparación y la ventana activa. El pesado cargado suma +0,8 m (no se mueve mientras carga). Tiene **magnetismo** hacia el objetivo fijado o cercano de delante: se detiene al contacto (radio + 0,8 m), no lo atraviesa y respeta las colisiones. El daño no cambia (el nivel 1 sigue igual).

| Arma | ligeros 1/2/3 (m) | pesado (m) |
|---|---|---|
| Dagas | 0,6 / 0,6 / 0,9 | 1,0 |
| Espada y escudo | 0,9 / 0,9 / 1,2 | 1,4 |
| Espada larga | 1,2 / 1,2 / 1,5 | 1,8 |
| Lanza | 1,4 / 1,4 / 1,8 | 2,0 |
| Hacha a dos manos | 0,8 / 0,8 / 1,0 | 2,4 |

Las estocadas en carrera y los golpes con salto conservan su propia embestida (mayor).

**Pruebas:** `tests/test_round25.gd` comprueba:
- las 8 direcciones (a pie libre, a pie fijado, montado);
- la órbita, el límite de inclinación, invertir Y, la colisión con pilar y muro, las zonas táctiles, la cámara en fijado, el tirón y que los ajustes se guardan;
- la Estocada: carga, invulnerabilidad, que no se interrumpe, el seguimiento y luego la dirección fija, la esquiva lateral, los 7,5 m al aire, que para al impactar, la recuperación castigable y el enfriamiento;
- que la IA la esquiva y la usa;
- el paso por arma y el magnetismo.

## Ronda 26 — Rendimiento (sin cambios de jugabilidad)

| # | Cambio | Dónde |
|---|---|---|
| 1 | Los modelos de eikon y montura se piden en hilo al empezar la arena (`ResCache`); al llegar se calienta una instancia oculta 2 fotogramas (sombreadores y caché). Invocar ya no carga nada. | `scripts/res_cache.gd`, `arena._warm_eikons`, `eikon.gd`, `mount.gd` |
| 2 | Sombras en móvil: atlas 2048, filtro suave bajo, 2 cortes y 40 m de distancia (solo móvil; PC igual). | `project.godot`, `arena.gd` |
| 3 | Caché de materiales en `MeshUtil.mat()`. Quien modifica uno usa `MeshUtil.own()` (copia propia): hoja, cuerpo, anillo de fijado, suelo del lobby. | `mesh_util.gd` |
| 4 | El muro circular es un solo `StaticBody3D` con 56 formas que comparten la misma caja (antes, 56 cuerpos). | `arena.gd` |
| 5 | La separación entre luchadores usa la lista estática `Fighter.all`, sin pedir el grupo en cada paso de física. | `fighter.gd` |
| 6 | Grupo de 8 reproductores `AudioStreamPlayer3D` reutilizables. Si los 8 suenan a la vez, se crea uno temporal como antes, así que ningún sonido se corta. | `audio_manager.gd` |
| 7 | El HUD solo reconstruye un texto cuando cambia lo que muestra (arma y tiempo del eikon, botones Jefe, Hechizo, Correr y Eikon, estados). | `hud.gd` (`_changed`) |
| 8 | Se quitó `_ring` del eikon, que no se usaba. | `eikon.gd` |

**Medido** con `tests/perf_probe.gd` (headless, en la CPU de la caja; 3 ejecuciones antes y 6 después):

| Métrica | Antes | Después |
|---|---|---|
| `summon()` del jugador (eikon montable) | 4,0–4,2 ms | 1,9–2,4 ms |
| `summon()` del rival (eikon con modelo nuevo) | 7,0–10,0 ms | 1,5–3,3 ms |
| Nodos en combate | ~500 | ~447 |
| `StaticBody3D` | 63 | 8 |
| Materiales únicos | 66–73 | 43–50 |

- El tiempo de física medido (~1,5–3 ms) tiene demasiado ruido en la caja para ver diferencias.
- El tiempo de GPU y las sombras no se pueden medir sin pantalla: hay que medirlos en el dispositivo.

## Ronda 27 — Animaciones Mixamo (biblioteca reapuntable)

Se importaron **99 animaciones de Mixamo** (vía Souls-Combat; solo animaciones) en `assets/animations/mixamo/`:

| Grupo | Animaciones |
|---|---|
| paladin | 15 |
| greatsword | 51 |
| akai | 18 |
| magic | 13 |
| xbot | 2 |

- Se importan como **AnimationLibrary**, reapuntadas al esqueleto humanoide de Godot (`SkeletonProfileHumanoid`, `%GeneralSkeleton`) con tres `BoneMap` según el rig de origen.
- Hay bibliotecas `lib_*.res` listas para cualquier modelo humanoide propio (reapuntado con un BoneMap humanoide).
- Lista, origen, archivos no importados y mapeo sugerido a las acciones del juego: `assets/animations/mixamo/README.md`.
- **Aún no se usan en el juego** (los modelos actuales son KayKit/Quaternius).
- Herramienta: `tools/build_mixamo_libs.gd`. Prueba: `tests/test_mixamo_anims.gd`.

## Ronda 28 — Animaciones Mixamo en el juego (rig KayKit)

Las animaciones Mixamo de la Ronda 27 se **reapuntan al esqueleto KayKit**. Lo comparten Caballero, Bárbaro/Berserker, Mago, Asesino/Pícaro, Paladín y Arquero, así que todos las usan.

**Cómo funciona:**
- `tools/retarget_kaykit.gd` reapunta cada clip con un delta de rotación global por hueso: `D = Gpose · Grest⁻¹` en el humanoide, aplicado al reposo KayKit. El resultado es `assets/animations/mixamo/lib_kaykit.res` (24 clips).
- **Movimiento de raíz:** se elimina la traslación horizontal de las caderas y solo se conserva la altura, escalada. El desplazamiento lo siguen dando el juego (pasos de ataque, embestidas, voltereta), así que las hitboxes y las pruebas no cambian.
- Los ataques se recortan para que el **pico de velocidad de la mano derecha** caiga en `CONTACT` (0,42), igual que los clips KayKit. Así el golpe visual coincide con la ventana activa.
- `KnightVisual` añade la biblioteca `mx` y sustituye clips por tablas (`MX_COMMON`, `MX_WEAPON`, `MX_LOCO`). Si un clip no existe, se usa el de KayKit.

| Acción (estado) | Clip | Origen |
|---|---|---|
| Espada y escudo: ligero 1 / 2 / 3, pesado | `sns_light0/1/2`, `sns_heavy` | xbot Sword And Shield Slash (1), paladin Sword And Shield Attack (2) / Attack, Sword And Shield Slash |
| Espada larga: ligero 1 / 2 / 3, pesado | `gs_light0/1/2`, `gs_heavy` | great sword slash, slash 5, slash 4, attack |
| Hacha a dos manos: ligeros / pesado | `gs_light1/0/2` / `axe_heavy` | great sword slash 5/1/4 / high spin attack |
| Guardia (espada larga, hacha) | `gs_block` (bucle) | great sword blocking |
| Reposo (espada larga, hacha) | `gs_idle` | great sword idle |
| Voltereta hacia delante | `roll_f` | akai Sprinting Forward Roll InPlace |
| Golpe recibido / aturdido | `hit` / `stun` | great sword impact 4 / impact 2 |
| **Rotura de postura** (nuevo estado `stance_break`) | `stance_break`, escalado a 1,2 s | akai Tripping |
| **Estocada de jefe: carga** (nuevo estado `boss_charge`, 2 s) | `boss_charge` | paladin Sword Scream (0–2 s) |
| **Estocada de jefe: embestida** (`boss_lunge`) | `boss_lunge`: el golpe del clip cae al final de la embestida | great sword slide attack |
| Salto con impacto (`slam`) | `jump_slam` | great sword jump attack |
| Hechizos (nuevo estado `cast`, ajustado a la duración del lanzamiento) | `cast` | Standing 1H Magic Attack 01 |
| Strafe caminando | `strafe_a` (izquierda), `strafe_b` (derecha) | great sword strafe, strafe 2 |
| Muerte | `death_1h` (espada y escudo, dagas), `death_2h` (espada larga, hacha, lanza) | akai Sword And Shield Death / two handed sword death |

**Se queda con KayKit, porque encaja mejor o porque Mixamo no tiene un equivalente:**
- arco y ballesta: apuntar, disparar, recargar;
- dagas y lanza: sus ataques;
- parada, golpe en guardia;
- voltereta lateral y hacia atrás;
- andar, correr y strafe corriendo;
- salto;
- ataque en carrera (`Dash_Strike`, compuesto);
- montar (Sit_Chair_Pose y RidingPose);
- cambiar de arma.

La contra de guardia usa los clips del combo de cada arma, igual que antes.

**Pruebas:** `tests/test_round28.gd` comprueba:
- que las pistas son huesos KayKit y no hay traslación horizontal;
- que cada personaje y arma usa los clips correctos (el arquero conserva los suyos);
- que la carga, la embestida, la rotura de postura y el hechizo usan sus estados.

`tests/test_defs.gd` se adaptó a los nuevos clips del combo. Hoja de poses para revisar a ojo: `tests/posesheet.gd`.

## Ronda 29

- **Personajes con nombre y selector.** Al empezar y al comprar un personaje (nivel de cuenta 3 + 2500 oro) hay que escribirle un nombre (máx. 16). El nombre se guarda (partida v9, sección `personajes`: nombres, desbloqueados y equipo/XP/habilidades/atributos de cada uno) y se ve en el lobby y en el HUD. En el lobby se cambia de personaje con ‹ ›, las flechas ←/→ o deslizando en Android. Un bloqueado se puede ver, y al pulsar Jugar se ofrece comprarlo.
- **Animaciones Mixamo en todos.** Los 5 personajes (caballero, berserker, asesino, arquero, paladín) usan el rig KayKit y comparten los clips comunes (voltereta, golpe, aturdido, rotura de postura, carga/embestida de jefe, hechizo, salto demoledor). Nuevo: las dagas (asesino y el arma cuerpo a cuerpo del arquero) usan tajos de espada a una mano y guardia `light_idle`, y espada y escudo usa `sns_idle`. La lanza mantiene sus estocadas KayKit.
- **Suelo, muro y pilares garantizados.** `Fighter._clamp_world()` se ejecuta después de cada movimiento (andar, volteretas, estocadas, arremetidas, embestida de jefe, empujones). Ningún personaje baja de y=0, sale del muro ni entra en un pilar. Las monturas tampoco bajan del suelo. Además, `KnightVisual.foot_lift()` eleva el modelo si un clip mete los pies bajo el suelo.
- **Salto comprometido.** La trayectoria se fija al despegar: no hay control ni giro en el aire.
- **Regla soulslike aplicada.** El ataque solo sigue al objetivo durante la anticipación. En los frames activos y en la recuperación su dirección queda fijada.
- **HUD del rival.** Solo muestra la vida y los estados, sin aguante ni barra de eikon.
- Pruebas: `tests/test_round29.gd`, más ajustes en test_purchase, test_first_run, test_magic/test_smithing (versión de partida) y test_round25 (el rival ya no puede colocarse fuera de la arena).

## Ronda 30

- **Movimiento fluido.**
  - Teclado: el vector de entrada se interpola en unos 0,08 s girando, así que W→D pasa por las diagonales.
  - Stick (mando o táctil): zona muerta radial y curva de respuesta (`PlayerController.shape_stick`). Al girar el stick se dibuja un círculo perfecto.
  - A pie se gira con velocidad angular fija (`Fighter.TURN_RATE_DEG` = 800°/s).
  - La velocidad gira hacia la dirección deseada sin caer a cero (`_steer_velocity`); solo frena en inversiones de más de 150°. El cuerpo se inclina hacia el giro.
- **Propiedad de personajes.**
  - Al empezar eliges UNO y le pones nombre.
  - Los demás se consiguen en la pestaña **Reclutar**: clase y nombre obligatorio, con coste de oro y nivel de cuenta.
  - El selector ‹ › solo recorre tus personajes; no hay escaparate de bloqueados. Las flechas son pequeñas y están junto al nombre, fuera del panel derecho.
  - Solo se cambia de personaje en el lobby.
- **Ficha personal (pestaña Personaje).** Nombre con título, nivel, tiempo jugado, victorias/partidas, estadísticas y equipo.
- **Menú con Esc (≡ en Android).** Continuar, Ajustes (cámara, volumen, invertir Y) y Salir al lobby. **No pausa el juego**: mientras está abierto tu personaje se queda quieto y en guardia, y el ratón queda libre.
- **Anillos (2 ranuras) y talismanes (3 ranuras)**, sin modelo 3D. Se compran en Tienda → Accesorios y se equipan en la ficha. Efectos: daño por subtipo físico, equilibrio, aguante al desviar, fotogramas de invulnerabilidad en la voltereta, menos gasto de aguante y medidor de eikon más rápido. Se guardan por personaje.
- **Títulos.** Se ganan con la ficha (victorias, partidas, nivel, horas). Uno por personaje; se muestra junto al nombre (lobby y HUD) y da una bonificación pequeña.
- **Grabado del arma.** Es el nivel de mejora de la herrería (+1…+10). Desde **+5** la hoja brilla, con más intensidad cuanto más alto es el nivel.
- **Partida v10.** Migración desde v9: sin accesorios, ficha y títulos a cero; personajes y equipo intactos.
- **Recursos de prueba.** `GameState.DEBUG_GRANT = true` (en `scripts/game_state.gd`) da una vez por perfil 500 000 de oro, 5000 cristales, piedras de forja (60/60/60/15) y todos los accesorios. **Ponlo en `false` antes de publicar.** También se puede forzar con `godot -- --debug-grant` o desactivar con `-- --no-debug-grant`. Las pruebas automáticas no lo reciben.
- **Erika.** No hay ningún modelo «Erika» en el proyecto, en su historial ni en el repositorio de origen de las animaciones, así que no se añadió ese personaje (ver informe).
- El movimiento fluido es del jugador (`Fighter.fluid`); la IA mantiene su conducción clásica (con la fluida rodeaba por la espalda demasiado: test_ai 23–25 %; así vuelve a 12 %).
- Pruebas: `tests/test_round30.gd`.

## Ronda 31
- **Aturdimiento en 3 niveles** acumulado (ventana de 3 s, ningún golpe aturde solo): tambaleo (se sale rodando), aturdido, derribo con animación de levantarse, inmunidad y ×0,85 de daño. Súper-armadura por ataque (fuertes cargados, habilidades).
- **Habilidades de jefe** (pestaña «Jefe», máx. 3; B usa, N cambia; sin recargas, cuestan aguante/maná/vida): Estocada (persigue, solo se esquiva rodando, 12 m), Carga en área, Ráfaga de 3 tajos, Escudo de maná, Combo de la pausa falsa, Salto con caída. Enciclopedia en la pestaña; la IA las usa y reacciona. Guardado v11.
- **Arcos**: mantener = disparo cargado (arco potente, ballesta triple).
- **Calibración**: velocidad de ataque hasta +25 % con curva más cara; la ficha la muestra.
- `docs/design.md` reescrito como referencia. Pruebas: `tests/test_round31.gd`.

## Ronda 32
- Fuerte cargado: la pose de carga aparece desde que se mantiene el botón.
- Combo falso mucho más lento (golpes a ~3 s, pausa falsa final), cada golpe avanza ~3 m siguiendo al rival.
- Ráfaga: espectros de tajo dorados en diagonal, más anchos, cada 0,9 s y 100 % teledirigidos; solo la voltereta los esquiva. La IA rueda cada uno.
- Salto con caída sin marca en el suelo; la IA reacciona al verle bajar.
- Arco/ballesta: mantener tensa sin disparar, dispara al soltar; cargado ≥ 0,9 s con brillo dorado y sonido.
- Botón ▶ en el HUD para cambiar la habilidad de jefe. Pruebas: `tests/test_round32.gd`.

## Ronda 35 — Primer paso del Duelo de Campeones

- La IA equipa el hechizo de su Eikon y un arte de arma; usa proyectiles a media distancia, conos de cerca, mejoras cuando está herida, estocadas para entrar y giros si el jugador se acerca.
- Se definió una escalera de cinco campeones con personaje, arma, Eikon, hechizo y tres habilidades de jefe fijos. El lobby permite activar el modo y guarda el avance de la escalera.
- Cada campeón empieza con dos habilidades. Al bajar del 50 % de vida, desbloquea la tercera, recibe 0,85 s de invulnerabilidad de transición y 9 s de Furia; un destello teñido por su Eikon, breve hitstop, sacudida de cámara y aviso anuncian la fase. Gorath invoca al Gólem.
- La primera victoria contra cada campeón entrega un Sello de Eikon único. El primer sello se equipa automáticamente; desde Eikons se puede cambiar o quitar. El sello modifica daño, duración, vida o ritmo de ataque de la invocación.
- Cambiar o quitar un sello guarda el loadout al instante. El aura de la Fase II se limpia al iniciar la siguiente ronda, y el resultado indica si el nuevo sello quedó equipado automáticamente.
- Cada campeón usa ajustes tácticos propios además de la dificultad general: distancia, velocidad de rodeo, frecuencia de recursos, compromiso y presión de Fase II. Vael presiona de cerca, Lyra juega alrededor de las respuestas defensivas, Gorath se compromete con ataques pesados, Nysera prioriza movilidad y recursos a distancia, y Draven acelera el cierre.
- El lobby muestra el campeón actual, su introducción y la recompensa; el botón principal nombra el enfrentamiento. La pantalla de victoria anticipa al próximo campeón y su sello.
- Pendiente del bloque: afinar los valores de cada perfil con observaciones de combate en fácil, normal y difícil.

## Fase E — Claridad y respuesta del combate (rondas 42–43)

- Los ataques cuerpo a cuerpo dibujan una estela 3D continua entre la empuñadura y la punta de la espada, teñida por la infusión; las habilidades de jefe pueden darle un color propio.
- El HUD muestra una barra fina de postura para cada luchador y cambia a tonos cálidos cuando queda menos del 25 %. Los contraataques, críticos, roturas de postura y roturas de guardia generan avisos flotantes junto al luchador involucrado.
- Los contraataques y críticos tienen respuesta de audio; las roturas conservan el sonido de guardia rota.
- Los críticos frontales y «Presa verdugo» activan durante 0,8 s una aproximación de cámara con FOV reducido y encuadre de perfil de ambos luchadores.

## Fase F — Controladores internos (rondas 44–45)

- `FighterCombat` agrupa el inicio, encadenamiento, actualización y resolución de los ataques cuerpo a cuerpo, el parry, la postura y los críticos.
- `FighterMount` agrupa montar/desmontar, selección de montura cercana, daño y recuperación de postura de montura.
- `FighterMagic` agrupa hechizos, sus tiempos de recarga y las artes de arma. `Fighter` conserva sus propiedades y métodos fachada para mantener los puntos de integración existentes.
- «Ráfaga» reproduce un tajo del personaje por cada proyectil; la fase de contacto de cada animación coincide con la emisión del corte espectral.
- La preparación para PvP queda limitada a esta modularización: faltan reglas de combate, salas y sincronización de red por definir antes de implementar un modo PvP.
- A pie, la aceleración normal es más rápida; el impulso de carrera entra con una respuesta exponencial de 0,14 s y cae con una cola más suave de 0,28 s al soltarla. El frenado de dirección sigue siendo ágil; las monturas mantienen su aceleración propia y comparten la entrada/salida gradual del galope.
