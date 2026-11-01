## 5. Arquitectura técnica

La arquitectura copia la que ya funciona en **Último Faro** y **Wizards Broke It** (`~/Code/wizards-broke-it`, sección "Arquitectura" de su `CLAUDE.md`), adaptada a un simulador de gestión en vez de a un juego de acción.

### 5.1 Stack

| Pieza | Elección | Motivo |
|---|---|---|
| Motor | **Godot 4.7.x** (fijar versión; misma que Wizards) | MIT, GDScript va bien con IA, ya hay experiencia y herramientas propias. |
| Lenguaje | GDScript con **tipado estático siempre** | Errores antes; el agente lo respeta mejor. |
| Render | GL Compatibility, filtro **Nearest**, partículas `CPUParticles2D` | Pixel art nítido; las partículas GPU no llegan en Compatibility. |
| Resolución | **960×540 escalado ×2 entero** (D2) | Píxeles siempre enteros con sprites de 48 px y tiles 64×32; la UI se diseña a esa escala. Ojo con la escala 1,6 de los edificios (pendiente D17). |
| Tests | Runner propio estilo Wizards (`tests/run_tests.gd` + `test_case.gd`) | Cualquier `ERROR` durante una prueba la hace fallar. Sin addons. |
| Inventario | Propio (no Gloot) | Ver L5. |
| Datos | JSON, una ficha por cosa, en `data/` | Validables por script, editables por el agente, diffs legibles. |
| Herramientas | Python 3 en `tools/` | Validador, generador de fichas, informes, cuaderno, pipeline de arte/audio. |

### 5.2 Capas: `sim/` decide, `game/` dibuja

```
sim/      TODAS las reglas. GDScript puro (RefCounted), sin nodos, determinista.
  core/     world_state.gd · clock.gd · rng.gd (con semilla) · ids.gd · event_log.gd · commands.gd
  econ/     inventory.gd · market.gd · production.gd · recipes.gd · quality.gd · ledger.gd · contracts.gd · loans.gd · errands.gd
            services.gd [EA, reservado]
  build/    buildings.gd · upgrades.gd · parcels.gd · construction.gd
  people/   characters.gd · employment.gd · relationships.gd · emotions.gd · lifecycle.gd · family.gd
  city/     routines.gd · social.gd · npc_expansion.gd · customers.gd · microevents.gd
  farm/     crops.gd [EA, reservado]
  crime/    combat.gd · theft.gd · guards.gd [EA, reservado]
  politics/ reputation.gd · titles.gd · offices.gd · elections.gd · tribunal.gd · inspections.gd
  ai/       directives.gd · schedules.gd · rival_smith.gd · family_ai.gd (utility AI, 4.21)   (dan órdenes, como el jugador)
  meta/     save.gd · migrations.gd · chronicle.gd · objectives.gd · score.gd
  bots/     bots que juegan dando órdenes (artesano_novato, artesano_experto, especulador…)
game/     presentación: escenas, vistas, UI, cámara, entrada, audio, VFX
  world/    vista del mapa exterior (tiles, edificios, NPC visibles)
  interior/ vista de un interior (puestos, trabajadores animados según el sim)
  ui/       HUD, paneles, tema, gestor de paneles
  input/    traduce ratón/teclado a órdenes
data/     catálogos en JSON (items, recetas, edificios, mejoras, cargos, eventos, microeventos, encargos, perfiles de IA,
          inicios, objetivos, metas, puntuación, frases, mapa, time.json, targets.json)
assets/   art/ (PixelLab) · audio/ (ElevenLabs, Suno) · fonts/ · inventario.json (8.5)
i18n/     strings.csv (ES y EN)
tools/    validador, new_content, sim_runner, informes, cuaderno, pipeline de arte y audio, qa/
tests/    pruebas de reglas sin ventana
docs/     gdd/ · hitos.json · decisiones.json · novedades.json · ASSETS.md · protocolos/ · style/ · paginas.json (8.5)
```

**Reglas de la arquitectura (no romperlas):**

