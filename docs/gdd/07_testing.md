## 7. Testing y verificación (el sistema de Wizards Broke It)

Se adopta tal cual el sistema de **rituales** de Wizards Broke It. Nada se da por hecho sin pasar los rituales que le tocan.

### 7.1 Rituales

| Ritual | Comando | Cuándo |
|---|---|---|
| **Reglas** | `godot --headless --path . -s tests/run_tests.gd [-- --only=<texto>]` | Siempre. Cualquier `ERROR`/`SCRIPT ERROR` durante una prueba la hace fallar. |
| **Contenido** | `python3 tools/validate_content.py` (+ `content_selftest.py`) | Al tocar `data/`. 0 errores. |
| **Arranque** | `godot --headless --path . --quit-after 120` y con cada escenario (`-- --scenario=<id>`); todos a la vez con `zsh tools/qa/boot_check.sh` | Siempre antes de sellar. Sale con 0 y sin `ERROR`. |
| **Guardado** | Ida y vuelta (`save → load → comparar dict`) en tests + `tools/stress_check.gd` (ficheros rotos) | Cada hito; el estrés completo, antes de cada release. |
| **Entrada real** | `godot --headless --path . -s tools/input_check.gd` (ratón/teclado → órdenes, sin ventana) | Si se toca UI o controles: los bots dan órdenes directas y no la cubren. |
| **Simulación con bots** | `godot --headless --path . -s tools/sim_runner.gd -- --scenario=<id> --bots=<b> --days=N --seeds=30 --jobs=3` | Al tocar reglas de economía, empleados, familia o política. Comprueba **dianas**. |
| **Coste del sim** | `godot --headless --path . -s tools/sim_bench.gd` | Al tocar sistemas que corren cada paso. Diana: < 2 ms/paso. |
| **Visual (smoke)** | `grimoire heavy --timeout 3m -- godot --audio-driver Dummy --path . -- --smoke --scenario=<id> --shots=12 --seed=3` | La última comprobación, no la primera. **Hay que mirar las capturas.** |
| **Rendimiento real** | `grimoire heavy -- godot --audio-driver Dummy --path . --resolution 1280x800 --disable-vsync -s tools/perf_check.gd` | Al cambiar vistas, luces o población. |
| **Build** | `grimoire heavy -- python3 tools/build_check.py` (exporta y arranca; comprueba textos, arte en CPU y sonido) | Antes de entregar una versión jugable. |
| **Todo junto** | `python3 tools/qa/run_all.py [--visual]` → página de QA en Grimoire | Al cerrar un hito. |

### 7.2 Bots

Los bots juegan **dando órdenes**, igual que la UI. Sirven para medir el balance y para detectar bloqueos.

| Bot | Qué hace | Para medir |
|---|---|---|
| `idle` | No hace nada | Que el mundo sigue solo (NPC, mercado, días, herrero rival) y nada se rompe; que el oro solo baja por mantenimiento y deuda. |
| `artisan_novice` | Compra hierro, produce lingotes y espadas a mano, vende en el mercado, cumple encargos, paga la deuda inicial | Oro a los 3/10 días; deuda pagada antes del día 8; oro neto/día de la fase de inicio (4.19); que el bucle core es rentable pero no trivial con el rival compitiendo. |
| `artisan_expert` | Contrata, usa la cola, mejora la Forja, construye un segundo negocio, sube de título | Tiempo hasta Ciudadano/Patricio; oro a los 30 días; curva de crecimiento; oro neto/día y peso de los sumideros por fase (4.19). |
| `dynasty` | Corteja, se casa, tiene hijos, designa heredero | Que la herencia funciona y que una generación dura lo previsto con D1(b): ~25 años ≈ 200 días; primer hijo ~1,5 años tras la boda. |
| `politician` | Sube reputación y se presenta a cargos | Tiempo hasta el primer cargo; % de elecciones ganadas. |
| `crook` | Mejoras de Secretos, sobornos | Frecuencia de inspecciones y juicios; que el crimen compensa con riesgo. |
| `random_clicker` | Órdenes aleatorias válidas e inválidas | Que ninguna orden rompe el estado (fuzzing). |
| `full_player` | La partida entera con todo encendido y buen criterio, componiendo los bots anteriores (§7.4) | Que todo junto se juega: deuda, títulos, familia, desbloqueos a tiempo, mecánicas tocadas, ritmo, atascos, coste. |
| `chaos_player` | La misma partida con decisiones y órdenes válidas al azar; guarda y carga cada día (§7.4) | Que nada se cuelga ni deja estados imposibles, y que el guardado recupera siempre lo mismo. |

