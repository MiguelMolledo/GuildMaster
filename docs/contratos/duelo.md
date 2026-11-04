# Contrato · duelo en la partida

Lo que comparte el duelo de honor (rama `duelo2`, sale de `main` 15e52fd; la junta el manager). Quien cambie un nombre lo
cambia aquí. Diseño: [docs/gdd/04e_combate.md](../gdd/04e_combate.md) (aprobado el 2026-11-04, O-C1..O-C12). Pantalla:
[docs/ui/mecanicas/combate.md](../ui/mecanicas/combate.md). Guardado **v15** (los viajes, v16, y 4.22, v17, van detrás).

## Zonas (ficheros)

| Zona | Ficheros | Pruebas |
|---|---|---|
| reglas del lance | `sim/combat/combat_rules.gd`, `sim/combat/duel.gd` (`Duel.wrap` sobre los datos del estado), `data/combat.json` (`actions`…`items`), `tools/duel_bench.gd` | `tests/test_combat_duel.gd` |
| duelo en el sim | `sim/combat/duels.gd` (`Duels`); enganches en `sim/core/orders.gd`, `sim/core/sim.gd` (paso y retención de órdenes), `sim/core/world_state.gd` (`duels`), `sim/meta/save_file.gd` (`_to_v15`), `data/combat.json` (`challenge`, `ai_answer`, `consequences`), `tools/validate_content.py` (`check_combat`) | `tests/test_combat_duels_game.gd` |
| bot y escenario | `sim/bots/bot_duelist.gd`, `tools/sim_runner.gd` (medidas `duels_*`), `data/targets.json` (`duelist`), `tools/scenarios/make_duel_scenarios.gd` → `data/scenarios/duel_ready.json`, `tools/qa/run_all.py` (paso `duel`) | — |
| vista | `game/ui/duel_director.gd` (cartas y apertura de la pantalla), `game/ui/duel_screen.*` (modo partida y prototipo), `game/ui/duel_arena.gd`, `game/ui/duel_pips.gd`, «Retar a duelo…» en `game/ui/npc_panel.gd`, `Game.step_now` (`game/autoload/game.gd`), `VisualPaths.duel_vfx` / `duel_icon` / `duel_illustration`, `game/smoke/smoke_duelo_partida.gd`, `game/smoke/smoke_duel.gd` | `tests/test_ui_duel.gd` |
| tutorial | `data/tutorial/duel.json`, `data/tutorial.json` (capítulo `duel`, paneles `DuelScreen` y `DuelCard`, pistas `duel_button`, `duel_card`, `duel_screen`) | `tests/test_ui_tutorial.gd` |

## Estado (v15)

Raíz `duels: {open: {id → duelo}, closed: [duelo]}` (ids `duel_0001`, `Ids.next(state, "duel")`; `closed` guarda los 20
últimos sin sus lances). Un duelo:

```
{id, challenger, challenged, challenger_family, challenged_family,
 cause: offense | courtship | rivalry, about (la persona cortejada o ""), kind: first_blood,
 status: pending | accepted | fighting, created, answer_by, at (minuto del duelo), place [x, y], weapon,
 challenge_witnesses (int), witnesses [chr], called (bool), started (minuto), duel (Duel.d), player_side (-1, 0, 1)}
al cerrar: status closed, outcome: fought | draw | yielded | no_show | refused | withdrawn, winner (chr o ""),
 closed_at, touches [a, b], lances
```

Migración 14 → 15 (`SaveFile._to_v15`): `duels` vacío. Un paso propio: el de v16 se encadena detrás en `_step`.

## Órdenes

