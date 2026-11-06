# 05 · Tutorial interactivo

> Dueño: tutorial · Estado: borrador para revisar · Fecha: 2026-11-03
> Estilo: [00_lenguaje_visual.md](00_lenguaje_visual.md) · Zonas y teclas: [01_hud.md](01_hud.md) · Globos de primera
> vez pedidos en cada documento de [mecanicas/](mecanicas/) (punto «Primera vez»).
> Datos: `data/tutorial.json` y `data/tutorial/<capítulo>.json` · Motor: `game/ui/tutorial/` · Textos: `tutorial.*` en
> `i18n/strings.csv`.

## 1. Para qué sirve

Responde a «¿y ahora qué toco?» sin salir del juego. El juego explica cada mecánica **sobre la pantalla real**:
oscurece todo menos lo que hay que tocar, lo enmarca en oro, dice en una frase qué hacer y espera a que lo hagas.

Dos modos:

- **Capítulos guiados.** Una lección corta por mecánica, de 4 a 12 pasos. El primero sale solo en una partida nueva
  con «Con tutorial» marcada; todos se pueden repetir desde la ayuda (F1). Al acabar uno se ofrece el siguiente.
- **Pistas de primera vez.** La primera vez que abres un panel o pasa algo (primer evento global, primera boda,
  primer juicio…), un globo corto junto a lo que importa, con «Entendido» y «No volver a mostrar». Sin velo: no
  interrumpe. Son los «globos de primera vez» que dejaron pendientes los documentos de mecánicas.

El tutorial **no cambia ninguna regla**: no da órdenes al sim, no regala oro ni acelera la producción. Escucha los
eventos del sim y de la interfaz, lee el estado y pinta. Lo único que toca de la sesión es la pausa (el primer paso
del capítulo 1 la pone para que se lea; el jugador la quita él mismo en el paso «resume»).

## 2. Cómo se abre y se cierra

| Desde | Qué pasa |
|---|---|
| Partida nueva, casilla **«Con tutorial»** | Marcada la primera vez que se juega (`tutorial/asked` en los ajustes). Al empezar, el capítulo 1. |
| Ayuda (F1), bloque **«Tutorial»** | Un botón por capítulo, con «hecho» en los vistos. Clic: se cierra la ayuda y empieza ese capítulo. Los de oficio solo se pueden hacer en una partida de ese oficio (motivo a la vista). |
| Fin de capítulo | Tarjeta «Capítulo terminado» con «Siguiente capítulo» y «Cerrar». |
| Opciones · Juego | «Pistas de primera vez» (apaga o enciende todas) y «Tutorial guiado» (bloquear clics fuera del foco). |

Teclas mientras hay un paso a la vista (acciones del mapa de entrada, `TutorialKeys`):

| Tecla | Hace |
|---|---|
| Tab | Saltar el paso (o «Siguiente» en los que solo explican; «Entendido» en una pista) |
| Mayús+Tab | Saltar el capítulo |
| Retroceso | Repetir el paso: vuelve a enseñar la tarjeta, recoloca la cámara y reinicia el latido |
| Esc, Espacio | Lo de siempre (cerrar lo de arriba, menú de pausa; pausa). El tutorial nunca se los queda |

El tutorial se esconde mientras hay un menú (título, pausa, guardar, opciones…) y se cierra al cargar otra partida.

## 3. Jerarquía de información

1. **Lo resaltado**: el rectángulo del objetivo sin velo, con marco dorado que late y una flecha que lo señala.
2. **La tarjeta**: una frase en segunda persona, qué hacer y por qué (≤ 2 líneas de 236 px casi siempre). Encima,
   el capítulo en la cinta y, pequeño, «Paso 3 de 12» en la tarjeta. Debajo, «Siguiente» si el paso solo explica, o «Hazlo para seguir» si espera tu acción.
3. **A demanda**: las teclas del tutorial en la línea de pie de la tarjeta.

## 4. El modelo: capítulos, pasos y pistas

Todo es dato. Añadir, quitar o reordenar pasos o capítulos se hace en JSON y en `i18n/strings.csv`; el validador
(`tools/validate_content.py`, `check_tutorial`) dice si algo no encaja.

### 4.1 Ficheros

- `data/tutorial.json`: `chapters` (el orden), `openers` (qué abre qué, §4.5), `panels` (los paneles que se vigilan),
  `hints` (las pistas de primera vez) y `look` (velo, marco, flecha, tarjeta: cifras de presentación, no reglas).
- `data/tutorial/<id>.json`: un capítulo. `id`, `name_key`, `desc_key`, `requires` (opcional: condición para poder
  hacerlo, p. ej. el oficio), `test` (con qué partida lo prueba el smoke de datos: `start` o `scenario`) y `steps`.

### 4.2 Un paso

```json
{"id": "ingot", "text": "tutorial.produce.ingot",
 "target": {"ui": "Row_forge_ingot", "in": "StationMenu"},
 "when": null,
 "done": {"ui": "order_given", "match": {"type": "work_at", "recipe": "forge_ingot"}},
 "advance": "action"}
```

| Campo | Qué es |
|---|---|
| `id` | Único en el capítulo, snake_case |
| `text` | Clave de i18n. Puede llevar `{head}` (el cabeza de tu familia), `{active}` (el personaje activo), `{workshop}` (tu tipo de taller, en minúscula), `{town}` (el pueblo), `{family}` |
| `target` | Qué se resalta (§4.4). Sin él, la tarjeta sale en el centro de la vista libre y no hay velo |
| `when` | **Disparador** (§4.3): el paso no sale hasta que pasa. Sin él, sale al acabar el anterior |
| `done` | **Acción esperada**: un disparador o una lista (vale cualquiera). Obligatorio con `advance: "action"` |
| `advance` | `"action"`: avanza solo cuando haces la acción · `"next"`: solo explica, avanza con «Siguiente» |
| `if` | Condición (§4.3, `state`): si no se cumple al llegar, el paso se salta (p. ej. el botón del juicio sin juicio) |
| `pause` | `true`: al salir el paso se pausa el juego (solo el primero del capítulo 1) |

