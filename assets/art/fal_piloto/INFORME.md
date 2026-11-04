# Piloto de arte con fal.ai

> 2026-11-03 · rama `arte-fal` · gasto **1,24 USD** de un tope de 3 · galería: `assets/art/fal_piloto/galeria.html`
> (artifact «Piloto de arte fal»). Nada entra en el juego: solo candidatos en `assets/art/fal_piloto/<pieza>/final/`.

Preguntas: (1) qué arte que no es sprite animado sale ya con fal con calidad de juego; (2) si fal sirve para sprites
estáticos y animados o hay que esperar a PixelLab (renueva el 15-nov).

**Respuesta corta:** (1) retratos, pantallas, ilustraciones de evento y de carta salen ya con calidad de juego;
iconos y fachadas también, con un repaso. (2) Para sprites estáticos (fachadas, props, iconos) fal sirve con un
retoque. Para los animados, no: la animación espera a PixelLab.

## 1. Gasto

| Pieza | Generaciones | USD |
|---|---|---|
| Retratos (8 personas + 1 rejilla de prueba con nano) | 1 × nano · 2 × nano-banana-2 · 17 × image2pixel | 0,211 |
| Pantalla de título (alba y noche) | 2 × nano-banana-2 · 2 × image2pixel | 0,161 |
| Eventos (guerra regional, fiesta popular) | 2 × nano-banana-2 · 2 × image2pixel | 0,161 |
| Iconos (sierra, arcón, estatua y acero en una imagen) | 1 × nano-banana-2 · 4 × image2pixel | 0,081 |
| Fachada de la Sastrería | 2 × nano-banana-2 · 1 × nano-banana-pro · 3 × image2pixel | 0,311 |
| Paseo de 4 fotogramas | 2 × nano-banana-2 · 1 × nano-banana-pro · 3 × image2pixel · 2 × birefnet | 0,313 |
| **Total** | 15 imágenes, 33 llamadas de proceso | **1,24** |

El detalle por llamada está en `gasto.json`. image2pixel y birefnet se cobran por segundo: cada llamada se apunta con
su tiempo total (cola incluida), así que la cifra es una cota alta. Precios de la API de fal de hoy:
nano-banana 0,0398 · nano-banana-2 0,08 · nano-banana-pro 0,15 · image2pixel 0,00017/s · birefnet 0,000575/s.

## 2. Veredicto por categoría

