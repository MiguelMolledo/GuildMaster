# Editar a mano en Godot

Qué tocar para cambiar algo sin pedírselo a la IA, y qué pasar después. La idea: **los datos dicen qué hay** (ids y
cifras en `data/`), **las escenas de Godot dicen cómo se ve y cómo suena** (`game/visuals/`, `data/audio.json`), y los
ficheros de arte y audio **se llaman como su id**. El sim no se toca para nada de esto.

## Antes de empezar

- Abre el proyecto en Godot 4.7.2 (`/opt/homebrew/bin/godot --path . -e`). Para abrir los `.json` dentro de Godot:
  Editor → Editor Settings → Docks → FileSystem → TextFile Extensions, añade `json` (o usa Cursor).
- **Mueve y renombra solo en el panel FileSystem de Godot**, nunca en Finder: así Godot reescribe las referencias.
  Haz commit (o pide que se selle) antes de mover algo gordo. Si algo sale en rojo: *Fix Dependencies*.
- Los ficheros con nombre de id (arte, audio, escenas de `game/visuals/`) **no se renombran**: el id manda. Renombrar
  un id es un encargo (hay que tocar datos y fichero a la vez).
- Nombres en minúsculas y snake_case: `forge.png`, nunca `Forge.png` (el juego exportado distingue mayúsculas).
- Si una escena la está tocando un subgrim, no la tengas abierta. Si Godot dice que cambió en disco: recarga.

## Dónde está cada cosa