### 4.3 Disparadores

Tres formas, las mismas para `when`, `done`, `if` y las pistas:

| Forma | Ejemplo | Cuándo se cumple |
|---|---|---|
| Evento del sim | `{"sim": "work_done", "match": {"item": "iron_ingot"}, "count": 2}` | Llega por `Events.sim_event` un evento de ese tipo que casa con `match` (mismos operadores que los objetivos: igualdad, `gte`, `lte`, `ne`). Por defecto solo los de tu familia (por `family` o por el `actor`); `"anyone": true` quita el filtro. `count`: cuántos desde que salió el paso |
| Evento de la UI | `{"ui": "panel_opened", "match": {"panel": "LedgerPanel"}}` | Lo emite el propio motor al ver el cambio (lista abajo) |
| Condición sobre el estado | `{"state": "storage_has", "item": "iron_ingot", "qty": 2}` | Se mira cada fotograma: vale aunque ya se cumpliera antes de salir el paso (por eso se prefieren a los eventos cuando se puede) |

Los tipos de evento del sim que se aceptan son los que el sim emite (`"type": "…"` en `sim/`; el validador los saca
de ahí). Los de la UI y las condiciones son los de `TutorialRules` (`game/ui/tutorial/tutorial_rules.gd`):

| Evento de la UI | Datos |
|---|---|
| `panel_opened` · `panel_closed` | `panel` (nombre del nodo), y si el panel los tiene: `tab`, `stall`, `zone`, `mode`, `building` |
| `order_given` | La orden tal cual se da a `Game.give` (`type`, `actor`, `recipe`…): es lo que pide el jugador, no lo que el sim acepta |
| `selected` · `building_picked` | `id` |
| `interior_opened` · `interior_closed` | `building`, `type` |
| `camera_moved` · `zoom_changed` | `px` · `zoom` |
| `paused` · `resumed` · `speed_changed` | `speed` |
| `help_opened` · `chapter_started` | `chapter` |

| Condición | Argumentos | Se cumple si |
|---|---|---|
| `paused` | `is` | `Game.paused == is` |
| `speed` | `is` | Velocidad actual (sin pausa) |
| `selected` | `is` | El personaje elegido (`$head`, `$active` o un id) |
| `picked_building` | `is` | El edificio elegido en el mapa |
| `interior` | `is` | El edificio abierto por dentro (`""` = el pueblo, `$workshop`) |
| `interior_type` | `is` | El tipo del edificio abierto (`armory`) |
| `panel_open` | `is`, y opcionales `tab`, `stall`, `zone`, `mode` | Ese panel está a la vista (y sus propiedades valen eso) |
| `panel_prop` | `panel`, `prop`, `value` | Una propiedad de un panel visible vale eso |
| `node_visible` | `is` | Un nodo de la UI con ese nombre está a la vista |
| `camera_moved` | `px` | La cámara se ha movido al menos `px` desde que salió el paso |
| `storage_has` | `item`, `qty`, `building` (`$workshop`) | El almacén tiene al menos `qty` |
| `carries` | `item`, `qty` | El personaje activo lo lleva encima |
| `gold_gte` | `is` | El oro de la familia |
| `objective` · `objective_done` | `is` | El objetivo de inicio actual · ya cumplido |
| `has_trial` · `event_active` | `is` | Tu familia tiene un juicio abierto · hay un evento global en curso |
| `profession` | `is` | El oficio de tu taller (`carpenter`…) |

### 4.4 Qué se resalta

| Forma | Ejemplo | Qué rectángulo |
|---|---|---|
| Nodo de la UI | `{"ui": "LedgerButton"}` · `{"ui": "Debts", "in": "LedgerPanel"}` · `{"ui": "*_pay", "in": "LedgerPanel"}` | El primer nodo visible con ese nombre (comodín `*`), dentro del nodo `in` si se da. Se busca en el HUD, la UI del interior y las capas de tarjetas, por nombre de nodo (los `%Unique` del `.tscn` y los que crean los paneles: `Row_<receta>`, `Office_<cargo>`…) |
| Zona del HUD | `{"zone": "view"}` | Un rect de `HudLayout.ZONES` (`card`, `status`, `clock`, `column`, `manage`, `selection`, `notices`) o la vista libre (`view`) |
| Edificio · puerta | `{"world": "building", "id": "$workshop"}` · `{"world": "door", "type": "armory"}` | El volumen del edificio (planta + altura) o su puerta, por id, `$workshop` o `type` |
| Personaje | `{"world": "character", "id": "$head"}` | Su figura |
| Puesto | `{"world": "station", "id": "anvil"}` | El puesto en el interior abierto (`$first_station` = el primero de trabajo) |
| Servicio | `{"world": "service", "id": "resources"}` | Un puesto del mercado, `board` o `town_hall` |
| Casilla | `{"world": "tile", "at": [26, 19]}` | El rombo de la casilla |

`pad` (opcional) agranda el rect. Un edificio se resalta por su sprite tal como se dibuja. Un objetivo del mundo en el
pueblo mueve la cámara hasta él si no cae en la vista libre: al salir el paso, al repetirlo y cada vez que el foco pasa
a otro objetivo (al salir de un edificio, al abrir lo que lo abría); nunca lo persigue fotograma a fotograma, para que el
jugador pueda mover la cámara.

