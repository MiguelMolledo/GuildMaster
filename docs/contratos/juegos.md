# Contrato · Juegos y competiciones (04f §4.26)

Rama `juegos`. Diseño: [docs/gdd/04f_vida_y_fiestas.md §4.26](../gdd/04f_vida_y_fiestas.md). Pantalla:
[docs/ui/mecanicas/juegos.md](../ui/mecanicas/juegos.md). Cifras: `data/games.json` (validador:
`tools/validate_games.py`, llamado desde `tools/validate_content.py`).

**Sin guardado.** Una partida vive mientras se juega en su pantalla y llega entera al sim en **una orden**
(`game_play`): las jugadas del jugador y si el resto se resolvió sin jugar. El sim la vuelve a jugar con las mismas
claves y aplica el oro y la reputación. Nada de los juegos entra en `WorldState` ni en el fichero de guardado.

## 1. Piezas (`sim/games/`)

| Clase | Qué es |
|---|---|
| `GameRules` | Tiradas con clave (`semilla | games | partida | paso | qué`), d6, d100 con críticos, lectura (`read_chance`), pista (`cue`), posterior de una pista, temperamentos |
| `GameMatch` | Base de todas las partidas, como `Duel`: `d` (JSON), `view(lado)`, `choose(lado, acción)`, `auto_finish()`, `result()`, `moves()`, `ai_move(lado)` |
| `AzarMatch`, `MayorMatch`, `PulsoMatch` | Bloque 1: «azar», «tres dados a la mayor» y pulso |
| `EnviteMatch` | Bloque 2: los naipes («envite», con farol y lectura del gesto) |
| `Betting` | Bloque 3: cuotas (`quote`, `market`), `settle`, la orden `game_bet` y las apuestas a la propia partida |
| `Games` | La API: `create`, `auto`, `win_odds`, `player_of`, `preset_player`, `player_ref`, `spec_of`, `replay` (la orden) |

Una tirada nunca usa `state.rng`: un juego no mueve ninguna otra tirada de la partida, y da igual cuándo se resuelva.
Misma semilla del mundo + mismo id de partida + mismos jugadores + mismas jugadas = misma partida (pruebas
`test_games_*`).

## 2. Jugadores

`{id, name, name_key, family, stats {…}, temper, preset, look}`.

- **Personajes del estado:** `Games.player_of(state, "chr_0006")` (sus atributos; temperamento `even`).
- **Fichas** (parroquianos, forasteros, jinetes de fuera): `"preset:<id>"` o `"preset:<id>#<n>"` para varios iguales,
  de `data/games.json` → `presets` (atributos, temperamento, nombre y aspecto). La Posada y las fiestas pueden añadir
  las suyas a esa tabla.
- **Temperamentos** (`tempers`): `even` (templado: la política que juega bien, la de «Resolver sin jugar»), `prudent`
  (pide más margen para seguir o doblar), `boastful` (el atrevido: sigue y dobla siempre), `cheat` (lee mejor:
  `read_bonus`).

## 3. La API

```gdscript
var spec := {"game": "azar", "match": "fest_0003|azar|1", "seed": state.world_seed,
	"players": [Games.player_of(state, me), Games.preset_player(cat.games, "preset:regular_boastful")],
	"player": 0,            # el lado que juega el humano (-1: nadie, la IA juega todos)
	"stake": 10,            # apuesta por cabeza (0 en las competiciones por premio)
	"opts": {"house": "bld_0042"}}   # opciones del juego (abajo)
var m := Games.create(cat.games, spec)   # para jugar paso a paso (la pantalla)
var r := Games.auto(cat.games, spec)     # la partida entera con la IA en todos los lados
var p := Games.win_odds(cat.games, spec, 60)  # {lado: probabilidad}: de donde salen las cuotas
```

`result()` = `{ok, over, game, winner (lado o -1), ranking [lados, el mejor primero], scores [por lado], net [oro de
cada lado: lo que gana o pierde de las apuestas, antes de la casa], how (cómo acabó), facts [...], stake}`.

**Opciones comunes** (`opts`): `house` (id del edificio con licencia de tafurería: la casa se queda `house.rake` de lo
que gana el ganador y se lo da al dueño; sin `house`, en la calle, 0), `rake` (forzar el margen: pruebas y bancos),
`event` (id de la fiesta o del turno de la posada: viaja en `game_played` para que quien llama aplique lo suyo).

**Opciones de cada juego:** `azar`: `thrower` (0/1: quién tira; si no, una tirada con clave), `loaded` (el lado que usa
dados cargados: en una orden solo `0`, el actor, y si lleva el objeto `loaded_dice`). `mayor`: `loaded`. `envite`:
`mano` (0/1). `pulso`: —.

## 4. La orden `game_play` (gestión: se aplica al momento, también en pausa)

| Campo | Qué |
|---|---|
| `actor` | El personaje del jugador que juega (lado 0) |
| `game` | `azar`, `mayor`, `pulso` (y los de los bloques siguientes) |
| `opponents` | Refs de los demás: ids de personajes o `preset:<id>[#n]` |
| `stake` | 5, 10, 25 o 50 (`stakes`; tope 50, O-V8); 0 en el pulso por orgullo |
| `opts` | Las de §3 |
| `moves` | Las jugadas del lado 0, en orden (`GameMatch.moves()`) |
| `auto` | `true` (por defecto): lo que falte se resuelve sin jugar. `false`: la partida tiene que venir acabada |
| `bets` | Opcional: `[{on: lado, stake}]` apuestas a la propia partida, a las cuotas de antes de jugarla (`on: 0` por uno mismo; contra uno mismo y perder habiendo jugado es fraude) |
| `match` | Opcional: el id de la partida. Por defecto `"<game>|<actor>|<minuto>"`: la misma partida no se puede volver a tirar en el mismo minuto, y cada partida jugada mueve el reloj un minuto por su orden |

