# full_player: antes y después

Antes: `reports/full_player_ref/full_player_antes_eq.json` (3y, 4 semillas, commit b0616e72). Después: `reports/full_player_ref/full_player_despues_eq.json` (3y, 4 semillas, commit 1f39d995).

| Medida | Banda | Antes | Después | Antes cumple | Después cumple |
|---|---|---|---|---|---|
| `refused_orders` | run [0, 0] | 0.25 [0-1] | 0.00 [0-0] | no | sí |
| `ledger_mismatch` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `engine_errors` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `hangs` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `gold_negative` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `off_map` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `debt_paid` | run [1, 1] | 1.00 [1-1] | 1.00 [1-1] | sí | sí |
| `debt_paid_day` | run [1, 8] | 3.00 [3-3] | 2.50 [2-3] | sí | sí |
| `title_citizen_day` | run [1, 20] | 20.50 [20-21] | 12.75 [11-14] | no | sí |
| `unlocks_off` | run [0, 0] | 2.00 [2-2] | 0.00 [0-0] | no | sí |
| `staff_hungry_share_max` | run [0, 0.5] | 0.82 [0.736-0.861] | 0.00 [0-0.007] | no | sí |
| `child_hungry_share_max` | run [0, 0.5] | 0.22 [0-0.88] | 0.00 [0-0] | no | sí |
| `step_ms_mean` | run [0, 5] | 1.35 [1.29-1.415] | 1.40 [1.2-1.686] | sí | sí |
| `mechanics_used` | run [14, None] | 21.75 [20-23] | 25.25 [23-27] | sí | sí |
| `inherited` | run [1, 1] | 0.00 [0-0] | 0.00 [0-0] | no se juzga | no se juzga |
| `game_over` | run [0, 0] | 0.00 [0-0] | 0.00 [0-0] | no se juzga | no se juzga |
| `ai_refused_per_family_year` | run [0, 1] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `watch_arrived_share` | run [0.9, 1] | 1.00 [1-1] | 1.00 [1-1] | sí | sí |
| `npc_stalls` | run [0, 2] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `npc_hungry_share_max` | run [0, 0.5] | 0.00 [0-0] | 0.00 [0-0] | sí | sí |
| `townsfolk_end` | run [10, None] | 14.25 [14-15] | 15.25 [15-16] | sí | sí |
| `visitors_per_day` | run [2, 6] | 5.67 [5.33-5.83] | 5.63 [5.21-5.92] | sí | sí |
| `ai_contracts_accepted` | run [10, None] | 41.75 [31-58] | 36.50 [17-53] | sí | sí |
| `net_year_1` | mean [25, None] | 46.69 [26.75-59.25] | 57.97 [51.63-66.88] | sí | sí |
| `title_citizen` | share [0.66, None] | 1.00 [1-1] | 1.00 [1-1] | sí (1.00) | sí (1.00) |
| `wed` | share [0.66, None] | 1.00 [1-1] | 1.00 [1-1] | sí (1.00) | sí (1.00) |
| `ai_titled_families` | propuesta [1, None] | 0.25 [0-1] | 0.25 [0-1] | no | no |
| `ai_office_runs` | propuesta [1, None] | 0.25 [0-1] | 0.00 [0-0] | no | no |
| `ai_broke_days_max` | propuesta [0, 4] | 2.00 [0-7] | 10.25 [5-13] | no | no |
| `children` | propuesta [1, None] | 0.50 [0-1] | 0.75 [0-1] | no | no |
| `net_year_2` |  | 19.41 [11.63-35.5] | 1.35 [-31.12-17.75] | — | — |
| `net_year_3` |  | -19.43 [-56.12-41.88] | 51.28 [17.25-88.13] | — | — |
| `gold_end` |  | 135.75 [2-406] | 668.00 [433-886] | — | — |
| `gold_min` |  | 0.00 [0-0] | 0.00 [0-0] | — | — |
| `wedding_day` |  | 15.50 [14-17] | 12.75 [12-14] | — | — |
| `masterworks` |  | 4.75 [2-7] | 0.25 [0-1] | — | — |
| `hired` |  | 5.00 [4-6] | 6.00 [5-7] | — | — |
| `upgrades_done` |  | 4.75 [4-7] | 9.50 [8-10] | — | — |
| `contracts_done` |  | 12.75 [10-16] | 17.75 [12-21] | — | — |
| `contracts_failed` |  | 2.25 [0-3] | 2.50 [2-4] | — | — |
| `stalls` |  | 6.75 [5-8] | 3.50 [3-4] | — | — |
| `y1_gap_median_s` |  | 4.60 [4.4-5] | 4.55 [4.4-4.6] | — | — |
| `y1_gap_max_s` |  | 45.42 [29.7-66] | 22.20 [15-29] | — | — |

