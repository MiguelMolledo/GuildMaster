## 9. Ciudades: estilos de referencia y cómo replicarlos con PixelLab

### 9.1 Qué hace que una ciudad medieval se lea como "compleja"

1. **Jerarquía**: un centro claro (plaza, iglesia, ayuntamiento) y barrios que se distinguen por función y riqueza.
2. **Calles orgánicas**: no una cuadrícula; calles que se estrechan, plazuelas, callejones, una calle mayor más ancha.
3. **Densidad con variedad**: casas adosadas que comparten muros, alturas distintas (1-3 plantas), tejados de colores y materiales distintos por barrio.
4. **Bordes**: muralla o río que contiene la ciudad, puertas, arrabales fuera de los muros, campos alrededor.
5. **Vida en la calle**: puestos, carros, barriles, ropa tendida, pozos, letreros, humo de chimeneas, gente.
6. **Capas de detalle**: suelo con transiciones (adoquín → tierra → hierba), charcos, musgo, sombras.

### 9.2 Seis estilos de ciudad

| Estilo | Planta | Rasgos visuales | Referencias | Encaje en Guild Renew |
|---|---|---|---|---|
| **A. Villa de mercado orgánica** (centroeuropea) | Calles radiales que llegan a una plaza de mercado irregular con iglesia y ayuntamiento | Entramado de madera (*fachwerk*), tejados rojos, soportales en la plaza | The Guild 2 y 3, Kingdom Come: Deliverance (Rattay), Manor Lords | **Recomendado para el mapa EA.** Encaja con las 6 zonas del GDD y con la plaza del mercado ya diseñada. |
| **B. Ciudad amurallada en colina** | Anillos concéntricos subiendo hacia el castillo/catedral; calles en curva de nivel | Muros de piedra, escaleras, contraste entre barrio noble arriba y artesano abajo | Carcassonne, Stronghold, Tristram (Diablo) | Variante del EA si se quiere el barrio noble "arriba". La altura es cara en isométrico 2D (rampas, muros). |
| **C. Ciudad de río y puerto** (hanseática) | La ciudad se estira a lo largo del río; muelles, puente, almacenes; mercado junto al agua | Casas altas y estrechas con piñón escalonado, ladrillo, grúas de madera, barcas | Lübeck/Brujas, Anno 1404, The Guild 2 (mapas con puerto) | Muy buena para la zona **Puerto/río** del GDD y para el comercio entre ciudades (post-EA). |
| **D. Bastida en cuadrícula** | Cuadrícula regular planificada con plaza porticada central | Ordenada, legible, fácil de zonificar en parcelas | Bastidas del sur de Francia, Caesar III / Pharaoh (lógica de parcelas) | La más fácil de construir y de jugar (parcelas claras), pero menos "orgánica". Útil para un segundo mapa. |
| **E. Pueblo-calle** (*Straßendorf*) | Una calle larga con casas a ambos lados y campos detrás | Rural, granjas, huertos, cercas | The Settlers, Stardew Valley (Pelican Town), Graveyard Keeper | Ideal para la **rebanada vertical**: mapa pequeño, barato de producir, legible. |
| **F. Ciudad densa de fantasía** | Organica pero exagerada: puentes entre casas, voladizos, torres torcidas | Saturada, mucha verticalidad | Eastward, Octopath Traveler, Sea of Stars | Inspiración para detalles (voladizos, carteles), no para el plan entero: rompe el tono "histórico". |

Referencias de juegos en 2D isométrico con sprites y ciudad densa que conviene estudiar: **Caesar III / Pharaoh / Zeus** (cómo se ocupan parcelas y se leen los barrios), **The Settlers II/III** (sprites isométricos medievales), **Age of Empires II** (lectura de edificios a distancia), **Graveyard Keeper** (paleta y estilo objetivo), **Kingdoms and Castles** y **Townscaper** (cómo unas pocas piezas modulares dan mucha variedad).

### 9.3 Cómo producirlas con PixelLab

**Estrategia recomendada: kits modulares + edificios clave únicos.**