`data/targets.json` define las **dianas** (p. ej. `artisan_novice.gold_day10: [150, 400]` ya con la deuda pagada, `artisan_novice.debt_paid_by_day8: ≥ 0,9` de las semillas, `artisan_expert.days_to_citizen: [8, 20]`, `rival_smith.gold_day10: [40, 300]`, y el bloque `goldflow` con el oro neto por día de cada fase y la regla de conservación de 4.19). Las dianas son para dificultad Normal; Fácil y Difícil solo comprueban el orden (4.23). `tools/sim_runner.gd` escribe `reports/sim/<modo>_<semillas>.json` y `tools/sim_report.py` genera la página "Guild Renew · simulación" en Grimoire, con antes/después.

### 7.4 El jugador completo y el caótico

Cada bot de 7.2 prueba su sistema por separado, y muchos con interruptores apagados (`_no_events`, `_no_life`,
`_festivals`) para que sus dianas no se muevan. El **jugador completo** (`sim/bots/bot_full_player.gd`) juega la partida
entera con todo encendido, como un jugador con buen criterio, y sirve para probarlo todo junto.

**Cómo juega.** No reinventa ningún sistema: compone los bots que ya existen. El negocio es `festive` (que es
`artisan_expert`, que a su vez es `artisan_novice`): la deuda, forjar a mano, el mercado, los encargos del tablón y los
de las fiestas, los empleados y su cola, las mejoras, los títulos, los cargos menores (`runs_office`), el patrocinio y
el banquete de su boda. Al acabar su plan de mejoras añade el mostrador. La familia es `dynasty`: corteja, propone, se casa
y luego corteja el heredero con su propio cuerpo; elige la Artesanía en la escuela y nombra heredero al mejor
artesano. Los sucesos son `guard_watch` (las cartas de incidente) y sus propias respuestas a los microeventos. El duelo es
`duelist` (los lances). Los viajes, las caravanas y los tratados salen de `merchant`. Añade lo que a ninguno le tocaba:
acusar en el tribunal con un hecho público y defenderse o acusar en la vista.
- **La Taberna-Posada** (posada, 04f §4.27) es `innkeeper`. Cuando ya es Ciudadano (el segundo negocio de 03b), el
  negocio va solo y le sobra el precio sobre la reserva, compra la taberna en venta y se la asigna a un adulto libre
  de la familia, primero el cónyuge (`assign_building`). `BotInnkeeper` la lleva con ese posadero. Las mejoras de la
  taberna solo se compran si queda la reserva de la forja.
- **La Forja viva y los desbloqueos** (forja, 03b §3b.2-§3b.4). Todo trabajo a mano en un yunque va en modo `live`, y
  cada minuto toma la decisión del ciclo bien: el color de la receta, su plantilla de golpes (con los de la variante) y
  el temple que pide el encargo, o si no el de la receta (como `pacing`). La pieza de un encargo con variante se hace a
  ella (`work_at` con `contract` y `variant`). Lee cada carta de desbloqueo (`unlock_seen`) y no contrata ni compra
  mejoras hasta que la interfaz las abre (`Unlocks.ui_open`): lo que el jugador no ve, el bot no lo usa. El caótico
  toma la mitad de las decisiones de la forja viva al azar, o «Resolver sin jugar».
- **Los juegos** (04f §4.26). En el último día antes de una competición de una fiesta (`FestivalGames`) se inscribe
  (`game_enter`) si su probabilidad de ganar (`Games.win_odds`) supera en un 20 % la media del campo y cumple el título
  y la entrada. Cuando le llaman, la juega con «Resolver sin jugar». Si no entra, apuesta 5 al favorito
  (`game_bet`) mientras le sobre oro. El caótico juega dados por poco en la calle y se inscribe o apuesta al azar.

