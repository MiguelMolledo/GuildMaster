# Arte con fal · producción del 2026-11-03

Retratos, eventos, estaciones, cartas y pantallas hechos con fal tras el piloto (`assets/art/fal_piloto/INFORME.md`).
Gasto: **5,51 USD** de un tope de 8 en retratos e ilustraciones y **2,13 USD** en la tanda extra de iconos y
fachadas (sin tope) (filas en `assets/art/MANIFEST.md`; detalle por llamada en
`assets/art/fal_piloto/gasto.json`, `tanda: produccion`). Todo está en estado `sprite` en `assets/inventario.json` y
**sin cablear** en escenas: lo decide la integración de UI.


> [!NOTE]
> **Dónde vive cada cosa.**
> - **En git**, solo lo final: `assets/art/portraits/`, `assets/art/illustrations/`, los iconos, `assets/art/buildings/fal/`.
>   Además, `assets/art/fal_piloto/gasto.json`, los informes (este y `assets/art/fal_piloto/INFORME.md`), la galería
>   ligera del piloto y los scripts.
> - **Fuera de cualquier repo**, todo lo demás, con la misma estructura de carpetas: crudos, mapas de regiones, pixelados
>   de image2pixel, celdas, referencias, vistas sin codificar y galerías de producción. Están en
>   `$GUILDMASTER_ARTE_CRUDOS`, que por defecto es `~/Code/GuildMaster-arte-crudos/` y tiene `fal_piloto/` y
>   `fal_produccion/`.
> - Los scripts `tools/art/fal_*.py` leen y escriben ahí a través de `tools/art/fal_rutas.py`.
> - Sin esa carpeta se puede usar todo lo final, pero no reprocesar sin volver a pagar las generaciones.

## Retratos · `assets/art/portraits/`

80 tipos de personaje. Cada uno tiene `<id>.png` (64×64, busto, para fichas y cartas) y `<id>_32.png` (32×32, cara,
para el HUD y el árbol). Fondo transparente: el color de fondo lo pone el marco (`docs/ui/mecanicas/familia.md`).

Los ids siguen el patrón `<grupo>_<etapa>_<m|f>[_<n>]`:

- **Grupos.**
  - `artisan`, `patron`, `scholar` y `rogue`: la familia del jugador según su clase (10 cada uno).
  - `worker`: empleados (4).
  - `townsfolk`: vecinos (16; adultos y maduros con dos caras, `_1` y `_2`).
  - `rival`: cabeza y pareja de cinco familias rivales (`rival_adult_m_<n>` y `rival_adult_f_<n>`, n = 1 a 5).
- **Etapas** (`data/family.json`): `child` (0-7), `youth` (8-15), `adult` (16-44), `mature` (45-54) y `elder` (55+).
- **Cargos y personajes únicos**, por su id: `mayor`, `judge`, `priest`, `constable`, `tax_collector`,
  `market_inspector`, `councillor`, `captain` (el del encargo), `dignitary` (visita) y `foreigner` (forastero).

**Identidad de familia (GDD 4.10.9).** Los retratos van codificados igual que los sprites de personaje
(`tools/art/personajes_guild.py`): alfa 254, región en el azul y brillo relativo en el rojo. Se pintan con
`game/visuals/characters/identity_swap.gdshader` y los mismos uniformes `hair`, `skin`, `primary` y `secondary`.

| Región | Azul | Qué cubre |
|---|---|---|
| Pelo | 50 | Pelo, barba, bigote y cejas |
| Piel | 100 | Cara, labios, orejas, cuello y manos |
| Ropa principal | 150 | Túnica, vestido, sayo o capa |
| Ropa secundaria | 200 | Cuello, ribete, pañuelo, toca, capucha o chaleco |

El resto (ojos, contorno, mandil y correas de cuero, sombreros, joyas) conserva su color. En los cargos y únicos solo
se marcan el pelo y la piel: su ropa es la del cargo.

Para la integración:

- **Ancianos.** El shader pinta el pelo con el tono de la persona. Para que un anciano salga canoso, el juego le pasa
  un `hair` gris o blanco; el dibujo no lo fuerza.
