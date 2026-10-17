# HANDOFF — Arena de Eikons (para Grok Build)

Proyecto de Jonathan: luchador de arena 1v1 en **Godot 4.7.2** (GDScript), offline contra IA y online P2P con rollback. Vas a seguir el desarrollo **en local, en su PC Fedora Linux**. Repo: `https://github.com/JonathanLazarte/arena-game` (rama `master`, base de este handoff: `3fb3bd4`; fase 8 completa en `6f4d0ab`+).

Leé antes de tocar nada: `README.md` (historial por rondas), `docs/design.md` (reglas duraderas y números), `docs/netcode.md` (online, §9–§15), `docs/determinism_audit.md`, `server/README.md`, `server/DEPLOY.md`. Para crear habilidades de jefe nuevas (o pedírselas a un modelo): `docs/abilities_guide.md` (esquema JSON objetivo, validación, ejemplos y «estado actual vs esquema»).

---

## 1. Mapa de carpetas
| Ruta | Qué hay |
|---|---|
| `project.godot`, `export_presets.cfg` | Proyecto y presets (Android, Windows, Linux) |
| `scenes/` | `arena.tscn`, lobby, etc. |
| `scripts/arena.gd` | Arena (muro circular, pilares), rondas, cámara; crea SimMatch (offline con SimAI, online con NetMatch) |
| `scripts/combat/` | **Solo vista + datos**: `fighter.gd` (~1300 líneas: estadísticas que hornea SimParams, modelo/animación/sonido; SimView escribe su estado), `fighter_magic.gd` (consultas de hechizos), `boss_abilities_ext.gd` (datos), `mount.gd`/`eikon.gd` (títeres que coloca SimWorld), `projectile.gd`/`ground_aoe.gd` (solo constantes de arena), `status_fx.gd` |
| `scripts/ai/` | `ai_difficulty.gd` (perfiles; la IA es `net/sim/sim_ai.gd`) |
| `scripts/data/` | Datos: `stun_rules.gd`, `boss_abilities.gd`, `attributes.gd`, defs de armas/monturas/eikons |
| `scripts/ui/` | `hud.gd`, `touch_stick.gd`, `lobby.gd`, `first_run.gd`, ficha, árbol de habilidades, tienda… |
| `scripts/game_state.gd` | Progresión, guardado, `DEBUG_GRANT` |
| `net/` | Prototipo rollback (`rb_sim/rb_session/rb_engine/rb_harness`) |
| `net/sim/` | **La jugabilidad entera** (offline y online, ver §3); `sim_ai.gd` IA; `sim_world.gd` vista de eikons/marcas/proyectiles |
| `net/online/` | Transporte, lobby online, overlay, regiones, loadout |
| `server/` | Relay Node 20 + TypeScript (`src/relay.ts`, `src/index.ts`, `test/`, `Dockerfile`, `deploy/` compose, `fly.toml`) |
| `tests/` | Tests headless `test_*.gd`, bench, capturas |
| `tools/` | `build_mixamo_libs.gd`, `retarget_kaykit.gd` |
| `assets/` | Modelos, audio, **animaciones Mixamo** (`assets/animations/mixamo/*.fbx`, `lib_*.res`) |

## 2. Arquitectura (fase 8: offline = online)
- **Una sola fuente de verdad: `net/sim`.** Toda partida corre en `SimMatch` sobre `FightSim`: offline con las dos entradas locales (jugador = `SimMatch.sample_device`, rival = `SimAI`), online con `NetMatch`/`RbSession` (rollback). Mismas reglas, mismo código.
- **Fighter / Eikon / Mount = vista.** `SimView` vuelca el estado en los `Fighter` (`sim_driven`), `SimWorld` coloca eikons y monturas títere, marcas de suelo, ondas y proyectiles. La animación sigue al estado (`KnightVisual`), nunca al revés. Los `Fighter` siguen existiendo porque `SimParams.bake` lee de ellos las estadísticas (personaje, arma, atributos, armadura, amuletos).
- **IA** (`net/sim/sim_ai.gd`): cada tick lee el estado y devuelve bits de entrada (como un mando). Fases CIRCLE/COMMIT/RETREAT/REST/BREATHE, perfiles `AIDifficulty`, estilo de campeón. Memoria propia + xorshift sembrado por partida (determinista dada la misma secuencia). Decide con float: no es netcode (online no hay IA).
- **Arena**: rondas, reloj de 90 s, premios y presentación (sacudida, cinemática de crítico, aura de Fase II) a partir de eventos de la sim (`_on_sim_event`). La Fase II del campeón es una regla de la sim (`P.ph2`, `P.boss_n`).
- **HUD/lobby**: `hud.gd` + `touch_stick.gd` (botones → acciones de Input → bits). `PlayerController` solo conserva ayudas de HUD/cámara (objetivo, forma del stick, menú, ajuste del búfer).