Cada `DECIDE_EVERY` minutos, si el cabeza está libre (en casa, sin viaje ni ciclo en marcha, de día), puntúa las metas
abiertas que necesitan su cuerpo (cortejar, viajar, retar) frente a seguir con el negocio y toma la mejor. Si una meta
no está lista, apunta el porqué (`why_not`: «falta el título», «primero la deuda», «falta oro», «pocas opciones (0,31)»...).
Todo lo demás son órdenes de gestión, que se dan al momento. Solo da órdenes del jugador y lee lo que lee la UI. Con
la muerte del fundador, la forja pasa al nuevo cabeza, o al regente si el heredero es menor.

Donde el hábito de los bots anteriores no es de buen criterio, el jugador completo lo corrige en su propia clase y no
toca la de ellos, para que sus dianas no cambien:
- **Encargos de fiesta.** Mira las horas que quedan de verdad (`due_at`), no `deadline_days` redondeado.
- **Mostrador.** Solo pone a alguien en él si tiene dos o más empleados.
- **Cortejo.** Corteja con un regalo por visita, y solo cuando la forja ya no depende de él o el bolsillo lo permite.

**El caótico** (`sim/bots/bot_chaos_player.gd`) es la misma partida al azar. Elige al azar entre las metas listas, da una
respuesta al azar a cada carta y, cada ~40 minutos de juego, da una orden válida al azar. La orden sale del sistema
que menos ha tocado (peso 1/(1 + usos)), entre 18: andar, comprar y vender, trabajar, la cola, el personal, las mejoras,
los encargos, el cortejo, el heredero, los cargos, las acusaciones inventadas, el duelo, los viajes, las caravanas, los
tratados, las fiestas, la deuda y mover cosas. «Válida» quiere decir que se construye con lo que existe y, donde las
reglas tienen una consulta de estado, con una que dice que sí. Hasta saldar la deuda inicial solo da órdenes que no
gastan (si no, se arruina el día 9 y no llega a nada). Su dado es suyo (`RandomNumberGenerator` con la semilla), nunca
`state.rng`.

**El runner** (`tools/full_player.gd`) no pasa por `sim_runner`, porque nunca apaga nada:

```
godot --headless --path . -s tools/full_player.gd -- [--bot=full_player|chaos_player] [--years=3 | --generation]
    [--seeds=3 | --seed-list=1,4] [--difficulty=normal] [--roundtrip] [--tag=<nombre>] [--no-check]
python3 tools/full_report.py [reports/<carpeta> ...]       # el resumen HTML (index.html en cada carpeta)
python3 tools/qa/noche.py [--seeds=5] [--gen-seeds=2] [--chaos-seeds=3]   # las corridas largas, de noche
godot --headless --path . -s tools/full_player.gd -- --bot=idle_player --years=3 --seeds=3   # la IA sola
```

`--years=N` juega N años (3 por defecto, 24 días). `--generation` juega hasta que muere el fundador y el heredero ha llevado la
casa 8 días más (como mucho, hasta la edad de muerte segura). En `run_all`, los pasos `full` y `chaos` juegan 1 año con
1 semilla (~35 s cada uno) y `full_html` hace su resumen. La noche corre 3 años × 5 semillas, una generación × 2, el
caótico 3 años × 3 e `idle_player` 3 años × 3, y escribe `reports/qa/noche.md`. `BOT_VARS=goals=0` prueba el jugador sin metas propias (solo el
negocio), para ver lo que le cuesta cada meta.

**El informe** (`reports/<bot>[_<tag>]/<semilla>.json`, `summary.json` e `index.html`) recoge:
- las curvas de oro, deuda, reputación, título, empleados y familia;
- el oro neto por día de cada año;
- la familia (bodas, hijos, muertes, herencia, heredero designado), los títulos y los cargos;
- cada desbloqueo de `data/unlocks.json` frente a su ventana de 03b (a tiempo, pronto o tarde con ±1 día, o nunca);
- cada mecánica, usada o no: el día de su primer uso, sus órdenes y rechazos, y, si nunca la tocó, por qué («aún no
  está en el juego», «falta el título», el `why_not` del bot o «no se dio la ocasión»);
- los segundos reales entre decisiones, como el bot `pacing`: ×1, y ×8 cuando el jugador saltaría el tiempo;
- las órdenes rechazadas del bot, con su motivo;
- los atascos y su causa probable: un personaje que ni anda ni trabaja 12 h; la cola con trabajo pendiente y empleados,
  pero sin ningún ciclo durante 8 h de día; los encargos que fallan;
