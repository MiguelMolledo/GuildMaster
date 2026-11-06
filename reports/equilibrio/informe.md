# Equilibrio con todo encendido · informe (rama equilibrio, 2026-11-05)

Base: `origin/main` ac3a238 (medida en un worktree limpio, `GuildMaster-eqbase`). Después: la rama `equilibrio`.
Medidas: `tools/equilibrio/measure.py` (full_player 3 años × semillas 1-4, 2 a la vez; pacing 5 semillas) y
`sim_runner` para los bots de cada sistema. Un JSON pequeño por punto en `reports/equilibrio/punto_*.json`; los
resúmenes completos en `00_base_*.json`, `all1-3.json`, `fun1-2.json`, `eq10_*.json`, `fin_pacing.json`.

## Tabla final: jugador completo (full_player, 3 años × 4 semillas, mediana [mín-máx])

| Medida | Antes | Después | Diana |
|---|---|---|---|
| Ciudadano, día | 21 [19-24] | 13,5 [11-15] | año 2 (9-16) ✅ |
| Hueco máximo entre decisiones (3 años) | 136 s [119-176] | 38 s [31-42] | < 60 s ✅ |
| Hueco máximo, año 1 | 109 s [61-137] | 15 s [10-33] | < 60 s ✅ |
| Horas paradas por obras (cabeza) | 68 [58-81] | 0 | — ✅ |
| Atascos | 7,5 [6-11] | 0,5 [0-1] | — |
| Viajes / tratados / caravanas | 0 / 0 / 0 | 1 / 1 / 0 | — (caravanas: no sobran espadas) |
| Mecánicas tocadas | 15 [14-17] | 17,5 [17-18] | ≥ 14 ✅ |
| Neto/día año 1 · 2 · 3 | 30 · 18 · 27 | 34 · 22 · 121 | ≥ 25 de media ✅ |
| Oro al final | 572 [161-621] | 1.208 [585-1.446] | — |
| Encargos fallidos | 3,5 | 1,5 | — |
| Empleados con hambre (peor parte de horas) | 73 % [65-82] | 0 % | ≤ 50 % ✅ |
| Niños con hambre | 0 % [0-88] | 0 % | ≤ 50 % ✅ |
| Diversión media del pueblo | 19 | 37 | banda propuesta 35-65 ✅ |
| Peor vecino con diversión baja | 83 % | 57 % | — |
| Forasteros al día (media · mediana) | 5,7 · 4 | 5,8 · 4 | 2-6 de media ✅ |
| Boda, día | 18 [14-22] | 19 [17-21] | ≥ 2/3 ✅ |
| Órdenes rechazadas | 0 | 0 (1 en 1 de 16 partidas) | 0 ⚠️ |
| Errores del motor · libro | 0 · 0 | 0 · 0 | 0 ✅ |
| Paso medio | 2,6 ms | 3,7 ms (máquina cargada) | < 5 ms ✅ |

## Por punto