| # | Pieza | Veredicto | Por qué |
|---|---|---|---|
| 1 | Retratos 64 / 32 | **Sirve** | Cuatro retratos por imagen (rejilla 2×2), con el mismo fondo, encuadre y luz. La 2ª tanda, que lleva la 1ª como referencia, sale igual. Con image2pixel a escala 8, el retrato de 64 queda limpio y con contorno. A **32** se leen la edad, el género, el pelo y la barba si se recorta solo la cara (el busto entero no se lee); los rasgos finos se pierden. nano (0,04) también vale, aunque sale algo más pictórico; nano-banana-2 mantiene mejor el contraste. |
| 1b | Identidad 4.10.9 | **Sirve con retoque** | Se pidió la ropa en rojo de familia con ribete dorado; después `fal_procesar.py key` codifica las cuatro regiones como `personajes_guild.py` (alfa 254 y región en el azul). Pelo, piel, ropa principal y secundaria cambian bien con tres familias. Fallan dos cosas: la barba no entra como pelo, y labios y cuello caen como ropa roja. Hay que ajustar las reglas por retrato o repasarlo a mano. Pedir la ropa en colores planos y muy distintos de la piel ayuda. |
| 2 | Fondo del título 960×540 | **Sirve** | La ciudad al alba deja libre el tercio de arriba para el logotipo. La noche se hizo con /edit sobre el alba y sale la misma ciudad. Reducida a 480×270 con la paleta de image2pixel y escalada ×2 entera, se ve nítida. |
| 3 | Ilustraciones de evento | **Sirve** | Propongo **240×135** para el libro y las cartas (caben en una carta de 380 con margen) y **192×108** para el aviso emergente. Con el título como referencia, el estilo de las dos casa. Se leen a 240 porque se pidieron con pocas formas grandes. |
| 4 | Iconos 32 | **Sirve con retoque** | Salen cuatro por imagen (0,02 USD por icono), limpios y legibles. Frente a los de Guild Renew son más planos y de contorno más grueso. La estatua queda pequeña en su casilla y el acero sale más grande que `iron_ingot`. Hay que igualar el tamaño y el contorno con `pixelart_workbench` (gratis). A 16 no se probó: para listas, mejor PixelLab o repaso a mano. |
| 5 | Fachada de la Sastrería | **Sirve con retoque** | Con **solo** la armería de referencia respeta la proyección 2:1, el suelo de rombo y la altura. Con dos referencias (armería y casa) se fue a una torre. Pro sale más limpia, pero casi calca el volumen de la armería; nano-banana-2 es más propia. El cartel lleva unas tijeras y ninguna letra. Falta repasar el borde y la sombra, y no se probaron los estados de obras y dañado. |
| 6 | Paseo de 4 fotogramas | **No sirve** | El personaje se parece al vecino y su rejilla nativa da 41-49 px, cerca de los 51 del juego. Pero los fotogramas no forman un ciclo: dos poses casi iguales, la altura cambia de un fotograma a otro (41-49 px) y el giro de la diagonal varía entre fotogramas. Pro tampoco lo arregla. La transparencia tiene solución: con fondo blanco plano el recorte local queda exacto; el verde deja motas tras pixelar; birefnet deja ~20.000 píxeles semitransparentes por hoja y hay que umbralizarlos. Lo que falla es la coherencia entre fotogramas. |

## 3. Flujo recomendado

1. **Modelo:** nano-banana-2/edit para todo. nano-banana-pro (0,15) solo para la pose normal de un edificio clave
   cuando la proyección importe más que la variedad, porque calca mejor la referencia. nano (0,04) para tantear
   composiciones.
2. **Referencias:** una sola por encargo, la más cercana a lo que se pide. Con dos, el modelo las mezcla. Retratos:
   la primera rejilla buena es la referencia de todas las siguientes. Pantallas y eventos: el título al alba.
   Fachadas: la fachada del juego de la misma categoría, ampliada ×4 con vecino más cercano. Iconos: 8 de
   Guild Renew ampliados ×4.
3. **Pedir en rejilla 2×2:** cuatro retratos o cuatro iconos por imagen dividen el coste entre cuatro y salen
   iguales entre sí.
4. **Fondo plano** (blanco para sprites, casi negro para retratos) y recorte local por inundación
   (`fal_procesar.py`). birefnet no hace falta con fondo plano.
5. **Pixelado:** image2pixel mejor que la reducción local. Detecta la rejilla, conserva el contorno y el contraste;
   la reducción local con caja ablanda caras e iconos. Lo mejor de cada uno: image2pixel con `scale` fijo cuando la
   medida es divisor exacto (retratos 512 → 64 a escala 8). Para pantallas y eventos, que no lo son, Pillow con caja
   a la medida y la **paleta de image2pixel**. Cuesta unos 0,001 USD por imagen.
6. **Repaso:** `pixelart_workbench` (lint, contorno) y, para personajes, codificar los colores clave.

Scripts: `tools/art/fal_piloto.py` (genera con tope de gasto y apunta en `gasto.json`),
`tools/art/fal_procesar.py` (rejilla, fondo, reducción, colores clave), `tools/art/fal_piloto_build.py` (procesa
todo), `tools/art/fal_piloto_galeria.py` (galería).

## 4. Sprites animados: no

Hoy fal no saca un ciclo de paseo coherente. Arreglar fotograma a fotograma cuesta más que esperar al 15-nov.
PixelLab anima partiendo del personaje (`animate_character`, 8 direcciones, misma figura) y es lo que ya usan
todos los personajes del juego. fal sí vale para una **pose fija** (retrato, carta, ilustración) y para sprites
estáticos con repaso.

