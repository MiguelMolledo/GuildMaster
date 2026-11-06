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