Rechazos (`reason.<id>`): `unknown_game`, `unknown_actor`, `bad_players` (número de jugadores fuera de
`PLAYERS`, un rival desconocido o uno mismo), `bad_stake`, `over_cap`, `not_enough_gold` (hay que poder pagar lo
peor: el doble en los dados, siete veces la apuesta en el envite, más las apuestas), `unknown_house`, `bad_option`
(dados cargados fuera de los dados), `no_loaded_dice`, `bad_bet`, `bad_move` (una jugada que la partida no admite),
`unfinished`. `opts.rake` de una orden se ignora: el margen es el de la casa.

Efectos: el oro de la familia del actor cambia en su `net` (libro: categoría `games`); con `house`, la casa se queda
`floor(net × rake)` de una ganancia y se lo da al dueño del edificio (si es de otra familia). El oro de los rivales
viene de fuera y va a fuera (P4). Si en el día la familia lleva perdidos más de `warn_loss` (100) en el juego, un
aviso `notice.games_losses` (una vez al día, O-V8).

Dados cargados: cada rival puede verlos (d100 con clave ≤ `loaded.catch.base` + (su Empatía − Destreza del actor) ×
`step`). Si lo pillan: pierde la apuesta y los dados, `how: "caught"`, hecho público `cheat` (cargo `cheat`), reputación
`loaded.reputation` y el evento `game_cheat_caught {actor, family, match, how: loaded_dice | fraud, by, fact}`.

Evento: `game_played {actor, family, game, match, opponents, stake, winner, won, net, house_cut, house, how, moves,
facts, bets_net, event}`.

## 4 bis. La orden `game_bet` (apostar sobre una partida de otros)

`{actor, game, players [refs, todos ajenos al actor], match (obligatorio: el id de la partida), opts, on (lado),
stake, game_stake (la apuesta entre ellos, si la hay)}`. El sim calcula el mercado (`Betting.market`), juega la
partida con `Games.auto` (mismo id = mismo ganador que obtendría cualquiera) y liquida: `floor(stake × cuota) −
stake` o `−stake`; con `opts.house`, el dueño se lleva `floor(stake × margen)`. Rechazos: `unknown_game`,
`unknown_actor`, `bad_players`, `bad_stake`, `not_enough_gold`, `bad_bet` (lado fuera de rango o sin `match`),
`unknown_house`. Evento: `game_bet_settled {actor, family, game, match, on, stake, odds, winner, won, net, house,
house_cut}`.

Para apuestas que esperan a una competición futura (el calendario de las Fiestas, con su guardado v18):
`Betting.market(games, spec)` al apostar (guarda `odds`) y `Betting.settle(stake, odds, on, winner)` cuando
`Games.auto(spec)` da el ganador.

## 5. Para las otras ramas

- **Corredor de apuestas** (pantalla): `{actor, game, watch: true, players: [refs], match, stake}` abre el mercado,
  apuesta con `game_bet` y enseña la partida. Con `bets_open: true` en una partida propia, el mercado sale antes.
- **Posada** (mesa de juego, 4.27.4): abre la pantalla con `{actor, game: "azar" | "mayor" | "envite", opponents:
  ["preset:regular_…"], stake, opts: {house: <la taberna>, event: <el turno>}}` (App → `GameScreen.open`). Con
  licencia, la casa gana su parte por `game_played.house_cut`; sin licencia, jugar en la taberna es delito leve si lo
  ve el Alguacil (eso lo aplica la Posada al oír `game_played` con su `house`). Los parroquianos jugadores son fichas
  (`presets`) o vecinos del estado.
- **Fiestas** (espectáculos, 4.25.3 `spectacle`): para una competición sin el jugador, `Games.auto(spec)` con su
  `match` propio (p. ej. `"fest_<id>|justa"`) da ganador y clasificación sin mover nada. Para la del jugador, la
  pantalla con `opts.event`; los premios extra del patrocinador los aplica Fiestas al oír `game_played`.
- **Nuevos juegos:** un `*Match` que extiende `GameMatch`, su sección en `data/games.json`, su fila en
  `Games.GAMES`/`PLAYERS` y su tablero en `game/ui/games/board_<juego>.gd` (BOARDS de `GameScreen`).

## 6. Pruebas y bancos

- `tests/test_games_dice.gd`: reglas, determinismo, «Resolver sin jugar» = jugar bien, la orden y sus rechazos, la
  casa y el aviso de pérdidas. `tests/test_games_cards.gd`: el envite. `tests/test_games_bets.gd`: cuotas, `game_bet`,
  apostar a uno mismo y el fraude, dados cargados y que te pillen.
- Bot `gambler` (`sim/bots/bot_gambler.gd`, escenario `games_gambler`, diana `gambler`): `godot --headless --path . -s
  tools/sim_runner.gd -- --scenario=games_gambler --bots=gambler --days=8 --seeds=5` (en `run_all`, paso `gambler`).
- `godot --headless --path . -s tools/games_bench.gd [-- --n=4000 --only=azar,pulso]`: tablas de 04f §4.26.10.
- Capturas: `grimoire heavy --timeout 5m -- godot --audio-driver Dummy --always-on-top --path . --
  --smoke-script=juegos [--smoke-games=azar,pulso]` → `reports/shots/juegos_<juego>_{1,2,3}.png`.
- A mano: `godot --path . -- --games-test=<juego> [--games-stake=25] [--games-opponents=preset:regular_cheat]`.
