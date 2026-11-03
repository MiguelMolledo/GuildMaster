# GuildMaster — reglas del proyecto

Simulador de vida y dinastía medieval en pixel art isométrico 2:1, para PC (Steam Early Access), hecho con Godot **4.7.2**
y GDScript. Reconstrucción desde cero de Guild Renew (repo `guild`) con la arquitectura y el proceso de Wizards Broke It.
Repo: `git@github.com:MiguelMolledo/GuildMaster.git`.

## El diseño manda
- El diseño vive en `docs/gdd/` (índice en `docs/gdd/README.md`). Antes de escribir código lee 02 (lecciones), 05
  (arquitectura) y esta página; para cada hito, su parte de 04 y su fila de 10.
- Si lo jugado choca con el diseño, gana lo jugado: se cambia el diseño en el mismo commit y se apunta en `docs/decisiones.json`.
- Lo que no esté definido se pregunta: no se inventan mecánicas. Lo marcado [balance] se ajusta con bots, no a ojo.
- Lo marcado [POST-MVP] / [POST-EA] no se implementa hasta que se pida, pero la arquitectura no lo impide.
- Ids en inglés y snake_case. Textos del juego en ES y EN vía `i18n/strings.csv`. Documentos internos en español.

## Arquitectura (no romperla)
```
sim/      todas las reglas: RefCounted puro, sin nodos, determinista. Paso fijo = 1 minuto de juego.
  core/   world_state · clock · catalog · ids · orders · sim
  econ/   inventory (y market, production... según hitos)
  meta/   save_file (versión + migraciones) · new_game · chronicle
  bots/   bots que juegan dando órdenes
game/     dibuja y traduce la entrada a órdenes: app.tscn, autoload/ (Log, Data, Events, Game), iso.gd, vistas, ui/,
          visuals/ (una escena por cosa visible + visual_paths.gd), audio/ (AudioDirector), tools/ (galería)
data/     contenido en JSON, una ficha por cosa (ids y cifras, nunca rutas); data/_templates/ y `_*` no se cargan
assets/   art/ (PixelLab) · audio/ · concept/ (fal) · inventario.json (estado de cada asset)
i18n/     strings.csv (keys,en,es)
tools/    validador, new_content, arte, cuaderno, sim_runner, sim_bench, qa/, art/, audio/
tests/    pruebas de reglas sin ventana (tests/test_*.gd)
docs/     gdd/ · hitos.json · decisiones.json · novedades.json · ASSETS.md · style/biblia.md · protocolos/ · paginas.json
```
1. **`sim/` contiene todas las reglas** y es determinista: misma partida + misma semilla + mismas órdenes = mismo
   resultado. El azar sale de `state.rng`, nunca de `randf()` global ni de `Time`. Sin nodos, sin física, sin NavigationServer.
2. **`game/` solo dibuja** y da órdenes. Las vistas leen el estado y escuchan `Events`; nunca calculan reglas.
3. **Todo cambio de estado entra como orden** (`Orders.apply`): `{"type", "actor", ...}`. La UI, los bots, la IA de
   familiares y las familias rivales dan las mismas órdenes. No hay "el jugador" global.
4. **Las cifras viven en `data/`**, nunca en el código. Las duraciones de diseño van en unidades de juego (horas, días).
5. **Un interior es una vista.** La producción corre en el sim se mire o no (lección L1, BUG-024).
6. **Guardar/cargar funciona siempre**: todo estado nuevo vive en `WorldState`, solo con datos JSON e ids (nunca nodos),
   y tiene su prueba de ida y vuelta. Cambiar el formato = subir `WorldState.VERSION` + paso en `SaveFile._step()` + prueba.
   Tras cargar, los números enteros vuelven como `int`: lee el estado con `int()` / `float()`.
7. **Como mucho 5 autoloads** (hoy: Log, Data, Events, Game; falta UI). Los sistemas no guardan referencias unos a otros.
8. Nunca se ordenan ni comparan con `<` dos `StringName`: pásalas a `String` antes (lección de Wizards).
9. **`data/` guarda ids y cifras, nunca rutas a ficheros** (el validador lo rechaza). Cada cosa visible es una escena
   `game/visuals/<tipo>/<id>.tscn` (`buildings`, `interiors`, `stations`, `props`, `characters`) con `Marker2D` `Feet`
   y `Top` y su greybox dentro (nodos editables, no `_draw` en la vista); el id → ruta solo en
   `game/visuals/visual_paths.gd`. El dibujo por código queda para lo dinámico (barras, marcas, selección, día/noche).
   Arte y audio se llaman como su id, en minúsculas. Audio por id (`data/audio.json`, buses fijos de
   `default_bus_layout.tres`, `AudioDirector` en `app.tscn`). Dónde está cada cosa: `docs/protocolos/editar-a-mano.md`.

