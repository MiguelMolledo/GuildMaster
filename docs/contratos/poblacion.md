# Contrato · Población variada (reparto generado)

Rama `poblacion` (2026-11-03). Código: `sim/meta/cast.gd` (`Cast`); datos: `data/cast.json`; pruebas:
`tests/test_poblacion_cast.gd`. Diseño: GDD 4.10.9 (identidad), 4.11.1 (población), 4.16 (partida nueva).

## Qué decide el reparto y qué no

| Decide (cosmético) | No toca (balance) |
|---|---|
| Nombres de pila y apellido de casa: protagonista (propuesta), rival, competidores, vecinos | Atributos del protagonista, del rival y de los competidores |
| Edad del rival (34-36), de los competidores (33-44), de sus parejas (31-41) y de los vecinos (18-30) | Edad del protagonista (la del inicio) |
| Sexo cuando el dato no lo fija (en town_e todos lo fijan) | Sexo del rival, de los competidores y de sus parejas |
| Pelo, piel, retrato base `{id, type}` del pool, colores de ropa de las familias IA | Oro, deuda, edificios, encargos, perfiles IA, oficios |
| Personalidad de los vecinos: carisma, empatía y destreza ±1 | Rango, oficio y el resto de atributos de los vecinos |

**Orden de edad.** Los cargos van al mayor de cada casa con título (`Offices.setup`) y el heredero es el hijo
mayor: las edades de los vecinos se sortean, pero se reparten en el orden de edad de los datos (empates por id; un
empate nuevo se deshace con un día dentro del año de nacimiento, `birth_offset`, que no cambia la edad). Así los
mismos vecinos ocupan los mismos cargos con cualquier reparto.

## Modos y semilla

- `choices.cast`: `"random"` (por defecto; la partida del jugador) o `"fixed"` (los nombres, edades y tonos de
  `data/starts` y `data/maps`, idéntico al reparto de antes: pruebas, escenarios, guiones de captura y `sim_runner`).
- `choices.cast_seed`: semilla del reparto. Por defecto `Cast.sub_seed(world_seed, 0)`. Es una **sub-semilla**: el
  botón «Otra familia» de Partida nueva sube la tirada (`Cast.sub_seed(world_seed, tirada)`) y la semilla del mundo no
  cambia (eventos, mercado y el resto de tiradas siguen siendo los de esa semilla).
- Cada tirada del reparto sale de su propio flujo (`semilla del reparto | mapa | clave`): no mueve ninguna otra tirada.
- `sim_runner`: `--cast=fixed` por defecto (las dianas se fijaron con él); `--cast=random` para medir con repartos
  generados (con `--tag`, para no pisar los informes oficiales).

## Estado (guardado v14)

- Raíz `cast: {mode, seed, map}`.
- `character.visual.portrait: {id, type}`. `id`: el retrato del pool (`<sexo>_<franja>_<tipo>_<nn>`), elegido con la
  semilla del reparto entre los candidatos de su sexo, franja y tipo (sin ninguno, el `fallback` del índice y después
  `commoner`), sin repetir cara dentro del reparto mientras el pool tenga. `type`: su tipo social (`artisan`,
  `commoner`, `merchant`, `noble`, `clergy`, `guard`, `scholar`, `farmer`, `rogue`): la familia del jugador por su clase
  (`portraits.classes`: artisan → artisan, patron → farmer, scholar → scholar, rogue → rogue), el rival y los
  competidores `artisan`, vecinos y recién llegados `commoner`; un hijo toma el del padre. Se guarda aparte porque el
  id puede venir de un `fallback` (una niña `scholar` lleva un `merchant`) y la franja siguiente se elige del tipo.
- Migración 13 → 14: `cast = {mode: "fixed", seed: 0, map}` (los nacimientos y llegadas de una partida vieja siguen
  como antes) y a cada personaje `{id: "", type}` por su familia (el guardado no tiene el pool): la vista enseña uno
  de su tipo mientras tanto y `Cast.grow_portraits` le da su id en el siguiente cambio de año.

## Después del inicio