## 3. Arquitectura online
- **Modelo**: rollback P2P estilo GGPO. Solo viajan inputs. Sim pura de enteros a **60 Hz**; jamás lee delta, reloj, `Engine.time_scale` ni física del árbol.
- **`net/sim/fight_sim.gd`**: estado = un `PackedInt64Array` (2 luchadores × N campos + globales: frame, freeze de hit-stop, RNG xorshift, rondas `G_WINS0/1`, `G_ROUND`, `G_END_T` + pools: proyectiles 12, hazards 16). `SIZE` se calcula al final de las constantes de layout. Unidades: posición µm, velocidad µm/tick, HP/aguante en milésimas, multiplicadores ‰, timers en ticks, rumbo 0..255. Checksum FNV-1a. Save/load = `duplicate()`.
- **Bits de entrada**: 0–4 rumbo (32), 5 move, 6 medio stick, 7 atacar, 8 bloquear, 9 parry, 10 rodar, 11 correr, 12 swap, 13 fijar, 14 IN_BOSS, 15 IN_BOSS_NEXT, 16 IN_SPELL, 17 IN_SPELL_NEXT, 18 IN_EIKON, 19 IN_MOUNT, 20 IN_ART, 21 IN_BOSS_VAR, 22 IN_JUMP, 23 IN_FLASK, 24–29 rumbo de apuntado (64 pasos), 30 IN_AIM (31 libre: paquete int32). Flancos derivados en la sim (`prev_input` en estado).
- **`fx_math.gd`**: trig por tabla, sqrt/atan2 enteros. **`sim_abilities.gd`**, **`sim_magic.gd`**: jefe, magia, eikons, montura.
- **`SimParams.bake(a, b)`**: se calcula una vez por partida desde los dos `Fighter` reales (personaje, arma, atributos, armadura, amuletos, loadout). Pre-resuelve daño/tablas de defensa por par atacante→defensor; duraciones vía `tk()` (replica la acumulación float offline). `params_checksum()` se intercambia: si difiere → `params_mismatch`. Lenience de parry online según delay inicial (`lenience_for_delay`).
- **`RbSession`** (`net/rb_session.gd`): input delay (1–4, adaptativo en partida con histéresis), predicción (repite último input), ventana 8 ticks, resim, stall, checksums confirmados, `reset_to(estado, f)` con épocas (reconexión). `fight_engine.gd` = adaptador RbEngine.
- **`SimView`** (`sim_view.gd`): estado → nodos `Fighter` (`sim_driven = true`), suavizado visual de correcciones; nunca realimenta la sim. **`SimMatch`**: bucle local (muestrea dispositivo, teclado+táctil, camera-relative → mundo) y stepping online.
- **Eventos rollback-safe** (`sim_events.gd` + `sim_fx.gd`): eventos con tick; online se retienen 2 ticks (`hold_ticks`) y se cancelan si la resim no los regenera; acciones propias instantáneas.
- **`NetLink`** (`net/online/net_link.gd`): UDP crudo (`PacketPeerUDP`, IPv4). Relay (sala por código, partida rápida, ping por región, token de reconexión), NAT punch P/Q y fallback por relay, **LAN** en `0.0.0.0:47801/udp` con broadcast "Buscar". **`NetMatch`**: handshake (`hi`+loadout → ping/pong → `start` delay/seed → `go`), fase LOAD (`ka`/`rdy`, 30 s), paquete `in`, sync de ventaja, desync → `user://net/desync_*.json`, replays `user://net/replay_*.json` verificables (incluye resyncs), reconexión con snapshot deflate en trozos de 900 B.
- **Protocolo = 8** (fase 9: apuntado IN_AIM bits 24-30 y mensajes de revancha; fase 8: FLASK_T/FLASKS/PH2, IN_FLASK). Al cambiar el layout del estado, bits de entrada, params o mensajes, subí en **todos** estos lugares:
  1. `net/online/net_link.gd` → `const GAME_PROTO := 8` (`NetMatch.PROTO` lo hereda).
  2. `server/src/index.ts` → default `num(env.GAME_PROTO, 8)` (y la env `GAME_PROTO` del relay desplegado).
  3. `server/test/relay.test.ts` → `{ v: 8 }` (y `proto`/`need` del test de versión) en los envíos.
  4. `tests/test_net_reconnect.gd` (check `== 8`) y revisar `tests/test_net_relay5.gd`, `tests/net_client.gd`.
  5. Docs: `server/DEPLOY.md`, `docs/netcode.md`, `docs/design.md` .