## Ficheros y edición a mano (el owner edita en Godot)
- Mover o renombrar ficheros **solo dentro de Godot** (panel FileSystem), nunca en Finder ni con `mv`/`git mv`: Godot
  reescribe las referencias. Los `.import` y `.uid` van a git. Un fichero con nombre de id no se renombra (el id manda).
- **Toda `.tscn`/`.tres` lleva uid** en la cabecera y en cada `ext_resource` (el del `.uid` del script, el `.import`
  del asset o la cabecera de la escena). Si escribes escenas a mano: `godot --headless --path . --import` y luego
  `python3 tools/uids.py --fix` (el validador falla si falta alguno).
- Escenas nuevas de `game/visuals/` se copian de las existentes (Feet, Top, Greybox) y se revisan en la galería.
- Si el owner tiene abierta en Godot una escena que vas a tocar, avísale: al guardar pisaría tu cambio.

## Godot
- Binario: `/opt/homebrew/bin/godot` (4.7.2). El alias `godot` del shell puede apuntar a otro: usa la ruta completa.
- Solo sintaxis de Godot 4, tipado estático siempre. Sin ternario `?:` (usa `a if c else b`).
- Escenas 2D extienden `Node2D`. UI en `.tscn` con `%UniqueName`, nunca rutas `$A/B/C`.
- Viewport 960×540 escalado ×2 entero (D2), filtro Nearest.
- Nunca `get_image()` sobre texturas en el juego (en el exportado puede no dar nada).
- Logs solo en debug: `Log.info("Sistema", "acción: detalle (k=v)")`.
- Clases nuevas con `class_name` o assets nuevos sin abrir el editor: `godot --headless --path . --import`.
- Exportar (cuando toque): el filtro de exportación debe incluir `*.json` (data/ no son recursos).

## Rituales (antes de dar algo por hecho)
- Reglas: `/opt/homebrew/bin/godot --headless --path . -s tests/run_tests.gd [-- --only=<texto>]`. Cada `tests/test_*.gd`
  hace `extends "res://tests/test_case.gd"`; cualquier `ERROR` o `SCRIPT ERROR` durante una prueba la hace fallar.
- Contenido: `python3 tools/validate_content.py` (0 errores) al tocar `data/`, `i18n/`, `game/visuals/` o escenas
  (también comprueba rutas en data/, mayúsculas, escenas y marcadores por id, audio y uid).
- Galería de visuales (al tocar `game/visuals/` o arte): `godot --path . -- --gallery`; captura con
  `grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot --audio-driver Dummy --always-on-top --path . -- --gallery --smoke`.
- Arte: `python3 tools/arte.py [--falta]` al tocar `assets/` o el inventario.
- Arranque sin ventana con cada escenario: `zsh tools/qa/boot_check.sh` (sale con 0 y sin `ERROR`).
- Coste del sim: `godot --headless --path . -s tools/sim_bench.gd` (diana < 2 ms por paso).
- Bots y dianas: `godot --headless --path . -s tools/sim_runner.gd -- --bots=idle --days=3 --seeds=5` (dianas en
  `data/targets.json`) al tocar reglas. Partida nueva real: `--start=artisan_blacksmith [--difficulty=easy,normal,hard]`.
- Balance del inicio (H3, ~3 min, al tocar cifras [balance] de economía): `godot --headless --path . -s tools/sim_runner.gd
  -- --start=artisan_blacksmith --difficulty=easy,normal,hard --bots=artisan_novice --days=10 --seeds=30` (dianas de
  Normal y orden Fácil > Normal > Difícil en oro neto/día; informes en `reports/sim/`).
- Balance de la forja con empleados (H5, ~15 min por dificultad; al tocar cifras [balance] de economía, empleados o
  mejoras): `godot --headless --path . -s tools/sim_runner.gd -- --start=artisan_blacksmith --difficulty=easy,normal,hard
  --bots=artisan_expert --days=24 --seeds=30` (dianas `goldflow.staff` de días 9-24 y `artisan_expert`). Lo que aportan
  los empleados (mismas semillas): `--bots=artisan_expert_0,artisan_expert_1,artisan_expert_2`. Pruebas de
  cifras sin tocar `data/`: `--set=<tabla>.<id>.<clave>=<json>` (p. ej. `--set=market.demand.recover_per_day=0.3`) y
  `--tag=<nombre>` → `reports/sim/trial_<nombre>_*.json`.
- Títulos (H9, largos, al tocar reputación, títulos o la IA rival): `godot --headless --path . -s tools/sim_runner.gd --
  --start=artisan_blacksmith --bots=expert_titles --days=96 --seeds=10` (Patricio, ~17 min) y `--bots=idle_titles
  --days=80 --seeds=10` (la familia IA sube de título, ~9 min). Captura: `--smoke-script=titulos`.
