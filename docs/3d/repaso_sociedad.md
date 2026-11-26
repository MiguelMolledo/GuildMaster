# Repaso en 3D · familia, sociedad y política

Rama `3d-sociedad` (sale de `3d` en f8d582cc). Encargo: que las mecánicas de familia, sociales y políticas funcionen en
el pueblo 3D, verificadas de punta a punta con los flujos de `data/flows` (conductor de UI con ratón y con teclado).
Se mira sobre todo lo que pasa fuera del taller: ayuntamiento, plaza, iglesia y las casas.

Leyenda: **verde** = funcionaba en 3D sin tocar nada · **arreglado** = fallaba y se arregló · **falla** = sigue fallando.

## Tabla

| Mecánica | Flujo | Estado 3D | Qué se arregló / qué falta |
|---|---|---|---|
| Cortejar y boda | `cortejo_boda` | verde | Ficha (I) → Cortejar → hablar → proponer → boda y su carta. Las cartas de la pila salen sobre el 3D igual que en 2D. |
| Fiesta de boda | `fiesta_boda` | verde | Con 30 de oro: «Dar banquete» apagado con su motivo y «Boda sencilla». La rama del banquete con encargos en el tablón no se recorre en este escenario (falta oro); el tablón en 3D ya lo prueba `primer_dia`. |
| Regalos y equipo | `regalos` | verde | Equiparse, regalar en el cortejo, banquete (330 de oro) y regalar a un vecino pulsado en el pueblo 3D. |
| Vecinos y familia | `vecinos_familia` | verde | Hablar/halagar/insultar/amenazar a un vecino pulsado en 3D, acusar al rival pulsado en 3D, heredero, oficio, rutina, directivas de la IA familiar, poder de cargo y cerrar la dinastía. |
| Edades | `edades` | arreglado | Los retratos del árbol estaban bien; **los cuerpos 3D no** (y la familia en casa salía mal: ver abajo): los hijos de `family_ages` (0, 8, 12 y 16 años) salían con el pelo blanco, que heredan de su madre en los datos. El 3D no pasaba por `Identity.natural_hair` como el 2D; ahora sí (las canas de los mayores siguen saliendo de la edad). Prueba: `test_world3d_sociedad`. |
| Escuela | `escuela` | verde | Árbol → hija de 8 → materia → confirmar. Panel 2D sobre el 3D. |
| Dados y apuesta | `dados` | verde | La carta del altercado de la plaza a las 20:00, el corredor de apuestas (sin oro y con 200) y los dados. Los dados siguen abriéndose por el arnés: no hay entrada por la interfaz (llega con la taberna; ya estaba así en 2D). |
| Duelo | `duelo` | arreglado | Fallaba en 3D **y en 2D**: tras cargar otra partida, las cartas acopladas de la anterior seguían en la pila y la carta del reto se quedaba esperando detrás («pelea_carta»). Ahora, al empezar o cargar una partida, se cierran las cartas del pueblo de la anterior. Prueba en `test_ui_card_stack`. |
| Reto recibido y limosna | `reto_recibido` | verde | Aceptar un reto, retar y retirarse, y dar limosna a un mendigo pulsado en el pueblo 3D. |
| Juez | `juez` | verde | El juicio que preside la familia se abre y pausa; el veredicto contra la balanza pide confirmar. |
| Tribunal | `tribunal` | verde | Acusado: preparar la defensa, la vista oral (se abre sola y pausa), interrogar, concluir y la tarjeta del veredicto. |
| Título | `titulo` | verde | Clic derecho en el puesto del Ayuntamiento del pueblo 3D → su panel → pedir el título → ceremonia. |
| Elecciones | `elecciones` | verde | Organigrama (O), presentarse, discurso de campaña y la tarjeta del recuento del cambio de año. |

**Resumen:** 13 de 13 flujos en verde en 3D, sin ventana y con ventana, con ratón y con teclado. 11 funcionaban sin
tocar nada, 2 se arreglaron (edades, duelo). Ninguno falla.

## Arreglos fuera de una mecánica concreta

- **Auditor visual de los flujos en 3D.** En 3D la captura sale al tamaño de la ventana (1920×1080) y los controles
  viven en el lienzo de 960×540: el auditor medía el contraste en otro sitio y daba decenas de avisos falsos
  (`regalos`: 124). Ahora mide sobre la captura escalada al lienzo (`regalos`: 0, igual que en 2D). Beneficia también
  a los flujos `quick` en 3D.