1. **`sim/` contiene todas las reglas y es determinista**: misma partida guardada + misma semilla + mismas órdenes = mismo resultado. El azar sale del `RandomNumberGenerator` del estado, nunca de `randf()` global. No usa nodos, ni escenas, ni la física de Godot, ni `Time`.
2. **`game/` solo dibuja y traduce entrada a órdenes.** Las vistas leen el estado y escuchan eventos. Nunca calculan reglas (ni precios, ni calidad, ni si alguien puede trabajar).
3. **Las cifras viven en `data/`**, nunca en el código.
4. **Preparado para N personajes controlados:** toda orden lleva `actor_id`. No hay "el jugador" global; hay una familia controlada por el humano y familias controladas por IA, con las mismas órdenes.
5. **Un interior es una vista.** Entrar en la Forja no cambia nada en el sim; solo crea la escena que pinta el estado de ese edificio. Salir la destruye. La producción sigue igual (corrige L1 / BUG-024).
6. **Ordenar `StringName`:** nunca compararlas con `<` (Godot ordena por dirección de memoria y cambia entre procesos). Convertir a `String` antes (lección de Wizards, 2026-10-22).

### 5.3 Estado del mundo

Un único objeto `WorldState` (RefCounted) contiene **todo** lo que se guarda:

```
WorldState
  version: int                      # para migraciones del guardado
  seed: int · rng_state
  difficulty: "easy" | "normal" | "hard"            # 4.23, fija desde la partida nueva
  clock: { minute_of_day, day, season, year, speed, paused }
  characters: { chr_id → Character }  # incluye order_queue (pausa activa), schedule (rutina 4.10.8) y visual (paleta 4.10.9)
  families:   { fam_id → Family }     # incluye colors, ai_profile, objectives y goals cumplidos
  buildings:  { bld_id → Building }
  parcels:    { par_id → Parcel }     # [EA, reservado] estado de los campos de cultivo (4.22)
  market:     { demand: {item_id → float}, regulations: […], errands: [Errand] }   # recados en camino
  contracts:  { con_id → Contract }   # encargos del tablón y aceptados (4.5.6)
  loans:      { loan_id → Loan }      # deuda inicial desde H3; préstamos del Banquero en EA (4.22)
  ledger:     { entries: [LedgerEntry], summaries: {año → …}, alerts: [Alert] }   # 4.18
  rivalry:    { "fam_a|fam_b" → int } # 4.21
  microevents: { active: [Microevent], cooldowns: {…} }
  offices:    { office_id → Office }
  elections:  [Election] · trials: [Trial]
  relationships: { "chr_a|chr_b" → {relation, affinity} }
  emotions:   { chr_id → [EmotionState] }
  events_active: [ActiveEvent]
  chronicle:  [ChronicleEntry]      # diario de hechos, entrada del futuro cronista IA
  next_ids:   { chr: 41, bld: 12, … }
```

- Cada entidad es un diccionario tipado o un `RefCounted` con `to_dict()` / `from_dict()`.
- **Reservado desde H0 aunque se use en EA:** la entidad `Loan` (`{id, lender, borrower, principal, interest, due_day, installments, collateral, status}`) existe desde H3 por la deuda inicial y la reutiliza el Banquero; las recetas admiten `kind: "craft" | "service"` (el validador acepta `service` aunque no haya ninguna hasta H12); el estado de combate de un personaje (salud, herido hasta) tiene sitio en `Character` aunque se quede vacío en el MVP.
- **El oro solo cambia por `ledger.post()`** (4.18), igual que los objetos solo cambian por `Inventory`.
- **IDs:** `chr_0001`, `fam_0001`, `bld_0001`, `par_0001`, `off_alcalde`, `trial_0003`. Generados por `ids.gd`, nunca reutilizados.
- **Las vistas guardan solo IDs.** Un `BuildingView` sabe que pinta `bld_0003`; no tiene datos propios.

### 5.4 Reloj y paso de simulación

- **Paso fijo del sim = 1 minuto de juego.** A ×1, un día (1.440 min) dura 300 s → 4,8 pasos por segundo real. A ×4, ~19 pasos/s. Debe caber holgado (objetivo: < 2 ms por paso con 40 NPC y 30 edificios; medirlo con `tools/sim_bench.gd`).
- Los sistemas se ejecutan **en un orden fijo** cada paso (`clock → routines → production → customers → emotions → …`) y otros solo cuando cambia la hora, la fase o el día (salarios, demanda, nacimientos, mandatos, inspecciones).
- `TimeConfig` (en `data/time.json`): segundos reales por día (300), **días por estación (2)**, estaciones por año (4) y años de edad por año de calendario (**1**, D1(b)). La variante de desarrollo solo cambia los segundos por día (30); el calendario no cambia (4.1).
- El movimiento de personajes por la ciudad: el sim guarda posición en **casillas** y un destino; avanza por una ruta calculada sobre una rejilla de costes (calles 1, campo 10, edificios bloqueados). La vista interpola entre casillas para que se vea suave. **Sin `NavigationServer`** (no es determinista ni funciona sin escena). **Todos** se mueven así, también el personaje que el jugador mueve a mano: un clic se traduce en `MoveTo(actor, tile)` (D3).

