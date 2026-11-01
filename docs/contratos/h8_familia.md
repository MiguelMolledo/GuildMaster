# Contrato H8 · familia y herencia

Lo que comparte H8 (un solo subgrim, rama `h8-familia`; el manager la junta con `main`). Quien cambie un nombre lo
cambia aquí. Base: `docs/contratos/h1_mundo.md` … `h5_mejoras.md`. GDD: 4.2.5 (ciclo de vida), 4.10 entero (cortejo,
pareja, hijos, herencia, grupo 1-2-3, directivas, árbol, rutina 4.10.8, identidad visual 4.10.9), 4.17 (puntuación,
metas, pantalla final), 4.21 (solo el módulo de familia de la IA rival), 06 (personaje y familia).
Criterios del hito (10, fila H8): bot `dynasty` hereda dentro de su diana (generación ~200 días; primer hijo ~1,5 años
tras la boda); Game Over sin heredero con la puntuación desglosada; la partida sigue con el heredero; con rutinas, 3
personajes trabajan un día entero sin órdenes manuales y una orden manual la interrumpe y luego se retoma; captura del
árbol donde la familia se reconoce por sus colores y los hijos llevan el pelo o la piel de un padre.

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/family/kin.gd` (consultas), `sim/core/world_state.gd` (v7), `sim/meta/save_file.gd` (paso 6→7), `sim/meta/new_game.gd` (edades, tonos, cabeza), `sim/core/clock.gd` (`age_years` por años de calendario), `sim/core/catalog.gd` (`family`, `score`, `goals`), `data/family.json`, `data/score.json`, `data/goals.json`, `data/view.json` (`palette`), `tools/maps/make_town_e.py` (edades y tonos de la población), `tools/scenarios/make_family_scenarios.gd`, `tools/validate_content.py` (`check_h8`, `check_h8_scenario`) | `tests/test_core_h8_base.gd` |
| sim | `sim/family/lifecycle.gd`, `births.gd`, `courtship.gd`, `schedules.gd`, `sim/ai/family_ai.gd`, `sim/meta/dynasty.gd`, `sim/bots/bot_dynasty.gd`, enganches en `sim/core/sim.gd`, `orders.gd`, `sim/econ/production.gd` (`may_work`) | `tests/test_family_*.gd`, `tests/test_meta_dynasty.gd`, `tests/test_bots_dynasty.gd` |
| vista | `game/identity.gd` (paleta), `game/ui/family_tree_panel.*`, `family_tree_node.*`, `portrait_frame.*`, `courtship_panel.*`, `routine_editor.*` (en `character_panel`), el grupo en `hud.*` (`GroupBar`), `ending_screen.*`, `game/visuals/characters/portrait.*`, `game/visuals/greybox/greybox_figure.gd` (pelo), `game/world/character_view.gd` y `world_view.gd` (tonos; rehacer la figura si cambia familia, control o empleo), `game/app.gd`, `game/smoke/smoke_familia.gd` | `tests/test_game_family.gd` |

## Estado (guardado v7)
Sin campos nuevos en la raíz (`relationships` y `chronicle` ya existían). Migración 6 → 7 (`SaveFile._step`):
- **Personaje** (todos): `birth_day: int` (días; negativo = antes de la partida; nacido al empezar un año de calendario
  para que las edades cambien juntas), `death_day: int` (−1 vivo), `class` (`"artisan"`), `profession`
  (`"blacksmith"` | `""`), `spouse: "" | chr` (pareja viva; al enviudar `""` y el muerto pasa a
  `life.former_spouses`), `parents: [chr]`, `children: [chr]`, `assigned: "" | bld` (edificio asignado; `""` = el
  taller de la familia), `directives: ["work"]`, `schedule: null | {fase: franja}`, `visual: {hair, skin}` (índices de
  la paleta), `life: {}` (memoria libre: `wedding_day` y `last_birth_day` en la madre, `school`, `former_spouses`).
  Migración: `MIGRATION_AGE` = 25 años al día de la partida, sin parentesco, tonos `n % 6` y `n % 4` del número del id.
- **Familia**: `head` (cabeza vivo), `heir` (designado; `""` = la regla por defecto), `founder`, `generation` (1 = el
  fundador), `regent` (la pareja que gestiona a un heredero menor), `class`, `goals_done: [ids]`. Migración: cabeza =
  primer miembro vivo.
- **Relación** `relationships["chr_a|chr_b"]`: `{relation, affinity, talk_day, near_day}`.
- **Crónica** (`Chronicle.add`): `birth {family, character, mother, father}`, `wedding {family, character, spouse,
  from_family}`, `death {family, character, age, cause}`, `inheritance {family, from, heir, generation, regent}`,
  `extinct {family, last}`, `goal_done {family, goal}`, `wealth_peak {family, value}`, `dynasty_closed`.
- **Final** `state.ending = {kind: "game_over" | "closed" | "ruin", family, minute, score}`.
- **Regla**: dentro de `life`, `routine` y `ai_state.family` se pueden añadir campos sin subir versión (JSON, con prueba).
- Prueba: `tests/test_core_h8_base.gd` con `tests/data/saves/v6_forge_upgrade_works.json`. Todos los escenarios
  regenerados en v7 sin otra diferencia (mismo `rng_state`, minuto y oro; comprobado).

## Datos (`data/family.json` → `Catalog.family`)
- `life`: `school_age 8`, `apprentice_age 12`, `majority_age 16`; `decline` (edades y atributos); `death {from_age 55,
  base 0.02, growth 1.25, constitution_step 0.05, certain_age 75}` (la fórmula de 4.2.5; pasa de 1 hacia los 73);
  `ai_school_stat`, `adult_carry_weight 30`.
- `courtship`: `talk [3, 5]`, `gift {min 5, max 15, gold_per_point 2}`, `work_near 1`, `charisma_step 0.1`,
  `same_title_mult 1.15`, `propose_min 80`, `range_tiles 3`, `blocking_emotions`, `opposite_sex true`.
- `children`: `first_child_days 2`, `daily_chance 0.10`, `between_days 8`, `max_per_couple 3`, `mother_max_age 45`,
  `stat_jitter 1`, `both_high_min 7`, `both_high_bonus 1`, `new_tone_chance 0.1`.
- `visual {hair_tones 6, skin_tones 4}` (los colores en `data/view.json` `palette`), `group {max 3}`, `routine
  {actions, default, ai_rest_phases, retry_minutes}`, `directives {known, default}`, `succession {voluntary_close
  false}`, `ai_family {court_phase, court_from_day}`, `names {male, female}`.
- `data/score.json`: puntos por tipo de hecho (`points`), por valor (`by_value`: títulos, cargos, condenas) y el
  patrimonio (`wealth {gold_per_point 100, step 100}`). `data/goals.json`: `five_generations`, `fortune`, `mayor`.

## Paso del sim (`Sim.step`, orden fijo)
1. Órdenes de fuera (cada una pasa antes por `Schedules.note_manual`); 2. `RivalAI.orders` → **`FamilyAI.orders`**;
3. `Clock.tick` → `OrderQueue` → `Movement` → `Buildings` → **`Lifecycle.step`** → `Upgrades` → `Staff` → `Routines`
   → **`Schedules.step`** → `WorkQueue` → `Production` → **`Courtship.step`** → `Market` → `Contracts` → `Upkeep` →
   `Inspections` → `Loans` → **`Births.step`** → **`Dynasty.step`** → `Objectives` → `Ledger` → `Notices`.
- **Azar de la familia**: `Kin.roll` / `Kin.randi_range`, un flujo propio sembrado con `world_seed` + clave (sistema,
  día, personas). Determinista y aparte de `state.rng`: un nacimiento no mueve las tiradas de la economía (las dianas
  de H3-H5 no cambian) y la misma partida da la misma familia.
- **`Lifecycle.step`** (al cambiar de año, en orden de id): cumpleaños (8: escuela, el jugador elige con
  `school_choice`, la IA `ai_school_stat`; 12: profesión de la familia y edificio asignado; 16: inventario propio, entra
  en el grupo si cabe con la rutina por defecto, fin de la regencia; declive) y después las tiradas de muerte.
- **Muerte** (`Lifecycle.die`): fuera del mapa, de su puesto y de su empleo; la pareja enviuda; crónica. Si era el
  cabeza → **herencia** (`succeed`): la familia conserva oro, edificios (con mejoras y empleados), préstamos y título;
  el heredero recibe inventario y equipo del muerto (lo que no cabe, al almacén de la residencia), es el cabeza,
  `generation + 1`, entra en el grupo (si está lleno, sale el adulto más joven); heredero menor → la pareja viva es
  regente (entra en el grupo) hasta los 16. **Sin heredero válido**: la familia humana termina (`ending.kind
  "game_over"` con la puntuación); una familia IA se extingue.
- **Heredero válido** (`Kin.can_inherit`): descendiente vivo del cabeza, de la familia, adulto; o menor si vive la
  pareja del cabeza. `Kin.heir`: el designado si vale, si no el mayor adulto, si no el menor mayor.
- **`Births.step`** (amanecer): cada pareja casada (madre viva con marido vivo) con `can_conceive` tira `daily_chance`.
  El hijo: de la familia del padre, en la residencia, `controlled_by "ai"`, inventario de 0 kg hasta los 16, atributos
  `(p + m) / 2 + [−1, +1]` (+1 si los dos ≥ 7), pelo y piel de un padre al azar (10 %: tono nuevo).
- **`Schedules.step`**: adultos de la familia humana sin empleo. Controlados con rutina → la franja de la fase;
  controlados sin rutina → nada; con IA (pareja, adultos fuera del grupo) → directiva, y descansan en
  `ai_rest_phases`. `work` = ir al edificio (el de la franja o el asignado) y `work_at` en el mejor puesto/receta
  posible (`pick_work`: precio de venta de la salida), con la repetición de `Production`; `rest` = a casa, sin trabajar;
  `free` = directiva (`work`). Una orden de fuera (no de gestión) marca `routine.manual` (y `manual_until` = ahora +
  `manual_grace_minutes`, 60): hasta que el personaje queda libre (sin ruta, sin cola, sin ciclo) y pasa ese margen, la
  rutina no actúa; luego retoma la franja de ahora. El margen deja encadenar órdenes a mano (salir y luego ir a un
  sitio) sin que la rutina se lo lleve entre medias; una acción que espera detrás de un `move_to` va encolada
  (`queued`) y también lo retiene.
- **`Courtship.step`**: con cada `work_done`, +`work_near` (una vez al día) a la pareja de solteros adultos de familias
  distintas que trabajaba a la vez en ese edificio.
- **`FamilyAI.orders`**: familias IA con perfil. Un cabeza soltero sin heredero, de noche y libre, visita una vez por
  noche al candidato con más afinidad (primero los que no tienen empleo): `exit_building` + `move_to` a su puerta,
  `court_talk` o `propose` (≥ 80) y vuelta a casa. Los demás adultos vuelven a la residencia.
- **`Dynasty.step`** (amanecer, familias que juegan): `wealth_peak` si el patrimonio supera el último en `step`; metas.
- **`Production.may_work`**: un miembro de la familia humana trabaja en los edificios de su familia como el jugador
  (también de noche) desde los 16 (`too_young` antes).

## Órdenes (por `Orders.apply`)
| Orden | Campos | Regla |
|---|---|---|
| `court_talk` | actor, target | Ambos vivos, adultos, solteros, de familias distintas, sexo opuesto, sin emoción que bloquee, a `range_tiles` (o dentro del mismo edificio); una vez por día y pareja. +`talk` × multiplicadores. |
| `court_gift` | actor, target, item, quality | Lo mismo; una unidad del inventario del actor pasa al del pretendido; +valor/`gold_per_point` en [5, 15]. |
| `propose` | actor, target | Lo mismo y afinidad ≥ 80 → boda (`Courtship.marry`). |
| `designate_heir` | actor, heir | Gestión. `heir` puede heredar del cabeza (`Kin.can_inherit`) o `""` (regla por defecto). |
| `school_choice` | actor, child, stat | Gestión. Hijo de la familia con la escuela pendiente: +1 al atributo. |
| `assign_building` | actor, character, building | Gestión. Edificio de la familia o `""`. |
| `set_schedule` | actor, character, schedule | Gestión. Miembro controlado de la familia; `null` o franjas válidas (`check_schedule`). |
| `set_directives` | actor, character, directives | Gestión. Ids de `directives.known`. |
| `close_dynasty` | actor | Gestión. **Desactivada** (`succession.voluntary_close false`, D19): `disabled`. |

Motivos nuevos (`reason.*`): `unknown_target`, `too_young`, `not_single`, `same_family`, `same_sex`, `offended`,
`already_talked`, `low_affinity`, `no_head`, `not_an_heir`, `no_choice`, `unknown_stat`, `disabled`,
`not_your_family`, `bad_schedule`, `bad_directives` (y los ya existentes `too_far`, `not_family`, `not_enough`...).

## Eventos y avisos
- Eventos: `child_born`, `wedding`, `affinity_changed`, `birthday`, `character_died`, `inheritance`,
  `regency_ended`, `group_changed`, `family_extinct`, `game_over {kind, family}`, `heir_designated`, `school_chosen`,
  `building_assigned`, `schedule_changed`, `directives_changed`, `routine_paused`, `routine_resumed`, `routine_slot`,
  `goal_done`; `employee_left` con `reason "married"` / `"died"`.
- Avisos (solo la familia humana): `notice.child_born`, `notice.wedding`, `notice.death` (urgente),
  `notice.inheritance` (urgente), `notice.school_choice`, `notice.apprentice`, `notice.came_of_age`,
  `notice.goal_done`.

## Consultas para la UI
`Kin.group`, `Kin.heir`, `Kin.age`, `Kin.can_inherit`, `Kin.descendants`, `Kin.residence`, `Kin.assigned_building`;
`Courtship.candidates(sim, actor) -> [{character, name, female, family, age, affinity, status}]`, `status`, `spot`,
`affinity`; `Schedules.view(sim, chr) -> {schedule, phase, now, manual, directives}`, `check_schedule`;
`Lifecycle.death_chance`; `Dynasty.score(sim, fam) -> {total, by_kind, facts, peak}`, `summary`, `goals_view`,
`wealth`.

## Escenarios (`tools/scenarios/make_family_scenarios.gd`, desde una partida nueva Normal, semilla 1)
- **`founder_old`**: día 0, 06:00. Hugo 60 años, casado con Agnès (56); Pere (16, heredero, en el grupo con rutina) y
  Clara (12); 600 de oro; la deuda pagada.
- **`founder_no_heir`**: día 7, 23:50. Hugo 74, viudo, su único hijo murió: sin heredero. A medianoche cumple 75 y
  muere → Game Over con la puntuación (boda, nacimiento, patrimonio).
- **`courtship`**: día 1, 19:30. Hugo 20 ante la casa de los Soler con 76 de afinidad con Agnès.
- **`dynasty_start`**: día 0, amanecer. Hugo 40, soltero, 400 de oro, sin deuda (el bot `dynasty`).
- **`family_routines`**: día 2, 04:30. Hugo (40), Agnès y sus hijos Pere (18) y Clara (17), los tres del grupo con
  rutina (Día = trabajar en la forja, Amanecer/Atardecer libres, Noche descansar); la forja con Capacidad 1-3 (cuatro
  puestos: los tres y la pareja, que trabaja por su directiva) y hierro, carbón y lingotes para un día.

## Bot `dynasty` y su diana
`sim/bots/bot_dynasty.gd` desde `dynasty_start`: el pretendiente (el cabeza soltero sin heredero; después el heredero
adulto soltero) camina hasta la puerta del candidato con más afinidad (primero sin empleo) con la acción encolada
detrás, conversa una vez al día y propone al llegar a 80. Medidas (`measures()`, las suma `sim_runner`): `wedding_day`,
`first_child_days`, `inherited`, `inherit_day`, `generation_days` (nacimiento del segundo cabeza → su primer hijo),
`game_over`. Ritual a mano (largo, ~10-30 min por semilla): `godot --headless --path . -s tools/sim_runner.gd --
--scenario=dynasty_start --bots=dynasty --days=320 --seeds=3` (dianas en `data/targets.json` `dynasty`).

## Decisiones provisionales
- **Edad por años de calendario** (`Clock.age_years`): todos cumplen a la vez al cambiar de año (4.2.5 lo pide).
- **Azar propio de la familia** (`Kin.roll`), sembrado con la semilla: no mueve las dianas de H3-H5.
- **El fundador de una partida nueva empieza sin rutina** (`schedule null`): la rutina por defecto de 4.10.8 con
  «el resto, Libre» le haría trabajar todo el día desde el minuto 1 y cambiaría el balance de H3-H5; se activa en la
  ficha. Quien entra en el grupo a los 16 recibe la rutina por defecto.
- **La rutina vale también para el personaje seleccionado**: el sim no sabe quién está seleccionado; una orden manual
  manda hasta que queda libre.
- **Familiares con IA descansan de noche** (`ai_rest_phases`) hasta que lleguen las necesidades (POST-MVP).
- **Cortejo entre sexos opuestos** (los hijos necesitan padre y madre); `opposite_sex` en datos.
- **Los vecinos son solteros** (cada casa: dos adultos que no son pareja): son los candidatos de cortejo. No se casan
  entre ellos ni tienen hijos (su vida completa es de H7).
- **Alcance de cortejo**: a 3 casillas de la persona o de la puerta del edificio donde está (los vecinos sin empleo
  están en casa); dentro del mismo edificio también vale.
- **Regalo**: valor = precio de venta en el mercado; 1 punto cada 2 de oro, entre 5 y 15.
- **Al casarse** la pareja deja su empleo (si lo tenía) y su familia, y vive en la residencia de su nueva familia.
- **Madre hasta 45 años** (`mother_max_age`, el GDD no lo da).
- **Declive**: −1 Constitución a los 45, 50, 55, 58, 61, 64, 67, 70; −1 Destreza a los 50, 61, 67; +1 Retórica a los 55.
- **Heredero menor sin pareja viva** no vale (sin regente no hay quién gestione): se busca un adulto o es Game Over.
- **Herencia**: el oro, los edificios, los empleados y las deudas ya son de la familia; cambia el cabeza. El
  inventario personal pasa al heredero. Los cargos (H10) no existen todavía.
- **Grupo lleno al heredar**: el heredero entra y sale el adulto más joven del grupo.
- **Módulo de familia de la IA** (4.21 sin cerrar): lo mínimo, solo cortejo nocturno del cabeza sin heredero; los
  demás miembros de una familia IA no trabajan (solo el actor de `RivalAI`).
- **Patrimonio** = oro + `build_cost` de sus edificios + coste en oro de sus mejoras terminadas.
- **Actitudes morales** (4.2.3) no entran: no hay `attitudes` todavía.
- **Teclas**: el grupo usa 1-2-3 (4.10.5); las velocidades pasan a Mayús+1/2/3 (choque con D4; `project.godot` no se
  toca en esta rama: lo hace el HUD por código).
- **Cierre voluntario** (D19): orden y botón detrás de `succession.voluntary_close` (false).

## Vista
- **Retrato** `game/visuals/characters/portrait.tscn` (`Portrait`, Polygon2D editables: fondo, cuerpo en el color
  primario, cuello en el secundario, cabeza en la piel, pelo; melena si es mujer; cruz si murió). El marco de la UI
  (`game/ui/portrait_frame.tscn`): borde exterior del color de la familia, anillo dorado (controlable) o gris, fondo
  claro si es el activo, corona del heredero y la tecla del grupo. Colores: `Identity.of(state, chr)` con
  `data/view.json` `palette` (6 pelos, 4 pieles). El caminante greybox pinta el pelo y la piel de la persona.
- **Grupo** (HUD, `GroupBar` bajo la ficha del seleccionado): los retratos del grupo; 1-2-3 o clic eligen, doble clic
  centra; Mayús+1/2/3 las velocidades.
- **Árbol** (F, o «Familia» en la ficha): disposición `FamilyTreePanel.layout` (fundador arriba, parejas a la derecha
  con línea y anillo, hijos bajo la pareja; las líneas son ColorRect), zoom +/−, ficha lateral (atributos, Designar
  heredero, Cambiar a este personaje, Cortejar, Trabaja en, Escuela +1) y la dinastía (generación, puntos, metas). El
  aviso de escuela abre el árbol con el niño elegido.
- **Cortejo** (desde la ficha o el árbol): candidatos con su afinidad; Hablar / Regalar / Proponer; lejos, camina
  primero (`move_to` + la acción encolada).
- **Rutina** (en la ficha, I): una fila por franja (acción, receta o «Automática», modo), Activar/Quitar, y la línea
  «Ahora (fase): acción · manda una orden a mano». Una sola orden `set_schedule` con la rutina entera.
- **Pantalla final**: generaciones, cabezas con sus días, patrimonio máximo, metas y la puntuación por tipo de hecho.
- Capturas: `grimoire heavy --timeout 4m -- godot --audio-driver Dummy --always-on-top --path . --
  --smoke-script=familia` → `reports/shots/h8_arbol.png`, `h8_rutina.png`, `h8_game_over.png`.

## Preguntas abiertas (para el manager / owner)
1. D19: ¿se aprueba el cierre voluntario de la dinastía?
2. ¿Las velocidades a Mayús+1/2/3 (o a otra tecla) para dejar 1-2-3 al grupo?
3. ¿Rutina por defecto también para el fundador desde el inicio, aunque mueva el balance de H3-H5?
4. 4.21: cuando se cierre el diseño de la IA rival, el módulo de familia se rehace con utilidad.