| Cosa | Dónde |
|---|---|
| Cifras de reglas (precios, salarios, tiempos, costes, dificultad) | `data/*.json`, `data/items/`, `data/recipes/`, `data/buildings/`, `data/upgrades/` |
| Cómo se ve un edificio por fuera | `game/visuals/buildings/<tipo>.tscn` |
| Interior de un edificio (sala, puestos, mejoras) | `game/visuals/interiors/<tipo>.tscn` |
| Cómo se ve un puesto (horno, yunque…) | `game/visuals/stations/<puesto>.tscn` (o el hijo de su `Marker2D` en el interior) |
| Árboles, bloques, puestos del mercado, tablón | `game/visuals/props/<tipo de casilla>.tscn`, `props/stall_<puesto>.tscn` |
| Manzanas del pueblo (casillas `#` que no son de ningún edificio) | Casas `props/lot_house_*.tscn` y patios `props/yard_*.tscn`; cuáles y en qué tamaño de solar, `filler` en `data/view.json` (sin ese bloque, vuelve el bloque greybox `props/building.tscn` por casilla) |
| Decoración del pueblo (barriles, bancos, carros, sacos…) | `game/visuals/towns/<mapa>.tscn` (hoy `town_e.tscn`): cada hijo es un prop colocado a mano |
| Personajes | `game/visuals/characters/<rol>_<m\|f>.tscn` + `<rol>_<m\|f>_frames.tres` (roles: `artisan`, `worker`, `townsfolk`) |
| Retrato de las personas (HUD, árbol genealógico) | `game/visuals/characters/portrait.tscn` (nodos Polygon2D: pelo, cabeza, cuerpo; los colores los pone el juego) |
| Tonos de pelo y piel (paleta de intercambio, H8) | `data/view.json` → `palette` (6 pelos, 4 pieles; cuántos, en `data/family.json` → `visual`) |
| Si falta la escena de un id | sale `game/visuals/<tipo>/_generic.tscn` (magenta: se nota) |
| Sprites, iconos | `assets/art/<tipo>/<id>.png` (contrato en `docs/ASSETS.md`) |
| Música y sonidos | `assets/audio/<music\|sfx\|ambient\|voice>/<id>.ogg\|wav`; volumen y bus en `data/audio.json` |
| Buses de audio | `default_bus_layout.tres` (panel Audio, abajo en Godot): Master, Music, Sfx, Ambient, Voice, Ui |
| Textos | `i18n/strings.csv` |
| Paneles de la UI | `game/ui/<panel>.tscn`; el aspecto común (marco de madera, botones, campos, barras, fuente de los botones) en `game/ui/greybox_theme.tres`, que llevan todos los paneles y la raíz del HUD: un panel nuevo bajo el HUD lo hereda sin tocarlo. Las piezas son `assets/art/ui/theme/*.png` (`tools/art/dibujar_ui.py`) |
| Tiempo que el objetivo muestra su «cómo» en el mapa | `hud.objective_hint_seconds` en `data/view.json` (luego se pliega; al pasar el ratón se despliega; dentro de un edificio siempre se ve) |
| Colores de las marcas (letreros, puertas, barras, día/noche) y zoom | `data/view.json` |
| Suelo del mapa | Textura por tipo de casilla en `assets/art/tiles/<tipo>.png` (`grass`, `street`, `plaza`, `dirt`…); sin PNG, el color de `data/tiles.json` (`color`) |
| Orilla del río, bordillo del puente | `ground_edges` en `data/view.json` (qué tipos de casilla bordea cada uno) y `assets/art/tiles/<tipo>_edge_<ne\|se\|sw\|nw>.png` |
| Árboles (y otros props con varios aspectos) | `props/tree.tscn`, `tree_round.tscn`, `tree_pine.tscn`; cuál sale en cada casilla, `prop_variants` en `data/view.json` |
| Campos (o cualquier suelo) que cambian con la estación | `seasonal_tiles.kinds` en `data/view.json` y `assets/art/tiles/<tipo>_<spring\|summer\|autumn\|winter>.png` |
| Borde del mapa (bosque o campo fuera de la rejilla) | `map_border` en `data/view.json`: ancho en casillas, suelo, qué tipos siguen hacia fuera (calles, río), fundido al fondo y árboles (`tiles: 0` lo quita) |
| Aspecto de las casas de vecinos | `building_variants.house` en `data/view.json` (escenas `buildings/house*.tscn`); cada casa toma uno por su casilla, siempre el mismo |
| Escala de los edificios (escala B) y cómo volver al sprite de antes | `assets/art/buildings/escala_b/` (sale de `tools/art/escala_b.py`); en cada escena, el nodo oculto `SpriteAntes` es el de antes (ver `docs/arte/reuso_guild.md`, «Escala B») |
| Edificio que se vuelve translúcido cuando tapa a la persona elegida | `see_through` en `data/view.json` (`alpha`, `min_height`; `alpha: 1` lo apaga) |
| Suelo y paredes de un interior | Grupo *Art* del nodo `Kit` de `game/visuals/interiors/<tipo>.tscn` (suelo, pared ne/nw, pared con puerta ne/nw); vacíos = colores greybox |
| Ayuda en pantalla (F1 / «?») | Textos `help.*` de `i18n/strings.csv` (una línea por clave; el orden, en `LINES` de `game/ui/help_panel.gd`); aspecto en `game/ui/help_panel.tscn` |
| Pista «cómo» del objetivo | `objective_how.<id del objetivo>` en `i18n/strings.csv` (`objective_how.free` cuando ya no quedan objetivos) |
| Encuadre del interior | `interior.zoom` (entero) y `interior.center_offset` (píxeles) en `data/view.json` |
| Burbujas sobre la cabeza (actividad social y emociones, H7) | `game/visuals/bubbles/<id>.tscn` (`rest`, `chat`, `shop`, `wave`, `think`, `dice`, `emotion_<estado>`); qué burbuja lleva cada actividad o emoción: `bubble` / `icon` en `data/town.json` |
| Bancos y mesa de dados de la plaza (H7) | `game/visuals/props/bench.tscn`, `dice_table.tscn`; dónde están: `social_points` de `data/maps/town_e.json` (lo genera `tools/maps/make_town_e.py`) |
| Oficios de los vecinos (H7) | `workplaces` de `data/maps/town_e.json` (casilla y orden de reparto); nombres `workplace.<id>` en `i18n/strings.csv` |
| Frases de los vecinos (H7) | Claves en `data/social_phrases.json` (por actividad, fase y profesión); textos `phrase.*` en `i18n/strings.csv` |
| Rutina, actividades, emociones, acciones, mostrador, microeventos y población (H7) | `data/town.json`; cada microevento en `data/microevents/<id>.json`; la palanca `microevent_chance` en `data/difficulty.json` |
| Estaciones en precios y producción, grupos de objetos (H13) | `data/seasons.json` (`goods`: grupo -> ids de objetos; `price` / `production`: estación -> grupo -> multiplicador) |
| Eventos globales (H13) | `data/events.json`: cada evento con `enabled`, `scope`, `trigger.chance` por estación, `duration`, `excludes`, `declarable` (Alcalde) y `effects`; textos `event.<id>`, `.desc`, `.short` en `i18n/strings.csv` |
| Ficha del vecino y tarjeta de microevento (H7) | `game/ui/npc_panel.tscn`, `game/ui/microevent_card.tscn` |
| Títulos: coste, reputación, requisitos y lo que abren (H9) | `data/titles/<id>.json` (uno por título; el orden por `rank` debe ser el de `titles` en `data/upgrade_rules.json`) |
| Reputación: clases, reglas (comercio justo, venta de calidad, salarios, acciones sobre vecinos), pasiva y ceremonia (H9) | `data/politics.json`; la regla mínima de la IA rival, `title_rule` en `data/ai_profiles/rival_smith.json` |
| Ayuntamiento en el mapa (H9) | Dónde: `town_hall` de `data/maps/town_e.json` (lo genera `tools/maps/make_town_e.py`: huella, letrero y casilla donde se pide); cómo se ve: `game/visuals/buildings/town_hall.tscn` (sprite de Guild Renew a escala 1,6) |
| Panel del Ayuntamiento, tarjeta de ceremonia y pestaña Reputación (H9) | `game/ui/town_hall_panel.tscn`, `game/ui/title_card.tscn` (segundos en pantalla: `title_card_seconds` de `data/view.json`), `game/ui/ledger_panel.*`; textos `ui.town_hall.*`, `ui.title_card.*`, `ui.ledger.rep.*`, `rep.reason.*` |
| Cargos: título mínimo, salario, mandato, asientos, orden en el organigrama, pasivos y poderes (H10) | `data/offices/<id>.json` (uno por cargo) |
| Gobierno al empezar, elecciones (niveles de campaña, pesos del voto, acciones), impuestos y regulación de precios (H10) | `data/politics.json` (`government`, `elections`, `taxes`, `regulation`); la regla mínima de la IA rival, `office_rule` en `data/ai_profiles/rival_smith.json` |
| Panel de cargos (organigrama, campaña, poderes) y tarjeta de la votación (H10) | `game/ui/offices_panel.tscn`, `game/ui/office_card.tscn` (segundos en pantalla: `office_card_seconds` de `data/view.json`); textos `office.*`, `power.*`, `campaign.*`, `ui.offices.*`, `ui.office_card.*` |
| Tribunal: cargos y su gravedad, condenas, hechos, testigos, vista oral, acusar, Juez (H11) | `data/justice.json`; la regla mínima de la IA rival, `accuse_rule` e `initial_attitudes` en `data/ai_profiles/rival_smith.json` |
| Panel del juicio y carta «Te acusan» / veredicto (H11) | `game/ui/trial_panel.tscn` (la sección morada es el estilo del tribunal), `game/ui/trial_card.tscn` (segundos: `trial_card_seconds` de `data/view.json`); textos `charge.*`, `severity.*`, `sentence.*`, `ui.trial.*`, `ui.trial_card.*` |
| IA familiar: directivas (orden, cuáles están listas), necesidades, moral, comercio y avisos (H14) | `data/family.json` (`directives`, `needs`, `morale`, `trade`, `leisure`, `kin_notices`) |
| Panel de IA del familiar (H14) | `game/ui/kin_ai_panel.tscn` (botón «IA» de la ficha y del árbol); textos `directive.*`, `need.*`, `ui.kin_ai.*` |

