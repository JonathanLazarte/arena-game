# Diseño — referencia (reglas duraderas)

Datos en código: `scripts/data/stun_rules.gd`, `scripts/data/boss_abilities.gd`, `scripts/data/attributes.gd`.

## Principios de balance
- Inspiración souls (curvas tipo Elden Ring, números propios): ganancias por tramos con rendimientos decrecientes (primeros ~25–30 puntos rinden, luego cae).
- Todo ataque fuerte o de jefe se telegrafía; al soltarse solo se evita con voltereta en la ventana justa (no caminando).
- Ningún recurso gratis: las habilidades de jefe no tienen recarga pero cuestan aguante, maná (= Energía) o vida.

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
| estocada | 30 aguante | 1,6× fuerte | 60 | inmune | carga 1,6 s siguiendo; embestida 12 m a 30 m/s con giro 140°/s → solo voltereta |
| carga_area | 35 maná | 1,4× (mágico) | 45+magia | ×5 | inmóvil 1,8 s, AoE 4,5 m; interrumpible |
| rafaga | 30 maná | 0,55× ligero c/u | 14+magia c/u | ×1,5 | 3 tajos, 18 m/s, giro 55°/s durante 0,6 s: caminar no escapa, correr a distancia sí |
| escudo_mana | 25 maná | — | — | inmune | 1,5 s invulnerable total, mitad de velocidad |
| combo_falso | 38 aguante | 0,7/0,7/0,9/1,7× ligero | 4/4/18/45 | ×1,3 | pausa falsa antes del 4.º (t=1,75 s) |
| salto_caida | 15 vida | 1,5× fuerte | 50 | inmune en el aire | marca sigue hasta 1,25 s, cae a 1,65 s, AoE 3,5 m |
- Coste de vida: no se puede usar si dejaría la vida ≤ 0. IA: elige por distancia/situación y huye de marcas/AoE, corre de lado ante la ráfaga, rueda la estocada.

## Arcos
- Toque = disparo normal. Mantener tras tensar 0,9 s = cargado; soltar antes = normal.
- Arco «potente»: ×2,2 daño (×2,4 con Ojo de halcón), ×1,4 velocidad, ×2,5 aturdimiento. Ballesta «triple»: 3 virotes en abanico (±0,18 rad), ×0,7 daño. `WeaponDef.charged_shot` lo fuerza.

## Calibración de atributos
- Velocidad de ataque (Destreza): 0,8 %/pt hasta 25, 0,5 % hasta 40, 0,3 % después; tope +25 % (antes +16 %).
- Un punto de Destreza ≈ 40 % del daño que da un punto de Fuerza en «escala» (2 %/pt temprano), compensado por velocidad, voltereta e i-frames.
- La ficha muestra la velocidad de ataque final.

## Pendiente
- Erika: falta el FBX de Mixamo.
