# Elden Ring: referencia de sistemas y hoja de ruta de diseño

> Documento de diseño de **Arena de Eikons** (1v1 a caballo/eikon, móvil y Windows, Godot 4.7).
> Resumen con palabras propias de las mecánicas de *Elden Ring* (ER), comparadas con el estado del juego al cierre de la **Ronda 20** (commit `0f40c48`), con propuestas adaptadas y prioridades.

## ⚑ Pilar de diseño principal (Ronda 25)

**Cada duelo es mitad PvP, mitad combate contra un jefe de Dark Souls.** Los personajes tienen habilidades «de jefe»: **imparables e invulnerables mientras se ejecutan**, pero **siempre telegrafiadas** con una preparación inconfundible (pose, brillo/partículas, sonido creciente). El reto es el **ritmo** (leer y esquivar a tiempo), no los reflejos puros. Siempre dejan una **recuperación castigable**, tienen enfriamiento y una trayectoria fija y aprendible. Toda habilidad nueva se diseña contra este pilar. Primera: **Estocada de jefe** (Ronda 25).
> Los números de ER son de las wikis citadas en cada sección (consultadas en octubre de 2026; parche 1.1x + *Shadow of the Erdtree*). Son **referencia**: en el juego usamos valores propios, normalizados para que el nivel 1 juegue igual.

**Leyenda de estado:** ✅ implementado · 🟡 parcial · ❌ falta.
**Prioridad:** **P0** imprescindible/siguiente · **P1** alto impacto · **P2** deseable · **P3** opcional / largo plazo.

**Fuentes generales**
- Fextralife: https://eldenring.wiki.fextralife.com/
- Eldenpedia (wiki.gg): https://eldenring.wiki.gg/
- Fandom: https://eldenring.fandom.com/
- Bandai Namco, *How-To Guides*: https://en.bandainamcoent.eu/elden-ring/news (Part 1: Stats; Part 2: Combate)

---