- los errores y avisos del motor, contados con un `Logger` (`OS.add_logger`);
- el bench con todo encendido: la media, el p99 y el peor paso, el coste del bot, los pasos de más de 50 ms y los de
  más de 2 s;
- la partida guardada al final y en el primer atasco, en `saves/`. Para abrirla en el juego, se copia como
  `slot_3.json` a la carpeta de guardado y se carga la ranura 3 desde el menú.

El caótico, además, guarda y carga cada día en memoria, compara el hash y sigue jugando con lo cargado (`--roundtrip`
hace lo mismo con el completo). También comprueba los estados imposibles: oro negativo o alguien fuera del mapa.

**El resto del mundo** lo mide `tools/full_watch.gd`, en la misma partida.
- **Las familias rivales** (las de la IA con perfil). De cada una: la curva de oro, título, reputación, edificios y
  familia; títulos, cargos, bodas, hijos y herencias; ventas, compras y encargos; los encargos de fiesta que le ganó al
  jugador; sus ataques al jugador (hoy, el juicio); qué tareas eligió en cada plan de `RivalAI` y cuáles terminó; sus
  órdenes rechazadas; los días parada (sin vender ni trabajar) y sin oro; y los atascos de su cabeza (16 h sin moverse).
  La agenda de intenciones de 04c es H6 y no está hecha: lo que se mide es el plan de tareas de hoy.
- **El pueblo.** Cada hora, la actividad y las necesidades de los vecinos (`Agenda.view`), con la peor parte de horas
  con una necesidad baja (< 25), por separado para adultos, empleados y niños. Además: los vecinos atascados (20 h),
  la población al final de cada año, las bodas, nacimientos y muertes, los forasteros por día y por tipo, los sucesos
  por estación y la guardia (llamadas, llegadas y minutos hasta llegar).

`--bot=idle_player` juega la misma partida sin hacer nada (como `idle`): el jugador se arruina hacia el día 11 y el
mundo sigue hasta el horizonte (`ending_day` dice cuándo acabó la suya). Sirve para ver si la IA y el pueblo avanzan
solos. El formato de los JSON es estable y está documentado en `docs/contratos/informe_jugador_completo.md`
(`format_version`). Lo leen el HTML y el resumen de balance de la rama `verifica`.

**Dianas** (`data/targets.json`, `full_player` y `chaos_player`; `_needs_days` deja fuera lo que una corrida corta no puede
juzgar).
- **Jugador completo:** ninguna orden rechazada, el libro cuadra, ningún error del motor, la deuda saldada en el año 1,
  Ciudadano en 3 años (con media de los días 9-24), boda en ≥ 2/3 de las semillas, al menos un hijo en ≥ 30 %,
  ≥ 14 mecánicas tocadas, paso medio < 5 ms y, en la generación, herencia sin fin de partida.
- **Caótico:** ningún error, ningún paso de más de 2 s, la ida y vuelta del guardado idéntica, nunca oro negativo ni
  nadie fuera del mapa, y el libro cuadra.

Lo que el bot encuentra (lo roto, lo que no compensa, lo que llega tarde) no se arregla para que pase: se apunta en
el informe y en `docs/decisiones.json` (pendientes).

### 7.5 Tipos de prueba

- **Reglas puras** (la mayoría): crear un `WorldState` mínimo o cargar un escenario, dar órdenes, avanzar N pasos, comprobar el estado. Sin escenas.
- **Determinismo**: misma semilla + mismas órdenes → mismo hash del estado tras 30 días.
- **Conservación del oro**: tras N días de cualquier bot, la suma de asientos del libro de cada familia es igual a la variación de su oro (4.18, 4.19).
- **Escenarios de integración**: cargar `forge_two_workers.json`, avanzar 3 días, comprobar que hay espadas en el almacén **sin ninguna vista abierta** (prueba directa de BUG-024).
- **Vistas**: instanciar una vista con un estado y comprobar que pinta lo que debe (p. ej. cuántos trabajadores aparecen en el interior). Pocas.

### 7.6 Verificación por la interfaz (cómo verifica el manager una rama)

