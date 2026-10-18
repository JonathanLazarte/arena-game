# Diseño — referencia (reglas duraderas)

Datos en código: `scripts/data/stun_rules.gd`, `scripts/data/boss_abilities.gd`, `scripts/data/attributes.gd`.

## Principios de balance
- Inspiración souls (curvas tipo Elden Ring, números propios): ganancias por tramos con rendimientos decrecientes (primeros ~25–30 puntos rinden, luego cae).
- Todo ataque fuerte o de jefe se telegrafía; al soltarse solo se evita con voltereta en la ventana justa (no caminando).
- Ningún recurso gratis: las habilidades de jefe cuestan aguante, maná (= Energía) o vida. Hay recarga global de 1,4 s (85 ticks en la sim). La recarga propia de cada habilidad no se usa todavía; más adelante será `max(global, propia)`.

## Aturdimiento (3 niveles acumulados)
- Fuerza por golpe: `str_force(Fuerza) + fuerza del arma + fuerza del golpe` × `stun_dealt`. Mágico: `magia × 0,1 + fuerza asignada` (por impacto).
- `str_force`: 0,6/pt hasta 30, 0,3 hasta 50, 0,1 después. Arma: dagas 4, espada+escudo 8, lanza 9, espada larga 11, hacha 14, arco 3, ballesta 6.
- Robustez del defensor = equilibrio (poise rol + Aguante + armadura) / `stun_taken` / resistencia de armadura, × (1 + súper-armadura actual).
- Se acumula durante 3 s desde el primer golpe; al cerrar la ventana se recupera todo de golpe. Un golpe aporta como mucho 0,95 × robustez → ninguno aturde solo.
- Umbrales (acumulado/robustez): 1,0 tambaleo (0,35 s, se cancela rodando) · 1,6 aturdido (0,9 s) · 2,4 derribo (1,1 s suelo + 0,8 s levantarse). Cada nivel una vez por ventana.
- Tras derribo: inmune al aturdimiento (no al daño) hasta levantarse + 0,6 s, recibiendo ×0,85 de daño. Montado, el derribo se convierte en aturdido.
- Rotura de postura (stance) sigue aparte y reinicia el medidor; parry y rotura de guardia aturden directo.
- Súper-armadura: fuerte en anticipación +1,0 (+1,0 más con carga completa), dash/salto +0,5, por golpe `ComboHit.stun_resist`, por arma `WeaponDef.heavy_stun_resist`.

## Habilidades de jefe (máx. 3 equipadas por personaje, pestaña «Jefe»; B usa, N cambia)
| id | coste | daño | fuerza | resist. | clave |
|---|---|---|---|---|---|
| estocada | 30 aguante | 1,6× fuerte | 60 | inmune | carga 1,6 s; deja de seguir 0,3 s antes de la embestida. Embestida 12 m a 30 m/s → solo voltereta |
| carga_area | 35 maná | 1,4× (mágico) | 45+magia | ×5 | inmóvil 1,8 s, AoE 4,5 m; interrumpible |
| rafaga | 30 maná | 0,55× ligero c/u | 14+magia c/u | ×1,5 | 3 espectros de tajo dorados en diagonal cada 0,9 s, radio 1,3, 16 m/s, persiguen siempre (600°/s): solo la voltereta esquiva cada uno; esquivado sigue de largo |
| escudo_mana | 25 maná | — | — | inmune | 1,5 s invulnerable total, mitad de velocidad |
| combo_falso | 38 aguante | 0,7/0,7/0,9/1,7× ligero | 4/4/18/45 | ×1,3 | golpes lentos a 1,2/4,2/7,2 s y el 4.º tardío a 11,2 s; cada uno gira (120°/s) y avanza ~3 m (7 m/s × 0,4 s) |
| salto_caida | 15 vida | 1,5× fuerte | 50 | inmune en el aire | sin marca: sigue al objetivo hasta 1,25 s, cae a 1,65 s, AoE 3,5 m; la pista es verle en el aire |
- Coste de vida: no se puede usar si dejaría la vida ≤ 0. IA: elige por distancia/situación, huye de la carga, rueda la estocada y cada tajo de la ráfaga, y ante el salto se aparta/rueda al verle empezar a bajar.
- Cambio de habilidad: tecla N o botón ▶ del HUD (PC y táctil).