Un objetivo puede llevar su propio abridor: `"opener": {objetivo}` (y `"opener_text"`, la clave del texto), que manda
sobre la tabla. Sirve para las pestañas (`*_pay` del libro se abre con la pestaña Deudas) y para lo que solo se ve en
un sitio concreto (el mostrador de la Armería: si no estás dentro, la Armería).

### 4.5 Si el objetivo no está a la vista: lo que lo abre

Cuando el objetivo no se encuentra o está escondido, el motor resalta **lo que lo abre** y la tarjeta lo dice
(«Abre el libro de cuentas: L o este botón.»). Se busca así, como mucho 4 saltos:

1. El abridor propio del objetivo, si lo lleva (§4.4).
2. El primer antepasado escondido del nodo con entrada en `openers` (un panel cerrado, o una pestaña: `DynastyPage`
   → pestaña Dinastía) → su `target`, que a su vez puede no estar a la vista (`CourtshipPanel` → `CourtButton` en
   `CharacterPanel` → `InventoryButton`). El panel `in` solo cuenta como abridor si está cerrado: dentro de un panel
   abierto, lo que falta no se abre con el botón del panel.
3. La UI de un edificio o un puesto con el pueblo a la vista → `@interior` (tu taller).
4. Algo del pueblo desde dentro de un edificio → `@town` (Salir).

En cuanto el objetivo aparece, el foco salta a él sin que el paso cambie.

### 4.6 Pistas de primera vez

`data/tutorial.json` `hints`: `{id, when, target, text, until}`. Sale como mucho una a la vez (las que llegan
mientras, hasta 3, esperan su turno), solo si las pistas están encendidas y no se ha visto antes. Con un capítulo en
curso no sale (saldrá la próxima vez que pase). `until` (opcional) la quita sola y la da por vista (la del puesto se va
al dar la primera orden de trabajo); la de un panel se va si se cierra el panel, sin darla por vista. «Entendido» (o
Tab) la cierra y la da por vista; «No volver a mostrar» apaga todas las pistas (se vuelven a encender en Opciones).
`$event.<campo>` en el objetivo toma el dato del evento que la disparó (la de un puesto señala el puesto del
evento).

## 5. Cómo se ve

- **Velo**: `#1a1209` al 62 % sobre todo menos el rectángulo del objetivo (+3 px). Encima del HUD y de las tarjetas,
  debajo de los menús y del fundido (capa 35 entre las tarjetas, 30, y las pantallas, 40).
- **Marco**: 2 px de oro (`#c8a84e`) que late: crece 0 → 2 px y baja de brillo en 0,9 s, a saltos de píxel entero.
- **Flecha**: triángulo de oro de 7 px entre la tarjeta y el objetivo, apuntándolo, que sube y baja 2 px.
- **Tarjeta**: el aviso corto del kit de página (236 de ancho): la cinta con el capítulo (su nombre corto, `<capítulo>.short`, si el largo no cabe en una línea),
  «Paso n de total» en pequeño arriba a la derecha, el texto y los
  botones (ver abajo). Se coloca debajo del objetivo; si no cabe, encima, a la derecha o a la izquierda; nunca
  encima del objetivo ni fuera de la pantalla. Sin objetivo, en el centro de la vista libre.
- **Pista**: sin velo, el marco y la flecha más la tarjeta con «Entendido» / «No volver a mostrar».
- **Sigue al objetivo cada fotograma**: los paneles entran con `UiAnim` y se mueven; el foco se recalcula siempre
  (y vuelve a buscar el nodo cada 0,25 s si desapareció).
- **Modo guiado** (opcional, Opciones): el velo se queda los clics fuera del objetivo; pasan los del objetivo, los de
  la tarjeta y los del botón de pausa y velocidades. Esc y Espacio siempre funcionan.

Tarjeta: el aviso corto del kit de página ([04](04_kit_de_pagina.md), `PageCard`, plantilla `notice`, 236 de ancho,
variaciones `Page*`): el capítulo en la cinta (una línea), el paso en la tarjeta (`TutorialStep`, arriba a la derecha), el texto como párrafo (`PageInk`) y los botones en el pie.
Lo que el aviso no trae va en su columna con dos variaciones propias del theme común: `TutorialTitle` (la línea de
qué lo abre, bajo la cinta) y `TutorialStep` (la línea de teclas, sobre los botones). `TutorialCard`
(`tutorial_card.tscn`) envuelve la página: la monta con `build` (no se centra sola) y `sticky` (un clic no la cierra).

## 6. Progreso

En los ajustes del jugador (`user://settings.cfg`, `Settings`), **no en la partida** (no hay que subir la versión
del guardado):

| Clave | Qué |
|---|---|
| `tutorial/done` | Capítulos terminados (ids) |
| `tutorial/seen` | Pistas vistas (ids) |
| `tutorial/asked` | Ya se jugó una partida nueva (la casilla «Con tutorial» deja de salir marcada) |
| `game/tutorial_hints` | Pistas encendidas (sí por defecto) |
| `game/tutorial_guided` | Modo guiado (no por defecto) |

«Valores por defecto» de Opciones no borra `tutorial/*`. Un capítulo a medias no se guarda: al cargar una partida
no sigue (se repite desde F1).

## 7. Datos

- Lee: `Game` (pausa, velocidad, `order_given`), `Events.sim_event`, la app (interior abierto, mundo, cámara, HUD),
  `SimQuery` / `Objectives` / `Inventory` / `Tribunal` / `WorldEvents` solo para leer.