1. **Edificios clave únicos** (`create_map_object`, 1 gen cada uno): ayuntamiento, iglesia, tribunal, taberna, forja, tiendas del mercado, molino. Es lo que el jugador reconoce. 3 estados por edificio (normal, obras, dañado) y variantes de fachada por nivel.
2. **Casas de relleno con kit** (`create_building_kit`, 10-25 gen por kit): un kit por estilo de barrio (entramado artesano, piedra noble, ladrillo del puerto, madera rural) con muros, esquinas, puertas, ventanas, tejados y piñones. Se montan en Godot en **variantes de casa** (2×2, 2×3, 3×3; 1-3 plantas) combinando piezas, con un script que las compone y las hornea a una textura por variante. Así salen 30-50 casas distintas de 4 kits.
3. **Suelos** (`create_tiles_pro`, `create_path_tiles`): adoquín de plaza, adoquín de calle, tierra, hierba, barro, agua, con transiciones. 16 variantes por hoja para romper la repetición.
4. **Props** (`create_map_object` 1 gen, o gratis con `pixelart_workbench`): puestos, carros, barriles, sacos, pozo, fuente, bancos, farolas, letreros, ropa tendida, cercas, árboles.
5. **Efectos gratis** (`vfx_workbench`): humo de chimenea, chispas de forja, antorchas, agua.
6. **Muralla y puertas**: con `create_building_kit` (tramos, torres, puerta) si se elige el estilo B o un borde amurallado.

**Coherencia de estilo** (PixelLab no garantiza una referencia de estilo compartida entre 30+ edificios en `create_building_kit`): fijar una **biblia de estilo** en `docs/style/biblia.md` (como en Wizards) con prompts base por barrio, paleta (9.6), láminas de 9.5, parámetros (`view`, `outline`, `shading`, `detail`) y 3-5 imágenes ancla; usar `background_image` en `create_map_object` cuando haga falta encajar con lo existente; pasar todo por `reduce_colors` a la paleta del juego; revisar con `frame_check.py`.

**Presupuesto orientativo** para el mapa EA (estilo A con borde de río y zona de puerto C):

| Bloque | Cantidad | Generaciones aprox. |
|---|---|---|
| Edificios clave (28 tipos × 3 estados) | ~84 | ~85-120 |
| Kits de casas por barrio | 4-5 kits | ~60-125 |
| Hojas de suelo y caminos | 6-8 | ~80-160 |
| Props | 40-60 | ~40-60 |
| Muralla, puerto, puente | 2 kits + 10 objetos | ~30-60 |
| Efectos | 15-20 | 0 |
| **Total exteriores** | | **~300-525** |

**Interiores** (kit modular, 4.6.4) [estimación]:

| Bloque | Cantidad | Generaciones aprox. |
|---|---|---|
| Kit de interior: suelos y paredes (madera, piedra, entramado), puerta, ventanas, chimenea | 2-3 hojas + ~10 piezas | ~30-50 |
| Mobiliario genérico (mesa, estantería, barril, cofre-almacén, mostrador, cama, banco) | ~20 | ~20-25 |
| Mejoras visuales genéricas reutilizables (estantería llena, literas, comedor, tapiz, alfombra, candelabro, caja fuerte, cerradura, escaparate) | ~15 | ~15-20 |
| Puestos propios de cada oficio (horno, yunque, telar, horno de pan…) | 18 oficios × 2-3 | ~45-60 |
| Variantes de puesto por mejora de Producción/Calidad | 18 oficios × ~2 | ~35-45 |
| Efectos de interior (fuego, vapor, chispas) | 10-15 | 0 (`vfx_workbench`) |
| **Total interiores** | | **~145-200** |

Solo para el MVP (Forja, Armería del mercado y vivienda) hacen falta ~40-60. **Total EA (exteriores + interiores): ~450-725 de las 2.000 mensuales.** La variación de personajes por paleta (4.10.9) no gasta generaciones.

### 9.4 Plan de prueba cuando haya créditos (a partir del 2026-11-15)