Cada escena visual tiene dos `Marker2D`: **`Feet`** (el punto que se apoya en el suelo: centro de la casilla, centro
de la huella o los pies) y **`Top`** (lo alto que es: ahí van el letrero, la barra o el nombre, y hasta ahí llega la
zona de clic). Mientras no hay arte, dentro hay un nodo **`Greybox`** con el dibujo provisional, editable en el Inspector.

## Quiero cambiar…

### Un sprite (edificio, puesto, árbol…)
1. Copia el PNG a `assets/art/<tipo>/<id>.png` (arrástralo al panel FileSystem de Godot, a su carpeta).
2. Abre su escena, p. ej. `game/visuals/buildings/forge.tscn`.
3. Añade un `Sprite2D` (clic derecho en la raíz → Add Child Node), arrastra el PNG a su *Texture* y quita
   *Centered* si te es más cómodo. Ajusta *Offset* hasta que la base del dibujo toque el `Feet`.
4. Borra (u oculta) el nodo `Greybox`. Mueve `Top` a lo alto del dibujo (letrero y clic).
5. Si es el mismo tamaño que el anterior y solo cambia el dibujo: basta con sobrescribir el PNG con el mismo nombre.

### La decoración del pueblo (barriles, bancos, carros…)
1. Abre `game/visuals/towns/town_e.tscn`: en el editor se dibuja el mapa debajo (colores de `data/tiles.json`) para
   ver dónde cae cada cosa (`show_map` en el Inspector lo apaga).
