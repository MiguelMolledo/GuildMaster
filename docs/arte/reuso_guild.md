# Reuso de sprites de Guild Renew

Catálogo de lo que hay en el repo anterior (`~/Code/guild`, `assets/sprites/`) y si sirve para sustituir greybox en
GuildMaster sin gastar créditos. Revisado contra `docs/style/biblia.md` (pixel art 16-bit, isométrico 2:1, diamante
64×32, contorno negro, paleta cálida, sin texto) y `docs/ASSETS.md`.

**Escala.** Guild Renew dibujaba los edificios de 192 px con escala 1,6 para 1920×1080. GuildMaster usa D2 (viewport
960×540 ×2 entero), así que todo va a **escala 1** (píxel entero, filtro Nearest). Un edificio de 192 px ocupa justo
el ancho de una huella de 3×3 (diamante de 192×96); la de 3×4 mide 224 px, y el sprite queda algo más estrecho que la
huella. Las escalas no enteras (1,17) se descartan: deforman el píxel.

**Ancla.** «Ancla» es el píxel del PNG que cae sobre el `Feet` de la escena (centro de la huella o de la casilla): el
centro del diamante de la base del dibujo. En la escena va como `Sprite2D` con `centered = false` y
`offset = -ancla`.

Veredictos: **usar** · **usar con ajuste** · **no sirve** · **catalogado** (personajes: no se integran aquí).

## Edificios del mapa

| Sprite de Guild Renew | Asset de GuildMaster | Encaja | Ajuste | Veredicto |
|---|---|---|---|---|
| `buildings/forge/exterior/building_forge_192.png` (192×192) | `bld_forge` → `buildings/forge.tscn` | 2:1, base de 184 px, paleta cálida, contorno | Escala 1, ancla (96, 139); `Top` a lo alto del tejado | **usar con ajuste** |
| `test_blacksmith_192.png` (192×192, raíz de sprites) | alternativa a `bld_forge` | 2:1, forja abierta con yunque (se lee mejor como herrería) | Ancla (96, 145) aprox.; era una prueba, no estaba en el inventario | alternativa (no se usa) |
| `buildings/forge/exterior/building_forge_ne.png`, `_sw.png` (64×64) | — | Miniaturas de 64 px de otras caras | — | **no sirve** (tamaño de icono) |
| `buildings/market/exterior/building_armeria_192.png` | `bld_armory` → `buildings/armory.tscn` | 2:1, tienda de piedra con escudos | Escala 1, ancla (96, 130) | **usar con ajuste** |
| `buildings/residential/house_modest_1/…_192.png` | `bld_house` → `buildings/house.tscn` (las 8 casas) | 2:1, entramado y teja de barro (estilo E de la biblia) | Escala 1, ancla (96, 141); base de 144 px dentro de la huella 3×3 | **usar con ajuste** |
| `house_modest_2_192.png` | `bld_house_a` | 2:1, con losa de piedra y macetas | Ancla (96, 136). Sin escena aún (casa de relleno) | **usar** (solo el PNG) |
| `house_modest_3_192.png` | `bld_house_b` | 2:1, dos plantas con balcón | Ancla (96, 142). Sin escena aún | **usar** (solo el PNG) |
| `house_humble_1`, `_2`, `_3_*`, `_4_*` (192) | variantes futuras de casa | 2:1, techo de paja; buen relleno de barrio pobre | Escala 1; base ~150 px | reserva |
| `house_humble_5_*` (192) | — | Dibujo pequeño (~100 px) con valla y parcela; escala distinta del resto | — | **no sirve** (escala) |
| `house_merchant_1` (192) | variante futura | 2:1, entramado rojo | — | reserva |
| `house_merchant_2` (192) | — | Lleva un cartel con letras | — | **no sirve** (texto en el sprite) |
| `house_noble_1`, `_2`, `house_tavern_style` (192) | variantes futuras (casa noble, taberna) | 2:1 | — | reserva |
| `market/exterior/building_alimentos_192`, `_materiales_`, `_recursos_` | — | Edificios enteros; en GuildMaster cada puesto es **una casilla** | — | **no sirve** (los puestos usan el de 64 px) |
| `market/exterior/building_roperia_192` | — | Cartel «TAILOR» | — | **no sirve** (texto) |
| `market/exterior/building_market_192`, `_boticario_192` | futuros (mercado cubierto, boticario) | 2:1 | — | reserva |
| `test_tavern_192`, `test_tavern_NE/NW/SW` | futura taberna | 2:1 | — | reserva |
| `buildings/common/shadow_short.png`, `shadow_long.png` | — | Sombra elíptica gris con antialias | — | **no sirve** (degradado, no es pixel art) |