### Reglas comunes (Ronda 33)
- Imbloqueable (`unblockable` en la definición; `BossAbilities.is_unblockable`): el escudo no la para y el parry tampoco (golpe tipo 3). Lo son la Estocada y las marcadas en la tabla (Tajo Retardado, Presa del Verdugo, Giro Devastador, Paso Espectral, Lanza Celeste, Cuerno, Daga Sagrada, Estocada Negra, Flor Umbral, Presa de Fauces, Rueda Noble, Danza Triple, Picado de Alas y Flecha Grave).
- Estocada: sigue durante la carga y deja de girar 18 ticks (0,3 s) antes de la embestida. En la embestida solo corrige la dirección los primeros 0,15 s, después va recta. Durante la carga y la embestida es inmunidad total, igual que hoy; queda pendiente de balance.
- Recarga global de 1,4 s (85 ticks, `tk(1,4)`) desde que acaba una habilidad de jefe (la Ráfaga puede encadenarse consigo misma). La recarga propia no corre. Más adelante, `max(global, propia)`.
- Cada habilidad tiene un aviso propio (texto `tele`/`tele_txt` y color de brillo distintos), coste de recurso, fuerza de aturdimiento y recuperación castigable (≥ 0,3 s). Un coste de vida se rechaza si dejaría la vida en 0; si se paga, se recorta a 1.
- Interrupción (`interruptible_by`, en el motor nuevo): lista vacía = no se corta con tambaleo, aturdimiento ni derribo; solo se esquiva. Quien se corta lo declara, por ejemplo `["stun_lvl2", "knockdown", "parry"]`. La Danza del Cisne declara parry, aturdimiento fuerte y derribo (ya no hay un corte cableado por id una vez migrada).
- Invulnerabilidad total (el golpe cuenta como esquiva): i-frames de la Danza, el Paso Espectral, la transición a Fase II y el escudo de maná. Son esquivas. El derribo no es invulnerable: inmune al aturdimiento y daño ×0,85.
- Daño de estas habilidades: `damage_scaling` `weapon_heavy` o `weapon_light` (multiplicador del fuerte o del ligero). Si la habilidad es mágica, además × magia/100.
- Onda: empuje de 6 m/s si el catálogo no dice otra cosa (`knockback_mps`).
- Cuándo se puede usar: en el suelo, sin montar, sin frasco, sin estar agotado y con la espada (el escudo de maná también con arco). Vive en `SimAbilities.can_use`.
- En móvil todos los avisos duran +12 % (`telegraph_k` = 1,12).
- Aura dorada pulsante mientras hay invulnerabilidad, inmunidad al aturdimiento o súper-armadura (robustez extra ≥ +1,0).
- Voltereta con búfer de 0,18 s: si se pulsa durante una acción, sale en cuanto el personaje queda libre.
- Rendimiento: rival más cercano cacheado cada 0,1 s; datos del ataque calculados una vez por ataque; máximo 6 ráfagas de partículas simultáneas.

### Habilidades extendidas (13)
| id | nombre | coste | tipo | clave |
|---|---|---|---|---|
| tajo_retardado | Tajo Retardado | 24 aguante | golpe | amague y golpe tardío a 1,25 s; onda al impactar |
| presa_verdugo | Presa del Verdugo | 28 aguante | agarre | agarre imbloqueable; si falla, recuperación larga |
| giro_martillo | Giro Devastador | 30 aguante | barrido | 360°, dos golpes, súper-armadura |
| danza_cisne | Danza del Cisne | 40 aguante | ráfaga | 6 tajos con i-frames breves; un parry la corta |
| paso_espectral | Paso Espectral | 25 maná | teletransporte | desaparece invulnerable y golpea por la espalda |
| onda_rastrera | Onda Rastrera | 24 aguante | ondas | 3 ondas en abanico con trayectoria visible |
| rayos_trazadores | Rayos Trazadores | 25 maná | lluvia | 4 rayos que siguen tu posición |
| lluvia_meteoros | Lluvia de Meteoros | 35 maná | lluvia | 7 marcas repartidas, aviso 1 s |
| aliento_dragon | Aliento de Dragón | 30 maná | cono | fuego sostenido 1,5 s que gira despacio |
| furia_fase | Furia de Fase | 20 vida | bufo | +30 % daño, +15 % velocidad, súper-armadura 9 s |
| postura_contra | Postura de Contragolpe | 22 aguante | contra | si le atacan en la ventana, anula y castiga |
| embate_sismico | Embate Sísmico | 18 vida | ondas | 8 ondas en anillo (una apunta al rival), fuerza 45, recuperación 1,3 s |
| lanza_celeste | Lanza Celeste | 30 maná | lluvia | una lanza imbloqueable sobre tu posición, aviso 1,1 s, fuerza 70, recuperación 1,4 s |

### Habilidades extendidas (lote 2, 26)
Patrones de jefe con nombres y números propios. Mismas reglas: aviso, coste, recuperación castigable. `pillar` dibuja columna; `slam_always` suelta el área aunque el cuerpo falle; `type: rafaga` es un tajo que persigue (se puede repetir al terminar, pagando otra vez).