Los bots juegan dando órdenes; la **verificación por la interfaz** juega como una persona: solo eventos de ratón y
teclado (`InputEventMouseMotion`, `InputEventMouseButton`, `InputEventKey`) entran por `Input.parse_input_event`, el
mismo camino que los del sistema (mapa de entrada, GUI, `_unhandled_input`, la cámara). Es la otra mitad de los bots
`full_player` y `chaos_player`: ellos miden el sim, esto mide que todo se puede hacer, se ve y se entiende.

**Piezas** (`game/smoke/flow/`):
- `UiDriver`: busca un control por su nombre (`%UniqueName`), su texto (o una clave i18n), su tooltip, la fila en la
  que está o un localizador del panel (`row_of`, `cell_of`, `tab_button`), lo trae a la vista con la rueda si está en
  una lista, lleva el ratón hasta él en varios pasos, comprueba que es el control que hay bajo el puntero y hace clic.
  Si no recibe el clic es un fallo con su motivo: no se ve, deshabilitado (con su tooltip o «sin motivo»), fuera de
  pantalla, **lo tapa** otro control, o el panel **rehízo el botón** entre pulsar y soltar (el clic se pierde: se apunta
  y se pulsa otra vez, como haría una persona).
- `FlowRunner` (`--flow=<id>` / `--flows=all|quick|a,b`): juega `data/flows/<id>.json` paso a paso; tras cada paso
  comprueba el estado (expresiones sobre `FlowQuery`: `q.gold() > q.was('gold')`, `q.order('buy')`,
  `q.visible('LedgerPanel')`...), guarda una captura (con ventana) y pasa las comprobaciones visuales. Las cartas que
  saltan solas (un evento, una fiesta) y tapan lo que el paso quería se cierran con su «Entendido» y se apuntan como
  interrupción. Escribe `reports/verifica/<fecha>/<flujo>/result.json`.
- `VisualAudit`, en cada paso y cada pantalla: texto cortado o que se sale de su caja o de la pantalla, letra por
  debajo de 8 px o a un tamaño que no es el suyo (`tools/ui/tokens.json`), fuente que no es del theme, contraste por
  debajo de 3:1 (aviso) o 2:1 (fallo; necesita la captura), controles o textos solapados, claves i18n o `[ids]` en
  pantalla, rótulos de greybox, y avisos recién salidos tapados por un panel. Cada fallo con su recorte marcado en rojo.

**Flujos** (`data/flows/*.json`, un paso por línea; `python3 tools/verifica/fmt_flows.py` los formatea): un paso es
una acción (`click` / `right_click` / `double_click` sobre un control, `world` sobre la ciudad —casilla, edificio,
persona, puesto—, `station` / `door` en una sala, `inn` —`guest` o `bed`— en la sala de una posada, `key`, `type`,
`spin`, `popup`, `wheel`, `pan`, `restart` —otro escenario a mitad de flujo—), una espera
(`until` con `timeout` y `fast`, un acelerón del reloj del arnés, nunca una orden), `expect`, `when` (solo si se
cumple), `soft` (si falla, sigue). Los flujos `teclas` (cada tecla en la ciudad y dentro: qué hace, si no hace nada o
si choca) y `esc` (cada pantalla se cierra con Esc) dan la cobertura de teclas.

**Escenarios de los flujos**: cuando ninguna partida de las que ya hay llega a una orden, el flujo empieza en un
escenario hecho para él por `tools/scenarios/make_verifica_scenarios.gd` (cada uno sale de un escenario que ya existe o
de una partida nueva; mismo código y mismos datos, mismo fichero): `patron_treaties` (Barón y alcalde con reputación en
la aldea: los tratados y los encargos de fuera, flujo `tratados`), `judge_family` (Hugo juez y la vista del juicio
contra el rival a punto de empezar: `juez`), `school_age` (Clara recién cumplidos los 8: `escuela`),
`courtship_gifts` (regalos en la bolsa y oro para el banquete: `regalos`), `festival_eve` (la víspera de un torneo:
`fiestas`), `inn_chores` (la posada con camas sin hacer y gente esperando), `tavern_for_sale` (la posada en venta con
oro para comprarla) y `altercation_purse` (oro para apostar en un altercado); los tres últimos, en `taberna` y `dados`.