## Puestos del mercado y tablón

| Sprite | Asset | Encaja | Ajuste | Veredicto |
|---|---|---|---|---|
| `market/interior/stall_alimentos.png` (64×64) | `bld_stall_food` → `props/stall_food.tscn` | Mesa iso de 1 casilla con comida | Ancla (32, 43) | **usar con ajuste** |
| `market/interior/stall_materiales.png` (64×64) | `bld_stall_materials` → `props/stall_materials.tscn` | Puesto con toldo rojo, 1 casilla | Ancla (32, 45) | **usar con ajuste** |
| `market/interior/stall_recursos.png` (64×64) | `bld_stall_resources` → `props/stall_resources.tscn` | Puesto con toldo de tela, 1 casilla | Ancla (32, 46) | **usar con ajuste** |
| `market/interior/stall_armeria`, `_boticario`, `_roperia` | — | Puestos de otros oficios | — | reserva |
| `market/exterior/building_market.png` (64×64) | — | Puesto rayado rojo/amarillo, muy saturado | — | reserva |
| (no hay) | tablón de encargos `props/board.tscn` | `props/sign_post.png` es un poste indicador, no un tablón | — | **no sirve**: sigue el greybox |
| (no hay) | árbol `props/tree.tscn`, bloque `props/building.tscn` | No hay árboles en Guild Renew; el bloque es por casilla | — | sigue el greybox |

## Suelo (tiles)

| Sprite | Asset | Encaja | Ajuste | Veredicto |
|---|---|---|---|---|
| `tiles/test_tiles_pro_diamond/tile_0.png` (64×32) | `tile_grass` → `tiles/grass.png` | Diamante exacto, hierba lisa que **casa sin costura** | Ninguno | **usar** |
| `tiles/test_tiles_pro_diamond/tile_1..15` | variantes de hierba (flores, piedras, barro) | Diamante exacto | Necesitaría variantes al azar en el suelo (no pedido) | reserva |
| `tiles/diamonds/grass_01..05_block.png` (64×32) | — | Diamante exacto, pero cada casilla tiene borde oscuro: el suelo se ve cuadriculado | — | **no sirve** (se nota la rejilla) |
| `tiles/tile_cobblestone_diamond.png` (64×32) | `tile_cobblestone` → `tiles/street.png` y `tiles/plaza.png` | Diamante exacto, adoquín; tono gris azulado frío | Ninguno; revisar el tono en captura | **usar con ajuste** |
| `tiles/diamonds/tile_dirt_block.png` (64×32) | `tile_dirt_path` → `tiles/dirt.png` | Diamante exacto, tierra rojiza con grietas en el borde | Revisar la rejilla en captura | **usar con ajuste** |
| `tiles/placeholders/*.png` (64×32) | — | Diamantes de color plano: lo mismo que el greybox | — | **no sirve** |
| `tiles/*_block.png`, `tile_grass.png`, `tile_dirt.png`, `tile_cobblestone.png` (64×64) | — | Bloques con lateral de tierra (cubo), no suelo plano | — | **no sirve** (forma) |
| `tiles/stone_floor_flat/*`, `tiles/test_tiles_pro/*` (64×64) | — | Diamante 1:1, no 2:1 | — | **no sirve** (perspectiva) |
| `test_tiles_iso/*` (64×64) | — | Losas con grosor y flores, muy pequeñas | — | **no sirve** |
| `tiles/diamonds/stones.png`, `test.png`, `test30Grades.png` | — | Tiras de prueba | — | **no sirve** |
| `buildings/*/tile_interior_stone.png` (32×32) | suelo del interior | Losa de 32 px | No es 64×32 | **no sirve**: el suelo del interior sigue el greybox |

