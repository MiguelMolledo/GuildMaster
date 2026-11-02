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
| 2026-11-02 | Kit de UI: pestañas, marcos de retrato y fuentes pixel libres (Pixel Operator CC0, Jacquarda Bastarda 9, Tiny5 y VT323 OFL) | Pillow (`tools/art/dibujar_ui.py`), fuentes descargadas de sus repos con su licencia al lado; `tools/ui/glifos_extra.py` añade → ← ↑ ↓ − a Pixel Operator | 5 piezas 9-patch, 4 fuentes | — | — | 0 (sin créditos) |