**Lanzarlo**:

| Para qué | Comando |
|---|---|
| Un flujo a mano, viéndolo | `godot --path . -- --flow=primer_dia` |
| Rápido, sin ventana (pasos y comprobaciones, sin capturas ni contraste) | `python3 tools/verifica/verifica.py --flows=quick` |
| El paso `ui` de `run_all` (los flujos `quick`, con ventana, cada uno por `grimoire heavy`) | `python3 tools/qa/run_all.py --only=ui` |
| Completo, para la noche (todos, con capturas, y el artifact en Grimoire) | `python3 tools/qa/run_all.py --night` o `python3 tools/verifica/verifica.py --window --flows=all --artifact` |
| Rehacer solo el informe | `python3 tools/verifica/report.py [--sim-dir=<reports/sim>]` |

**Cómo revisa el manager una rama** antes de juntarla:
1. QA de la rama (`python3 tools/qa/run_all.py`, que ya incluye `ui`) y, si la rama toca pantallas o controles, el
   modo completo con `--artifact`.
2. Abre `reports/verifica/<fecha>/index.html` (o el artifact «GuildMaster · verificación por la interfaz»):
   - **Hallazgos, por gravedad**: `bloquea` (el flujo no pudo seguir), `fallo`, `aviso`. Los de la rama, antes de juntar.
   - **Flujos**: cada paso con su captura, sus comprobaciones, las órdenes que dio (`/mouse` o `/key`) y lo que falló.
   - **Por pantalla**: los fallos visuales con su recorte.
   - **Cobertura**: cada orden de `Orders.apply` con su camino por ratón y por teclado probados (o el motivo apuntado
     en `data/flows/_coverage.json`), las teclas que no hacen nada o chocan, y las pantallas que no cierra Esc.
   - **Balance**: de los informes de los bots (`reports/sim/`): oro, oro neto por día, títulos, dianas fallidas, lo que
     no pasa nunca y los gastos que nunca devuelven.
   - **Revisión de estilo**: una captura por pantalla, una al lado de otra, con tres preguntas: ¿se lee el título?,
     ¿encaja la ventana con el resto?, ¿se entiende qué hacer? Esto lo mira el manager con sus propios ojos.
3. Un flujo nuevo por cada mecánica nueva que se pueda tocar: si la rama añade una pantalla o una orden, añade (o
   amplía) su flujo y su motivo en `_coverage.json` si no necesita ratón o teclado.

**Teclado** (`--flow-input=keys`; `verifica.py --keys` o `--both`): los mismos flujos, pero cada clic sobre un control
se hace con Tab (y F6 para cambiar de zona) hasta él y Enter; las cantidades se escriben; el mapa y las salas siguen
siendo del ratón (su motivo, en `_coverage.json`). Sus resultados van a `<flujo>__teclado/` y la cobertura junta las dos
pasadas: una orden cuenta por teclado si algún flujo la dio con el teclado. El modo noche (`run_all --night`) juega las
dos.

**Pasada de jugador** (`python3 tools/verifica/jugador.py [--window]`): el primer año de la partida por defecto
(semilla 11), jugado como un novato:
- el tutorial de lo básico;
- los objetivos;
- las cartas «Nuevo»;
- medias jornadas de oficio.

Son bloques cortos de `data/flows/jugador/` en una sola sesión: el bloque 2 y los siguientes empiezan con
`start {"keep": true}`, la partida como la dejó el anterior. Los bloques 06-15 los genera `jugador_bloques.py`.
Escribe `reports/jugador/<fecha>/`: las capturas de cada bloque y `ritmo.json`, con los tramos sin decisión en
segundos reales a la velocidad del jugador, para compararlos con la diana de 03b §3b.6. El informe de cada pasada,
con sus hallazgos por gravedad y su dueño, va en `reports/jugador/<fecha>/informe.md`.

Reglas: un solo Godot con ventana a la vez (`grimoire heavy`), y se cierra al acabar; los ajustes y las partidas
guardadas de los flujos van a `tmp/verifica_home` (nunca a los del owner). Si un flujo descubre que algo no se puede
hacer por la interfaz o se ve mal, es un hallazgo: se apunta en el informe, no se tapa en el flujo.