## Bandas propuestas (no aplicadas: esperan visto bueno)

Medido con `full_player`, 3 años × 4 semillas (1-4), Normal, con todo encendido. Antes: `b0616e72`. Después: `1f39d995`
(equilibrio Eq1-15). Por semilla, después: Ciudadano los días 14, 14, 12 y 11; boda los días 14, 13, 12 y 12; hijos
0, 1, 1 y 1; neto del año 1 51,6-66,9 de oro/día; el peor hueco del año 1 entre 15 y 29 s; un viaje, la cuota firmada
y el cargo el día 17 en las cuatro.

| Medida | Hoy | Propuesta | Medido después | Por qué |
|---|---|---|---|---|
| `debt_paid_day` (por semilla) | [1, 8] | [1, 6] | 2-3 | La deuda cae en el año 1 con margen; 6 deja dos días de holgura |
| `title_citizen_day` (por semilla) | [1, 20] | [1, 16] | 11-14 | La decisión 3: Ciudadano en el año 2 (días 9-16) en todas las semillas |
| `title_citizen_day` (media) | [9, 16] | se queda | 12,75 | Ya es la del año 2 |
| `wedding_day` (por semilla, nueva) | — | [1, 20] | 12-14 | La boda en el año 2; antes iba solo la proporción |
| `had_child` (proporción, vuelve) | `children` en propuesta | ≥ 0,5 | 3 de 4 | Con la boda en los días 12-14 hay días para el 10 % diario |
| `net_year_1` (media) | ≥ 25 | ≥ 40 | 58,0 (51,6-66,9) | El año 1 rinde más tras el equilibrio |
| `net_year_3` (media, nueva) | — | ≥ 25 | 51,3 (17,3-88,1) | El negocio vuelve a crecer en el año 3 |
| `mechanics_used` (por semilla) | ≥ 14 | ≥ 20 | 23-27 | Con posada, juegos, forja viva, viajes y cuota se tocan más |
| `y1_gap_median_s` (nueva) | — | [0, 30] | 4,4-4,6 | La diana de 03b §3b.6 (mediana < 30 s) |
| `y1_gap_max_s` (nueva) | — | [0, 60] | 15-29 | La diana de 03b §3b.6 (máximo < 60 s), que antes fallaba (hasta 137 s) |
| `masterworks` (por semilla, nueva) | — | [0, 3] | 0-1 | Antes del equilibrio salían 2-7; que no vuelvan a ser tan fáciles |
| `staff_hungry_share_max` (por semilla) | [0, 0,5] | [0, 0,1] | 0-0,007 | Arreglado: estrecharla avisa si vuelve |
| `child_hungry_share_max` (por semilla) | [0, 0,5] | [0, 0,1] | 0 | Lo mismo |
| `trips` (por semilla, nueva) | — | ≥ 1 | 1 en las 4 | Viajar ya compensa en 3 años (decisión 7) |
| `treaties` (por semilla, nueva) | — | ≥ 1 | 1 en las 4 | La cuota se firma en las 4 |
| `stalls` (por semilla, nueva) | — | [0, 8] | 3-4 | Las obras ya no paran tanto (decisión 9) |

Se quedan como propuestas (`_proposed`), porque siguen sin cumplirse: `ai_titled_families` ≥ 1 (1 de 4), `ai_office_runs` ≥ 1 (0 de 4) y
`ai_broke_days_max` ≤ 4 (5-13). Es la agenda de 04c (H6).

## Lo que ha encontrado la medida (para el equilibrio)

1. **El año 2 sale casi a cero:** neto de 1,4 de oro/día de media (de −31 a 18), cuando antes era 19. El año 2 compra
   Ciudadano, la campaña, mejoras (9,5 de media frente a 4,75) y la taberna, y la taberna pierde dinero en las cuatro
   semillas: `bot_inn_net_day` de −26 a −89. Con la clientela única (Eq14) y llevada por la cónyuge con `BotInnkeeper`,
   la taberna del jugador completo sigue sin compensar en 3 años.
2. **La IA rival sigue sin oro más días en 3 años:** `ai_broke_days_max` pasa de 0-7 a 5-13. El año 1 ya cumple la
   diana nueva de fiestas (paso `fest_ai`), pero en los años 2-3 vuelve a quedarse sin oro.
3. **Lo arreglado se ve en la medida:** el hambre de empleados y niños (0), las obras maestras (0-1), Ciudadano en el
   año 2, los desbloqueos a tiempo (0 fuera de su ventana), el ritmo (el peor hueco del año 1 baja de 66 a 29 s), y el
   viaje, la cuota y el cargo en las cuatro semillas.