- Emite: ninguna orden. Cambia la pausa de la sesión solo con `pause: true`.
- Nuevo fuera de `game/ui/tutorial/`: la señal `Game.order_given(order)`; el bloque «Tutorial» de la ayuda
  (`HudKeys`/`HelpPanel` → `hud.tutorial_requested`); la casilla de partida nueva; dos casillas en Opciones.

## 8. Pruebas

- `tests/test_ui_tutorial.gd`: un disparador avanza el paso; «Siguiente» frente a acción; un objetivo escondido
  resalta lo que lo abre; el foco sigue al nodo si se mueve; pistas (vistas, apagadas, en cola durante un capítulo).
- `--smoke-script=tutorial_datos`: cada paso de cada capítulo encuentra su objetivo (abriendo lo que haga falta con
  sus `openers`) en la partida de su `test`; captura del primer y último paso de los capítulos 3 en adelante.
- `--smoke-script=tutorial`: los capítulos 1 y 2 enteros desde la partida nueva, haciendo las acciones como un
  jugador; una captura por paso (`reports/shots/tut_<capítulo>_<n>_<paso>.png`).

## 9. Los capítulos

Generadas de los datos el 2026-11-03; mandan los JSON. «Sale cuando» = disparador; «Pasa con» = acción esperada
(«Siguiente» si solo explica).

### 1. Primeros pasos (`first_steps`)

Elegir y mover a tu personaje, la hora y la velocidad, entrar en tu taller.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `welcome` | acaba el anterior · pausa | — | Esto es {town}. Te enseño lo básico paso a paso; el juego espera en pausa mientras lees. | «Siguiente» |
| 2 | `camera` | acaba el anterior | zona `view` | Mueve la cámara: WASD o las flechas, o arrastra con el botón central del ratón. | estado `camera_moved` (px=48) |
| 3 | `zoom` | acaba el anterior | zona `view` | La rueda del ratón acerca y aleja la vista. | ui `zoom_changed` |
| 4 | `select` | acaba el anterior | character `$head` | Tu protagonista: {head}. Con clic izquierdo eliges a alguien de tu familia (o con 1, 2 y 3); sobre un vecino, abres su ficha. | «Siguiente» |
| 5 | `group` | acaba el anterior | `GroupBar` | Arriba a la izquierda, tu grupo: hasta tres familiares, con las teclas 1, 2 y 3. Al lado, el oro de toda la familia. | «Siguiente» |
| 6 | `clock` | acaba el anterior | `ClockPanel` | Aquí la hora, el día y la estación. Un día de juego pasa en unos minutos. | «Siguiente» |
| 7 | `resume` | acaba el anterior | `PauseButton` | Pulsa Espacio (o este botón) para que corra el tiempo. Espacio otra vez lo para. | estado `paused` (is=False) |
| 8 | `speed` | acaba el anterior | `Speeds` | Mayús+2 (o ×2) va el doble de rápido. Prueba ×2. | estado `speed` (is=2) |
| 9 | `walk` | acaba el anterior | zona `view` | Ahora, clic derecho en el suelo: {head} va andando hasta allí. | ui `order_given` (type=move_to) |
| 10 | `workshop` | acaba el anterior | building `$workshop` | Esta es tu {workshop}. Clic derecho sobre ella para entrar. | estado `interior` (is=$workshop) |
| 11 | `bar` | acaba el anterior | `BuildingBar` | Dentro, abajo, la barra del taller: Producción (P), Almacén (A), Empleados (E), Mejoras (M) y Salir. | «Siguiente» |
| 12 | `objective` | acaba el anterior | `ObjectivePanel` | A la izquierda, tu objetivo de ahora. Si dudas, F1 abre la ayuda y desde ella repites cualquier capítulo. | «Siguiente» |

### 2. Producir (`produce`)

Recetas, puestos y calidad: de hierro a espada.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `furnace` | acaba el anterior | station `furnace` | Cada puesto hace sus recetas. El horno funde el hierro en lingotes. | «Siguiente» |
| 2 | `furnace_menu` | acaba el anterior | station `furnace` | Clic derecho en el horno: su menú. | estado `panel_open` (is=StationMenu, zone=furnace) |
| 3 | `modes` | acaba el anterior | `Modes` en `StationMenu` | Rápido, normal o con cuidado: con cuidado tarda más y sale mejor. | «Siguiente» |
| 4 | `ingot` | acaba el anterior | `Row_forge_ingot` en `StationMenu` | Elige el lingote de hierro: {head} se pone a trabajar. | ui `order_given` (type=work_at, recipe=forge_ingot) |
| 5 | `wait_ingots` | acaba el anterior | station `furnace` | La barra sobre el horno avanza. Una espada pide dos lingotes: espera a tenerlos (Mayús+3 acelera). | estado `storage_has` (item=iron_ingot, qty=2) |
| 6 | `anvil_menu` | acaba el anterior | station `anvil` | Ya están. Ahora clic derecho en el yunque. | estado `panel_open` (is=StationMenu, zone=anvil) |
| 7 | `live` | acaba el anterior | `CarefulButton` en `StationMenu` | Elige Forja viva: la espada la forjas tú, en tres pasos. | estado `panel_prop` (panel=StationMenu, prop=mode, value=live) |
| 8 | `quality` | acaba el anterior | `QualityBox` en `StationMenu` | La calidad esperada: depende de tu oficio, de la herramienta y del modo. | «Siguiente» |
| 9 | `sword` | acaba el anterior | `Row_forge_sword` en `StationMenu` | Elige la espada. | ui `order_given` (type=work_at, recipe=forge_sword) |
| 10 | `live_forge` | estado `panel_open` (is=LiveForgeScreen) | `Panel` en `LiveForgeScreen` | Saca el hierro en rojo cereza, bate siguiendo la plantilla y témplala al aceite. Esc: resolver sin jugar. | sim `live_forge_done` (recipe=forge_sword) o sim `work_done` (item=sword) |
| 11 | `storage` | estado `storage_has` (item=sword, qty=1) | `StorageButton` | La espada está en el almacén. Ábrelo (A). | estado `panel_open` (is=StoragePanel) |
| 12 | `result` | acaba el anterior | `BuildingGrid` en `StoragePanel` | Aquí está, con su calidad. El siguiente capítulo enseña a venderla. | «Siguiente» |

