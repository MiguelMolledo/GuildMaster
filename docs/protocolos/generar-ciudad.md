# Generar una ciudad

El constructor de ciudades (`tools/city/`) hace dos cosas: **viste** un mapa por reglas (casas de relleno mirando a la
calle, patios detrás, farolas, barriles, carros, bancos, vallas) y **genera** ciudades nuevas en el mismo formato de
`data/maps/`. Es una herramienta offline: el juego carga el resultado sin código nuevo en el sim.

| Fichero | Qué hace |
|---|---|
| `tools/city/ciudad.py` | La entrada: `vestir`, `validar`, `vista`, `generar` |
| `tools/city/citylib.py` | El modelo del mapa, las reglas del vestido (`dress`) y el validador (`validate`) |
| `tools/city/generator.py` | Los trazados y los pasos del generador |
| `tools/city/organic.py`, `tools/city/ciudades.json` | Las ciudades orgánicas de la región y sus planos (§1b) |
| `tools/city/preview.py` | La vista previa en PNG (plano + boceto isométrico), sin abrir el juego |
| `tools/city/reglas.json` | Las cifras de las reglas (cada cuántas casillas una farola, qué props van en cada taller…) |
| `tools/city/sprites_ciudad.py`, `fal_ciudad.py` | Los sprites del constructor (farola, valla, casas de espaldas) y su gasto en fal |
| `tools/city/sprites_catalog.py` | Exporta `data/building_sprites.json` de los marcadores `Door` de las escenas (y lo comprueba) |
| `tools/city/proponer_puerta.py`, `marcar_puertas.py` | Ayuda de una vez al importar un sprite: propone la puerta; escribe el marcador (`--update` lo reescribe) |
| `tools/city/enchufar_fachadas.py` | Pone las fachadas fal en las escenas de los edificios (frente, obras, dañada) y crea sus `_back` |
| `tools/scenarios/make_city_scenarios.gd` | Un escenario de prueba `<mapa>_start` por cada ciudad generada |

Por qué Python: las herramientas offline del repo ya lo son (`validate_content.py`, `arte.py`, `make_town_e.py`),
no necesita el motor (corre en un segundo), Pillow da la vista previa y una sola implementación de las reglas sirve
para vestir `town_e`, para generar y para validar. El juego solo lee el JSON.

## 1. Generar una ciudad

```bash
python3 tools/city/ciudad.py generar --id town_road --layout calle --seed 1 [--size 40x40] [--start artisan_blacksmith]
    [--households N] [--fields N] [--reach N] [--filler N] [--trees X]
/opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_city_scenarios.gd -- --maps=town_road
python3 tools/city/ciudad.py validar town_road
```

- `--layout`: `calle` (pueblo-calle, como town_e), `plaza` (plaza mayor con cuatro calles radiales y una ronda; en
  mapas de 60 o más, más anillos cada 9 casillas, el primero de calle), `cruce` (dos caminos que cruzan el mapa, la
  plaza en una esquina del cruce), `rio` (villa de río con puente), `aldea` (un camino por la plaza y dos caminos de
  tierra hacia los campos; para mapas pequeños, desde 30×30) o `abadia` (la plaza es el atrio de la abadía, una ronda
  de calle la rodea de cerca y dentro quedan los edificios y huertos; el camino entra por el oeste y sale de tierra
  por el este).
- **Perfil del pueblo** (todo opcional; sin nada, lo de `reglas.json generator`): `--households N` (hogares, una casa
  cada uno: los primeros, los de town_e tal cual; a partir del noveno, otra vez los de town_e con solo `gold`, `rank`
  y `stats`, y el reparto pone apellido, colores, nombres, sexo, edad y aspecto, `docs/contratos/poblacion.md`),
  `--fields N` (campos), `--reach N` (hasta dónde llega el relleno desde la plaza), `--filler N` (manzanas de relleno
  como mucho) y `--trees X` (densidad de árboles). El perfil queda en `"generated".profile` del mapa.
- `--seed`: misma semilla, mismo trazado y mismo tamaño = mismo fichero, byte a byte. El id no cuenta: puedes
  probar en `--out tmp/x` y luego generar con el id bueno.
- `--start` (repetible): de qué inicios salen los solares obligatorios. Sin él, los cuatro del Artesano
  (`player_forge`, `rival_forge`, `workshop_carpentry`, `workshop_masonry`, `workshop_tailor`). La armería
  (`armory`, pública) y el ayuntamiento van siempre. `make_city_scenarios.gd` juega el inicio `artisan_blacksmith`:
  su mapa necesita los solares de ese inicio (los de por defecto los tienen).
- Sale `data/maps/<id>.json` y su vista previa en `reports/ciudad/<id>.png`. Añade el nombre en `i18n/strings.csv`
  (`map.<id>`). El mapa lleva `"generated"` (trazado, semilla, tamaño): así el validador lo trata en modo estricto y
  `make_city_scenarios.gd` le hace su escenario.
- Probarlo: `/opt/homebrew/bin/godot --path . -- --scenario=<id>_start`; bots: `godot --headless --path . -s
  tools/sim_runner.gd -- --scenario=<id>_start --bots=wanderer,idle,smith --days=3 --seeds=5`; capturas:
  `grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot --audio-driver Dummy --always-on-top --path . --
  --smoke-script=mapa --smoke-maps=<id>_start`.
- **No sustituyas `town_e`**: las dianas de `data/targets.json` y los escenarios se ajustaron sobre sus solares.
  `town_e` no se genera: su fuente es `tools/maps/make_town_e.py` (trazado, solares, población y, al final, el
  vestido por reglas). Tras tocar el mapa o las reglas, `python3 tools/maps/make_town_e.py`; el paso `town_e` de la
  QA (`--check`) falla si el fichero y el script no coinciden.

### Los mapas de la región

