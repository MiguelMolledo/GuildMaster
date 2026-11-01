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