## Índice
1. [Atributos y estadísticas derivadas](#1-atributos-y-estadísticas-derivadas)
2. [Cálculo de daño](#2-cálculo-de-daño)
3. [Golpes de contraataque, críticos, guardia y equilibrio](#3-golpes-de-contraataque-críticos-guardia-y-equilibrio)
4. [Estados alterados](#4-estados-alterados)
5. [Armas](#5-armas)
6. [Escudos y catalizadores](#6-escudos-y-catalizadores)
7. [Magia](#7-magia)
8. [Armadura, talismanes y Grandes Runas](#8-armadura-talismanes-y-grandes-runas)
9. [Consumibles](#9-consumibles)
10. [Cenizas de espíritu → nuestros eikons](#10-cenizas-de-espíritu--nuestros-eikons)
11. [Combate a caballo (Torrent)](#11-combate-a-caballo-torrent)
12. [Movimiento](#12-movimiento)
13. [Reglas de aguante (estamina)](#13-reglas-de-aguante-estamina)
14. [IA y patrones de jefes](#14-ia-y-patrones-de-jefes)
15. [Progresión y economía](#15-progresión-y-economía)
16. [Balance PvP](#16-balance-pvp)
17. [Hoja de ruta por fases](#17-hoja-de-ruta-por-fases)
18. [Preguntas abiertas](#18-preguntas-abiertas)

---

## 1. Atributos y estadísticas derivadas

Fuentes: https://eldenring.wiki.fextralife.com/Stats · https://eldenring.wiki.fextralife.com/Vigor · https://eldenring.wiki.fextralife.com/Mind · https://eldenring.wiki.fextralife.com/Endurance · https://eldenring.wiki.gg/wiki/Stats · https://eldenring.wiki.fextralife.com/Equip+Load · https://eldenring.wiki.fextralife.com/Discovery · https://eldenring.wiki.fextralife.com/Poise

### Cómo lo hace ER
Hay 8 atributos (de 1 a 99). Cada uno alimenta una o varias estadísticas derivadas, y todas tienen curvas por tramos con **topes blandos**: pasado cierto valor, cada punto rinde mucho menos.

| Atributo | Afecta | Topes blandos (aprox.) |
|---|---|---|
| Vigor | PV, Inmunidad, defensa contra fuego | 40 (1450 PV), 60 (1900 PV); máx. 2100 PV a 99 |
| Mente | PM (FP), Concentración (Focus) | 50-55 (~ 450 PM); máx. 450-ish a 60 |
| Aguante (Endurance) | Estamina, Carga, Robustez | estamina 15 → 105, 30 → 130, 50 → 155 (máx. 170); carga 25, 60 (máx. 160) |
| Fuerza | escalado y requisitos, defensa física | escalado 20 / 55 / 80 |
| Destreza | escalado, velocidad de lanzamiento, menos caída a caballo | 20 / 55 / 80 |
| Inteligencia | hechicerías, defensa mágica | 20 / 50 / 80 |
| Fe | encantamientos | 20 / 50 / 80 |
| Arcano | Descubrimiento, Vitalidad, acumulación de sangre/veneno (en armas con arcano) | 20 / 50 / 80 (estados: 45 / 60) |

Estadísticas derivadas:

| Derivada | Origen | Notas |
|---|---|---|
| PV | Vigor | curva propia; a 10 de Vigor hay ~400 PV, a 40 ~1450 |
| PM | Mente | gasto de hechizos y Cenizas de guerra |
| Estamina | Aguante | 80 con valores bajos, ~155 a 50 |
| Carga de equipo | Aguante | 45 base → 160; ligero < 30 %, medio < 70 %, pesado ≤ 100 %, sobrecargado > 100 % |
| Defensa (por tipo) | nivel + atributos | física: Fuerza; mágica: Int; fuego: Vigor; rayo: Arcano/nada; sagrado: Fe/Arcano |
| Absorción (%) | armadura y talismanes | multiplicativa entre piezas |
| Resistencias | Robustez (Aguante), Inmunidad (Vigor), Concentración (Mente), Vitalidad (Arcano) + nivel + armadura | umbral de cada estado |
| Equilibrio (Poise) | armadura y talismanes | ver §3 |
| Descubrimiento | Arcano | 100 + Arcano; afecta la tasa de botín |

### Nuestro estado
- ✅ **8 atributos propios** (Ronda 18): Vitalidad, Concentración, Aguante, Fuerza, Destreza, Sabiduría, Devoción y Vínculo (Vínculo reemplaza al Arcano y potencia al eikon). Repartos iniciales por rol, 2 puntos por nivel, máximo 60, redistribución gratis.
- ✅ **Derivadas relativas al rol** (`Attributes.derived`): vida, estamina, poise, aturdimiento sufrido/infligido, guardia, carga, energía (PM), impacto, velocidad, coste de voltereta, i-frames, magia, curación, sagrado, eikon y medidor. Curvas por tramos con topes blandos.
- ✅ **Defensa, Absorción, Resistencias, Equilibrio y Carga** (Ronda 19, `EquipStats`), aplicados al daño recibido.
- 🟡 **Resistencias:** Robustez → aturdimiento y sangrado/congelación; Inmunidad → daño de área y veneno; Concentración → rotura de guardia/equilibrio. **Vitalidad no hace nada** (no hay Muerte).
- ❌ **Descubrimiento:** no hay botín aleatorio.

### Propuesta
- Dejar las curvas como están (ya son relativas).
- Dar uso a la **Vitalidad**: si entra un estado tipo "Perdición" (§4), que lo resista. Si no, fusionarla con otra resistencia para no mostrar números muertos.
- **Descubrimiento → "Fortuna"** en Vínculo o en un talismán: +% de piedras de forja y oro por partida (aprovecha la economía nueva de la Ronda 20).
- Ficha: mostrar el **tope blando** sobre cada barra de atributo (marca en 20/40) y "rendimiento decreciente" en la vista previa.

**Prioridad:** P2 (Fortuna, marcas de tope blando) · P3 (Vitalidad).

---

## 2. Cálculo de daño

Fuentes: https://eldenring.wiki.fextralife.com/Attack+Power · https://eldenring.wiki.fextralife.com/Calculating+Damage · https://eldenring.wiki.fextralife.com/Damage+Types · https://eldenring.wiki.gg/wiki/Damage_Calculation · https://eldenring.fandom.com/wiki/Weapon_Scaling

### Cómo lo hace ER
- **AR (Ataque)** = base del arma (por tipo de daño) + bono de escalado. El bono es base × coeficiente del atributo × curva de ese atributo (la curva depende del arma y de la afinidad).
- **Letras de escalado**: S (≥ 1,75), A (1,40-1,75), B (0,90-1,40), C (0,60-0,90), D (0,25-0,60), E (< 0,25).
- **Requisitos**: si no cumplís alguno, el bono de escalado de ese tipo se anula y se aplica una penalización fuerte (en torno al 40 % del AR).
- **Defensa**: el daño se calcula por tipo como `AR × mult(AR/Defensa) × (1 − Absorción)`. El multiplicador va de ~10 % (cuando el ataque es mucho menor que la defensa) a ~90 % (cuando el ataque la supera de lejos). Es una función por tramos de la relación ataque/defensa.
- **Tipos de daño:**

| Tipo | Subtipo | Notas |
|---|---|---|
| Físico | Estándar, Contundente, Cortante, Perforante | cada ataque tiene subtipo; la armadura absorbe distinto por subtipo |
| Mágico | — | Inteligencia |
| Fuego | — | Fe; algunas criaturas son débiles al fuego |
| Rayo | — | Destreza; más daño a enemigos mojados o metálicos |
| Sagrado | — | Fe; muertos vivientes y dragones |

Los ataques de **estocada** (perforante) tienen bonus de contraataque (§3), y los **contundentes** hacen más daño de equilibrio.

### Nuestro estado
- ✅ **AR, escalado S–E y requisitos** (Ronda 18): `Attributes.weapon_mult`, con una penalización propia de −30 % si no cumplís los requisitos.
- ✅ **Defensa con multiplicador entre 10 % y 90 %** y **absorción por tipo** (físico, mágico, fuego, rayo, sagrado) (Ronda 19).
- ✅ **Elementos de los eikons**: fénix → fuego, lobo → mágico, grifo → rayo, gólem → físico.
- 🟡 **Sin subtipos físicos**: todo golpe cuerpo a cuerpo es "físico".
- 🟡 **Las armas no tienen daño elemental propio**; el escalado sagrado (Devoción) de la espada y escudo sí da una parte sagrada.
- ✅ Mejoras (+6 %/nivel) e infusiones (Ronda 20).

### Propuesta
- **Subtipos físicos** baratos de implementar: un `damage_subtype` por golpe de combo (`ComboHit`) y por arma:
  - Dagas: cortante / perforante.
  - Lanza: perforante.
  - Hacha: cortante; su golpe fuerte, contundente.
  - Espada larga: estándar.
  - Escudo (embestida): contundente.
- **Absorción por subtipo en la armadura** con diferencias pequeñas (±3 %), para que elegir armadura sea una decisión real sin romper el balance.
- **Contundente → +20 % de daño de equilibrio**, **perforante → +bonus de contraataque** (§3).
- **Afinidades elementales** (las Ronda 20 son solo de estado): *Ardiente* (fuego, escala Devoción), *Mágica* (Sabiduría) y *Sagrada* (Devoción), que dividen el AR entre físico y elemento. Esto le da sentido a la absorción por tipo de la armadura.

**Prioridad:** P1 (subtipos + bonus) · P2 (afinidades elementales).

---

## 3. Golpes de contraataque, críticos, guardia y equilibrio

Fuentes: https://eldenring.wiki.fextralife.com/Counter+Damage · https://eldenring.wiki.fextralife.com/Critical+Hits · https://eldenring.wiki.fextralife.com/Guard+Boost · https://eldenring.wiki.fextralife.com/Guard+Counter · https://eldenring.wiki.fextralife.com/Poise · https://eldenring.wiki.fextralife.com/Stance · https://eldenring.wiki.fextralife.com/Hyperarmor · https://eldenring.wiki.fextralife.com/Parry

### Cómo lo hace ER
- **Contraataque (counter hit)**: golpear a alguien mientras está en la anticipación o la ejecución de su ataque. Da más daño (~+15 % en golpes normales; los perforantes y algunos ataques fuertes tienen un bono mayor) y más daño de equilibrio.
- **Críticos**:
  - **Puñalada por la espalda (backstab)**: por detrás y a corta distancia.
  - **Riposta**: tras un parry o una rotura de postura (*stance break*).
  - El daño es AR × el multiplicador crítico del arma (≈ 100-140, más en dagas; el talismán Daga Maldita sube el daño crítico). Durante la animación hay invulnerabilidad.
- **Guardia**:
  - **Guard Boost** (estabilidad): un número del escudo que reduce el aguante gastado al bloquear (escudo grande ~ 70+, mediano ~ 50-60, pequeño ~ 30-40).
  - **Absorción de guardia**: el % de daño que el escudo bloquea por tipo (100 % físico en la mayoría de escudos medianos y grandes).
  - Si se te acaba el aguante, la guardia se rompe (*guard break*) y quedás tambaleando.
- **Contra de guardia (guard counter)**: atacar fuerte justo después de bloquear. Es rápido, tiene mucho daño de equilibrio y no se puede cancelar. Es la herramienta defensiva clave de ER.
- **Equilibrio (poise) del jugador**:
  - Es una barra invisible de "vida de equilibrio" (el valor que muestra la ficha). Cada golpe le resta daño de equilibrio; al llegar a 0 te tambaleás y se recarga entera.
  - El jugador recupera el equilibrio completo tras ~30 s sin recibir golpes.
  - Umbrales útiles en PvE: 51 de equilibrio aguanta la mayoría de golpes normales; 101, los grandes.
- **Postura (stance) de los enemigos**: igual que el equilibrio, pero al romperse los deja expuestos a un **crítico frontal**. Se regenera tras 6-15 s sin recibir golpes.
- **Superarmadura (hyperarmor)**: algunos ataques (sobre todo los fuertes de armas grandes y los saltos) multiplican tu equilibrio durante la animación, así no te interrumpen al atacar.
- **Nivel de daño**: cada golpe tiene un nivel (corto, medio, largo, derribo) que decide qué animación de tambaleo produce.
- **Parry**: una ventana corta con escudo pequeño o arma ligera. Si sale bien, el atacante queda expuesto a una riposta.

### Nuestro estado
- ✅ **Parry** (Ronda 6+): ventana de 0,3 s, recuperación de 0,8 s si falla, el rival queda tambaleando 1,6 s y la riposta hace ×1,8.
- ✅ **Bloqueo y rotura de guardia**: chip de 12 % con escudo, más daño sin escudo, coste de aguante por golpe y multiplicador de rotura por arma.
- ✅ **Equilibrio con regeneración** y aturdimiento por golpe según el arma y la posición en el combo (Ronda 17). Fuerza y Aguante lo modifican (Ronda 18).
- ✅ **Superarmadura en el fuerte**: el golpe fuerte no se interrumpe durante su anticipación.
- ❌ Contraataque (bonus por golpear durante el ataque rival).
- ❌ Puñalada por la espalda / críticos con animación.
- ❌ Contra de guardia.
- 🟡 Estabilidad del escudo: está implícita (`guardia` del personaje y `guard_break_mult` del arma); no existe como estadística del escudo.

### Propuesta (alto impacto, en 1v1 el núcleo es el intercambio)
1. **Contraataque**: si el rival está en `WINDUP` o `ACTIVE`, el golpe hace ×1,15 de daño y ×1,3 de equilibrio (perforante ×1,25). Que salga el texto "¡Contra!" y un destello. Es barato de hacer y le da sentido a leer al rival.
2. **Contra de guardia** (sin botón nuevo en móvil): **atacar en los 0,35 s siguientes a bloquear** lanza un golpe específico.
   - Anticipación de 0,25 s, ×1,3 de daño, mucho daño de equilibrio y superarmadura.
   - Cuesta un 25 % más de aguante.
3. **Rotura de postura**: cuando el equilibrio del rival llega a 0 tras un golpe **fuerte o contundente**, en vez del aturdimiento corto queda **expuesto 1,2 s**. Atacar en ese tiempo hace un **crítico frontal** (×2,2, animación de 0,8 s, invulnerable mientras dura).
4. **Puñalada por la espalda**: atacar con ligero a < 1,5 m y en un cono trasero de 60° de un rival **que no está atacando** → crítico ×2. Hay que limitarla (no si el rival rueda o está montado) para que no se abuse con la cámara de móvil.
5. **Estabilidad del escudo** como estadística (`guard_boost` en `WeaponDef`: escudo 60, sin escudo 25), mostrada en la ficha; el coste de bloquear pasa a `daño × (1 − GB/100) × k`.
6. **Niveles de daño**: los golpes tienen un nivel (0 nada · 1 corto · 2 medio · 3 largo · 4 derribo) que elige la animación (`Hit_A` / `stun` / `knockdown`), en vez de un único tambaleo.

**Prioridad:** P0 (contraataque, contra de guardia) · P1 (rotura de postura + crítico, estabilidad) · P2 (puñalada, niveles de daño).

---

## 4. Estados alterados

Fuentes: https://eldenring.wiki.fextralife.com/Hemorrhage · https://eldenring.wiki.fextralife.com/Frostbite · https://eldenring.wiki.fextralife.com/Poison · https://eldenring.wiki.fextralife.com/Scarlet+Rot · https://eldenring.wiki.fextralife.com/Sleep · https://eldenring.wiki.fextralife.com/Madness · https://eldenring.wiki.fextralife.com/Death+Blight · https://eldenring.wiki.fextralife.com/Status+Effects · https://eldenring.wiki.gg/wiki/Status_Effects

### Cómo lo hace ER
Cada golpe con estado suma puntos a una barra oculta. Cuando la barra pasa el umbral (la resistencia del objetivo), el efecto se dispara. La acumulación **decae** con el tiempo. Tras dispararse, algunos estados no se pueden volver a acumular hasta que termina el efecto (congelación) y otros sí, enseguida (sangrado, sin enfriamiento).

| Estado | Resiste | Efecto en ER | Acumulación típica por golpe |
|---|---|---|---|
| Sangrado | Robustez | 15 % de la vida máx. + 100 (o 200) de golpe; jefes 70 % | 38-70 (dagas 38-50, katanas 45-50) |
| Congelación | Robustez | 10 % + 30 de golpe; +20 % de daño recibido durante 30 s; no se reacumula mientras dura | 55-65 |
| Veneno | Inmunidad | 0,07 % + 7/s durante 90 s (mortal: 0,14 % + 14/s, 30 s) | 36-90 |
| Podredumbre escarlata | Inmunidad | 0,18 % + 15/s durante 90 s (más fuerte que el veneno) | 50-75 |
| Sueño | Concentración | dormido/inmóvil ~ unos segundos (los jefes, menos) | 50-70 |
| Locura | Concentración | 15 % + 100 de golpe, −10 % + 30 de PM y un tambaleo; solo humanoides | 55-70 |
| Muerte (Perdición) | Vitalidad | muerte instantánea si se llena; los jefes son inmunes | flechas/hechizos concretos |

### Nuestro estado (Ronda 20)
- ✅ **Sangrado, Veneno y Congelación** con acumulación y decaimiento, más un bloqueo de 1,5 s tras dispararse. Umbral = 10 + resistencia. Barras en el HUD y sobre el rival, partículas y tintes, sonido.
- ✅ Fuentes: dagas (sangrado), Lobo de Hielo (congelación), infusiones Sangrante / Venenosa / Gélida.
- ❌ Podredumbre, Sueño, Locura y Perdición.
- ❌ Curas (bolos) y talismanes de resistencia.
- 🟡 Bloquear anula toda la acumulación (en ER el escudo deja pasar parte según su absorción).

### Propuesta
- **Bloqueo**: que pase un 30 % de la acumulación al bloquear (40 % sin escudo). Hace que el estado sea una amenaza también contra el que se tortuga.
- **Podredumbre (P2)**: un daño continuo más fuerte que el veneno, exclusivo de un eikon futuro o de un arma rara. En un 1v1 corto puede quedar redundante con el veneno; usarlo solo si diferenciamos (por ejemplo, que la podredumbre baje también la regeneración de energía).
- **Sueño (P2, con cuidado)**: en un 1v1 es frustrante. Alternativa propia: **"Aturdimiento de vínculo"**, 0,8 s de lentitud (−40 % de movimiento) y el eikon desmontado. Resiste Concentración.
- **Locura (P3)**: estallido + quita **Energía** (nuestros PM) + tambaleo corto. Encaja con la habilidad del Berserker.
- **Perdición**: ❌ no recomendada (la muerte instantánea no va con un 1v1 por rondas).
- **Curas**: un objeto de bolsillo por ronda (§9) que limpia la acumulación y los efectos activos.

**Prioridad:** P1 (bloqueo parcial, curas) · P2 (podredumbre o equivalente, sueño suave) · P3 (locura).

---

## 5. Armas

Fuentes: https://eldenring.wiki.fextralife.com/Weapons · https://eldenring.wiki.fextralife.com/Moveset · https://eldenring.wiki.fextralife.com/Power+Stance · https://eldenring.wiki.fextralife.com/Ashes+of+War · https://eldenring.wiki.fextralife.com/Affinities · https://eldenring.wiki.fextralife.com/Upgrades · https://eldenring.wiki.fextralife.com/Smithing+Stones · https://eldenring.wiki.fextralife.com/Somber+Smithing+Stones

### Cómo lo hace ER
- **Más de 30 clases** (dagas, espadas rectas, grandes espadas, colosales, curvas, katanas, estoques, hachas, martillos, lanzas, alabardas, guadañas, látigos, puños, garras, arcos, ballestas…). Cada clase comparte un **moveset**.
- **Moveset** por arma:
  - **Ligero (R1)**: cadena de 3-6 golpes.
  - **Fuerte (R2)**: se puede **cargar** para más daño y equilibrio.
  - **Ataque corriendo**, **tras voltereta/paso atrás**, **en salto** (ligero y fuerte) y **agachado**.
  - **Contra de guardia**.
  - **Críticos**.
- **A dos manos**: la Fuerza cuenta ×1,5 para requisitos y daño; cambia el moveset.
- **Doble empuñadura (power stance)**: dos armas de la misma clase dan una cadena propia con L1.
- **Cenizas de guerra**: habilidades (L2) que gastan PM. Se ponen en armas normales y fijan la **afinidad** (Pesada, Afilada, Calidad, Mágica, Fría, Fuego, Llama sagrada, Rayo, Sagrada, Sangre, Veneno, Oculta).
- **Mejora**: armas normales a +25 con piedras de forja 1-8 (2/4/6 piedras por nivel) y la piedra de dragón antigua al final. Las armas únicas van a +10 con **piedras sombrías** y no aceptan cenizas ni afinidad.

### Nuestro estado
- ✅ **7 armas**: espada y escudo, espada larga, hacha a dos manos, lanza, dagas, arco y ballesta. Cada una con daño, anticipación, recuperación, coste, alcance, combo y aturdimiento propios.
- ✅ **Combos de 3 golpes con nombre** (`ComboHit`, Ronda 16).
- ✅ Ligero y fuerte.
- ✅ **Estocada con dash** (ataque tras voltereta), **ataque en salto** (picado), **ataque montado** y **ataque tras dash montado**.
- ✅ Arma secundaria (cuerpo a cuerpo ↔ distancia) con cambio rápido.
- ✅ **Mejora +10 e infusiones** (Ronda 20).
- ❌ Fuerte cargado.
- ❌ Ataque corriendo propio: el ataque al correr es el ligero normal.
- 🟡 A dos manos: está fijo por arma (el hacha es a dos manos), no se puede alternar.
- ❌ Doble empuñadura (las dagas lo son de forma fija).
- 🟡 Habilidad de arma: solo el **Golpe sísmico** del Berserker gasta Energía; es del personaje, no del arma.
- ❌ Piedras sombrías / armas únicas.

### Propuesta
- **Fuerte cargado** (P1): mantener el botón más de 0,6 s → ×1,4 de daño, ×1,5 de equilibrio y superarmadura. Encaja con el gesto táctil de "mantener".
- **Ataque corriendo** (P1): si vas corriendo, el ligero hace una estocada o barrido de 1 golpe con poco avance. Da un "abridor" reconocible.
- **"Artes de arma" = nuestras Cenizas de guerra** (P0/P1, ver preguntas abiertas):
  - Una habilidad por arma (y no por personaje) que gasta **Energía**, en un botón "Arte" que reemplace a "Habilidad".
  - Al principio, una por arma de base (por ejemplo: Escudo → *Embestida de escudo*; Lanza → *Estocada impulsada*; Hacha → *Torbellino*; Dagas → *Danza sangrienta*; Arco → *Lluvia de flechas*; Ballesta → *Virote perforante*).
  - Más adelante, **intercambiables**, compradas o ganadas.
- **Afinidades elementales** (§2) como nuevas infusiones.
- **Armas únicas** (P2): armas de recompensa con arte fija, que solo se mejoran a +5 con "Piedra sombría" (ganada en logros o en dificultad Difícil).
- **Mejora**: mantener +10 (en móvil es la escala correcta). Opción P3: +15 cuando haya más contenido.

**Prioridad:** P0 (artes de arma básicas) · P1 (cargado, ataque corriendo) · P2 (únicas, afinidades) · P3 (doble empuñadura alternable, dos manos alternable).

---

## 6. Escudos y catalizadores

Fuentes: https://eldenring.wiki.fextralife.com/Shields · https://eldenring.wiki.fextralife.com/Greatshields · https://eldenring.wiki.fextralife.com/Glintstone+Staffs · https://eldenring.wiki.fextralife.com/Sacred+Seals

### Cómo lo hace ER
- **Escudo pequeño** (para parry, estabilidad baja), **mediano** (100 % de absorción física, estabilidad media) y **grande** (estabilidad muy alta, poco movimiento, contra de guardia potente).
- **Catalizadores**:
  - **Bastón** (hechicerías): su "Potencia de hechicería" escala con Inteligencia.
  - **Sello** (encantamientos): escala con Fe.
  - Se pueden llevar en la mano izquierda junto a un arma.

### Nuestro estado
- 🟡 Escudo único integrado en "espada y escudo" (más una variante sin escudo para el resto de armas). No hay escudos separados.
- ❌ Catalizadores.

### Propuesta
- **Separar el escudo como ranura de mano izquierda** (P2): pequeño (parry con ventana +0,05 s, estabilidad 35), mediano (estabilidad 60, el actual) y grande (estabilidad 85, −15 % de movimiento, no permite parry).
- **Catalizadores** (P3): solo si se decide que haya magia (§7). Propuesta: un **"Talismán de eikon"** como catalizador que escala con Vínculo y lanza las magias ligadas al eikon equipado. Así la magia no compite con el eikon, lo extiende.

**Prioridad:** P2 (escudos) · P3 (catalizador).

---

## 7. Magia

Fuentes: https://eldenring.wiki.fextralife.com/Sorceries · https://eldenring.wiki.fextralife.com/Incantations · https://eldenring.wiki.fextralife.com/Memory+Slots · https://eldenring.wiki.fextralife.com/Casting+Speed

### Cómo lo hace ER
- **Hechicerías** (Int) y **encantamientos** (Fe; algunos Arcano). Cada hechizo tiene requisitos, coste de PM, coste de estamina y número de **ranuras de memoria** (2 iniciales, hasta 10 con las Piedras de memoria y el talismán).
- **Velocidad de lanzamiento**: la Destreza acorta la animación (hasta un tope).
- Algunos hechizos se pueden **cargar** para más daño.
- Tipos: proyectiles, área, bufos (armas, cuerpo), curación, invocaciones de luz.

### Nuestro estado
- ❌ Sin magia del jugador.
- 🟡 La Sabiduría y la Devoción existen y alimentan magia/curación de las pasivas (Paladín: Luz sanadora). La "Energía" (barra violeta) es el equivalente a los PM.

### Propuesta (ver preguntas abiertas)
- Opción A, **"Magia de eikon"** (recomendada, P2):
  - Cada eikon ofrece **2 hechizos** que el jugador lanza a pie con Energía, aunque el eikon no esté invocado. Ejemplos: Fénix → *Chispa* (proyectil de fuego) y *Ala ígnea* (bufo); Lobo → *Aliento helado* (cono con congelación) y *Aullido* (bufo de velocidad).
  - Escalan con Sabiduría (ofensivos) o Devoción (bufos/curas).
  - **2 ranuras de memoria** fijas; sin catalizador o con el "Talismán de eikon".
- Opción B, **escuelas clásicas**: hechicerías y encantamientos completos. Es más contenido y más UI; desaconsejado en esta fase.
- Velocidad de lanzamiento = Destreza (ya existe `vel`).

**Prioridad:** P2 (opción A) · P3 (opción B).

---

## 8. Armadura, talismanes y Grandes Runas

Fuentes: https://eldenring.wiki.fextralife.com/Armor · https://eldenring.wiki.fextralife.com/Talismans · https://eldenring.wiki.fextralife.com/Great+Runes · https://eldenring.wiki.fextralife.com/Equip+Load

### Cómo lo hace ER
- **Armadura**: 4 piezas (casco, pecho, guantes, piernas). Cada una tiene peso, absorción por tipo, resistencias y equilibrio. Lo más pesado da más equilibrio. El conjunto con más equilibrio (Toro-Cabra) llega a ~100.
- **Talismanes**: 1 ranura al empezar, hasta 4 (con las Medallas de talismanes). Son bonos pasivos: +% de daño en ciertas condiciones, −daño de equilibrio recibido (Talismán del Toro-Cabra: −25 %), estamina, carga, críticos, etc. Algunos tienen versiones mejores (+1, +2, +3).
- **Grandes Runas**: se activan con un Arco rúnico y dan un bonus grande (por ejemplo, Godrick: +5 a todos los atributos; Radahn: +PV/PM/estamina; Morgott: +25 % de PV). Se pierden si morís.

### Nuestro estado
- ✅ Armadura de 4 ranuras, 9 conjuntos (5 iniciales y 4 a la venta) con peso, absorción, equilibrio y resistencias. Se ve en el personaje. El rival lleva armadura (Ronda 19).
- ❌ Talismanes.
- ❌ Grandes Runas.

### Propuesta
- **Talismanes = "Amuletos"** (P1):
  - 2 ranuras (la segunda se desbloquea en el nivel de cuenta 5) y 10-12 amuletos iniciales con un efecto claro y número visible.
  - Ejemplos: *Toro-Cabra* (−20 % de daño de equilibrio recibido), *Colmillo* (+12 % de daño en contraataque), *Daga maldita* (+20 % de daño crítico), *Cuerno firme* (+20 % de Robustez), *Escarabajo verde* (+8 % de regeneración de estamina), *Vínculo ardiente* (+15 % de duración del eikon), *Arquero errante* (+10 % de daño de flecha).
  - Se compran en la Tienda o se ganan como recompensa. Se equipan en la ficha (ranura nueva en `CharSheet`).
- **"Grandes Runas" → "Sellos de eikon"** (P2): un bonus fuerte ligado a una victoria especial (por ejemplo, ganar en Difícil con cada eikon). Solo se lleva uno, y se activa al invocar al eikon (en lugar del Arco rúnico). Por ejemplo, *Sello del Fénix*: tras invocar, +10 % de PV máx. el resto de la ronda.
- Mostrar en la ficha los **umbrales de equilibrio** (por ejemplo: "aguanta 1 golpe ligero de hacha sin tambalearte").

**Prioridad:** P1 (amuletos) · P2 (sellos de eikon).

---

## 9. Consumibles

Fuentes: https://eldenring.wiki.fextralife.com/Flask+of+Crimson+Tears · https://eldenring.wiki.fextralife.com/Flask+of+Wondrous+Physick · https://eldenring.wiki.fextralife.com/Consumables · https://eldenring.wiki.fextralife.com/Pots

### Cómo lo hace ER
- **Frascos**: el Frasco de Lágrimas Carmesí (vida) y el de Lágrimas Cerúleas (PM) se reparten entre 4 y 14 cargas en total y se recargan en los lugares de gracia. La mejora del frasco (+0 → +12) sube la cantidad que cura. Beber cuesta una animación de ~1,1 s en la que te pueden castigar.
- **Frasco de Físico Maravilloso**: mezclás 2 lágrimas cristalinas con efectos temporales (bufos, curas, equilibrio).
- **Arrojables**: vasijas (fuego, veneno, sangre, sagradas), dardos, cuchillos.
- **Grasas**: elemento o estado temporal en el arma.
- **Bufos de comida** (carnes curadas), **bolos** (curan estados).

### Nuestro estado
- ❌ Sin consumibles. La única cura es la pasiva del Paladín (Luz sanadora).

### Propuesta (un 1v1 por rondas necesita que curarse sea una decisión arriesgada)
- **"Lágrima carmesí"** (P1):
  - **1 carga por ronda** (2 con un amuleto), que cura el 35 % de la vida máx. en 1,0 s. La animación se puede castigar: te deja caminar al 30 % y no se puede cancelar.
  - Se usa con un botón táctil nuevo "Curar" junto al joystick.
  - La IA de nivel Difícil castiga el trago (§14).
- **Bolsa de ronda** (P2):
  - **1 objeto** elegido en el lobby entre bolo (limpia estados), vasija arrojable (fuego / hielo / veneno, en arco), grasa (estado al arma durante 20 s) o físico (un bufo de 15 s).
  - Se compran con oro: es un sumidero de economía.
- Sin PM separados: la Energía ya se regenera.

**Prioridad:** P1 (lágrima carmesí) · P2 (bolsa de ronda).

---

## 10. Cenizas de espíritu → nuestros eikons

Fuentes: https://eldenring.wiki.fextralife.com/Spirit+Ashes · https://eldenring.wiki.fextralife.com/Spirit+Calling+Bell · https://eldenring.wiki.fextralife.com/Mimic+Tear+Ashes

### Cómo lo hace ER
- Las **cenizas** se invocan con la Campana de invocación cerca de una piedra de renacimiento (sobre todo en jefes). Cuestan PM (y algunas, PV).
- Cada una tiene una IA propia, se mejora con las Hierbas de tumba (+10) y se queda hasta morir o hasta que termina la pelea.
- La **Lágrima mímica** copia tu equipo.
- No se pueden usar en PvP.

### Nuestro estado (es nuestro sistema central)
- ✅ **4 eikons**:
  - Fénix: montable, especial *Llamarada*.
  - Lobo de Hielo: montable, especial *Colmillo* (congela).
  - Grifo: montable, especial *Vendaval*.
  - Gólem: compañero, golpe de área.
- ✅ Medidor de invocación que se llena con el tiempo y los golpes, duración limitada, llamada a la montura y escalado con **Vínculo**.
- ✅ Especiales con daño elemental.
- ❌ Mejora del eikon.
- ❌ Más eikons y mayor variedad de compañeros.
- ❌ Eikon "mímico".

### Propuesta
- **Mejora del eikon** (P1): +0..+5 con **"Esencia de eikon"** (un material nuevo, ganado al ganar con ese eikon equipado). Cada nivel da +8 % de vida, +6 % de daño del especial y −4 % de enfriamiento. Reutiliza la UI del Herrero (pestaña "Eikons → Vínculo").
- **Coste de invocación**: se mantiene el medidor (es más legible en móvil que gastar PM).
- **Más compañeros** (P2): un eikon **arquero** (a distancia, frágil) y uno **sanador** (cura el 2 %/s cerca), para que haya decisiones entre montar y acompañar.
- **"Reflejo"** (P3): un eikon que copia tu arma con la mitad de vida (la Lágrima mímica); muy caro.
- **Mapeo de nombres**: "Ceniza" → "Eikon"; "Campana" → el botón "Eikon"; "Hierba de tumba" → "Esencia".

**Prioridad:** P1 (mejora de eikon) · P2 (compañeros nuevos) · P3 (reflejo).

---

## 11. Combate a caballo (Torrent)

Fuentes: https://eldenring.wiki.fextralife.com/Torrent · https://eldenring.wiki.fextralife.com/Mounted+Combat · https://eldenring.wiki.gg/wiki/Torrent

### Cómo lo hace ER
- Torrent tiene **vida y postura propias**. Si se le rompe la postura, el jinete cae y queda aturdido varios segundos (muy castigable). Si Torrent muere, revivirlo cuesta un frasco.
- **Ataques montados**: ligero y "de arrastre" (fuerte) a izquierda o derecha. El de arrastre se carga arrastrando el arma por el suelo y con armas grandes puede lanzar al aire.
- No se puede bloquear ni rodar montado: la defensa es el **dash** (sin i-frames) y el **doble salto**, que esquiva barridos.
- Montado se usa una sola mano. Los arcos funcionan; la ballesta tiene un truco de recarga en el aire.
- No se puede montar en PvP ni en mazmorras.

### Nuestro estado (más profundo que ER en este eje)
- ✅ Monturas eikon, ataques a caballo con más alcance y arco, lanza con daño montado extra, dash montado con embestida y derribo, dash + ataque.
- ✅ Disparo libre montado y **tiro parto**.
- ✅ Brinco de lobo y grifo; el fénix vuela.
- ✅ Jinete girado en la silla; llamada a la montura (Ronda 17).
- ✅ Derribo del jinete con golpes fuertes (probabilidad).
- ❌ Postura de la montura (el derribo es aleatorio, no por postura).
- ❌ Ataque de arrastre / cargado montado.
- ❌ Doble salto montado.
- 🟡 Las monturas solo tienen vida cuando van sin jinete.

### Propuesta
- **Postura de la montura** (P1): sustituir el derribo aleatorio por una **barra de postura de la montura** (visible bajo el icono del eikon). Al romperse, el jinete cae con 1,0 s de aturdimiento. Es más justo y legible, y los golpes contundentes y la lanza la rompen más.
- **Ataque de arrastre** (P1): mantener el fuerte montado → la anticipación se alarga mientras se mantiene (hasta 1,2 s) y al soltar hace ×1,5 de daño y mucho daño de postura a la montura rival. Lado izquierdo/derecho según hacia dónde está girado el jinete (ya tenemos `rider_yaw`).
- **Doble salto** (P2): solo lobo y grifo. Un segundo brinco en el aire para esquivar áreas (ya existe la esquiva de áreas en el aire).
- **Vida de la montura con jinete** (P2): parte de los golpes bajos (barridos, áreas) dan a la montura en vez de al jinete. Agrega lectura táctica sin cambiar el núcleo.

**Prioridad:** P1 (postura de montura, arrastre) · P2 (doble salto, vida compartida).

---

## 12. Movimiento

Fuentes: https://eldenring.wiki.fextralife.com/Controls · https://eldenring.wiki.fextralife.com/Equip+Load · https://eldenring.wiki.fextralife.com/Stealth · https://eldenring.wiki.gg/wiki/Dodge

### Cómo lo hace ER
- **Voltereta según la carga**:

| Carga | Voltereta | I-frames aprox. (a 30 fps) | Recuperación |
|---|---|---|---|
| Ligera (< 30 %) | larga y rápida | 13 | corta |
| Media (< 70 %) | normal | 13 | normal |
| Pesada (≤ 100 %) | corta y lenta | 12 | larga |
| Sobrecargada | no hay voltereta (solo un tropiezo) | — | — |

- **Paso atrás** (backstep): sin dirección; i-frames cortos y se encadena rápido con ataques.
- **Salto**: el ataque en salto rompe mucho equilibrio y esquiva barridos.
- **Correr**: gasta estamina de forma continua.
- **Agacharse**: silencioso, para ataques sorpresa.
- **Sigilo**: menos ruido y cero detección con ciertos objetos/hechizos.

### Nuestro estado
- ✅ Voltereta estilo souls (arranque vulnerable, 12 i-frames, recuperación), modificada por carga (Ronda 19) y Destreza (+1/+2 i-frames).
- ✅ Correr (con toggle en móvil) y salto con ataque en salto y esquiva de áreas.
- ✅ Estocada con dash, búfer de voltereta → estocada.
- ❌ Paso atrás.
- ❌ Agacharse y sigilo (en un 1v1 en arena abierta aportan poco).

### Propuesta
- **Paso atrás** (P2): voltereta sin dirección (con el joystick neutro) = paso atrás de 6 i-frames, 1,2 m, recuperación corta y −30 % de coste. Enlaza con el ataque ligero ("ataque de paso atrás"). En móvil sale gratis con el mismo botón de Dash.
- **Agacharse / sigilo**: ❌ fuera de alcance para el 1v1. Podría volver solo si se añaden modos con escenario (P3).

**Prioridad:** P2 (paso atrás) · P3 (sigilo).

---

## 13. Reglas de aguante (estamina)

Fuentes: https://eldenring.wiki.fextralife.com/Stamina · https://eldenring.wiki.fextralife.com/Endurance · https://eldenring.wiki.gg/wiki/Stamina

### Cómo lo hace ER
- Atacar, rodar, correr, saltar y bloquear gastan estamina; los costes dependen del arma (pesada = más).
- Se regenera tras un breve retraso; **más lento mientras bloqueás**; a caballo, igual.
- Quedarte sin estamina mientras bloqueás = **guardia rota**.
- Se puede atacar con 1 punto de estamina (el ataque sale entero y te deja en negativo hasta 0).
- Algunos bufos y talismanes suben la regeneración (Escarabajo verde, físico de estamina).

### Nuestro estado
- ✅ Costes por arma y acción, retraso de regeneración de 0,6 s, regeneración en reposo más rápida, drenaje al bloquear y al correr, agotamiento de 1,5 s, rotura de guardia sin aguante.
- ✅ La carga modifica la regeneración (Ronda 19); la congelación la reduce (Ronda 20).

### Propuesta
- **Regeneración más lenta con la guardia alzada** (P2): ×0,5 de regeneración mientras bloqueás (además del drenaje). Reduce la tortuga.
- Dejar el agotamiento propio (el de ER no existe, pero nuestra versión es legible en móvil).
- **Amuleto de regeneración** (§8).

**Prioridad:** P2.

---

## 14. IA y patrones de jefes

Fuentes: https://eldenring.wiki.fextralife.com/Bosses · https://eldenring.wiki.fextralife.com/Margit,+The+Fell+Omen · https://eldenring.wiki.fextralife.com/Malenia,+Blade+of+Miquella · https://eldenring.wiki.fextralife.com/Input+Reading

### Cómo lo hace ER
- **Ataques retrasados**: la anticipación es larga o variable (Margit, Morgott) para castigar a quien rueda por reflejo.
- **Combos de longitud variable**: la misma apertura puede terminar en 2, 3 o 5 golpes; a veces con un golpe "retrasado" al final.
- **Fases**: al 50-60 % de vida el jefe cambia el moveset, agrega elemento o área y acelera.
- **Ventanas de castigo**: tras ciertos combos o áreas el jefe queda expuesto; las lee el jugador.
- **Lectura de entradas**: algunos jefes reaccionan al botón de curarse o de atacar.
- **Agresividad adaptativa**: si te alejás, usa proyectiles o saltos de cierre de distancia.

### Nuestro estado
- ✅ `AIController` con 3 dificultades (`AIDifficulty`): respiros, bloqueo, parry, voltereta ante golpes, esquiva de áreas con salto, uso del eikon y del especial, puntería con adelanto en Difícil.
- 🟡 La IA usa combos, pero no **varía su longitud**, no **retrasa** golpes y no tiene **fases**.
- ❌ No hay jefes / rivales únicos.

### Propuesta
- **Golpes retrasados** (P1): un `ComboHit.delay_variants` (por ejemplo, +0,25 s / +0,45 s) que solo usa la IA (y, en el futuro, el arte de arma). En Normal sale un 20 % de las veces, en Difícil un 40 %.
- **Combos variables** (P1): la IA corta el combo tras 1, 2 o 3 golpes según la distancia y la vida.
- **Lectura de curación** (P1, con la lágrima): en Difícil, si el jugador bebe a < 6 m, la IA hace un dash-ataque.
- **Fases del rival** (P2): al 50 % de vida, el rival invoca al eikon si lo tiene cargado, o entra en "furia" (+10 % de velocidad, cambio de color).
- **Modo "Duelo de campeones" con jefes** (P3): rivales únicos con armas y movesets propios (el Caballero Errante, la Cazadora de Hielo…), con fases y recompensas únicas (armas únicas, sellos de eikon).

**Prioridad:** P1 (retrasos, combos variables, lectura de curación) · P2 (fases) · P3 (jefes).

---

## 15. Progresión y economía

Fuentes: https://eldenring.wiki.fextralife.com/Level · https://eldenring.wiki.fextralife.com/Runes · https://eldenring.wiki.gg/wiki/Level · https://eldenring.wiki.fextralife.com/Soft+Caps

### Cómo lo hace ER
- **Costo del siguiente nivel en runas**, con x = ((nivel + 81) − 92) × 0,02 y x ≥ 0: `costo = ((x + 0,1) × (nivel + 81)² + 1)` redondeado. Los niveles bajos cuestan muy poco y la curva crece aproximadamente con el cuadrado del nivel. Referencias aproximadas:

| Nivel | Runas para el siguiente |
|---|---|
| 10 | ~ 1 000 |
| 50 | ~ 33 000 |
| 100 | ~ 160 000 |
| 150 | ~ 395 000 |

- **Topes blandos** típicos (§1): Vigor 40/60, Mente 50-55, Aguante 50, ofensivos 55/80. El "meta" de PvP es el nivel 125-150 con +25.
- Las runas también son moneda (tienda, mejoras); se pierden al morir y se recuperan una vez.

### Nuestro estado
- ✅ XP de cuenta y de personaje, niveles, 2 puntos de atributo por nivel y 1 de habilidad por nivel, árbol de habilidades por rol.
- ✅ Oro por partida con multiplicador por dificultad; cristales (moneda de muestra).
- ✅ Tienda (armas, armaduras, eikons, materiales).
- ✅ Piedras de forja como recompensa (Ronda 20).
- 🟡 La curva de XP es propia (`Progression.xp_at_level`); no hay techo de nivel competitivo ni emparejamiento por nivel (el rival es la IA a tu nivel).
- ❌ No hay sumideros de oro recurrentes más allá de mejoras y compras únicas.

### Propuesta (sin "runas")
- **Separar XP y moneda** (ya está así): XP = progreso y oro = economía. **No** perder nada al morir (en un 1v1 por rondas sería punitivo).
- **Curva de XP**: mantener el crecimiento cuadrático suave (estilo ER, pero comprimido): `xp(n) ≈ 100 × n^1,8`. Poner un **nivel máximo de 40** por personaje (80 puntos de atributo), así los topes blandos (20/40) son decisiones reales.
- **Sumideros recurrentes**: bolsa de ronda (§9), infusiones, mejoras de eikon, cosméticos. Los cristales, para cosméticos y no para poder (es la regla anti pay-to-win de cara a la publicación).
- **Recompensas por desafío**: primera victoria del día (×2), victoria perfecta (ya existe), logros que dan piedras sombrías o esencias.

**Prioridad:** P1 (nivel máximo y curva revisada) · P2 (sumideros, desafíos diarios).

---

## 16. Balance PvP

Fuentes: https://eldenring.wiki.fextralife.com/PvP · https://eldenring.wiki.fextralife.com/Invasions · https://eldenring.wiki.fextralife.com/Patch+Notes · https://eldenring.wiki.fextralife.com/Poise (tabla PvP)

### Cómo lo hace ER
- En PvP se aplican **modificadores propios**:
  - el daño de los jugadores se escala distinto (~ por tipo de arma y hechizo);
  - el Frasco de Lágrimas Carmesí cura menos al invadir;
  - el anfitrión con aliados recibe menos;
  - el daño de equilibrio entre jugadores sigue una tabla propia (por ejemplo, ligero de daga ~40, de espada recta ~110, de colosal ~500).
- Los parches ajustaron muchas veces la **superarmadura**, el **daño de equilibrio de los saltos** y la acumulación de **sangrado** en PvP (de ahí los valores menores de sangrado para jugadores).
- No se puede montar a Torrent en PvP.

### Nuestro estado
- El juego es 1v1 contra la IA; no hay multijugador. El balance está pensado para el jugador contra la IA.

### Propuesta
- Diseñar desde ya con **"reglas de duelo"** por si llega el PvP (P3):
  - multiplicador global de daño en duelo ×0,8 (más intercambios);
  - estados con un 70 % de acumulación;
  - curación con un 70 % de eficacia;
  - superarmadura solo en golpes fuertes y saltos;
  - topes de equilibrio.
- **Tabla de daño de equilibrio por arma** explícita en `WeaponDef` (hoy deriva del daño × 2). Sirve tanto para PvE como para PvP (P1, va con el §3).
- Telemetría local (P2): registrar en las partidas qué armas o eikons ganan, para balancear con datos.

**Prioridad:** P1 (tabla de equilibrio) · P2 (telemetría) · P3 (reglas de duelo PvP).

---

## 17. Hoja de ruta por fases

Ordenada por impacto en la sensación de combate y por dependencias.

### Fase 1: "El intercambio" (núcleo del 1v1)
1. ✅ (Ronda 24) **Contraataque**: ×1,15 de daño y ×1,3 de equilibrio, con texto y destello (§3). *Sin dependencias.*
2. ✅ (Ronda 24) **Tabla de daño de equilibrio por arma** y **subtipos físicos** (estándar, contundente, cortante, perforante) en `WeaponDef` y `ComboHit` (§2, §16).
3. ✅ (Ronda 24) **Contra de guardia**: atacar en los 0,35 s tras bloquear (§3). *Depende de 2.*
4. ✅ (Ronda 24, animación provisional) **Rotura de postura + crítico frontal**, con animación e invulnerabilidad (§3). *Depende de 2.*
5. ⏸ (pospuesto por el usuario) **Lágrima carmesí**: 1 carga por ronda, botón "Curar" y castigo de la IA (§9, §14).
6. Pruebas: `test_counter.gd`, `test_guard_counter.gd`, `test_stance_break.gd`, `test_flask.gd`.

### Fase 2: "Identidad de las armas"
1. ✅ (Ronda 21) **Artes de arma** (Cenizas de guerra propias) con Energía: una por arma; el botón "Habilidad" pasa a ser "Arte" (§5). *Depende de que se decidan las preguntas 1-2.*
2. ✅ (Ronda 24) **Fuerte cargado** (mantener) y **ataque corriendo** (§5).
3. 🟡 (Ronda 24: regeneración ×0,5 con guardia; estabilidad por escudo pendiente) **Estabilidad del escudo** + **regeneración ×0,5 con guardia alzada** (§3, §13).
4. 🟡 (Ronda 24: golpes retrasados; combos variables ya existían por cadena aleatoria) **Golpes retrasados y combos variables de la IA** (§14).
5. Pruebas por cada arte y prueba de IA con retrasos.

### Fase 3: "Construcciones" (builds)
1. **Amuletos** (talismanes): 2 ranuras y 10-12 amuletos; ficha y Tienda (§8).
2. **Afinidades elementales** (Ardiente, Mágica, Sagrada) que dividen el AR (§2, §5).
3. **Mejora de eikon +5** con Esencia (§10).
4. **Postura de montura + ataque de arrastre** (§11).
5. **Nivel máximo 40 y curva de XP revisada** + marcas de tope blando en la ficha (§1, §15). Guardado v8 con migración.

### Fase 4: "Profundidad"
1. **Bolsa de ronda**: bolo, vasija, grasa, físico (§9).
2. **Acumulación parcial al bloquear** + estado nuevo (podredumbre o aturdimiento de vínculo) (§4).
3. **Paso atrás**, **doble salto montado**, **niveles de daño** (§3, §11, §12).
4. **Escudos separados** (pequeño, mediano, grande) (§6).
5. **Fases del rival** y **lectura de curación** en Difícil (§14).

### Fase 5: "Contenido y largo plazo"
1. **Magia de eikon** (2 hechizos por eikon, 2 ranuras) (§7).
2. **Armas únicas** con piedra sombría (§5).
3. **Eikons compañeros nuevos** (arquero, sanador) (§10).
4. **Duelo de campeones** (jefes con fases) y **sellos de eikon** (§8, §14).
5. **Telemetría de balance**; reglas de duelo PvP si hay multijugador (§16).

---

## 18. Preguntas abiertas

1. ✅ **Decidido (Ronda 21) — Artes de arma:** **intercambiables** desde una colección (no fijas). Implementado: `WeaponArts` con *Estocada impulsada* (inicial) y *Torbellino* (Tienda → Artes, 300 de oro); se cambian por arma en Armas → «Arte». Usan el botón Habilidad cuando el personaje no tiene habilidad propia (el Golpe sísmico del Berserker tiene prioridad). **Curación/lágrimas: pospuesto** (decisión del usuario: todavía no).
2. 🟡 **Botones en móvil:** resuelto en parte con botones **contextuales** (Ronda 21): Parry desaparece montado, «Objetivo» solo con 2+ objetivos, «Hechizo»/«↻» solo a pie con hechizos equipados, Habilidad pasa a «Arte». Pendiente: ¿anillo contextual si se suman más acciones?
3. ✅ **Decidido (Ronda 21) — Magia = magia de eikon:** varias **ranuras** configurables en Eikons → «Hechizos» (2 base, +1 con Sabiduría o Devoción ≥ 18, +1 con ≥ 30). Cada eikon poseído enseña un hechizo (Fénix: Chispa ígnea; Lobo: Aliento helado; Grifo: Saeta del vendaval; Gólem: Piel de piedra). Ofensivos escalan con Sabiduría, protecciones con Devoción. Se lanzan a pie (X / «Hechizo»), cuestan Energía. Pendiente: más hechizos por eikon y uso por la IA.
3b. ✅ **Decidido (Ronda 21) — Montado sin parry:** la opción de parry se elimina montado (botón oculto y entrada bloqueada).
3c. ✅ **Decidido (Ronda 21) — Botón de cambio de objetivo:** solo visible con más de un objetivo válido.
4. **Críticos y puñaladas por la espalda:** ¿te parecen bien en un 1v1 con cámara de móvil, o preferís solo la riposta (parry y rotura de postura) para evitar frustración?
5. **Estados nuevos:** ¿sueño y locura entran, o nos quedamos con 3-4 estados y los hacemos más distintos entre sí?
6. **Curación:** ¿1 lágrima por ronda para todos, o que sea una ventaja del Paladín (más cargas) para preservar su identidad?
7. **Nivel máximo:** ¿40 por personaje? ¿Habrá reinicio de temporada?
8. **Monetización:** ¿confirmamos que los cristales sean solo cosméticos (sin poder pagado)?
9. **Multijugador:** ¿hay intención de PvP real (en línea o local)? Cambia cuánto invertir ahora en "reglas de duelo".
10. **Audio definitivo:** ¿la Fase 2 incluye reemplazar el audio provisional CC0 por el final que vas a conseguir?

---

*Mantener este documento al día en cada ronda: marcar el estado (✅/🟡/❌) y mover las tareas terminadas de la hoja de ruta.*