### 3. Vender y comprar (`market`)

El mercado, la demanda y el recado de entrega.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `armory` | acaba el anterior | building tipo `armory` | La Armería compra armas y herramientas. Vende allí lo que lleves encima. | «Siguiente» |
| 2 | `take` | acaba el anterior · si estado `storage_has` (item=sword, qty=1) | `BuildingGrid` en `StoragePanel` | Para vender hay que llevarlo encima: en el almacén de tu taller, clic en la espada la coge. | estado `carries` (item=sword) |
| 3 | `enter` | acaba el anterior | building tipo `armory` | Clic derecho en la Armería: {head} va y entra. | estado `interior_type` (is=armory) |
| 4 | `counter` | acaba el anterior | station `counter` | Clic en el mostrador para comerciar. | estado `panel_open` (is=MarketPanel) |
| 5 | `sell_tab` | acaba el anterior | `SellTab` en `MarketPanel` | Pestaña Vender. | estado `panel_prop` (panel=MarketPanel, prop=tab, value=sell) |
| 6 | `sell_list` | acaba el anterior | `Scroll` en `MarketPanel` | Lo que llevas, con su precio. Cada venta baja la demanda; al alba se recupera. | «Siguiente» |
| 7 | `leave` | acaba el anterior | `ExitButton` | Sal a la calle (Salir o Esc). | estado `interior` (is=) |
| 8 | `resources` | acaba el anterior | service `resources` | El puesto de Recursos vende hierro y carbón. Clic derecho sobre él: vas y se abre. | estado `panel_open` (is=MarketPanel, stall=resources) |
| 9 | `errand` | acaba el anterior | `Send` en `BuyList` | Recado: te lo llevan a tu taller por un recargo y no cargas peso. Encarga algo. | sim `errand_sent` |
| 10 | `done` | acaba el anterior | — | Compra barato, vende cuando la demanda esté alta. El libro (L) apunta cada moneda. | «Siguiente» |

### 4. Deuda y libro de cuentas (`debt`)

Cuánto debes, cuándo vence y dónde se paga.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `debt_box` | acaba el anterior | `DebtBox` | Empiezas con una deuda: la cifra, lo pagado y los días que quedan. | «Siguiente» |
| 2 | `open` | acaba el anterior | `LedgerButton` | Abre el libro de cuentas: L o este botón. | estado `panel_open` (is=LedgerPanel) |
| 3 | `today` | acaba el anterior | `Tabs` en `LedgerPanel` | Pestañas: hoy, los últimos días, cada edificio, deudas, avisos y reputación. | «Siguiente» |
| 4 | `debts` | acaba el anterior | `Debts` en `LedgerPanel` | Pestaña Deudas. | estado `panel_prop` (panel=LedgerPanel, prop=tab, value=debts) |
| 5 | `pay` | acaba el anterior | `*_pay` en `LedgerPanel` | Paga aquí cuando tengas oro. Si vence sin pagar: −10 de reputación y una prórroga con recargo; después, embargo. | «Siguiente» |
| 6 | `notices` | acaba el anterior | `Notices` en `LedgerPanel` | Avisos: todo lo que ha pasado, también lo que ya no está en pantalla. | «Siguiente» |

### 5. Empleados (`staff`)

Contratar, rangos y la cola de producción.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `manage` | acaba el anterior | building `$workshop` | Doble clic en tu {workshop}: la gestionas sin ir andando. | estado `interior` (is=$workshop) |
| 2 | `open` | acaba el anterior | `StaffButton` | Empleados (E). | estado `panel_open` (is=StaffPanel) |
| 3 | `staff_tab` | acaba el anterior | `StaffTab` en `StaffPanel` | Tu plantilla: quién trabaja, su rango, su lealtad y su sueldo. | «Siguiente» |
| 4 | `hire_tab` | acaba el anterior | `HireTab` en `StaffPanel` | Pestaña Contratar. | estado `panel_prop` (panel=StaffPanel, prop=tab, value=hire) |
| 5 | `ranks` | acaba el anterior | `Ranks` en `StaffPanel` | Cada rango cobra más al día y trabaja más rápido. | «Siguiente» |
| 6 | `list` | acaba el anterior | `List` en `StaffPanel` | Los candidatos. Contratar: un clic arma el botón y el segundo confirma. | «Siguiente» |
| 7 | `production` | acaba el anterior | `ProductionButton` | Los empleados trabajan la cola de Producción (P). | estado `panel_open` (is=ProductionPanel) |
| 8 | `queue_tab` | acaba el anterior | `QueueTab` en `ProductionPanel` | Pestaña Cola. | estado `panel_prop` (panel=ProductionPanel, prop=tab, value=queue) |
| 9 | `add` | acaba el anterior | `RecipeGrid` en `ProductionPanel` | Elige qué fabricar y cuántos; el bucle lo repite sin fin. | «Siguiente» |

### 6. Mejoras (`upgrades`)

