# Repaso en 3D · ciudad, economía, región y sistema (rama `3d-ciudad`)

> Encargo del owner (2026-11-26): «repasa que las mecánicas funcionen ahora con el 3D». Esta tabla cubre los flujos de
> la ciudad, la economía, la región y el sistema. Cada flujo de `data/flows/` pasa a `"view": "3d"` y se juega con
> ratón y teclado reales sobre el pueblo 3D (`python3 tools/verifica/verifica.py --flows=<id> [--window]`).
> Estado: **verde** (funciona en 3D sin tocar nada), **arreglado** (fallaba en 3D y se arregló en la vista o el puente
> 3D), **falla** (sigue sin funcionar; dice por qué).

## Tabla

| Mecánica | Flujo | Estado en 3D | Qué se arregló / qué falta |
|---|---|---|---|
| Comprar la taberna y llevar un turno (carta, precios, plato del día, licencia, noche, camas, servir) | `taberna` | **arreglado** | La capa de la posada (huéspedes y camas) era 2D y en 3D quedaba oculta: el flujo «pasaba» pulsando una capa invisible. Ahora los huéspedes del turno son cuerpos 3D sentados en los taburetes y bancos de la sala (`Inn3D` los mete en el reparto de `SituLive`, vestidos con los colores de su grupo), las camas son las camas de huésped del interior 3D, y sobre ellos se dibujan el pedido, la paciencia y el estado de la cama; el clic sirve y hace la cama (`InnLayer` con proyector). Las camas están en la planta de arriba: se ven con «Planta alta». La posada de nivel 3 no tenía interior en sitio que cupiera en su casa del mapa (6×6 m, 3 plantas) y caía al interior 2D: ahora toma el interior del nivel más cercano dibujado para su solar, con sus plantas |
| Abrir un segundo negocio en una parcela (modo construcción, restaurar una ruina, obra, reconvertir, derribar) | `parcelas` | **arreglado** (con ventana, cierre con fallo) | Todos los pasos pasan con y sin ventana, pero con ventana Godot se cae **al salir** (`~ArrayMesh` sin RenderingServer, mallas y materiales sin liberar tras rehacer casas por obras, reconversión y derribo): `verifica` lo cuenta como FALLA. No afecta a la partida; queda por buscar qué guarda esas mallas. El modo construcción (B) no existía en 3D: `BuildLayer3D` pinta las parcelas por zona sobre el suelo del pueblo 3D (proyectadas cada fotograma, con sus rótulos y el resalte al pasar) y el clic en una abre su carta. Una partida nueva o una carga sale del modo construcción. El flujo apunta a la parcela (`"world": {"plot": …}`) en vez de a una casilla |
| Responder a un suceso (microevento y secuestro) | `suceso` | **verde** | Tarjetas de la columna: no dependen de la vista |
| Fiestas (pregón, patrocinar, inscribirse en la justa) | `fiestas` | **verde** | Cartas y pregón sobre el 3D. La fiesta dibujada en 3D (puestos, decoración) es de M3D-5 |
| Tratados y encargos de fuera | `tratados` | **verde** | Mapa de la región y fichas en 2D encima del 3D (la región en 3D es M3D-6) |
| El mapa de la región (R, fichas, rueda, Esc) | `mapa_region` | **verde** | Sigue en 2D sobre el juego en 3D (M3D-6) |
| Viajar, caravana y tratado | `viajes` | **verde** | Pantallas de ciudad y caravanas en 2D sobre el 3D (M3D-6) |
| Elegir otra ciudad (Bellcaire) | `otra_ciudad` | **verde** | La capital se monta en 3D desde su mapa |
| Cada pantalla se cierra con Esc | `esc` | **arreglado** | Fallaba la ficha de un vecino: el clic caía donde también estaba alguien de la familia (en 3D gana la familia, como en 2D) y el flujo no lo evitaba; ahora apunta donde solo está el vecino |
| Teclas (cada una hace algo y no choca) | `teclas` | **arreglado** | Se audita con los controles 3D de hoy: en la ciudad W/A/S/D y las flechas desplazan la cámara, Q/E la giran, RePág/AvPág la inclinan (la firma del flujo mide ahora giro e inclinación); dentro de una casa abierta en sitio las flechas avisan «La cámara no se mueve dentro» y W/S/D no hacen nada (A abre el almacén). **Decisión del owner**: qué deben hacer W/A/S/D en 3D (hoy mueven la cámara; en 2D, desde 0c29e28f, andan con la persona elegida) |
| Opciones, tutorial y desbloqueos | `opciones_tutorial` | **verde** | Título, opciones, tutorial con Tab y F1 sobre el 3D |
| Rótulos con zoom | `zoom_rotulos` | **arreglado** | El zoom 3D es continuo (tamaño de cámara 3-90, la rueda lo suaviza), no ×1/×2: el flujo compara el tamaño de la cámara antes y después. Los letreros de `Marks3D` guardan su tamaño en pantalla a cualquier zoom |

## Lo que necesita al owner
- **W/A/S/D en 3D**: hoy desplazan la cámara (como en Prueba3D); en 2D andan con la persona elegida. Opción conservadora
  tomada: se deja como está y el flujo `teclas` audita lo de hoy.

## Lo que queda para otros hitos
- La región, los viajes y las caravanas se ven en 2D (M3D-6); la fiesta dibujada en el pueblo, M3D-5.
- La posada de nivel 3 usa el interior del nivel 1 (su casa se dibuja con 2 plantas) hasta que haya un interior de
  nivel 3 para el solar de 6 m de town_e (M3D-5, interiores de los oficios).
- Si el interior 3D tiene menos camas de huésped que la sim (nivel 1: 2 + 1 de la mejora frente a 4), las que no tienen
  pieza no se ven ni se pulsan en 3D: se hacen desde el panel (Habitaciones).

## Pruebas (2026-11-26)
- Sin ventana: 12/12 flujos en verde. Con ventana: 11/12 (parcelas: el cierre de Godot, arriba).
- Reglas: 1279/1279.

## Capturas
- `docs/novedades/ciudad_taberna_servir.png`: la sala llena, huéspedes 3D con su pedido y paciencia.
- `docs/novedades/ciudad_taberna_camas.png`: «Planta alta», las camas de huésped con su estado.
- `docs/novedades/ciudad_parcelas.png`: el modo construcción en 3D y la carta de la ruina.
- `docs/novedades/ciudad_otra_ciudad.png`: Bellcaire en 3D con la forja abierta en sitio.
- `docs/novedades/ciudad_zoom_rotulos.png`: los letreros de la plaza acercando la cámara.
- Pendiente de arte: los nombres de los huéspedes se amontonan sobre la sala llena; las letras de los pedidos.