- **Relay** (`server/`): Node/TS, UDP 47800, HTTP 8080 `/healthz` y `/metrics`. Salas (código 5 chars), cola rápida, tokens 96 bits, gracia 20 s → 'F' abandono, rate limits, baneos, paquete máx. 1200 B, check de versión.

## 4. LA REGLA CLAVE
**La jugabilidad vive SOLO en `net/sim`** (FightSim / SimAbilities / SimMagic / SimParams, y la IA en SimAI). Nada de reglas en `Fighter`, `Eikon`, `Mount` ni en la arena: esos nodos solo dibujan y suenan. Una regla nueva = cambio en la sim + prueba en `test_fight_sim` / `test_sim_rules` / `test_net_abilities` (y en `test_sim_ai` si la IA debe usarla) + lo que haga falta en `SimView`/`SimWorld` para verla. Si cambia el layout de estado, los bits o los params → subir protocolo (§3). Dentro de la sim: nada de floats, `randf`, nodos ni reloj. Correr también `test_net_rollback` y `test_net_online`.

## 5. Tests headless
```bash
cd ~/arena-game            # o donde esté el repo
godot --headless --path . --import                      # primera vez / tras agregar assets
godot --headless --path . -s res://tests/test_fight_sim.gd
godot --headless --path . -s res://tests/test_sim_rules.gd
godot --headless --path . -s res://tests/test_sim_ai.gd
# todos:
for t in tests/test_*.gd; do echo "== $t"; godot --headless --path . -s "res://$t" 2>&1 | tail -3; done
# bench rollback:
godot --headless --path . -s res://tests/bench_net_rollback.gd -- 2 8
# relay:
cd server && npm ci && npm test && GODOT=$(which godot) npm run test:e2e
```
- **Fase 8**: las pruebas antiguas de jugabilidad del Fighter offline se portaron a la sim (`test_sim_rules`, `test_sim_ai`) o se retiraron; las secciones retiradas de los tests por rondas llevan el comentario `[fase 8] retirado` con el motivo. Los tests de datos/UI se ajustaron al diseño actual.
- **Línea base fase 9 (2026-10-17, Godot 4.7.2 headless, 45 `test_*.gd`):** 45/45 pasan con el relay local levantado (`cd server && npm run build && PORT=47800 REGION=local npm start`; sin él fallan solo `test_net_relay5` y `test_net_matchmaking`). Nuevos: `test_boss_ui`, `test_bow_aim`, `test_net_rematch`, `test_ability_fx`. Relay: `npm test` 9/9, `npm run test:e2e` 5/5 (protocolo 8). Antes (fase 8, `6f4d0ab`): 40/41, fallaba `test_ui_audio`.
- **Ronda 46:** el catálogo de jefe pasa a 45 habilidades (6 base + 39 extendidas). Las 26 nuevas reusan los ejecutores de la sim (línea de tiempo, onda, lluvia, aliento, ráfaga, furia, contragolpe). Protocolo sigue en **8**. Prueba nueva: `test_boss_roster.gd`. Verificadas en esta ronda: roster, UI de jefe, efectos, rollback de habilidades, IA y `test_round34`. La suite entera de 46 tests no se re-corrió.
- **Ronda 47:** `Mount.expire` existe otra vez (sin ella, morir con un eikon activo cortaba la partida). El jinete del fénix sigue la silla; el vuelo no se aplica dos veces. Prueba: `test_mount_seat.gd`.
- **Ronda 48:** respaldo de las 45 en `docs/backup/habilidades_ronda46/` (no se migraron). Esa carpeta tiene `.gdignore` y las copias no declaran `class_name`: si lo declararan, Godot usaría el respaldo en vez de los scripts vivos. Hoja Escarlata (`trazos_hoja`, `danza_garza`, `caida_hoja`, `floracion_escarlata`) se hornea con `AbilityCatalog.load_file` y corre en `SimCatalog`, reusando `AB_*`. Protocolo sigue en **8**. Verificadas: `test_hoja_escarlata`, `test_ability_catalog`, roster, UI de jefe, efectos, rollback y `test_round34`. La suite entera no se re-corrió.
- `test_net_events` no era flaky: exigía `> 20` eventos y la partida genera exactamente 20 a 50 ms; ahora el umbral (≥ 15) es una comprobación aparte. `test_round25` pasó en esta corrida (sigue siendo posicional).
- **Catálogo de habilidades (JSON):** `net/sim/ability_catalog.gd` carga, valida (V01–V19) y hornea a enteros un catálogo según `docs/abilities_guide.md`; la sim aún no lo usa. CLI: `godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/catalog.example.json` (sale 1 si hay errores). Prueba: `test_ability_catalog`. Suite completa 48/48 con relay local (2026-10-17). Siguiente paso: `docs/prompt_motor_habilidades.md`.
- Los tests online/sim (`test_net_*`, `test_fight_sim`, `test_sim_*`) deben pasar al 100 %.