## Interior de la forja (estaciones)

Las estaciones se ven desde la cámara fija del interior: se usa la vista por defecto (sin sufijo), que mira al frente.
Las variantes `_ne`, `_nw`, `_se`, `_sw` quedan de reserva.

| Sprite | Asset | Encaja | Ajuste | Veredicto |
|---|---|---|---|---|
| `forge/interior/workzone_horno.png` (64×64) | puesto `furnace` → `stations/furnace.tscn` (y `furnace_2`) | Horno de ladrillo con fuego, 1 casilla | Ancla (32, 50) | **usar con ajuste** |
| `forge/interior/workzone_yunque.png` (64×64) | puesto `anvil` → `stations/anvil.tscn` (y `anvil_2`) | Yunque sobre tocón | Ancla (32, 48) | **usar con ajuste** |
| `forge/interior/workzone_almacen.png` (64×64) | puesto `storage` → `stations/storage.tscn` | Pila de cajas | Ancla (32, 44) | **usar con ajuste** |
| `props/counter_sales.png` (80×64) | puesto `counter` → `stations/counter.tscn` (forja y armería) | Mostrador con estante sobre tarima de madera | Ancla (40, 46) | **usar con ajuste** |
| `forge/interior/workzone_puerta*.png` (64×64) | puerta del kit | Puerta frontal en arco | El kit dibuja la puerta en la pared por código; no hay paredes de Guild Renew | **no sirve** todavía |
| `forge/interior/fal_test/horno_*_fal.png` (1024×1024) | — | Concepto de fal | — | **no sirve** (concepto) |
| (no hay) | paredes y suelo del interior (`int_forge`) | — | — | sigue el greybox |

## Visuales de mejoras (fachada y extras)

| Sprite | Asset | Encaja | Veredicto |
|---|---|---|---|
| `buildings/overlays/shop_sign.png` (64×64) | `upgrade_trade_sign` (forja) | Letrero colgante vacío, sin texto | reserva (la posición del greybox no casa con el sprite del edificio: se ajusta a mano) |
| `buildings/overlays/lock_reinforced.png` (48×48) | `upgrade_reinforced_lock` | Cerrojo plano, no iso | reserva |
| `buildings/overlays/garden_plants.png` (96×48) | `upgrade_garden` | Setos de lado, no iso | reserva |
| `buildings/overlays/facade_stone.png` (96×96) | `upgrade_stone_facade` | Óvalo de piedra, no es una fachada | **no sirve** |
| `buildings/overlays/facade_noble.png` (96×96) | `upgrade_noble_facade` | Fachada frontal, no isométrica | **no sirve** (perspectiva) |
| `props/scaffolding.png` (96×96) | `prop_scaffolding` / nodo `Works` | 2:1, andamio sobre una losa de 2×2 casillas | reserva (el andamio greybox rodea toda la huella) |

## Props

En GuildMaster solo se dibujan como prop los tipos de casilla con escena (`tree`, `building`, `board`, puestos); no
hay casillas de barril, pozo ni carro. Los PNG se traen a su ruta para tenerlos listos, sin escena.