Cada asentamiento de `data/world/region.json` (`docs/gdd/09b_region.md`) tiene su mapa. La villa es `town_e` (a mano);
los otros cinco son **ciudades orgánicas** (§1b): sus planos están en `tools/city/ciudades.json` y se hacen con
`python3 tools/city/ciudad.py region [id...]`. Bellcaire, Portvell, Peñarroja y Vilablat toman su esqueleto de un
plano dibujado con fal (§1e, `"use": "imagen"`); Montsacre crece del plan (`"procedural"`). Los cuatro mapas de ejemplo (`town_road`, `town_square`,
`town_crossroads`, `town_river`) siguen con los trazados de rejilla de esta sección.

| Asentamiento | Mapa | Estilo | Qué lo define en el plano |
|---|---|---|---|
| Bellcaire (capital) | `region_capital` 80×80 | A + C | Muralla con torres y cuatro puertas, catedral con atrio junto a la plaza, el Daura de 8 casillas al sur con muelles, lonja, aduana, almacenes, grúa y barcos; barrios de mercaderes, menestrales y la vila dentro; dos arrabales fuera (oeste y al otro lado del puente) |
| Portvell (puerto) | `region_port` 48×48 | C | El río de 7 casillas con el muelle a lo largo de la orilla norte, cinco embarcaderos, barcos y barcas, lonja, aduana, tres almacenes, grúa; el astillero en la otra orilla; casas estrechas apretadas en la ribera |
| Peñarroja (mina y cantera) | `region_quarry` 40×40 | B | La sierra al norte (casillas de roca), la boca de la mina, la cantera, tres escombreras y la fundición; un torrente con su puente y un vado |
| Vilablat (aldea) | `region_hamlet` 32×32 | E | Casas sueltas con huerto delante, el arroyo con puente y vado, el molino de agua, dos eras, el pajar y campos grandes con caminos de tierra |
| Montsacre (abadía) | `region_abbey` 36×36 | B | El recinto amurallado con su puerta: iglesia abacial, claustro, hospedería, huerto y estanque; el burgo con la plaza fuera del recinto |

Después de generar, sus escenarios: `/opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_city_scenarios.gd --
--maps=region_capital,region_port,region_quarry,region_hamlet,region_abbey`. Si cambias el tamaño o las casas de un
mapa, cambia también `map_size` y `households` de su asentamiento en `region.json` (el validador lo comprueba).
Todos llevan los solares del inicio del herrero porque su escenario juega `artisan_blacksmith`.

## 1b. Ciudades orgánicas (`tools/city/organic.py`)

Una ciudad orgánica no tiene trazado fijo: su **plano** es un bloque de `tools/city/ciudades.json` y el generador lo
sigue paso a paso (terreno, plaza, calles mayores, muralla, puerto, hitos, calles que crecen, solares del sim, casas,
campos, bosques). Mismo plano y misma semilla, mismo fichero. Las coordenadas son casillas `[columna, fila]`.

```bash
python3 tools/city/ciudad.py region region_port          # una (o todas sin id); --out tmp/x para probar sin tocar data/
python3 tools/city/ciudad.py validar region_port
```

Sale `data/maps/<id>.json` y su vista previa `reports/ciudad/<id>.png` (plano y boceto isométrico con los volúmenes).

### Los parámetros del plano

| Clave | Qué es | Valores |
|---|---|---|
| `size`, `seed`, `households`, `starts`, `style` | Tamaño, semilla, hogares (una casa del sim cada uno), inicios cuyos solares lleva, estilo del GDD 9.2 | `seed` cambia las curvas y el reparto, no el plan |
| `per_house`, `population_max` | Plantillas: vecinos por casa desde el inicio (los que faltan, con rango y atributos de los de town_e; el reparto les pone el resto) y el tope del mapa (por defecto, los que salen) | `per_house` 5 = `data/life/life.json population.per_house`; menos si el bench no lo aguanta |
| `plaza.centre`, `plaza.bulge` | Dónde va la plaza del mercado (la de town_e, 10×12) y cuánto se ensancha de forma irregular | `bulge` 1 (casi rectangular) a 3 (plaza grande y redondeada) |
| `rivers[]` | Ríos y arroyos: `path` (puntos por los que pasa, curva suave), `width` (casillas), `wobble` (cuánto varía la anchura) | Río navegable 6-8; arroyo 2-3 |
| `pond` | Estanque: `at`, `size` | |
| `rock` | La sierra en un borde: `edge` (`north`), `depth`, `wobble`, `spurs` (estribaciones: `at` columna, `depth`, `half`) | |
| `roads[]` | Calles mayores y secundarias con nombre: `path`, `width` (2-2,2 mayor; 1,2-1,6 secundaria), `gate` (la puerta del mapa: `west_gate` y `east_gate` hacen falta), `main` | Al cruzar el agua se hace un puente de piedra (`b`) |
| `lanes[]` | Caminos de tierra (`,`): `path`, `ford: true` hace un vado (`v`) donde cruzan un arroyo | |
| `walls` | Muralla: `centre`, `radius` [rx, ry], `wobble`, `towers_every` (una torre cada N casillas de muro), `tower` (huella), `tower_height`, `from` (casilla desde la que se mide el interior; por defecto el centro) | Se abre donde pasa una calle mayor (las puertas, con sus torres) y termina en la orilla |
| `port` | Puerto: `quay.cols` [desde, hasta], `quay.bank` (`north`/`south`), `quay.width` (el muelle de calle), `piers` (embarcaderos), `pier_len`, `pier_width`, `spacing`, `boats` (barcos amarrados), `boat` (huella), `rowboats` (barcas), `crane` (`height`, `color`) | Los embarcaderos nunca pasan de media anchura: queda canal |
| `landmarks[]` | Hitos (§1c): `type`, `size`, `near` (dónde buscarle sitio), `reach`, `front` (`road`, `water`, `rock`, `any`: a qué da su frente), `front_share`, `rotate`, `on` (casillas que puede ocupar: `.`, y `R` para la mina o la cantera), `inside_wall`/`outside_wall`, `parvis` (casillas de atrio delante), `count`, `height` (px), `color`, `stage` (`early` antes de las calles, `mid`, `late`) | |
| `plots[]` | Huertos en un sitio concreto (el de la abadía): como un hito, pero de campo | |
| `districts[]` | Barrios (§1d): `id`, `centre`, `radius`, `inside_wall`/`outside_wall`, `roof` (color de sus casas), `streets`, `alleys`, `density` | El primero que contiene una casilla se la queda |
| `fields` | Campos fuera de la ciudad: `count`, `cell` (tamaño aproximado de cada campo), `min_size`, `lanes` | Celdas irregulares con un camino alrededor |
| `trees`, `gardens` | Bosque fuera (en manchas) y árboles sueltos en los huertos de dentro | 0-0,3 |