| # | Qué | Antes | Después |
|---|---|---|---|
| 11 | Plazos reales de los encargos de fiesta en todos los bots | pacing con fiestas y vida: 4/5 semillas fuera (mejoras sin abrir), hueco 198 s, 42 oro/día; festive: 3 encargos fallidos | 0 fuera, hueco máx. 35 s, 76 oro/día; festive: 0,3 fallidos, todas sus dianas |
| 1 · 10 | Un regalo al día; cortejar a diario | regalos sin tope | el panel lo dice; boda igual (días 17-21); el cortejo ya no cuesta en el año 1 (31,6 sin metas / 33,9 con ellas) |
| 2 | Préstamo de urgencia y embargo | chaos semilla 1: muerta desde el día 8 | bot broke (broke_forge): 5/5 toman el préstamo, lo devuelven y acaban con 103-266 de oro; 0 ruinas |
| 9 · 12 | Obras de noche / a medio ritmo | ver tabla | ver tabla; experto (10 × 24 días): neto 9-24 70 → 80/día, sumideros 0,34 → 0,32 (bandas intactas) |
| 3 | Ciudadano en el año 2 | día 21 | día 13,5 (11-15) |
| 7 | Prima de calidad en la capital y reputación de fuera | merchant: ventas fuera 637, tratados 0,83 | 766, tratados 1,67, llegadas 1,8 → 2,7; full_player viaja y firma en 4/4 |
| 5 | Pecha por patrimonio al cerrar el año | — | 0 hasta 1.000 y 4/8/12 % por tramos; en 3 años muerde poco (patrimonio 1.000-1.600) |
| 13 | Fama del taller 0,5-2,0 | — | en el mostrador y el panel de producción; gancho `contest_won` para fiestas |
| 15 | Bolsa de los hogares | vecinos en la taberna ~2/noche | 6,2/noche (diana 6-12); clientes 26 → 28,3, explotación 68 → 92, quejas 9,3 → 4,5 (comarca [4,8] → [3,6], jornal 7/9) |
| 15 · fama | Fama de la taberna (owner: banda [1,5, 4,0] si los nobles no llegan antes del año 2) | 1,76; con la bolsa, 4,0 en las 5 semillas (el tope de 0,25 cada noche), fama 3 el día 11 | «no esperó» pesa 0,5 en la fama (antes 0,6): 3,61 (3,15-3,96), fama 3 los días 12-15; `inn_fame3_day` [8, null] y la banda [1,5, 4,0]; QA inn en verde |
| Vida | Hambre, diversión, forasteros | ver tabla | ver tabla |
| D16 · 8 | Demanda del mostrador; mostrador con un empleado | ×0,38 del salario | ×0,34 (D16 le quita un poco); la demanda de la espada no se mueve: el mostrador vende muy poco. La diana ×2 espera la clientela de comarca de interiores |
| D19 | «Retirarse» | apagado | encendido, con confirmación y pantalla final (prueba de la UI y capturas) |
| Punto 13 · ritmo | La banda con fiestas pasa a diana | propuesta | diana; pacing en `_festivals`, fuera de `_no_life`; 0 fallos |

## Después de la revisión (2026-11-05)

| Cosa | Causa | Arreglo | Medido |
|---|---|---|---|
| La orden rechazada (1 de 16 partidas) | Del bot: `artisan_expert` compraba `forge_production_2` (se lleva 5 lingotes del almacén) y en el mismo minuto pedía forjar un martillo con esos lingotes → `work_at` / `missing_inputs` (reproducido: semilla 1, día 14, minuto 21290). No es un hueco del juego: la pantalla ya da el motivo | El minuto en que compra una mejora no planea trabajo | Semilla 1 sin rechazos; 8 partidas de 3 años, 0 órdenes rechazadas |
| Caravanas a 0 | Solo salían con espadas que la villa no quería (nunca sobran), y la cuota se firmaba y se rompía (3 de 4 semillas) | Con cuota firmada, full_player aparta cada estación sus espadas, compra el carro y las manda; firma solo si puede servirla | Caravanas 0 → 1,5 (5, 1, 0, 2); ventas en la capital hasta 2.259; cuotas rotas 3/4 → 1/4; neto año 2 24 → 39/día, año 3 98 → 86, oro final 990 → 957. Ninguna banda cambia |


## Tras la parada (2026-11-06): informes de jugador y fiestas

| Cosa | Antes | Después | Cómo |
|---|---|---|---|
| Obras maestras (bot de ritmo, 3 años × 5 semillas, tirada simulada sobre sus ~85 piezas perfectas) | 8,5 en 3 años, la primera el día 1 | 0,9 (ninguna en el 38 %), la primera el día 20 de mediana (p10: 16) | práctica: 30 piezas perfectas de la receta antes; 5 % (antes 10 %) |
| Desbloqueo de mejoras | 300 de oro en mano: días 7-12 con full_player | días 3-5 en full_player; índices 2-3 en pacing | 300 de oro, o la deuda saldada desde el día 4 |
| Desbloqueo del rival (pacing, 10 semillas) | ventana de un día: falla 1/10 (3/10 con las obras raras) | ventana [2, 3]: 0/10 | el día en que le ganas en ventas depende del dado |
| Cargos y tratados | Patricio: nunca en 3 años | Ciudadano y año 3: el día 16 en 4/4 | Ciudadano ya da los cargos menores y la cuota |
| full_player: desbloqueos fuera | 1-2 | 0 en 4/4 | |
| Taberna recién comprada (innkeeper_start, 48 días × 3 semillas) | — | explotación 46-130/día el año 1; 200-404/día del 3 al 6 (fama 5) | las pérdidas de jugador son el arranque en sus últimos días; a largo plazo rinde 3-4 veces la forja |
| Concursos de fiestas → fama del taller | gancho a mano | `buildings[b].contests_won` con el evento `festival_contest` (+0,2 cada uno) | listo para cuando entre fiestas |