## 5. Presupuesto para la lista completa (con fal, nano-banana-2)

Los retratos se cuentan por **arquetipo**, no por persona: el intercambio de paleta (4.10.9) pone el pelo, la piel y
los colores de familia, así que un mismo retrato sirve para toda una familia.
Etapas: niño (0-7), escuela y aprendiz (8-15), adulto (16-44), maduro (45-54) y anciano (55+), según `data/family.json`.
Se cuenta medio intento más por pieza para repetir lo que salga mal (×1,5) y el doble en iconos.

| Grupo | Cuántos | De dónde | Imágenes | USD |
|---|---|---|---|---|
| Retratos · familia del jugador | 5 etapas × 2 géneros × 4 clases = 40 (MVP: solo Artesano, 10) | GDD 4.2.5, 4.22 | 10 rejillas × 1,5 | 1,20 |
| Retratos · empleados | adulto y maduro × 2 = 4 | 4.4 | 1 × 1,5 | 0,12 |
| Retratos · vecinos (30-40 NPC) | 3 etapas × 2 géneros × 2 caras + 2 niños = 14 | 4.11.1 | 4 × 1,5 | 0,48 |
| Retratos · rivales (5 familias) | cabeza y pareja propios = 10 (el herrero rival de H3 ya hecho) | 4.21 | 3 × 1,5 | 0,36 |
| Retratos · cargos y únicos | alcalde, juez, alguacil, recaudador, inspector, concejal, capitán, dignatario, cura = 9 | 4.12, 4.13 | 3 × 1,5 | 0,36 |
| Eventos y estaciones | 10 eventos (4.13) + 4 estaciones | 4.13 | 14 × 1,5 | 1,68 |
| Pantallas | título (alba y noche ya hechas), 3 de carga y 3 finales (sin heredero, Alcalde, cinco generaciones) | docs/ui/02, 4.17 | 6 × 1,5 | 0,72 |
| Cartas | boda, nacimiento, muerte, juicio y elección (+ título y sucesión, opcionales) | docs/ui/mecanicas | 7 × 1,5 | 0,84 |
| Iconos que faltan | sierra y acero (ya candidatos) + ~15 de UI (reputación, menú, guardar, cargar, mazo, urna, campaña, parcela, mapa, campana, velocidad, cofre, escudo, propuesta, nacimiento) + 5 blasones + 4 burbujas de emoción ≈ 24 | docs/ui/00 §7, 03 §2, inventario | 6 rejillas × 2 | 0,96 |
| Fachadas | 28 tipos × 3 estados = 84 (normal con la fachada de su categoría como referencia; obras y dañado por /edit sobre la normal) | GDD 9 | 28 × 2 + 56 × 1,5 | 11,20 |
| Pixelado y recorte | ~250 llamadas a image2pixel | — | — | ~0,30 |
| **Total** | | | | **~18 USD** |

- Con Pro para la pose normal de las 28 fachadas: 28 × 2 × 0,15 = 8,40 en vez de 4,48, unos **22 USD** en total.
- Solo el **MVP** (Artesano, vecinos, empleados, herrero rival, eventos, pantallas, cartas, iconos y las fachadas
  del MVP: forja, armería, sastrería, casas y ayuntamiento, unas 8 × 3): unos **8 USD**, de los que 3,20 son fachadas.
- No entran los iconos nativos de 16 px ni las animaciones: esos son de PixelLab.

## 6. Pendiente del owner

- Elegir entre la versión Pro y la de nano-banana-2 de la Sastrería y decidir si sustituye a `building_roperia`.
  Ninguna entra en el juego sin su visto bueno.
- Medidas de las ilustraciones: 240×135 en carta y libro, y 192×108 en el aviso. Falta decidir si van en
  docs/ui/00.
- Retratos del HUD a 32: con recorte de cara, como el piloto, o con el busto entero, que no se lee.
