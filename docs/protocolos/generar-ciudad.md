# Generar una ciudad

El constructor de ciudades (`tools/city/`) hace dos cosas: **viste** un mapa por reglas (casas de relleno mirando a la
calle, patios detrás, farolas, barriles, carros, bancos, vallas) y **genera** ciudades nuevas en el mismo formato de
`data/maps/`. Es una herramienta offline: el juego carga el resultado sin código nuevo en el sim.

| Fichero | Qué hace |
|---|---|
| `tools/city/ciudad.py` | La entrada: `vestir`, `validar`, `vista`, `generar` |
| `tools/city/citylib.py` | El modelo del mapa, las reglas del vestido (`dress`) y el validador (`validate`) |
| `tools/city/generator.py` | Los trazados y los pasos del generador |
| `tools/city/preview.py` | La vista previa en PNG (plano + boceto isométrico), sin abrir el juego |
| `tools/city/reglas.json` | Las cifras de las reglas (cada cuántas casillas una farola, qué props van en cada taller…) |
| `tools/city/sprites_ciudad.py`, `fal_ciudad.py` | Los sprites del constructor (farola, valla, casas de espaldas) y su gasto en fal |
| `tools/scenarios/make_city_scenarios.gd` | Un escenario de prueba `<mapa>_start` por cada ciudad generada |

Por qué Python: las herramientas offline del repo ya lo son (`validate_content.py`, `arte.py`, `make_town_e.py`),
no necesita el motor (corre en un segundo), Pillow da la vista previa y una sola implementación de las reglas sirve
para vestir `town_e`, para generar y para validar. El juego solo lee el JSON.

## 1. Generar una ciudad

```bash
python3 tools/city/ciudad.py generar --id town_road --layout calle --seed 1 [--size 40x40] [--start artisan_blacksmith]
/opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_city_scenarios.gd -- --maps=town_road
python3 tools/city/ciudad.py validar town_road
```

- `--layout`: `calle` (pueblo-calle, como town_e), `plaza` (plaza mayor con cuatro calles radiales y una ronda),
  `cruce` (dos caminos que cruzan el mapa, la plaza en una esquina del cruce) o `rio` (villa de río con puente).
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

### Los pasos del generador

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
5. **El mapa**: solares (`buildings` con `origin` y `door`), `spawns` (jugador, mercado, puertas), `stalls`,
   `board`, `town_hall`, `social_points`, `workplaces` (los 16 oficios de town_e en su orden de reparto) y
   `population` (la de town_e, con sus casas nuevas).
6. **El vestido** por reglas (§3) y la **validación** estricta (§2).

## 2. Reglas de coherencia (el validador)

`python3 tools/city/ciudad.py validar [mapa...]` (paso `ciudad` de `tools/qa/run_all.py`). En las ciudades generadas
todo es error; en `town_e` (hecho a mano) lo que su trazado antiguo incumple queda como aviso.

| Regla | Qué mira |
|---|---|
| Nada se solapa | Ninguna casilla en dos solares; puestos y tablón fuera de los solares; cada huella sobre casillas `#` |
| Puertas transitables | La puerta de cada solar es una casilla transitable pegada a su huella |
| Puertas a la calle | La puerta es calle, plaza, camino o puente, o toca una |
| Todo conectado | BFS desde la plaza: llega a cada puerta, servicio, punto social, spawn y oficio, y a toda casilla transitable (sin bolsas de hierba encerradas: el bot wanderer va a cualquiera) |
| Una sola red de calles | Calles, plaza y puente forman una pieza (un camino de tierra nunca corta una calle: donde se cruzan, sigue la calle) |
| Puestos a la plaza | La casilla de servicio de cada puesto está pegada a él y es plaza |
| Farolas cada N | Cada casilla de calle tiene una farola a `lanterns.every` casillas o menos |
| La población cabe | Cada hogar en una casa del mapa distinta, como mucho `house_capacity` por casa, y el total cabe |
| El vestido | Cubre cada `#` libre una sola vez; cada casa de relleno mira a una calle y su sprite y su giro casan con su puerta; ninguna pieza pisa una puerta, un camino (`=`, `,`, `b`), un servicio, un punto social, un spawn ni un oficio; lo mismo para la decoración a mano de `game/visuals/towns/<mapa>.tscn` |
| Puertas en caras ocultas (aviso) | Un edificio del sim con la puerta hacia -fila o -columna y sin escena `<id>_back`: su sprite dibuja la puerta en la otra cara |
| Sin reflejo (aviso) | Una escena de `building_door_face.no_mirror` (carteles con texto: la sastrería) con la puerta en la otra cara visible |

### La orientación de una casa

La cámara ve las dos caras que miran a **+fila** (abajo a la izquierda) y a **+columna** (abajo a la derecha). Con
un sprite que dibuja la puerta en una de ellas salen las cuatro orientaciones:

| La calle queda hacia | Sprite | Reflejado |
|---|---|---|
| +fila | la casa | no |
| +columna | la casa | sí |
| -fila | la casa de espaldas (`<id>_back`) | no |
| -columna | la casa de espaldas | sí |

Las casas de relleno lo hacen con `lot_house_<a..f>` y `lot_house_<a..f>_back` (`tools/city/reglas.json`
`filler.back`). Los edificios del sim, en el juego (`WorldView._door_facing`): `data/view.json`
`building_door_face.faces` dice en qué cara dibuja la puerta cada escena (`row` por defecto, `col` la forja y la
sastrería); si la puerta del mapa está en la otra cara visible se refleja (salvo las de `no_mirror`, cuyo cartel
tiene texto y saldría al revés), y si está en una oculta usa `<escena>_back` si existe (hoy `house_slate_back`,
`house_ochre_back`, `house_tall_back`). El generador pone cada edificio, si puede, donde su puerta cae en una cara
que la cámara ve y que su sprite dibuja (la sastrería, solo con la calle hacia +columna); si no hay sitio así, en la
calle que le toca con aviso.

## 3. Reglas de mobiliario

Las hace `citylib.dress` en este orden; las cifras están en `tools/city/reglas.json`:

1. **Casas de relleno**: en cada manzana libre, lotes de 3×3 donde su frente da a una calle a `street_reach`
   casillas o menos (mejor calle que plaza, mejor plaza que camino), las puertas hacia ella; dos lotes vecinos nunca
   con la misma casa.
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
| Edificios del sim | `buildings/<tipo>` | ✔ | Con la puerta en una cara oculta hace falta `<tipo>_back` (lo lleva el arte, ver §2) |

Cómo se hicieron la farola y las casas de espaldas (fal, `nano-banana-2/edit` con una sola referencia: el sprite
vecino ×4 sobre blanco, y recorte y paleta locales): `tools/city/fal_ciudad.py` y `tools/city/sprites_ciudad.py`;
cada generación con su coste en `tools/city/fal_gasto.json` y `assets/art/MANIFEST.md`. Para una casa nueva de
espaldas: `python3 tools/city/fal_ciudad.py gen --piece back_houses --name <id>_back_v1 --ref <sprite> --prompt
"..."` y `python3 tools/city/sprites_ciudad.py back <letra> <crudo>`.

## Rituales

`python3 tools/city/ciudad.py validar` (0 errores) · `python3 tools/validate_content.py` · `python3 tools/arte.py` ·
pruebas (`--only=test_ciudad`, `--only=test_arte_filler`) · arranque (`zsh tools/qa/boot_check.sh`) · los bots en el
escenario nuevo · la captura `--smoke-script=mapa` (mírala).