- **La gente dentro de la casa abierta en sitio.** `InteriorView._project` quería parar el `InteriorStage` del
  interior 2D, pero lo pedía `as CanvasItem` y el stage es un `Node`: daba null y seguía colocando y mostrando cada
  fotograma los sprites 2D de quien está dentro, encima del 3D y en las posiciones de la sala 2D. Con la familia en
  casa (`family_ages`, la forja) salían figuras en píxel por la forja y dos niñas de pie sobre el tejado vecino; el
  botón de planta además decía «Planta baja» estando en la baja. Ahora se para su `_process` (su entrada, la de atender
  clientes y cambiar de planta, sigue) y solo se ven los cuerpos 3D. El anillo de la persona elegida, que daba ese
  sprite, lo pone ahora el 3D sobre su cuerpo dentro de la casa. Los flujos `quick` y los capítulos 1-2 del tutorial
  en 3D siguen en verde. Afecta a todas las casas abiertas en sitio, no solo a la familia.

## Lo que queda (y de quién es)

| Qué | Por qué no se hizo aquí | Hito |
|---|---|---|
| La pantalla del duelo dibuja a los duelistas con sprites 2D («Arte provisional: faltan las poses del duelo»). | Es arte y otra pantalla, no la vista del pueblo. La mecánica funciona entera. | M3D-5 / M3D-7 |
| La pelea de la plaza (altercado) no se ve como pelea en el pueblo 3D: la carta y la apuesta funcionan, pero los cuerpos no hacen el gesto. | Los altercados en 3D son de «vida» (rondas, corrillos, altercados). | M3D-5 |
| Los guiones de captura `--smoke-script=familia, titulos, cargos, tribunal, duelo_partida` siguen siendo 2D (usan `app.world()`). | Solo fotografían paneles que los flujos ya recorren en 3D con entrada real. | M3D-8 |
| Las casas sin trazado en sitio abren todavía el interior 2D. Ninguna de estas mecánicas entra en una (el Ayuntamiento es un puesto con panel; iglesia y molino no son edificios de la sim en town_e). | Transición de casas: worker de la rama `3d`. | M3D-4 / M3D-5 |
| La captura de la planta alta de la forja con los hijos (edades en 3D). | Con ventana, Godot se cerró dos veces al montar el pueblo (máquina sin memoria con otras pasadas a la vez); sin ventana no hay imagen. Sin capturar. | — |
| Dentro de la casa abierta no sale el nombre de la persona elegida (solo su anillo). | Era el sprite 2D quien lo ponía; las marcas 3D (`Marks3D`) solo nombran a la gente de la calle. | M3D-4 / M3D-7 |
| Fugas de memoria al salir (`ERROR: … RID allocations leaked at exit`) en los flujos con carta de fiesta (`cortejo_boda`, `fiesta_boda`, `regalos`). | Salen igual en 2D: no son del 3D. No rompen el flujo (verifica las apunta como `engine_errors`). | — |

## Cómo se comprueba

- Sin ventana, un flujo: `/opt/homebrew/bin/godot --audio-driver Dummy --headless --path . -- --flow=<id>
  --verifica-out=tmp/x` (los 13 llevan `"view": "3d"`; `--view=2d` los juega en 2D para comparar).
- Con ventana y capturas: `python3 tools/verifica/verifica.py --window --flows=cortejo_boda,fiesta_boda,…`
  (cada flujo por `grimoire heavy`). Con teclado: `--keys`.
- Pruebas: `--only=test_ui_card_stack`, `--only=test_world3d_sociedad`.

## Capturas

En `docs/novedades/`, todas con ventana en 3D (1920×1080): `sociedad_cortejo_boda` (carta de la boda),
`sociedad_fiesta_boda` (la oferta), `sociedad_regalos` (ficha de un vecino pulsado en el pueblo),
`sociedad_vecinos_familia` (el rival pulsado: acusar, retar), `sociedad_edades` (árbol, 62 años), `sociedad_escuela`,
`sociedad_dados` (la pelea de la plaza encuadrada) y `sociedad_dados_2` (los dados), `sociedad_duelo` (la pantalla del
lance) y `sociedad_duelo_2` (la carta «acepta el duelo»), `sociedad_reto_recibido` (el mendigo y «Dar limosna»),
`sociedad_juez`, `sociedad_tribunal` (la vista oral), `sociedad_titulo` (el Ayuntamiento) y `sociedad_elecciones`
(campaña). Los flujos de encuadre que las sacaron no son flujos del juego: quedan fuera de git (`tmp/`).
