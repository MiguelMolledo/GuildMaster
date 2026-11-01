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
game/     dibuja y traduce la entrada a órdenes: app.tscn, autoload/ (Log, Data, Events, Game), iso.gd, vistas, ui/
data/     contenido en JSON, una ficha por cosa; data/_templates/ y los ficheros `_*` no los carga el juego
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
- Contenido: `python3 tools/validate_content.py` (0 errores) al tocar `data/` o `i18n/`.
- Arte: `python3 tools/arte.py [--falta]` al tocar `assets/` o el inventario.
- Arranque sin ventana con cada escenario: `zsh tools/qa/boot_check.sh` (sale con 0 y sin `ERROR`).
- Coste del sim: `godot --headless --path . -s tools/sim_bench.gd` (diana < 2 ms por paso).
- Bots y dianas: `godot --headless --path . -s tools/sim_runner.gd -- --bots=idle --days=3 --seeds=5` (dianas en
  `data/targets.json`) al tocar reglas.
- Todo junto: `python3 tools/qa/run_all.py [--visual]`.
- Con ventana, la última comprobación y siempre por la cola: `grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot
  --audio-driver Dummy --path . -- --smoke --shots=2 --shot-every=3 [--scenario=<id>]` → `reports/shots/`. **Mira las capturas.**
- Opciones del juego (tras `--`): `--scenario=<id>`, `--seed=<n>`, `--dev-time` (días de 30 s), `--lang=es|en`, `--smoke`.

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
- Créditos (PixelLab, ElevenLabs, fal): solo con encargo; saldo antes y después en `assets/art/MANIFEST.md` /
  `assets/audio/MANIFEST.md`. `.env` (fuera de git) tiene `FAL_KEY`, `PIXELLAB_KEY` y `ELEVENLABS_API_KEY`: nunca se imprimen ni se suben.
- Copia jugable: el hook post-commit (`ln -sf ../../tools/git-hooks/post-commit .git/hooks/post-commit`) prepara
  `tmp/jugar/<commit>`; el owner juega con doble clic en `jugar.command`.
- No añadir features, refactors ni "mejoras" no pedidas. Respuestas cortas y en español.