- Nacimientos (`Births.born` → `Cast.newborn`) y recién llegados (`Population._arrive` → `Cast.newcomer`): con reparto
  fijo, la tirada de H7/H8 (`data/family.json names`, mismas claves); con reparto generado, un nombre de
  `data/cast.json` que no lleve nadie vivo y tonos de `look`. En los dos, un retrato del pool que no lleve nadie vivo.
- Al cambiar de año (`Population.step` → `Cast.grow_portraits`), quien cambia de franja recibe un retrato de la nueva,
  el mismo `nn` si lo hay (el pool tiene del 01 al 06 en todas las combinaciones).

## Retratos (vista)

Pool: `assets/art/portraits/index.json` versión 1 y su README (566 retratos, 81 combinaciones de 6 a 12 caras).

- El sim solo depende de `data/`: `data/portraits.json` (ids, sexo, franja, tipo y `fallback`, sin rutas) se exporta
  del índice con `python3 tools/art/portraits_catalog.py` cada vez que cambia el pool, y `tools/validate_content.py`
  falla si no coinciden (como `data/building_sprites.json` de ciudad). Lo lee `Catalog.portrait_pool`. Las rutas,
  solo `VisualPaths.portrait_file(id, size)` con el índice: la cara de 32 para `size` 32, el busto de 64 para 64.
- Franjas (`data/cast.json portraits.stages`, las del pool): child ≤11 (menos de 6 también), youth 12-17, adult
  18-44, mature 45-59, elder 60+. El validador comprueba que casan con el índice y que existe `commoner` en todas.
- `Identity.of` pasa `portrait: {id, type, stage, seed}`; sin id (partida vieja hasta su año siguiente),
  `VisualPaths.portrait(type, stage, sexo, seed)` elige uno estable del índice con el mismo orden de reserva.
- Canas: el dibujo no las trae; `Identity.greyed` mezcla el pelo con gris según la franja (`data/view.json
  portraits.greying`: mature 0,3, elder 0,75).
- Zonas: el shader solo pinta los píxeles marcados; si una toca o un casco tapan el pelo, o la ropa es fija, no se
  tiñen (el `recolor` del índice lo cuenta, el juego no lo necesita).
- La barba es la región de pelo de los colores clave (4.10.9): toma el tono del pelo.

## Varias ciudades

`Cast.generate(catalog, start, map, mode, seed)` lee la población del mapa que recibe (casas y miembros, en orden) y su
id entra en las claves: otro mapa, u otra ciudad de la misma partida, da otra gente con la misma semilla. Un miembro
de un mapa puede traer solo `rank` y `stats`: nombre, sexo, edad y aspecto los pone el reparto (también en modo fijo).
Con 74 nombres de hombre, 71 de mujer, 94 apellidos generales y 27 de oficio, el mapa EA (30-40 NPC, 5 familias
rivales) cabe sin repetir; con la baraja gastada se repite.

## Plantillas: empezar en cualquier ciudad

`NewGame.from_start(..., choices.city)`: el asentamiento de `data/world/region.json` donde empieza la partida (su
mapa sustituye al del inicio; el resto del inicio es el mismo). Sin `city`, o con la ciudad del propio inicio
(Vilarrasa para los cuatro del Artesano), la partida es la de siempre, byte a byte: las dianas no se mueven. Rechazos:
`unknown_city` y `city_lacks_site` (al mapa le falta un solar del inicio; hoy las seis ciudades llevan los de los
cuatro oficios). El reparto se genera con el id del mapa de esa ciudad (otra gente con la misma semilla) y la
propuesta de nombre de Partida nueva también. `meta.city` guarda la elegida (solo informativo).

Las ciudades de la región empiezan llenas: el plan de `tools/city/ciudades.json` trae `per_house` (vecinos por casa;
los que pasan de los de town_e solo llevan rango y atributos) y el mapa su `population_max`. Partida nueva:
«Dónde empiezas»; línea de órdenes: `--start-city=<id>`. Pruebas: `tests/test_plantillas_ciudades.gd`; sonda de vida
por ciudad: `tools/life/plantillas_probe.gd`; capturas: `--smoke-script=plantillas`.
