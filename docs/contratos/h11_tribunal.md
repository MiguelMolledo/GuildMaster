# Contrato H11 · tribunal

Lo que comparte H11 (un subgrim, rama `h11-tribunal`, que sale de `main` 3ace882 con H1-H10 y el tema de UI pixel
art; el manager la junta con `main`). Quien cambie un nombre lo cambia aquí. Base: `docs/contratos/h1_mundo.md` …
`h10_cargos.md`. GDD: 4.12.5 (tribunal: acusación, testigos, preparación de 1 estación, vista oral, condenas), 4.8
(inspecciones de Secretos: «multa y juicio automático»), 4.12.1 (reputación de las condenas y de la acusación falsa),
4.12.2 (una condena grave baja el título), 4.12.3 (poderes de Juez y Alguacil), 4.2.3 (honestidad), 4.2.4 (SkillCheck),
4.17 (puntos de juicio y condenas), 4.19 (`justice`), 4.21 y 04c 4.21.9 (la IA acusa; 04c sin aprobar: aquí solo una
regla mínima), ap. A (fórmula del juicio). UI: `docs/ui/mecanicas/tribunal.md` de la rama `diseno-ui` (borrador; se
sigue en lo razonable).
Criterios del hito (10, fila H11): partida de 2 h del owner (ocupa un cargo menor y ve nacer un hijo); desde
`founder_old` hereda y sigue jugando; el bot `crook` acaba en juicio con la frecuencia esperada; en el sim una familia
IA acusa al jugador solo con motivo real o con pruebas fabricadas si su honestidad es baja.

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/core/world_state.gd` (v11), `sim/meta/save_file.gd` (paso 10→11), `sim/core/catalog.gd` (`justice`), `data/justice.json`, `data/score.json`, `data/ai_profiles/rival_smith.json`, `data/offices/*.json` (poderes de H11 listos), `tools/scenarios/make_trial_scenarios.gd`, `tools/validate_content.py` (`check_h11`), `tests/data/saves/v10_office_campaign.json` | `tests/test_core_h11_base.gd` |
| sim | `sim/politics/tribunal.gd` (hechos, juicios, testigos, vista, veredicto, condenas, destierro); enganches en `sim/core/sim.gd` (paso y órdenes del desterrado), `orders.gd`, `sim/econ/inspections.gd` (juicio automático), `sim/politics/elections.gd` (soborno descubierto = hecho), `sim/politics/offices.gd` (poderes de Juez y Alguacil; impuesto con `tax_mult`), `sim/family/schedules.gd` (el desterrado no tiene rutina), `sim/meta/new_game.gd` (actitudes), `sim/ai/rival_ai.gd` (tarea `accuse`), `sim/bots/bot_artisan_expert.gd` (ganchos `crook`), `tools/sim_runner.gd`, `data/targets.json` | `tests/test_justice_*.gd`, `tests/test_bots_crook.gd` |
| vista | `game/ui/trial_panel.*` (preparación y vista oral), `game/ui/trial_card.*` (carta «Te acusan» y veredicto), botón «Juicio» del HUD (tecla J), «Acusar…» en `npc_panel`, insignia de destierro (HUD, ficha, árbol), personaje desterrado oculto en el mapa, ayuda F1, `game/smoke/smoke_tribunal.gd` | `tests/test_game_trials.gd` |

## Estado (guardado v11)
Migración 10 → 11 (`SaveFile._step`):
- **Familias**: `attitudes: {honesty, generosity, diplomacy}` (GDD 4.2.3, −100..100). Migración: todo 0 (lo que ya
  suponía `Inspections.honesty_of`). Partida nueva: el rival toma `initial_attitudes` de su perfil.
- **Personajes**: `banished_until`: −1, o el último día (incluido) del destierro.
- **Raíz** `trials` (ya existía, vacía): `[trial]`. Un juicio: `{id: "tri_0001", charge, severity, accused, family
  (la del acusado), accuser ("" = la ciudad), accuser_family, source: inspection | accusation | arrest, fact,
  fabricated, proofs, witnesses: [{character, disposition: favor | neutral | against, done: {acción: día}, cross: "" |
  ok | fail}], extra: [cargos], status: preparation | hearing | done, start, prep_until, hearing_until (minutos),
  verdict: "" | guilty | innocent, judge_verdict: "", sentence: {}, scale: {defense, accusation}}`. Se guardan los
  abiertos y los últimos `trials.keep` cerrados.
- **Raíz** nueva `justice: {facts: [fact]}`. Un hecho: `{id: "fct_0001", kind, family, actor, charge, day, public,
  tried}` (lo que se puede llevar a juicio: una inspección, un soborno descubierto…).
- Ids nuevos (`Ids.next`): `tri`, `fct`.
- Regla: dentro de un juicio, de un testigo, de `sentence` y de un hecho se pueden añadir campos sin subir versión.
- Prueba: `tests/test_core_h11_base.gd` con `tests/data/saves/v10_office_campaign.json`.

## Datos
- **`data/justice.json`** → `Catalog.justice`:
  - `charges`: `{id: {severity, name_key}}`. Leve: `brawl` (pelea), `minor_fraud`; media: `tax_evasion`,
    `smuggling`; grave: `bribery`, `corruption`; máxima: `violent_crime`, `treason` (GDD 4.12.5, ejemplos de su tabla).
  - `sentences`: por gravedad `{kind: fine | confiscation | office_loss | banishment, fine [10, 50], reputation}`:
    leve multa 10-50 y −10; media confiscación (los productos del almacén del negocio implicado; las materias se
    quedan) y −30; grave pérdida de
    cargo + título −1 y −50; máxima destierro de `banishment_days` (8 = 1 año) [reputación de la máxima: −50,
    provisional].
  - `facts`: el cargo de cada tipo de hecho: `inspection` (según la mejora de Secretos: `tax_evasion` o, con
    contrabando, `smuggling`), `bribe_scandal` y `witness_bribe` → `bribery`, `witness_threat` → `brawl`,
    `judge_scandal` → `corruption`, `fabrication` → `corruption`.
  - `trial`: `witnesses [3, 5]`, `disposition_band 10` (relación con el acusado − relación con el acusador ≥ +10 a
    favor, ≤ −10 en contra), `prep_days` (= 1 estación), `hearing_hours 2`, `proofs {fact 1, inspection 1, fabricated
    1}`, fórmula (`rhetoric 2`, `witness 15`, `reputation 0.1`, `proof 20`), `town_rhetoric 5` (la ciudad acusa con
    esa Retórica si no hay Inspector), `keep 12`.
  - `witness_actions`: `convince` (Retórica vs Empatía; una vez al día por testigo), `bribe` (`gold_base 20` +
    `gold_per_negotiation 5` × Negociación del testigo; a favor seguro; Sigilo vs Empatía, fallo = denuncia: cargo
    extra `bribery`), `threaten` (Arte Marcial vs Arte Marcial; fallo = en contra y cargo extra `brawl`).
  - `cross`: interrogatorio en la vista (Retórica vs Empatía): éxito, el testigo no cuenta; fallo, cuenta doble.
  - `accuse`: `min_title citizen`, `fabricate {stat stealth, target 5, fail_reputation -50}`, `false_reputation -50`.
  - `judge`: `manipulate_honesty -20`, `scandal {target 5, reputation -20}`.
  - `honesty`: cambios de la actitud: `bribe -5`, `fabricate -10`, `manipulate -20` [−20 GDD; el resto provisional].
- **`data/score.json`**: `sentence.maximum −150` (como la grave; el GDD no la puntúa) [provisional].
- **`data/ai_profiles/rival_smith.json`**: `initial_attitudes {honesty 20, generosity 0, diplomacy 10}` (04c, columna
  «artesano tozudo») y `accuse_rule {accuses, real_facts, fabricate_max_honesty -30, protect_days 8, cooldown_days 8}`
  [provisional: regla mínima hasta que se apruebe 04c].
- **`data/offices/*.json`**: los poderes `arrest`, `investigate`, `preside_trial`, `pardon` pasan a `ready: true`;
  `seize_building` pasa a `H6` (embargar un edificio necesita la propiedad de H6).

## Paso del sim
Orden fijo (H10 + lo nuevo en negrita): … `Emotions` → `Offices.step` → **`Tribunal.step`** → `Reputation.step` → …
- **Hechos**: `Tribunal.add_fact(sim, kind, fam, actor, charge)`; todos los de H11 son **públicos** (multas de
  inspección y escándalos salen en avisos) [provisional: lo que ve un miembro con sus ojos llega con 04c].
- **Juicio automático** (GDD 4.8): una inspección que pilla (`inspection` con `caught`) añade un hecho y abre juicio
  contra el cabeza de la familia dueña; acusa la ciudad (el Inspector si lo hay).
- **Apertura** (`Tribunal.open`): 3-5 testigos (tirada de la ciudad, `Kin.randi_range`): empleados de la familia
  acusada, adultos de la familia acusadora y vecinos, por relación (la más fuerte primero) e id; disposición por la
  relación con acusado y acusador. Preparación hasta `start + prep_days`. Aviso urgente a la familia acusada.
- **Vista**: al acabar la preparación pasa a `hearing` (aviso) durante `hearing_hours`; el acusado interroga a los
  testigos en contra (`trial_cross`) y cierra cuando quiere (`trial_rest`); si no, al acabar la vista se dicta.
- **Veredicto**: `defensa = retórica_acusado × 2 + a_favor × 15 + reputación × 0,1`; `acusación = retórica_acusador ×
  2 + en_contra × 15 + pruebas × 20` (interrogado con éxito: no cuenta; con fallo: doble). Defensa > acusación →
  inocente (si la acusación era fabricada, el acusador pierde `false_reputation` y queda el hecho `fabrication`); si no,
  culpable y la condena de la gravedad mayor entre el cargo y los extra. Un Juez humano que no es parte puede dictar
  otro veredicto (`trial_verdict`): −20 de honestidad y SkillCheck de escándalo. Crónica `trial_won {family}` (gana el
  acusado inocente o el acusador de un culpable) y `sentence {family, severity}`; evento `trial_verdict`.
- **Condenas**: multa (`justice`, lo que tenga); confiscación (los productos del almacén del negocio implicado o, si no hay,
  del primer negocio de la familia); pérdida de cargo (`Offices.leave` motivo `sentence`) y título −1; destierro
  (`banished_until`, el personaje sale de su edificio y del mapa, pierde su cola de órdenes y no puede dar órdenes: motivo
  `banished`; vuelve a la puerta de su casa al acabar). La reputación de cada una.
- **Desterrados**: `Sim` rechaza sus órdenes; `Schedules`, `Routines` y la IA los saltan. Al amanecer se acaba el
  destierro vencido (evento `banishment_ended`).

## Órdenes
| Orden | Campos | Regla |
|---|---|---|
| `accuse` | actor, target, fact? \| charge + fabricate | **Gestión** (ficha del vecino). Actor vivo, adulto, de familia con título ≥ Ciudadano; target vivo, adulto, de otra familia, sin juicio abierto contra su familia. Con `fact`: público, sin juzgar y de la familia del target (el cargo es el del hecho). Con `fabricate`: un cargo de la lista; SkillCheck Sigilo vs 5: éxito, juicio con prueba fabricada; fallo, −50 de reputación y hecho `fabrication` contra el acusador. |
| `witness_action` | actor, trial, witness, kind | En persona (al alcance de H7). Actor de la familia acusada; juicio en preparación; testigo del juicio vivo; una vez al día por testigo y acción. `convince`, `bribe` (oro `justice`), `threaten`. |
| `trial_cross` | actor, trial, witness | **Gestión**. Actor de la familia acusada; juicio en vista; testigo en contra sin interrogar. |
| `trial_rest` | actor, trial | **Gestión**. Actor de la familia acusada; juicio en vista: se dicta ya. |
| `trial_verdict` | actor, trial, verdict | **Gestión**. Actor Juez (poder `preside_trial`) que no es de la familia acusada ni acusadora; juicio en vista. |
| `use_office_power` (H10) | `arrest {fact}`, `investigate {family}`, `pardon {character}` | Alguacil: abre juicio por un hecho público sin juzgar (acusa él); investiga una familia: si tiene mejoras de Secretos, hecho público. Juez: indulta a un desterrado. |

Motivos nuevos (`reason.*`): `banished`, `already_on_trial`, `unknown_trial`, `not_your_trial`, `trial_not_preparing`,
`trial_not_in_hearing`, `unknown_witness`, `unknown_fact`, `fact_not_usable`, `unknown_charge`, `needs_fact`,
`not_against`, `already_crossed`, `not_the_judge`, `party_to_trial`, `nothing_found`, `not_banished` (con los de antes).

## Eventos y avisos
- Eventos: `fact_added {fact, kind, family, charge}`, `trial_opened {trial, accused, family, accuser_family, charge,
  source}`, `witness_action {trial, actor, witness, kind, ok}`, `trial_hearing {trial}`, `trial_cross {trial, witness,
  ok}`, `trial_verdict {trial, verdict, defense, accusation, sentence}`, `banished {character, until}`,
  `banishment_ended {character}`, `accusation_failed {actor, target}`.
- Avisos: `notice.trial_accused` (urgente, familia acusada), `notice.trial_accuser` (la tuya acusa), `notice.trial_hearing`,
  `notice.trial_verdict_guilty` / `_innocent`, `notice.trial_other` (info: juicio entre otras familias),
  `notice.banished`, `notice.banishment_ended`, `notice.false_accusation`, `notice.witness_denounced`.

## Consultas para la UI
`Tribunal.open_trials(sim)`, `Tribunal.of_family(sim, fam)`, `Tribunal.view(sim, trial_id, viewer_fam) -> {..., scale:
{defense, defense_parts, accusation, accusation_parts, proofs_hidden}, witnesses: [{character, name, family, why,
disposition, actions: {kind: motivo}}], days_left, minutes_left}`, `Tribunal.accuse_options(sim, actor, target) ->
{facts: [...], charges: [...], reason}`, `Tribunal.is_banished(st, chr)`, `Tribunal.witness_status(...)`.

## Escenarios (`tools/scenarios/make_trial_scenarios.gd`, desde una partida nueva Normal, semilla 1)
- **`accused_player`**: día 9, 10:00. La Forja tiene la Doble contabilidad y una inspección acaba de pillarla: juicio
  automático en preparación (tarjeta y panel del juicio), 300 de oro, reputación 60.
- **`trial_hearing`**: el mismo juicio al final de la preparación: la vista empieza en unos minutos.
- **`rival_accused`**: día 9, 10:00. La familia es Ciudadana; el herrero rival tiene un hecho público sin juzgar (un
  soborno descubierto): Hugo puede acusarle desde su ficha.
- **`founder_old`** (H8, ya existía): fundador de 60 con heredero de 16.

## Bots y dianas
- `crook` (`BotArtisanExpert` con `crook = 1`, partida nueva Normal): juega como `artisan_expert`; en cuanto puede,
  compra la Doble contabilidad (Secretos 1) y, si le juzgan, interroga a los testigos en contra y cierra la defensa.
  Diana `crook` (40 días, 10 semillas): acaba en juicio en ≥ 60 % de las semillas y con 1-4 juicios por semilla de
  media (riesgo 5 %/día desde la compra).
- `rival_accuses` (bot `idle`, partida nueva Normal, 40 días): cada acusación de la IA tiene motivo (hecho real) o es
  fabricada con honestidad ≤ −30 (`ai_accusations_bad = 0`); test de reglas para las tres ramas.
- Medidas nuevas en `tools/sim_runner.gd`: `trials` (juicios contra la familia del jugador), `trial_day` (el primero),
  `guilty`, `ai_accusations`, `ai_accusations_bad`, `banished_days`.

## Vista
- **Carta «Te acusan»** (`game/ui/trial_card.*`, «Preparar la defensa» abre el panel); botón **Juicio** del HUD (tecla J)
  mientras haya un juicio de tu familia (acusada o acusadora).
- **Panel del juicio** (`game/ui/trial_panel.*`): acusado contra acusador, cargo y gravedad con la condena posible,
  días que quedan; la **balanza** con sus sumandos (pruebas del acusador «?» hasta la vista); los testigos con su
  disposición y Convencer / Sobornar / Amenazar (lejos: camina primero). En la vista, el mismo panel: los testigos en
  contra con «Interrogar», «Concluir la defensa», y el Juez (si eres tú) puede dictar. El juego **se pausa** al empezar
  la vista de un juicio tuyo (como pide el diseño de UI; el sim no cambia).
- **Tarjeta de veredicto** (la misma `trial_card`): sello INOCENTE / CULPABLE, balanza final y condena concreta.
- **Acusar…** en la ficha del vecino (hechos públicos contra su familia o fabricar con un cargo).
- **Desterrado**: insignia en el retrato y la ficha («desterrado hasta el día N»), no se dibuja en el mapa.
- Ayuda (F1): sección «Tribunal» (`help.trials*`).
- Capturas: `--smoke-script=tribunal` → `h11_acusacion`, `h11_preparacion`, `h11_vista`, `h11_vista_interrogada`,
  `h11_veredicto`, `h11_acusar`, `h11_destierro`.

## Decisiones provisionales
- **Vista oral interactiva = interrogar a cada testigo en contra** (opción (b) del diseño de UI): SkillCheck Retórica
  vs Empatía; éxito no cuenta, fallo cuenta doble. Y «Concluir la defensa».
- **Pruebas del acusador ocultas («?») hasta la vista** (opción (b) del diseño de UI).
- **Todos los hechos de H11 son públicos**; nada de `known` de 04c.
- **Juicio automático tras inspección**: además de la multa de H5; acusa la ciudad (Retórica 5 o la del Inspector).
- **Confiscación = la mercancía**: los productos a la venta del almacén (como el ladrón de H7); las materias primas se
  quedan para poder seguir trabajando (sin ellas y sin oro el negocio quedaba bloqueado, medido con el bot `crook`). El
  edificio no (la propiedad llega con H6).
- **Destierro**: el desterrado desaparece del mapa y no da órdenes; su negocio sigue con empleados y el resto de la
  familia; conserva su cargo. Si era el único adulto, la familia no puede actuar hasta que vuelva.
- **Cifras de honestidad** (soborno −5, fabricar −10) y la reputación de la condena máxima.
- **IA rival**: acusa al jugador solo con un hecho público sin juzgar contra su familia o, si su honestidad ≤ −30, con
  pruebas fabricadas (Sigilo); no en el primer año; una vez por `cooldown_days`. No se defiende (04c).
- **Testigos**: la relación de H7 decide la disposición; el acusado los trabaja en persona.