| Sprite | Asset | Encaja | Veredicto |
|---|---|---|---|
| `props/barrel/barrel_64.png` (64×64) | `prop_barrel` | 2:1, contorno | **usar** (solo el PNG) |
| `props/bench/bench_64.png` (64×48) | `prop_bench` | 2:1 | **usar** (solo el PNG) |
| `props/cart/cart_96.png` (96×64) | `prop_cart` | 2:1 | **usar** (solo el PNG) |
| `props/grain_sack/grain_sack_48.png` (48×48) | `prop_grain_sack` | Saco frontal | **usar** (solo el PNG) |
| `props/well/well_96.png` (96×96) | `prop_well` | 2:1 con base de hierba | **usar** (solo el PNG) |
| `props/anvil.png` (64×64) | `prop_anvil` | 2:1 sobre peana | **usar** (solo el PNG) |
| `props/crate.png` (48×48) | `prop_crate` | 2:1 | **usar** (solo el PNG) |
| `props/torch.png` (32×64) | `prop_torch` | Antorcha de pared | **usar** (solo el PNG) |
| `props/sign_post.png` (64×64) | `prop_sign_post` | Poste indicador | **usar** (solo el PNG) |
| `props/scaffolding.png` | `prop_scaffolding` | ver mejoras | **usar** (solo el PNG) |
| `props/barrel.png`, `cart.png`, `well.png` (versiones viejas) | — | Las de subcarpeta son las buenas | **no sirve** (duplicado) |
| `props/counter_sales.png` | estación `counter` | ver interior | **usar con ajuste** |
| `props/dining_table`, `dormitory_bed`, `safe_box`, `hidden_passage` | — | 2:1; para casas y secretos (no hay asset aún) | reserva |
| `lights/light_gradient_64.png` | — | Degradado radial | **no sirve** (degradado; la luz es por código) |

## Iconos (32×32)

Hay dos juegos: `assets/sprites/icons/` (sombreado y contorno negro, de la biblia) y `ui/icons/` (planos, sin
contorno). Se usa el primero. Ojo: hoy la UI de GuildMaster **no pinta iconos de objeto** (`VisualPaths.icon` no lo
llama nadie); los PNG quedan en su ruta para cuando la UI los pida.

| Guild Renew (`icons/`) | Asset | Veredicto |
|---|---|---|
| `icon_hierro` | `icon_iron` | **usar** |
| `icon_carbon` | `icon_coal` | **usar** |
| `icon_madera` | `icon_wood` | **usar** |
| `icon_piedra` | `icon_stone` | **usar** |
| `icon_trigo` | `icon_wheat` | **usar** |
| `icon_lana` | `icon_wool` | **usar** |
| `icon_hierbas` | `icon_herbs` | **usar** |
| `icon_lingote_hierro` | `icon_iron_ingot` | **usar** |
| `icon_lingote` | `icon_steel` | **no sirve**: es igual que el lingote de hierro |
| `icon_harina` | `icon_flour` | **usar** |
| `icon_tablas` | `icon_planks` | **usar** |
| `icon_tela` | `icon_cloth` | **usar con ajuste**: parece un pergamino (se confunde con documento) |
| `icon_espada` | `icon_sword` | **usar** |
| `icon_pan` | `icon_bread` | **usar** |
| `icon_ropa_comun` | `icon_common_clothes` | **usar** |
| `icon_armadura` | `icon_armor` | **usar** |
| `icon_martillo` | `icon_hammer` | **usar** |
| `icon_sierra` | `icon_saw` | **no sirve**: es solo un mango (la de `ui/icons` es plana, sin contorno) |
| `icon_aguja` | `icon_needle` | **usar** |
| `icon_azadon` | `icon_hoe` | **usar con ajuste**: se lee como un pico |
| `icon_ropa_trabajo` | `icon_work_clothes` | **usar** |
| `icon_capa_viaje` | `icon_travel_cloak` | **usar** |
| `icon_vendas` | `icon_bandages` | **usar** |
| `icon_comida_preparada` | `icon_prepared_meal` | **usar** |
| `icon_documento` | `icon_document` | **usar** |
| `icon_llave` | `icon_key` | **usar** |
| `icon_contrato` | `icon_contract` | **usar** |
| `icon_oro`, `icon_cerveza`, `icon_carne`, `icon_pocion`, `icon_libro`, `icon_backpack`, `icon_herramienta`, `icon_profesion_herrero` | sin objeto en `data/items/` | reserva |

## UI