### 1c. Hitos

Un hito es un edificio que define el sitio y que **el sim no lee**: la catedral, la lonja, los almacenes, la grúa, la
mina, la cantera, el molino, el claustro, las torres de la muralla... En el mapa va en `"landmarks"`
(`type`, `origin`, `size`, `height`, `color`, `label`) y sus casillas son `H` (bloqueadas): nada del sim ni del
decor puede pisarlas. En el juego se ve como un bloque isométrico de su huella, su color y su altura, con su nombre
(`i18n` `hito.<type>`) encima. **Para ponerle sprite** basta crear `game/visuals/props/<type>.tscn` (con `Feet` en el
centro de la huella): el juego usa esa escena en vez del bloque genérico (`props/hito.tscn`). Están en
`assets/inventario.json` como `hito_<type>` («falta», con su huella). Los barcos (`"boats"`, sobre el agua) igual,
con `props/boat.tscn` de bloque genérico.

### 1d. Barrios y densidad

Cada barrio crece sus propias calles y se llena con su densidad. Para que el owner pida «más denso» o «más suelto»
se cambian estos números:

| Clave | Qué hace | Denso (Bellcaire dentro) | Suelto (aldea) |
|---|---|---|---|
| `streets.every` | Cada cuántas casillas sale una calle de otra | 6-8 | 8-10 |
| `streets.p` | Probabilidad de que salga | 0,8 | 0,6 |
| `streets.gap` / `clear` | Fondo mínimo de manzana / distancia mínima entre dos calles casi paralelas | 8 / 4 | 6 / 3 |
| `streets.max_len`, `min_len`, `turn`, `axis_bias` | Largo de cada calle, cuánto se curva al avanzar (grados por paso) y cuánto tiende a los ejes (0 libre, 1 recta) | | |
| `streets.width`, `ch` | Anchura (1 callejón, 1,2-1,6 calle) y casilla (`=` calle, `,` tierra) | 1,2 `=` | 1 `,` |
| `alleys` | Igual que `streets`, para los callejones que salen de las calles | `p` 0,35-0,5 | sin |
| `density.fill` | Parte de la fachada a la calle que se construye | 0,95 | 0,5-0,6 |
| `density.lot_sizes` | Tamaños de casa (a lo largo de la calle × fondo); 3×3 tiene sprite, el resto bloque | 2×3, 3×3, 3×2, 2×2, 3×4 | 3×3, 3×2, 2×3 |
| `density.touch` | Casas pegadas (hileras) o con un hueco entre ellas | `true` | `false` |
| `density.backyard` | Filas de patio detrás de cada casa | 1 | 1 |
| `density.setback` | Casillas de huerto entre la casa y la calle | 0 | 1 |
| `density.blocks`, `block_max` | Probabilidad de cerrar con patios una manzana pequeña (hasta `block_max` casillas) | 0,9 / 40 | sin |
| `density.patios` | Probabilidad de que la hierba encerrada entre casas se vuelva patio | 0,5 | sin |

**Pedidos en lenguaje normal → cambio en `ciudades.json`** (luego `ciudad.py region <id>` y los escenarios):

| Pedido | Cambio |
|---|---|
| «Más denso» en un barrio | `density.fill` ↑ (hasta 1), `touch: true`, `blocks` ↑, `streets.every` ↓ |
| «Más suelto» | `fill` ↓ (0,5), `touch: false`, `setback: 1`, `blocks: 0` |
| «Más calles» / «menos calles» | `streets.every` ↓ / ↑, `streets.p` ↑ / ↓ |
| «Calles más torcidas» | `streets.turn` ↑ (14 → 22), `axis_bias` ↓ (0,55 → 0,3) |
| «Manzanas más grandes» | `streets.gap` y `clear` ↑ |
| «Casas más grandes» | `lot_sizes` con 3×4, 4×3 delante |
| «El río más ancho» | `rivers[].width` ↑ (y `port.pier_len` como mucho la mitad menos uno) |
| «Más barcos» / «más muelles» | `port.boats`, `port.rowboats`, `port.piers` ↑, `port.spacing` ↓ |
| «La catedral más grande» o «en otro sitio» | Su `size` / su `near` en `landmarks` |
| «Muralla más grande» | `walls.radius` ↑ (los barrios con `inside_wall` crecen con ella) |
| «Más campos» / «campos más grandes» | `fields.count` / `fields.cell` ↑ |
| «Otra calle hacia el puerto» | Una entrada más en `roads` con `main: false` |

### 1e. Desde un plano dibujado (fal → rejilla → generador)

La forma de una ciudad puede salir de un **plano semántico** visto desde arriba: una imagen en colores planos que
significan algo (`tools/city/paleta_planos.json`: calles gris, plazas beige, agua azul, casas rojo, muralla negro,
campos amarillo, bosque verde oscuro, roca gris pardo, embarcaderos marrón y cada hito su color: iglesia morado,
lonja naranja, almacenes cian, mina magenta, cantera gris muy claro, claustro blanco, molino rosa). La forma la pone
el dibujo y la coherencia el generador.