| id | nombre | coste | tipo | clave |
|---|---|---|---|---|
| cuerno_embiste | Cuerno de Embiste | 28 aguante | golpe | dos tiempos, el primero cierra a gran velocidad; imbloqueable |
| tajo_cruzado | Tajo Cruzado | 32 aguante | golpe | dos cortes y estocada; se bloquea |
| zarpazo_sangre | Zarpazo de Sangre | 26 maná | golpe | corte y estallido en el suelo |
| barrido_cola | Barrido de Cola | 26 aguante | golpe | dos arcos de 170°, alcance 4,4 m |
| daga_sagrada | Daga Sagrada | 24 aguante | golpe | pinchazo y estocada tardía con amague; imbloqueable |
| estocada_negra | Estocada Negra | 28 maná | golpe | una estocada larga, fuerza 52; imbloqueable |
| flor_umbral | Flor Umbral | 16 vida | golpe | picado y flor de 5,2 m aunque falle el cuerpo |
| presa_fauces | Presa de Fauces | 26 aguante | agarre | mordisco; si falla, recuperación extra |
| giro_noble | Rueda Noble | 22 aguante | golpe | embestida que gira a 360°/s; imbloqueable |
| danza_triple | Danza Triple | 42 aguante | golpe | cuatro tajos en tres pulsos, i-frames breves; imbloqueable |
| alas_picado | Picado de Alas | 30 aguante | golpe | caída con área fija de 3,8 m |
| garra_suelo | Garra de Suelo | 24 aguante | ondas | una onda ancha (2,6 m), fuerza 48 |
| vendaval_hacha | Vendaval de Hacha | 28 aguante | ondas | dos ondas rápidas en abanico de 10° |
| anillo_fuego | Anillo de Fuego | 30 maná | ondas | ocho ondas cortas en anillo |
| pisoton | Pisotón | 20 aguante | ondas | una onda baja de 4,2 m de ancho, fuerza 55 |
| lluvia_lanzas | Lluvia de Lanzas | 28 maná | lluvia | cinco columnas que siguen tu sitio |
| flecha_grave | Flecha Grave | 24 maná | lluvia | un círculo de 2,6 m, aviso 1,25 s; imbloqueable |
| lluvia_sangre | Lluvia de Sangre | 32 maná | lluvia | seis marcas repartidas en 5 m |
| columnas_rayo | Columnas de Rayo | 34 maná | lluvia | tres columnas separadas 0,7 s |
| saeta_oscura | Saeta Oscura | 18 maná | ráfaga | un tajo que curva a 48°/s |
| orbe_lunar | Orbe Lunar | 30 maná | ráfaga | orbe lento de radio 1,05 m, poco giro |
| aliento_rayo | Aliento de Rayo | 32 maná | cono | rayo, arco 18°, alcance 9 m |
| aliento_escarcha | Aliento de Escarcha | 28 maná | cono | hielo, arco 42°, alcance 6,5 m |
| chorro_lava | Chorro de Lava | 34 maná | cono | fuego denso, 5,5 m, 1,6 s |
| grito_guerra | Grito de Guerra | 26 aguante | bufo | 5,5 s de furia (+30 % daño, +15 % velocidad) |
| guardia_reflejo | Guardia Refleja | 20 aguante | contra | ventana 1,6 s, alcance 3,2 m, castigo ×1,9 |

### Esquema de datos de habilidades (objetivo)
- Formato JSON objetivo para autorar habilidades (catálogo + presets de jefe, pasos 1..N con windup/activo/recuperación en ticks, hitboxes con daño por golpe, ramas y remates a elección): [`docs/abilities_guide.md`](abilities_guide.md). El cargador y el validador están en `net/sim/ability_catalog.gd`. Las 45 anteriores están en `data/abilities/catalog.json` (`source` más el paso). `BossAbilities` solo lee ese archivo. `SimSteps` las ejecuta siempre y lee `interruptible_by` del catálogo. `ab_engine` queda en los params y por defecto es 1; ya no hay camino sin envolver. La recarga de esas habilidades es la global de 85 ticks: el `cooldown` propio no se usa todavía. Hoja Escarlata (`data/abilities/hoja_escarlata_catalog.json`) corre aparte en `SimCatalog`: Trazos de Hoja, Danza de la Garza, Caída de la Hoja y Floración Escarlata. Preset: trazos, garza y floración (la tercera, solo en Fase II del campeón). Ahí la recarga propia es el máximo con la global de 1,4 s, en el mismo contador. La zona es una tanda de anillos. El sangrado es la acumulación que ya existe. El protocolo de red es 12 (la ráfaga se salta la global si se repite: `global_cd_on_repeat`). Desde el 11, el bit 21 es el `alt` de la ventana abierta y el motor de pasos es el único camino de las 45.

