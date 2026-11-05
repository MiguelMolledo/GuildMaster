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

Cada `DECIDE_EVERY` minutos, si el cabeza está libre (en casa, sin viaje ni ciclo en marcha, de día), puntúa las metas
abiertas que necesitan su cuerpo (cortejar, viajar, retar) frente a seguir con el negocio y toma la mejor. Si una meta
no está lista, apunta el porqué (`why_not`: «falta el título», «primero la deuda», «falta oro», «pocas opciones (0,31)»...).
Todo lo demás son órdenes de gestión, que se dan al momento. Solo da órdenes del jugador y lee lo que lee la UI. Con
la muerte del fundador, la forja pasa al nuevo cabeza, o al regente si el heredero es menor.

Donde el hábito de los bots anteriores no es de buen criterio, el jugador completo lo corrige en su propia clase y no
toca la de ellos, para que sus dianas no cambien:
- **Encargos de fiesta.** Mira las horas que quedan de verdad (`due_at`), no `deadline_days` redondeado. **Desde
  Equilibrio 11 (2026-11-05) lo hacen todos los bots** (`artisan_novice` y los de oficio: `_hours_left`); el completo
  solo apunta el porqué.
- **Mostrador.** Solo pone a alguien en él si tiene dos o más empleados.
- **Cortejo.** Corteja con un regalo por visita, y solo cuando la forja ya no depende de él o el bolsillo lo permite;
  nunca un segundo regalo el mismo día (Equilibrio 1: no contaría).
- **Ciudadano** (Equilibrio 3). Lo pide en cuanto el ayuntamiento se lo daría y le queda la reserva, no al acabar su plan
  de mejoras (el hábito del experto, que se queda en su clase por las dianas de H5). `BOT_VARS=titles_early=0` juega
  como antes.
- **El primer viaje** (Equilibrio 7). Guarda sus mejores espadas (excelentes, buenas y normales) hasta tener 3, como si
  fueran de un encargo, y las vende allí todas: la capital paga la calidad.
- **Sin salida** (Equilibrio 2). Pide el préstamo de urgencia en cuanto se lo ofrecen (el caótico, a veces).

`tools/full_player.gd` acepta además `--set=<tabla>.<clave>=<json>` como `sim_runner` (con `--tag`), para medir un
punto apagando los demás (rama equilibrio, `tools/equilibrio/measure.py`).

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
