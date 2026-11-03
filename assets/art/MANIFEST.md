# Arte · gasto de créditos

Cada encargo que gaste apunta aquí el saldo **antes y después** (PixelLab: `get_balance`; fal: coste estimado).
Gratis: `pixelart_workbench`, `vfx_workbench`, `search_help`, `get_*`, `list_*`.
Ojo: con las generaciones del plan a 0, PixelLab cobra del crédito en $ antes que del regalo diario.
Plan: Tier 1, 2.000 generaciones/mes, se renueva el 15 de cada mes.

| Fecha | Encargo | Herramienta | Assets | Saldo antes | Saldo después | Gasto |
|---|---|---|---|---|---|---|
| 2026-11-01 | Láminas de concepto de ciudad (6) | fal Nano Banana Pro | `assets/concept/ciudades/` (en el repo guild) | — | — | 6 imágenes |
| 2026-11-01 | Instalación de PixelLab Pip: comprobación de saldo (sin generar) | `get_balance` | — | 0 gen. del plan · $0.00 · 4 de regalo hoy | igual | 0 |
| 2026-11-02 | Reuso de sprites de Guild Renew (rama arte-guild): edificios, puestos, suelo, puestos de la forja, props, iconos, bocadillos | Copia del repo `guild` (sin generar) | 53 assets, origen `guild-renew` (lista en `docs/arte/reuso_guild.md`) | — | — | 0 (reuso sin coste) |
| 2026-11-02 | Reuso de Guild Renew, 2ª tanda: casas de relleno, patios, tablón compuesto, props a escala, adoquín y tierra recoloreados, iconos de 16 px | Copia del repo `guild` + Pillow (`tools/art/derivar_guild.py`) | 2 casas, tablón, surcos, suelo de patio, 25 iconos pequeños; recoloreo de street/plaza/dirt; props a mitad | — | — | 0 (reuso sin coste) |
| 2026-11-02 | Arte 3ª tanda: suelo y paredes de forja y armería, árboles, río con orilla, puente, andamio, fachadas, iconos de 16 px | Pillow (`tools/art/dibujar_pixel.py`) + recortes del repo `guild` | interiores (2 kits), 3 árboles, agua + 4 orillas, puente + 4 bordillos, suelo bajo árboles, andamio, 2 zócalos, estandarte, 4 overlays a mitad, 2 iconos | — | — | 0 (sin créditos) |
| 2026-11-02 | Arte 4ª tanda: mejoras del interior de la forja, borde del mapa (bosque que se funde), casas recoloreadas | Pillow (`tools/art/dibujar_mejoras.py`, `derivar_guild.py houses`) + piezas del repo `guild` | 15 visuales de mejora, 2 casas (e, f) + 3 variantes de la casa de vecinos | — | — | 0 (sin créditos) |
| 2026-11-02 | Arte 5ª tanda: campos por estación y detalle de estanterías y mostrador | Pillow (`tools/art/dibujar_pixel.py fields`, `dibujar_mejoras.py`) | 5 tiles de campo, 2 muebles redibujados | — | — | 0 (sin créditos) |
| 2026-11-02 | Personajes de Guild Renew (familia, empleados, vecinos) con la identidad de H8 por shader; mesa de dados | Copia del repo `guild` + Pillow (`tools/art/personajes_guild.py`, `derivar_guild.py dice`) | 6 ids de personaje × 8 direcciones (idle, walk, work, forge, death; vecinos idle y walk), 1 prop | — | — | 0 (reuso sin coste) |
| 2026-11-02 | Tema de UI pixel art (marco, botones, campos, pergamino) y fuente Silkscreen | Pillow (`tools/art/dibujar_ui.py`) + fuente del repo `guild` (SIL OFL 1.1) | 7 piezas 9-patch, 1 fuente | — | — | 0 (sin créditos) |
| 2026-11-02 | Estudio de escala y ciudades (rama concepto-escala): tanda 1, iteración sobre maquetas grises a escala B | fal Nano Banana (`nano`, edit con referencia) | 6 imágenes, descartadas (pruebas) | tope del encargo 6 USD | — | 6 × 0,0398 = ~0,24 USD |
| 2026-11-02 | Estudio de escala y ciudades: tanda 2, láminas buenas (E, A, A+C, catedral, castillo, catálogo) | fal Nano Banana Pro 2K (edit con maqueta) | 6 imágenes → `assets/concept/ciudades2/` | — | — | 6 × 0,15 = 0,90 USD |
| 2026-11-02 | Estudio de escala y ciudades: tanda 3 (E amplia, kit de entramado, 3 kits de castillo; 2 descartados) | fal Nano Banana Pro 2K | 5 imágenes (3 buenas) | — | — | 5 × 0,15 = 0,75 USD |
| 2026-11-02 | Estudio de escala: consulta de límites de PixelLab, sin generar | `get_balance`, `search_help` | — | 0 gen. del plan (2.030/2.000 usadas, se renueva el 15-nov) | igual | 0 |
| 2026-11-02 | Kit de UI: pestañas, marcos de retrato y fuentes pixel libres (Pixel Operator CC0, Jacquarda Bastarda 9, Tiny5 y VT323 OFL) | Pillow (`tools/art/dibujar_ui.py`), fuentes descargadas de sus repos con su licencia al lado; `tools/ui/glifos_extra.py` añade → ← ↑ ↓ − a Pixel Operator | 5 piezas 9-patch, 4 fuentes | — | — | 0 (sin créditos) |
| 2026-11-02 | Kit de UI (2): pergamino, casilla, deslizador, scroll, separador, insignias de título y cargo, galones, sello de lacre y cursores | Pillow (`tools/art/dibujar_ui.py`) | 8 piezas, 17 marcas, 3 cursores | — | — | 0 (sin créditos) |
| 2026-11-02 | Logotipo «GuildMaster» y fuente Jacquard 24 (OFL) | Pillow (`tools/ui/logo.py`) | 1 logotipo, 1 fuente | — | — | 0 (sin créditos) |
| 2026-11-03 | H12 · oficios del Artesano (carpintero, albañil, sastre): fachadas derivadas, interiores, puestos, mejoras, iconos, 2 puestos de mercado | Pillow (`tools/art/oficios_h12.py`) + sprites del repo `guild` (solo lectura) | 3 fachadas, 3 kits de interior, 6 puestos, 18 visuales de mejora, 11 iconos (+16 px), 2 puestos de plaza; todo placeholder o derivado (`assets/inventario.json`, `para` H12) | — | — | 0 (sin créditos) |