| Sprite | Asset | Veredicto |
|---|---|---|
| `ui/icons/bubble_chat`, `_dice`, `_rest`, `_shop`, `_think`, `_wave` (32×32) | `bubble_*` (`assets/art/ui/bubbles/<x>.png`) | **usar** (solo el PNG: el juego aún no pinta bocadillos) |
| `ui/frames/frame_wood_panel.png` (256×256), `frame_dark_panel`, `frame_tooltip`, `frame_button_*` | `ui_panel_frame` | **usar con ajuste** más adelante: requiere montar un 9-patch en `greybox_theme.tres`, y la UI la tocan otros hitos. No se integra aquí |
| `ui/icons/icon_rama_*` (8) | ramas del árbol de mejoras | reserva (la UI de mejoras usa colores) |
| `ui/icons/icon_idle`, `icon_working`, `icon_warning`, `state_*`, `icon_sun`, `icon_moon`… | marcas de estado | reserva (las marcas se dibujan por código en `data/view.json`) |
| `ui/parcels/parcel_*` (64×32) | — | Diamantes de color semitransparente | **no sirve** (lo hace el código) |
| `ui/radial/icon_entrar`, `_examinar`, `_gestionar` | — | No hay menú radial | reserva |

## Personajes y NPC (solo catálogo)

No se integran en esta rama: H7 y H8 están cambiando los personajes. Todos son de PixelLab (vista *low top-down*,
8 direcciones: `south`, `south-east`, `east`, `north-east`, `north`, `north-west`, `west`, `south-west`), en lienzo
de 68×68 con la figura de ~48 px (niños: lienzo 48×48, figura de ~34 px). Cada carpeta tiene `rotations/<dir>.png`,
`animations/<anim>/<dir>/frame_NNN.png` y `metadata.json` con el id de PixelLab.

| Carpeta (Guild Renew) | Quién | Alto | Animaciones (fotogramas por dirección) | Asset que podría cubrir |
|---|---|---|---|---|
| `characters/artesano` | artesano | 48 px | idle 4 · walk 8 · work 5 · forge 6 · death 7 | `chr_artisan_m` (faltan carry, talk, sit) |
| `characters/artesana` | artesana | 52 px | idle 5 · walk 6 · work 8 · forge 4 · death 7 | `chr_artisan_f` (ídem) |
| `characters/patron`, `patrona` | patrón/a | 49 px | idle 4 · walk 5-6 · work 5-6 · forge 8 · death 7 | clase futura |
| `characters/erudito` | erudito | 49 px | idle 4 · walk 6 · work 5 · forge 8 · death 7 | clase futura |
| `characters/erudita`, `picaro`, `picara` | — | 46-47 px | solo rotaciones | clase futura |
| `npcs/aldeano_hombre` | aldeano | 48 px | idle 4 · walk 6 | `npc_townsfolk_m` (faltan talk, sit) |
| `npcs/aldeana_mujer` | aldeana | 48 px | idle 4 · walk 6 | `npc_townsfolk_f` (ídem) |
| `npcs/mercader` | mercader | 49 px | `animating-*` 4 (idle) · `walking-*` 6 | vendedor del mercado |
| `npcs/nino_generico`, `nina_generica` | niños | 34 px | `animating-*` 4 · `walking-*` 6 | niños (H futuro) |
| `ui/portraits/portrait_*.png` (192×192) y `family/*` (64×64) | retratos | — | — | `retrato` (64×64): recortes de la rotación sur |

Para traerlos: hoja por animación y dirección con `make_sheet.py` (protocolo de PixelLab, «Promover al juego»),
renombrar direcciones al contrato (`s se e ne n nw w sw`) y ajustar el pie (centro inferior de la figura, no del
lienzo de 68 px). No hay `npc_worker_*`: los empleados podrían salir del artesano con otra paleta.

## Lo que no hay en Guild Renew

Árboles, tablón de encargos, paredes y suelo del interior, andamio que cubra la huella, variantes de obras y dañado de
los edificios, `icon_steel`, `icon_saw`, VFX (chispas, humo) y el 9-patch ya montado. Todo eso sigue en greybox.

## Integración (fase 2) y revisión (fase 3)