### 5.5 Órdenes (commands)

Todo cambio de estado que inicia un actor entra como **orden**:

```
MoveTo(actor, tile) · EnterBuilding(actor, bld) · WorkAt(actor, bld, zone, recipe, mode) · MasterTouch(actor, bld, zone)
Buy(actor, stall, item, qty, deliver_to = null) · Sell(actor, stall, item, qty, quality)
AcceptContract(actor, contract) · DeliverContract(actor, contract) · RepayLoan(actor, loan, amount)
Transfer(actor, from_inv, to_inv, item, qty, quality)
Equip(actor, slot, item) · Hire(owner, bld, chr) · Fire(owner, chr) · SetRole(owner, chr, role)
QueueAdd(owner, bld, recipe, qty) · QueueLoop(owner, bld, on) · QueuePause(owner, bld, on)
StartUpgrade(owner, bld, upgrade) · Build(owner, parcel, type) · Demolish(owner, bld) · BuyBuilding(owner, bld)
Talk(actor, npc) · Gift(actor, npc, item) · Flatter/Insult/Threaten(actor, npc) · Propose(actor, npc)
SetHeir(owner, chr) · AssignBuilding(owner, chr, bld) · SetDirective(owner, chr, directives[]) · SetSchedule(owner, chr, schedule)
ResolveMicroevent(actor, microevent, choice) · EndDynasty(owner)   # EndDynasty, si se aprueba D19
RequestTitle(actor) · RunForOffice(actor, office, level) · CampaignAction(actor, kind, target)
Accuse(actor, target, crime) · WitnessAction(actor, witness, kind) · UseOfficePower(actor, power, args)

# [EA, reservadas desde ya: existen en el catálogo de órdenes y se rechazan con "no disponible" hasta H12]
Attack(actor, target) · Rob(actor, target) · GrantLoan(lender, borrower, terms)
# Los servicios del Erudito no necesitan orden nueva: son WorkAt sobre una receta de kind "service" con un cliente.
```

- Cada orden se **valida** en el sim (devuelve `ok` o un motivo legible para la UI) y produce **eventos** (`item_sold`, `worker_hired`…).
- La UI, los bots, la IA de familiares y las familias rivales **usan las mismas órdenes**. Así la IA se prueba igual que el jugador y no hay atajos que se salten reglas.
- Las órdenes se pueden **grabar** (con el paso en que se dieron) y **reproducir**: es la base de las repeticiones de bugs y de los bots.
- **Cola de órdenes por actor** (pausa activa, 4.1): cada personaje guarda sus órdenes pendientes en `order_queue`; se validan al ejecutarse, no al encolarse (el mundo puede haber cambiado). La rutina (4.10.8) solo genera órdenes cuando la cola está vacía.

### 5.6 Eventos y bus

- `sim/core/event_log.gd` acumula los eventos del paso. Al final del paso, `game/` los recibe por un único autoload `Events` y cada vista reacciona.
- Los eventos importantes se copian a la **crónica** (`chronicle`): nacimientos, bodas, muertes, herencias, títulos, cargos, juicios, compras de edificios, eventos globales, metas cumplidas y ataques de familias rivales. La puntuación de dinastía (4.17) se calcula solo a partir de la crónica.

### 5.7 Autoloads (como mucho 5)

| Autoload | Responsabilidad |
|---|---|
| `Game` | Tiene el `WorldState` y el runner del sim; avanza el reloj; carga y guarda. |
| `Data` | Carga y valida los catálogos de `data/` al arrancar. |
| `Events` | Reenvía a `game/` los eventos del sim. |
| `UI` | Gestor de paneles (pila, ESC, foco, modales, toasts). |
| `Log` | Logs por categoría, solo en debug: `[Sistema] acción: detalle (k=v)`. |

### 5.8 Guardado