1. **Exploración en fal.ai** (no gasta PixelLab): hecha el 2026-11-01, ver 9.5. El owner aceptó el 2026-11-01 la propuesta como provisional (D10: A + C para el EA, E para la rebanada); la Gate definitiva es tras el paso 4.
2. **Prueba de kit** (~50 gen): 1 kit de entramado + 1 hoja de adoquín + 1 de tierra/hierba + 10 props. Componer en Godot un **barrio de 12×12 casillas** con 8-10 casas generadas por combinación.
3. **Comparar** con 3-4 edificios únicos de `create_map_object` en la misma escena: ¿se ven del mismo juego?
4. **Captura y decisión**: hoja de contacto + captura del barrio en el cuaderno; el owner decide estilo y método antes de producir el resto.
5. **Producción por barrios**, un subgrim por barrio, cada uno con su presupuesto y su fila en el MANIFEST.

### 9.5 Láminas de concepto generadas (fal.ai, 2026-11-01)

Seis láminas con Nano Banana Pro (`scripts/tools/generate_concept.py --model nanopro`), un prompt base común (16-bit SNES, isométrico 2:1, paleta de tierras cálidas, contorno negro) y la planta de cada estilo. Están en `assets/concept/ciudades/<estilo>/<estilo>.png`, con su prompt en `prompts.log`. Son **concepto**, no sprites: la perspectiva no siempre es 2:1 exacta y no se pueden recortar para el juego.

| Lámina | Qué enseña | Qué copiar |
|---|---|---|
| `A_villa_mercado` | Plaza irregular de adoquín con puestos, iglesia gótica y ayuntamiento porticado; casas de entramado apretadas; calles que se abren a la plaza. | El centro del mapa EA: proporciones de la plaza frente a las casas, soportales, mezcla de tejado rojo con alguno verde. |
| `B_amurallada_colina` | Anillos de muralla, castillo y catedral arriba, terrazas con escaleras, arrabal y mercado fuera de la puerta. | El borde amurallado con puerta y el arrabal exterior. La colina en sí es cara en 2D isométrico. |
| `C_rio_puerto` | Muelles de madera, grúa, barcas, puente de piedra en arco, casas hanseáticas de ladrillo con piñón escalonado. | La zona Puerto/río del GDD y un segundo kit de casas (ladrillo) que distingue el barrio. |
| `D_bastida_cuadricula` | Plaza porticada cuadrada con mercado cubierto, parcelas regulares, campos y muralla alrededor. | Lectura de parcelas: es la que mejor enseña al jugador dónde se puede construir. |
| `E_pueblo_calle` | Calle larga de tierra y adoquín, forja con fuego visible, capilla, pozo, huertos, frutales, campos y cercas. | **La rebanada vertical**: escala pequeña, la Forja como protagonista, huertos y cercas como relleno barato. |
| `F_fantasia_densa` | Voladizos, torrecillas, pasarelas entre casas, carteles colgados, ropa tendida, noria. | Detalles de vida (carteles de oficio, ropa tendida, noria del molino) sin la exageración vertical. |

**Decisión provisional (D10, 2026-11-01):** A + C para el mapa EA (plaza central orgánica, río con puerto al sur), E para la rebanada vertical, y los detalles de F como props. La Gate definitiva se mantiene tras la prueba de PixelLab (9.4).

### 9.6 Paleta y reglas de arte (se conservan)

- Pixel art 16-bit SNES, isométrico 2:1, personajes de 48 px, tiles de 64×32, contorno negro de un color, sombreado medio.
- **Paleta base (tierras cálidas):** marrones, tostados, terracota, verde bosque, gris piedra, dorado, rojo oscuro, azul cielo. **Paleta secundaria (otoñal):** gris oscuro, púrpura profundo, oro apagado, verde bosque — para noche, intrigas, zona del Pícaro, tribunal.
- Edificios de 192 px: filtro Nearest, escala 1,6 (ratio edificio:personaje ≈ 4,5:1). Con D2 (escalado ×2 entero) la escala 1,6 deforma los píxeles: pendiente D17.
- **Colores clave de personaje** (4.10.9): pelo, piel, ropa principal y ropa secundaria usan colores reservados que no aparecen en ningún otro sitio del sprite, para que el shader los cambie. Se fijan en `docs/style/biblia.md`.
- **UI medieval:** marco de madera con remaches, fondo pergamino. Madera `#5c3a1e`, remaches `#8a8a7a`, pergamino `#d4b896`, sección oscura `#2a1f14`, filete dorado `#c8a84e`, slot vacío `#1a1209`, positivo `#7ec87e`, negativo `#c85050`.