- **Cómo está montado.** En cada escena de `game/visuals/` hay un nodo `Sprite` (Sprite2D, `centered = false`,
  `offset = -ancla`, filtro Nearest) junto al `Greybox`, que queda **oculto, no borrado**. Volver al greybox en el
  editor: ocultar `Sprite`, mostrar `Greybox` y devolver `Top` al valor que dice el `editor_description` del Sprite.
- **Top.** Edificios: de 40 a 72 px (el letrero queda sobre el tejado). La zona de clic es el prisma de la huella con
  esa altura: con más de ~76 px tapa la calle que hay detrás de la forja, por eso no llega a lo alto del dibujo.
  Puestos del mercado: 32-45 px; puestos de la forja: 38-47 px (barra, marcas y clic sobre el dibujo).
- **Suelo.** `GroundLayer` pinta `assets/art/tiles/<tipo>.png` si existe (`VisualPaths.tile`) y, si no, el color de
  `data/tiles.json`. Con textura: hierba, calle, plaza y tierra. Campo, puente y agua siguen en color.
- **Toque de maestro.** `StationView` teñía el bloque greybox; con el greybox oculto tiñe el sprite (modulate).
- **Revisado en captura** (galería, rebanada completa): mapa, forja por dentro, mercado y armería. Ningún asset quedó
  peor que el greybox. Avisos:
  - Los bloques de relleno `#` del mapa (`props/building.tscn`) siguen en greybox y, cuando están delante, tapan la
    base de los sprites (orden correcto, pero se ve el contraste).
  - El adoquín es gris azulado, más frío que la paleta base; la tierra tiene borde marcado y se nota algo la rejilla.
  - Todas las casas son la misma (`house_modest_1`): hay variantes en reserva cuando haya escena por variante.
  - El andamio de obras (`Works`) y las mejoras exteriores siguen en greybox, colocados para el bloque de 40 px.
- Capturas: `docs/novedades/arte_guild_*_antes.png` / `_despues.png`.

## Segunda tanda (manzanas, tablón, decoración, recoloreo)

Todo lo derivado sale de `tools/art/derivar_guild.py` (Pillow, sobre copias; el repo `guild` no se toca).

| Qué | De dónde | Cómo |
|---|---|---|
| Casas de las manzanas (`props/lot_house_a..d`) | `house_modest_2`, `house_modest_3`, `house_merchant_1`, `house_humble_4_south` | Escala 1, una por solar de 3×4/4×3/3×3; la mitad en espejo |
| Patios (`props/yard_*`) | barriles, cajas, sacos, carro, surcos (`test_tiles_pro_diamond/tile_15`) | Temas por manzana (huerto / patio), cada patio con props una vez por manzana |
| Suelo de patio (`tiles/building.png`) | `test_tiles_pro_diamond/tile_12` | Tal cual |
| Props a escala (`barrel`, `crate`, `grain_sack`, `cart`, `bench`, `well`) | los de 64-96 px | Reducción 2:1 de pixel art (conserva el contorno, sin colores nuevos) |
| Tablón (`props/board.png`) | marco de `overlays/shop_sign` + poste de `props/sign_post` | Compuesto, con cuatro notas clavadas dibujadas a mano |
| Adoquín (`street`, `plaza`) | `tile_cobblestone_diamond` | Tono a gris piedra cálido (h≈32-38°, menos saturación); la plaza, más clara |
| Tierra (`dirt`) | `diamonds/tile_dirt_block` | De rosada a marrón; las grietas oscuras del borde se igualan al tono base (sin rejilla) |
| Iconos pequeños (`icons/small/<id>.png`) | los iconos de 32 | Reducción 2:1; en las filas del almacén y del inventario |

Pendiente: árboles, puente y agua siguen en greybox; las variantes de hierba (`tile_1..11`) podrían salpicar el suelo.

## Tercera tanda (interiores, naturaleza, obras, fachadas)

Lo dibujado sale de `tools/art/dibujar_pixel.py` (Pillow, paleta de la biblia, contorno oscuro, luz de arriba a la
izquierda). Sin créditos. `--preview DIR` deja una hoja ampliada para revisar.