El árbol de mejoras y las obras.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `manage` | acaba el anterior | building `$workshop` | Doble clic en tu {workshop} para gestionarla. | estado `interior` (is=$workshop) |
| 2 | `open` | acaba el anterior | `UpgradesButton` | Mejoras (M). | estado `panel_open` (is=UpgradePanel) |
| 3 | `grid` | acaba el anterior | `Grid` en `UpgradePanel` | Ocho ramas de tres niveles. Cada casilla, una mejora; las de abajo piden las de arriba. | «Siguiente» |
| 4 | `detail` | acaba el anterior | `Detail` en `UpgradePanel` | El detalle: lo que cambia, lo que cuesta y lo que falta. | «Siguiente» |
| 5 | `buy` | acaba el anterior | `BuyButton` en `UpgradePanel` | Comprar abre una obra: el taller para mientras dura. | «Siguiente» |

### 7. Familia, cortejo y herencia (`family`)

El árbol, el heredero y cómo buscar pareja.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `open` | acaba el anterior | `TreeButton` en `StatusBar` | El árbol de tu familia: F o este botón. | estado `panel_open` (is=FamilyTreePanel) |
| 2 | `canvas` | acaba el anterior | `Canvas` en `FamilyTreePanel` | Tu familia: el cabeza, su pareja y los hijos. La corona marca a quien hereda: si muere el cabeza, lo recibe todo. Clic en alguien para ver su ficha. | «Siguiente» |
| 3 | `heads` | acaba el anterior | `Heads` en `FamilyTreePanel` | Pestaña Dinastía: los cabezas que ha tenido tu casa y cuántos días mandó cada uno. | «Siguiente» |
| 4 | `goals` | acaba el anterior | `Goals` en `FamilyTreePanel` | Las metas de tu dinastía: cinco generaciones, una fortuna, la alcaldía. | «Siguiente» |
| 5 | `sheet` | acaba el anterior | `InventoryButton` | La ficha de quien tienes elegido: I. | estado `panel_open` (is=CharacterPanel) |
| 6 | `court` | acaba el anterior | `CourtButton` en `CharacterPanel` | Cortejar: busca pareja entre los solteros del pueblo. | estado `panel_open` (is=CourtshipPanel) |
| 7 | `courtship` | acaba el anterior | `CourtshipPanel` | Conversar cada día y regalar sube la afinidad. Con bastante, pides su mano y hay boda. | «Siguiente» |
| 8 | `heir` | acaba el anterior | `GroupBar` | Los hijos que cumplen 16 entran en tu grupo. Cuida de quien herede: tu dinastía sigue con su línea. | «Siguiente» |

### 8. Títulos y reputación (`titles`)

Qué da la reputación y cómo se pide un título.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `card` | acaba el anterior | `FamilyTitle` | El título de tu familia y su reputación. | «Siguiente» |
| 2 | `open` | acaba el anterior | `LedgerButton` | La reputación se lleva en el libro: L. | estado `panel_open` (is=LedgerPanel) |
| 3 | `rep_tab` | acaba el anterior | `Reputation` en `LedgerPanel` | Pestaña Reputación. | estado `panel_prop` (panel=LedgerPanel, prop=tab, value=reputation) |
| 4 | `rep` | acaba el anterior | `Content` en `LedgerPanel` | Sube con encargos cumplidos, ventas justas y sueldos pagados; baja con deudas vencidas, multas e insultos. | «Siguiente» |
| 5 | `hall` | acaba el anterior | service `town_hall` | El Ayuntamiento, al sur de la plaza. Clic derecho sobre él con alguien elegido. | estado `panel_open` (is=TownHallPanel) |
| 6 | `ladder` | acaba el anterior | `Ladder` en `TownHallPanel` | La escalera de títulos: cada uno abre más edificios y cargos. | «Siguiente» |
| 7 | `req` | acaba el anterior | `ReqList` en `TownHallPanel` | Lo que pide el siguiente: reputación, oro y negocios. Se paga aquí. | «Siguiente» |

### 9. Cargos y elecciones (`offices`)

Quién gobierna, cuándo se vota y qué poderes da un cargo.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `open` | acaba el anterior | `OfficesButton` | Los cargos del pueblo: O. | estado `panel_open` (is=OfficesPanel) |
| 2 | `chart` | acaba el anterior | `Chart` en `OfficesPanel` | Quién ocupa cada cargo y hasta cuándo. Cada título abre cargos nuevos. | «Siguiente» |
| 3 | `calendar` | acaba el anterior | `Calendar` en `OfficesPanel` | Hay que inscribirse antes del invierno; el invierno es la campaña y se vota al cambiar de año. | «Siguiente» |
| 4 | `powers` | acaba el anterior | — | Un cargo paga cada día y da poderes: mover un precio, multar, fijar el impuesto… | «Siguiente» |

### 10. Tribunal (`court`)

Cómo se llega a juicio y cómo se gana.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `why` | acaba el anterior | — | Una inspección, un soborno descubierto o una acusación te llevan a juicio. | «Siguiente» |
| 2 | `button` | acaba el anterior · si estado `has_trial` (is=True) | `TrialsButton` | Tienes un juicio abierto: J o este botón. | estado `panel_open` (is=TrialPanel) |
| 3 | `balance` | acaba el anterior · si estado `has_trial` (is=True) | `Balance` en `TrialPanel` | Gana quien más pese al final: tu retórica y tus testigos contra los suyos y las pruebas. | «Siguiente» |
| 4 | `witnesses` | acaba el anterior · si estado `has_trial` (is=True) | `Witnesses` en `TrialPanel` | Antes de la vista, convence, soborna o amenaza a los testigos en persona. | «Siguiente» |
| 5 | `accuse` | acaba el anterior | — | Siendo Ciudadano puedes acusar tú a otra familia desde la ficha de uno de los suyos. | «Siguiente» |

### 11. Estaciones y eventos (`seasons`)