2. Para añadir una pieza, arrastra su escena (`game/visuals/props/barrel.tscn`, `bench`, `cart`, `crate`,
   `grain_sack`, `well`…) dentro de la raíz y muévela. Su `Feet` es el punto que toca el suelo.
3. Es solo decoración: no corta el paso. Ponla en hierba o junto a las paredes, no en mitad de la calle.

### Las manzanas de casas y patios
Las casillas `#` libres del mapa se rellenan solas: en cada hueco de 3×4, 4×3 o 3×3 va una casa (`props/lot_house_*`,
la mitad en espejo) y en lo que sobra, patios bajos (`props/yard_*`) que no tapan la base del edificio de detrás: cada manzana
toma un tema de `yard_themes` (huerto, o patio con barriles, sacos y carro). Lo que va en cada casilla depende solo de la casilla (el pueblo sale igual en cada
partida). Cambia el aspecto de una casa o un patio en su escena; qué escenas se usan y con qué peso (repetir un id),
en `filler` de `data/view.json`.

### Una animación de personaje
1. Abre `game/visuals/characters/<id>_frames.tres` (doble clic): se abre el panel SpriteFrames.
2. Las animaciones ya están creadas (`idle`, `walk`, `work`…). Elige una y añade fotogramas desde la tira PNG
   (*Add frames from sprite sheet*); ajusta FPS y bucle.
3. En `game/visuals/characters/<id>.tscn`, oculta o borra el `Greybox`. Los pies del dibujo, sobre `Feet`.
4. Hoy los fotogramas vienen de Guild Renew (`tools/art/personajes_guild.py strips` y `frames`): animaciones
   `<anim>_<dir>` (`idle`, `walk`, `work`, `forge`, `death`; direcciones `s se e ne n nw w sw`). El pelo, la piel y la
   ropa van codificados en el PNG y los pinta `identity_swap.gdshader` con los colores de la persona y su familia.
   Para volver al greybox: oculta `Sprite` y muestra `Greybox`.

### Una música
1. Pon el fichero en `assets/audio/music/<id>.ogg` con el id de `data/audio.json` (hoy: `music_city_day`, `music_night`).
2. En Godot, selecciónalo → panel Import → marca *Loop* → *Reimport*.
3. ¿Fuerte o flojo? `volume_db` de ese id en `data/audio.json`. ¿Otra música para una fase del día? `phase_music`.
   Para toda la música a la vez: el bus `Music` en el panel Audio.