| Qué | Cómo | Dónde |
|---|---|---|
| Suelo de la forja | `stone_floor_flat/tile_4` (diamante 1:1) aplastado a 2:1 | grupo *Art* del `Kit` de `interiors/forge.tscn` |
| Suelo de la armería | `stone_floor_flat/tile_11` aplastado y templado | `interiors/armory.tscn` |
| Paredes | Dibujadas por segmento (32 px, 36 de alto): sillares (forja) y yeso con entramado (armería), viga arriba; variante con puerta | `KitWall.texture` |
| Árboles | Roble, árbol redondo y pino dibujados; suelo de hierba con sombra bajo la copa | `props/tree*.tscn`, `prop_variants.tree` |
| Río | Agua con ondas + orilla (tierra, arena, espuma) en los lados que tocan otra casilla | `tiles/water*.png`, `ground_edges` |
| Puente | Tablones cruzados a la calle + bordillo hacia el agua | `tiles/bridge*.png` |
| Andamio de obras | Postes, tablones, riostras y escalera sobre la base del sprite | `Works/Scaffold` en `buildings/forge.tscn` |
| Fachada de piedra / noble | Zócalo de sillares (claro y con estandartes en la noble) | `Upgrades/upgrade_*_facade` |
| Jardín, escaparate, letrero, cerradura | `overlays/garden_plants`, `stall_armeria`, `shop_sign`, `lock_reinforced` a mitad | `Upgrades/upgrade_*` |
| Iconos espada y aguja (16 px) | Redibujados píxel a píxel | `icons/small/` |

Sigue en greybox: la guardia contratada (es un personaje), los visuales de mejoras del interior y los campos.

## Cuarta tanda (mejoras del interior, borde del mapa, más casas)

| Qué | Cómo | Dónde |
|---|---|---|
| Fuelle, tina de temple, pila de temple, banco de grabado, sello de maestro, libro doble, estanterías, mostrador de venta | Dibujados con cajas isométricas (`tools/art/dibujar_mejoras.py`) | `Upgrades/<nodo>/Sprite` de `interiors/forge.tscn` |
| Forja de maestro, pasadizo oculto, caja fuerte, literas, comedor, banco de maestro, alijo | `workzone_horno_sw`, `hidden_passage`, `safe_box`, `dormitory_bed`, `dining_table`, `anvil` de guild; el alijo con cajas, barril y saco del pueblo | ídem |
| Borde del mapa | Anillo de 9 casillas fuera de la rejilla: hierba que se oscurece hacia el fondo (con algo de ruido para que no salgan franjas), calles y río que siguen hacia fuera, bosque que se espesa | `map_border` en `data/view.json`; `GroundLayer` + `WorldView._add_border_trees` |
| Casas `house_e` y `house_f` | Recoloreo de `house_a` (pizarra + encalado) y `house_c` (barro marrón + ocre) | solares `lot_house_e/f`; vecinos `buildings/house_slate`, `house_ochre`, `house_tall` (`building_variants`) |

Los segundos puestos (`anvil_2`, `furnace_2`) ya salían con su sprite (son la escena del puesto).

## Quinta tanda (campos por estación, detalle de muebles)

| Qué | Cómo | Dónde |
|---|---|---|
| Campos (casillas `f`) | Surcos de 8 px que casan de casilla a casilla; primavera brotes, verano surcos verdes, otoño trigo dorado, invierno tierra con escarcha (`dibujar_pixel.py fields`) | `seasonal_tiles` en `data/view.json`; `GroundLayer.set_season`, que `WorldView` llama con la estación del reloj |
| Estanterías (forge_capacity_2) | Abiertas hacia delante: fondo de tablas, lateral, tres baldas con lingotes, tarros, cuerda, martillo, bolsa y libro | `upg_shelves.png` |
| Mostrador de venta (forge_commerce_1) | Paneles hundidos, esquinas de hierro; encima tela, monedas, espada y balanza | `upg_counter.png` |