## Lista de la compra · PixelLab (a partir del 15-nov)

Lo que H12 deja como placeholder (dibujado o derivado sin créditos). Por orden de prioridad; estilo y paso a paso en
`docs/protocolos/generar-arte-pixellab.md` y `pixellab-pip-style.json`. Ids y rutas, las del inventario.

| # | Asset | Id del inventario | Qué pedir | Por qué |
|---|---|---|---|---|
| 1 | Fachada de la carpintería (3×4) | `bld_carpentry` | Taller de madera con portalón, cartel de sierra sin texto, banco de carpintero y tablas en el patio, escala B | El granero de Guild Renew es demasiado ancho para la huella |
| 2 | Fachada de la cantería (3×4) | `bld_masonry` | Taller de piedra con cobertizo abierto, bloques y una grúa de mano, cartel sin texto | Hoy es una casa de relleno recoloreada: se confunde con las de los vecinos |
| 3 | Fachada de la sastrería (3×3) | `bld_tailor_shop` | La ropería de Guild Renew sin el cartel «TAILOR» (texto en inglés), con telar a la vista | El cartel en inglés |
| 4 | Puestos del oficio (6) | `int_carpentry`, `int_masonry`, `int_tailor_shop` | Caballete de serrar, banco de carpintero, banco de corte, banco de tallar, telar y mesa de costura; 80×72, base en (40, 56) | Cajas iso dibujadas |
| 5 | Kits de interior (3) | `int_*` | Suelo de tablas (carpintería), losas de cantera (cantería), tarima con alfombra (sastrería); paredes a juego | Hoy, el kit de la forja recoloreado (casi igual en los tres) |
| 6 | Mejoras de Producción y Calidad (18) | `int_*` | Una variante del puesto por nivel (sierra de bastidor, grúa, telar de pedal…), ver `game/visuals/interiors/<edificio>.tscn` Upgrades | Mesa + icono encima |
| 7 | Iconos de objetos (10) | `icon_chest` … `icon_statue`, `icon_saw` | 32×32 como los de la forja: arcón, armario, rueda de carro, sillar, piedra de afilar, abrevadero, muela, estatua, sierra | Dibujados a mano en Pillow |
| 8 | Puestos de la plaza (2) | `bld_stall_clothier`, `bld_stall_goods` | Puesto de ropería y puesto de enseres (muebles, barriles, piedra labrada), 64×64 | El de materiales recoloreado (todo, suelo incluido) |
| 9 | Animación de trabajo por oficio | `chr_artisan_m/f` (`work`) | Serrar, picar piedra, coser/tejer (hoy todos usan `work`) | Opcional: la forja tiene `forge` |