## Fuerte cargado
- La pose de carga del fuerte se ve desde que se empieza a mantener el ataque (antes de que salga el fuerte).

## Arcos
- Mantener = tensa y apunta sin disparar; dispara al soltar (animación normal). Si se mantuvo ≥ 0,9 s tras tensar, sale cargado (brillo dorado pulsante en el arco + sonido al cargarse); si no, normal. Igual en ballesta.
- Arco «potente»: ×2,2 daño (×2,4 con Ojo de halcón), ×1,4 velocidad, ×2,5 aturdimiento. Ballesta «triple»: 3 virotes en abanico (±0,18 rad), ×0,7 daño. `WeaponDef.charged_shot` lo fuerza.

## Calibración de atributos
- Velocidad de ataque (Destreza): 0,8 %/pt hasta 25, 0,5 % hasta 40, 0,3 % después; tope +25 % (antes +16 %).
- Un punto de Destreza ≈ 40 % del daño que da un punto de Fuerza en «escala» (2 %/pt temprano), compensado por velocidad, voltereta e i-frames.
- La ficha muestra la velocidad de ataque final.

## Movimiento a pie (fase 7: respuesta de juego de acción)
Mismos valores offline (Fighter, jugador con `fluid`) y online (SimParams → FightSim). Velocidad de andar 8,3 m/s × multiplicadores; correr ×1,3.
| Parámetro | Valor | Efecto |
|---|---|---|
| FOOT_MOVE_ACCEL | 90 m/s² | 0 → andar en ~0,09 s |
| FOOT_SPRINT_ACCEL | 75 m/s² | andar → correr ~0,06 s (lo limita la rampa); 0 → correr ~0,14 s |
| FOOT_BRAKE_ACCEL | 120 m/s² | frena andando en ~0,07 s (0,29 m), corriendo ~0,09 s (≤0,5 m) |
| SPRINT_RAMP_UP / DOWN | 0,06 s / 0,08 s | rampa lineal del multiplicador de carrera (online: 278 ‰ / 208 ‰ por tick) |
| TURN_RATE_DEG | 1080 °/s | giro del cuerpo (online 13 rumbos/tick) |
| STEER_TURN_MULT | 2,0 | la velocidad gira a 2160 °/s conservando el módulo: sin derrapes en curvas; >150° frena en línea recta |
| INPUT_SMOOTH | 0,03 s / 90° | suavizado del stick (solo offline); voltereta, ataque y salto usan la dirección sin suavizar |
Compromisos que se mantienen: atacando 30 % de velocidad, bloqueando 45 %, agotado 60 %, al caer de un salto 40 % durante 0,18 s.
Antes (sincronización del proyecto del usuario): 36 / 30 / 46 m/s², carrera exponencial 0,14 / 0,28 s, giro 800 °/s, velocidad girando a 920 °/s y suavizado 0,08 s → ~0,25 s para arrancar, ~0,45 s para correr y hasta 1,3 m de deslizamiento al frenar corriendo.

## Salto
8 m/s, gravedad 20 m/s² (×1,8 durante el picado): 0,8 s en el aire, 1,67 m. Coste 12 de aguante. Sin control en el aire (trayectoria fijada al despegar) y sin giro. Atacar en el aire = picado (golpea al aterrizar si aún está en la anticipación). Recuperación al caer 0,18 s. Evita los golpes de área a ras de suelo (altura > 0,35 m). Montado: brinco de lobo/grifo (salto de la montura × 0,85); en el fénix no se salta. Entrada IN_JUMP.

## Frasco
1 carga por ronda (H / botón «Frasco»): 1,1 s bebiendo (sin atacar ni bloquear, 25 % de velocidad), cura el 35 % de la vida máxima al terminar. No se bebe montado, en el aire ni atacando.

## Duelo de Campeones: Fase II
Al bajar del 50 % de vida: desbloquea su tercera habilidad de jefe, furia 9 s, invulnerable 0,85 s y, según el campeón, medidor de eikon lleno (invoca). La IA presiona más (habilidades ×2,5, especiales ×1,5).

## IA del rival
Lee el estado de la partida y pulsa botones como un jugador. Fases: rodear, comprometerse (1–N golpes, a veces retrasa el primero), retirarse, descansar (poco aguante) y respiros periódicos. Perfiles fácil/normal/difícil (`resources/ai/*.tres`): reacción, esquiva, parry, castigo, uso de habilidades.

## Pendiente
- Erika: falta el FBX de Mixamo.