```bash
python3 tools/city/fal_planos.py gen region_port --name v1 [--count 2]   # fal nano-banana-2, 0,08 USD por imagen
python3 tools/city/desde_imagen.py docs/arte/ciudades_v2/fal/region_port.png --size 48x48   # la rejilla, para mirarla
python3 tools/city/ciudad.py region region_port --variante imagen --out tmp/x                 # probar sin tocar data/
```

1. **El dibujo** (`fal_planos.py`). El prompt de cada ciudad es su bloque `fal` de `ciudades.json` (`brief`: qué
   hay y dónde; `classes`: los colores que puede usar) más la paleta, la regla de colores planos (sin sombras, sin
   texto) y el tamaño de nuestra plaza de mercado en proporción al mapa (la del sim mide 10×12 casillas: si el
   dibujo la hace pequeña, la plantilla se come sus calles). **Mejor solo con texto**: con el boceto anterior de
   referencia el modelo copia la rejilla. Cada llamada queda en `tools/city/fal_gasto.json` y
   `assets/art/MANIFEST.md`; las elegidas, en `docs/arte/ciudades_v2/fal/<mapa>.png`.
2. **La rejilla** (`desde_imagen.py`). Cada píxel va al color más cercano de la paleta; cada casilla a una clase
   por la parte de sus píxeles, con prioridades porque lo fino de un plano no llena nunca una casilla: agua ≥ 0,45,
   muralla ≥ 0,12, un hito ≥ 0,35, embarcadero ≥ 0,22, calle ≥ 0,28, plaza ≥ 0,4; si no, la clase con más
   píxeles.
3. **El esqueleto** (`tools/city/esqueleto.py`, un plan con `"skeleton"` y `"use": "imagen"`). Del dibujo se toman
   el agua, las calles, las plazas, la muralla, los hitos, los campos, el bosque, la roca y dónde hay casas, y se
   limpian:
   - la muralla se cierra a partir del dibujo (la distancia mediana al muro en cada dirección desde su centro),
     acaba en la orilla, se abre donde la cruza una calle (puertas con sus torres) y, si deja dentro suelo al que
     no se llega, se le abre una puerta;
   - los embarcaderos lejos del agua (contornos marrones de las casas) se quitan;
   - los hitos dibujados se colocan antes que nada: su propio rectángulo si tiene el tamaño del plan, si no, el
     tamaño del plan junto a su mancha; la plantilla del mercado (plaza, ayuntamiento, armería) va lo más cerca de la
     plaza dibujada, en tierra;
   - las calles sueltas se unen a la red de la plaza por el camino más corto (cruzando el agua como puente si
     hace falta) o se quitan; dos calles que solo se tocan en diagonal reciben la casilla de al lado; el cauce del
     río se mide columna a columna y se cierra donde el dibujo lo corta; una calle sobre el agua es un puente; un
     puente que no une dos orillas vuelve a ser agua; entre campo y calle queda un arcén de hierba (las farolas);
     las puertas del mapa son las calles que llegan a los bordes (si no llega ninguna al oeste o al este, se tiende
     una).
4. **El generador** pone lo demás con sus reglas de siempre: los solares del sim (prefiriendo donde el dibujo tiene
   casas), las casas de relleno con la puerta a la calle (en las casas del dibujo y hasta `reach` casillas
   alrededor; los campos pegados al pueblo pasan a huertos), los barcos junto a los embarcaderos dibujados, la grúa,
   el decor y la validación (0 errores).

**El bloque `skeleton`**: `image`, `types` (clase del dibujo → tipo de hito, p. ej. `{"church": "abbey_church"}`),
`districts` (cada uno con `when`: `inside`/`outside` de la muralla, `dense`/`loose` según lo apretado del dibujo, o
`any`; `roof` y `density` como en §1d), `reach` (cuántas casillas alrededor de las casas dibujadas pueden llevar
casas, 3), `walls` (`towers_every`, `tower`, `tower_height`), `boats`, `boat`, `rowboats`, `crane`.

**Qué sale de cada uno** (2026-11-04, comparadas una a una en la galería «Planos de Valldaura v2»):

| Ciudad | Se queda | Por qué |
|---|---|---|
| Bellcaire | imagen | La muralla cerrada siguiendo el dibujo, calles en abanico hacia la plaza, la catedral junto a ella, el muelle con lonja y almacenes, el arrabal al otro lado del puente |
| Portvell | imagen | Más denso y ocupa el mapa; calles curvas bajando al muelle |
| Peñarroja | imagen | La mina al final de su camino, la cantera y las escombreras donde las puso el dibujo |
| Vilablat | imagen | Los campos grandes e irregulares de la aldea |
| Montsacre | procedural | En 36×36 la plantilla del mercado, los talleres y el recinto no caben como en el dibujo: se perdían el claustro y la hospedería |

**Límites**: el modelo tiende a ciudades redondas de calles radiales (anillo y radios); la plaza del sim, de
10×12, ocupa mucho en los mapas pequeños y borra lo que el dibujo tenía allí; las líneas finas de parcela del dibujo
se pierden (lo que es bueno: las parcelas las pone el generador).

### 1f. Reglas de lo orgánico

Qué hace que una villa medieval no parezca una cuadrícula, sacado de planos reales (Girona, Besalú, Montblanc,
Peratallada, Pals, Santillana, Ávila, Carcassonne, Rothenburg, Brujas, Lübeck) y de la morfología urbana (Conzen:
calles, parcelas y edificios), y cómo lo traduce el constructor:

| Regla | En los planos reales | En el constructor |
|---|---|---|
| Las calles siguen el terreno y los caminos viejos | La calle mayor es el camino que ya pasaba (Santillana: dos calles que se juntan ante la colegiata); en ladera, las calles van por curvas de nivel y las cuestas las cortan (Montblanc sube hacia Santa María; Girona, la Força Vella) | `roads` en curva desde las puertas; `rock` y el río desvían el crecimiento; `axis_bias` y `turn` para que las calles se curven sin ir en escalera |
| La plaza está en el cruce o ante la iglesia | El mercado nace donde se cruzan los caminos o delante de la iglesia (Montblanc, la plaza Mayor porticada; Ávila, el Mercado Chico dentro y el Mercado Grande fuera de la puerta) | La plaza del mercado y la catedral con su atrio (`parvis`) juntas; las calles mayores llegan a sus esquinas |
| Manzanas largas y estrechas | Parcelas en tira (*burgage plots*) con la casa a la calle y el huerto detrás; en una calle sola, espina de pez | `lot_sizes` estrechos (2×3, 2×4) a lo largo de la calle, `backyard`, patios que cierran la manzana (`blocks`) |
| Cruces en ángulo no recto y jerarquía | Calle mayor, calles que salen de ella y callejones; las calles se encuentran como pueden (Rothenburg, el Plönlein: una calle que se abre en dos) | Ramas a 62-118° de su calle, `streets` y `alleys` por barrio; nunca dos calles casi paralelas más cerca que `clear` |
| La muralla marca el borde y el arrabal queda fuera | La muralla cierra el núcleo (Ávila, 2,5 km, nueve puertas; Montblanc, más de veinte torres); fuera, junto a las puertas, el arrabal de oficios y huertas; a veces las casas son la muralla (Peratallada) | `walls` con puertas donde pasan las calles y torres; barrios `inside_wall` apretados y `outside_wall` sueltos junto a las puertas |
| La ciudad crece en anillos | Rothenburg y Carcassonne: la muralla vieja queda dentro y la nueva más fuera | Varios barrios concéntricos con distinta densidad (se puede pedir una ronda donde estaba la muralla vieja) |
| El río ordena el puerto | Brujas: los canales y el Markt junto al agua, la grúa del muelle; Lübeck: calles que bajan perpendiculares al Trave, almacenes en la orilla y pasajes (*Gänge*) dentro de las manzanas | El muelle a lo largo de la orilla, embarcaderos perpendiculares, almacenes y lonja con su frente al agua, calles de bajada al muelle |
| El puente es un sitio | Besalú: el puente fortificado es la entrada; el arrabal nace al otro lado | Un puente por calle mayor; el barrio de la otra orilla suelto |

