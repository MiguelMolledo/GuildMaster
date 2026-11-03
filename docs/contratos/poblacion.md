# Contrato · Población variada (reparto generado)

Rama `poblacion` (2026-11-03). Código: `sim/meta/cast.gd` (`Cast`); datos: `data/cast.json`; pruebas:
`tests/test_poblacion_cast.gd`. Diseño: GDD 4.10.9 (identidad), 4.11.1 (población), 4.16 (partida nueva).

## Qué decide el reparto y qué no

| Decide (cosmético) | No toca (balance) |
|---|---|
| Nombres de pila y apellido de casa: protagonista (propuesta), rival, competidores, vecinos | Atributos del protagonista, del rival y de los competidores |
| Edad del rival (34-36), de los competidores (33-44), de sus parejas (31-41) y de los vecinos (18-30) | Edad del protagonista (la del inicio) |
| Sexo cuando el dato no lo fija (en town_e todos lo fijan) | Sexo del rival, de los competidores y de sus parejas |
| Pelo, piel, retrato base `{type, variant}`, colores de ropa de las familias IA | Oro, deuda, edificios, encargos, perfiles IA, oficios |
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
- `character.visual.portrait: {type, variant}`. `type`: la clase de la familia del jugador (`artisan`…), `rival`
  (rival y competidores), `townsfolk` (vecinos y recién llegados); un hijo toma el del padre. `variant` en
  `[0, portraits.variants)`.
- Migración 13 → 14: `cast = {mode: "fixed", seed: 0, map}` (los nacimientos y llegadas de una partida vieja siguen
  como antes) y a cada personaje su retrato: tipo por su familia, variante por el número de su id.

## Después del inicio

- Nacimientos (`Births.born` → `Cast.newborn`) y recién llegados (`Population._arrive` → `Cast.newcomer`): con reparto
  fijo, la tirada de H7/H8 (`data/family.json names`, mismas claves); con reparto generado, un nombre de
  `data/cast.json` que no lleve nadie vivo y tonos de `look`.

## Retratos (vista)

- `Identity.of` añade `portrait: {type, stage, variant}`; la etapa sale de la edad de ahora (cambia al envejecer):
  `data/cast.json portraits.stages` (child ≤7, youth ≤15, adult ≤44, mature ≤54, elder).
- `VisualPaths.portrait(type, stage, female, variant, size)`: `assets/art/portraits/<type>_<stage>_<m|f>[_<n>]`
  (`_32` para 32 px), la variante `variant % nº de variantes que existan`; si no hay, los tipos de
  `data/view.json portraits.fallback`; sin ninguno, el greybox. Mientras los retratos de producción no estén en main,
  sirven los 8 del piloto en `assets/art/portraits_pilot/` (mismos nombres; se borra la carpeta al llegar los buenos).
- La barba es la región de pelo de los colores clave (4.10.9): toma el tono del pelo.

## Varias ciudades

`Cast.generate(catalog, start, map, mode, seed)` lee la población del mapa que recibe (casas y miembros, en orden) y su
id entra en las claves: otro mapa, u otra ciudad de la misma partida, da otra gente con la misma semilla. Un miembro
de un mapa puede traer solo `rank` y `stats`: nombre, sexo, edad y aspecto los pone el reparto (también en modo fijo).
Con 74 nombres de hombre, 71 de mujer, 94 apellidos generales y 27 de oficio, el mapa EA (30-40 NPC, 5 familias
rivales) cabe sin repetir; con la baraja gastada se repite.