Cómo cambian los precios con la estación y los eventos.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `date` | acaba el anterior | `DateLabel` | El día y la estación. Cada estación mueve los precios: en invierno la comida sube. | «Siguiente» |
| 2 | `event` | acaba el anterior · si estado `event_active` (is=True) | `EventLabel` | Un evento en curso y lo que le queda. Pasa el ratón para verlos todos. | «Siguiente» |
| 3 | `open` | acaba el anterior | `LedgerButton` | El libro (L) explica cada precio. | estado `panel_open` (is=LedgerPanel) |
| 4 | `today` | acaba el anterior | `Today` en `LedgerPanel` | Pestaña Hoy. | estado `panel_prop` (panel=LedgerPanel, prop=tab, value=today) |
| 5 | `prices` | acaba el anterior | `SeasonPrices` en `LedgerPanel` | El motivo de cada precio: la estación y los eventos. | «Siguiente» |

### 12. Oficio: carpintero (`trade_carpenter`)

Tu carpintería: sus dos puestos y dónde se vende. · solo si `carpenter`

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `enter` | acaba el anterior | building `$workshop` | Tu carpintería. Clic derecho para entrar (o doble clic para gestionarla). | estado `interior` (is=$workshop) |
| 2 | `first` | acaba el anterior | station `sawhorse` | El caballete sierra la madera. Clic derecho sobre él. | estado `panel_open` (is=StationMenu, zone=sawhorse) |
| 3 | `recipe` | acaba el anterior | `Row_carpentry_planks` en `StationMenu` | Tablas: la base de todo lo demás. | «Siguiente» |
| 4 | `second` | acaba el anterior | station `workbench` | En el banco, las tablas se vuelven barriles, arcones y armarios. | «Siguiente» |
| 5 | `stall` | acaba el anterior | service `goods` | Se vende en el puesto de Enseres; la madera se compra en Recursos. | «Siguiente» |

### 13. Oficio: albañil (`trade_mason`)

Tu cantería: sus dos puestos y dónde se vende. · solo si `mason`

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `enter` | acaba el anterior | building `$workshop` | Tu cantería. Clic derecho para entrar (o doble clic para gestionarla). | estado `interior` (is=$workshop) |
| 2 | `first` | acaba el anterior | station `cutting_bench` | El banco de corte saca sillares de la piedra. Clic derecho sobre él. | estado `panel_open` (is=StationMenu, zone=cutting_bench) |
| 3 | `recipe` | acaba el anterior | `Row_masonry_ashlar` en `StationMenu` | Sillares: los piden casi todas las piezas. | «Siguiente» |
| 4 | `second` | acaba el anterior | station `carving_bench` | En el banco de tallar: piedras de afilar, abrevaderos y muelas. | «Siguiente» |
| 5 | `stall` | acaba el anterior | service `goods` | Se vende en el puesto de Enseres; la piedra se compra en Recursos. | «Siguiente» |

### 14. Oficio: sastre (`trade_tailor`)

Tu sastrería: sus dos puestos y dónde se vende. · solo si `tailor`

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `enter` | acaba el anterior | building `$workshop` | Tu sastrería. Clic derecho para entrar (o doble clic para gestionarla). | estado `interior` (is=$workshop) |
| 2 | `first` | acaba el anterior | station `loom` | El telar teje la lana en tela. Clic derecho sobre él. | estado `panel_open` (is=StationMenu, zone=loom) |
| 3 | `recipe` | acaba el anterior | `Row_tailor_cloth` en `StationMenu` | Tela: la base de toda la ropa. | «Siguiente» |
| 4 | `second` | acaba el anterior | station `sewing_table` | En la mesa de costura: ropa de trabajo, capas y ropa común. | «Siguiente» |
| 5 | `stall` | acaba el anterior | service `clothier` | Se vende en la Ropería; la lana se compra en Recursos. | «Siguiente» |

### 15. Duelo (`duel`)

Retar con motivo y ganar al alba (docs/gdd/04e_combate.md). Se prueba con el escenario `duel_ready`.

| # | Paso | Sale cuando | Resalta | Texto (ES) | Pasa con |
|---|---|---|---|---|---|
| 1 | `why` | acaba el anterior | — | El juego no va de pelear, pero el honor cuenta: puedes retar a quien te ha ofendido, a un pretendiente rival o al rival de tu oficio. Rechazar un reto ante testigos cuesta reputación. | «Siguiente» |
| 2 | `sheet` | acaba el anterior | — | Haz clic en el rival de tu oficio para abrir su ficha. | estado `panel_open` (is=NpcPanel) |
| 3 | `button` | acaba el anterior · si estado `panel_open` (is=NpcPanel) | `DuelButton` en `NpcPanel` | «Retar a duelo…»: la carta dice el motivo, tus opciones y lo que te juegas. | «Siguiente» |
| 4 | `dawn` | acaba el anterior | — | Si acepta, el duelo es al alba siguiente en la plaza. Tu duelista irá solo: si no está allí a la hora, pierde. | «Siguiente» |
| 5 | `read` | acaba el anterior | — | En el duelo, lee el gesto: Golpe gana a Finta, Finta a Parada y Parada a Golpe. «Resolver sin jugar» rinde lo mismo que seguir la pista. | «Siguiente» |

### Pistas de primera vez