- **Elegir retrato.** Por grupo (clase de la familia, empleado, vecino o rival), etapa según la edad y sexo. Entre
  `_1` y `_2` decide la semilla de la persona. Esa elección es una regla de `game/` y no va en `data/`, que no lleva
  rutas.
- **Sin cable todavía.** `game/visuals/characters/portrait.tscn` sigue en greybox: falta poner el sprite con el
  material del shader.

Cómo se hicieron:

1. `tools/art/fal_retratos.py gen` pide 18 rejillas 2×2 con `nano-banana-2/edit`. La única referencia es la rejilla
   buena del piloto. Para que el juego la sustituya, la ropa se pidió en el rojo y el dorado por defecto de la familia.
2. Por cada rejilla, un segundo `/edit` devuelve su **mapa de regiones**: el mismo dibujo en colores planos, magenta
   para el pelo, amarillo para la piel, cian para la ropa principal y verde para la secundaria. Cuesta 0,08 USD más
   por rejilla. Hubo que repetir el mapa de tres celdas en las que salió otra cara o faltaba ropa
   (`mascara_celda --solo <id>`).
3. `tools/art/fal_retratos_proc.py` hace el resto:
   - pixela con image2pixel: escala 8 para el busto y 12 para el recorte de cara;
   - alinea la rejilla de píxeles con el mapa;
   - vota la región de cada píxel;
   - extiende la ropa a los vecinos de color parecido que el mapa dejó cortos;
   - quita el fondo y codifica los colores clave.

   Las vistas sin codificar, para revisar, están en `retratos/natural/`.

## Ilustraciones · `assets/art/illustrations/`

| Qué | Ids | Medidas |
|---|---|---|
| Eventos globales (`data/events.json`, también los 3 desactivados) | `event_famine`, `event_epidemic`, `event_war`, `event_good_harvest`, `event_festival`, `event_religious_feast`, `event_dignitary_visit`, `event_riot`, `event_political_crisis`, `event_discovery` | 240×135 y `<id>_192.png` (192×108, aviso) |
| Estaciones | `season_spring`, `season_summer`, `season_autumn`, `season_winter` (la misma vista en las cuatro) | 240×135 y 192×108 |
| Cartas | `card_wedding`, `card_birth`, `card_death`, `card_trial`, `card_verdict`, `card_election`, `card_title` | 240×135 |
| Pantallas | `screen_title_dawn`, `screen_title_night` (luna movida a la izquierda para dejar sitio al logotipo), `screen_loading_1`, `screen_loading_2`, `screen_saves`, `screen_ending_victory`, `screen_ending_extinction` | 960×540, dibujadas a 480×270 y dobladas ×2 entero |

`tools/art/fal_ilustraciones.py gen` genera cada pieza con una sola referencia: la lámina del título al alba o la
pieza de la que deriva (las estaciones salen de la primavera). `proc` reduce cada pieza a su medida con caja y la
paleta de image2pixel. La guerra, la fiesta y el título al alba vienen del piloto. Las pantallas de título llevan su
vista previa con el logotipo del kit en `ilustraciones/vista/`; ese fichero no es el asset.

## Iconos · tanda extra (sin tope)

21 iconos de 32 con su versión de 16 en `small/`, hecha con la `half()` de `tools/art/derivar_guild.py`.

| Qué | Ids y rutas | Estado |
|---|---|---|
| Objetos en greybox o que faltaban | `icon_saw`, `icon_steel`, `icon_chest`, `icon_cabinet`, `icon_cart_wheel`, `icon_ashlar`, `icon_grindstone`, `icon_trough`, `icon_millstone`, `icon_statue` → `assets/art/icons/<objeto>.png` | Sustituyen al placeholder en su ruta: el juego los carga por id, así que ya se ven. |
| UI que faltaban (docs/ui/00 §7) | `ui_icon_gavel`, `ui_icon_ballot_box`, `ui_icon_reputation`, `ui_icon_menu`, `ui_icon_save`, `ui_icon_load`, `ui_icon_parcels` → `assets/art/ui/icons/icon_<nombre>.png` | Sin cablear. |
| Burbujas de emoción (GDD 4.11.5) | `bubble_emotion_grateful`, `_offended`, `_angry`, `_scared` → `assets/art/ui/bubbles/emotion_<emoción>.png` | Su escena (`game/visuals/bubbles/`) sigue con el greybox. |

