# Pantalla · Juegos y competiciones

Reglas: [docs/gdd/04f_vida_y_fiestas.md §4.26](../../gdd/04f_vida_y_fiestas.md). Contrato:
[docs/contratos/juegos.md](../../contratos/juegos.md). Escena: `game/ui/games/game_screen.tscn` (`GameScreen`), un tablero
por juego en `game/ui/games/board_<juego>.gd` (`GameBoard`).

## Disposición (como el duelo)

```
┌──────────────────────── Nombre del juego (gótica dorada) ────────────────────────┐
│                         Apuesta: 10 de oro · en la tafurería                      │
│ [retrato ×2]   ┌──────────────── tablero del juego 404×180 ────────────────┐ [retrato ×2] │
│  Nombre        │  dados / brazos / naipes / liza / pista…                   │  Nombre      │
│  atributos     │                                                            │  atributos   │
│                └────────────────────────────────────────────────────────────┘  (otros)     │
│ ┌ pergamino: la decisión ─────────────────────────────────────────────────────────┐ │
│ │ Título (lo que se decide) · texto (lo que sabes: odds, gesto) · fiabilidad/oro    │ │
│ └──────────────────────────────────────────────────────────────────────────────────┘ │
│ [Acción 1] [Acción 2] [Acción 3]                               [Resolver sin jugar A]│
│ últimas líneas del registro                                                        │
│ Arte provisional: falta …                                                          │
└────────────────────────────────────────────────────────────────────────────────────┘
```

- **Retratos:** `PortraitFrame` grande (82×82) del jugador (dorado) y del primer rival; los demás (a la mayor, la
  carrera, el torneo) en pequeño bajo el rival. Las fichas (`preset:`) tienen un aspecto por `look`.
- **Tablero:** dibujo por código de lo que cambia cada paso (dados, brazos, posiciones), sobre el fondo del juego
  (`VisualPaths.game_art(<juego>, "table")`). Sin arte, greybox con su etiqueta, y la línea «Arte provisional: falta …»
  al pie dice qué piezas faltan.
- **Decisión:** el pergamino dice qué se decide y **todo lo que cuenta**: en los dados, cuántas de cada 100 ganas y el
  oro esperado de cada opción; en el pulso, el gesto del rival y su fiabilidad («Fiable: 6 de cada 10») o cuánto te
  lee él. Mientras se anima un paso no se adelanta el resultado («Ruedan los dados», «¡Empujan!»).
- **Acciones:** un botón por acción de la decisión abierta (teclas 1-4), con su coste de fuerza si lo tiene y apagado
  con su motivo. **Resolver sin jugar** (A) juega el resto con la IA. **Esc**: resuelve sin jugar si la partida no ha
  acabado (no se deja una partida a medias), cierra si ya acabó.
- **Resultado:** `PageCard` con la lámina del juego (`VisualPaths.game_illustration("game_<juego>")`), quién gana,
  cómo acabó y **lo que el sim aplicó** (el oro, la parte de la casa); «Otra partida» y «Cerrar».

## Tableros

| Juego | Tablero | Animación |
|---|---|---|
| Azar | Tira (quién), en juego, la suerte de cada uno (grande), la tirada en el centro y las de antes | Cada tirada rueda 0,35 s (0,16 s si son muchas) |
| A la mayor | Una fila por jugador: nombre, tres dados (el del cubilete, tapado), lo que se ve y lo que decidió | Al final se levantan los cubiletes |
| Pulso | Dos antebrazos sobre la mesa; fuerza y empujes de cada uno | El forcejeo y la caída del brazo del que pierde |
| Envite | Sus tres naipes boca abajo arriba, los tuyos abajo, las tres bazas en el centro, lo que hay en juego y quién es mano | Lo que dice cada uno («¡Envido!») y cada baza al descubrirse |
| Torneo | El cuadro de los ocho a la izquierda (los que ganan suben) y el combate en curso a la derecha (toques, aliento, asalto y lance) | Tus lances uno a uno, como el duelo; los combates de los demás, de golpe |
| Justa | La liza con la tela en el centro, los dos jinetes y sus puntos | La carga, el choque y lo que hizo cada lanza («¡Al pecho! +2», «¡Desmontado!») |
| Sortija | El marcador de los jinetes, la calle con sus tres postes y la anilla (grande, mediana o pequeña) | El jinete cruza, baja la lanza en el poste que eligió y la anilla se ensarta o se mece |
| Carrera | Una calle por jinete con los cuatro tramos, cada caballo donde va y su fuelle | Los caballos avanzan juntos; quien tropieza en la curva lo dice |
| Toros | La plaza cerrada con carros, el toro, el mozo de turno y los aplausos de cada uno | La embestida, el quiebro o la huida tras los carros, y lo que dio |
| Apuestas | El corredor: la probabilidad y la cuota de cada uno en el pergamino; «Por: …» recorre los participantes, «Apuesta: n» las cantidades, «Apostar (paga x)» y «Sin apuesta» | Con `watch`, después se mira la partida |

## Probarlo

- `godot --path . -- --games-test=<azar|mayor|pulso|envite|tourney|joust|sortija|race|bulls|apuestas>` (sobre la partida en pausa, contra el herrero rival; la orden
  va al sim de verdad). `--games-stake=`, `--games-opponents=preset:regular_cheat,…`, `--games-house=<edificio>`.
- Capturas: `--smoke-script=juegos [--smoke-games=…]` → `reports/shots/juegos_<juego>_1` (antes de decidir), `_2` (el
  momento clave, a media animación) y `_3` (el resultado).