| Pista | Sale cuando | Resalta | Texto (ES) | Se va sola con |
|---|---|---|---|---|
| `inside` | estado `interior` (is=$workshop) | station `$first_station` | Clic derecho en un puesto: trabajar aquí. | ui `order_given` (type=work_at) |
| `storage` | estado `panel_open` (is=StoragePanel) | `BuildingGrid` en `StoragePanel` | Clic: coger. Lo que llevas encima, abajo. | — |
| `production` | estado `panel_open` (is=ProductionPanel) | `Tabs` en `ProductionPanel` | Elige qué fabricar y cuántos en la pestaña Cola: los empleados la trabajan. | — |
| `market` | estado `panel_open` (is=MarketPanel) | `MarketPanel` | Cada venta baja la demanda; al alba se recupera. | — |
| `ledger` | estado `panel_open` (is=LedgerPanel) | `Tabs` en `LedgerPanel` | Tu oro día a día, tus deudas y los avisos que se fueron de la pantalla. | — |
| `staff` | estado `panel_open` (is=StaffPanel) | `StaffTab` en `StaffPanel` | Cada rango cobra más y trabaja más rápido: mira la tabla antes de contratar. | — |
| `upgrades` | estado `panel_open` (is=UpgradePanel) | `Grid` en `UpgradePanel` | Las mejoras paran el taller mientras dura la obra. | — |
| `tree` | estado `panel_open` (is=FamilyTreePanel) | `Heads` en `FamilyTreePanel` | El heredero recibe todo si muere el cabeza. Cámbialo en su ficha. | — |
| `courtship` | estado `panel_open` (is=CourtshipPanel) | `CourtshipPanel` | Con afinidad alta puedes pedir su mano. Conversar cada día y regalar la suben. | — |
| `npc` | estado `panel_open` (is=NpcPanel) | `RelationBar` en `NpcPanel` | Lo que hagas cambia la relación y los precios que te pone. | — |
| `microevent` | estado `panel_open` (is=MicroeventCard) | `MicroeventCard` | El tiempo no se para: si no eliges, se aplica la marcada. | — |
| `town_hall` | estado `panel_open` (is=TownHallPanel) | `Ladder` en `TownHallPanel` | Cada título abre más edificios y cargos; se pide aquí pagando oro. | — |
| `offices` | estado `panel_open` (is=OfficesPanel) | `Calendar` en `OfficesPanel` | Inscríbete antes del invierno: la campaña es el invierno y se vota al cambiar de año. | — |
| `families` | estado `panel_open` (is=FamiliesPanel) | `FamiliesPanel` | La rivalidad sube si les quitas ventas, parcelas o cargos, y baja con el tiempo y los regalos. | — |
| `trial` | sim `trial_opened` | `TrialsButton` | Te han llevado a juicio. Hasta la vista, gana testigos a tu favor: J abre el juicio. | — |
| `trial_panel` | estado `panel_open` (is=TrialPanel) | `Balance` en `TrialPanel` | Gana quien más pese al final de la vista. | — |
| `world_event` | sim `world_event_started` (anyone=True) | `EventLabel` | Un evento cambia precios y demanda mientras dura. Pasa el ratón por aquí para ver cuánto queda. | — |
| `wedding` | sim `wedding` | `GroupBar` | ¡Boda! Tu pareja entra en tu grupo: elígela con su número. | — |
| `birth` | sim `child_born` | `TreeButton` en `StatusBar` | Ha nacido un hijo. En el árbol (F) eliges su escuela cuando crezca. | — |
| `inheritance` | sim `inheritance` | `Card` | Quien hereda toma el mando: ahora juegas con su personaje. | — |
| `duel_button` | estado `node_visible` (is=DuelButton) | `DuelButton` en `NpcPanel` | Con un motivo (una ofensa, un pretendiente rival, el rival de tu oficio) puedes retarle a duelo. | — |
| `duel_card` | estado `panel_open` (is=DuelCard) | `DuelCard` | Cuantos más testigos, más honor: un duelo público cuenta el doble, y rechazarlo también. | — |
| `duel_screen` | estado `panel_open` (is=DuelScreen) | `Gesture` en `DuelScreen` | Lee el gesto y cuánto fiarte de él. Golpe gana a Finta, Finta a Parada, Parada a Golpe; parar recupera aliento. | — |

## 10. Criterios de aceptación

- [ ] Partida nueva por primera vez: «Con tutorial» marcada; al empezar sale el capítulo 1 con el juego en pausa.
- [ ] En cada captura de `--smoke-script=tutorial` el marco cae justo encima de lo que dice la tarjeta y la tarjeta
      no lo tapa.
- [ ] Con el libro cerrado, un paso sobre la pestaña Deudas resalta el botón del libro; al abrirlo, el foco pasa a la
      pestaña sin cambiar de paso.
- [ ] Un panel que entra animado (UiAnim) lleva el foco pegado a su botón en cada fotograma.
- [ ] `--smoke-script=tutorial_datos` sale con 0: todos los pasos de todos los capítulos encuentran su objetivo.
- [ ] Pistas: la primera apertura del almacén enseña la suya; «Entendido» no la vuelve a enseñar; «No volver a
      mostrar» apaga todas y Opciones las enciende.
- [ ] Ningún cambio en `sim/`; `WorldState.VERSION` sin tocar.

## Decisiones que necesitan al owner

1. **Pausa al empezar.** El primer paso del capítulo 1 pausa el juego para que se lea; el jugador la quita en el
   paso «resume». Alternativa: no pausar nunca (el capítulo 1 enseña igual la pausa).
2. **Modo guiado apagado por defecto.** Propongo apagado (el jugador puede explorar sin que nada le bloquee) y
   encenderlo en Opciones. Alternativa: encendido en el capítulo 1.
3. **«No volver a mostrar» apaga todas las pistas**, no solo esa (la de esa ya no vuelve a salir con «Entendido»).
4. **Teclas**: Tab, Mayús+Tab y Retroceso. Alternativa: F2 / F3 / F4.
5. **El capítulo 1 no se reabre solo** al cargar una partida a medias: se repite desde F1.