Fuentes: [Atherstone (plaza junto a la iglesia)](https://www.ourwarwickshire.org.uk/?p=40563),
[parcelas en tira de Hungerford](https://www.hungerfordvirtualmuseum.co.uk/index.php/10-themes/954-burgage-plots),
[Leighton Buzzard](https://bedsarchives.bedford.gov.uk/CommunityArchives/LeightonBuzzard/MedievalLeightonBuzzard.aspx),
[Montblanc](https://www.femturisme.cat/ca/pobles/montblanc),
[pueblos medievales de Cataluña (Peratallada, Besalú)](https://naciodigital.cat/societat/pobles-medievals-catalunya.html),
[la muralla de Ávila](https://muralladeavila.com/en/history/the-mediaeval-walls-12th-15th-centuries),
[Brujas, centro histórico](https://geographyworlds.com/blog/old-town-bruges-unesco-world-heritage/),
[el Plönlein de Rothenburg](https://explorial.com/de/sights/rothenburg-plonlein-de/).

### 1g. La escalera de las calles en diagonal

En una rejilla, una calle en diagonal es una escalera de casillas. En el juego, `GroundLayer` la suaviza
(`data/view.json` `ground_corners`): en una casilla de hierba, tierra o campo cuyos dos vecinos de lados que se
juntan en una esquina son calle, pinta un triángulo de calle sobre esa esquina (`fill` = qué parte de sus dos lados
cubre: 0,75). La escalera se lee como una cinta continua y las esquinas de las manzanas salen achaflanadas. Solo es
pintado: la rejilla, los caminos y el sim no cambian. La vista previa hace lo mismo en su boceto isométrico.

### Los pasos del generador de rejilla (§1)

1. **Calles y plaza** (el trazado): las calles principales (`=`, dos de ancho, salen del mapa por las puertas), las
   secundarias (`=` de uno o caminos de tierra `,`) y la plaza de 10×12.
2. **La plaza**: la plantilla de town_e (cinco puestos y el tablón dando a la plaza, el pozo, bancos, corros y
   dados), el ayuntamiento al norte (puerta a la plaza, en su cara visible) y la armería al oeste.
3. **Parcelas a lo largo de las calles**: un rectángulo libre cuyo frente entero es calle y que deja una casilla de
   hierba alrededor (callejones: ahí van las farolas). La puerta va siempre en el lado de la calle, en el centro del
   frente.
4. **Edificios por prioridad**: los talleres de los inicios con la puerta en una cara visible que su sprite dibuje,
   en las calles principales si cabe (si no, en una secundaria antes que de espaldas), lo más cerca de la plaza; las
   casas de vecinos (una por hogar de la población) en las secundarias; los campos fuera, tocando un camino; el resto
   del frente, manzanas de relleno (`#`) hasta `generator.town_reach` casillas de la plaza; un estanque si no hay
   río; árboles en la hierba lejos de todo; la hierba que queda encerrada (sin camino a la plaza) se vuelve bosque.
   Dos solares que ningún inicio construye juntos (sus inicios no se cruzan) comparten hueco, como en town_e: el
   segundo va pegado a la calle del primero si cabe y su escena dibuja la puerta hacia esa calle; si no, hueco propio.
   El vestido de reserva de un hueco se hace una vez, para el solar mayor.
5. **El mapa**: solares (`buildings` con `origin` y `door`), `spawns` (jugador, mercado, puertas), `stalls`,
   `board`, `town_hall`, `social_points`, `workplaces` (los 16 oficios de town_e en su orden de reparto) y
   `population` (la de town_e, con sus casas nuevas).
6. **El vestido** por reglas (§3) y la **validación** estricta (§2).

### 1h. Puntos de reunión y rondas de la guardia (04f 4.24)

Después del decor, `citylib.add_life` añade a cada mapa lo que le falte (el generador, `ciudad.py region` y
`tools/maps/make_town_e.py` lo llaman solos; para un mapa ya hecho, `python3 tools/city/ciudad.py reunion [mapa…]`):

- **Puntos de reunión** (`social_points` con kinds nuevos, 2-5 huecos transitables, nunca en una casilla protegida
  ni bajo el decor): `well` (junto al oficio `well`), `atrium` (delante de la iglesia: entre `church_a` y
  `church_b`), `tavern` (la puerta de un sitio `tavern_inn`), `washhouse` (la orilla más cercana a la plaza),
  `bridge` (el puente más cercano), `gate` (uno por puerta, a dos casillas dentro) y `square` (cuatro casillas de la
  plaza abierta). Para poner uno a mano: un `social_point` con su `id` (snake_case), su `kind` y sus `slots`.
- **Rondas** (`patrols`: `[{id, tiles}]`): `patrol_main` de puerta a puerta pasando por la plaza y `patrol_plaza`
  por sus esquinas. Cada casilla, transitable y alcanzable desde la plaza (el validador lo comprueba).
- `population_max` (opcional): el tope de vecinos del mapa con la vida encendida (si no, 5 por casa hasta 32). Las
  ciudades de la región lo traen del plan (`per_house` × casas, o su `population_max`): empiezan llenas.

H7 solo usa `bench`, `chat` y `dice`: un punto nuevo no cambia el día de H7 ni sus dianas.

### 1i. Parcelas: solares, ruinas y negocios en venta (04 §4.9.1)

`tools/city/plots.py` reparte por reglas (`reglas.json` → `plots`) la lista `plots` de cada ciudad de `plots.maps`
(las seis: town_e y las cinco de la región). Va después de la vida y nunca encima de ella. **El sim no la lee:** la
rejilla, los solares y los puntos de reunión no se mueven, así que ninguna diana cambia (lo prueba
`tests/test_plantillas_parcelas.gd`). Comprar, construir, restaurar y reconvertir son de H6.

| Estado | De dónde sale | Cómo se ve (`game/world/plot_layer.gd`) |
|---|---|---|
| `lot` dentro | Un solar de relleno (casa decorativa sin `site`, casillas `#`) que deja de ser casa; si no hay, hierba dentro | Tierra (`props/plot_ground`) y una estaca en cada esquina (`props/plot_stake`) |
| `lot` fuera | Hierba o campo junto a un camino, fuera de la villa | Igual |
| `ruin` | Un solar de relleno dentro (el mejor situado primero: la ganga); sin ninguno, hierba con calle delante | Muros rotos de alturas distintas (`props/ruin_wall`) y escombro (`props/ruin_rubble`) |
| `business` | Cada taller y casa del mapa (el solar mayor de su huella) | El cartel «Se vende» (`props/for_sale_sign`) junto a la puerta, solo si `for_sale` y el edificio es de una familia IA en esa partida |

- Cada parcela: `id`, `state`, `side` (`inside`/`outside`: con muralla, respecto a ella —en Montsacre, el recinto
  de la abadía—; sin muralla, a `inside_reach` casillas de lo edificado), `zone` (`rustic`/`production`/`housing`),
  `origin`, `size`, `front` (la casilla desde la que se entra: la puerta en un negocio), `location` y, en un negocio,
  `site` y `for_sale`.
- **Situación** (`location` 0-1): pesos de `plots.location` sobre la distancia andando a la plaza, la calle mayor
  (calle y plaza), las puertas y el paso de gente (los paseos de cada puerta y cada portal a la plaza) [balance].
- **Mínimos que comprueba el validador** en las ciudades de `plots.maps`: 2 solares dentro (`min_inside`), 2 fuera
  (`min_outside`), de 1 a 3 ruinas y la válvula de 4.9 (`valve`: 2 parcelas libres —solares y ruinas— de cada zona).
  Además, que ninguna pise un edificio, una puerta, un servicio, un punto social, una casilla de oficio o una casa de
  relleno, que no se solapen, que se entre desde la plaza, que su lado sea el que dice y que las rústicas vayan fuera.
- La decoración de las fiestas (`FestivalLayer.sites`) no se pone en solares ni ruinas, como no se pone en la
  decoración del mapa (el pozo), los puestos, el tablón, las puertas ni los puntos de reunión.
- En venta: `for_sale` talleres, los mejor situados que no estén en `never_for_sale` (la forja del jugador y la del
  rival del herrero).
- Repartirlas otra vez: `python3 tools/city/ciudad.py parcelas [mapa…]` (las ciudades de `ciudades.json` se
  regeneran enteras, el mismo mapa; town_e: `python3 tools/maps/make_town_e.py`). Captura:
  `--smoke-script=plantillas --smoke-moments=ruina,solar,fuera,venta`.

## 2. Reglas de coherencia (el validador)

`python3 tools/city/ciudad.py validar [mapa...]` (paso `ciudad` de `tools/qa/run_all.py`). En las ciudades generadas
todo es error; en `town_e` (hecho a mano) lo que su trazado antiguo incumple queda como aviso.

| Regla | Qué mira |
|---|---|
| Nada se solapa | Ninguna casilla en dos solares, salvo **solares alternativos**: uno dentro de la huella de otro (H12: el rival del oficio del jugador en el solar de la forja), y entonces ningún inicio de ese mapa puede construir los dos; puestos y tablón fuera de los solares; cada huella sobre casillas `#` |
| Puertas transitables | La puerta de cada solar es una casilla transitable pegada a su huella |
| Puertas a la calle | La puerta es calle, plaza, camino o puente, o toca una |
| Todo conectado | BFS desde la plaza: llega a cada puerta, servicio, punto social, spawn y oficio, y a toda casilla transitable (sin bolsas de hierba encerradas: el bot wanderer va a cualquiera) |
| Una sola red de calles | Calles, plaza y puente forman una pieza (un camino de tierra nunca corta una calle: donde se cruzan, sigue la calle) |
| Puestos a la plaza | La casilla de servicio de cada puesto está pegada a él y es plaza |
| Farolas cada N | Cada casilla de calle tiene una farola a `lanterns.every` casillas o menos |
| La población cabe | Cada hogar en una casa del mapa distinta, como mucho `house_capacity` por casa, y el total cabe |
| El vestido | Cubre cada `#` libre una sola vez; cada casa de relleno mira a una calle y su sprite y su giro casan con su puerta; ninguna pieza pisa una puerta, un camino (`=`, `,`, `b`), un servicio, un punto social, un spawn ni un oficio; lo mismo para la decoración a mano de `game/visuals/towns/<mapa>.tscn` |
| El agua se cruza por puentes o vados | En las ciudades orgánicas, las casillas del cauce de cada río (`"generated".rivers`: su curva y su núcleo) son agua, puente, vado o embarcadero; cada puente y cada vado une dos orillas |
| Muelles | Cada embarcadero (`m`) toca el agua y la tierra, y cada casilla suya está sobre el agua |
| Barcos en el agua | Cada barco (`"boats"`) solo sobre casillas de agua y sin cruzarse con otro |
| Hitos | Cada hito (`"landmarks"`) sobre casillas `H` y dibujado por el decor; toda casilla `H` es de un hito; ningún solar, puesto, servicio ni pieza del decor pisa su huella |
| Puertas en caras ocultas (aviso) | Un edificio del sim con la puerta hacia -fila o -columna y sin escena `<id>_back`: su sprite dibuja la puerta en la otra cara |
| Marcadores de puerta | Cada escena de `game/visuals/buildings/` y cada casa de relleno tiene su `Door`, y `data/building_sprites.json` dice lo mismo (`sprites_catalog.check`) |
| Puerta dibujada = puerta del mapa | Para cada edificio del sim, el lado y la casilla de la puerta que dibuja su escena (con el reflejo o la vista de espaldas que elija el juego) son los de `door` del mapa; en las casas de relleno, el lado es el de su calle y la casilla de delante de la puerta es transitable |

### Puertas: el marcador `Door`

Dónde está la puerta lo dice la escena, no la imagen. Cada escena de edificio, casa o variante
(`game/visuals/buildings/*.tscn`, `game/visuals/props/lot_house_*.tscn`) lleva un `Marker2D` **«Door»** en el umbral
de la puerta dibujada, con estos metadatos:

| Metadato | Qué es |
|---|---|
| `side` | La cara de la huella: **SW** (mira a +fila, abajo a la izquierda), **SE** (+columna, abajo a la derecha), **NE** (-fila) y **NW** (-columna); las dos últimas no las ve la cámara |
| `tile` | La casilla de la puerta desde el origen de la huella (fuera de la huella, en ese lado) |
| `footprint` | La huella para la que está dibujado el sprite |
| `mirror` | Si puede reflejarse (no lleva texto; hoy todos salvo el ayuntamiento) |
| `back` / `front` | La misma escena vista desde el otro lado (`""` si no hay) |

- **El reflejo no lleva marcador propio**: x → -x cambia columnas por filas, así que SW ↔ SE y NE ↔ NW, y la casilla
  sale de la posición reflejada sobre la huella del mapa. Con un sprite y su vista de espaldas salen las cuatro
  orientaciones: como está, reflejado, de espaldas, de espaldas reflejado.
- **El catálogo**: `data/building_sprites.json` (no se edita a mano) se exporta de los marcadores con
  `python3 tools/city/sprites_catalog.py`; `--check` sale con 1 si no casan (lo usa el validador) y
  `tests/test_ciudad_sprites.gd` lo comprueba contra las escenas cargadas. El generador y el validador leen el
  catálogo; el juego (`WorldView._door_facing`, `VisualPaths.door_of`) lee el marcador de la escena que dibuja.
- **Un sprite nuevo**: `python3 tools/city/proponer_puerta.py buildings/<id> --sheet reports/ciudad/puertas.png`
  propone el umbral (el hueco oscuro de la fachada que toca la base) y dibuja la propuesta: solo ayuda, falla a
  menudo. Mira la hoja, pon el `Door` en Godot (o en `tools/city/marcar_puertas.py`, que escribió los primeros) con
  su posición y metadatos, y exporta el catálogo.
- **Otros accesos** (el portalón de un patio, la entrada de un campo, el sitio de un carro): el exportador recoge
  cualquier escena con un `Door`; hoy no hace falta ninguno más (el portalón de la carpintería es su `Door`; las
  farolas y los props se apoyan en su `Feet`).

Todos los edificios del sim tienen su vista de espaldas (`<id>_back`, fachadas fal de `assets/art/buildings/fal/`
puestas por `tools/city/enchufar_fachadas.py`, y las casas de vecinos `house_slate_back`, `house_ochre_back`,
`house_tall_back`); el ayuntamiento también elige frente o espalda por su casilla de servicio. Las fachadas fal llevan
sus estados en dos nodos ocultos, `LookConstruction` y `LookDamaged`: `WorldView._apply_looks` pone su textura en el
`Sprite` mientras el edificio está en obras (una mejora en curso) o dañado (mantenimiento sin pagar). La de escala B
queda en `SpriteEscalaB` para volver atrás. El generador pone cada edificio donde una de sus
vistas dibuja la puerta en una cara que la cámara ve, y escribe en el mapa la casilla de puerta que dice su marcador.

## 3. Reglas de mobiliario

Las hace `citylib.dress` en este orden; las cifras están en `tools/city/reglas.json`:

1. **Casas de relleno**: en cada manzana libre, lotes de 3×3 donde su frente da a una calle a `street_reach`
   casillas o menos (mejor calle que plaza, mejor plaza que camino), con la vista cuyo `Door` mira a ella; dos lotes
   vecinos nunca con la misma casa.
2. **Patios**: lo que queda de la manzana (detrás o al lado de las casas), un tema por manzana (huerto o patio de
   trabajo, `data/view.json` `filler.yard_themes`).
3. **Farolas** (`lanterns`): primero en los cruces, luego cada `every` casillas a lo largo de las calles, en la
   hierba o un patio pegado a la calle, desplazadas `curb` hacia el bordillo; nunca en una calle, una puerta ni sus 8
   vecinas.
4. **Talleres** (`workshops.props`): junto a la puerta de cada tipo, contra la pared si la puerta está en una cara
   visible, si no en la hierba de al lado.
5. **Puestos** (`stalls`): un carro (o lo que diga `props`) detrás o al lado de cada puesto, nunca en su casilla de
   servicio ni pegado a ella.
6. **Bancos de la plaza** (`plaza_benches`): `count` bancos en el borde de la plaza, separados `spacing`.
7. **Vallas** (`fences`): un tramo en cada borde de un campo que no da a otro campo ni al agua, con un portillo cada
   `gate_every` bordes de camino y en las casillas de los oficios.

Todo es determinista: el único «azar» es `citylib.tile_hash` de la casilla. Tras tocar las filas o los solares de un
mapa: `python3 tools/city/ciudad.py vestir <mapa>` (reescribe solo su `"decor"`).

El juego lo dibuja en `WorldView._add_decor`: los lotes (`house`, `yard`, `single`) en el centro de sus casillas y
registrados como prop de cada una; las piezas (`lantern`, `prop`, `fence`) en el centro de su casilla más `off`
píxeles. Un lote cuyas casillas ocupa un edificio de esta partida se salta y esas casillas vuelven al relleno de
antes (`_add_filler`). La decoración a mano de `game/visuals/towns/<mapa>.tscn` sigue funcionando encima.

## 4. Añadir un trazado

1. En `tools/city/generator.py`, una función `layout_<nombre>(rng, w, h) -> Plan` que dibuje en `p.g` las calles
   (`=` principales con `main=True`, `,` o `=` secundarias), el río (`w`) y el puente (`b`) si los hay, ponga la
   plaza con `_plaza_centre(p, rng, cx, cy)` y apunte las puertas del mapa en `p.gates` (`west_gate` y `east_gate`
   hacen falta: dan los oficios de las puertas). La calle principal debe cruzar la plaza por sus filas +5 y +6 o
   llegar a ella.
2. Regístrala en `LAYOUTS` y en esta página.
3. Genera tres semillas con `--out tmp/x`, mira las vistas previas y valida: 0 errores. Si un solar no cabe, el
   generador lo dice (`no cabe ...`): más calles o un mapa mayor.

## 5. Añadir una regla de mobiliario

1. Sus cifras en un bloque nuevo de `tools/city/reglas.json` (con su `_doc`).
2. El paso en `citylib.dress`, después de los que ya ocupan sitio (las farolas van antes que los props). Usa
   `open_spot` (casilla libre, no protegida) y `add_prop(kind, id, tile, toward, frac, flip)`; nada sobre
   `m.protected()` ni sobre un camino.
3. Si la pieza necesita una escena nueva, `game/visuals/props/<id>.tscn` (copiada de `lantern.tscn`: `Feet`, `Top`,
   `Sprite`), su entrada en `assets/inventario.json` y `python3 tools/uids.py --fix`.
4. Si hay una regla que comprobar, añádela a `citylib.validate`.
5. `python3 tools/city/ciudad.py vestir town_e`, `validar`, la captura `--smoke-script=mapa` y la prueba
   `tests/test_ciudad_decor.gd`.

## 6. Sprites que necesita cada trazado

| Pieza | Escena | Todos | Notas |
|---|---|---|---|
| Suelo: hierba, calle, plaza, tierra, campo | `assets/art/tiles/` | ✔ | Los cruces se resuelven solos (cada casilla es un rombo entero) |
| Casas de relleno y de espaldas | `props/lot_house_<a..f>[_back]` | ✔ | 192 px, escala B, base en `Feet` |
| Patios, pozo | `props/yard_*`, `props/well` | ✔ | |
| Farola | `props/lantern` | ✔ | 32×64 |
| Barriles, cajas, sacos, carro, banco | `props/barrel`, `crate`, `grain_sack`, `cart`, `bench` | ✔ | |
| Valla | `props/fence` | ✔ (campos) | Un tramo dibujado `\`, reflejado para `/` |
| Árboles | `props/tree*` | ✔ | `data/view.json` `prop_variants.tree` |
| Agua, orilla, puente | `tiles/water*`, `tiles/bridge*` | `rio` (y el estanque) | |
| Edificios del sim | `buildings/<tipo>` | ✔ | Cada uno con su `Door`; con la puerta en una cara oculta hace falta `<tipo>_back` (lo lleva el arte, ver §2) |

Cómo se hicieron la farola y las casas de espaldas (fal, `nano-banana-2/edit` con una sola referencia: el sprite
vecino ×4 sobre blanco, y recorte y paleta locales): `tools/city/fal_ciudad.py` y `tools/city/sprites_ciudad.py`;
cada generación con su coste en `tools/city/fal_gasto.json` y `assets/art/MANIFEST.md`. Para una casa nueva de
espaldas: `python3 tools/city/fal_ciudad.py gen --piece back_houses --name <id>_back_v1 --ref <sprite> --prompt
"..."` y `python3 tools/city/sprites_ciudad.py back <letra> <crudo>`.

## Rituales

`python3 tools/city/ciudad.py validar` (0 errores; incluye `sprites_catalog.py --check`) · `python3 tools/validate_content.py` · `python3 tools/arte.py` ·
pruebas (`--only=test_ciudad` cubre decor, mapas y marcadores; `--only=test_arte_filler`) · arranque (`zsh tools/qa/boot_check.sh`) · los bots en el
escenario nuevo · la captura `--smoke-script=mapa` (mírala).