- `meta/save.gd`: `WorldState.to_dict()` → JSON en `user://saves/slot_N.json`, escritura atómica (`.tmp` + renombrar). 3 ranuras (D6) + autoguardado al empezar cada día.
- `version` y **migraciones** encadenadas desde el primer día.
- Robustez (copiado de Wizards `stress_check`): ficheros truncados, vacíos, con basura o de otra versión no rompen el juego: avisan y ofrecen otra ranura.
- **Los escenarios de prueba son partidas guardadas** en `tests/data/saves/` y `data/scenarios/`: "forja recién abierta", "forja con 2 empleados", "familia con hijo de 15 años", "juicio a punto de vista"… Se cargan en el juego real con `-- --scenario=<id>` (corrige L7).

### 5.9 Inventario propio

```
Inventory
  owner_id
  constraint: { kind: "weight" | "stacks", limit: float }
  stacks: Array[{ item_id: StringName, quality: int (0 normal / 1 buena / 2 excelente), qty: int }]
  # API: can_add(item, q, n) · add · remove(item, q, n) -> bool · count(item, q = -1) · weight() · to_dict()
```

- Una pila = `(item_id, calidad)`. `remove` nunca deja negativos y devuelve si pudo. Vender o transferir *siempre* pasa por estas funciones.
- Las ranuras de equipo son un diccionario aparte en el personaje.

### 5.10 Presentación

- **Proyección isométrica en un solo sitio** (`game/iso.gd`): `tile → píxel` y su inversa para el ratón. Diamante de 64×32. `world = ((col - row) × 32, (col + row) × 16)`.
- Capas: suelo (`TileMapLayer`), objetos y personajes en un mismo nodo con **Y-sort**, luces, UI (`CanvasLayer` 10+).
- **Escenas visuales por id** (`game/visuals/<tipo>/<id>.tscn`; tipos `buildings`, `interiors`, `stations`, `props`, `characters`): los datos dicen qué hay (ids y cifras), la escena dice cómo se ve. Cada una lleva un `Marker2D` `Feet` (punto de apoyo) y otro `Top` (altura del letrero, la barra o el nombre y de la zona de clic), y el greybox dentro hasta que llega el arte. `game/visuals/visual_paths.gd` es el único sitio que convierte un id en ruta; si falta la escena sale `<tipo>/_generic.tscn`. Galería de revisión: `game/tools/gallery.tscn` (`-- --gallery`). Cómo se editan: `docs/protocolos/editar-a-mano.md`.
- Edificios: `buildings/<tipo>.tscn` colocada en el centro de su huella (la huella es del sim, `data/buildings`); los visuales de las mejoras exteriores, nodos ocultos en `Upgrades/`.
- Personajes: `characters/<rol>_<m|f>.tscn` (`artisan`, `worker`, `townsfolk`) con `AnimatedSprite2D` + `SpriteFrames` (`<id>_frames.tres`): tiras en 8 direcciones de PixelLab. La paleta de familia la aplica la vista.
- Interiores: `interiors/<tipo>.tscn` con el `Kit` (tamaño y puerta de la sala), un `Marker2D` por puesto (`Stations/<id del puesto>`, también los que añaden las mejoras, que solo salen cuando el edificio tiene ese puesto) y los visuales de las mejoras en `Upgrades/` (se encienden con `Upgrades.visuals`). La vista coloca a cada trabajador junto al marcador del puesto que el sim le ha asignado.
- **Audio**: por id, nunca por fichero. `data/audio.json` (bus, volumen, variación; música por fase; sonido por evento del sim), buses fijos en `default_bus_layout.tres` (Master, Music, Sfx, Ambient, Voice, Ui) y un nodo `AudioDirector` dentro de `app.tscn` (no gasta autoload). Sin fichero, silencio.
- **Ficheros**: todas las `.tscn`/`.tres` con uid (`tools/uids.py`); se mueven y renombran solo dentro de Godot.
- **UI:** escenas `.tscn`, `%UniqueName`, un `Theme` común (paleta de 9.6), textos desde `i18n/`. El gestor de paneles mantiene una pila: ESC cierra el de arriba; abrir uno principal cierra los demás principales; los modales bloquean el mundo.

### 5.11 Rendimiento

- Objetivo: 60 fps con 40 NPC visibles y 30 edificios en un Mac de 16 GB.
- NPC dentro de casa o en interiores no visibles: solo existen en el sim, sin nodo.
- Medir con `tools/sim_bench.gd` (sin ventana) y `tools/perf_check.gd` (con ventana, en cola `grimoire heavy`).