### Un efecto de sonido
1. `assets/audio/sfx/<id>.ogg` o `.wav` (la lista de ids, en la sección `sfx` de `data/audio.json`).
2. Variantes para que no suene siempre igual: `<id>_01.wav`, `<id>_02.wav`… (sin el fichero sin número). Sale una al azar.
3. Volumen y variación de tono (`pitch_jitter`, 0–0,5) en `data/audio.json`. Qué evento lo dispara: `events`.
   Los avisos (`notice_added`) suenan por su clave (`"notice.objective_done": "sfx_objective_done"`) o, si no está,
   por su severidad (`"notice_added.warning"`, `"notice_added.urgent"`); así un aviso nunca suena dos veces.
   Un evento puede sonar distinto según su puesto, fase, categoría o puesto del mercado: `"work_started.furnace"`,
   `"phase_changed.dawn"`, `"gold_changed.counter_sales"` ganan al tipo solo. Una entrada puede ser una lista
   (`["sfx_coins", "voice_market_deal"]`). Los eventos de `selected_only` (los pasos) solo suenan para la persona
   seleccionada. `cooldown_s` en un id: segundos reales antes de poder volver a sonar (las voces, 20 s).

### Los sonidos de la interfaz
Sección `ui` de `data/audio.json`: `button` (todos los botones, sin tocar los paneles), `pause` / `resume`,
`panel_open` / `panel_close` para los paneles de `panels` (nombres de escena de `game/ui/`), y `panel_open_by`: un
sonido más al abrir un panel concreto (el vendedor en `market_panel`, el pregonero en `board_panel`), y
`screen_music`: la música mientras se ve una pantalla (el tema de título en `new_game_screen`). Para que un
panel nuevo suene al abrirse, añade su nombre a `panels`. Un sonido de UI que no esté aquí es un encargo.

### Un ambiente (plaza, noche, interior)
1. `assets/audio/ambient/<id>.ogg` con el id de la sección `ambient` de `data/audio.json`; en el panel Import, *Loop*.
2. Qué ambiente suena en el pueblo en cada fase del día: `phase_ambient`. Dentro de un edificio, por su tipo:
   `interior_ambient` (`"forge": "ambient_forge"`; un tipo sin entrada queda en silencio dentro).
3. Volumen: `volume_db` del id, o el bus `Ambient` para todos.

### Regenerar audio con ElevenLabs (encargo con créditos)
`python3 tools/audio/eleven.py balance` (saldo) y `sfx` / `music` / `voice` (crudo en `audio-generations/`, con coste
registrado); `python3 tools/audio/master.py sfx|loop` lo deja en `assets/audio/` recortado, normalizado y en bucle.
Plan, tarifas y prompts: `docs/audio/plan.md`; gasto: `assets/audio/MANIFEST.md`.

### Un texto
`i18n/strings.csv` (columnas `keys,en,es`). Después, abre el editor o pasa `godot --headless --path . --import`.

### Una cifra (precio, salario, duración, coste)
Su ficha en `data/` (objetos `data/items/`, recetas `data/recipes/`, edificios `data/buildings/`, mejoras
`data/upgrades/`, el resto en `data/*.json`). Si está marcada [balance], pasa también los bots de balance.

### Un color de la UI
`game/ui/greybox_theme.tres` (editor de temas) para todos los paneles; un panel concreto, su `.tscn`. Las marcas del
mapa (letreros, puertas, insignias, barras del interior, día/noche) en `data/view.json`. El color provisional de un
edificio o un puesto, en el `Greybox` de su escena.

### Un interior por datos (la forja; 04g §4.6.5.2)
Los interiores con fichero en `data/interiors/<tipo>.json` (forja, armería, carpintería, cantería, sastrería, casa y taberna) no
tienen escena: los monta `game/interior/interior_builder.gd`.
1. Edita el JSON: salas (`rooms`), puertas, desniveles, escaleras, puestos (`stations`: casilla, pieza de
   `data/props/interior.json` o la escena del puesto, y `stand`, donde se pone quien trabaja), sitios de clientes,
   sitios de espera, atrezo (`props`), reglas (`rules`) y las piezas de cada mejora (`upgrades`, por su nodo).