## Año 2 del jugador completo (manager, 2026-11-06)

| Cosa | Antes (dato del manager) | Ahora (rama equilibrio 1a05b830 + este arreglo, 4 semillas × 3 años) | Cómo |
|---|---|---|---|
| Neto/día año 2 | 1,4 (−31 a 18) | 30,5 de media (19,8-56,3; mediana 23,1) | La despensa de la taberna (cdca6e52) ya estaba: la taberna se compra en los días 14-21 y su primer año cae en el 2 o el 3 |
| Neto/día año 3 | — | 49,8 de media (4,9-148,4) | El primer año de la taberna (compra, mejoras, recados) aún pesa en 2 semillas; probé a frenar sus mejoras hasta que se pague sola y fue peor (−46/día en la semilla 1): las mejoras son lo que trae clientes. Se deja |
| Órdenes rechazadas | 154 en una semilla | 0 (1 en otra: festival_offer_gift sin pieza) | unlock_seen y read_notices se pueden dar de viaje (Travel.AWAY_ORDERS): darse por enterado no pide estar en la villa |

## La partida por defecto siguiendo el tutorial (manager, 2026-11-06/07)

Bot `tutorial_route` (sim/bots/bot_tutorial_route.gd): la ruta de verifica con órdenes reales y el pueblo vivo, sobre
`artisan_blacksmith`. Día 1: una espada, vender, recado de hierro y los martillos del carpintero. Día 2: la espada de
calidad del capitán. Después, una jornada al día: el aprendiz al abrirse Empleados (con su cola de 5 lingotes en
bucle), pagar si sobran 40, encargo de espadas, hierro ×8 y carbón por recado, 2 espadas y venderlas una a una.
Desglose por categorías: `tools/equilibrio/tutorial_probe.gd`. La semilla 11 calca la pasada de verifica: ventas 727 +
encargos 153 frente a compras 405, recados 79, mantenimiento 180 y sueldo 49; ruina el día 11.

**Por qué se arruina:** la espada normal (calidad 0) se vende a 46 y cuesta 32 de material más 6 de recado (el 73 es la
excelente). Además, la ruta solo compra hierro con 60 de oro: con el mantenimiento del amanecer cae por debajo y deja
de fabricar.

| Variante (30 semillas, Normal salvo que se diga) | Paga ≤ día 8 | Neto/día ruta | Novato (25-60; oro d10 ≤ 540) | Posada neta (10-60) · explotación (30-100) | Mercader capital (450-900) |
|---|---|---|---|---|---|
| Antes | **17 %** (5/30) | 12,5 | 52,8 · ok | 31,2 · 86,2 | 858 |
| A: recado 0 en todo + espada 70 + rampa | 93 % | 25,1 | **60,5** · 576 | **101,2 · 165,5** | **928** |
| C: recado 20 % + espada 75 + rampa (10 semillas) | 9/10 | 21,6 | **71,5** | 34,1 · 89,1 | **998** |
| **D: recado 0 solo en Recursos + espada 68 + rampa** | **93 %** (28/30); Fácil 100 %; Difícil 27 % | 25,4 | 58,8 · **596** (semilla 9) | 47,4 · **109,1** | 899,5 |
| D sin rampa (10 semillas) | 7/10 | 17,5 | | | |

Rampa: el mantenimiento de los amaneceres de los días 1, 2 y 3 ×0,25 / 0,5 / 0,75 (`data/accounts.json`
upkeep_ramp).

D es la mínima que cumple. Deja dos roces en bandas ajenas, propuestos al manager sin tocar:
- artisan_novice: gold_day10 hasta 600 (hoy 540; sale de 30 + 10 × 60 − 200 + 110 con la espada a 65).
- innkeeper: inn_operating_day hasta 120 (hoy 100; la taberna compra trigo y madera en Recursos).