| Orden | Campos | Gestión | Motivos |
|---|---|---|---|
| `duel_challenge` | actor, target, cause, kind | no (en persona) | `unknown_actor`, `unknown_target`, `dead`, `same_family`, `too_young`, `wounded`, `busy`, `cooldown`, `kind_locked`, `no_cause`, `too_far` |
| `duel_answer` | actor, duel, answer (`accept` \| `refuse`) | sí | `unknown_duel`, `not_challenged`, `already_answered`, `bad_answer` |
| `duel_withdraw` | actor, duel | sí | `unknown_duel`, `not_challenger`, `already_fighting` |
| `duel_move` | actor, duel, action (`strike` \| `parry` \| `feint`) | sí | `unknown_duel`, `not_fighting`, `not_your_side`, `no_breath`, `bad_action`, `already_chosen`, `duel_over` |
| `duel_auto` | actor, duel | sí | `unknown_duel`, `not_fighting`, `not_your_side` |
| `duel_brawl` | actor, target | no (en persona) | `unknown_actor`, `unknown_target`, `same_family`, `too_young`, `busy`, `too_far` |

- Los NPC dan `duel_answer` (por `Sim.give`, con `duel_ai: true`) en el minuto siguiente al reto; **nunca retan**.
- Las órdenes del propio duelo que da el sim llevan `by_duel: true` (`exit_building`, `move_to` de las 05:30).
- **Retención:** `Duels.holds(state, chr)` es verdad desde la llamada (05:30) hasta el cierre; `Sim.give` y las órdenes de
  `RivalAI` / `FamilyAI` en `Sim.step` no se dan a esos personajes (salvo `by_duel`). Las del jugador sí.

## Eventos

`duel_challenged {duel, actor, target, family, target_family, cause, about, kind}` ·
`duel_answered {duel, answer, actor (el retado), family, target_family}` · `duel_called {duel, family, target_family, place}` ·
`duel_started {duel, family (la del jugador si juega), target_family, witnesses, player_side}` ·
`duel_lance {duel, family, lances}` · `duel_finished {duel, outcome, winner, family, target_family, touches, lances, public,
absent}` · `duel_brawl {duel, actor, target, family, target_family, winner, witnesses, fact}` ·
`affinity_changed {actor, target, amount, affinity, reason: duel_*}` (cortejo).
Además los de siempre: `reputation_changed` (motivos `duel_win`, `duel_lose`, `duel_draw`, `duel_yield`, `duel_refuse`,
`duel_no_show`, `duel_no_show_rival`, `duel_withdraw`, `duel_challenge_refused`, `duel_brawl`), `relation_changed`,
`notice_added` (`notice.duel_*`), `emotion_ended` (ofensa resuelta).

## Crónica

`duel` (una por familia): `{family, duel, character, rival, cause, outcome, result: won | lost | draw | refused | withdrawn |
no_show, touches, public}`; `brawl`: `{family, actor, target, winner, fact}`.

## Vista

- `NpcPanel`: botón `DuelButton` («Retar a duelo…»), apagado con `Duels.challenge_status(..., check_range = false)`;
  abre `DuelDirector.show_challenge(actor, target)` (grupo `duel_director`).
- `DuelDirector` (hijo de `App`, sus nodos en `CardsLayer`): `DuelCard` (PageCard) para el reto, la respuesta y la
  incomparecencia; `DuelScreen` abierta en `duel_started` con `player_side ≥ 0` (pausa; al cerrar, la pausa vuelve a como
  estaba).
- `DuelScreen.open_game(sim, id, give)`: `give` es `Game.step_now` (aplica la orden y un paso del sim en el acto, también
  en pausa; devuelve los eventos). Esc = «Resolver sin jugar».
- Arte con caída: `VisualPaths.duel_vfx(kind)`, `duel_icon(id[, small])`, `duel_illustration(id)` (§4e.8).

## Rituales

- Reglas: `godot --headless --path . -s tests/run_tests.gd -- --only=test_combat` y `--only=test_ui_duel`.
- Bot: `godot --headless --path . -s tools/sim_runner.gd -- --scenario=duel_ready --bots=duelist --days=8 --seeds=5`.
- Banco: `godot --headless --path . -s tools/duel_bench.gd`.
- Capturas: `grimoire heavy --timeout 4m -- /opt/homebrew/bin/godot --audio-driver Dummy --always-on-top --path . --
  --smoke-script=duelo_partida` (y `--smoke-script=duel --duel-again` para el prototipo).