## 6. Exportar (solo Android y Linux; Jonathan no quiere otros)
Plantillas 4.7.2: Editor → *Manage Export Templates* o descomprimir el `.tpz` en `~/.local/share/godot/export_templates/4.7.2.stable/`.

**Android sin Android Studio (Fedora):**
```bash
sudo dnf install java-17-openjdk-devel unzip
mkdir -p ~/Android/Sdk/cmdline-tools && cd ~/Android/Sdk/cmdline-tools
# bajar commandlinetools-linux-*_latest.zip de developer.android.com/studio#command-tools
unzip commandlinetools-linux-*.zip && mv cmdline-tools latest
export ANDROID_HOME=~/Android/Sdk; export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
sdkmanager --licenses
sdkmanager "platform-tools" "build-tools;35.0.0" "platforms;android-35"
keytool -genkeypair -v -keystore ~/debug.keystore -storepass android -alias androiddebugkey -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```
Editor Settings → Export → Android: `java_sdk_path` (`/usr/lib/jvm/java-17-openjdk`), `android_sdk_path` (`~/Android/Sdk`), debug keystore/usuario/clave (`androiddebugkey`/`android`). El preset ya tiene arm64-v8a + armeabi-v7a, `permissions/internet=true` (imprescindible para online), sin Gradle.
```bash
godot --headless --path . --export-debug Android ../out/arena-game-debug.apk
adb install -r ../out/arena-game-debug.apk
```
Para instalar por sideload en el teléfono hay que **desactivar Play Protect** (Play Store → Play Protect → ⚙ → desactivar análisis), si no bloquea el APK.

**Linux:** `godot --headless --path . --export-release Linux ../out/linux/ArenaGame.x86_64` (o `--export-debug`) y `chmod +x`.