- Cargos (H10, al tocar cargos, elecciones o la IA rival): `godot --headless --path . -s tools/sim_runner.gd --
  --start=artisan_blacksmith --bots=politician --days=40 --seeds=10` (gana un cargo menor, ~6 min); `idle_titles` mide
  además que el rival se presenta. Captura: `--smoke-script=cargos`.
- Tribunal (H11, al tocar justicia, inspecciones o la IA rival): `godot --headless --path . -s tools/sim_runner.gd --
  --start=artisan_blacksmith --bots=crook --days=40 --seeds=10` (acaba en juicio, ~6 min). Captura:
  `--smoke-script=tribunal`. Escenarios: `accused_player`, `trial_hearing`, `rival_accused`, `founder_old`.
- IA familiar (H14, al tocar directivas, necesidades o la rutina): `godot --headless --path . -s tools/sim_runner.gd --
  --scenario=kin_trader --bots=kin_trader --days=2 --seeds=10` (un familiar con Comerciar aprovisiona la forja; en
  `run_all`, paso kin). Captura: `--smoke-script=ia_familiar`.
- Oficios del Artesano (H12, al tocar recetas, talleres o los inicios): `godot --headless --path . -s tools/sim_runner.gd --
  --start=artisan_<carpenter|mason|tailor> --bots=<oficio>_novice --difficulty=easy,normal,hard --days=10 --seeds=30`
  (diana `goldflow.start_<oficio>`, la del inicio de la forja; en `run_all`, pasos carpenter, mason y tailor).
- Todo junto: `python3 tools/qa/run_all.py [--visual]`.
- Con ventana, la última comprobación y siempre por la cola: `grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot
  --audio-driver Dummy --always-on-top --path . -- --smoke --shots=2 --shot-every=3 [--scenario=<id>]` → `reports/shots/`. **Mira las capturas.**
  `--always-on-top` porque macOS deja de dibujar una ventana tapada y la captura repite un fotograma viejo. Guion de la forja:
  `--smoke-script=forja`.
- Opciones del juego (tras `--`): `--scenario=<id>` (por defecto `town_e_start`), `--seed=<n>`, `--dev-time` (días de 30 s),
  `--lang=es|en`, `--at=HH:MM`, `--smoke`, `--smoke-script=<id>`, `--gallery`.
- Contratos entre zonas de cada hito: `docs/contratos/` (los subgrims trabajan contra ellos).

## Registro del proyecto (dónde se apunta cada cosa)
- `docs/hitos.json`: estado de cada hito y de cada criterio (pendiente / en_curso / hecho, con prueba y fecha).
- `docs/novedades.json`: cada función terminada añade una entrada **al principio** (fecha, titulo, que, como_probar,
  capturas reales en `docs/novedades/`). Sin entrada con capturas, no está entregada.
- `docs/decisiones.json`: tomadas, pendientes y próximos pasos. Cualquier cambio de reglas, datos o controles lo actualiza.
- `assets/inventario.json` + `docs/ASSETS.md`: cada asset con su estado (falta → greybox → concepto → sprite → animado → final).
- `docs/style/biblia.md`: perfil estético. Todo asset nuevo se pide y se revisa contra ella.
- Después de tocar cualquiera de ellos: `python3 tools/cuaderno.py` (página «GuildMaster · cuaderno» en Grimoire).

## Forma de trabajo
- Un hito a la vez (`docs/gdd/10_hitos.md`); no se empieza el siguiente sin cerrar los criterios del anterior.
- Manager + como mucho 4 subgrims de Grimoire (`grimoire cmd orchestrate.delegate`), cada uno en su zona de ficheros;
  los subgrims no hacen commit: ponen sus pruebas en `tests/test_<zona>_*.gd` y su entrada en `reports/novedades/<zona>.json`.
- Procesos con ventana, exportaciones o navegador: `grimoire heavy`. Nunca `pkill -f` con patrones generales.
- Arte con PixelLab: plugin **PixelLab Pip** (`/pixellab-pip`, instalado en `.claude/settings.json`), con el estilo
  `pixellab-pip-style.json` y el paso a paso de `docs/protocolos/generar-arte-pixellab.md`.
- Créditos (PixelLab, ElevenLabs, fal): solo con encargo; saldo antes y después en `assets/art/MANIFEST.md` /
  `assets/audio/MANIFEST.md`. `.env` (fuera de git) tiene `FAL_KEY`, `PIXELLAB_KEY` y `ELEVENLABS_API_KEY`: nunca se imprimen ni se suben.
- Copia jugable: el hook post-commit (`ln -sf ../../tools/git-hooks/post-commit .git/hooks/post-commit`) prepara
  `tmp/jugar/<commit>`; el owner juega con doble clic en `jugar.command`.
- No añadir features, refactors ni "mejoras" no pedidas. Respuestas cortas y en español.
