# Contrato H14 · IA familiar

Lo que comparte H14 (un subgrim, rama `h14-ia-familiar`, que sale de `main` 1512388 con H1-H11, el estudio de escala y
las decisiones de UI; el manager la junta con `main`). Quien cambie un nombre lo cambia aquí. Base:
`docs/contratos/h4_empleados.md`, `h7_ciudad.md`, `h8_familia.md` (rutina y directivas) y los demás.
GDD: 4.10.6 (directivas IA de familiares: el jugador las ordena por prioridad y la IA las equilibra con las
necesidades; **las mismas órdenes que el jugador**), 4.10.8 (rutina: la franja «Libre» sigue la directiva), 4.2.6
(necesidades hambre, descanso, social y diversión 0-100; si se descuidan baja la moral y con ella la productividad),
4.18 (registro de avisos). UI: `docs/ui/mecanicas/familia.md`, `forja_interior.md` (rutina) y `docs/ui/01_hud.md`
(avisos) de la rama `diseno-ui` (se siguen en lo razonable).
Criterio del hito (10, fila H14): un familiar con «Comerciar» aprovisiona la forja solo.

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/core/world_state.gd` (v12), `sim/meta/save_file.gd` (paso 11→12), `data/family.json` (`directives`, `needs`, `morale`, `trade`, `notices`), `sim/meta/new_game.gd`, `tools/scenarios/make_kin_ai_scenarios.gd`, `tools/validate_content.py` (`check_h14`), `tests/data/saves/v11_accused_player.json` | `tests/test_core_h14_base.gd` |
| sim | `sim/family/needs.gd` (necesidades, moral, productividad, avisos), `sim/family/directives.gd` (comerciar, sociabilizar, divertirse y el reparto con las necesidades); enganches en `sim/family/schedules.gd` (franja libre), `sim/core/sim.gd`, `sim/econ/production.gd` (la moral en la duración del ciclo de un familiar), `tools/sim_runner.gd`, `data/targets.json` | `tests/test_family_needs.gd`, `tests/test_family_directives.gd` |
| vista | `game/ui/kin_ai_panel.*` (directivas por prioridad, qué hace y por qué, necesidades y moral), botón «IA» de la ficha (`character_panel`), ayuda F1, `game/smoke/smoke_ia_familiar.gd` | `tests/test_game_kin_ai.gd` |

## Estado (guardado v12)
Migración 11 → 12 (`SaveFile._step`), en **personajes**:
- `needs: {hunger, rest, social, fun}`: enteros 0-100 (GDD 4.2.6). Migración y personajes nuevos: `needs.start`.
- `ai: {}`: memoria libre de las directivas (`doing`, `why`, `task`, `buy`, `notified: {aviso: día}`…).
- La moral **no se guarda**: se deriva de las necesidades (`Needs.morale`).
- Regla: dentro de `ai` se pueden añadir campos sin subir versión.
- Prueba: `tests/test_core_h14_base.gd` con `tests/data/saves/v11_accused_player.json`.

## Datos (`data/family.json`)
- `directives.known`: `work`, `trade`, `socialize`, `leisure`, `learn`; `directives.ready`: `{id: true | hito}`
  (`learn` → `EA`: el GDD no da cómo sube un atributo); `default ["work"]`. El orden de la lista es la prioridad.
- `needs`: `start 80`, `per_hour` por necesidad y situación (enteros, al cambiar de hora): hambre −2 y +12 en casa sin
  trabajar; descanso −2 despierto, −3 trabajando de noche, +8 en casa sin trabajar; social −1 y +8 en actividad social o
  conversando (+10 por `npc_talk`, `greeted` o una compra/venta en el mercado); diversión −1 y +12 en ocio. `low 30`
  (la IA atiende primero la necesidad más baja que esté por debajo) y `critical 15` (aviso «agotado»).
- `morale`: media de las cuatro; `productivity {full_at 40, min_mult 0.8}`: con moral ≥ 40 trabaja a ritmo normal;
  por debajo, la duración del ciclo de un familiar se divide por un multiplicador que baja en línea hasta 0,8 en moral 0.
  `low 30` (aviso «moral baja»).
- `trade`: `min_stock 6` (unidades de cada materia prima de las recetas del edificio que se quieren en el almacén),
  `buy_up_to 10`, `gold_reserve 20`, `keep_products 4` (por encima, vende), `max_carry_units 10`.
- `notices`: un aviso por personaje y tipo cada `cooldown_days 1`.
Todas las cifras **[provisional, balance]**: el GDD (4.2.6) no da ninguna.

## Paso del sim
Orden fijo: … `Routines` → `TownLife` → `Counter` → `Schedules` (**franja libre → `Directives.step_one`**) → … →
`Emotions` → **`Needs.step`** → `Offices` → …
- **`Needs.step`**: con `hour_changed`, a los adultos de las familias humanas que lleva la IA o una rutina: cada necesidad cambia por su situación
  (en casa sin trabajar, trabajando, en ocio, en actividad social…) y los eventos de la hora (`npc_talk`, `greeted`,
  compras y ventas). Avisos (una vez al día por tipo): `notice.kin_exhausted` (una necesidad ≤ critical),
  `notice.kin_low_morale` (moral ≤ low), `notice.forge_short` (el edificio asignado sin materias para su mejor receta y
  nadie de la familia comerciando).
- **Productividad**: `Production._start_cycle` divide la duración de un familiar (no empleado) por `Needs.productivity`.
- **Directivas** (`Directives.step_one`, en una franja «Libre» de la rutina o para un familiar con IA): primero la
  necesidad más baja si está por debajo de `low` (hambre o descanso → a casa y quieto; social → sociabilizar; diversión →
  ocio); si no, la primera directiva de la lista (en orden) que tenga algo que hacer:
  - `work`: lo de H8 (`Schedules._work`), modo Normal, sin toque de maestro.
  - `trade`: con el mercado abierto, si el almacén del edificio asignado tiene menos de `min_stock` de una materia prima
    de sus recetas, va al puesto que la vende, la compra (`buy`, hasta `buy_up_to`, guardando `gold_reserve`), vuelve y
    la deja (`transfer`); si tiene más de `keep_products` de un producto, lo coge y lo vende en su puesto.
  - `socialize`: busca al vecino adulto más cercano en la calle y conversa (`npc_talk`, H7).
  - `leisure`: va a un banco libre de la plaza (puntos sociales de H7) y se queda una hora.
  - `learn`: apagada (`EA`).
  Lo que hace y por qué queda en `ai.doing` / `ai.why` (`Directives.view`).

## Órdenes
Las de siempre: `move_to`, `enter_building`, `exit_building`, `buy`, `sell`, `transfer`, `work_at`, `stop_work`,
`npc_talk`. `set_directives` (H8) acepta ahora las directivas listas (`directives.ready` = true); una apagada:
`directive_not_ready`.

## Eventos y avisos
- Eventos: `directive_task {character, directive, task}`, `needs_changed {character}` (al cambiar de hora).
- Avisos: `notice.kin_exhausted`, `notice.kin_low_morale`, `notice.forge_short`, `notice.kin_supplied` (info: un familiar
  ha traído materias).

## Consultas para la UI
`Needs.view(sim, chr) -> {needs, morale, productivity}`, `Directives.view(sim, chr) -> {directives, ready, doing, why}`.

## Escenarios (`tools/scenarios/make_kin_ai_scenarios.gd`, partida nueva Normal, semilla 1)
- **`kin_trader`**: día 9, 06:00. Hugo casado con Agnès (en el grupo, rutina «Libre» todo el día salvo la noche) con
  directiva Comerciar; la forja sin hierro ni carbón; 200 de oro.
- **`kin_tired`**: el mismo con Agnès cansada y con hambre (necesidades bajas, moral baja): avisos y la IA la manda a casa.

## Bots y dianas
- `kin_trader` (bot `idle` desde el escenario `kin_trader`, 2 días): la forja tiene hierro y carbón al final del primer
  día de mercado sin órdenes del jugador (`forge_supplied 1`) en N de N semillas.
- Medidas nuevas en `tools/sim_runner.gd`: `forge_supplied`, `kin_bought`, `low_morale_hours`.

## Vista
- **Panel IA del familiar** (`game/ui/kin_ai_panel.*`, botón «IA» de la ficha): las directivas en orden con ▲ ▼ y
  activar/quitar (las apagadas, en gris con su hito), una sola orden `set_directives`; «Ahora: …» con el porqué; barras
  de hambre, descanso, social, diversión y moral (con su efecto en el trabajo).
- Avisos por el registro (H3) y sus ventanas emergentes.
- Ayuda (F1): sección «IA de la familia» (`help.kin_ai*`).
- Capturas: `--smoke-script=ia_familiar` → `h14_directivas`, `h14_comerciar`, `h14_necesidades`.

## Decisiones provisionales
- **Directivas que entran**: Trabajar, Comerciar, Sociabilizar, Divertirse; Aprender queda apagada (EA).
- **Divertirse = un rato en un banco de la plaza** (no hay taberna en el MVP); descansar y comer = estar en casa sin
  trabajar (no hay comida ni camas en el MVP).
- **Necesidades solo de los adultos de la familia humana que lleva la IA o una rutina** (la pareja, los adultos fuera
  del grupo y los del grupo con rutina). Quien se juega solo a mano (sin rutina, como el fundador de una partida nueva)
  no tiene necesidades que se muevan: no hay órdenes de comer ni dormir y el bot novato, que trabaja 22 h al día, perdía
  10 de oro neto al día en el año 1 (de 54,7 a 44,2) por la moral; igual que H8 dejó al fundador sin rutina para no
  mover H3-H5. Enfermedad por necesidades: no (POST-MVP, como dice 4.2.6).
- **Todas las cifras** de necesidades, moral y comercio.
- **Comerciar compra las materias de las recetas del edificio asignado** y vende el excedente de productos; no compra
  herramientas ni mejoras.