**Última build (fase 9):** `/workspace/arena-game-build/arena-game-f9.apk` (debug, arm64-v8a + armeabi-v7a, firmada v2+v3 con la debug keystore; `apksigner verify` OK) y `/workspace/arena-game-build/arena-game-f9-linux.zip` (binario `arena-game-f9-linux.x86_64`, pck embebido, modo 755). `apksigner` necesita `JAVA_HOME` (JDK 17) en el PATH.

**Firewall Fedora para LAN** (host de partida LAN):
```bash
sudo firewall-cmd --add-port=47801/udp --permanent && sudo firewall-cmd --reload
```

## 7. Relay (NO desplegado → partida rápida/salas por código no funcionan hasta desplegarlo; LAN sí)
Local: `cd server && npm ci && npm run build && PORT=47800 REGION=local npm start` (o `docker build -t arena-relay . && docker run -p 47800:47800/udp arena-relay`). En el juego: campo relay `127.0.0.1:47800` o `sa=host:47800, us=...`.
Deploy recomendado: Oracle Cloud Always Free, São Paulo, `server/deploy` con `docker compose up -d --build`; abrir UDP 47800 en VCN y en el firewall de la VM; no exponer 8080. Detalle en `server/DEPLOY.md`.

## 8. Reglas del proyecto
- Código verificado con **tests headless**; agregar test para cada feature/arreglo.
- **Commit + push frecuentes** (checkpoints pequeños, mensajes tipo `phase7c: ...`).
- `docs/design.md` = solo datos/reglas duraderas (no bitácora; el historial va en README/netcode).
- **Evitar nombres y assets de FromSoftware** (Elden Ring, Dark Souls, etc.): nombres propios, números propios.
- `DEBUG_GRANT` en `scripts/game_state.gd` debe quedar en **`false`** antes de cualquier release (hoy está en false; `--debug-grant` por CLI para pruebas).
- `assets/` y las animaciones Mixamo **están trackeadas en git aunque `.gitignore` las cubra — no las borres ni las "limpies"**. Si agregás nuevas, `git add -f`.
- Builds: solo Android + Linux.
- Textos de UI en español.

## 9. Movimiento (fase 7, vive en la sim)
Andar 8,3 m/s, correr ×1,3; aceleraciones, giro (13 rumbos/tick) y frenado en `fight_sim.gd`. Atacando 30 %, bloqueando 45 %, agotado 60 %, aterrizaje 40 % por 0,18 s. Salto 8 m/s, gravedad 20 (×1,8 picado), 12 aguante, sin control aéreo. Offline ya no aplica suavizado de entrada propio.

## 10. Huecos conocidos
1. `NetLink` resuelve el DNS del relay **sincrónicamente** (`IP.resolve_hostname` en `net_link.gd` ~l.119 y ~l.181): congela la UI si el DNS tarda. Pasar a `IP.resolve_hostname_queue_item` + poll.
2. Referencias a Elden Ring / Dark Souls en docs y comentarios (README rondas 9/25, `docs/design.md`, `docs/ELDEN_RING_REFERENCIA.md`, comentarios "estilo ER") → limpiar/renombrar.
3. `test_round25` posiblemente flaky (posicional).
6. Fase 9 cerró los huecos de la fase 8 (✕ de Ajustes, HUD del campeón, apuntado con ratón, efectos de habilidades, iconos, ciclo ▶, revancha online); ver `docs/netcode.md` §17.
4. Relay sin desplegar; IPv4 solo.
5. Pendiente de design: Erika sin FBX de Mixamo.

## 11. Próximos pasos (prioridad)
2. Desplegar el relay (Oracle São Paulo) y probar partida rápida Android↔Linux real; anotar IP/host en la config por defecto.
3. DNS asíncrono en `NetLink`.
4. Vigilar `test_round25`. Probar la revancha y el apuntado con ratón en una partida real Android↔Linux.
5. Limpiar referencias FromSoftware en docs/comentarios/nombres.
6. Probar rendimiento de rollback en un Android medio (overlay F3/"Red": µs por paso).
7. Checklist de release: `DEBUG_GRANT=false`, keystore de release, versión de app.
