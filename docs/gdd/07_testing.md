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

`data/targets.json` define las **dianas** (p. ej. `artisan_novice.gold_day10: [150, 400]` ya con la deuda pagada, `artisan_novice.debt_paid_by_day8: ≥ 0,9` de las semillas, `artisan_expert.days_to_citizen: [8, 20]`, `rival_smith.gold_day10: [40, 300]`, y el bloque `goldflow` con el oro neto por día de cada fase y la regla de conservación de 4.19). Las dianas son para dificultad Normal; Fácil y Difícil solo comprueban el orden (4.23). `tools/sim_runner.gd` escribe `reports/sim/<modo>_<semillas>.json` y `tools/sim_report.py` genera la página "Guild Renew · simulación" en Grimoire, con antes/después.

### 7.3 Tipos de prueba

- **Reglas puras** (la mayoría): crear un `WorldState` mínimo o cargar un escenario, dar órdenes, avanzar N pasos, comprobar el estado. Sin escenas.
- **Determinismo**: misma semilla + mismas órdenes → mismo hash del estado tras 30 días.
- **Conservación del oro**: tras N días de cualquier bot, la suma de asientos del libro de cada familia es igual a la variación de su oro (4.18, 4.19).
- **Escenarios de integración**: cargar `forge_two_workers.json`, avanzar 3 días, comprobar que hay espadas en el almacén **sin ninguna vista abierta** (prueba directa de BUG-024).
- **Vistas**: instanciar una vista con un estado y comprobar que pinta lo que debe (p. ej. cuántos trabajadores aparecen en el interior). Pocas.

### 7.4 Verificación por la interfaz (cómo verifica el manager una rama)

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
persona, puesto—, `station` / `door` en una sala, `key`, `type`, `spin`, `popup`, `wheel`, `pan`), una espera
(`until` con `timeout` y `fast`, un acelerón del reloj del arnés, nunca una orden), `expect`, `when` (solo si se
cumple), `soft` (si falla, sigue). Los flujos `teclas` (cada tecla en la ciudad y dentro: qué hace, si no hace nada o
si choca) y `esc` (cada pantalla se cierra con Esc) dan la cobertura de teclas.

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

Reglas: un solo Godot con ventana a la vez (`grimoire heavy`), y se cierra al acabar; los ajustes y las partidas
guardadas de los flujos van a `tmp/verifica_home` (nunca a los del owner). Si un flujo descubre que algo no se puede
hacer por la interfaz o se ve mal, es un hallazgo: se apunta en el informe, no se tapa en el flujo.