Cómo se hicieron (`tools/art/fal_iconos.py`):
- Rejillas 2×2 con una sola referencia: 8 iconos buenos del juego (armadura, barril, lingote, tablas, leña, piedra,
  mandil y espada) ampliados ×4. Las burbujas llevan de referencia las 6 burbujas del juego.
- Cada icono se pide sobre una rejilla de 32, con volumen y contorno oscuro de 1 px.
- image2pixel a escala 16 lo deja exacto a 32×32. Después se oscurece el borde de la silueta donde haga falta, como
  en Guild Renew.
- La piedra de afilar salió ilegible y se repitió.

## Fachadas · tanda extra

Los 6 edificios de `data/buildings` (`armory`, `forge`, `house`, `carpentry`, `masonry` y `tailor_shop`) están en
`assets/art/buildings/fal/`: `<id>.png` (normal), `<id>_construction.png` (en obras) y `<id>_damaged.png` (dañada).
La sastrería ya no lleva el cartel «TAILOR», sino unas tijeras.

- **Mismo lienzo y ancla** que el sprite de escala B (`assets/art/buildings/escala_b/<id>.png`). Para usarla, en
  `game/visuals/buildings/<id>.tscn` se pone esta textura en el nodo `Sprite` y no se toca nada más (Feet, offset).
  Quedan aparte, y no en el sitio de las de escala B, porque cambiar el aspecto de un edificio lo decide la
  integración.
- **Cómo se hicieron** (`tools/art/fal_fachadas.py`):
  - La referencia única es el propio sprite de escala B, en un lienzo blanco de 256 ampliado ×4 (1024 exactos), y se
    pide redibujarlo en la misma posición.
  - image2pixel a escala 4.
  - Ajuste de ±8 px contra la silueta vieja: todas casan entre 0,83 y 1,00 y quedan desplazadas como mucho 1 px.
  - Las obras y la dañada salen de un /edit sobre la normal nueva. En las obras se quita también el blanco del
    fondo que queda entre las vigas.
- **Avisos.**
  - La cantería en obras deja parte de los andamios fuera del lienzo de 208 (287 px cortados en el borde).
  - La carpintería gana una base empedrada que antes no tenía.
- No hizo falta Pro.

## Pool de retratos (sexo × edad × tipo social)

566 retratos en `assets/art/portraits/<sexo>/<edad>/<tipo>/`, con su `index.json` y el contrato en
`assets/art/portraits/README.md` (formato del índice, fallback, cómo elegir con la semilla y teñir).

- Son 486 nuevos (6 por cada una de las 81 combinaciones) y los 80 de la primera tanda copiados.
- Se hicieron con `tools/art/fal_pool.py`, igual que los anteriores: rejillas 2×2, mapa de regiones por /edit y
  `fal_retratos_proc.build()`.
- `recolor` se calcula del PNG.
- `qa` marca los dudosos: salieron 35 y, revisados a ojo, eran sombreros rojos, manos y pieles de abrigo, no mapas
  rotos.
- Sus crudos e image2pixel (277 MB) están, como todos, en `~/Code/GuildMaster-arte-crudos/fal_produccion/pool/`.

## Rehacer

```bash
FAL_TANDA=produccion python3 tools/art/fal_retratos.py gen          # solo genera lo que falta
python3 tools/art/fal_retratos_proc.py                              # usa image2pixel en caché (i2p/)
FAL_TANDA=produccion python3 tools/art/fal_ilustraciones.py gen
FAL_TANDA=produccion python3 tools/art/fal_ilustraciones.py proc
python3 tools/art/fal_produccion_inventario.py                      # altas en el inventario
FAL_TANDA=extra python3 tools/art/fal_iconos.py gen && python3 tools/art/fal_iconos.py proc
FAL_TANDA=extra python3 tools/art/fal_fachadas.py gen [--estado construction|damaged]   # y proc
python3 tools/art/fal_produccion_galeria.py [--publicar]            # galería (no va a git)
/opt/homebrew/bin/godot --headless --path . --import && python3 tools/arte.py
```