2. `python3 tools/interiors/interiores.py reglas <tipo>` (coloca lo de las reglas), `python3 tools/interiors/remap_props.py
   <tipo>` (sus piezas con la paleta de sus fondos) y `validar <tipo>` (0 errores).
3. `python3 tools/interiors/interiores.py vista <tipo> --marcas` para verlo sin abrir el juego.
4. Si cambian las salas o las paredes, el fondo pintado ya no encaja: `python3 tools/art/fal_salas.py gen|ver|proc`.

### La posición de un puesto en un interior hecho a mano
1. Abre `game/visuals/interiors/<tipo>.tscn` (hoy solo `_generic.tscn`: los demás son por datos).
2. Mueve el `Marker2D` del puesto (`Stations/anvil`…): su nombre es el id del puesto. Déjalo en el centro de una
   casilla (la vista lo redondea a la casilla para los clics).
3. Los puestos que añaden las mejoras (`anvil_2`, `furnace_2`) ya tienen su marcador: solo salen cuando la mejora está hecha.
4. Tamaño de la sala y puerta: el nodo `Kit` (*size*, *door*, colores, alto de pared). Su grupo *Art* lleva las
   texturas del suelo y de las paredes; si las vacías, vuelven los colores.
5. Sala pintada (la forja, `docs/arte/interiores.md`): *backdrop* del `Kit` es una sola imagen del suelo y las paredes
   del fondo, con *backdrop_offset* = su esquina de arriba a la izquierda desde el centro de la casilla (0, 0). Si la
   vacías, vuelven las casillas y tramos de pared. Si cambias *size*, *door* o el alto de pared, el fondo ya no encaja:
   hay que pintarlo otra vez (`tools/art/fal_interiores.py fondo` y `proc`).
6. Atrezo de pie (carbonera, muela…): un Sprite2D bajo `Props`, con su posición en los pies (el centro de su casilla)
   y su *offset* para que la base caiga ahí. Se ordena con la gente como los puestos.

### El visual de una mejora
Bajo `Upgrades` del interior (`interiors/forge.tscn`) o del exterior (`buildings/forge.tscn`) hay un nodo oculto por
cada `visual.interior_node` / `visual.exterior_overlay` de `data/upgrades/`. Hazlo visible en el editor para verlo,
cámbialo o ponle su sprite, y vuelve a ocultarlo: el juego lo enciende cuando la mejora termina.
En las ramas de `upgrades.latest_only_branches` de `data/view.json` (Producción y Fachada) solo se ve el nivel más alto
terminado; en el resto, todos.

### El andamio de una obra
El nodo oculto `Works` de `game/visuals/buildings/<tipo>.tscn` (postes y tablones greybox) sale en el mapa mientras el
edificio está en obras. Cámbialo igual que un visual de mejora. Los colores de la barra de la obra sobre el edificio y
de las casillas del panel de mejoras: `upgrades` en `data/view.json`.

## Después de tocar algo

| Has tocado | Pasa |
|---|---|
| Una escena o arte | Abre `game/tools/gallery.tscn` y pulsa F6 (o `/opt/homebrew/bin/godot --path . -- --gallery`): todo a escala con un caminante de 48 px |
| `data/` o `i18n/` | `python3 tools/validate_content.py` (0 errores: también vigila rutas, mayúsculas, escenas, marcadores, audio y uid) |
| Cifras [balance] | Los bots de balance (comando en `CLAUDE.md`, unos 3 min) |
| `assets/` o el inventario | `python3 tools/arte.py` y sube el estado en `assets/inventario.json` |
| Escenas creadas fuera de Godot | `python3 tools/uids.py --fix` y `godot --headless --path . --import` |
| Antes de sellar | `python3 tools/qa/run_all.py` y una captura con ventana (`--smoke` por `grimoire heavy`) |
